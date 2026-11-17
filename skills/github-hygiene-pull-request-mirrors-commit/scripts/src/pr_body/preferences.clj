(ns pr-body.preferences
  "Skills' preferences files, Markdown lists of `- Key: value` items,
  parsed with `pr-body.markdown`, so that bold keys and values in code
  spans read the same as plain ones."
  (:require [babashka.fs :as fs]
            [clojure.string :as str]
            [pr-body.markdown :as md]))

(defn texts
  "The texts of `skill`'s preferences files that exist: the one beside
  the installed skill, the user's, then the project's, which is under
  `CLAUDE_PROJECT_DIR` or else `project-dir`."
  [skill project-dir]
  (let [file (str skill ".preferences.md")
        scripts-dir (some-> (System/getProperty "babashka.config") fs/parent)
        config-dir (or (System/getenv "CLAUDE_CONFIG_DIR") (str (fs/home) "/.claude"))
        project-dir (or (System/getenv "CLAUDE_PROJECT_DIR") project-dir)]
    (->> [(some-> scripts-dir (fs/path ".." ".." file))
          (fs/path config-dir "skills" file)
          (some-> project-dir (fs/path ".agents" "skills" file))]
         (remove nil?)
         (map #(str (fs/normalize %)))
         distinct
         (filter fs/regular-file?)
         (mapv slurp))))

(defn settings
  "`{key value}` from a preferences file's `text`: each list item's first
  paragraph as plain text, parted at its first colon, the key in lower
  case."
  [text]
  (into {}
        (for [item (md/of-type (md/parse text) :item)
              :let [para (first (filter #(= :paragraph (:type %)) (:children item)))
                    s (some-> para md/plain str/trim)
                    i (some-> s (str/index-of ":"))]
              :when i]
          [(str/lower-case (str/trim (subs s 0 i))) (str/trim (subs s (inc i)))])))

(defn choice
  "The last value of `key` among `texts`, the user's file before the
  project's, that is one of `allowed` in any case, as a keyword, or
  `default`."
  [texts key allowed default]
  (or (->> texts
           (keep #(some-> (get (settings %) key) str/lower-case))
           (filter (set allowed))
           last
           keyword)
      default))

(defn value
  "The last value of `key` among `texts`, or nil."
  [texts key]
  (last (keep #(get (settings %) key) texts)))
