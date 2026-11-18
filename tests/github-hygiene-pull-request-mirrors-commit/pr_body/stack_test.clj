(ns pr-body.stack-test
  (:require [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [pr-body.stack :as stack]))

(def prs [{:number 1 :head "a" :base "main"}
          {:number 2 :head "b" :base "a"}
          {:number 3 :head "c" :base "b"}
          {:number 9 :head "x" :base "main"}])

(defn- stack-of [& ns] {"open" true "pull_requests" (mapv #(hash-map "number" %) ns)})

(deftest chain
  (testing "down to the default branch and up the single line above"
    (is (= {:numbers [1 2 3] :bottom-base "main"} (stack/chain prs 2 "main"))))
  (testing "a branch below with no open pull request"
    (is (= {:numbers [3] :bottom-base "b"} (stack/chain (remove #(= 2 (:number %)) prs) 3 "main"))))
  (testing "two pull requests on one branch end the line above"
    (is (= [1] (:numbers (stack/chain (conj prs {:number 4 :head "d" :base "a"}) 1 "main"))))))

(deftest linked
  (is (stack/linked? [(stack-of 1 2 3)] [1 2 3]))
  (is (stack/linked? [(stack-of 5 1 2 3)] [1 2]))
  (is (not (stack/linked? [(stack-of 2 1)] [1 2])))
  (is (not (stack/linked? [(assoc (stack-of 1 2) "open" false)] [1 2])))
  (is (not (stack/linked? [(stack-of 1) (stack-of 2)] [1 2]))))

(deftest verdict
  (testing "the default branch needs no stack"
    (is (nil? (stack/verdict {:prs prs :stacks [] :number 9 :base "main" :default "main"}))))
  (testing "linked"
    (is (nil? (stack/verdict {:prs prs :stacks [(stack-of 1 2 3)] :number 2 :base "a" :default "main"}))))
  (testing "unlinked: the command, bottom to top"
    (let [v (stack/verdict {:prs prs :stacks [] :number 2 :base "a" :default "main"})]
      (is (= "gh stack link 1 2 3" (:command v)))
      (is (str/includes? (:message v) "merging it would merge only into a"))))
  (testing "a chain that can't be linked has no command"
    (let [v (stack/verdict {:prs (remove #(= 2 (:number %)) prs) :stacks [] :number 3 :base "b" :default "main"})]
      (is (nil? (:command v)))
      (is (str/includes? (:message v) "has no open pull request")))))
