---
name: github-policy-codeowners
description: |
  Set up `.github/CODEOWNERS` for multi-contributor repos, and flip the
  ruleset's `require_code_owner_review` flag once owners are defined.
  Apply when more than one person can merge to the default branch.
tags: [setup]
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# github-policy-codeowners

When more than one person can merge to the default branch, define code
owners so the right reviewer gets pulled into each PR automatically.
Pairs with the `require_code_owner_review` flag in
`github-policy-protect-default-branch`'s ruleset.

## How to load this skill

Loading this skill doesn't mean you should create a CODEOWNERS file
now — just that when onboarding a second contributor or auditing
review rules, you'll consider this setup.

## Create `.github/CODEOWNERS`

GitHub uses [.github/CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositories-settings-and-features/customizing-your-repository/about-code-owners)
to map paths to required reviewers. Simple example:

```
# Default owner for everything in the repo.
*       @owner

# More specific paths override the default.
/docs/  @docs-team
/api/   @backend-team @owner
*.tf    @infra-team
```

Patterns follow `.gitignore`-style globbing. The last matching pattern
wins.

## Flip the ruleset flag

Once `.github/CODEOWNERS` is in place, update the ruleset created by
`github-policy-protect-default-branch` so PRs require approval from a code
owner of the changed paths:

```bash
# Fetch the existing ruleset.
gh api "repos/<owner>/<repo>/rulesets" --jq '.[] | select(.name=="protect-default-branch") | .id'

# Update the pull_request rule's parameters via the ruleset's update endpoint.
# (Edit the rules array to add require_code_owner_review: true to the pull_request rule.)
```

## When to apply

- Onboarding a second contributor with merge rights.
- Auditing an existing repo's review requirements.
- After applying `github-policy-protect-default-branch`, when you're ready
  to require code-owner review.
