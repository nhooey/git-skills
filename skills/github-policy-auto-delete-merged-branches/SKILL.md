---
name: github-policy-auto-delete-merged-branches
description: |
  Enable GitHub's `delete_branch_on_merge` repository setting, so a PR's
  head branch is deleted when the PR merges, with one `gh api` PATCH per
  repo and a check that it took. Use when creating a new GitHub repo,
  setting one up alongside a default-branch ruleset, or when merged
  branches are piling up on the remote.
tags: [setup]
allowed-tools:
  - Bash
  - Read
  - 'Bash(gh api *)'
---

# Auto-delete merged branches

_Turn on GitHub's per-repo setting that deletes a PR's head branch when the PR merges._

Merged branches left on the remote bury the active ones in
`git branch -r`, and a reused name (`fix-login` six months later)
collides with a stale ref in tools that key off branch names.
`git fetch --prune` only helps once the remote branch is gone.

Loading this skill doesn't mean changing a repo's settings now; apply it
when setting up a repo or auditing its branches.

## Apply with `gh`

```bash
gh api -X PATCH "repos/<owner>/<repo>" \
  -F delete_branch_on_merge=true
```

Use `-F` (typed field), not `-f`: `-f` sends the JSON string `"true"`,
while this setting is a boolean. The endpoint coerces the string today,
but send the right type rather than rely on that.

## Verify

```bash
gh api "repos/<owner>/<repo>" --jq '.delete_branch_on_merge'
# → true
```

In the UI: **Settings → General → Pull Requests → Automatically delete
head branches**.

## Scope

The setting deletes only the head branch of a merged PR: never the base
branch, never a branch whose PR closed without merging, never a branch
with no PR. It is safe on any repo where changes land through PRs.

When the PR comes from a fork, the branch lives in the contributor's
fork and stays there; that cleanup is theirs.

## When to apply

- Creating a new GitHub repo, together with
  `github-policy-protect-default-branch`.
- Auditing an existing repo where merged branches accumulate.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `github-policy-protect-default-branch`: the companion default-branch ruleset to apply at the same repo-setup time.
