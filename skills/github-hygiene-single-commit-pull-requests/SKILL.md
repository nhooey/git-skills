---
name: github-hygiene-single-commit-pull-requests
description: |
  Decide when a PR is a single commit: one commit per PR by default, and
  several only for a reason the preferences allow (by default
  `refactor-split`, `vendored-import` or `run-snapshot`), each commit
  building and passing on its own, with the reason declared in a
  `Multi-commit: <reason>` trailer on the lead commit. A PR with several
  commits and no allowed reason is squashed into one commit whose message
  is a single delta written afresh, without interactive rebase, then
  force-pushed with a lease and re-synced. Never `fixup!` or `squash!`
  commits, commits already on the base branch or a commit cherry-picked
  onto every branch of a stack; a stack isn't a multi-commit PR. Use
  before opening or updating a PR with more than one commit, when
  reviewing one, and when squashing a branch for a PR.
tags: [workflow, team-stance]
allowed-tools:
  - Bash
  - Read
---

# Single-commit pull requests

_A PR is one commit, unless the preferences allow a reason for several and the lead commit declares it in a `Multi-commit:` trailer._

This skill is the one place that decides how many commits a PR holds.
`github-hygiene-pull-request-mirrors-commit` derives the PR's title and
body from them.

## The default: one commit

A PR holds one commit. Its message is a single delta: what became true
and why.

## Several commits, for an allowed reason

A PR keeps several commits only for a reason named in the preferences'
`Allowed reasons`, and only when each commit builds and passes on its
own. The default reasons:

| Reason            | Kept apart                                        |
| ----------------- | ------------------------------------------------- |
| `refactor-split`  | a refactor, from the behaviour change it enables  |
| `vendored-import` | a vendored or generated import, from edits to it  |
| `run-snapshot`    | several finished runs, one commit each            |

The lead commit, the one that states what the whole PR achieves, names
the reason in a trailer, so a program reads it without guessing:

```text
Multi-commit: refactor-split
```

The lead commit's subject is the PR's title and its body the PR's
body, the synthesis, with only the footer after it; the PR's commits
tab lists the commits. Write that body as the synthesis, not as a copy
of any one commit, since each commit is one click away:

- **What it says:** what no single commit says, such as how the
  commits relate, why they share a PR, and what to review across them.
- **How it names a commit:** by its subject, the commit's canonical
  label, never by restating its body.

`github-hygiene-pull-request-mirrors-commit`'s `check` warns when a
paragraph of the synthesis repeats another commit's body.

## Never in a PR

- `fixup!` or `squash!` commits.
- Commits already on the base branch.
- A commit cherry-picked onto every branch of a stack: land it once, in
  its own PR, and stack the rest on it.

A stack isn't a multi-commit PR. Changes that each need their own
review are separate single-commit PRs, chained as
`github-workflow-pull-request-stacked` describes.

## Squashing a PR with no allowed reason

A PR with several commits and no allowed reason becomes one commit.
Interactive rebase isn't available to agents, so:

1. **Only `fixup!` commits besides the real one:**
   `git rebase --autosquash origin/<base>`.
2. **Otherwise:** `git reset --soft $(git merge-base origin/<base> HEAD)`,
   then commit again.
3. **Write the message afresh** as a single delta, per
   `git-hygiene-commit-message-format`, never the old subjects pasted
   together.
4. **Force-push with a lease,** per `git-hygiene-push-force-safely`.
5. **Re-sync the PR body** with
   `github-hygiene-pull-request-mirrors-commit`'s
   `create-or-update-pull-request.sh`.

Before squashing a PR someone else opened, follow the `Squash`
preference.

## Enforcement

The PR body generator's `check` mode reads these preferences and the
lead commit's `Multi-commit:` trailer. With `Multiple commits: refuse`
it exits 4 for a PR with several commits and no allowed reason; `warn`
reports it and exits 0; `allow` skips the check.

## Your preferences

!`cat "${CLAUDE_SKILL_DIR}/../github-hygiene-single-commit-pull-requests.preferences.md" "${CLAUDE_PROJECT_DIR}/.agents/skills/github-hygiene-single-commit-pull-requests.preferences.md" 2>/dev/null || true`

If your agent doesn't run the line above, read these files yourself if they
exist: `github-hygiene-single-commit-pull-requests.preferences.md` next to this skill's folder, then
`.agents/skills/github-hygiene-single-commit-pull-requests.preferences.md` in the project. A project's
file overrides the user's, and the user's overrides this skill's defaults.

The keys this skill reads, with its own defaults:

```markdown
- Multiple commits: refuse
- Allowed reasons: refactor-split, vendored-import, run-snapshot
- Squash: ask
```

- **`Multiple commits`:** `refuse`, `warn` or `allow`.
- **`Allowed reasons`:** the reasons a `Multi-commit:` trailer may name.
- **`Squash`:** `ask` asks before squashing someone else's PR; `yes`
  squashes without asking.

## When to apply

- About to open or update a PR with more than one commit.
- Reviewing a PR with several commits.
- Squashing a branch before a PR.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `github-hygiene-pull-request-mirrors-commit`: derives the PR's title and body from its commits, and re-syncs them after a squash.
- `git-hygiene-push-force-safely`: the `--force-with-lease` push after a squash.
- `git-hygiene-commit-message-format`: the single-delta message a squashed commit gets.
- `github-workflow-pull-request-stacked`: chaining dependent single-commit PRs instead of one multi-commit PR.
- `writing-hygiene-refer-by-canonical-label`: naming a commit by its subject in the synthesis.
