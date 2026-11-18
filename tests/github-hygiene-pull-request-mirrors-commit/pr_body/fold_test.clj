(ns pr-body.fold-test
  (:require [cheshire.core :as json]
            [clojure.string :as str]
            [clojure.test :refer [deftest is testing]]
            [pr-body.fold :as fold]
            [pr-body.footer :as footer]
            [pr-body.sync :as sync]))

(def head "0123456789abcdef0123456789abcdef01234567")
(def attribution "🤖 Generated with [Claude Code](https://claude.com/claude-code)")

(def rendered
  {:title "Retry a failed upload once"
   :body (footer/assemble
          (str "Uploads failed for good on a single dropped connection; one retry covers the "
               "common case. See [`up.clj:3`](https://github.com/o/r/blob/" head "/up.clj#L3).\n\n"
               "- the resumable endpoint retries too\n- the plain one doesn't")
          head attribution)})

(def save-command "gh pr view 7 --repo o/r --json number,title,body > <file>")

(defn- plan [body & [saved]]
  (sync/plan {:title (:title rendered) :body body} rendered [] saved))

(deftest folded-bodies-are-overwritten
  (testing "a hand-written body, rewrapped, its code reference unlinked, a trailer and a stack line"
    (let [body (str "Uploads failed for good on a single\ndropped connection; one retry covers the\n"
                    "common case. See `up.clj:3`.\n\n"
                    "* the plain one doesn't\n\n"
                    "Stacks on o/r#3 \"Older\"\n\n"
                    "Co-Authored-By: Ada <ada@example.com>\nReviewed-by: Bob <bob@example.com>\n\n"
                    attribution)]
      (is (empty? (fold/missing body (:body rendered))))
      (is (= :folded (sync/status body [] (:body rendered))))
      (is (= {:action :patch :status :folded} (plan body)))))
  (testing "an edited marked body whose edit is now in the commit"
    (let [body (footer/assemble (str "Uploads failed for good on a single dropped connection; one retry "
                                     "covers the common case.\n\n## Commits (2)\n\n- [`abcdef0`](u) A squashed commit")
                                "fedcba9" attribution)
          edited (str/replace body "common case." "common case. See `up.clj:3`.")]
      (is (= :edited (footer/edit-status edited)))
      (is (= {:action :patch :status :folded} (plan edited)))))
  (testing "an older render's body, with its Commits, What changes and Stacks on, edited by hand"
    (let [old (footer/assemble (str "Uploads failed for good on a single dropped connection; one retry "
                                    "covers the common case.\n\n"
                                    "## Commits (2)\n\n- [`abcdef0`](u) Retry a failed upload once\n"
                                    "- [`abcdef1`](u) Bump nixpkgs\n\n"
                                    "## What changes\n\n### `flake.lock`\n\n"
                                    "| Input | Revision |\n| ----- | -------- |\n"
                                    "| `nixpkgs` | `aaaaaaa` → `bbbbbbb` |\n\n"
                                    "Stacks on o/r#3 \"Older\"")
                               "fedcba9" attribution)
          edited (str/replace old "common case." "common case. See `up.clj:3`.")]
      (is (= {:action :patch :status :untouched} (plan old)))
      (is (= :edited (footer/edit-status edited)))
      (is (empty? (fold/missing edited (:body rendered))))
      (is (= {:action :patch :status :folded} (plan edited))))))

(deftest unfolded-bodies-are-refused
  (let [body "Uploads failed for good on a single dropped connection\n\nReviewer note: also covers the resumable endpoint."
        refused (plan body)
        message (sync/refusal {:label "PR #7 (o/r)" :live {:body body} :rendered rendered
                               :status (:status refused) :save-command save-command})]
    (is (= ["Reviewer note: also covers the resumable endpoint."] (fold/missing body (:body rendered))))
    (is (= {:action :refuse :status :unmarked} refused))
    (is (str/includes? message "\"Reviewer note: also covers the resumable endpoint.\""))
    (is (str/includes? message "Fold it into the commit message"))
    (is (str/includes? message "--dropped-text-saved <file>"))
    (is (not (str/includes? (str/replace message "--force-with-lease" "") "--force")))
    (testing "a trailer-looking line inside prose is still text"
      (is (= ["Note: keep this. And this too."]
             (fold/missing "Note: keep this.\nAnd this too." (:body rendered)))))
    (testing "a table and a code block count"
      (is (= ["a | b" "x | y" "make it"]
             (fold/missing "| a | b |\n| - | - |\n| x | y |\n\n```\nmake it\n```" (:body rendered)))))))

(deftest dropped-text-needs-a-backup-holding-the-live-body
  (let [body "An old commit's text, no longer true.\n\nOne retry covers the common case."
        backup (json/generate-string {:number 7 :title "Old" :body body})]
    (testing "gh pr view --json output holding the body"
      (is (= {:action :patch :status :saved} (plan body {:path "b.json" :text backup :number 7}))))
    (testing "a text file holding the body"
      (is (= {:action :patch :status :saved}
             (plan body {:path "b.md" :text (str "# Old\n\n" body "\n") :number 7}))))
    (testing "another pull request's backup"
      (is (= {:action :refuse :status :not-saved} (plan body {:path "b.json" :text backup :number 8}))))
    (testing "a backup of another body"
      (is (= {:action :refuse :status :not-saved}
             (plan body {:path "b.json" :text (json/generate-string {:number 7 :body "Other."}) :number 7})))
      (is (str/includes? (sync/refusal {:label "PR #7 (o/r)" :live {:body body} :rendered rendered
                                        :status :not-saved :save-command save-command :saved-path "b.json"})
                         "b.json doesn't hold PR #7 (o/r)'s live body")))
    (testing "a folded body needs no backup, and an unfolded one without a backup is refused"
      (is (= {:action :refuse :status :unmarked} (plan body))))))
