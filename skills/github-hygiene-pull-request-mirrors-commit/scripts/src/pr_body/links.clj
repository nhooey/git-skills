(ns pr-body.links
  "Code links and issue references in a commit's body or subject, made
  as edits to its Markdown, `pr-body.markdown/parse`d.

  - `path:a` and `path:a-b`, bare or alone in a code span, become a
    link to those lines in the file at the commit, but only when the
    file exists there with that many lines. A top-level paragraph that
    is such a reference alone becomes the bare permalink, which GitHub
    renders as a snippet.
  - `repo#N` is qualified to `owner/repo#N`; a bare `#N` is collected so
    the caller can warn when it names no issue or pull request.

  Only text nodes and code spans are read, so code blocks, HTML, links
  and their targets are left alone. A text node's source holds no
  Markdown but escapes, so the references and bare URLs in it are flat
  tokens, matched by `token`. Nothing here reads git: `scan` lists what
  to look up, and the caller passes the answers in as `:line-counts
  {[sha path] n}`."
  (:require [clojure.string :as str]
            [pr-body.markdown :as md]))

(def ^:private path-ref #"([A-Za-z0-9_][\w.\-/]*):(\d+)(?:-(\d+))?")

(def ^:private token
  "The tokens of a text node's source, in priority order: a URL, left
  alone; a bare code reference; `repo#N`; and `#N`."
  (re-pattern
   (str "(https?://\\S+)"
        "|(?<![\\w/.\\-:#])([A-Za-z0-9_][\\w.\\-/]*):(\\d+)(?:-(\\d+))?(?![\\w:/-])"
        "|(?<![\\w/.\\-#])([A-Za-z0-9_][\\w.\\-]*)#(\\d+)\\b"
        "|(?<![\\w/&#])#(\\d+)\\b")))

(defn- parse-ref
  "`{:path :from :to}` for `path:a` or `path:a-b`, or nil."
  [s]
  (when-let [[_ path from to] (re-matches path-ref (str/trim (or s "")))]
    (let [from (parse-long from) to (if to (parse-long to) from)]
      (when (<= 1 from to) {:path path :from from :to to}))))

(defn- valid? [{:keys [path to]} sha line-counts]
  (when-let [n (get line-counts [sha path])] (<= to n)))

(defn permalink [repo sha {:keys [path from to]}]
  (str (:url repo) "/blob/" sha "/" path "#L" from (when (not= from to) (str "-L" to))))

(defn- code-link [repo sha {:keys [path from to] :as ref}]
  (str "[`" path ":" from (when (not= from to) (str "-" to)) "`]("
       (permalink repo sha ref) ")"))

(defn- segment
  "The replacement for one `token` match."
  [{:keys [repo sha line-counts]} [whole _ path from to repo-name repo-num _]]
  (cond
    path (let [ref (parse-ref (str path ":" from (when to (str "-" to))))]
           (if (and ref (valid? ref sha line-counts)) (code-link repo sha ref) whole))
    repo-name (str (:owner repo) "/" repo-name "#" repo-num)
    :else whole))

(defn- targets
  "The text nodes and code spans of `doc` that may hold a reference:
  those on one line, outside a link or an image."
  [doc]
  (->> (md/of-type doc :text :code)
       (remove (fn [n] (some #(#{:link :image} (:type %)) (:ancestors n))))
       (filter (fn [{[l1 _ l2] :pos}] (and l1 (= l1 l2))))))

(defn- span-edge
  "The column of the outermost backtick around a code span's content,
  which ends at `col`, looking in direction `step`; nil when it isn't
  where it should be."
  [doc line col step]
  (let [at #(md/byte-at doc line %)
        c (if (and (= \space (at (+ col step))) (= \` (at (+ col step step)))) (+ col step) col)]
    (when (= \` (at (+ c step)))
      (loop [c (+ c step)] (if (= \` (at (+ c step))) (recur (+ c step)) c)))))

(defn- inline-edit
  "The edit linking the references in one text node or code span, or nil."
  [{:keys [repo sha line-counts] :as ctx} doc {:keys [type literal] [line col _ end-col] :pos :as n}]
  (case type
    :text (let [src (md/source doc n)
                linked (str/replace src token #(segment ctx %))]
            (when (not= src linked) {:line line :from col :to end-col :text linked}))
    :code (let [ref (parse-ref literal)
                from (span-edge doc line col -1)
                to (span-edge doc line end-col 1)]
            (when (and ref from to (valid? ref sha line-counts))
              {:line line :from from :to to :text (code-link repo sha ref)}))))

(defn- standalone-edit
  "The edit making a top-level paragraph that holds one valid code
  reference alone into its permalink, or nil."
  [{:keys [repo sha line-counts]} paragraph]
  (let [[only & more] (remove #(and (= :text (:type %)) (str/blank? (:literal %))) (:children paragraph))
        ref (when (and only (nil? more) (#{:text :code} (:type only))) (parse-ref (:literal only)))
        [l1 _ l2] (:pos paragraph)]
    (when (and ref l1 (valid? ref sha line-counts))
      {:lines [l1 l2] :text (permalink repo sha ref)})))

(defn edits
  "The edits that link `doc`'s code references and qualify its `repo#N`.
  `ctx` is `{:repo {:owner :name :url} :sha s :line-counts m}`."
  [ctx doc]
  (vec (concat (keep #(inline-edit ctx doc %) (targets doc))
               (keep #(standalone-edit ctx %) (filter md/top-level? (md/of-type doc :paragraph))))))

(defn render
  "`doc` with its references linked, its paragraphs joined when `join?`."
  [ctx doc join?]
  (md/render doc {:join? join? :edits (edits ctx doc)}))

(defn scan
  "What `doc` needs looked up: `{:paths #{path} :issues #{n}}`, the
  paths of every code reference and the numbers of every bare `#N`."
  [doc]
  (reduce (fn [acc {:keys [type literal] :as n}]
            (if (= :code type)
              (if-let [ref (parse-ref literal)] (update acc :paths conj (:path ref)) acc)
              (reduce (fn [acc [_ _ path _ _ _ _ issue]]
                        (cond-> acc
                          path (update :paths conj path)
                          issue (update :issues conj (parse-long issue))))
                      acc
                      (re-seq token (md/source doc n)))))
          {:paths #{} :issues #{}}
          (targets doc)))
