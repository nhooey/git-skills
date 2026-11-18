---
name: git-workflow-tidy-worktrees
description: |
  Tidy a repo's git worktrees with the `worktrees` program: `status` to see
  them, `sweep` to list what would go and `sweep --apply` to remove it,
  `finish` for one worktree, `clean --apply` to drop the build output of one
  that stays. Covers when to tidy, what to do when a build is refused for
  disk space, stale and personal locks, and what never goes without the
  user's word: uncommitted changes, unlanded commits, stashes and gitignored
  files nothing regenerates. Use after a branch lands, at the end of a job
  that made worktrees, when a build is refused below the disk floor, and
  when the user asks what worktrees are lying around.
tags: [workflow, interactive, safety]
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# Tidy worktrees

_The `worktrees` program decides what is safe to remove and removes it;
this skill says when to run it, and what to bring to the user instead.
Nothing with work in it goes without the user's word._

Loading this skill is not a request to tidy now. When you do tidy, run the
program's commands rather than reasoning out `git worktree` by hand: which
branch has landed, which tree is idle and which lock is stale are the
program's rules, and it applies them the same way every time.

## When to tidy

- **A branch lands:** finish its worktree, and tidy the branch itself with
  `git-workflow-tidy-branches`.
- **A job that made worktrees ends:** finish each one it made; the ones
  whose branches haven't landed stay, and only their build output goes.
- **The user asks what is lying around:** show `worktrees status`, and
  `worktrees status --all` for every clone.
- **A build is refused for disk space:** see
  [When a build is refused for disk space](#when-a-build-is-refused-for-disk-space).

## The commands

| To                                                 | Run                                  |
| -------------------------------------------------- | ------------------------------------ |
| see this repository's worktrees and the free space | `worktrees status`                   |
| see every clone's under the configured roots       | `worktrees status --all`             |
| list what a sweep would remove and clean           | `worktrees sweep`                    |
| remove and clean what that list named              | `worktrees sweep --apply`            |
| remove one worktree and its branch, once landed    | `worktrees finish <worktree>`        |
| drop the build output of a worktree that stays     | `worktrees clean <worktree> --apply` |

- **List first:** run `worktrees sweep` and read its list before
  `worktrees sweep --apply`, and `worktrees clean <worktree>` before
  `--apply`. Without `--apply` nothing is removed.
- **`finish` says why it kept one:** a branch that hasn't landed or a tree
  with changes. Report that reason to the user; don't work around it.

## Where worktrees are

A worktree may be in `.claude/worktrees/`, in `<checkout>.worktrees/` beside
the checkout, or in a scratch directory. List them with `git worktree list`,
never by listing a folder: a folder misses the other two places, and can
hold a directory git no longer tracks or miss one it does.

## Locks

- **A Claude Code lock naming a dead process is stale.** Its reason has the
  form `claude agent … (pid <pid> start <time>)`, and the sweep clears it
  when that process is gone. Leave it to the sweep.
- **Any other lock is a person's.** Leave the worktree alone, and never run
  `git worktree unlock` on it; name it to the user if it is in the way.

## What never goes without the user's word

The program keeps each of these and reports it. Show it to the user and
ask before anything removes it:

| Kept                                      | Show it with                                    |
| ----------------------------------------- | ----------------------------------------------- |
| a worktree with uncommitted changes       | `git -C <worktree> status --short`              |
| a branch with commits that haven't landed | `git log --oneline <base>..<branch>`            |
| a stash                                   | `git stash list`, the entries naming its branch |
| gitignored files nothing regenerates      | `git -C <worktree> status --short --ignored`    |

- **Gitignored files kept:** `.env` and the like. A repository lists its
  own in a tracked `.worktree-keep`, in gitignore syntax; add a line there
  when the user names one the program doesn't keep.
- **Ask one question per worktree,** naming its path, branch and what is in
  it, with "keep it" as an option. Never answer it with `--force`,
  `git branch -D`, `git stash drop` or `git clean -f`.

## When a build is refused for disk space

The disk floor's refusal names the commands to run. Run them in order:

1. `worktrees sweep --apply` in the repository, which removes and cleans
   only what is safe.
2. `worktrees status --all`, to find what holds the rest of the space:
   the largest worktrees and build folders, landed or not.
3. Report the largest to the user, and ask before anything the sweep
   wouldn't do: removing an unlanded worktree, dropping a stash, or
   deleting anything outside a worktree.

Below the lower floor only reading and cleanup commands run, so don't
retry the build or route it through another command; free the space first.

## Without the program

When `worktrees` isn't installed, remove one worktree at a time with git
itself, by name:

```bash
git worktree remove <path>
git branch --delete <name>
```

Never with `--force` or `-D`: git then refuses a dirty tree and an
unmerged branch, which are the cases to bring to the user. Tell the user
the program comes from the nix-worktrees repository, as the `worktrees`
package of its flake, or run as `python3 -m worktrees` from a clone.

## Preference keys

- **Clone roots:** the folders holding the user's clones, which
  `worktrees status --all` and `worktrees sweep --all` walk. With none set,
  use `--all` only when the user asks about every clone.
- **Scheduled sweep:** whether a schedule already sweeps this machine.
  When it does, finish the worktrees your own job made and leave the rest
  to the schedule; when it doesn't, run `worktrees sweep` at the end of a
  job and offer its list to the user.

## Your preferences

!`cat "$(dirname "${CLAUDE_SKILL_DIR}")/git-workflow-tidy-worktrees.preferences.md" "${CLAUDE_PROJECT_DIR}/.agents/skills/git-workflow-tidy-worktrees.preferences.md" 2>/dev/null || true`

If your agent doesn't run the line above, read these files yourself if they
exist: `git-workflow-tidy-worktrees.preferences.md` next to this skill's folder, then
`.agents/skills/git-workflow-tidy-worktrees.preferences.md` in the project. A project's
file overrides the user's, and the user's overrides this skill's defaults.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `git-workflow-tidy-branches`: tidying the branches, once their worktrees are gone.
- `git-hygiene-avoid-sweeping-operations`: why removal is by name, never with `--force`, `-D` or `git clean -f`.
- `shell-hygiene-delete-named-paths`: deleting only named paths, after listing them, as the program does.
