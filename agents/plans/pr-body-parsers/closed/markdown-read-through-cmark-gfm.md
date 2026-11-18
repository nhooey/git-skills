---
title: The PR body program reads Markdown through cmark-gfm --sourcepos
state: implemented
kind: implementation
part-of: pr-body-program-reads-formats-with-libraries
implemented-by: nhooey/git-skills#113
touches: [skills/github-hygiene-pull-request-mirrors-commit/scripts/src/pr_body/markdown.clj, skills/github-hygiene-pull-request-mirrors-commit/script-inputs.nix]
---

# The PR body program reads Markdown through cmark-gfm --sourcepos

The compromise taken in place of `write-clojure-markdown-library`, pinned through `script-inputs.nix`.

`pr-body.markdown/parse` runs `cmark-gfm --to xml --sourcepos` and reads
the XML. No writer is needed because `render` slices the source by
position and rewrites only the lines the program changes. Two
`cmark-gfm` position bugs are corrected in `parse`:

- a table that interrupts a paragraph gets the paragraph's start, and
  the paragraph none, so `parse` adds a blank line before the header row
  and parses again;
- inside a paragraph, a backslash hard break doesn't advance the line,
  so `parse` maps positions back onto the real lines.

The `autolink` extension stays off, as it gives the nodes it makes wrong
positions; bare URLs in text are matched as tokens in `pr-body.links`.
