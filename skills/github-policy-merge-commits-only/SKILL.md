---
name: github-policy-merge-commits-only
description: |
  Configure repo so PRs land as explicit merge commits — disable squash
  and rebase merges. The merge commit is a clean revert point (`git
  revert -m 1`), and per-commit history stays for `git log
  --first-parent` and `git blame`. Skip this skill if the team prefers
  squash-merge.
tags: [setup, team-stance]
allowed-tools:
  - Bash
  - Read
---

# github-policy-merge-commits-only

A team-stance: this skill takes the position that every PR should land
as an explicit merge commit. Other teams legitimately prefer
squash-merge or rebase-merge; if so, skip this skill.

## How to load this skill

Loading this skill doesn't mean you should reconfigure a repo's merge
settings now — just that when configuring a new repo or auditing one,
you'll apply this opinion.

## The rule

Disable squash and rebase merges so every PR lands as an explicit merge
commit, even when fast-forward would be possible.

```bash
gh api -X PATCH "repos/<owner>/<repo>" \
  -f allow_merge_commit=true \
  -f allow_squash_merge=false \
  -f allow_rebase_merge=false
```

## Why

Two reasons:

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

Do **not** add `{ "type": "required_linear_history" }` to the ruleset
in `github-policy-protect-default-branch` — that rule rejects exactly the
merge commits this option produces. The two settings are mutually
exclusive; pick one.

## When to apply

- Creating a new GitHub repo where the team wants merge commits.
- Auditing an existing repo for merge strategy.
- After enabling `github-policy-protect-default-branch`, double-check that
  `required_linear_history` is NOT in the ruleset.
