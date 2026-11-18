(ns pr-body.test-runner
  "Runs every `*_test.clj` namespace beside this file for `bb test`,
  exiting non-zero on a failure."
  (:require [babashka.fs :as fs]
            [clojure.string :as str]
            [clojure.test :as t]))

(defn run []
  (let [namespaces (for [file (sort (fs/glob "test/pr_body" "*_test.clj"))]
                     (symbol (str "pr-body." (str/replace (fs/strip-ext (fs/file-name file)) "_" "-"))))
        _ (apply require namespaces)
        {:keys [fail error]} (apply t/run-tests namespaces)]
    (System/exit (if (zero? (+ fail error)) 0 1))))
