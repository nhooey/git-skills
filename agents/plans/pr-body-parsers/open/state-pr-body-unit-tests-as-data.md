---
title: State the PR body program's unit tests as data
state: proposed
kind: implementation
part-of: pr-body-program-holds-only-its-own-rules
touches: [tests/github-hygiene-pull-request-mirrors-commit]
cost: about 2M tokens, $2, 0.03% of the weekly limit
---

# State the PR body program's unit tests as data

## What it would be

The cases in `tests/github-hygiene-pull-request-mirrors-commit/pr_body/*_test.clj` become EDN beside
`tests/github-hygiene-pull-request-mirrors-commit/golden/`: each names a function, its arguments and the value it
returns, and one test reads them all. A Python port runs the same files.
About 150 fewer lines of test code.

## In place now

`tests/github-hygiene-pull-request-mirrors-commit/golden/` holds the render's cases as data, and
`pr-body.test-runner` finds the test namespaces itself. The unit tests
are `clojure.test` forms, 1 file per namespace.

## Do it when

A Python port starts, which needs the cases in a form both programs
read.

## Done when

`tests/github-hygiene-pull-request-mirrors-commit/pr_body/` holds the golden test, the data test and the runner, and
`bb test` makes the same assertions.
