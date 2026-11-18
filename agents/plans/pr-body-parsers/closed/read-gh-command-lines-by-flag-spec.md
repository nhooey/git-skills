---
title: Read gh command lines in the write guard by a spec of gh's flags
state: implemented
kind: implementation
part-of: pr-body-program-reads-formats-with-libraries
implemented-by: nhooey/git-skills#113
touches: [skills/github-hygiene-pull-request-mirrors-commit/scripts/src/pr_body/guard.clj]
---

# Read gh command lines in the write guard by a spec of gh's flags

`pr-body.guard/gh-flags` declares the flags of `gh pr create`, `gh pr
edit` and `gh api`, as `gh`'s own `--help` lists them: which take a
value and which don't. `clojure.tools.cli`, which Babashka includes,
parses each command's words by that spec, short flags bundled (`-df`)
and attached (`-XPATCH`) included, and the guard decides from the
parsed options and arguments.

`babashka.cli` reads neither bundled nor attached short flags, which is
why the guard's spec is for `clojure.tools.cli` while the program's own
command line stays on `babashka.cli`.

## Check

`bats test/guard.bats` passes, and the only flags `guard.clj` names are
in `gh-flags` and the keys read from its parse.
