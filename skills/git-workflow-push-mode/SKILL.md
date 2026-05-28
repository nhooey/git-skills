---
name: git-workflow-push-mode
description: |
  Before the first push to a repo, check project memory for a saved
  push-mode preference. If none, ask the user once which push workflow
  applies — Mode 1 (direct to main), Mode 2 (PRs always, never push
  main), or Mode 3 (ask each time) — and save the answer as a project
  memory so future sessions don't re-ask. Includes a `gh pr list`
  detection probe and follow-up questions for the branch-on-Mode-1 /
  branch-on-Mode-2 cases.
tags: [workflow, interactive, team-stance]
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
---

# git-workflow-push-mode

Before pushing anything to a remote, know which workflow this repo
uses. The choice has real consequences (PR history, review surface,
what goes on the main branch), so don't guess. If you don't already
know the mode for this repo, **check project memory; if no answer is
recorded there, ask the user once and save the answer as a project
memory** so future sessions in this repo apply it silently.

## How to load this skill

Active workflow:

1. On first push of a session, read project memory for an existing
   `push-workflow-mode` entry (see "Memory format" below).
2. If found, apply it silently — no question.
3. If not found, prompt the user (using the question script below),
   then **write the answer to project memory** before applying it.
4. For the rest of this session and all future sessions in this repo,
   apply the saved mode silently.

A reasonable detection probe to inform the question:

```bash
gh pr list --state all --limit 1 --json number --jq 'length'
```

`0` means no PRs have ever been opened (mode 1 is plausible default).
`1` means the repo has used PRs at least once (mode 2 is plausible
default).

## The three modes

**Mode 1 — Direct-to-main (no-PR-history repo).** The repo has never
had a pull request opened. Default to pushing straight to the main
branch. Subcases:

- *On main, with new commits:* push main.
- *On a feature branch, with new commits:* **push the branch to its
  own remote tracking branch only.** Do not auto-merge into main, do
  not auto-fast-forward main, do not open a PR. The user will merge it
  themselves if they want to. (If you just created the branch in this
  session for a specific task, ask whether to merge it back to main
  before pushing — but otherwise leave it alone.)

**Mode 2 — PR-always (never push to main).** The repo uses pull
requests as its review boundary. Never push commits directly to main.
Subcases:

- *On main, with new commits:* this is anomalous — commits should not
  be landing on main locally. Stop and ask. Likely fix: move the
  commits to a feature branch (`git switch -c <branch>`), reset main
  to its remote tip, push the branch, open a PR.
- *On a feature branch, with new commits:* push the branch, then
  **ask the user whether to open a PR** (`gh pr create`). If a PR for
  the branch already exists (`gh pr list --head <branch>`), just push
  — the existing PR's diff updates automatically, but its title and
  body do not. If you amended or reworded the commit, re-sync them
  per `github-hygiene-pull-request-mirrors-commit`.

**Mode 3 — Ask each time.** The user wants a per-push prompt. Before
any push, ask: "Push to main directly, or open a PR?" — with the
current branch state baked into the question. Probe
`gh pr list --head <branch> --state open` first so the question is
informed: "Push to main, or push branch + (open PR | update PR #N)?"
If a PR already exists and you amended the commit, re-sync title and
body per `github-hygiene-pull-request-mirrors-commit`.

## What to ask, when

- **First push for a repo whose mode isn't in project memory:** ask
  the user which mode to use (see "Question script" below). Offer the
  three modes and recommend the one suggested by the `gh pr list`
  probe above. **Save the answer to project memory immediately** so
  this never has to be asked again in any future session.
- **First time on a feature branch in modes 1 or 2 with no saved
  on-branch preference:** the on-branch behavior is a sub-decision;
  ask the relevant follow-up from the question script and **save that
  answer to project memory too**.
- **Every subsequent push (this session or any future session):**
  apply the saved mode silently — the whole point of picking a mode
  is to stop asking. Exception: Mode 3, which always asks.
- **Anomalous states** (on main with PR-always mode, on a detached
  HEAD, mid-rebase, etc.): always stop and ask, regardless of mode.

## Question script

Use these exact questions (via `AskUserQuestion` or equivalent) so the
user gets a consistent prompt across sessions and repos. The literal
start of each question and each option is fixed — only the bracketed
dynamic parts (current branch, recommended option) vary — so identical
prompts surface identically across sessions and re-asks. The
recommended option is marked; pick whichever the `gh pr list` probe
suggests, or fall back to "Ask each time" when in doubt.

**Q1 — Primary mode (ask once per repo per session).**

**Entity type:** single-select (radio / multiple-choice; exactly one
mode applies per repo).

**Question text** (literal start fixed; dynamic parts in `[brackets]`):

> Which Git push workflow do you want to use for this repo? (recommended: `[Mode N]`)
>
> - **Mode 1 — Direct to main:** This repo has never had a PR opened;
>   just push commits straight to the main branch. (Recommend if
>   `gh pr list --state all --limit 1` returns 0.)
> - **Mode 2 — PRs always:** Never push directly to main. Always go
>   through a feature branch + pull request. (Recommend if the repo
>   has any PR history.)
> - **Mode 3 — Ask each time:** Prompt before every push.

**Q2 — On-branch follow-up (ask only if Mode 1 was picked AND the user
is on a feature branch).**

**Entity type:** single-select (radio / multiple-choice; one on-branch
default applies per repo).

**Question text** (literal start fixed; dynamic part in `[brackets]`):

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

**Q3 — On-branch follow-up (ask only if Mode 2 was picked AND the user
is on a feature branch).**

**Entity type:** single-select (radio / multiple-choice; one on-branch
default applies per repo).

**Question text** (literal start fixed; dynamic part in `[brackets]`):

> In Mode 2 (PRs always — never push to main), what should happen when
> you're on feature branch `[branch-name]` and ask Claude to push?
>
> - **Push branch + open PR:** Push the branch and, if no PR is open
>   for it yet, open one with `gh pr create`. If a PR already exists,
>   just push — the diff updates, but re-sync the title and body per
>   `github-hygiene-pull-request-mirrors-commit` if you amended the commit message.
> - **Push branch only:** Just push the branch. Don't auto-open a PR —
>   leave that to the user. (Useful if the user prefers to write PR
>   descriptions themselves or uses a non-`gh` flow.)
> - **Ask whether to open PR:** Push the branch, then ask whether to
>   open a PR. Sub-question per push.

After collecting answers, **write them to project memory immediately**
(see "Memory format" below). Don't re-ask in future sessions — the
saved memory is the source of truth. If the user later says something
inconsistent with the saved mode ("actually, open a PR for this one"),
treat that as a one-off override, not a mode change. If the user
explicitly says "switch modes", **update the saved memory** with the
new value before applying it.

## Memory format

Save the decision as a `feedback`-type memory in the project's auto-
memory directory. Pick a stable slug like `push-workflow-mode` so
re-reads find it deterministically. Example:

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

Also add a one-line index entry to the project's `MEMORY.md`:

```
- [Push workflow mode](push-workflow-mode.md) — Mode 2; PRs always
```

On every subsequent push in any future session, the memory loads
automatically and this skill applies the saved mode without prompting.

## Safety net

The `pull-request-sync-check.sh` PostToolUse hook shipped by the
`github-pull-request-watcher` skill (wired into
`~/.claude/settings.json`) probes for an open PR on every
`git commit --amend` and `git push`, and emits a system reminder if
HEAD's commit message has diverged from the PR's title or body. This
catches amend-without-push and forgotten-PATCH cases that heuristic
skill loading might miss. The hook is non-blocking — it nudges, it
does not deny — but treat its reminder as authoritative and run the
PATCH it suggests. See the watcher skill's "Companion hook" section
for wiring instructions.

## Why this rule exists

Pushing is the action with the largest blast radius — it's the moment
work becomes visible to others, gets attached to a review process (or
doesn't), and starts showing up in history that future readers can't
easily rewrite. A repo that uses PRs has a social contract around
review; bypassing it with a direct push is expensive to undo and
signals disrespect for the contract. A repo that doesn't use PRs has a
different contract — opening one unprompted creates noise. Picking the
right path requires knowing the repo's norms, and the cheapest way to
know is to ask once.

## When to apply

- First push for a repo (any session) whose mode isn't in project
  memory — ask and save.
- Subsequent pushes — read from project memory and apply silently.
- Anomalous push state (on main but using Mode 2, mid-rebase, etc.)
  — always stop and ask, regardless of saved mode.
- User explicitly says "switch modes" — update the saved memory
  before applying.
