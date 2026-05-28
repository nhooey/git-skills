---
name: github-policy-protect-default-branch
description: |
  Apply a Rulesets-API branch ruleset to the default branch: require PR,
  required status checks, block force-pushes (`non_fast_forward`), block
  deletion, apply to admins. Includes a workflow for auditing and
  protecting an existing unprotected repo. Apply when creating a new
  repo, noticing an unprotected default branch, or onboarding a second
  contributor.
tags: [setup, safety]
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# github-policy-protect-default-branch

The default branch (`main` or `master`) is what every fresh clone
checks out and what production deploys typically track. An unprotected
default branch lets anyone with write access push broken commits
straight to it, force-push over published history, or delete the
branch entirely. None of those should be possible in a single
keystroke.

## How to load this skill

Loading this skill doesn't mean you should configure the repo right
now — just that when branch protection is on the table (new repo,
audit, onboarding), you'll apply the rules below.

## Minimum protection rules to set

- **Require a pull request before merging.** Direct pushes to the
  default branch are blocked; every change goes through a PR. This is
  the single most important rule — most of the others enforce
  themselves once direct pushes are gone.
- **Require status checks to pass before merging.** Whatever CI you
  have (tests, type checks, lint, security scans) must be green. Pick
  the specific check names; "require any check" is too loose and lets
  a missing CI run masquerade as success.
- **Require branches to be up to date before merging** when status
  checks are required. Otherwise a PR can merge green against a base
  that has since broken — and you only find out on `main`.
- **Block force-pushes.** Rewriting published history on the default
  branch is almost never what you want; if it is, lift the rule
  deliberately for that one operation and put it back.
- **Block deletions.** Self-explanatory. The default branch should not
  be deletable by anyone short of a repo admin override.
- **Apply rules to administrators too.** Admins shouldn't have a side
  door around the rules they set. Carve out exceptions for break-glass
  moments, not as the default.

## Apply with `gh`

Uses the modern Rulesets API — supersedes the older branch protection
endpoints, which still work but are being phased out.

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
deletion. `~DEFAULT_BRANCH` is GitHub's symbolic ref for "whatever the
default branch is right now" — it follows along if you rename
`master` → `main` later.

## Verify

In the UI: **Settings → Rules → Rulesets**. Or:

```bash
gh api "repos/<owner>/<repo>/rulesets" --jq '.[] | {name, enforcement, target}'
```

## Applying to an existing unprotected repo

If the repo has been unprotected for a while, expect cleanup:

1. **Audit local clones.** Run `git fetch --prune` to drop tracking
   refs whose remote branches have already been deleted. See
   `git-workflow-cleanup-merged-branches` for the local cleanup workflow.
2. **Survey stale remote branches.** Many will already be merged:
   ```bash
   gh api "repos/<owner>/<repo>/branches?protected=false&per_page=100" \
     --jq '.[].name' | head -50
   ```
   Don't bulk-delete without asking — some teams keep release branches
   around. Ask the user before pruning branches the current session
   didn't create:

   **Entity type:** multi-select (one option per branch the user can
   individually check or uncheck).

   **Question text** (literal start fixed; dynamic part in `[brackets]`):

   > Prune these stale remote branches in `[owner/repo]`?

   **Option text** (one per branch; literal start fixed):

   - `Delete remote branch [branch-name]`

   The literal prefixes (`Prune these stale remote branches in` and
   `Delete remote branch`) are fixed so the prompt is recognisable
   across sessions and the pre-selection by prior answer remains
   deterministic. Only the bracketed segments vary.
3. **Watch for direct-push patterns.** Once the PR rule is on, any
   contributor whose habit was `git push origin main` will hit a wall.
   Mention the change in an announcement issue/PR.

## When to apply

- Creating a new GitHub repo.
- Auditing an existing repo with no branch protection.
- Adding a second contributor (also see `github-policy-codeowners`).
- Renaming the default branch — confirm `~DEFAULT_BRANCH` still
  matches your ruleset's target.
