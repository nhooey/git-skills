---
name: git-hygiene-no-history-in-code
description: |
  Don't embed diachronic notes ("added in v3.2", "TODO remove after Q4
  migration", "this used to do X") in source. That context belongs in
  the commit message that introduced or changed the code. Apply when
  about to add any historical/migration-related comment, or when
  reviewing existing ones.
tags: [style]
allowed-tools:
  - Read
  - Edit
---

# git-hygiene-no-history-in-code

Resist embedding sentences like "added in v3.2", "TODO: remove after Q4
migration", "this used to do X but we changed it" into source files.
That kind of context belongs in the commit message that introduced or
changed the code. Once it lives in source, it rots: future edits drift,
comments contradict the code, and nobody trusts them.

## How to load this skill

Passive reference. Loading it doesn't mean the user wants you to edit
code right now — just that when a "historical note" comment would be
appropriate, you'll redirect that content to the commit message
instead.

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

If you delete the comment, does a curious reader lose anything they
couldn't recover from `git log` / `git blame`? If no, don't write it.

## When to apply

- About to add a "historical note" comment to code.
- Reviewing existing comments that document past states.
- Cleaning up TODO comments tied to old migrations.
