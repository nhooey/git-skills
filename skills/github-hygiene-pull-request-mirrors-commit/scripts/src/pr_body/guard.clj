(ns pr-body.guard
  "The PreToolUse guard: denies a Bash command that writes a pull
  request's title or body by hand, through `gh pr create`, `gh pr edit`
  or `gh api` on a `pulls` endpoint, so every title and body comes from
  the commits through `create-or-update-pull-request.sh`.

  The hook sees only the command line the agent runs. The program's own
  `gh api` calls run inside its Babashka process and never reach the
  hook, so they need no marker an agent could also type.

  The command is parsed by `shfmt --to-json` into its syntax tree, and
  every simple command in it is read, inside a pipeline, a list, a
  subshell or a command substitution alike, so a commit message, a
  comment or a quoted here-document that only mentions `gh pr create
  --fill` passes. A command that doesn't parse runs nothing, and passes.

  It also denies retargeting a pull request onto a branch other than
  the default one (`gh pr edit --base`, or `gh api` with a `base`
  field), pointing at `gh stack link`: such a pull request belongs in a
  linked stack.

  `- Write guard: deny|remind|off` in the skill's preferences file turns
  it down: `remind` lets the command run and adds the message as
  context, `off` says nothing."
  (:require [babashka.process :as p]
            [cheshire.core :as json]
            [clojure.string :as str]
            [clojure.tools.cli :as cli]
            [pr-body.preferences :as preferences]))

;; Compromise: plan node write-clojure-shell-parser-library

(defn- syntax-tree
  "The syntax tree `shfmt --to-json` gives for the Bash command line `s`,
  or nil when it doesn't parse."
  [s]
  (let [r (p/sh {:in s :continue true} "shfmt" "--to-json")]
    (when (zero? (:exit r)) (json/parse-string (:out r)))))

(defn- part-text
  "A word part's text with its quotes removed; an expansion, known only
  when the command runs, as `$`."
  [part]
  (case (get part "Type")
    ("Lit" "SglQuoted") (get part "Value")
    "DblQuoted" (apply str (map part-text (get part "Parts")))
    "$"))

(defn- word-text [word] (apply str (map part-text (get word "Parts"))))

(defn commands
  "The simple commands in the shell command line `s`, each a vector of
  its words with quotes removed, wherever they sit in its syntax tree."
  [s]
  (->> (syntax-tree s)
       (tree-seq coll? #(if (map? %) (vals %) %))
       (filter #(and (map? %) (= "CallExpr" (get % "Type"))))
       (map #(mapv word-text (get % "Args")))
       (filter seq)))

(def ^:private prefixes #{"env" "command" "exec" "nohup" "time" "sudo" "builtin" "noglob"})

(defn- basename [w] (last (str/split w #"/")))

(defn- program-words
  "`words` from the program on: leading assignments and wrappers such as
  `env` and `command` (with their options) dropped."
  [words]
  (loop [ws words]
    (let [w (first ws)]
      (cond
        (nil? w) []
        (re-matches #"[A-Za-z_][A-Za-z0-9_]*=.*" w) (recur (rest ws))
        (prefixes (basename w)) (recur (drop-while #(str/starts-with? % "-") (rest ws)))
        :else (vec ws)))))

;; gh's flags, from `gh pr create|edit --help` and `gh api --help`, as
;; `short/long` names: those that take a value, then those that don't.
(defn- flag-spec [valued switches]
  (letfn [(row [value? flag]
            (let [[short long] (str/split flag #"/")]
              (cond-> [(when (seq short) (str "-" short)) (str "--" long (when value? " VALUE"))]
                value? (into [:multi true :update-fn (fnil conj [])]))))]
    (into (mapv #(row true %) (str/split valued #" ")) (map #(row false %) (str/split switches #" ")))))

(def ^:private gh-flags
  {["pr" "create"] (flag-spec "a/assignee B/base b/body F/body-file H/head l/label m/milestone p/project /recover r/reviewer R/repo T/template t/title"
                              "d/draft /dry-run e/editor f/fill /fill-first /fill-verbose /no-maintainer-edit w/web")
   ["pr" "edit"] (flag-spec "/add-assignee /add-label /add-project /add-reviewer B/base b/body F/body-file m/milestone /remove-assignee /remove-label /remove-project /remove-reviewer R/repo t/title"
                            "/remove-milestone")
   ["api"] (flag-spec "/cache F/field H/header /hostname /input q/jq X/method p/preview f/raw-field t/template"
                      "i/include /paginate /silent /slurp /verbose")})

(defn- gh-call
  "`{:options {flag value-or-values} :arguments [word]}` for the words
  after `gh pr create`, `gh pr edit` or `gh api`, read by `gh`'s flags."
  [command words]
  (cli/parse-opts words (gh-flags command)))

(defn- api-write
  "`{:fields {k v} :input? b}` for a `gh api` POST, PATCH or PUT to a
  `pulls` endpoint, or nil."
  [words]
  (let [{{:keys [method field raw-field input]} :options [path] :arguments} (gh-call ["api"] words)
        fields (concat raw-field field)
        method (str/upper-case (or (last method) (if (or (seq fields) input) "POST" "GET")))]
    (when (and path
               (re-matches #"/?repos/[^/]+/[^/]+/pulls(/[0-9]+)?/?" path)
               (#{"POST" "PATCH" "PUT"} method))
      {:fields (into {} (map #(str/split % #"=" 2) fields)) :input? (some? input)})))

(defn- gh-denial
  "What's wrong with the words after `gh`: `{:what s}` for a written
  title or body, `{:what s :base b}` for a retarget, or nil."
  [default? [a b & more :as words]]
  (let [pr (when (and (= a "pr") (#{"create" "edit"} b)) (:options (gh-call [a b] more)))
        api (when (= a "api") (api-write (rest words)))
        base (if api (get-in api [:fields "base"]) (when (= b "edit") (last (:base pr))))]
    (cond
      (some #(get pr %) [:body :body-file :title :fill :fill-first :fill-verbose]) {:what (str "gh pr " b)}
      (and api (or (:input? api) (some (:fields api) ["title" "body"]))) {:what "gh api"}
      (and base (not (default? base))) {:what (if api "gh api" "gh pr edit") :base base})))

(defn- denied-command
  "What's wrong with one simple command, `{:what s}` for a title or body
  and `{:what s :base b}` for a retarget, or nil. `default?` tells the
  default branch."
  [default? words]
  (let [[program & args] (program-words words)]
    (case (some-> program basename)
      "gh" (gh-denial default? args)
      ("bash" "sh" "zsh") (let [script (second (drop-while #(not= "-c" %) args))]
                            (when script (some #(denied-command default? %) (commands script))))
      "eval" (some #(denied-command default? %) (commands (str/join " " args)))
      nil)))

(defn- default-predicate
  "Whether a branch is the default one: `default` when it's known, else
  main or master."
  [default]
  (if default #(= default %) #{"main" "master"}))

(defn denial
  "Why `command-line` is denied, or nil when it may run. `script` is the
  path of `create-or-update-pull-request.sh` to name; `default` the
  repository's default branch, when known."
  ([command-line script] (denial command-line script nil))
  ([command-line script default]
   (when-let [{:keys [what base]} (some #(denied-command (default-predicate default) %)
                                        (commands (or command-line "")))]
     (str/join
      "\n"
      (if base
        [(str "Blocked " what " retargeting a pull request onto " base ": a pull request based on a branch "
              "other than the default one belongs in a linked GitHub stack, since merging the top of a linked "
              "stack merges the whole stack into the default branch, while a pull request merely based on "
              base " merges only into " base ".")
         "Link the chain instead, bottom to top, by branch or pull request number; it sets each base to the one below:"
         "  gh stack link <bottom> … <top>"
         (str "or push and run bash " script " sync, which links the branch's chain of open pull requests.")]
        [(str "Blocked " what ": a pull request's title and body come from its commits, "
              "never written by hand or by gh pr create --fill, which copies trailers and "
              "keeps the 72-column wrap that GitHub renders as line breaks.")
         "Push the branch, then open or re-sync the pull request with create-or-update-pull-request.sh from github-hygiene-pull-request-mirrors-commit:"
         (str "  bash " script " render   # preview the title and body")
         (str "  bash " script " sync [--base <branch>] [--draft]")
         "To change the title or body, amend the commit message and sync again."])))))

(def skill "github-hygiene-pull-request-mirrors-commit")

(defn mode
  "`:deny`, `:remind` or `:off` from the preferences `texts`, the
  user's before the project's: the last `Write guard:` item wins."
  [texts]
  (preferences/choice texts "write guard" ["deny" "remind" "off"] :deny))

(defn hook-output
  "The PreToolUse hook's stdout for the JSON `payload` under `mode`, or
  nil to say nothing. `default` is the repository's default branch, or
  nil."
  [payload script mode default]
  (let [command-line (get-in (json/parse-string payload) ["tool_input" "command"])
        reason (when (not= mode :off) (denial command-line script default))]
    (when reason
      (json/generate-string
       {:hookSpecificOutput
        (if (= mode :remind)
          {:hookEventName "PreToolUse" :additionalContext reason}
          {:hookEventName "PreToolUse"
           :permissionDecision "deny"
           :permissionDecisionReason reason})}))))

(defn- default-branch
  "The default branch of the repository at the payload's `cwd`, from its
  `origin/HEAD`, or nil."
  [payload]
  (let [cwd (or (get (json/parse-string payload) "cwd") ".")
        prefix "refs/remotes/origin/"
        r (p/sh {:continue true :dir cwd} "git" "symbolic-ref" "--quiet" (str prefix "HEAD"))
        target (str/trim (:out r))]
    (when (and (zero? (:exit r)) (str/starts-with? target prefix))
      (subs target (count prefix)))))

(defn -main [& [script]]
  (try
    (let [payload (slurp *in*)]
      (some-> (hook-output payload (or script "create-or-update-pull-request.sh")
                           (mode (preferences/texts skill (get (json/parse-string payload) "cwd")))
                           (when (re-find #"--base|-B|base=" payload) (default-branch payload)))
              println))
    (catch Exception _ nil)))
