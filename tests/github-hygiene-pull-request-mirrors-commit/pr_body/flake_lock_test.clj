(ns pr-body.flake-lock-test
  (:require [clojure.test :refer [deftest is]]
            [pr-body.flake-lock :as flake-lock]))

(defn- lock [nodes] {"version" 7 "root" "root" "nodes" nodes})

(deftest age
  (is (= "—" (flake-lock/age nil 5)))
  (is (= "same date" (flake-lock/age 5 5)))
  (is (= "36 hours newer" (flake-lock/age 0 (* 3 43200))))
  (is (= "3 days newer" (flake-lock/age 0 (* 3 86400))))
  (is (= "3 hours older" (flake-lock/age 10800 0))))

(deftest unchanged-lock-has-no-section
  (let [l (lock {"root" {"inputs" {"a" "a"}} "a" {"locked" {"rev" "1" "narHash" "h"}}})]
    (is (nil? (flake-lock/section [{:path "flake.lock" :old l :new l}])))))

(deftest follows-change
  (let [old (lock {"root" {"inputs" {"a" "a" "b" "b"}}
                   "a" {"locked" {"rev" "1"}}
                   "b" {"inputs" {"a" ["a"]} "locked" {"rev" "2"}}})
        new (lock {"root" {"inputs" {"a" "a" "b" "b"}}
                   "a" {"locked" {"rev" "1"}}
                   "b" {"inputs" {"a" "a_2"} "locked" {"rev" "2"}}
                   "a_2" {"locked" {"rev" "3"}}})]
    (is (= {:rows [] :added [] :removed []
            :graph ["- `b/a` no longer follows `a`"]}
           (flake-lock/changes old new)))))

(deftest added-and-removed-inputs-are-one-line-each
  (let [old (lock {"root" {"inputs" {"a" "a" "b" "b" "moved" "moved"}}
                   "a" {"inputs" {"x" "x"} "locked" {"rev" "aaaaaaa1"}}
                   "x" {"locked" {"rev" "xxxxxxx1"}}
                   "b" {"locked" {"rev" "bbbbbbb1"}}
                   "moved" {"locked" {"type" "github" "owner" "o" "repo" "m"
                                      "rev" "1111111aaaa" "lastModified" 0}}})
        new (lock {"root" {"inputs" {"c" "c" "moved" "moved" "same" "same"}}
                   "c" {"inputs" {"y" "y"} "locked" {"type" "github" "owner" "o" "repo" "c" "rev" "a72c483ffff"}}
                   "y" {"locked" {"rev" "yyyyyyy1"}}
                   "same" {"locked" {"rev" "5"}}
                   "moved" {"locked" {"type" "github" "owner" "o" "repo" "m"
                                      "rev" "2222222bbbb" "lastModified" 86400}}})]
    (is (= (str "## What changes\n\n"
                "### `flake.lock`\n\n"
                "| Input | Revision | Age | Compare |\n"
                "| ----- | -------- | --- | ------- |\n"
                "| `moved` | `1111111` → `2222222` | 24 hours newer | "
                "[compare](https://github.com/o/m/compare/1111111aaaa...2222222bbbb) |\n\n"
                "Added: `c` ([`a72c483`](https://github.com/o/c/commit/a72c483ffff)), `same` (`5`)\n\n"
                "Removed: `a`, `b`")
           (flake-lock/section [{:path "flake.lock" :old old :new new}])))))
