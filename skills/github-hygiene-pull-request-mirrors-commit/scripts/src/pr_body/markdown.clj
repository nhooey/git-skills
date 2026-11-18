(ns pr-body.markdown
  "Commit bodies as GitHub-flavoured Markdown, parsed by `cmark-gfm`, the
  parser GitHub renders with, and rewritten by source position.

  `parse` runs `cmark-gfm --to xml --sourcepos` and keeps the source
  lines beside the syntax tree. `render` then changes only what the
  program changes, sliced out of the source by the tree's positions, so
  everything else comes out byte for byte and no Markdown writer is
  needed:

  - each paragraph's lines join with spaces, wherever it sits (a list
    item, a block quote), except across a hard break;
  - a list that follows a paragraph line directly, a table that follows
    any block directly, and a block that follows a table directly get a
    blank line between them;
  - the edits the caller passes replace spans of single lines, or whole
    paragraphs;
  - runs of blank lines outside code and HTML blocks collapse to one.

  GitHub renders every newline in a pull request body as a line break,
  which is why a body wrapped at 72 columns is joined.

  Positions are cmark's: lines from 1, columns as UTF-8 byte offsets
  from 1, both ends inclusive."
  (:require [babashka.process :as p]
            [clojure.data.xml :as xml]
            [clojure.string :as str])
  (:import (java.nio.charset StandardCharsets)
           (java.util Arrays)))

;; Compromise: plan node write-clojure-markdown-library

;; --- parsing ----------------------------------------------------------

(def ^:private extensions
  ;; Not `autolink`: cmark-gfm gives the nodes it makes wrong positions.
  ["table" "strikethrough"])

(defn- cmark-xml [text]
  (let [r (try
            (apply p/sh {:in text :continue true}
                   "cmark-gfm" "--to" "xml" "--sourcepos"
                   (mapcat #(vector "--extension" %) extensions))
            (catch java.io.IOException e
              (throw (ex-info (str "cmark-gfm not found: " (.getMessage e)) {:exit 2}))))]
    (when-not (zero? (:exit r))
      (throw (ex-info (str "cmark-gfm failed: " (:err r)) {:exit 2})))
    (:out r)))

(defn- sourcepos
  "`[line col end-line end-col]` from cmark's `l:c-l:c`, or nil."
  [s]
  (when s
    (let [[from to] (str/split s #"-" 2)]
      (mapv parse-long (concat (str/split from #":") (str/split to #":"))))))

(defn- node
  "A tree node, `{:type :pos :literal :children}`, from an XML element,
  with a heading's `:level`."
  [el]
  (let [children (filter map? (:content el))
        level (get-in el [:attrs :level])]
    (cond-> {:type (keyword (name (:tag el)))
             :pos (sourcepos (get-in el [:attrs :sourcepos]))
             :children (mapv node children)}
      level (assoc :level (parse-long level))
      (empty? children) (assoc :literal (apply str (filter string? (:content el)))))))

(defn- backslash-break? [line]
  (odd? (count (take-while #{\\} (reverse line)))))

(defn- runs
  "The lines `from`..`to` in runs that backslash hard breaks join: cmark-gfm
  gives the nodes inside a paragraph positions as though each such run
  were one line, the newline after the backslash one more column."
  [lines from to]
  (reduce (fn [acc l]
            (if (and (seq acc) (backslash-break? (nth lines (- l 2))))
              (conj (pop acc) (conj (peek acc) l))
              (conj acc [l])))
          []
          (range from (inc to))))

(defn- true-point
  "The real `[line col]` of cmark's `[line col]` inside a paragraph whose
  lines come in `runs`."
  [lines widths runs first-line [line col]]
  (if-let [run (get runs (- line first-line))]
    (loop [[l & more] run col col]
      (let [w (widths (dec l))]
        (if (and (seq more) (> col (inc w))) (recur more (- col w 1)) [l col])))
    [line col]))

(defn- fix-positions
  "`root` with the positions of the nodes inside each paragraph made
  real, as `runs` describes."
  [lines root]
  (let [widths (mapv #(count (.getBytes ^String % StandardCharsets/UTF_8)) lines)
        fix (fn fix [move n]
              (cond-> (update n :children #(mapv (partial fix move) %))
                (:pos n) (update :pos (fn [[l1 c1 l2 c2]] (into (move [l1 c1]) (move [l2 c2]))))))
        walk (fn walk [n]
               (if (and (= :paragraph (:type n)) (:pos n))
                 (let [[l1 _ l2] (:pos n)
                       move (partial true-point lines widths (runs lines l1 l2) l1)]
                   (update n :children #(mapv (partial fix move) %)))
                 (update n :children #(mapv walk %))))]
    (walk root)))

(defn- tree [lines]
  (fix-positions lines (node (xml/parse-str (cmark-xml (str/join "\n" lines)) :support-dtd false))))

(defn nodes
  "Every node under `root`, in document order, each with its
  `:ancestors`, outermost first."
  ([root] (nodes root []))
  ([root ancestors]
   (cons (assoc root :ancestors ancestors)
         (mapcat #(nodes % (conj ancestors root)) (:children root)))))

(defn- breaks [node]
  (count (filter #(#{:softbreak :linebreak} (:type %)) (nodes node))))

(defn- misplaced-headers
  "The lines of the header rows of tables that interrupt a paragraph.
  cmark-gfm gives such a paragraph no position and its table the
  paragraph's start, so `parse` parts the two with a blank line."
  [root]
  (for [{:keys [children]} (nodes root)
        [a b] (partition 2 1 children)
        :when (and (= :paragraph (:type a)) (nil? (:pos a)) (= :table (:type b)) (:pos b))]
    (+ (first (:pos b)) (breaks a) 1)))

(defn parse
  "`{:lines [{:text s :synthetic? b}] :root node}` for the Markdown
  `text`. A synthetic line is a blank one `parse` added to get the
  positions right; `render` keeps it only when it joins lines."
  [text]
  (loop [lines (mapv (fn [t] {:text t}) (str/split-lines (or text ""))) tries 3]
    (let [root (tree (mapv :text lines))
          before (set (misplaced-headers root))]
      (if (and (seq before) (pos? tries))
        (recur (vec (mapcat (fn [i line] (if (before i) [{:text "" :synthetic? true} line] [line]))
                            (iterate inc 1) lines))
               (dec tries))
        {:lines lines :root root}))))

;; --- reading the tree -------------------------------------------------

(defn of-type
  "The nodes of `doc` of any of `types`, in document order."
  [doc & types]
  (filter #((set types) (:type %)) (nodes (:root doc))))

(defn top-level? [node] (= [:document] (mapv :type (:ancestors node))))

(defn plain
  "The text of an inline `node` and its children: a code span as its
  code, a line break as a space."
  [node]
  (case (:type node)
    (:softbreak :linebreak) " "
    (:text :code :html_inline) (:literal node)
    (apply str (map plain (:children node)))))

(defn- utf8 ^bytes [^String s] (.getBytes s StandardCharsets/UTF_8))

(defn- from-utf8 [^bytes b from to]
  (String. (Arrays/copyOfRange b (int from) (int to)) StandardCharsets/UTF_8))

(defn- line-text [doc line] (:text (nth (:lines doc) (dec line))))

(defn source
  "The source of the single-line `node`, by its position."
  [doc {[line col _ end-col] :pos}]
  (let [b (utf8 (line-text doc line))
        to (min (alength b) end-col)]
    (from-utf8 b (min (dec col) to) to)))

(defn byte-at
  "The byte at column `col` of `line`, as a char, or nil past either end."
  [doc line col]
  (let [b (utf8 (line-text doc line))]
    (when (<= 1 col (alength b)) (char (aget b (dec col))))))

;; --- rendering --------------------------------------------------------

(defn- hard-break? [line]
  (or (str/ends-with? line "  ") (str/ends-with? line "\\")))

(defn- quote-depth [node] (count (filter #(= :block_quote (:type %)) (:ancestors node))))

(defn- strip-quote-markers
  "`line` without `n` leading block quote markers, each up to three
  spaces, `>` and an optional space; a lazy line may have fewer."
  [line n]
  (loop [s line n n]
    (let [t (str/triml s)]
      (if (and (pos? n) (str/starts-with? t ">") (<= (- (count s) (count t)) 3))
        (recur (let [r (subs t 1)] (if (str/starts-with? r " ") (subs r 1) r)) (dec n))
        s))))

(defn- gaps
  "`{line prefix}`: a blank line to add before `line`, as the block
  quotes around it write one."
  [doc]
  (into {}
        (for [{:keys [children] :as parent} (nodes (:root doc))
              [a b] (partition 2 1 children)
              :let [a-end (get-in a [:pos 2]) b-start (get-in b [:pos 0])]
              :when (and a-end b-start (= (inc a-end) b-start)
                         (or (and (= :paragraph (:type a)) (= :list (:type b))
                                  (not= :item (:type parent)))
                             (= :table (:type b))
                             (= :table (:type a))))]
          [b-start (str/join " " (repeat (quote-depth (assoc b :ancestors (conj (vec (:ancestors parent)) parent)))
                                         ">"))])))

(defn- line-roles
  "`{line [role depth]}` for the lines the tree says how to treat:
  `:join` (onto the line before, inside `depth` block quotes), `:para`,
  `:heading` or `:verbatim` (code and HTML blocks, whose blank lines
  stay)."
  [doc join?]
  (reduce
   (fn [roles {:keys [type pos] :as n}]
     (let [[l1 _ l2] pos
           lines (range l1 (inc l2))]
       (case type
         :paragraph (into roles (for [l lines]
                                  [l (if (and join? (> l l1) (not (hard-break? (line-text doc (dec l)))))
                                       [:join (quote-depth n)]
                                       [:para])]))
         (:code_block :html_block) (into roles (for [l lines] [l [:verbatim]]))
         (:heading :thematic_break) (into roles (for [l lines] [l [:heading]]))
         roles)))
   {}
   (filter :pos (nodes (:root doc)))))

(defn- apply-edits
  "`text` with each `{:from :to :text}` edit, by byte column, made."
  [text edits]
  (reduce (fn [out {:keys [from to] :as e}]
            (let [b (utf8 out)]
              (str (from-utf8 b 0 (dec from)) (:text e) (from-utf8 b to (alength b)))))
          text
          (sort-by :from > edits)))

(defn- collapse-blanks
  "Output lines `[text verbatim?]` as strings, with each run of blank
  lines outside verbatim blocks made one, and none at either end."
  [lines]
  (let [kept (reduce (fn [acc [text verbatim?]]
                       (let [blank? (and (not verbatim?) (str/blank? text))]
                         (cond (and blank? (or (empty? acc) (= "" (peek acc)))) acc
                               blank? (conj acc "")
                               :else (conj acc text))))
                     []
                     lines)]
    (if (= "" (peek kept)) (pop kept) kept)))

(defn render
  "The source of `doc` with `edits` made, its paragraphs joined unless
  `:join?` is false. An edit is `{:line l :from c :to c :text s}`,
  replacing bytes `from`..`to` of one line, or `{:lines [l1 l2] :text
  s}`, replacing whole lines, which wins over the edits inside them."
  [doc {:keys [join? edits]}]
  (let [roles (line-roles doc join?)
        gap (if join? (gaps doc) {})
        whole (into {} (for [{[l1 l2] :lines :as e} edits :when l1, l (range l1 (inc l2))]
                         [l (when (= l l1) (:text e))]))
        inline (group-by :line (remove :lines edits))]
    (->> (map vector (iterate inc 1) (:lines doc))
         (reduce
          (fn [out [l {:keys [text synthetic?]}]]
            (let [[role depth] (roles l)
                  text (if (contains? whole l) (whole l) (apply-edits text (inline l)))
                  text (if (and text (#{:para :join :heading} role) (not (hard-break? text)))
                         (str/trimr text)
                         text)
                  out (if-let [prefix (gap l)] (conj out [prefix false]) out)]
              (cond
                (nil? text) out
                (and synthetic? (not join?)) out
                (= :join role) (let [[prev v] (peek out)]
                                 (conj (pop out) [(str prev " " (str/triml (strip-quote-markers text depth))) v]))
                :else (conj out [text (= :verbatim role)]))))
          [])
         collapse-blanks
         (str/join "\n"))))

(defn unwrap
  "The Markdown `text` with its paragraphs joined."
  [text]
  (render (parse text) {:join? true}))
