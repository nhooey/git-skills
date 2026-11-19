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
    - `:line-counts` `{[sha path] lines}` for the files code references name;
    - `:issue-titles` `{number title}` for the bare `#N` references."
  (:require [clojure.string :as str]
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
  :issues #{n}}`, from the lead commit's subject and body, which are all
  the title and body show."
  [commits opts]
  (let [lead (lead-commit commits opts)
        found (map links/scan [(:subject-md lead) (:body-md lead)])]
    {:paths (set (for [p (mapcat :paths found)] [(:sha lead) p]))
     :issues (set (mapcat :issues found))}))

(defn- warnings [commits opts]
  (vec (for [n (sort (:issues (lookups commits opts)))
             :when (nil? (get (:issue-titles opts) n))]
         (str "#" n " names no issue or pull request with a title in this repository"))))

(defn render
  "`{:title :body :warnings}` for `commits` in `repo`."
  [commits repo opts]
  (let [lead (lead-commit commits opts)
        above (str/join "\n\n"
                        (remove str/blank?
                                [(rendered-body lead repo opts)
                                 (str/join "\n" (message/kept-trailers commits (:trailers opts :drop)))]))]
    {:title (:subject lead)
     :body (footer/assemble above (:sha (last commits)) (:attribution opts))
     :warnings (warnings commits opts)}))
