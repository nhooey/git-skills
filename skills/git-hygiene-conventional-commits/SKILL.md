---
name: git-hygiene-conventional-commits
description: |
  Use the `type(scope): subject` Conventional Commits format for commit
  subjects (type ∈ feat, fix, docs, refactor, chore, …). Apply when the
  repo's existing `git log` already follows CC, or when a team has
  explicitly adopted it. Match existing repo convention first; consistency
  within a repo beats matching an external standard.
tags: [style, team-stance]
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# git-hygiene-conventional-commits

A team-stance: some repos use Conventional Commits, some have their own
convention, and some have no convention at all. This skill applies when
you (or the team) have decided to adopt CC.

## How to load this skill

Passive reference. Loading it doesn't mean the user wants you to commit
right now — just that when a commit happens, the subject should follow
CC.

## The rule

Use `type(scope): subject` format for the commit subject:

- **type** — one of `feat`, `fix`, `docs`, `refactor`, `chore`, `test`,
  `perf`, `build`, `ci`, `style`, `revert` (the standard set; teams
  sometimes add their own).
- **scope** — short identifier of the affected area (`auth`, `parser`,
  `ci`). Optional but encouraged when more than one subsystem is in play.
- **subject** — imperative-mood description of the change.

The format compresses meta into the subject, signals intent at a glance,
and plays well with changelog generators (e.g. release-please,
standard-version).

## Match existing convention first

If a repo's `git log` already follows a different convention (e.g. Linux
kernel style, "Topic: subject", ticket-prefixed), match it instead.
Consistency within a repo beats matching an external standard.

## Budget tighter

The `type(scope):` prefix eats into the ~50-char budget from
`git-hygiene-commit-message-format`. Tighten the summary side rather than
allowing the subject past 72.

## When to apply

- Writing a commit in a repo that uses CC.
- Reviewing a PR's commit subject in such a repo.
- Onboarding a new repo where the team wants CC adopted.
