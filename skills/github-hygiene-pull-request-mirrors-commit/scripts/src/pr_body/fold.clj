(ns pr-body.fold
  "Whether a live pull request body's text is all in the commit message,
  so that `sync` may overwrite a body edited by hand without losing
  anything.

  Both bodies are parsed by `pr-body.markdown`, and compared by their
  text blocks: each paragraph and heading as its plain text (a link as
  its text, a code span as its code), each code or HTML block as its
  literal, and each table row as its cells, all with whitespace
  normalised. A block of the live body is in the render when it is
  part of one of the render's blocks, so a block folded into a longer
  paragraph counts, and so does one whose code references the render
  links.

  What the program generates, or the commit keeps apart, is left out of
  the live body first: the footer (the marker and the attribution line)
  and a closing trailer block. So are a `Stacks on` line and
  `Commits (N)` and `What changes` sections, which describe commits an
  amend or squash may have replaced rather than hold the commit
  message's text."
  (:require [clojure.string :as str]
            [pr-body.footer :as footer]
            [pr-body.markdown :as md]))

(defn- normalize [s] (str/join " " (remove str/blank? (str/split (or s "") #"\s+"))))

(defn- text
  "The text of a block `node` as `missing` compares it, or nil for a
  node holding no text of its own."
  [node]
  (case (:type node)
    (:paragraph :heading) (md/plain node)
    (:code_block :html_block) (:literal node)
    (:table_header :table_row) (str/join " | " (map md/plain (:children node)))
    nil))

(defn- texts
  "The normalised, non-blank texts of the blocks under `nodes`, in
  document order."
  [nodes]
  (->> nodes
       (mapcat md/nodes)
       (keep text)
       (map normalize)
       (remove str/blank?)))

;; --- what describes the commits ------------------------------------

(defn- generated-heading?
  "Whether `node` opens a `Commits (N)` or `What changes` section."
  [node]
  (and (= :heading (:type node)) (= 2 (:level node))
       (let [t (str/trim (md/plain node))]
         (or (= t "What changes")
             (and (str/starts-with? t "Commits (") (str/ends-with? t ")"))))))

(defn- without-generated-sections
  "`blocks` without each generated section: its heading and every block
  up to the next heading of level 1 or 2."
  [blocks]
  (first
   (reduce (fn [[kept skipping?] b]
             (cond (generated-heading? b) [kept true]
                   (and (= :heading (:type b)) (<= (:level b) 2)) [(conj kept b) false]
                   skipping? [kept true]
                   :else [(conj kept b) false]))
           [[] false]
           blocks)))

(defn- paragraph-starting? [prefix node]
  (and (= :paragraph (:type node)) (str/starts-with? (md/plain node) prefix)))

(defn- trailer-line?
  "Whether `line` is a `Token: value` trailer as git reads one: a token of
  letters, digits and hyphens, then a colon ending the line or followed
  by a space."
  [line]
  (let [token (take-while #(or (Character/isLetterOrDigit ^char %) (= \- %)) line)
        rest (str/triml (subs line (count token)))]
    (and (seq token) (str/starts-with? rest ":")
         (or (= 1 (count rest)) (Character/isWhitespace ^char (nth rest 1))))))

(defn- trailer-block?
  "Whether the paragraph `node` of `doc` is a trailer block: its first
  line a trailer, and each line after it a trailer or a continuation
  indented under one."
  [doc node]
  (when-let [[l1 _ l2] (and (= :paragraph (:type node)) (:pos node))]
    (let [lines (map #(:text (nth (:lines doc) (dec %))) (range l1 (inc l2)))]
      (and (trailer-line? (first lines))
           (every? #(or (trailer-line? %) (and (seq %) (Character/isWhitespace ^char (first %))))
                   (rest lines))))))

(defn- drop-last-if [pred blocks]
  (if (and (seq blocks) (pred (peek blocks))) (pop blocks) blocks))

(defn- own-blocks
  "The top-level blocks of the live `body` that hold text written for
  this pull request rather than generated or kept in the commit."
  [body]
  (let [above (if-let [parsed (footer/parse body)] (:above parsed) (or body ""))
        doc (md/parse above)]
    (->> (:children (:root doc))
         without-generated-sections
         (remove (partial paragraph-starting? "Stacks on "))
         vec
         (drop-last-if (partial paragraph-starting? "🤖"))
         (drop-last-if (partial trailer-block? doc)))))

(defn missing
  "The text blocks of the live body `live` that aren't in the rendered
  body `rendered`, normalised, in order, each once. Empty when the live
  body's text is all in the commit message."
  [live rendered]
  (let [held (vec (texts [(:root (md/parse rendered))]))]
    (vec (distinct (remove (fn [t] (some #(str/includes? % t) held))
                           (texts (own-blocks live)))))))
