(ns pr-body.markdown-test
  (:require [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [pr-body.markdown :as md]))

(defn- lines [& ls] (str/join "\n" ls))

(deftest paragraphs-join
  (is (= "one two three" (md/unwrap (lines "one" "two" "three"))))
  (is (= "a b\n\nc d" (md/unwrap (lines "a" "b" "" "" "c" "d")))))

(deftest a-body-with-nothing-to-join-is-unchanged
  (let [body (lines "One paragraph, on one line." "" "Another, on one line too.")]
    (is (= body (md/unwrap body)))))

(deftest hard-breaks-stay
  (is (= (lines "one  " "two") (md/unwrap (lines "one  " "two"))))
  (is (= (lines "one\\" "two three") (md/unwrap (lines "one\\" "two" "three")))))

(deftest lists
  (testing "hanging indents join into the item"
    (is (= (lines "- one two" "- three") (md/unwrap (lines "- one" "  two" "- three")))))
  (testing "nested items keep their indent"
    (is (= (lines "1. a b" "   - c d" "2. e") (md/unwrap (lines "1. a" "   b" "   - c" "     d" "2. e")))))
  (testing "a lazy continuation line joins too"
    (is (= "- one two" (md/unwrap (lines "- one" "two")))))
  (testing "a list right after a paragraph line gets a blank line before it"
    (is (= (lines "Intro line:" "" "- a b" "- c") (md/unwrap (lines "Intro" "line:" "- a" "  b" "- c")))))
  (testing "each item keeps its own line, its continuation lines joined with single spaces"
    (is (= (lines "- one, or task_notification" "- two three")
           (md/unwrap (lines "- one, or" "  task_notification" "- two" "  three")))))
  (testing "items with no continuation stay one per line beside items that have one"
    (is (= (lines "Intro:" "" "- a" "- b" "- c d e" "- f")
           (md/unwrap (lines "Intro:" "" "- a" "- b" "- c" "  d" "  e" "- f")))))
  (testing "a list right under a heading"
    (is (= (lines "## H" "- a b" "- c") (md/unwrap (lines "## H" "- a" "  b" "- c")))))
  (testing "task list items"
    (is (= (lines "- [ ] a b" "- [x] c") (md/unwrap (lines "- [ ] a" "  b" "- [x] c")))))
  (testing "a list inside a block quote"
    (is (= (lines "> - a b" "> - c") (md/unwrap (lines "> - a" ">   b" "> - c")))))
  (testing "for every bullet marker and ordered lists"
    (is (= (lines "* a b" "* c d") (md/unwrap (lines "* a" "  b" "* c" "  d"))))
    (is (= (lines "+ a b" "+ c") (md/unwrap (lines "+ a" "  b" "+ c"))))
    (is (= (lines "1. a b" "2. c d") (md/unwrap (lines "1. a" "   b" "2. c" "   d"))))
    (is (= (lines "1) a b" "2) c") (md/unwrap (lines "1) a" "   b" "2) c")))))
  (testing "nested lists by indent, three levels and back out"
    (is (= (lines "- a b" "  * c d" "    1. e f" "- g h")
           (md/unwrap (lines "- a" "  b" "  * c" "    d" "    1. e" "       f" "- g" "  h")))))
  (testing "a second paragraph in an item joins on its own"
    (is (= (lines "- a b" "" "  c d" "- e") (md/unwrap (lines "- a" "  b" "" "  c" "  d" "- e")))))
  (testing "a fenced code block in an item stays as it is"
    (is (= (lines "- a b:" "" "  ```" "  x" "    y" "  ```" "- c d")
           (md/unwrap (lines "- a" "  b:" "" "  ```" "  x" "    y" "  ```" "- c" "  d")))))
  (testing "list lines inside a fenced code block are not joined"
    (is (= (lines "```" "- a" "  b" "1. c" "```") (md/unwrap (lines "```" "- a" "  b" "1. c" "```"))))))

(deftest blockquotes-join-within-the-quote
  (is (= (lines "> one two" ">" "> three") (md/unwrap (lines "> one" "> two" ">" "> three")))))

(deftest verbatim-blocks
  (testing "fenced code, its blank lines kept"
    (is (= (lines "```" "a  " "" "" "b" "```") (md/unwrap (lines "```" "a  " "" "" "b" "```")))))
  (testing "indented code"
    (is (= (lines "x" "" "    a" "    b") (md/unwrap (lines "x" "" "    a" "    b")))))
  (testing "a table"
    (is (= (lines "| a |" "|---|" "| 1 |") (md/unwrap (lines "| a |" "|---|" "| 1 |")))))
  (testing "a table right after a paragraph line gets a blank line before it"
    (is (= (lines "text:" "" "| a | b |" "|---|---|" "| 1 | 2 |")
           (md/unwrap (lines "text:" "| a | b |" "|---|---|" "| 1 | 2 |")))))
  (testing "a heading ends the paragraph before it"
    (is (= (lines "a" "## H" "b c") (md/unwrap (lines "a" "## H" "b" "c")))))
  (testing "a setext heading keeps its underline"
    (is (= (lines "Title" "=====" "b c") (md/unwrap (lines "Title" "=====" "b" "c")))))
  (testing "HTML and link definitions"
    (is (= (lines "<details>" "<summary>x</summary>" "" "[a]: https://example.com")
           (md/unwrap (lines "<details>" "<summary>x</summary>" "" "[a]: https://example.com"))))))

(deftest join-off-keeps-lines
  (is (= (lines "a" "b") (md/render (md/parse (lines "a" "b")) {:join? false})))
  (is (= (lines "text:" "| a |" "|---|") (md/render (md/parse (lines "text:" "| a |" "|---|")) {:join? false}))))

(deftest positions-are-real
  (testing "after backslash hard breaks, which cmark-gfm miscounts"
    (let [doc (md/parse (lines "aa\\" "bb x\\" "cc" "d"))]
      (is (= [[1 1 1 2] [2 1 2 4] [3 1 3 2] [4 1 4 1]] (map :pos (md/of-type doc :text))))))
  (testing "in a table that interrupts a paragraph"
    (let [doc (md/parse (lines "text" "| `a` |" "|---|"))]
      (is (= ["`a`"] (map #(str "`" (md/source doc %) "`") (md/of-type doc :code)))))))
