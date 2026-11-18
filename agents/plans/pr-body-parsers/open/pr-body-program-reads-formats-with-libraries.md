---
title: The PR body program reads every format with a parser library
state: proposed
kind: end-state
touches: [skills/github-hygiene-pull-request-mirrors-commit/scripts]
---

# The PR body program reads every format with a parser library

The Babashka program behind `create-or-update-pull-request.sh` and the
skill's two hooks reads each structured format it meets through a
Clojure library, used like any other dependency and pinned through Nix,
never through a hand-written parser or a command-line tool it shells
out to for parsing:

- commit bodies, subjects and preferences files as GitHub-flavoured
  Markdown, with source positions and a writer;
- the Bash command lines the write guard sees, as a syntax tree;
- `gh`'s own command lines inside them, by `gh`'s flag definitions;
- the sync check hook's inputs, read by the program rather than by
  `sed` and `awk` in the hook's Bash.

Git and `gh` stay the source of what they own: commit messages and
trailers (`git log --format`), diffs (`git diff --no-index`) and
repositories (`gh repo view --json`).

## Checks

- `git grep 'Compromise: plan node'` in the skill finds nothing.
- `script-inputs.nix` lists `babashka` and no parsing tool.
- `pull-request-sync-check.sh` holds no `sed` or `awk` over Markdown,
  JSON or URLs.
