(ns pr-body.stack
  "Whether a pull request based on a branch other than the default one
  sits in a linked GitHub stack. Merging the top of a linked stack merges
  the whole stack into the default branch; an unlinked chain only merges
  each pull request into the branch below it. So a pull request whose
  base isn't the default branch is linked into a stack with every open
  pull request it depends on and that depends on it.

  `prs` are the repository's open pull requests as `{:number :head
  :base}`; `stacks` are the repository's stacks as
  `GET repos/{owner}/{repo}/stacks` gives them, each with `open` and its
  `pull_requests` from bottom to top."
  (:require [clojure.string :as str]))

(defn chain
  "`{:numbers [n …] :bottom-base b}`: the pull request `number` with the
  open pull requests below it down to the one based on `default`, and the
  single line above it, bottom to top. `:bottom-base` is the base of the
  lowest one, which is `default` unless a branch below has no open pull
  request."
  [prs number default]
  (let [by-number (into {} (map (juxt :number identity) prs))
        by-head (group-by :head prs)
        by-base (group-by :base prs)
        this (by-number number)
        below (loop [pr this acc ()]
                (let [parent (first (by-head (:base pr)))]
                  (if (and parent (not= (:base pr) default) (not-any? #{parent} acc))
                    (recur parent (cons parent acc))
                    acc)))
        above (loop [pr this acc []]
                (let [children (by-base (:head pr))]
                  (if (and (= 1 (count children)) (not-any? #{(first children)} acc))
                    (recur (first children) (conj acc (first children)))
                    acc)))
        line (concat below [this] above)]
    {:numbers (mapv :number line)
     :bottom-base (:base (first line))}))

(defn- subsequence?
  "Whether `xs` appear in `ys` in the same order."
  [xs ys]
  (loop [xs (seq xs) ys (seq ys)]
    (cond (nil? xs) true
          (nil? ys) false
          (= (first xs) (first ys)) (recur (next xs) (next ys))
          :else (recur xs (next ys)))))

(defn linked?
  "Whether one open stack holds `numbers` in this order."
  [stacks numbers]
  (boolean
   (some (fn [s]
           (and (get s "open")
                (let [members (mapv #(get % "number") (get s "pull_requests"))]
                  (and (every? (set members) numbers) (subsequence? numbers members)))))
         stacks)))

(defn link-command [numbers] (str "gh stack link " (str/join " " numbers)))

(defn verdict
  "nil when pull request `number` (based on `base`) needs no stack or is
  in one; else `{:numbers :command :message}`, with no `:command` when
  the chain can't be linked because a branch below has no open pull
  request."
  [{:keys [prs stacks number base default]}]
  (when (and base default (not= base default))
    (let [{:keys [numbers bottom-base]} (chain prs number default)]
      (when-not (linked? stacks numbers)
        (if (= bottom-base default)
          {:numbers numbers
           :command (link-command numbers)
           :message (str "PR #" number " is based on " base ", not " default
                         ", and isn't in a linked GitHub stack, so merging it would merge only into "
                         base ". Link the chain, bottom to top:\n  " (link-command numbers))}
          {:numbers numbers
           :message (str "PR #" number " is based on " base ", not " default
                         ", and the chain below it ends at " bottom-base
                         ", which has no open pull request, so it can't be linked into a stack. "
                         "Open that branch's pull request, or rebase onto " default
                         " and retarget with gh pr edit --base " default ".")})))))
