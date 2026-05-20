---
name: git-commit-message-format
description: |
  Format commit messages with subject under 72 chars, blank line after the
  subject, body wrapped at 72 chars, and explain WHY rather than what.
  Apply whenever writing or amending any commit message. Pair with
  git-conventional-commits if the repo adopts that convention.
tags: [style]
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# git-commit-message-format

Apply this rule whenever you are about to create or amend a commit. The
goal is a readable history that future readers (including future-you) can
mine for context.

## How to load this skill

Passive reference, not a command. Loading it does **not** mean the user
wants you to commit right now. Do not run `git status`, stage files, or
create commits on load — just internalize the rule and apply it the next
time a commit comes up.

## The rule

- **First line under 72 characters.** Aim for ~50, hard cap at 72 — the
  50/72 convention from [Tim Pope's *A Note About Git Commit Messages*
  (2008)](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html),
  restated by [Chris Beams' *How to Write a Git Commit Message*](https://cbea.ms/git-commit/)
  and *Pro Git* §5.2. GitHub, `git log --oneline`, and most tools
  truncate or wrap past 72 (see `github-pr-mirrors-commit` for the
  empirical GitHub truncation). Use the imperative mood ("Add X", not
  "Added X").
- **Blank line after the first line.** Many tools rely on this to
  separate subject from body. No blank line means the body gets glued to
  the subject.
- **Wrap body lines at 72 characters.** `git log` indents the body by 4
  spaces, so wider lines wrap awkwardly in 80-column terminals.
- **Use the body to explain why, not what.** The diff already shows what
  changed. Spend the body on motivation, alternatives considered,
  landmines hit, and links to issues or discussions.

When writing a commit, draft the subject first, then add a blank line,
then write the body wrapped at 72. If a subject feels longer than 72,
the commit is probably doing too much — split it.

## When to apply

- About to write a commit message.
- About to amend an existing commit message.
- Reviewing someone else's commit message in a PR.
