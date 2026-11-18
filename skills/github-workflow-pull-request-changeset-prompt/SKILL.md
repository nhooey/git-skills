---
name: github-workflow-pull-request-changeset-prompt
description: |
  Load on finishing a set of edits, before staging or committing. Asks
  the user whether to stage, commit or follow up on the PR, rather than
  deciding yourself. `git-workflow-push-mode` decides whether a push or
  new PR is asked about; `coding-agent-questions-as-first-class-prompts`
  has the general asking rules; `git-workflow-inspect-before-commit`
  loads before the commit.
tags: [agent, interactive]
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# Change-set prompt

_Once a change-set lands in the work tree, the user picks what happens to it from one multi-select prompt; the agent never decides on its own whether to stage, commit or follow up on the PR, and pushes as the saved push mode says._

Loading this skill doesn't fire the prompt; the prompt fires after a
change-set lands in the work tree. It is always multi-select
(`multiSelect: true`), never single-select.

## The saved push mode decides whether to ask about pushing

`git-workflow-push-mode` owns whether a push is asked about first. Read
the saved mode as that skill says before building the prompt:

- **Mode 1 or Mode 2 saved, normal state:** leave Q2 out and push as
  the mode and its saved on-branch answer say. Leave Open Pull Request
  out of Q3 too, unless that on-branch answer is to ask.
- **Mode 3 saved:** ask Q2 and Q3 in full. Together they are the
  per-push question Mode 3 calls for, so don't ask it a second time.
- **No mode saved:** ask Q2 and Q3 in full. If the user picks Push or
  Force, `git-workflow-push-mode` asks its question script and saves
  the mode before the push.
- **The push needs Force, or the state is anomalous** (on main in
  Mode 2, a detached HEAD, mid-rebase): ask Q2 whatever the mode. A saved
  mode covers ordinary pushes, not rewriting published history or
  pushing from a state that skill says to stop in.

Q1 (Local actions), Re-derive PR name + title and Monitor + react are
not push decisions, so they are asked in every mode.

## The eight options, in order

- **Stage**: `git add` the changed files.
- **Commit**: new commit (`git commit`).
- **Amend**: fold into the last commit (`git commit --amend`).
- **Push**: regular `git push`.
- **Force**: `git push --force-with-lease` (see
  `git-hygiene-push-force-safely`).
- **Open Pull Request**: open the PR from the HEAD commit with
  `create-or-update-pull-request.sh`, per
  `github-hygiene-pull-request-mirrors-commit`.
- **Re-derive PR name + title**: re-sync the PR's title and body from
  the HEAD commit with the same script.
- **Monitor + react**: arm or re-arm `github-workflow-pull-request-watcher`.

## Split into three questions (4-option cap)

`AskUserQuestion` caps each question at 4 options, so split into
three multi-select questions. Every question and every option starts
with a fixed literal prefix; only the bracketed segments (current
branch, current PR number, file count) vary, so the same prompt
re-surfaces identically across iterations and pre-selection by the
prior answer is deterministic.

These questions leave out the `All` and `None` options that
`coding-agent-questions-as-first-class-prompts` puts first in a
multi-select: each question holds a mutually exclusive pair (below), so
`All` would never be a valid answer, and with them the options wouldn't
fit the cap.

### Q1: Local actions

**Question text** (literal start fixed; dynamic parts in `[brackets]`):

> Local actions for the change-set on branch `[branch-name]` (`[N] files`)?

**Option text** (literal start fixed):

- `Stage — git add the changed files`
- `Commit — new commit`
- `Amend — fold into the last commit`

### Q2: Push actions

**Question text** (literal start fixed; dynamic parts in `[brackets]`):

> Push the change-set on branch `[branch-name]`?

**Option text** (literal start fixed):

- `Push — regular git push`
- `Force — git push --force-with-lease`

### Q3: PR follow-up

Opening a PR is a follow-up on a pushed branch, not a push itself, so it
lives here next to the other PR-level actions, and it keeps the
mutually exclusive Open Pull Request and Re-derive pair in one question.

**Question text** (literal start fixed; dynamic part in `[brackets]`):

> PR follow-up for `[PR #N | new PR]` on branch `[branch-name]`?

**Option text** (literal start fixed):

- `Open Pull Request — from the HEAD commit`
- `Re-derive PR name + title — PATCH from HEAD commit`
- `Monitor + react — arm github-workflow-pull-request-watcher`

## Mutually exclusive pairs

Commit and Amend are mutually exclusive; if both get checked, ask which
the user meant rather than guessing. Same for Push and Force. Open Pull
Request and Re-derive PR name + title are likewise mutually exclusive:
one applies when no PR exists yet, the other when one does.

## Pre-select from the last instance of this question within the session

Workflows repeat: refining a single-commit PR typically loops Stage +
Amend + Force + Re-derive PR name + title + Monitor, so pre-select the
user's last answer to the same question. On the first ask of the
session, pre-select by context:

- New branch, no PR yet: Stage + Commit + Push + Open Pull Request +
  Monitor.
- Refining an existing PR: Stage + Amend + Force + Re-derive PR name +
  title + Monitor.
- Trivial doc edit, no PR: Stage + Commit + Push.

Resurface the question after every change-set; the user's last answer
is a hint, not a binding default.

## When to apply

- Finished any change-set in the work tree.
- About to push or commit and unsure which subset of operations the
  user wants this iteration.

## Your preferences

!`cat "$(dirname "${CLAUDE_SKILL_DIR}")/github-workflow-pull-request-changeset-prompt.preferences.md" "${CLAUDE_PROJECT_DIR}/.agents/skills/github-workflow-pull-request-changeset-prompt.preferences.md" 2>/dev/null || true`

If your agent doesn't run the line above, read these files yourself if they
exist: `github-workflow-pull-request-changeset-prompt.preferences.md` next to this skill's folder, then
`.agents/skills/github-workflow-pull-request-changeset-prompt.preferences.md` in the project. A project's
file overrides the user's, and the user's overrides this skill's defaults.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `coding-agent-questions-as-first-class-prompts`: the general rules for asking through `AskUserQuestion`, and the `All` and `None` options this prompt leaves out.
- `git-workflow-push-mode`: the saved push mode that decides whether Q2 and the Open Pull Request option are asked at all.
- `git-hygiene-push-force-safely`: how the Force option pushes, with `--force-with-lease`.
- `git-workflow-inspect-before-commit`: inspecting, staging and reviewing the diff before the Commit or Amend option commits.
- `git-hygiene-commit-message-format`: the message the Commit and Amend options write.
- `github-hygiene-pull-request-mirrors-commit`: how the Open Pull Request and Re-derive PR name + title options create or re-sync the PR from the commit.
- `github-workflow-pull-request-watcher`: the Monitor that the Monitor + react option arms or re-arms.
