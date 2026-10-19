---
name: git-workflow-tidy-branches
description: |
  Tidy a repo's branches in two passes: a read-only report from the bundled
  script, then an apply that acts only on the lines the user chose. Deletes
  local and remote branches whose changes are already in the base (squash and
  rebase merges included), rebases branches that replay onto the base without
  conflicts and force-pushes them with a lease, and flags what needs a person:
  stacks, conflicts, diverged copies, branches checked out elsewhere. Saves the
  user's choices as preferences. Apply after merging, when branches pile up,
  or when asked to clean up, prune or rebase branches.
tags: [workflow, interactive, safety]
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# git-workflow-tidy-branches

_Report first, apply second. The script decides what is safe from the
repository's state alone; the user decides what to act on. Nothing is
deleted or rewritten that the report didn't name, and nothing whose sha
moved since the report._

## How to load this skill

Passive reference. Loading it doesn't mean you should tidy branches now;
it means that when you do, you'll use the script instead of reasoning out
`git branch --merged` by hand.

## Why a script

Which branches are merged, which rebase cleanly and which are stacked are
facts about the repository, so the bundled `scripts/tidy-branches.py`
works them out the same way every time. It uses git itself for each
decision: `git merge-tree --write-tree` to test for a merge,
`git replay --ref-action=print` to try a rebase without moving any ref, and
`git update-ref` and `git push --force-with-lease=<ref>:<sha>` to act only
when a ref is still where the report saw it. It needs Python 3.9+ and
git 2.44+; `gh` is optional, for open pull requests.

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/tidy-branches.py" report
```

`report` fetches each remote it uses with `--prune` first; `--no-fetch`
skips that.

## What the report decides

The base is the `Base` preference, or else the default branch of a remote
named `upstream`, or else that of the push remote. A fork's own `main`
often holds work upstream hasn't taken, and measured against it every
branch would look merged.

| Branch state                                                                 | Plan line                                |
| ---------------------------------------------------------------------------- | ---------------------------------------- |
| Its changes are all in the base: by ancestry, or merging it changes nothing  | `delete-local`, `delete-remote`          |
| Behind the base, replays without conflicts, in step with its remote copy     | `rebase`, then `push`                    |
| Behind, replays cleanly, and has commits its remote copy lacks               | `rebase`, and a note to push it yourself |
| On another unmerged branch, or under one                                     | note: stacked                            |
| Rebasing it conflicts                                                        | note                                     |
| It and its remote copy each have commits the other lacks                     | note                                     |
| Its remote copy has commits it lacks                                         | note                                     |
| Checked out in a worktree                                                    | note                                     |
| Merged, but its pull request is still open                                   | note                                     |
| Has merge commits since the base                                             | note                                     |
| Its upstream branch is gone, but it isn't merged                             | note                                     |
| Matches a `Keep` pattern, or is the base                                     | nothing                                  |

Stale worktree entries get `prune-worktrees`. Each action line starts with
`ask` or `auto`, from the preferences, and each note with `note`; the first
line names the base and its sha.

## Doing it

1. **Run the report** and read it whole.
2. **Ask about the `ask` lines.** One multi-select AskUserQuestion per
   kind, with `All` and `None` first, then one option per branch:
   - `Delete these branches already merged into [base]?`, with options
     `Delete local branch [name]` and `Delete remote branch [remote]/[name]`.
   - `Rebase these branches onto [base]?`, with options `Rebase [name]`,
     ending `, then push to [remote]` when the plan pushes it.
3. **Apply** the `auto` lines and the chosen `ask` lines, unchanged, on
   stdin:

   ```bash
   python3 "${CLAUDE_SKILL_DIR}/scripts/tidy-branches.py" apply <<'PLAN'
   ask	delete-local	feature-x	3f2a…
   ask	rebase	feature-y	9c1d…	e51a…
   ask	push	origin	feature-y	9c1d…
   PLAN
   ```

   Keep a `push` line with its `rebase` line, after it. Each result line
   says `done` or `skipped` with the reason; the exit status is 1 if any
   was skipped.
4. **Report the notes.** They are the branches that need a person: name
   each with its reason and what would settle it. Stacks go to a stack
   tool, such as `git rebase --update-refs` or git-spice's
   `gs repo restack`, not to this script.

If the agent's permission layer refuses a force-push or a delete, stop and
give the user the exact `apply` input or `git push` line to run
themselves; don't rewrite it into a form the layer allows.

## Preferences

The script reads the preferences files and applies them itself.

| Key                         | Values                       | Default                       |
| --------------------------- | ---------------------------- | ----------------------------- |
| `Base`                      | a ref, like `upstream/main`  | as above                      |
| `Push remote`               | a remote                     | `origin`                      |
| `Keep`                      | branch globs, never touched  | `main`, `master`, `release/*` |
| `Delete merged`             | `ask`, `yes`, `no`           | `ask`                         |
| `Rebase`                    | `ask`, `yes`, `no`           | `ask`                         |
| `Rebase open pull requests` | `ask`, `yes`, `no`           | `ask`                         |

`yes` makes the lines `auto`, applied without a question; `no` leaves them
out of the plan. `Rebase open pull requests` overrides `Rebase` for
branches with an open pull request, since every force-push notifies the
reviewer and resets "changes since your last review".

**Saving a choice.** When the user answers in a way they'll want again,
such as "always keep `integration`" or "never rebase PR branches", save
it:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/tidy-branches.py" prefs set 'Keep' main,integration
python3 "${CLAUDE_SKILL_DIR}/scripts/tidy-branches.py" prefs show
```

`set` saves to the scope this skill is installed in; `--scope user` or
`--scope project` picks one.

- **Project:** it writes
  `.agents/skills/git-workflow-tidy-branches.preferences.md` in the
  project. Commit it with the change it belongs to.
- **User:** the user's file is generated by Home Manager, so the script
  writes nothing and prints the `home.file` setting to add to the Home
  Manager config. Propose that change to the user's config; a direct
  write would be refused, or lost on the next switch.

## When to apply

- Just merged a pull request: delete its branch, and rebase the ones behind.
- `git branch` lists more branches than are in flight.
- The user asks to clean up, prune or rebase branches, or to bring them up
  to date with the base.

## Your preferences

!`cat "${CLAUDE_SKILL_DIR}/../git-workflow-tidy-branches.preferences.md" "${CLAUDE_PROJECT_DIR}/.agents/skills/git-workflow-tidy-branches.preferences.md" 2>/dev/null || true`

If your agent doesn't run the line above, read these files yourself if they
exist: `git-workflow-tidy-branches.preferences.md` next to this skill's folder, then
`.agents/skills/git-workflow-tidy-branches.preferences.md` in the project. A project's
file overrides the user's, and the user's overrides this skill's defaults.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `git-hygiene-push-force-safely`: why every force-push carries a lease, as the script's do.
- `github-policy-auto-delete-merged-branches`: makes GitHub delete the remote head branch on merge, leaving only the local copy to tidy.
- `github-workflow-pull-request-stacked`: restacking the branches this skill only flags.
- `github-workflow-pull-request-watcher`: fires this cleanup when a pull request merges.
