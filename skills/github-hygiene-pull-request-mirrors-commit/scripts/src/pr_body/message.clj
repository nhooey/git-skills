(ns pr-body.message
  "Commit messages, as `pr-body.commits` reads them: the trailers a body
  keeps, the ranges the program refuses, and the single-commit policy of
  `github-hygiene-single-commit-pull-requests`."
  (:require [clojure.string :as str]
            [pr-body.preferences :as preferences]))

(def multi-commit-key "multi-commit")

(defn kept-trailers
  "The trailers to end the body with: none with `policy` `:drop` (the
  default, since the attribution footer is the body's one attribution
  line and the commit keeps its trailers), or with `:keep` each one in
  order of first appearance across `commits`, once. The `Multi-commit:`
  trailer is never kept: it's read by the program, not shown."
  [commits policy]
  (->> commits
       (mapcat :trailers)
       (remove #(= multi-commit-key (str/lower-case (:key %))))
       (filter (fn [_] (= policy :keep)))
       (reduce (fn [[seen acc] {:keys [key value] :as t}]
                 (let [id [(str/lower-case key) (str/trim value)]]
                   (if (seen id) [seen acc] [(conj seen id) (conj acc t)])))
               [#{} []])
       second
       (map #(str (:key %) ": " (:value %)))))

(defn range-problems
  "Why a range can't make a pull request body: each fixup!, squash! or
  amend! commit and each merge commit."
  [commits]
  (vec (concat
        (for [{:keys [sha subject]} commits
              :let [kind (some #(when (str/starts-with? subject (str % "! ")) %) ["fixup" "squash" "amend"])]
              :when kind]
          (str (subs sha 0 7) " is a " kind "! commit: squash it first"))
        (for [{:keys [sha parents]} commits
              :when (> (count parents) 1)]
          (str (subs sha 0 7) " is a merge commit: rebase the branch instead")))))

;; --- the single-commit policy -----------------------------------------

(def default-policy
  {:multiple-commits :refuse
   :allowed-reasons ["refactor-split" "vendored-import" "run-snapshot"]})

(defn policy
  "The policy from the texts of `github-hygiene-single-commit-pull-requests`
  preferences files, the user's first and the project's last, each key
  from the last file that sets it: `- Multiple commits:
  refuse|warn|allow` and `- Allowed reasons: a, b, c`."
  [texts]
  (let [reasons (preferences/value texts "allowed reasons")]
    (cond-> (assoc default-policy :multiple-commits
                   (preferences/choice texts "multiple commits" ["refuse" "warn" "allow"]
                                       (:multiple-commits default-policy)))
      reasons (assoc :allowed-reasons (vec (remove str/blank? (map str/trim (str/split reasons #","))))))))

(defn multi-commit-reason [commit]
  (some #(when (= multi-commit-key (str/lower-case (:key %))) (str/trim (:value %)))
        (:trailers commit)))

(defn multi-commit-lead
  "The commit that carries the `Multi-commit:` trailer, or nil."
  [commits]
  (first (filter multi-commit-reason commits)))

(defn multi-commit-verdict
  "`{:level :ok|:warn|:refuse :message s}` for a range of `commits`
  under `policy`: several commits need one that carries an allowed
  `Multi-commit:` reason. `base` names the base branch in the squash
  commands."
  [commits {:keys [multiple-commits allowed-reasons]} base]
  (let [reason (some-> (multi-commit-lead commits) multi-commit-reason)
        allowed? (some #{reason} allowed-reasons)]
    (if (or (<= (count commits) 1) allowed? (= multiple-commits :allow))
      {:level :ok}
      {:level multiple-commits
       :message (str/join
                 "\n"
                 [(str "github-hygiene-single-commit-pull-requests: this range holds "
                       (count commits) " commits and "
                       (if reason
                         (str "its reason `Multi-commit: " reason "` isn't allowed")
                         "no commit carries a `Multi-commit:` reason")
                       " (allowed: " (str/join ", " allowed-reasons) ").")
                  "Squash it into one commit, then push and re-sync:"
                  (str "  git rebase --autosquash origin/" base)
                  (str "  or: git reset --soft $(git merge-base origin/" base " HEAD) && git commit")
                  "  git push --force-with-lease"])})))
