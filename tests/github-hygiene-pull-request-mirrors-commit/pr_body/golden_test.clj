(ns pr-body.golden-test
  "Golden files: each `golden/<case>/input.edn` renders to its
  `expected.txt`, as the `render` mode prints it. A case with a `:live`
  pull request also records what `sync` decides about it.

  `input.edn` holds `:repo` (`{:owner :name}`, on github.com), `:opts`
  and `:commits`. Each commit's raw `:message` is committed into a
  throwaway repository and read back through `pr-body.commits`, so the
  golden files cover git's splitting of the message too, and its
  `:trailers` are what `git interpret-trailers --parse` prints for it,
  which `trailers-from-git` checks. `bb golden` rewrites every
  `expected.txt`; read its diff before committing it."
  (:require [babashka.fs :as fs]
            [babashka.process :as p]
            [clojure.edn :as edn]
            [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [pr-body.commits :as commits]
            [pr-body.render :as render]
            [pr-body.sync :as sync]))

(def golden-dir "golden")

(def ^:private empty-tree "4b825dc642cb6eb9a060e54bf8d69288fbee4904")

(def ^:private git-env
  {"GIT_AUTHOR_NAME" "Golden" "GIT_AUTHOR_EMAIL" "golden@example.com"
   "GIT_COMMITTER_NAME" "Golden" "GIT_COMMITTER_EMAIL" "golden@example.com"
   "GIT_CONFIG_GLOBAL" "/dev/null" "GIT_CONFIG_NOSYSTEM" "1"})

(defn- with-repo
  "`(f dir)` in a fresh repository, deleted after."
  [f]
  (let [dir (str (fs/create-temp-dir {:prefix "pr-body-golden"}))]
    (try
      (p/sh {:dir dir :extra-env git-env} "git" "init" "--quiet")
      (f dir)
      (finally (fs/delete-tree dir)))))

(defn- commit
  "The fixture commit `c` as `pr-body.commits` reads it from git, with
  the fixture's SHA and parents."
  [dir {:keys [sha parents message]}]
  (let [made (str/trim (:out (p/sh {:dir dir :in message :extra-env git-env}
                                   "git" "commit-tree" "--no-gpg-sign" "-F" "-" empty-tree)))]
    (assoc (commits/read-commit dir made) :sha sha :parents (or parents []))))

(defn- sync-report [{:keys [live]} rendered commits]
  (let [{:keys [action status]} (sync/plan live rendered commits nil)]
    (str "--- sync: " (name action) (when status (str " (" (name status) ")")) " ---\n"
         (when (= action :refuse)
           (str (sync/refusal {:label "PR #7 (octo/widgets)" :live live :rendered rendered :status status
                               :save-command (sync/save-command "octo/widgets" 7)})
                "\n")))))

(defn- github [{:keys [owner name] :as repo}]
  (assoc repo :url (str "https://github.com/" owner "/" name)))

(defn output
  "What a case renders to."
  [{:keys [repo opts] :as case}]
  (with-repo
    (fn [dir]
      (let [commits (mapv #(commit dir %) (:commits case))
            rendered (render/render commits (github repo) opts)]
        (str (:title rendered) "\n\n" (:body rendered) "\n"
             (when (seq (:warnings rendered))
               (str "--- warnings ---\n" (str/join "\n" (:warnings rendered)) "\n"))
             (when (:live case) (sync-report case rendered commits)))))))

(defn cases []
  (for [dir (sort (map str (fs/list-dir golden-dir)))
        :when (fs/exists? (fs/path dir "input.edn"))]
    {:name (str (fs/file-name dir))
     :input (edn/read-string (slurp (str (fs/path dir "input.edn"))))
     :expected (str (fs/path dir "expected.txt"))}))

(deftest golden
  (doseq [{:keys [name input expected]} (cases)]
    (testing name
      (is (fs/exists? expected) (str expected " is missing: run bb golden"))
      (when (fs/exists? expected)
        (is (= (slurp expected) (output input)))))))

(deftest trailers-from-git
  (doseq [{:keys [name input]} (cases)]
    (testing name
      (with-repo
        (fn [dir]
          (doseq [c (:commits input)]
            (is (= (:trailers c)
                   (apply str (for [{:keys [key value]} (:trailers (commit dir c))]
                                (str key ": " value "\n")))))))))))

(defn write-all []
  (doseq [{:keys [name input expected]} (cases)]
    (spit expected (output input))
    (println "wrote" name)))
