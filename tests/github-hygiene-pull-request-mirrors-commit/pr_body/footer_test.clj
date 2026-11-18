(ns pr-body.footer-test
  (:require [clojure.test :refer [deftest is testing]]
            [pr-body.footer :as footer]
            [pr-body.sync :as sync]))

(def head "0123456789abcdef0123456789abcdef01234567")

(deftest assemble-and-parse
  (let [body (footer/assemble "Some body." head "attribution")]
    (is (= {:above "Some body." :head head :digest (footer/sha256 "Some body.")}
           (footer/parse body)))
    (is (= :untouched (footer/edit-status body)))
    (is (= :edited (footer/edit-status (str "Edited. " body))))
    (is (= :unmarked (footer/edit-status "Written by hand.")))
    (is (= :empty (footer/edit-status "")))))

(deftest no-attribution-keeps-the-marker
  (is (re-find #"^Body\.\n\n\[//\]: # \(pr-body: generated from [0-9a-f]+; digest [0-9a-f]{64}\)$"
               (footer/assemble "Body." head nil))))

(deftest sync-plan
  (let [rendered {:title "T" :body (footer/assemble "New." head "a")}
        untouched {:title "T" :body (footer/assemble "Old." head "a")}
        edited {:title "T" :body (str "Hand. " (:body untouched))}]
    (testing "no pull request" (is (= :create (:action (sync/plan nil rendered false [])))))
    (testing "in sync" (is (= :none (:action (sync/plan rendered rendered false [])))))
    (testing "as generated" (is (= :patch (:action (sync/plan untouched rendered false [])))))
    (testing "edited by hand" (is (= {:action :refuse :status :edited} (sync/plan edited rendered false []))))
    (testing "forced" (is (= :patch (:action (sync/plan edited rendered true [])))))
    (testing "a title change alone is drift"
      (is (= :patch (:action (sync/plan (assoc rendered :title "Old") rendered false [])))))))

(deftest bodies-older-tools-generated
  (let [commits [{:subject "Fix it" :body "Why it\nbroke."
                  :raw-body "Why it\nbroke.\n\nCo-Authored-By: C <c@x>"}
                 {:subject "Test it" :body "" :raw-body ""}]
        rendered {:title "Fix it" :body (footer/assemble "New." head "a")}]
    (testing "the old script: %b reflowed, with the attribution line"
      (let [body "Why it broke.\n\nCo-Authored-By: C <c@x>\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)"]
        (is (= :generated (sync/status body commits)))
        (is (= {:action :patch :status :generated} (sync/plan {:title "Fix it" :body body} rendered false commits)))))
    (testing "gh pr create --fill on several commits"
      (is (= :generated (sync/status "- Test it\n- Fix it" commits)))
      (is (= :generated (sync/status "- Fix it\n- Test it\n" commits))))
    (testing "a body matching neither is refused"
      (is (= {:action :refuse :status :unmarked}
             (sync/plan {:title "Fix it" :body "Why it broke, and more."} rendered false commits))))))
