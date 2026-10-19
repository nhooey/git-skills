---
name: git-hygiene-avoid-sweeping-operations
description: |
  Never run a git command that acts on everything it can reach instead of
  what you inspected: `git add -A` / `--all` / `.` / `-u`, `git commit -a`,
  bare `git stash`, `git checkout .` / `git restore .`, `git reset --hard`,
  `git clean -f`, `git branch -D`, `git push --all` / `--mirror`,
  `git worktree prune`, `git gc --prune=now`, `--no-verify`. Name the paths
  and refs instead, and prefer the variant that refuses when it would lose
  work. Apply whenever about to stage, stash, discard, delete, prune or
  push in a working tree that the user, another agent or another session
  may also be using.
tags: [safety]
allowed-tools:
  - Bash
---

# git-hygiene-avoid-sweeping-operations

A sweeping command acts on everything it can reach: every changed file,
every untracked file, every branch, every worktree. It is only safe if you
know everything it will reach, and in a working tree you share you don't.
The user may have edits in progress, another agent may be working in the
same checkout, a generator may have dropped files, and `.env` or local
config may be lying untracked. A sweep stages them, stashes them or
deletes them along with your own change.

The rule: **name the paths and refs you inspected and own**, and where a
command has a variant that refuses instead of losing work, use it.

## How to load this skill

Passive reference. Loading it doesn't mean the user wants you to run any
of these now — just that when you stage, discard, delete or push, you'll
name what you act on.

## Commands to avoid, and what to run instead

| Avoid | What it sweeps | Run instead |
| --- | --- | --- |
| `git add -A`, `--all`, `.`, `*`, `-u` | every changed and (except `-u`) untracked file, including others' edits, secrets and build output | `git add <paths>`, or `git add -p <paths>` for mixed files |
| `git commit -a`, `-am` | every tracked change, staged or not | `git add <paths>` then `git commit` |
| `git restore --staged .`, `git reset` (no path) | everything anyone staged | `git restore --staged <paths>` |
| `git stash`, `git stash -u` (no pathspec) | every change in the tree, others' included, into one entry they won't find | `git stash push -- <paths>`, or a separate worktree |
| `git stash drop`, `git stash clear` | stash entries you didn't create | `git stash list` first, then drop only your own entry by index |
| `git checkout .`, `git checkout -- .`, `git restore .` | every unstaged edit, with no undo | `git diff <path>`, then `git restore <path>` for the paths you changed |
| `git reset --hard` | every staged and unstaged change, with no undo | `git reset --keep <commit>`, which refuses if local changes would be lost |
| `git clean -f`, `-fd`, `-fdx` | every untracked file (`-x`: ignored too, like `.env` and local config) | `git clean -n` to list, then `rm` the named paths you created |
| `git branch -D` | a branch's unmerged commits | `git branch -d`, which refuses unless merged; see `git-workflow-cleanup-merged-branches` for bulk deletes |
| `git push --force` | the remote's commits you haven't fetched | `git push --force-with-lease`; see `git-hygiene-push-force-safely` |
| `git push --all`, `--mirror`, `--tags` | every local branch or tag, scratch ones included | `git push origin <branch>`, `git push origin <tag>` |
| `git checkout <branch>`, `git switch` in a shared checkout | the branch under every other process using that tree | `git worktree add .worktrees/<name> -b <branch>` |
| `git worktree remove --force`, `git worktree prune` | other sessions' worktrees and their uncommitted work | `git worktree remove <path>` for worktrees you created |
| `git gc --prune=now`, `git reflog expire --expire=now` | the reflog and dangling commits, the net for every mistake above | leave gc to git's defaults |
| `git commit --no-verify`, `git push --no-verify` | every hook's check | fix what the hook reports |
| `git config --global ...` | every repo on the machine | `git config --local ...`, or ask first |

## When the user asks for a sweep

If the user explicitly asks for `git add -A`, `git reset --hard` or
similar, show them what it will touch first (`git status`,
`git clean -n`, `git stash list`, `git branch --no-merged`), say what
would be lost, and run it only once they've seen that. An instruction to
"clean up" or "start fresh" is not a request for a sweep; name the paths.

## Enforcement

This repo also ships a [CC Safety Net](https://github.com/kenryu42/claude-code-safety-net)
rulebook, `.cc-safety-net/rules/git-avoid-sweeping-operations/rulebook.json`,
that blocks most of the commands above before they run. A block reason
tagged `[git-avoid-sweeping-operations/<rule>]` comes from it; take the
alternative it names rather than working around it.

## Why the refusing variants

`-d` over `-D`, `--keep` over `--hard`, `--force-with-lease` over
`--force`, `-n` before `-f`: each pair does the same thing when you were
right about the state, and refuses when you were wrong. When the safe
variant refuses, **stop and look** — don't upgrade to the sweeping one to
make the error go away.

## When to apply

- About to stage, commit, stash, discard, reset or clean.
- About to delete or prune a branch, tag, stash entry or worktree.
- About to push more than the one branch you're working on.
- Working in a checkout that the user, another agent or another session
  may also be using, which is the default assumption.
