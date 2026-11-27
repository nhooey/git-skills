---
name: github-policy-no-hosted-ci
description: |
  Keep hosted CI out of a GitHub repository: no `.github/workflows/`, no
  `garnix.yaml`, no other hosted CI config. `nix flake check` is the test,
  run locally before every push, and a pull request with no check runs is
  expected. A repository that exists to benchmark CI is exempt. Use when
  creating a repository, adding tests or a release step, auditing a
  repository's CI config, or wondering why a PR has no checks.
tags: [setup, team-stance]
allowed-tools:
  - Bash
  - Read
---

# No hosted CI

_A repository commits no hosted CI config. Its tests are flake checks, and `nix flake check` runs them locally before every push. This is a team stance: a team that relies on hosted CI skips this skill._

Loading this skill is not a request to change a repository now; it applies when one is being created, given tests or audited.

## The rule

- **No GitHub Actions workflows:** nothing under `.github/workflows/`.
- **No Garnix:** no `garnix.yaml`.
- **No other hosted CI config:** no CircleCI, Travis, Buildkite or the
  like.

An audit that finds one proposes removing it in a pull request of its
own, with the checks it ran moved into the flake first.

## Testing instead

- **Every check is a flake output.** Tests, lint and formatting go in the
  flake's `checks`, so `nix flake check` runs all of them and anyone can
  run them on their own machine.
- **Run `nix flake check` before every push,** and before calling a change
  done. A PR is opened only once it passes.
- **Check what ships by hand.** After pushing a release, a package or a
  published artifact, install or fetch it and try it end to end; no
  hosted job does this.

## What to expect on a pull request

- **No check runs.** A PR shows none, and a PR watcher reports none. That
  is the normal state, not a fault: don't wait for CI, and don't report
  its absence as a problem.
- **No required status checks.** A default-branch ruleset from
  `github-policy-protect-default-branch` leaves out
  `required_status_checks`, since no job would ever report one and every
  PR would stay blocked.

## The exemption

A repository that exists to benchmark or test hosted CI itself keeps its
workflows, since they are what it studies:
`nhooey/nix-github-actions-cache-bench`, which compares Nix binary
caches on GitHub Actions runners, is one. It still runs its flake checks
locally.

## The account setting

Whether GitHub Actions is turned on for the account's repositories is
an account setting, and the account's GitHub settings are managed
elsewhere. This skill governs only what a repository commits: with
Actions on or off, no workflow file goes in.

## When to apply

- Creating a repository: give it flake checks, and no CI config.
- Adding tests or a release step: make it a flake check or a documented
  manual step, not a workflow.
- Auditing a repository that has `.github/workflows/` or `garnix.yaml`.
- A PR has no check runs: that is expected; run `nix flake check`
  locally instead.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `github-policy-protect-default-branch`: the default-branch ruleset, which leaves out required status checks when no CI reports them.
- `github-workflow-pull-request-watcher`: watching an open PR, where no check-run events are the normal case.
