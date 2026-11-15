---
name: github-policy-codeowners
description: |
  Set up `.github/CODEOWNERS` so the right reviewer is requested on each
  PR, then turn on `require_code_owner_review` in the default-branch
  ruleset once owners are defined. Use when more than one person can merge
  to the default branch, when onboarding a second contributor with merge
  rights, or when auditing a repo's review requirements.
tags: [setup]
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# Code owners

_Map paths to owners in `.github/CODEOWNERS`, then make the default-branch ruleset require a code owner's approval._

Loading this skill doesn't mean creating a CODEOWNERS file now; apply
it when a repo gets a second contributor with merge rights or its review
rules are being audited.

## Create `.github/CODEOWNERS`

GitHub uses [CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
to map paths to required reviewers. A simple example:

```text
# Default owner for everything in the repo.
*       @owner

# More specific paths override the default.
/docs/  @docs-team
/api/   @backend-team @owner
*.tf    @infra-team
```

- Patterns follow most `.gitignore` rules, but `!` negation and `[ ]`
  character ranges don't work.
- The last matching pattern wins, so put the default first.
- All owners of a pattern go on its one line.
- Every owner, user or team, needs explicit write access to the
  repository; an owner without it is not assigned.

## Require code-owner review in the ruleset

Once `.github/CODEOWNERS` is on the default branch, update the ruleset
created by `github-policy-protect-default-branch` so PRs need approval
from a code owner of the changed paths. A PUT replaces the ruleset's
whole `rules` array, so build it from the current rules rather than
retyping them:

```bash
RULESET_ID=$(gh api "repos/<owner>/<repo>/rulesets" \
  --jq '.[] | select(.name=="protect-default-branch") | .id')

# Keep every rule; on the pull_request rule, require code-owner review and
# at least one approval, filling the other parameters the API requires.
gh api "repos/<owner>/<repo>/rulesets/$RULESET_ID" --jq '{rules: [.rules[] |
  if .type == "pull_request" then
    .parameters = ({dismiss_stale_reviews_on_push: false,
                    require_last_push_approval: false,
                    required_review_thread_resolution: false}
                   + (.parameters // {}))
    | .parameters.require_code_owner_review = true
    | .parameters.required_approving_review_count |= ([., 1] | max)
  else . end]}' |
  gh api -X PUT "repos/<owner>/<repo>/rulesets/$RULESET_ID" --input -
```

`require_code_owner_review` lives in the `pull_request` rule's
`parameters`, and the API marks all five of its parameters required
(the three above, `require_code_owner_review` and
`required_approving_review_count`). The bare `{ "type": "pull_request" }`
rule in `github-policy-protect-default-branch` has no `parameters`
block; this fills one in. If the ruleset has no `pull_request` rule,
add one before running this.

Check the CODEOWNERS file itself before relying on enforcement:

```bash
gh api "repos/<owner>/<repo>/codeowners/errors"   # → empty errors array = valid
```

## When to apply

- Onboarding a second contributor with merge rights.
- Auditing an existing repo's review requirements.
- After applying `github-policy-protect-default-branch`, when you're
  ready to require code-owner review.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `github-policy-protect-default-branch`: the default-branch ruleset whose `require_code_owner_review` flag this skill turns on.
