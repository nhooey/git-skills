(ns pr-body.diff
  "A line diff of two texts, compared byte for byte by `git diff
  --no-index`."
  (:require [babashka.fs :as fs]
            [babashka.process :as p]
            [clojure.string :as str]))

(defn- unified
  "`git diff`'s output for files holding `a` and `b`, with no context."
  [a b]
  (let [dir (fs/create-temp-dir {:prefix "pr-body-diff"})
        [fa fb] (map #(str (fs/path dir %)) ["a" "b"])]
    (try
      ;; A newline after each text makes git's lines those of
      ;; splitting the text at every newline, a last empty one included.
      (spit fa (str a "\n"))
      (spit fb (str b "\n"))
      (:out (p/sh {:continue true}
                  "git" "diff" "--no-index" "--no-color" "--no-ext-diff" "--diff-algorithm=myers"
                  "--unified=0" fa fb))
      (finally (fs/delete-tree dir)))))

(defn changes
  "The lines that differ, `-` from `a` and `+` from `b`, in order."
  [a b]
  (->> (str/split-lines (unified (or a "") (or b "")))
       (drop-while #(not (str/starts-with? % "@@")))
       (filter #(or (str/starts-with? % "-") (str/starts-with? % "+")))
       vec))

(defn summary
  "The first `n` changed lines, with a count of the ones left out."
  [a b n]
  (let [lines (changes a b)]
    (str/join "\n" (concat (take n lines)
                           (when (> (count lines) n)
                             [(str "… " (- (count lines) n) " more changed lines")])))))
