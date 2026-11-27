---
name: git-workflow-push-mode
description: |
  Know which push workflow a repo uses before pushing to it: Mode 1 (direct
  to main), Mode 2 (PRs always, never push main) or Mode 3 (ask each time).
  On the first push of a session, read the mode from the project's tracked
  preferences file, `.agents/skills/git-workflow-push-mode.preferences.md`;
  if it names none, ask the user once, with a `gh pr list` detection probe
  to recommend a mode and follow-up questions for pushing from a feature
  branch in Mode 1 or Mode 2, and save the answer in that file so future
  sessions don't ask again. In Mode 2 the agent opens the PR and stops; the
  user merges. Use before the first push of a session to any repo, and
  whenever the user asks to switch push modes.
tags: [workflow, interactive, team-stance]
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
---

# Push workflow mode

_Each repo has one push workflow, chosen by the user once, saved in the project's tracked preferences file and applied silently on every later push._

## Workflow

1. On the first push of a session, use the mode the preferences below
   name (see [Preferences file format](#preferences-file-format)).
2. If a mode is found, apply it without asking.
3. If not, ask the user with the [question script](#question-script),
   save the answer in the project's preferences file, then apply it.
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
- *After the PR is open:* stop. The user merges their own PRs. A task
  to open PRs, a green check run, an approving review or a later
  "continue" grants no authority to merge; merging is a separate,
  outward-facing step the user keeps. Work that waits on the merge,
  such as the next PR in a chain, waits for it: arm
  `github-workflow-pull-request-watcher` and pick up when it reports
  the merge.

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

Write the answers to the project's preferences file before applying
them. A request that contradicts the saved mode ("open a PR for this
one") is a one-off override, not a mode change. When the user says to
switch modes, update the preferences file first, then apply the new
mode.

## Preferences file format

The mode lives in the project's
`.agents/skills/git-workflow-push-mode.preferences.md`, tracked in git
and committed like any other file, so every checkout, worktree and
agent of the repo reads the same answer. It never goes in an agent's
project memory, which only one agent on one machine sees.

The file holds one `- Mode:` line, and an `- On a feature branch:` line
once Q2 or Q3 is answered:

```markdown
- Mode: 2 (PRs always, never push to the default branch)
- On a feature branch: Push branch + open PR
```

`- Mode:` is the only key for the mode. A file that writes it another
way, such as `- Push mode:`, still names a mode; read it, and rewrite
the line as `- Mode:` the next time you edit the file.

In Mode 2 the commit that writes the file goes through a PR like any
other. The user's own
`~/.agents/skills/git-workflow-push-mode.preferences.md` can name a
default mode for every repo; the project's file overrides it.

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
- A PR opened in Mode 2: stop there; the user merges.
- Anomalous push state: stop and ask, whatever the saved mode.
- The user says to switch modes: update the preferences file before
  applying it.

## Your preferences

!`cat "$(dirname "${CLAUDE_SKILL_DIR}")/git-workflow-push-mode.preferences.md" "${CLAUDE_PROJECT_DIR}/.agents/skills/git-workflow-push-mode.preferences.md" 2>/dev/null || true`

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
- `github-workflow-pull-request-watcher`: watching an open PR in the background, so work that waits on the user's merge picks up when it lands.
