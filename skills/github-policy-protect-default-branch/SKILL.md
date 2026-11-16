---
name: github-policy-protect-default-branch
description: |
  Protect a GitHub repository's default branch with a ruleset from the
  Rulesets API: require a pull request and named status checks, block
  force-pushes (`non_fast_forward`) and deletion, and hold admins to the
  rules. Includes the clean-up for an existing repository that has gone
  unprotected. Use when creating a repository, noticing an unprotected
  default branch, or onboarding a second contributor.
tags: [setup, safety]
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
  - 'Bash(gh api *)'
---

# Protect the default branch

_No one pushes straight to the default branch, force-pushes over it or deletes it, admins included. Every change arrives through a pull request with green checks._

Loading this skill is not a request to configure a repository now; it applies when branch protection is on the table.

## Minimum protection rules to set

- **Require a pull request before merging.** Direct pushes to the
  default branch are blocked; every change goes through a PR.
- **Require status checks to pass before merging.** Whatever CI you
  have (tests, type checks, lint, security scans) must be green. Pick
  the specific check names; "require any check" is too loose and lets
  a missing CI run masquerade as success.
- **Require branches to be up to date before merging** when status
  checks are required. Otherwise a PR can merge green against a base
  that has since broken.
- **Block force-pushes.** When a rewrite of the default branch is truly
  needed, lift the rule for that one operation and put it back.
- **Block deletions.**
- **Apply rules to administrators too.** Carve out exceptions for
  break-glass moments, not as the default.

## Apply with `gh`

Use the Rulesets API rather than the older branch protection endpoints.
`gh ruleset` only lists, views and checks rulesets, so creating one goes
through `gh api`.

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
deletion. `strict_required_status_checks_policy` is the "up to date
before merging" rule. `~DEFAULT_BRANCH` is GitHub's symbolic ref for
whatever the default branch is right now, so it follows a rename from
`master` to `main`.

The empty `"bypass_actors": []` is what applies the rules to admins too:
the Rulesets API has no separate `enforce_admins` flag (that belongs to
the legacy branch-protection API), and anyone not listed as a bypass
actor is held to the rules. To grant a deliberate break-glass exception,
add an entry here rather than leaving admins unprotected by default.

## Verify

In the UI: **Settings → Rules → Rulesets**. Or:

```bash
gh ruleset list --repo <owner>/<repo>
gh ruleset check --default --repo <owner>/<repo>
```

## Applying to an existing unprotected repo

If the repo has been unprotected for a while, expect cleanup:

1. **Audit local clones.** Run `git fetch --prune` to drop tracking
   refs whose remote branches have already been deleted. See
   `git-workflow-tidy-branches` for the local cleanup workflow.
2. **Survey stale remote branches.** Many will already be merged:
   ```bash
   gh api "repos/<owner>/<repo>/branches?protected=false&per_page=100" \
     --jq '.[].name' | head -50
   ```
   Don't bulk-delete: some teams keep release branches around. Ask the
   user before pruning branches the current session didn't create, in
   a multi-select that opens with `All` and `None`, as
   `coding-agent-questions-as-first-class-prompts` requires, then one
   option per branch, split across questions when the branches don't
   fit the option cap.

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
   Mention the change in an announcement issue or PR.

## When to apply

- Creating a new GitHub repo.
- Auditing an existing repo with no branch protection.
- Adding a second contributor (also see `github-policy-codeowners`).
- Renaming the default branch: confirm `~DEFAULT_BRANCH` still
  matches your ruleset's target.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `coding-agent-questions-as-first-class-prompts`: the multi-select rules, `All` and `None` first, for the stale-branch prompt.
- `git-workflow-tidy-branches`: the local cleanup of merged branches found while auditing an existing repo.
- `github-policy-codeowners`: adds CODEOWNERS and code-owner review to this ruleset once a second contributor joins.
