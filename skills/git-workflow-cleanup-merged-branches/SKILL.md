---
name: git-workflow-cleanup-merged-branches
description: |
  After merging your own branch into main, delete the local and remote
  copies. When noticing merged branches the session didn't create,
  prompt via AskUserQuestion before bulk-deleting — some teams keep
  merged branches as release markers. Apply post-merge or when
  `git branch --merged` shows stragglers.
tags: [workflow, interactive]
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# git-workflow-cleanup-merged-branches

## How to load this skill

Passive reference. Loading it doesn't mean you should delete branches
now — just that after merging or when noticing stragglers, you'll apply
the right cleanup.

## After merging your own branch into main

1. Delete the local branch: `git branch -d <branch>` (use `-d`, not
   `-D` — the lowercase form refuses if the branch isn't merged, which
   is the safety check you want).
2. Delete the remote branch: `git push origin --delete <branch>` (or
   enable auto-delete on the hosting platform; see
   `github-policy-auto-delete-merged-branches`).

## When you notice merged branches this session didn't create

For example, from `git branch --merged main` or `git branch -r --merged
origin/main` showing branches whose tips are reachable from main, flag
them to the user and ask before cleaning up. Never auto-delete branches
the user didn't explicitly ask you to clean up in this session, even if
Git reports them as merged. Some teams keep merged branches around as
release markers or for historical reasons.

### Question to ask

**Entity type:** multi-select (one option per branch the user can
individually check or uncheck; "All" and "None" convenience options
allowed).

**Question text** (literal start fixed; dynamic parts in `[brackets]`):

> Delete these branches already merged into `[base-branch]`?

**Option text** (one per branch; literal start fixed per category):

- `Delete local branch [branch-name]`
- `Delete remote branch [branch-name]`

The literal prefix (`Delete these branches already merged into` /
`Delete local branch` / `Delete remote branch`) is fixed so the
question is recognisable across sessions and pre-selection by prior
answers stays deterministic. Only the bracketed segments vary.

## Useful detection commands

```bash
git fetch --prune origin
git branch --merged main | grep -v '^\*\|^  main$\|^  master$'
git branch -r --merged origin/main | grep -v 'origin/HEAD\|origin/main\|origin/master'
```

## When to apply

- Just merged a PR — clean up the source branch.
- `git branch --merged main` shows stragglers — ask before bulk-delete.
- About to push, and you've been merging from main locally — fetch
  with `--prune` to drop tracking refs whose remote branches are gone.
