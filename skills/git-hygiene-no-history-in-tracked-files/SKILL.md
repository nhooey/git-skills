---
name: git-hygiene-no-history-in-tracked-files
description: |
  Every file tracked in git states the current state; how it got there
  goes in the commit message that made the change. Covers code comments,
  READMEs and docs, skills (SKILL.md), plans, config and scripts: no
  "added in v3.2", "this used to do X", "TODO remove after the
  migration", dated rulings tables, quotes of who asked for a rule and
  when, or "changed from X to Y" notes. CHANGELOG.md, release notes,
  ADRs, decision logs and user migration guides are exempt. Load before
  adding a historical note to any tracked file, and when reviewing one.
tags: [style]
allowed-tools:
  - Read
  - Edit
---

# git-hygiene-no-history-in-tracked-files

A tracked file says what is true now. How it got that way belongs in the
commit message that made the change: git is already the record over
time, and `git log` and `git blame` put that record next to every line.
History written into the file itself rots. Later edits drift past it,
it contradicts the text around it, and readers stop trusting the file.

## How to load this skill

Passive reference. Loading it doesn't mean the user wants you to edit a
file right now — just that when a historical note seems called for,
you'll put it in the commit message instead.

## Which files

Every file git tracks, not only source:

- Code comments and docstrings.
- READMEs, docs and help text.
- Skills (`SKILL.md`) and agent instructions (`CLAUDE.md`, `AGENTS.md`).
- Plans and design notes describing work still to do.
- Config files and their comments.
- Scripts and their usage text.

## What to leave out

- Version notes: "added in v3.2", "new since the refactor".
- Past states: "this used to do X", "we used to call this Y".
- Change notes: "changed from X to Y", "renamed from `foo`",
  "previously 30s, now 60s".
- TODOs tied to past events: "TODO remove after the migration".
- Dated rulings tables: "2026-03-04: decided to ...".
- Provenance: quotes of who asked for a rule and when ("per Alice in
  standup, 3 March").

## What stays

A reason the reader needs in order to apply the rule or use the code,
written as a reason rather than a story:

- Keep: "Retries cap at 5 because the upstream rate-limits at 6 a
  minute."
- Drop: "We raised retries to 5 after the outage in March."

The first tells the reader what would break if they changed it. The
second tells them what happened, which is the commit message's job.

## Instead

- Put the historical context in the commit message body. `git log`,
  `git blame -w -C -C`, and `git log -L :function:file` will surface it
  later for anyone who needs it.
- If a specific line really needs a pointer, leave a short reference
  rather than the history itself: e.g., `// see commit log for
  migration context` or `// blame this line for rationale`. Then a
  reader can run `git blame <file>` on the line to find the commit and
  read its full message.

## The test

If you delete the note, does a curious reader lose anything they
couldn't recover from `git log` / `git blame`? If no, don't write it.

## Files that are a record over time

Some files exist to be the history: `CHANGELOG.md`, release notes,
architecture decision records (ADRs) and decision logs, and migration
guides for users moving between versions. Leave their history as it
is. The same goes for a plan that records work already done. This rule
is about every other file.

## When to apply

- About to add a historical note to any tracked file: a comment, a
  README line, a skill, a plan, a config comment.
- Reviewing a file that documents its own past states.
- Cleaning up TODOs tied to old migrations.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `git-hygiene-commit-message-format`: where the history goes instead, in a body that explains why.
