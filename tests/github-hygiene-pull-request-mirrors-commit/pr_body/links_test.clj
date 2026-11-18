(ns pr-body.links-test
  (:require [clojure.test :refer [deftest is testing]]
            [pr-body.links :as links]
            [pr-body.markdown :as md]))

(def sha "abcdef0123456789abcdef0123456789abcdef01")
(def ctx {:repo {:owner "o" :name "r" :url "https://github.com/o/r"} :sha sha
          :line-counts {[sha "a/b.clj"] 10}})

(defn- url [frag] (str "https://github.com/o/r/blob/" sha "/a/b.clj#" frag))

(defn- linked [text] (links/render ctx (md/parse text) true))

(deftest code-references
  (testing "a code span holding a reference"
    (is (= (str "see [`a/b.clj:3-4`](" (url "L3-L4") ")") (linked "see `a/b.clj:3-4`")))
    (is (= (str "see [`a/b.clj:3`](" (url "L3") ") and ``x``") (linked "see `` a/b.clj:3 `` and ``x``"))))
  (testing "a bare reference"
    (is (= (str "at [`a/b.clj:7`](" (url "L7") ").") (linked "at a/b.clj:7."))))
  (testing "after multi-byte text, and on the line after a backslash break"
    (is (= (str "— [`a/b.clj:7`](" (url "L7") ")\\\nthen [`a/b.clj:8`](" (url "L8") ")")
           (linked "— a/b.clj:7\\\nthen a/b.clj:8"))))
  (testing "lines past the end, a missing path, a reversed range"
    (is (= "a/b.clj:11 c.clj:1 `a/b.clj:4-2`" (linked "a/b.clj:11 c.clj:1 `a/b.clj:4-2`"))))
  (testing "inside a URL, a link, or a link target"
    (is (= "https://x.org/a/b.clj:3 [t](a/b.clj:3) [a/b.clj:3](u) <https://x.org/a/b.clj:3>"
           (linked "https://x.org/a/b.clj:3 [t](a/b.clj:3) [a/b.clj:3](u) <https://x.org/a/b.clj:3>")))))

(deftest standalone-reference-is-a-permalink
  (is (= (url "L2-L5") (linked "`a/b.clj:2-5`")))
  (is (= (str "- [`a/b.clj:2`](" (url "L2") ")") (linked "- a/b.clj:2"))))

(deftest code-blocks-are-left-alone
  (is (= "```\na/b.clj:2 r#3\n```" (linked "```\na/b.clj:2 r#3\n```"))))

(deftest issue-references
  (is (= "o/widgets#3, x/y#4 and #5" (linked "widgets#3, x/y#4 and #5")))
  (is (= {:paths #{"a/b.clj"} :issues #{5}}
         (links/scan (md/parse "`a/b.clj:1` widgets#3 #5\n\n    #6 c.clj:1")))))
