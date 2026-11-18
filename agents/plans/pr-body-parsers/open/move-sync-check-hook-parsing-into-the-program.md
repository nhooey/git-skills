---
title: Move the sync check hook's parsing into the program
state: proposed
kind: implementation
part-of: pr-body-program-reads-formats-with-libraries
touches: [skills/github-hygiene-pull-request-mirrors-commit/scripts/pull-request-sync-check.sh]
---

# Move the sync check hook's parsing into the program

## The ideal

`pull-request-sync-check.sh` is a thin shim like the write guard's: it
gates on builtins and hands the payload to a `pr-body` namespace, which
reads the push mode from the preferences files with
`pr-body.preferences`, and the pull request's repository from `gh`'s
JSON, and decides what to say.

## Done instead

The hook reads the push mode from the preferences files with `awk`, and
the repository from the pull request's URL with `sed`.

## Do it when

The hook's preferences grow another key, or a pull request URL it
misreads turns up.

## Done when

The hook holds no `sed` or `awk` over its inputs, its tests in
`tests/github-hygiene-pull-request-mirrors-commit/sync-check.bats` pass
unchanged, and no comment names this node.
