---
name: github-pull-request-changeset-prompt
description: |
  After completing any change-set in the work tree, present a
  multi-select `AskUserQuestion` prompt (split into Local / Push /
  Follow-up sub-questions to fit the 4-option cap) covering Stage /
  Commit / Amend / Push / Force / Open-PR / Re-derive PR / Monitor.
  Pre-select from prior instance of the question in the session, or
  by context if no prior. Apply after every change-set; never auto-
  decide.
tags: [agent, interactive]
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# github-pull-request-changeset-prompt

Once you've made changes in the work tree, don't auto-decide whether
to stage, commit, push, or follow up on the PR. Present a multi-select
(checkbox) prompt via `AskUserQuestion` — `multiSelect: true`, never
single-select / radio — with the eight options listed below.

## How to load this skill

Active. Loading doesn't fire the prompt; the prompt fires after a
change-set lands in the work tree.

## The eight options, in order

- **Stage** — `git add` the changed files.
- **Commit** — new commit (`git commit`).
- **Amend** — fold into the last commit (`git commit --amend`).
- **Push** — regular `git push`.
- **Force** — `git push --force-with-lease` (see
  `git-hygiene-push-force-safely`).
- **Open Pull Request** — `gh pr create` per
  `github-hygiene-pull-request-mirrors-commit` (single commit, `--fill`-equivalent
  title and unwrapped body).
- **Re-derive PR name + title** — re-PATCH title and body per
  `github-hygiene-pull-request-mirrors-commit`.
- **Monitor + react** — arm or re-arm `github-pull-request-watcher`.

## Split into three questions (4-option cap)

`AskUserQuestion` caps each question at 4 options, so split into
three multi-select questions:

- **Local actions** — Stage, Commit, Amend.
- **Push actions** — Push, Force, Open Pull Request.
- **Follow-up** — Re-derive PR name + title, Monitor + react.

## Mutually exclusive pairs

Commit and Amend are mutually exclusive in the user's mind; if both
get checked, ask which they meant rather than guessing. Same for Push
and Force. Open Pull Request and Re-derive PR name + title are
likewise mutually exclusive — one applies when no PR yet exists, the
other when one already does.

## Pre-select from the last instance of this question within the session

Workflows repeat: refining a single-commit PR typically loops Stage +
Amend + Force + Re-derive PR name + title + Monitor, and re-clicking
those every iteration is friction. On the first ask of the session
(no prior instance), pre-select by context:

- New branch, no PR yet → Stage + Commit + Push + Open Pull Request
  + Monitor.
- Refining an existing PR → Stage + Amend + Force + Re-derive PR
  name + title + Monitor.
- Trivial doc edit, no PR → Stage + Commit + Push.

Resurface the question after every change-set; the user's last
answer is a hint, not a binding default.

## When to apply

- Finished any change-set in the work tree.
- About to push/commit and unsure which subset of operations the
  user wants this iteration.
