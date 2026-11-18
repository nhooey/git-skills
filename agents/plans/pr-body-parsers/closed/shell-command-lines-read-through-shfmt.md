---
title: The write guard reads shell command lines through shfmt --to-json
state: implemented
kind: implementation
part-of: pr-body-program-reads-formats-with-libraries
implemented-by: nhooey/git-skills#113
touches: [skills/github-hygiene-pull-request-mirrors-commit/scripts/src/pr_body/guard.clj, skills/github-hygiene-pull-request-mirrors-commit/script-inputs.nix]
---

# The write guard reads shell command lines through shfmt --to-json

The compromise taken in place of `write-clojure-shell-parser-library`, pinned through `script-inputs.nix`.

`pr-body.guard/commands` runs `shfmt --to-json` on the command line and
walks the JSON syntax tree for `CallExpr` nodes, so the hook starts a
`shfmt` process on each Bash call that mentions `gh pr` or `gh api`, and
needs `shfmt` on its path.
