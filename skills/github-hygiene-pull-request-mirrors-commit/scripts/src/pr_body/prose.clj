(ns pr-body.prose
  "Finds sentences in a commit body's paragraphs that list three or more
  items with two or more commas, `X, Y, Z and W` or `X, Y, and Z`, which
  `writing-hygiene-prose-to-lists` would write as a list. A heuristic:
  `check` only warns about them.

  Only top-level paragraphs are read, never list items, tables or code,
  and `java.text.BreakIterator` splits them into sentences. Inside a
  paragraph, a code span, a link and a number such as 1,024 each count
  as one word, so commas inside them separate nothing. Each item is one
  to five words, and the last one follows `and` or `or`, so a run of
  clauses or an address (`1 Main St, Springfield, IL`) isn't taken for a
  list."
  (:require [clojure.string :as str]
            [pr-body.markdown :as md]
            [pr-body.preferences :as preferences])
  (:import (java.text BreakIterator)
           (java.util Locale)))

(defn- segments
  "A paragraph's inline content as `[shown masked]` pairs: text as it
  reads, and each code span, link and image as one word."
  [node]
  (mapcat (fn [n]
            (case (:type n)
              :text [[(:literal n) (:literal n)]]
              (:softbreak :linebreak) [[" " " "]]
              :code [[(str "`" (:literal n) "`") "code"]]
              (:link :image) [[(md/plain n) "link"]]
              :html_inline [[(:literal n) "html"]]
              (segments n)))
          (:children node)))

(defn- mask-words
  "`s` with each number such as 1,024 and each bare URL reduced to one word."
  [s]
  (-> s
      (str/replace #"\d{1,3}(?:,\d{3})+" "number")
      (str/replace #"https?://\S+" "link")))

(defn- sentence-bounds
  "`[from to]` of each sentence of `s`."
  [^String s]
  (let [it (doto (BreakIterator/getSentenceInstance Locale/ENGLISH) (.setText s))]
    (loop [from (.first it) acc []]
      (let [to (.next it)]
        (if (= to BreakIterator/DONE) acc (recur to (conj acc [from to])))))))

(defn- sentences
  "`[shown masked]` for each sentence of a paragraph's `segments`."
  [segs]
  (let [shown (apply str (map first segs))
        starts (reductions + 0 (map (comp count first) segs))]
    (for [[from to] (sentence-bounds shown)]
      [(str/trim (subs shown from to))
       (apply str (for [[[s m] at] (map vector segs starts)
                        :let [end (+ at (count s))]
                        :when (and (< at to) (> end from))]
                    (if (= s m) (subs s (- (max at from) at) (- (min end to) at)) (if (>= at from) m ""))))])))

(def ^:private word "[\\p{L}\\p{N}'’/+_-]+")
(def ^:private item (str word "(?: " word "){0,4}"))

(def ^:private enumeration
  ;; Two or more `item, ` then `and|or item` (the serial comma's form),
  ;; or two or more `item, ` then `item and|or item`.
  (re-pattern (str "(?i)(?:" item ", ){2,}(?:(?:and|or) " item "|" item " (?:and|or) " item ")")))

(defn listing-sentences
  "The sentences of the top-level paragraphs of `doc`, a parsed body,
  that list three or more comma-separated items, as they read."
  [doc]
  (vec (for [p (filter md/top-level? (md/of-type doc :paragraph))
             [shown masked] (sentences (segments p))
             :when (re-find enumeration (mask-words masked))]
         shown)))

(defn warning-mode
  "`:warn` or `:off` from the preferences `texts`, the user's before the
  project's: the last `Prose list warning:` item wins."
  [texts]
  (preferences/choice texts "prose list warning" ["warn" "off"] :warn))

(defn- normalize [s] (str/trim (str/replace (or s "") #"\s+" " ")))

(defn- paragraphs [doc]
  (->> (md/of-type doc :paragraph) (filter md/top-level?) (map (comp normalize md/plain)) (remove str/blank?)))

(defn repeated-paragraphs
  "The paragraphs of `lead`'s body, the synthesis of a multi-commit pull
  request, that repeat a paragraph of another of `commits`' bodies,
  whitespace aside. The synthesis should say only what no single commit
  says, and reference a commit by its subject."
  [commits lead]
  (let [others (set (mapcat #(paragraphs (:body-md %)) (remove #(= (:sha %) (:sha lead)) commits)))]
    (vec (filter others (paragraphs (:body-md lead))))))

(defn repetition-warnings
  "One warning per synthesis paragraph that repeats a commit's body."
  [commits lead]
  (when (< 1 (count commits))
    (vec (for [p (repeated-paragraphs commits lead)]
           (str "the synthesis repeats a commit's message; say only what no single commit says, "
                "and name a commit by its subject: \"" p "\"")))))

(defn warnings
  "One warning per listing sentence in the `commits`' bodies."
  [commits]
  (vec (for [c commits
             s (listing-sentences (:body-md c))]
         (str (subs (:sha c) 0 (min 7 (count (:sha c)))) " lists three or more items in one sentence; "
              "write them as a `-` list (writing-hygiene-prose-to-lists): \"" s "\""))))
