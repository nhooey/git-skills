(ns pr-body.cli
  "The command line of `create-or-update-pull-request.sh`: its spec,
  parsed by `babashka.cli`, and its help."
  (:require [babashka.cli :as cli]))

(def spec
  {:base {:ref "<branch>" :coerce :string
          :desc "base branch (default: the open PR's base, else the repository's default branch)"}
   :head {:ref "<branch>" :coerce :string :desc "head branch (default: the current branch)"}
   :repo {:ref "<owner/repo>" :coerce :string
          :desc "repository (default: the one `gh repo view` resolves from the remotes)"}
   :pr {:ref "<N>" :coerce :long
        :desc (str "an existing pull request: its head commits (fetched from origin when missing) and "
                   "base, in place of --head and --base; `check --pr N` compares its live title and "
                   "body with the render and writes nothing to GitHub")}
   :range {:ref "<a>..<b>" :coerce :string
           :validate {:pred #(boolean (re-matches #"[^.\s]+\.\.[^.\s]+" %))
                      :ex-msg #(str "--range takes <a>..<b>, not " (:value %))}
           :desc "commits to render (default: merge-base(base, head)..head)"}
   :lead {:ref "<sha>" :coerce :string :desc "commit whose subject is the title (default: the first commit)"}
   :stack-parent {:ref "<N>" :coerce :long
                  :desc (str "pull request this one stacks on (default: the base branch's open pull "
                             "request, when the base isn't the default branch)")}
   :trailers {:ref "keep|drop" :coerce :keyword
              :validate {:pred #{:keep :drop}
                         :ex-msg #(str "--trailers takes keep or drop, not " (name (:value %)))}
              :desc (str "keep every trailer, each once, or (default) drop them all: the footer is the "
                         "body's one attribution line, and the commits keep their trailers")}
   :footer {:ref "<text>" :coerce :string
            :desc "last line of the body (default: the Claude Code \"Generated with\" line)"}
   :no-footer {:coerce :boolean :desc "no attribution line; the invisible pr-body marker stays"}
   :draft {:coerce :boolean :desc "open a new pull request as a draft"}
   :force {:coerce :boolean :desc "sync over a body edited by hand"}
   :verbatim {:coerce :boolean :desc "skip the unwrapping of commit bodies"}
   :quiet {:coerce :boolean :desc "print nothing; the exit code tells"}
   :help {:alias :h :coerce :boolean :desc "show this help"}})

(def ^:private order
  [:base :head :repo :pr :range :lead :stack-parent :trailers :footer :no-footer
   :draft :force :verbatim :quiet :help])

(def usage
  (str "Usage: create-or-update-pull-request.sh [render|sync|check] [options]

Builds a pull request's title and body from its commits, the same way
every time, and keeps the open pull request in line with them.

Modes:
  render   print the title, a blank line and the body
  sync     (default) create the pull request, or PATCH the open one, then
           read it back and verify it
  check    report drift between the open pull request and the render,
           byte for byte, with the first 8 lines of the diff

Options:
" (cli/format-opts {:spec spec :order order}) "

One commit: its subject is the title, and the body is its unwrapped body
and the footer. Several commits: the subject and body of the lead commit,
the one carrying the `Multi-commit:` trailer, then a \"Commits (N)\" list
of each commit's linked SHA and subject, then the footer. A changed
flake.lock adds a \"What changes\" section.

`check` also warns, without changing its exit code, about a sentence
listing three or more comma-separated items (`- Prose list warning: off`
in the skill's preferences silences it), and about a paragraph of a
multi-commit synthesis that repeats another commit's body.

Several commits need an allowed reason: under the
github-hygiene-single-commit-pull-requests preferences (`Multiple commits:
refuse|warn|allow`, `Allowed reasons: ...`), one commit's
`Multi-commit: <reason>` trailer names it.

A live body with no pr-body marker counts as edited by hand, unless it's
what the old create-or-update-pull-request.sh or `gh pr create --fill`
wrote from these commits (compared with whitespace normalised): then
`check` says it's safe to re-sync and `sync` overwrites it.

A pull request based on a branch other than the default one belongs in a
linked GitHub stack: `check` counts one outside a stack as drift and names
the `gh stack link` command, and `sync` runs it, bottom to top.

Exit codes:
  0  in sync, synced, or rendered
  1  drift or no stack (check), or the synced pull request didn't read
     back as sent or couldn't be linked into its stack
  2  usage error, or a range holding fixup!, squash! or merge commits
  3  the body was edited by hand, so the sync was refused
  4  several commits without an allowed Multi-commit reason

Example:
  create-or-update-pull-request.sh check --quiet || create-or-update-pull-request.sh sync
"))

(def ^:private modes #{"render" "sync" "check"})

(defn- message
  "The usage error for a `babashka.cli` error."
  [{:keys [cause option value msg]}]
  (let [flag (str "--" (name option))]
    (case cause
      :restrict (str "unknown option: " flag)
      :coerce (if (#{"true" true} value)
                (str flag " needs a value")
                (case option
                  (:pr :stack-parent) (str flag " takes a pull request number, not " value)
                  msg))
      msg)))

(defn- conflicts [opts]
  (cond
    (and (:pr opts) (:head opts)) "--pr and --head can't be used together"
    (and (:footer opts) (:no-footer opts)) "--footer and --no-footer can't be used together"))

(defn parse
  "`{:mode m :opts {...}}`, `{:help true}` or `{:error message}` for
  `args`: a mode first, if any, then options."
  [args]
  (let [{:keys [cmds args]} (cli/parse-cmds args)
        [mode & extra] cmds]
    (try
      (let [{:keys [opts] more :args}
            (cli/parse-args args {:spec spec :restrict true
                                  :error-fn #(throw (ex-info (message %) {:usage true}))})
            stray (first (concat extra more))]
        (cond
          (:help opts) {:help true}
          (and mode (not (modes mode))) {:error (str "unknown mode: " mode " (render, sync or check)")}
          stray {:error (str "unexpected argument: " stray)}
          (conflicts opts) {:error (conflicts opts)}
          :else {:mode (or mode "sync") :opts opts}))
      (catch clojure.lang.ExceptionInfo e
        (if (:usage (ex-data e)) {:error (ex-message e)} (throw e))))))
