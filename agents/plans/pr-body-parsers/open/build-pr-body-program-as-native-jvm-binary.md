---
title: Build the PR body program as a native JVM Clojure binary
state: proposed
kind: implementation
part-of: pr-body-program-holds-only-its-own-rules
touches: [skills/github-hygiene-pull-request-mirrors-commit/scripts, skills/github-hygiene-pull-request-mirrors-commit/flake.nix, flake.nix]
cost: about 8M tokens, $8, 0.13% of the weekly limit
---

# Build the PR body program as a native JVM Clojure binary

## What it would be

The program is JVM Clojure, built into one binary by GraalVM
`native-image` through clj-nix, so it can load Java libraries that
Babashka can't. commonmark-java parses Markdown in process with source
spans for blocks and inlines, in characters, which removes the
`cmark-gfm` process, its XML, the UTF-8 byte columns and the 2 position
corrections: about 120 lines of `markdown.clj`, and `cmark-gfm` from
`script-inputs.nix`.

## Why the program stays on Babashka

- **It trades a parser for a build:** a `deps.edn`, a `deps-lock.json`
  and a clj-nix input in the skill's flake, the repository's flake and
  the hooks plugin, about 60 lines of Nix, and a `native-image` build of
  several minutes in `nix flake check` and on the first run from a
  checkout.
- **commonmark-java isn't the parser GitHub renders with,** so where the
  2 differ, such as a table that interrupts a paragraph, the body would
  be joined one way and rendered another.
- **No JVM library parses Bash,** so `shfmt` stays either way.
- **A Babashka pod** that wraps commonmark-java needs the same build,
  and adds the pod protocol.

Babashka already includes every other library the program uses.

## Do it when

The program needs a second Java library that Babashka can't load, or
`write-clojure-markdown-library` lands as a JVM library.

## Done when

`create-or-update-pull-request.sh` runs the binary, `cmark-gfm` is gone
from `script-inputs.nix`, and `test/golden/` passes unchanged.
