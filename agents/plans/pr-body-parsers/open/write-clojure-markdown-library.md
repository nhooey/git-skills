---
title: Write a Clojure Markdown library with source positions and a writer
state: proposed
kind: implementation
part-of: pr-body-program-reads-formats-with-libraries
touches: [skills/github-hygiene-pull-request-mirrors-commit/scripts/src/pr_body/markdown.clj, skills/github-hygiene-pull-request-mirrors-commit/script-inputs.nix]
---

# Write a Clojure Markdown library with source positions and a writer

## The ideal

A Clojure library in its own repository, packaged in Nix, parses
GitHub-flavoured Markdown the way GitHub renders it, gives every block
and inline node its exact source position, and writes a tree back out
as Markdown. `pr-body.markdown` parses commit bodies, subjects and
preferences files with it, changes the tree (joining paragraph lines,
linking code references) and writes the result.

## Needs

The parser with source positions is shared with document-skills' sentence-per-line check, so it is planned once, in github-config: [Write a Babashka Markdown library with source positions](https://github.com/nhooey/github-config/blob/master/agents/plans/open/write-babashka-markdown-library.md).
This node adds the writer to that library and moves `pr-body.markdown` onto it.

## In place now

The compromise taken, `markdown-read-through-cmark-gfm`.

## Do it when

Another program here needs to write Markdown rather than slice it, a
third `cmark-gfm` position bug turns up, or GitHub's renderer moves away
from `cmark-gfm`.

## Done when

`pr-body.markdown` calls the library, `cmark-gfm` is gone from
`script-inputs.nix`, and no comment names this node.
