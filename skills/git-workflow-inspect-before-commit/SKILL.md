---
name: git-workflow-inspect-before-commit
description: |
  Before turning working-tree changes into a commit, walk three steps:
  inspect (`git status` / `git diff`), stage only what belongs (`git add
  -p` for mixed changes), and review the cached diff (`git diff --cached`)
  for secrets, debug logging, and unintended formatting churn. Apply
  whenever about to `git commit`.
tags: [workflow]
allowed-tools:
  - Bash
  - Read
---

# git-workflow-inspect-before-commit

Before turning a working-tree change into a commit, walk three small
steps. None of them takes more than a few seconds; together they catch
the failure modes that show up later as "why is this in my diff?", "why
did I commit my `.env`?", or "this commit does three things at once."

## How to load this skill

Passive reference. Loading it doesn't mean the user wants you to commit
right now — just that when a commit comes up, you'll walk these steps
first.

## 1. Inspect before staging

```bash
git status         # what changed
git diff           # what the changes are
git diff --stat    # if the diff is too large to scan inline
```

Don't reach for `git add` before reading these. Surprises in `git diff`
— a stray `console.log`, an editor's auto-format-on-save, a secret that
crept in — are cheap to undo before staging and expensive to undo after
committing.

## 2. Stage only what belongs in this commit

When the changes are clean and all belong together, `git add <paths>` is
fine. When the working tree mixes concerns (refactor + feature,
formatting + logic, tests + prod code), stage by hunks instead:

```bash
git add -p                   # iterate hunk-by-hunk, accept/reject each
git restore --staged -p      # unstage by hunk
git restore --staged <path>  # unstage a file
```

The 1-2-sentence test (step 3) is the forcing function for whether to
split: if you can't describe the staged change in 1-2 sentences (what +
why), the commit is mixed; unstage some hunks and write a separate
commit for them.

## 3. Review what will actually be committed

```bash
git diff --cached    # the diff that's about to be committed
```

Scan for three failure modes that often slip past `git diff` in step 1
but become embarrassing after the push:

- **Secrets / tokens.** Hard-coded API keys, `.env` files, `id_rsa`,
  anything with `password=` or `token=` followed by a long random
  string.
- **Debug logging.** `console.log`, `print(...)`, `dbg!`, commented-out
  experiments left over from local poking.
- **Unrelated formatting churn.** A reformatter ran on save and
  rewrote 200 lines you didn't intend to touch. Either separate the
  reformat into its own commit (per step 2) or revert it.

If the repo has a fast meaningful check (a typecheck on the staged
files, a unit-test subset, a `lint --since=HEAD`), run it here too —
cheaper to find a broken commit before it lands in history than after
it does.

If any of these surface a problem, fix and re-stage. Don't commit "and
clean it up next time" — next time is harder.

## When to apply

- About to stage and commit changes.
- Reviewing your own working tree before pushing.
