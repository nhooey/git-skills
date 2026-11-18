(ns pr-body.commits-test
  (:require [babashka.fs :as fs]
            [babashka.process :as p]
            [clojure.string :as str]
            [clojure.test :refer [deftest is]]
            [pr-body.commits :as commits]))

(def ^:private git-env
  {"GIT_AUTHOR_NAME" "T" "GIT_AUTHOR_EMAIL" "t@example.com"
   "GIT_COMMITTER_NAME" "T" "GIT_COMMITTER_EMAIL" "t@example.com"
   "GIT_CONFIG_GLOBAL" "/dev/null" "GIT_CONFIG_NOSYSTEM" "1"})

(defn- read-back
  "The commit of `message`, made in a throwaway repository and read back."
  [message]
  (let [dir (str (fs/create-temp-dir {:prefix "pr-body-commits"}))]
    (try
      (p/sh {:dir dir :extra-env git-env} "git" "init" "--quiet")
      (let [sha (str/trim (:out (p/sh {:dir dir :in message :extra-env git-env}
                                      "git" "commit-tree" "--no-gpg-sign" "-F" "-"
                                      "4b825dc642cb6eb9a060e54bf8d69288fbee4904")))]
        (dissoc (commits/read-commit dir sha) :sha :subject-md :body-md))
      (finally (fs/delete-tree dir)))))

(deftest git-splits-the-message
  (is (= {:parents [] :subject "Subject wrapped" :body "Body one\nline.\n\nTwo."
          :raw-body "Body one\nline.\n\nTwo.\n\nFixes: #1\n  more\nCo-authored-by: A <a@x>"
          :trailers [{:key "Fixes" :value "#1 more"} {:key "Co-authored-by" :value "A <a@x>"}]}
         (read-back "Subject\nwrapped\n\nBody one\nline.\n\nTwo.\n\nFixes: #1\n  more\nCo-authored-by: A <a@x>\n")))
  (is (= {:parents [] :subject "Only" :body "" :raw-body "" :trailers []} (read-back "Only\n")))
  (is (= "" (:body (read-back "Second change\n\nMulti-commit: refactor-split\n")))))
