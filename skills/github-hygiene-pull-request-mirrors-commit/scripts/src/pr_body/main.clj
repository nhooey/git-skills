(ns pr-body.main
  "The shell around the core: reads the commits and the facts the render
  needs from git and gh, prints, and exits. Everything it decides is
  decided in `pr-body.render`, `pr-body.message`, `pr-body.sync` and
  `pr-body.stack`."
  (:require [babashka.fs :as fs]
            [babashka.process :as p]
            [cheshire.core :as json]
            [clojure.string :as str]
            [pr-body.cli :as cli]
            [pr-body.commits :as commits]
            [pr-body.footer :as footer]
            [pr-body.message :as message]
            [pr-body.preferences :as preferences]
            [pr-body.prose :as prose]
            [pr-body.render :as render]
            [pr-body.stack :as stack]
            [pr-body.sync :as sync]))

;; --- processes --------------------------------------------------------

(defn- run
  "Runs a command, `{:exit :out :err}`; `in` is its stdin."
  ([cmd] (run cmd nil))
  ([cmd in]
   (try
     (apply p/sh (cond-> {:continue true} in (assoc :in in)) cmd)
     (catch java.io.IOException e {:exit 127 :out "" :err (.getMessage e)}))))

(defn- out [cmd] (let [r (run cmd)] (when (zero? (:exit r)) (str/trim-newline (:out r)))))

(defn- git [& args] (out (into ["git"] args)))

(defn- gh-json
  "Parsed JSON from a `gh` command, or nil when it fails or prints nothing."
  ([args] (gh-json args nil))
  ([args in]
   (let [r (run (into ["gh"] args) in)]
     (when (and (zero? (:exit r)) (not (str/blank? (:out r))))
       (json/parse-string (:out r))))))

(defn- say [quiet? & parts] (when-not quiet? (println (apply str parts))))
(defn- warn [quiet? & parts] (when-not quiet? (binding [*out* *err*] (println (apply str parts)))))

(defn- fail
  "Ends the run with `code` after `message` on stderr."
  [code message]
  (throw (ex-info message {:exit code})))

;; --- facts from git ---------------------------------------------------

(defn- repo-of
  "`{:owner :name :url :default}` for `--repo`, or for the repository
  `gh` resolves from the remotes, as `gh repo view` reads them."
  [opts]
  (let [r (run (concat ["gh" "repo" "view"] (when (:repo opts) [(:repo opts)])
                       ["--json" "owner,name,url,defaultBranchRef"]))
        repo (when (zero? (:exit r)) (json/parse-string (:out r)))]
    (if (get repo "name")
      {:owner (get-in repo ["owner" "login"]) :name (get repo "name") :url (get repo "url")
       :default (get-in repo ["defaultBranchRef" "name"])}
      (fail 2 (str "can't tell the repository (gh repo view: " (str/trim (str (:err r)))
                   "): pass --repo <owner/repo>")))))

(defn- ref-exists? [ref] (some? (git "rev-parse" "--verify" "--quiet" (str ref "^{commit}"))))

(defn- local-or-remote [branch]
  (cond (ref-exists? (str "refs/heads/" branch)) (str "refs/heads/" branch)
        (ref-exists? (str "refs/remotes/origin/" branch)) (str "refs/remotes/origin/" branch)
        (ref-exists? branch) branch))

(defn- base-ref [base]
  (cond (ref-exists? (str "refs/remotes/origin/" base)) (str "refs/remotes/origin/" base)
        (ref-exists? base) base))

(defn- line-count [sha path]
  (when (zero? (:exit (run ["git" "cat-file" "-e" (str sha ":" path)])))
    (some-> (git "cat-file" "-p" (str sha ":" path)) str/split-lines count)))

(defn- flake-locks [from to]
  (vec (for [path (str/split (or (git "diff" "-z" "--name-only" from to) "") #"\x00")
             :when (= "flake.lock" (fs/file-name path))
             :let [read (fn [rev] (some-> (git "show" (str rev ":" path)) json/parse-string))]]
         {:path path :old (read from) :new (read to)})))

;; --- facts from GitHub ------------------------------------------------

(def ^:private pr-fields "number,url,title,body,baseRefName,headRefOid")

(defn- open-pr [slug head]
  (gh-json ["pr" "list" "--repo" slug "--head" head "--state" "open"
            "--json" pr-fields "--jq" ".[0] // empty"]))

(defn- pr-by-number [slug n]
  (or (gh-json ["pr" "view" (str n) "--repo" slug "--json" (str pr-fields ",headRefName")])
      (fail 2 (str "no pull request #" n " in " slug))))

(defn- fetch-pr!
  "Fetches pull request `n`'s head, and its base when there's no
  remote-tracking branch for it, into the local object store. Writes
  only local refs: FETCH_HEAD and `refs/remotes/origin/<base>`."
  [n head-sha base]
  (when-not (ref-exists? head-sha)
    (run ["git" "fetch" "--quiet" "origin" (str "refs/pull/" n "/head")]))
  (when-not (base-ref base)
    (run ["git" "fetch" "--quiet" "origin" (str "+refs/heads/" base ":refs/remotes/origin/" base)]))
  (when-not (ref-exists? head-sha)
    (fail 2 (str "can't fetch pull request #" n "'s head " head-sha " from origin"))))

(defn- stack-parent [slug opts base default]
  (let [pr (cond (:stack-parent opts)
                 (gh-json ["pr" "view" (str (:stack-parent opts)) "--repo" slug "--json" "number,title"])
                 (and base default (not= base default))
                 (gh-json ["pr" "list" "--repo" slug "--head" base "--state" "open"
                           "--json" "number,title" "--jq" ".[0] // empty"]))]
    (cond pr {:number (get pr "number") :title (get pr "title")}
          (:stack-parent opts) {:number (:stack-parent opts)})))

(defn- open-prs
  "The repository's open pull requests, as `{:number :head :base}`."
  [slug]
  (mapv (fn [pr] {:number (get pr "number") :head (get pr "headRefName") :base (get pr "baseRefName")})
        (gh-json ["pr" "list" "--repo" slug "--state" "open" "--limit" "1000"
                  "--json" "number,headRefName,baseRefName"])))

(defn- stacks
  "The repository's stacks, from `GET repos/{owner}/{repo}/stacks`."
  [slug]
  (let [r (run ["gh" "api" "--paginate" (str "repos/" slug "/stacks") "--jq" ".[]"])]
    (if (zero? (:exit r))
      (vec (json/parsed-seq (java.io.StringReader. (:out r))))
      (fail 1 (str "can't read " slug "'s stacks: " (str/trim (:err r)))))))

(defn- stack-verdict
  "`pr-body.stack/verdict` for pull request `number` based on `base`,
  from a fresh read of the open pull requests and stacks."
  [slug number base default]
  (when (and number base default (not= base default))
    (stack/verdict {:prs (open-prs slug) :stacks (stacks slug)
                    :number number :base base :default default})))

(defn- link-stack!
  "Links the chain `verdict` names into a GitHub stack; 0, or 1 when it
  can't."
  [slug verdict quiet?]
  (if-not (:command verdict)
    (do (say quiet? (:message verdict)) 1)
    (let [r (try
              (apply p/sh {:continue true :extra-env {"GH_REPO" slug}}
                     "gh" "stack" "link" (map str (:numbers verdict)))
              (catch java.io.IOException e {:exit 127 :err (.getMessage e)}))]
      (if (zero? (:exit r))
        (do (say quiet? "linked stack: " (str/join " " (map #(str "#" %) (:numbers verdict)))) 0)
        (do (say quiet? "couldn't link the stack (" (str/trim (str (:err r) (:out r))) "); run it yourself:\n  "
                 (:command verdict))
            1)))))

(defn- issue-title [slug n]
  (get (gh-json ["api" (str "repos/" slug "/issues/" n)]) "title"))

;; --- preferences ------------------------------------------------------

(def ^:private policy-skill "github-hygiene-single-commit-pull-requests")
(def ^:private own-skill "github-hygiene-pull-request-mirrors-commit")

(defn- preference-texts [skill]
  (preferences/texts skill (git "rev-parse" "--show-toplevel")))

;; --- the run ----------------------------------------------------------

(defn- gather
  "Everything the modes need: the repository, branches, open pull
  request, commits and the render."
  [mode opts]
  (let [repo (repo-of opts)
        slug (str (:owner repo) "/" (:name repo))
        default (:default repo)
        by-number (some->> (:pr opts) (pr-by-number slug))
        head (or (get by-number "headRefName") (:head opts) (git "symbolic-ref" "--short" "--quiet" "HEAD"))
        _ (when (and (nil? head) (not= mode "render"))
            (fail 2 "HEAD is detached: pass --head <branch>"))
        pr (or by-number
               (when (and head (or (not= mode "render") (not (or (:base opts) (:range opts)))))
                 (open-pr slug head)))
        base (or (:base opts) (get pr "baseRefName") default
                 (fail 2 "can't tell the base branch: pass --base <branch>"))
        _ (when by-number (fetch-pr! (:pr opts) (get by-number "headRefOid") base))
        head-ref (cond by-number (get by-number "headRefOid")
                       (:head opts) (or (local-or-remote head) (fail 2 (str "no branch " head)))
                       :else "HEAD")
        range (or (:range opts)
                  (let [b (or (base-ref base) (fail 2 (str "no branch " base " to diff against")))]
                    (str (or (git "merge-base" b head-ref) (fail 2 (str "no merge base of " base " and " head)))
                         ".." head-ref)))
        [from to] (str/split range #"\.\.")
        commits (commits/read-range "." range)
        _ (when (empty? commits) (fail 2 (str "no commits in " range)))
        problems (message/range-problems commits)
        _ (when (seq problems) (fail 2 (str/join "\n" (cons (str "refusing the range " range ":") problems))))
        render-opts {:lead (:lead opts)
                     :trailers (or (:trailers opts) :drop)
                     :verbatim? (:verbatim opts)
                     :attribution (cond (:no-footer opts) nil
                                        (:footer opts) (:footer opts)
                                        :else footer/default-attribution)}
        wanted (render/lookups commits render-opts)
        facts {:line-counts (into {} (for [[sha path :as k] (:paths wanted)] [k (line-count sha path)]))
               :issue-titles (into {} (for [n (:issues wanted)] [n (issue-title slug n)]))
               :flake-locks (flake-locks from to)
               :stack-parent (stack-parent slug opts base default)}]
    {:slug slug :repo repo :head head :base base :default default :pr pr :commits commits
     :rendered (render/render commits (select-keys repo [:owner :name :url]) (merge render-opts facts))}))

(defn- label [slug pr] (str "PR #" (get pr "number") " (" slug ")"))

(defn- live [pr] (when pr {:title (get pr "title") :body (or (get pr "body") "")}))

(defn- enforce-policy!
  "Exits 4, or warns, when the range breaks the single-commit policy."
  [{:keys [commits base]} opts]
  (let [verdict (message/multi-commit-verdict commits (message/policy (preference-texts policy-skill)) base)]
    (case (:level verdict)
      :refuse (do (warn (:quiet opts) (:message verdict)) (fail 4 nil))
      :warn (warn (:quiet opts) (:message verdict))
      nil)))

(defn- warn-prose-lists!
  "Warns about each sentence in the commits' bodies that lists three or
  more items, unless the preferences turn it off, and about each
  paragraph of a multi-commit synthesis that repeats a commit's body.
  Never changes the exit code."
  [commits opts]
  (when (= :warn (prose/warning-mode (preference-texts own-skill)))
    (doseq [w (prose/warnings commits)] (warn (:quiet opts) "warning: " w)))
  (doseq [w (prose/repetition-warnings commits (render/lead-commit commits {:lead (:lead opts)}))]
    (warn (:quiet opts) "warning: " w)))

(defn- check! [{:keys [slug head base default pr rendered commits]} opts]
  (warn-prose-lists! commits opts)
  (if (nil? pr)
    (do (say (:quiet opts) "no open pull request for " head) 0)
    (let [in-sync (sync/in-sync? (live pr) rendered)
          unstacked (stack-verdict slug (get pr "number") base default)]
      (when-not in-sync
        (say (:quiet opts) (sync/drift-report (label slug pr) (live pr) rendered
                                               (sync/status (:body (live pr)) commits))))
      (when unstacked (say (:quiet opts) (:message unstacked)))
      (if (or (not in-sync) unstacked)
        1
        (do (say (:quiet opts) "in sync: " (get pr "url")) 0)))))

(defn- write-pr! [slug method path payload]
  (or (gh-json ["api" "--method" method path "--input" "-"] (json/generate-string payload))
      (fail 1 (str "gh api --method " method " " path " failed"))))

(defn- then-stack
  "`code`, or when it's 0 and pull request `number` needs linking into a
  stack, the outcome of linking it."
  [code slug number base default quiet?]
  (if-let [v (and (zero? code) (stack-verdict slug number base default))]
    (link-stack! slug v quiet?)
    code))

(defn- sync! [{:keys [slug head base default pr rendered commits]} opts]
  (let [{:keys [action status]} (sync/plan (live pr) rendered (:force opts) commits)
        quiet? (:quiet opts)]
    (when (and pr (not= (get pr "headRefOid") (:sha (last commits))))
      (warn quiet? "the pull request's head is " (get pr "headRefOid")
            ", not the rendered " (:sha (last commits)) ": push the branch"))
    (case action
      :none (do (say quiet? "in sync: " (get pr "url"))
                (then-stack 0 slug (get pr "number") base default quiet?))
      :refuse (do (say quiet? (sync/refusal (label slug pr) (live pr) rendered status)) 3)
      (let [written (if (= action :create)
                      (write-pr! slug "POST" (str "repos/" slug "/pulls")
                                 (cond-> {:title (:title rendered) :body (:body rendered)
                                          :head head :base base}
                                   (:draft opts) (assoc :draft true)))
                      (write-pr! slug "PATCH" (str "repos/" slug "/pulls/" (get pr "number"))
                                 {:title (:title rendered) :body (:body rendered)}))
            number (get written "number")
            back (gh-json ["api" (str "repos/" slug "/pulls/" number)])
            url (or (get back "html_url") (get written "html_url"))]
        (if (and back (sync/in-sync? {:title (get back "title") :body (or (get back "body") "")} rendered))
          (do (say quiet? (if (= action :create) "created " "synced ") url)
              (then-stack 0 slug number base default quiet?))
          (do (say quiet? (sync/drift-report (str "PR #" number " (" slug ") as read back")
                                             {:title (get back "title") :body (or (get back "body") "")}
                                             rendered nil))
              1))))))

(defn- run-mode [{:keys [mode opts]}]
  (let [{:keys [rendered] :as ctx} (gather mode opts)]
    (doseq [w (:warnings rendered)] (warn (:quiet opts) "warning: " w))
    ;; render too: a body for a range the policy refuses would mislead.
    (enforce-policy! ctx opts)
    (case mode
      "render" (do (println (:title rendered)) (println) (println (:body rendered)) 0)
      "check" (check! ctx opts)
      "sync" (sync! ctx opts))))

(defn -main [& args]
  (let [parsed (cli/parse args)
        code (cond
               (:help parsed) (do (println cli/usage) 0)
               (:error parsed) (do (warn false (:error parsed) " (try --help)") 2)
               :else (try (run-mode parsed)
                          (catch clojure.lang.ExceptionInfo e
                            (when-let [m (ex-message e)] (warn false m))
                            (or (:exit (ex-data e)) 1))))]
    (System/exit code)))
