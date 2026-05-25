---
name: github-policy-auto-delete-merged-branches
description: |
  Enable GitHub's `delete_branch_on_merge` setting so PR head branches
  vanish on merge. One PATCH per repo. Apply when creating a new repo
  or when stale merged branches are accumulating on the remote.
tags: [setup]
allowed-tools:
  - Bash
  - Read
---

# github-policy-auto-delete-merged-branches

Once a PR is merged, the source branch has done its job. Leaving it on
the remote creates two ongoing costs:

- **`git branch -r` becomes unreadable.** Active branches drown in
  hundreds of merged-and-forgotten ones. `git fetch --prune` only
  helps after someone has deleted them on the remote.
- **Stale branches confuse tooling.** PR-checkers, deploy previews,
  and "open PRs by branch" UIs all key off branch names. Resurrected
  names (`fix-login` reused six months later) collide with stale refs
  and produce surprising behaviour.

GitHub has a per-repo toggle that deletes the head branch automatically
when a PR is merged. Turn it on.

## How to load this skill

Loading this skill doesn't mean you should change a repo's settings
now — just that when configuring a new repo or auditing branch hygiene,
you'll flip this toggle.

## Apply with `gh`

```bash
gh api -X PATCH "repos/<owner>/<repo>" \
  -f delete_branch_on_merge=true
```

## Verify

```bash
gh api "repos/<owner>/<repo>" --jq '.delete_branch_on_merge'
# → true
```

In the UI: **Settings → General → Pull Requests → Automatically delete
head branches**.

## Scope

The setting only deletes the *source* branch of a merged PR — never
the base branch, never branches that close without merging, never
branches with no associated PR. It is safe to enable on any repo where
contributors land changes via PRs.

## Forks are unaffected

Auto-delete operates on the head branch in the head repository. When
the PR comes from a fork, the contributor's fork keeps its branch —
that's their cleanup.

## When to apply

- Creating a new GitHub repo.
- Auditing an existing repo where merged branches accumulate.
- Companion to `github-policy-protect-default-branch` — apply both at repo
  setup time.
