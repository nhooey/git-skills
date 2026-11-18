(ns pr-body.cli-test
  (:require [clojure.string :as str]
            [clojure.test :refer [deftest is]]
            [pr-body.cli :as cli]))

(deftest modes
  (is (= {:mode "sync" :opts {}} (cli/parse [])))
  (is (= {:mode "check" :opts {:quiet true}} (cli/parse ["check" "--quiet"])))
  (is (= {:mode "render" :opts {:range "a..b" :trailers :keep}}
         (cli/parse ["render" "--range" "a..b" "--trailers" "keep"])))
  (is (= {:mode "check" :opts {:pr 12}} (cli/parse ["check" "--pr" "12"]))))

(deftest errors
  (is (= {:help true} (cli/parse ["sync" "--help"])))
  (is (= {:error "unknown option: --bogus"} (cli/parse ["--bogus"])))
  (is (= {:error "--base needs a value"} (cli/parse ["--base"])))
  (is (= {:error "--trailers takes keep or drop, not some"} (cli/parse ["--trailers" "some"])))
  (is (= {:error "--range takes <a>..<b>, not main"} (cli/parse ["--range" "main"])))
  (is (= {:error "--stack-parent takes a pull request number, not x"} (cli/parse ["--stack-parent" "x"])))
  (is (= {:error "--pr takes a pull request number, not x"} (cli/parse ["--pr" "x"])))
  (is (:error (cli/parse ["--footer" "f" "--no-footer"])))
  (is (:error (cli/parse ["--quiet" "check"])))
  (is (:error (cli/parse ["deploy"])))
  (is (:error (cli/parse ["--pr" "3" "--head" "b"]))))

(deftest help-lists-every-option
  (doseq [k (keys cli/spec)]
    (is (str/includes? cli/usage (str "--" (name k))))))
