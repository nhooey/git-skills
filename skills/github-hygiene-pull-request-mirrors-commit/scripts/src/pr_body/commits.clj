(ns pr-body.commits
  "Commits read from git, which splits each message into its subject,
  body and trailers itself, with the subject and body parsed as Markdown."
  (:require [babashka.process :as p]
            [clojure.string :as str]
            [pr-body.markdown :as md]))

(def ^:private fields
  "The `git log` format of one commit: its SHA, parents, subject, body,
  trailer block as written, and trailers as `key\\x1fvalue` pairs parted
  by `\\x1e`, each field ended by a NUL."
  (str/join "%x00" ["%H" "%P" "%s" "%b" "%(trailers)"
                    "%(trailers:only,unfold,separator=%x1e,key_value_separator=%x1f)"
                    ""]))

(defn- git
  "The output of `git args` in the repository at `dir`, or an exception."
  [dir & args]
  (let [r (apply p/sh {:dir dir :continue true} "git" args)]
    (if (zero? (:exit r))
      (:out r)
      (throw (ex-info (str "git " (str/join " " args) " failed: " (str/trim (:err r))) {:exit 2})))))

(defn- without-suffix [s suffix]
  (if (and (seq suffix) (str/ends-with? s suffix)) (subs s 0 (- (count s) (count suffix))) s))

(defn read-commit
  "`{:sha :parents :subject :body :raw-body :trailers :subject-md
  :body-md}` for commit `rev` of the repository at `dir`. `:raw-body` is
  everything after the subject, as `%b` gives it; `:body` is that
  without the trailer block git finds at its end."
  [dir rev]
  (let [[sha parents subject raw-body block trailers]
        (str/split (git dir "log" "--max-count=1" (str "--format=" fields) rev) #"\x00")
        body (str/trimr (without-suffix raw-body block))]
    {:sha sha
     :parents (vec (remove str/blank? (str/split parents #" ")))
     :subject subject
     :body body
     :raw-body (str/trimr raw-body)
     :trailers (vec (for [t (str/split trailers #"\x1e")
                          :when (seq t)
                          :let [[k v] (str/split t #"\x1f" 2)]]
                      {:key k :value (or v "")}))
     :subject-md (md/parse subject)
     :body-md (md/parse body)}))

(defn read-range
  "The commits in `range` of the repository at `dir`, oldest first."
  [dir range]
  (mapv #(read-commit dir %) (str/split-lines (git dir "rev-list" "--reverse" range))))
