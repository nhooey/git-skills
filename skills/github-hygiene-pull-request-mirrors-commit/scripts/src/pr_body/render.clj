(ns pr-body.render
  "The pure core: a pull request's title and body from its commits.

  `(render commits repo opts)` does no I/O. Everything it would look up
  arrives in `opts`, gathered by the shell from what `lookups` asks for:

  - `commits`: oldest first, each `{:sha :parents :subject :body
    :trailers :subject-md :body-md}`, as `pr-body.commits/read-commit`
    gives them, the last two the subject and body as
    `pr-body.markdown/parse` gives them;
  - `repo`: `{:owner :name :url}`;
  - `opts`:
    - `:lead` the SHA whose subject is the title (default the commit
      carrying `Multi-commit:`, else the first);
    - `:trailers` `:keep` or `:drop`;
    - `:attribution` the footer's last line, or nil for none;
    - `:verbatim?` skip the unwrapping;
    - `:stack-parent` `{:number :title}` of the pull request this one stacks on;
    - `:line-counts` `{[sha path] lines}` for the files code references name;
    - `:issue-titles` `{number title}` for the bare `#N` references;
    - `:flake-locks` `[{:path :old :new}]`, each lock's parsed JSON."
  (:require [clojure.string :as str]
            [pr-body.flake-lock :as flake-lock]
            [pr-body.footer :as footer]
            [pr-body.links :as links]
            [pr-body.message :as message]))

(defn- link-ctx [commit repo opts]
  {:repo repo :sha (:sha commit) :line-counts (:line-counts opts)})

(defn- rendered-body [commit repo opts]
  (links/render (link-ctx commit repo opts) (:body-md commit) (not (:verbatim? opts))))

(defn lead-commit
  "The commit whose subject is the title and whose body is the summary:
  the one `:lead` names, else the one carrying the `Multi-commit:`
  trailer, else the first."
  [commits opts]
  (or (some #(when (and (:lead opts) (str/starts-with? (:sha %) (:lead opts))) %) commits)
      (message/multi-commit-lead commits)
      (first commits)))

(defn lookups
  "What the shell has to look up before `render`: `{:paths #{[sha path]}
  :issues #{n}}`, from the lead commit's body and every subject, which
  is all the body shows."
  [commits opts]
  (reduce (fn [acc commit]
            (let [lead? (= commit (lead-commit commits opts))
                  found (map links/scan (cons (:subject-md commit) (when lead? [(:body-md commit)])))]
              (-> acc
                  (update :paths into (for [p (mapcat :paths found)] [(:sha commit) p]))
                  (update :issues into (mapcat :issues found)))))
          {:paths #{} :issues #{}}
          commits))

(defn- commit-item
  "One commit as its linked short SHA and subject. Its message stays in
  the commit, one click away, rather than copied into the body."
  [commit repo opts]
  (let [sha (:sha commit)]
    (str "- [`" (subs sha 0 7) "`](" (:url repo) "/commit/" sha ") "
         (links/render (link-ctx commit repo opts) (:subject-md commit) false))))

(defn- commits-section [commits repo opts]
  (str "## Commits (" (count commits) ")\n\n"
       (str/join "\n" (map #(commit-item % repo opts) commits))))

(defn- stack-line [repo {:keys [number title]}]
  (str "Stacks on " (:owner repo) "/" (:name repo) "#" number (when title (str " \"" title "\""))))

(defn- warnings [commits opts]
  (vec (for [n (sort (:issues (lookups commits opts)))
             :when (nil? (get (:issue-titles opts) n))]
         (str "#" n " names no issue or pull request with a title in this repository"))))

(defn render
  "`{:title :body :warnings}` for `commits` in `repo`."
  [commits repo opts]
  (let [lead (lead-commit commits opts)
        single? (= 1 (count commits))
        above (str/join "\n\n"
                        (remove str/blank?
                                [(rendered-body lead repo opts)
                                 (when-not single? (commits-section commits repo opts))
                                 (flake-lock/section (:flake-locks opts))
                                 (some->> (:stack-parent opts) (stack-line repo))
                                 (str/join "\n" (message/kept-trailers commits (:trailers opts :drop)))]))]
    {:title (:subject lead)
     :body (footer/assemble above (:sha (last commits)) (:attribution opts))
     :warnings (warnings commits opts)}))
