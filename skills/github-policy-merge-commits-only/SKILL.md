---
name: github-policy-merge-commits-only
description: |
  Configure a GitHub repository so every pull request lands as an
  explicit merge commit, with squash and rebase merges disabled. The
  merge commit is a clean revert point (`git revert -m 1`), and the
  branch's commits stay for `git log --first-parent` and `git blame`.
  Use when creating a GitHub repository or auditing its merge settings,
  unless the team prefers squash-merge.
tags: [setup, team-stance]
allowed-tools:
  - Bash
  - Read
  - 'Bash(gh api *)'
---

# Merge commits only

_Every pull request lands as an explicit merge commit. This is a team stance: a team that prefers squash-merge or rebase-merge skips this skill._

Loading this skill is not a request to change a repository's settings now; it applies when one is being created or audited.

## The rule

Disable squash and rebase merges so every PR lands as an explicit merge
commit, even when fast-forward would be possible.

```bash
gh api -X PATCH "repos/<owner>/<repo>" \
  -F allow_merge_commit=true \
  -F allow_squash_merge=false \
  -F allow_rebase_merge=false
```

Use `-F` (typed field), not `-f`: `-F` converts `true` and `false` to
JSON booleans, while `-f` sends them as the strings `"true"` and
`"false"` (see `github-hygiene-gh-cli-gotchas`).

## Why

1. **The merge commit is a clean revert point for the whole PR.**
   `git revert -m 1 <merge-sha>` undoes the entire feature in one go.
   Squash-merge produces a single commit (so revert is also clean)
   but discards the per-commit history below.

2. **The branch's individual commits stay on disk** where `git log
   --first-parent`, `git log --graph`, and `git blame` can use them.
   Squash-merge discards those commits and their messages; rebase-
   merge loses the topology. If you're investing in
   `git-workflow-curate-unpushed` (curating per-commit history before
   push), squash-merge throws that effort away.

## Compatibility caveat

Don't add `{ "type": "required_linear_history" }` to the ruleset
in `github-policy-protect-default-branch` — that rule rejects exactly the
merge commits this option produces. The two settings are mutually
exclusive; pick one.

## When to apply

- Creating a new GitHub repo where the team wants merge commits.
- Auditing an existing repo for merge strategy.
- After enabling `github-policy-protect-default-branch`, double-check that
  `required_linear_history` is not in the ruleset.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `git-workflow-curate-unpushed`: curating per-commit history before push, which is what makes keeping it in merge commits worthwhile.
- `github-hygiene-gh-cli-gotchas`: why `gh api` booleans go through `-F` rather than `-f`.
- `github-policy-protect-default-branch`: the default-branch ruleset, which must not include `required_linear_history` alongside merge commits.
