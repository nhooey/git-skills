(ns pr-body.diff-test
  (:require [clojure.test :refer [deftest is]]
            [pr-body.diff :as diff]))

(deftest changes
  (is (= [] (diff/changes "a\nb" "a\nb")))
  (is (= ["-b" "+c"] (diff/changes "a\nb" "a\nc")))
  (is (= ["-a b" "+a" "+b"] (diff/changes "a b" "a\nb")))
  (is (= ["-x  " "+x"] (diff/changes "x  " "x"))))

(deftest summary-caps-the-lines
  (is (= "-1\n-2\n… 3 more changed lines" (diff/summary "1\n2\n3\n4" "" 2)))
  (is (= "-1\n-2\n-3\n-4\n+" (diff/summary "1\n2\n3\n4" "" 8))))
