---
name: github
description: |
  Opinionated GitHub repository hygiene: protect the default branch
  against direct pushes / force-pushes / deletion, require pull requests
  for changes, and enable auto-deletion of head branches after merge.
  Apply when creating a new GitHub repository, auditing an existing one,
  or noticing that the default branch is unprotected or that merged
  branches are piling up on the remote.
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# github — GitHub Repository Hygiene

Apply these rules when you create a new GitHub repository, when you
notice an existing repo is unprotected, or when stale merged branches
are accumulating on the remote. Companion to the `git` skill, which
covers the local side of the same workflow.

The mechanics below use `gh` (GitHub CLI). Equivalent settings live
under the repo's **Settings → Branches** and **Settings → General →
Pull Requests** UI panels if you'd rather click.

## 1. Protect the default branch

The default branch (`main` or `master`) is what every fresh clone
checks out and what production deploys typically track. An
unprotected default branch lets anyone with write access push
broken commits straight to it, force-push over published history,
or delete the branch entirely. None of those should be possible
in a single keystroke.

**Minimum protection rules to set:**

- **Require a pull request before merging.** Direct pushes to the
  default branch are blocked; every change goes through a PR. This
  is the single most important rule — most of the others enforce
  themselves once direct pushes are gone.
- **Require status checks to pass before merging.** Whatever CI you
  have (tests, type checks, lint, security scans) must be green.
  Pick the specific check names; "require any check" is too loose
  and lets a missing CI run masquerade as success.
- **Require branches to be up to date before merging** when status
  checks are required. Otherwise a PR can merge green against a
  base that has since broken — and you only find out on `main`.
- **Block force-pushes.** Rewriting published history on the default
  branch is almost never what you want; if it is, lift the rule
  deliberately for that one operation and put it back.
- **Block deletions.** Self-explanatory. The default branch should
  not be deletable by anyone short of a repo admin override.
- **Apply rules to administrators too.** Admins shouldn't have a
  side door around the rules they set. Carve out exceptions for
  break-glass moments, not as the default.

**Apply with `gh`** (uses the modern Rulesets API — supersedes the
older branch protection endpoints, which still work but are being
phased out):

```bash
# Replace <owner>/<repo> and adjust the required check name.
gh api -X POST "repos/<owner>/<repo>/rulesets" \
  --input - <<'JSON'
{
  "name": "protect-default-branch",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "bypass_actors": [],
  "rules": [
    { "type": "pull_request" },
    { "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "ci" }
        ]
      }
    },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ]
}
JSON
```

`non_fast_forward` blocks force-pushes; `deletion` blocks branch
deletion. `~DEFAULT_BRANCH` is GitHub's symbolic ref for "whatever
the default branch is right now" — it follows along if you rename
`master` → `main` later.

**Verify** afterward by visiting `Settings → Rules → Rulesets`, or
with:

```bash
gh api "repos/<owner>/<repo>/rulesets" --jq '.[] | {name, enforcement, target}'
```

## 2. Auto-delete head branches after merge

Once a PR is merged, the source branch has done its job. Leaving
it on the remote creates two ongoing costs:

- **`git branch -r` becomes unreadable.** Active branches drown in
  hundreds of merged-and-forgotten ones. `git fetch --prune` only
  helps after someone has deleted them on the remote.
- **Stale branches confuse tooling.** PR-checkers, deploy previews,
  and "open PRs by branch" UIs all key off branch names. Resurrected
  names (`fix-login` reused six months later) collide with stale
  refs and produce surprising behaviour.

GitHub has a per-repo toggle that deletes the head branch
automatically when a PR is merged. Turn it on.

**Apply with `gh`:**

```bash
gh api -X PATCH "repos/<owner>/<repo>" \
  -f delete_branch_on_merge=true
```

**Verify:**

```bash
gh api "repos/<owner>/<repo>" --jq '.delete_branch_on_merge'
# → true
```

In the UI: **Settings → General → Pull Requests → Automatically
delete head branches**.

**Scope.** The setting only deletes the *source* branch of a merged
PR — never the base branch, never branches that close without
merging, never branches with no associated PR. It is safe to enable
on any repo where contributors land changes via PRs.

**Forks are unaffected.** Auto-delete operates on the head branch
in the head repository. When the PR comes from a fork, the
contributor's fork keeps its branch — that's their cleanup.

## 3. Other defaults worth setting once

When you're already in the repo settings, a few low-cost changes
pair naturally with rules 1 and 2:

- **Merge PRs with `--no-ff` (merge commits only).** Disable squash
  and rebase merges so every PR lands as an explicit merge commit,
  even when fast-forward would be possible. Two reasons: the merge
  commit is a clean revert point for the whole PR (`git revert -m 1
  <merge-sha>` undoes the entire feature in one go), and the
  branch's individual commits stay on disk where `git log
  --first-parent`, `git log --graph`, and `git blame` can use them.
  Squash-merge discards those commits and their messages; rebase-
  merge loses the topology. The `git` skill (rules 3 and 5) is
  already telling you to curate those commits — `--no-ff` is what
  makes the curation visible after merge.

  ```bash
  gh api -X PATCH "repos/<owner>/<repo>" \
    -f allow_merge_commit=true \
    -f allow_squash_merge=false \
    -f allow_rebase_merge=false
  ```

  Do **not** add `{ "type": "required_linear_history" }` to the
  ruleset — that rule rejects exactly the merge commits this option
  produces. The two settings are mutually exclusive; pick one.

- **Set up CODEOWNERS** if more than one person can merge. Pairs
  with the ruleset's `require_code_owner_review` flag (flip it to
  `true` once `.github/CODEOWNERS` exists).

## 4. When applying to an existing repo

If the repo has been unprotected for a while, expect cleanup:

1. **Audit local clones.** Run `git fetch --prune` to drop tracking
   refs whose remote branches have already been deleted. See the
   `git` skill's rule 7 for the post-merge local cleanup workflow.
2. **Survey stale remote branches.** Many will already be merged:
   ```bash
   gh api "repos/<owner>/<repo>/branches?protected=false&per_page=100" \
     --jq '.[].name' | head -50
   ```
   Don't bulk-delete without asking. Use `AskUserQuestion` to
   confirm before pruning branches the current session didn't
   create — some teams keep release branches around.
3. **Watch for direct-push patterns.** Once the PR rule is on, any
   contributor whose habit was `git push origin main` will hit a
   wall. Mention rule 1 in the PR/issue you open to announce the
   change.

## When to apply

- Creating a new GitHub repo → rules 1, 2, 3 immediately.
- Auditing an existing repo with no branch protection → rule 1.
- Noticing a wall of merged branches on the remote → rule 2.
- Adding a second contributor → rule 1 (raise the review count, add
  CODEOWNERS).
- Renaming the default branch → confirm `~DEFAULT_BRANCH` still
  matches your ruleset's target (it does, by design — but check).
