---
name: git-hygiene-conventional-commits
description: |
  Use the `type(scope): subject` Conventional Commits format for commit
  subjects (type ∈ feat, fix, docs, refactor, chore, …), with `!` or a
  `BREAKING CHANGE:` footer for breaking changes. Use when the repo's
  existing `git log` already follows Conventional Commits, or when a team
  has explicitly adopted it. Match the repo's existing convention first;
  consistency within a repo beats matching an external standard.
tags: [style, team-stance]
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# Conventional Commits

_In a repo that has adopted Conventional Commits, each subject opens with `type(scope):`, and a breaking change is marked so changelog tools see it._

Some repos use Conventional Commits, some have their own convention, and
some have none. This applies only where the repo or team has adopted it.

## The rule

Use `type(scope): subject` format for the commit subject:

- **type:** `feat` or `fix`, the two the specification defines, or one of
  the widely used extras from `@commitlint/config-conventional`: `docs`,
  `refactor`, `chore`, `test`, `perf`, `build`, `ci`, `style`, `revert`.
  Teams sometimes add their own.
- **scope:** a short identifier of the affected area (`auth`, `parser`,
  `ci`). Optional, but useful when more than one subsystem is in play.
- **subject:** an imperative-mood description of the change. Start it
  lower-case unless the repo's history capitalizes it, since
  `@commitlint/config-conventional` rejects a capitalized subject; this
  overrides the capitalized subject in `git-hygiene-commit-message-format`.
- **Breaking change:** add `!` before the colon (`feat(api)!: drop v1
  routes`), or a `BREAKING CHANGE: <description>` footer, or both. Either
  works with any type.

The format signals intent at a glance and feeds changelog and release
tools such as release-please.

## Match existing convention first

If a repo's `git log` already follows a different convention (e.g. Linux
kernel style, "Topic: subject", ticket-prefixed), match it instead.
Consistency within a repo beats matching an external standard.

## Budget tighter

The `type(scope):` prefix eats into the ~50-char budget from
`git-hygiene-commit-message-format`. Tighten the summary side rather than
allowing the subject past 72.

## When to apply

- Writing a commit in a repo that uses Conventional Commits.
- Reviewing a PR's commit subject in such a repo.
- Onboarding a new repo where the team wants Conventional Commits adopted.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `git-hygiene-commit-message-format`: the base subject and body rules (72-char budget, why over what) that the Conventional Commits prefix has to fit inside.
