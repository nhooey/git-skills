---
title: Write a Clojure library that parses Bash command lines
state: proposed
kind: implementation
part-of: pr-body-program-reads-formats-with-libraries
touches: [skills/github-hygiene-pull-request-mirrors-commit/scripts/src/pr_body/guard.clj, skills/github-hygiene-pull-request-mirrors-commit/script-inputs.nix]
---

# Write a Clojure library that parses Bash command lines

## The ideal

A Clojure library in its own repository, packaged in Nix, parses a Bash
command line into a syntax tree: simple commands with their words
unquoted, assignments, redirections and here-documents, pipelines,
lists, subshells and substitutions. `pr-body.guard` walks that tree in
process.

## In place now

The compromise taken, `shell-command-lines-read-through-shfmt`.

## Do it when

The guard's start-up time on those calls matters, `shfmt`'s JSON format
changes, or another program here needs to read shell command lines.

## Done when

`pr-body.guard` calls the library, `shfmt` is gone from
`script-inputs.nix`, and no comment names this node.
