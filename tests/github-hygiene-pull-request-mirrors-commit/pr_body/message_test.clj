(ns pr-body.message-test
  (:require [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [pr-body.message :as message]))

(deftest kept-trailers
  (let [commits [{:trailers [{:key "Signed-off-by" :value "A"} {:key "Co-authored-by" :value "B"}
                             {:key "Multi-commit" :value "run-snapshot"}]}
                 {:trailers [{:key "Co-Authored-By" :value "B"} {:key "Fixes" :value "#2"}]}]]
    (is (= [] (message/kept-trailers commits :drop)))
    (is (= ["Signed-off-by: A" "Co-authored-by: B" "Fixes: #2"] (message/kept-trailers commits :keep)))))

(deftest range-problems
  (is (= ["aaaaaaa is a fixup! commit: squash it first"
          "bbbbbbb is a merge commit: rebase the branch instead"]
         (message/range-problems [{:sha "aaaaaaaa" :subject "fixup! x" :parents ["1"]}
                                  {:sha "bbbbbbbb" :subject "Merge" :parents ["1" "2"]}
                                  {:sha "cccccccc" :subject "Fine" :parents ["1"]}]))))

(deftest preferences
  (is (= message/default-policy (message/policy [])))
  (is (= {:multiple-commits :warn :allowed-reasons ["run-snapshot"]}
         (message/policy ["- Multiple commits: warn\n- Allowed reasons: refactor-split\n"
                          "- **Allowed reasons:** `run-snapshot`\n"]))))

(def two [{:sha "1" :trailers []} {:sha "2" :trailers []}])
(def with-reason (assoc-in two [1 :trailers] [{:key "Multi-commit" :value "run-snapshot"}]))

(deftest multi-commit-verdict
  (testing "one commit is always fine"
    (is (= :ok (:level (message/multi-commit-verdict (take 1 two) message/default-policy "main")))))
  (testing "refuse, naming the skill and the squash commands"
    (let [{:keys [level] :as v} (message/multi-commit-verdict two message/default-policy "main")]
      (is (= :refuse level))
      (is (str/includes? (:message v) "github-hygiene-single-commit-pull-requests"))
      (is (str/includes? (:message v) "git reset --soft $(git merge-base origin/main HEAD)"))
      (is (str/includes? (:message v) "--force-with-lease"))))
  (testing "the commit carrying the trailer leads"
    (is (= "2" (:sha (message/multi-commit-lead with-reason))))
    (is (nil? (message/multi-commit-lead two))))
  (testing "an allowed reason in any commit's trailer"
    (is (= :ok (:level (message/multi-commit-verdict with-reason message/default-policy "main")))))
  (testing "a reason the preferences don't allow"
    (is (= :refuse (:level (message/multi-commit-verdict
                            with-reason
                            (assoc message/default-policy :allowed-reasons ["refactor-split"]) "main")))))
  (testing "warn and allow"
    (is (= :warn (:level (message/multi-commit-verdict two (assoc message/default-policy :multiple-commits :warn) "main"))))
    (is (= :ok (:level (message/multi-commit-verdict two (assoc message/default-policy :multiple-commits :allow) "main"))))))
