(ns pr-body.footer
  "The footer that ends a generated body, and what it says about a live one.

  The footer is an invisible marker line, a Markdown link reference
  definition naming the head commit and the SHA-256 of the body above
  it, then the attribution line:

      [//]: # (pr-body: generated from <head-sha>; digest <sha256>)
      🤖 Generated with [Claude Code](https://claude.com/claude-code)

  A live body whose text above the marker still hashes to the marker's
  digest is as the program left it, so `sync` may regenerate it; any
  other body was edited by hand."
  (:require [clojure.string :as str])
  (:import (java.security MessageDigest)))

(def default-attribution "🤖 Generated with [Claude Code](https://claude.com/claude-code)")

(defn sha256 [^String s]
  (->> (.digest (MessageDigest/getInstance "SHA-256") (.getBytes s "UTF-8"))
       (map #(format "%02x" (bit-and % 0xff)))
       (apply str)))

(defn marker [head-sha digest]
  (str "[//]: # (pr-body: generated from " head-sha "; digest " digest ")"))

(def ^:private marker-line
  #"(?m)^\[//\]: # \(pr-body: generated from ([0-9a-f]+); digest ([0-9a-f]{64})\)$")

(defn assemble
  "The whole body: `above`, the marker, and `attribution` unless nil."
  [above head-sha attribution]
  (let [above (str/trimr above)]
    (str/join "\n\n" (remove str/blank? [above (str (marker head-sha (sha256 above))
                                                    (when attribution (str "\n" attribution)))]))))

(defn parse
  "`{:above :head :digest}` from a live body with a marker, else nil.
  The last marker counts."
  [body]
  (let [m (re-matcher marker-line (or body ""))
        found (last (take-while some? (repeatedly #(when (.find m) [(.start m) (.group m 1) (.group m 2)]))))]
    (when-let [[start head digest] found]
      {:above (str/trimr (subs body 0 start)) :head head :digest digest})))

(defn edit-status
  "`:empty`, `:untouched` (as generated), `:edited` (the text above the
  marker changed) or `:unmarked` (no marker: written by hand or by an
  older tool) for a live body."
  [body]
  (if (str/blank? body)
    :empty
    (if-let [{:keys [above digest]} (parse body)]
      (if (= digest (sha256 above)) :untouched :edited)
      :unmarked)))
