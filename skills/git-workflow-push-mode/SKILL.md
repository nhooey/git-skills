---
name: git-workflow-push-mode
description: |
  Know which push workflow a repo uses before pushing to it: Mode 1 (direct
  to main), Mode 2 (PRs always, never push main) or Mode 3 (ask each time).
  On the first push of a session, check the preferences and project memory
  for a saved push-mode; if there is none, ask the user once, with a
  `gh pr list` detection probe to recommend a mode and follow-up questions
  for pushing from a feature branch in Mode 1 or Mode 2, and save the
  answer as a project memory so future sessions don't ask again. Use before
  the first push of a session to any repo, and whenever the user asks to
  switch push modes.
tags: [workflow, interactive, team-stance]
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
---

# Push workflow mode

_Each repo has one push workflow, chosen by the user once, saved in project memory and applied silently on every later push._

## Workflow

1. On the first push of a session, use the mode the preferences below
   name, if any. Otherwise read project memory for a `push-workflow-mode`
   entry (see [Memory format](#memory-format)).
2. If a mode is found, apply it without asking.
3. If not, ask the user with the [question script](#question-script),
   save the answer to project memory, then apply it.
4. Apply the saved mode silently for the rest of this session and in
   future sessions. Mode 3 is the exception: it asks on every push.

Always stop and ask, whatever the mode, in an anomalous state: on main
in Mode 2, a detached HEAD, mid-rebase and the like.

## The detection probe

`scripts/detect-push-mode.sh` gathers the facts behind the
recommendation, as `KEY=value` lines:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/detect-push-mode.sh"
# branch=<current>|DETACHED
# pr_history=yes|no|unknown
# open_pr=<number>|none|unknown
# recommended_mode=1|2
```

It wraps `gh pr list --state all --limit 1 --json number --jq 'length'`:
`0` means no PR has ever been opened (`recommended_mode=1`), `1` means
the repo has used PRs (`recommended_mode=2`). When `gh` is missing or a
call fails it reports `unknown` and recommends Mode 2, so it never
suggests pushing to main in a repo that might use PRs. It is a probe,
not a hook, because the choice is the user's and Mode 3 needs a prompt
on every push.

## The three modes

**Mode 1: direct to main.** The repo has never had a pull request
opened, so push straight to the main branch.

- *On main, with new commits:* push main.
- *On a feature branch, with new commits:* push the branch to its own
  remote branch only, unless the saved on-branch answer (Q2) says
  otherwise. Don't merge it into main, fast-forward main or open a PR;
  the user merges it if they want to. If you created the branch in
  this session for a specific task, ask whether to merge it back to
  main before pushing.

**Mode 2: PRs always.** The repo uses pull requests as its review
boundary. Never push commits directly to main.

- *On main, with new commits:* anomalous. Stop and ask. The likely fix
  is to move the commits to a feature branch (`git switch -c <branch>`),
  reset main to its remote tip, push the branch and open a PR.
- *On a feature branch, with new commits:* push the branch, then follow
  the saved on-branch answer (Q3), asking whether to open a PR (with
  `github-hygiene-pull-request-mirrors-commit`'s
  `create-or-update-pull-request.sh`, never `gh pr create`) if there is
  none. If a PR for the branch already
  exists (`gh pr list --head <branch>`), just push: its diff updates,
  but its title and body don't, so after an amend or reword re-sync
  them per `github-hygiene-pull-request-mirrors-commit`.

**Mode 3: ask each time.** Before every push, probe
`gh pr list --head <branch> --state open`, then ask with the branch
state in the question: "Push to main, or push the branch and (open a
PR | update PR #N)?" If a PR exists and you amended the commit, re-sync
its title and body per `github-hygiene-pull-request-mirrors-commit`.

## Question script

Ask these questions with `AskUserQuestion` or equivalent, each a
single-select. The start of each question and each option is fixed so
the prompt reads the same across sessions and repos; only the bracketed
parts vary. Mark the mode the probe recommends, or "Ask each time" when
in doubt.

### Q1: primary mode

Ask on the first push to a repo with no saved mode.

> Which Git push workflow do you want to use for this repo? (recommended: `[Mode N]`)
>
> - **Mode 1 — Direct to main:** This repo has never had a PR opened;
>   just push commits straight to the main branch. (Recommend if
>   `gh pr list --state all --limit 1` returns 0.)
> - **Mode 2 — PRs always:** Never push directly to main. Always go
>   through a feature branch + pull request. (Recommend if the repo
>   has any PR history.)
> - **Mode 3 — Ask each time:** Prompt before every push.

### Q2: on a feature branch in Mode 1

Ask the first time the user is on a feature branch in Mode 1 with no
saved on-branch answer.

> In Mode 1 (no PRs ever opened — just push to main), what should
> happen when you're on feature branch `[branch-name]` with new commits
> and ask Claude to push?
>
> - **Push the branch only:** Push the current branch to its remote
>   (creating an upstream if needed). Don't touch main. The branch
>   lives independently; user merges it themselves later if they want.
> - **Fast-forward main, push main:** If main can fast-forward to the
>   branch tip, do that locally, push main, then delete the feature
>   branch. If it can't FF, fall back to asking.
> - **Merge into main, push main:** Switch to main, merge the feature
>   branch (FF or merge commit), push main, delete the feature branch.
>   Closest to "just push to main" behavior.
> - **Ask in this case:** Mode 1 covers main-only pushes; if you're on
>   a branch, the situation is ambiguous enough that Claude should ask
>   each time anyway.

### Q3: on a feature branch in Mode 2

Ask the first time the user is on a feature branch in Mode 2 with no
saved on-branch answer.

> In Mode 2 (PRs always — never push to main), what should happen when
> you're on feature branch `[branch-name]` and ask Claude to push?
>
> - **Push branch + open PR:** Push the branch and, if no PR is open
>   for it yet, open one with `create-or-update-pull-request.sh` from
>   `github-hygiene-pull-request-mirrors-commit`. If a PR already exists,
>   just push — the diff updates, but re-sync the title and body per
>   `github-hygiene-pull-request-mirrors-commit` if you amended the commit message.
> - **Push branch only:** Just push the branch. Don't auto-open a PR —
>   leave that to the user. (Useful if the user prefers to write PR
>   descriptions themselves or uses a non-`gh` flow.)
> - **Ask whether to open PR:** Push the branch, then ask whether to
>   open a PR. Sub-question per push.

### After the answers

Write the answers to project memory before applying them. A request
that contradicts the saved mode ("open a PR for this one") is a one-off
override, not a mode change. When the user says to switch modes, update
the saved memory first, then apply the new mode.

## Memory format

Save the decision as a `feedback` memory in the project's auto-memory
directory, under a stable slug like `push-workflow-mode` so later reads
find it:

```markdown
---
name: push-workflow-mode
description: Push workflow mode chosen for this repo (Mode 1 / 2 / 3
  + on-branch follow-up if applicable)
metadata:
  type: feedback
---

**Mode:** 2 (PRs always — never push to main)
**On-branch behavior:** Push branch + open PR
**Why:** Repo has prior PR history; user confirmed PRs-always
**How to apply:** On any push from this repo, follow Mode 2 silently.
Never push to main; always open or update a PR. On amend behind an
open PR, re-sync the title/body per `github-hygiene-pull-request-mirrors-commit`.
```

Add a one-line index entry to the project's `MEMORY.md`:

```markdown
- [Push workflow mode](push-workflow-mode.md) — Mode 2; PRs always
```

## Safety net

The `pull-request-sync-check.sh` PostToolUse hook from
`github-hygiene-pull-request-mirrors-commit`, run by the
`git-skills-hooks` plugin, checks for an open PR on every
`git commit --amend` and `git push`, and emits a reminder when HEAD's
commit message has drifted from the PR's title or body. It doesn't
block; when it fires, re-sync the PR as it says. That skill's "The sync
check hook" section covers the plugin.

## When to apply

- First push to a repo, in any session, whose mode isn't saved: ask and
  save.
- Later pushes: apply the saved mode silently.
- Anomalous push state: stop and ask, whatever the saved mode.
- The user says to switch modes: update the saved memory before
  applying it.

## Your preferences

!`cat "${CLAUDE_SKILL_DIR}/../git-workflow-push-mode.preferences.md" "${CLAUDE_PROJECT_DIR}/.agents/skills/git-workflow-push-mode.preferences.md" 2>/dev/null || true`

If your agent doesn't run the line above, read these files yourself if they
exist: `git-workflow-push-mode.preferences.md` next to this skill's folder, then
`.agents/skills/git-workflow-push-mode.preferences.md` in the project. A project's
file overrides the user's, and the user's overrides this skill's defaults.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `github-hygiene-pull-request-mirrors-commit`: re-syncing an existing PR's title and body after you amend or reword the commit, and the `pull-request-sync-check.sh` safety-net hook that flags a PR whose title or body has drifted from HEAD.
