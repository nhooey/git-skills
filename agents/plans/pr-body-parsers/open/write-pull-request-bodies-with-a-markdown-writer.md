---
title: Write pull request bodies with a Markdown writer
state: proposed
kind: implementation
part-of: pr-body-program-holds-only-its-own-rules
touches: [skills/github-hygiene-pull-request-mirrors-commit/scripts/src/pr_body/markdown.clj, skills/github-hygiene-pull-request-mirrors-commit/scripts/src/pr_body/links.clj]
cost: about 3M tokens, $3, 0.05% of the weekly limit
---

# Write pull request bodies with a Markdown writer

## What it would be

`pr-body.markdown` parses a commit body into a tree, joins soft breaks
and links code references in the tree, and has a library write the tree
back out. The source-position slicing, the byte-column arithmetic and
the 2 `cmark-gfm` position corrections go: about 240 lines of
`markdown.clj` and `links.clj`.

## Why the program slices instead

A writer normalises everything it writes, so the body stops being the
commit's own text. Run on the commit bodies in `tests/github-hygiene-pull-request-mirrors-commit/golden/`:

- **`pandoc --from gfm --to gfm --wrap=none`** escapes `#4` at a line
  start as `\#4`, writes `1.  ` for `1. `, turns ```` ```bash ```` into
  ```` ``` bash ````, makes a tight list after a paragraph loose, and
  reads a table that follows a paragraph directly as paragraph text,
  where GitHub renders a table.
- **`cmark-gfm --to commonmark`** escapes every `_`, `*`, `[` and `#`
  in text, as in `snake\_case` and `\#4`, which `markdown-hygiene-escape-reserved-characters`
  forbids.
- **commonmark-java's `MarkdownRenderer`** needs a JVM
  (`build-pr-body-program-as-native-jvm-binary`), and isn't the parser
  GitHub renders with.

Slicing by `cmark-gfm`'s positions changes only the lines the program
means to change, and reads Markdown exactly as GitHub will.

## Do it when

A writer exists that escapes only what must be escaped and parses as
`cmark-gfm` does, such as the library of `write-clojure-markdown-library`.

## Done when

`markdown.clj` holds no source positions, and every `expected.txt` in
`tests/github-hygiene-pull-request-mirrors-commit/golden/` is unchanged or differs only in bytes GitHub renders the
same.
