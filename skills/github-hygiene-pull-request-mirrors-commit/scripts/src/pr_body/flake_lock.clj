(ns pr-body.flake-lock
  "The \"What changes\" section for changed `flake.lock` files.

  Each lock is read as parsed JSON (string keys). Every input reachable
  from the root is named by its path, such as `agent-skill-flake/nixpkgs`,
  and is either its own node or `follows` another path. The section has:

  - a table row per input whose locked revision changed, was added or was
    removed: the input, `old → new` short revisions, how much newer the
    new revision is, and a compare link for GitHub inputs;
  - a list of graph changes, where an input starts or stops following
    another.

  It derives from the two trees alone, so the same range always renders
  the same section."
  (:require [clojure.string :as str]))

(defn- input-entries
  "`{path entry}` for every input reachable from the root, where an entry
  is `{:node name}` or `{:follows path}`."
  [lock]
  (let [nodes (get lock "nodes")]
    (loop [queue [[[] (get lock "root" "root")]], seen #{}, acc {}]
      (if-let [[[prefix node-name] & more] (seq queue)]
        (let [inputs (sort-by key (get-in nodes [node-name "inputs"]))
              entries (for [[input target] inputs]
                        [(conj prefix input) target])
              acc (into acc (for [[path target] entries]
                              [(str/join "/" path)
                               (if (string? target) {:node target} {:follows (str/join "/" target)})]))
              next-nodes (for [[path target] entries
                               :when (and (string? target) (not (seen target)))]
                           [path target])]
          (recur (into (vec more) next-nodes) (into seen (map second next-nodes)) acc))
        acc))))

(defn- locked [lock node-name]
  (get-in lock ["nodes" node-name "locked"]))

(defn- short-rev [{:strs [rev narHash]}]
  (cond rev (subs rev 0 (min 7 (count rev)))
        narHash (str (subs narHash 0 (min 14 (count narHash))) "…")
        :else "?"))

(defn- github-repo [{:strs [type owner repo]}]
  (when (= type "github") [owner repo]))

(defn age
  "How much newer `new-lm` is than `old-lm`, both Unix seconds."
  [old-lm new-lm]
  (if (and old-lm new-lm)
    (let [delta (- new-lm old-lm)
          size (abs delta)
          unit (cond (< size 7200) [(quot size 60) "minute"]
                     (< size (* 2 86400)) [(quot size 3600) "hour"]
                     :else [(quot size 86400) "day"])
          [n word] unit]
      (cond (zero? delta) "same date"
            :else (str n " " word (when (not= n 1) "s") (if (pos? delta) " newer" " older"))))
    "—"))

(defn- row
  "A table row for an input whose locked revision moved from `old` to `new`."
  [path old new]
  (let [compare-url (when (and (github-repo old) (= (github-repo old) (github-repo new))
                               (get old "rev") (get new "rev"))
                      (let [[owner repo] (github-repo new)]
                        (str "https://github.com/" owner "/" repo "/compare/"
                             (get old "rev") "..." (get new "rev"))))]
    (str "| `" path "` | `" (short-rev old) "` → `" (short-rev new) "`"
         " | " (age (get old "lastModified") (get new "lastModified"))
         " | " (if compare-url (str "[compare](" compare-url ")") "—") " |")))

(defn- same-lock? [a b]
  (= (select-keys a ["rev" "narHash"]) (select-keys b ["rev" "narHash"])))

(defn- depth-then-path [path] [(count (str/split path #"/")) path])

(defn changes
  "`{:rows [line] :added [path+rev] :removed [path] :graph [line]}` for
  one lock's old and new JSON, either of which may be nil for a lock
  added or removed. Rows are the inputs whose revision moved; an input
  added or removed is named once, without the inputs it brings along."
  [old new]
  (let [old-entries (if old (input-entries old) {})
        new-entries (if new (input-entries new) {})
        paths (sort-by depth-then-path (distinct (concat (keys old-entries) (keys new-entries))))
        locks (into {} (for [path paths]
                         [path [(some->> (:node (old-entries path)) (locked old))
                                (some->> (:node (new-entries path)) (locked new))]]))
        ;; An input added or removed brings its own inputs with it: only
        ;; the outermost one gets a row.
        whole (set (for [[path [o n]] locks :when (not= (some? o) (some? n))] path))
        inside-whole? (fn [path] (some #(str/starts-with? path (str % "/")) whole))
        outermost (remove inside-whole? paths)
        rows (for [path outermost
                   :let [[o n] (locks path)]
                   :when (and o n (not (same-lock? o n)))]
               (row path o n))
        added (for [path outermost
                    :let [[o n] (locks path)]
                    ;; an input that only switched to or from `follows`
                    ;; is a graph change, below
                    :when (and n (nil? o) (nil? (old-entries path)))]
                (str "`" path "` ("
                     (if-let [[owner repo] (when (get n "rev") (github-repo n))]
                       (str "[`" (short-rev n) "`](https://github.com/" owner "/" repo "/commit/" (get n "rev") ")")
                       (str "`" (short-rev n) "`"))
                     ")"))
        removed (for [path outermost
                      :let [[o n] (locks path)]
                      :when (and o (nil? n) (nil? (new-entries path)))]
                  (str "`" path "`"))
        graph (for [path paths
                    :let [o (:follows (old-entries path))
                          n (:follows (new-entries path))]
                    :when (and (old-entries path) (new-entries path) (or o n) (not= o n))]
                (cond
                  (and o n) (str "- `" path "` follows `" n "` instead of `" o "`")
                  n (str "- `" path "` now follows `" n "`")
                  :else (str "- `" path "` no longer follows `" o "`")))]
    {:rows (vec rows) :added (vec added) :removed (vec removed) :graph (vec graph)}))

(defn- lock-part
  "One lock's subsection, its blocks parted by blank lines."
  [path {:keys [rows added removed graph]}]
  (str/join "\n\n"
            (remove nil?
                    [(str "### `" path "`")
                     (when (seq rows)
                       (str/join "\n" (concat ["| Input | Revision | Age | Compare |"
                                               "| ----- | -------- | --- | ------- |"]
                                              rows)))
                     (when (seq added) (str "Added: " (str/join ", " added)))
                     (when (seq removed) (str "Removed: " (str/join ", " removed)))
                     (when (seq graph)
                       (str "Input graph changes:\n\n" (str/join "\n" graph)))])))

(defn section
  "The \"What changes\" section for `locks`, a seq of `{:path :old :new}`,
  or nil when no lock's inputs changed."
  [locks]
  (let [parts (for [{:keys [path old new]} (sort-by :path locks)
                    :let [c (changes old new)]
                    :when (some seq (vals c))]
                (lock-part path c))]
    (when (seq parts)
      (str/join "\n\n" (cons "## What changes" parts)))))
