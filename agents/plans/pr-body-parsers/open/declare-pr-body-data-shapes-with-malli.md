---
title: Declare the PR body program's data shapes with Malli
state: proposed
kind: implementation
part-of: pr-body-program-holds-only-its-own-rules
touches: [skills/github-hygiene-pull-request-mirrors-commit/scripts/src/pr_body, skills/github-hygiene-pull-request-mirrors-commit/script-inputs.nix]
cost: about 1.5M tokens, $1.50, 0.02% of the weekly limit
---

# Declare the PR body program's data shapes with Malli

## What it would be

Malli schemas for a commit, a pull request as `gh` gives it, the render
options and the preferences, checked where each enters the program, and
used to coerce `gh`'s JSON and the preferences' values.

## Why the program has none

- **There are no hand checks for it to replace.** `babashka.cli`
  validates and coerces the command line, `git log --format` shapes the
  commits, `gh --json --jq` shapes the pull requests, and the
  preferences' only check is `preferences/choice`, one function. Schemas for
  the 4 shapes add about 40 lines and remove about 10.
- **Babashka doesn't include Malli,** so it would be the program's first
  source dependency, pinned through `script-inputs.nix` and put on the
  classpath by the entry point and both hooks.

## Do it when

A shape gains a second reader, such as a Python port that shares the
schemas as JSON Schema, or a malformed `gh` reply reaches the render.

## Done when

Each shape is one schema, checked at the edge it enters by, and
`preferences/choice` is gone.
