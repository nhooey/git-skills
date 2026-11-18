(ns pr-body.prose-test
  (:require [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [pr-body.markdown :as md]
            [pr-body.prose :as prose]))

(defn- listing [body] (prose/listing-sentences (md/parse body)))

(defn- commit [sha body] {:sha sha :body body :body-md (md/parse body)})

(deftest hits
  (testing "X, Y, Z and W"
    (is (= ["It drops the reader, the writer, the queue and the cache."]
           (listing "Why.\n\nIt drops the reader, the writer, the queue and the cache."))))
  (testing "the serial comma, X, Y, and Z"
    (is (= 1 (count (listing "It touches parsing, rendering, and syncing.")))))
  (testing "or, across a 72-column wrap"
    (is (= ["Pick one of the reader, the writer, the queue or the cache."]
           (listing "Pick one of the reader,\nthe writer, the queue or the cache."))))
  (testing "code spans as items, quoted as written"
    (is (= ["It removes `a`, `b`, `c` and `d`."] (listing "It removes `a`, `b`, `c` and `d`."))))
  (testing "only the sentence that lists"
    (is (= ["Then it drops a, b, c and d."] (listing "It starts. Then it drops a, b, c and d. It ends.")))))

(deftest non-hits
  (testing "an address" (is (empty? (listing "It ships to 1 Main St, Springfield, IL 62701."))))
  (testing "numbers" (is (empty? (listing "It reads 1,024,000 rows of 2,048 columns and 1,024 pages."))))
  (testing "commas inside a code span"
    (is (empty? (listing "It calls `f(a, b, c and d)` once."))))
  (testing "commas inside a link"
    (is (empty? (listing "See [reader, writer, queue and cache](https://x.test/a,b,c) first."))))
  (testing "two items" (is (empty? (listing "It drops the reader and the writer."))))
  (testing "a list is already a list"
    (is (empty? (listing "It drops:\n\n- the reader, the writer, the queue and the cache"))))
  (testing "long clauses aren't items"
    (is (empty? (listing
                 "The hook ran on every call in every session, which cost time when nothing changed, and the cache helps.")))))

(deftest preference
  (is (= :warn (prose/warning-mode [])))
  (is (= :off (prose/warning-mode ["- Prose list warning: off\n"])))
  (is (= :warn (prose/warning-mode ["- Prose list warning: off\n" "- **Prose list warning:** `warn`\n"]))))

(deftest repeated-paragraphs
  (let [a (commit "a" "Why the pair.\n\nThe reader moves\nout.")
        b (commit "b" "The reader moves out.")]
    (is (= ["The reader moves out."] (prose/repeated-paragraphs [a b] a)))
    (is (= 1 (count (prose/repetition-warnings [a b] a))))
    (let [a (commit "a" "Why the pair.")]
      (is (empty? (prose/repeated-paragraphs [a b] a))))
    (testing "a single commit's body is the mirror, not a repetition"
      (is (empty? (prose/repetition-warnings [a] a))))))

(deftest warnings
  (let [[w] (prose/warnings [(commit "abcdef0123" "It drops a, b, c and d.")])]
    (is (str/starts-with? w "abcdef0 lists three or more items"))
    (is (str/includes? w "writing-hygiene-prose-to-lists"))))
