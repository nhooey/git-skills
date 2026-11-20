---
name: git-hygiene-push-force-safely
description: |
  Force-push only with `git push --force-with-lease`, never plain
  `git push --force` or `-f`. The lease rejects the push if the remote tip
  changed since your last fetch, so a collaborator's commits aren't
  silently clobbered; `--force-if-includes` also covers a background fetch.
  Ships an allow rule for `--force-with-lease` with the two hooks it needs,
  a git pre-push hook refusing rewrites and deletions of a default branch
  and a Claude Code hook denying pushes that skip it. Use whenever about
  to force-push, or when either hook refuses a push.
tags: [safety]
allowed-tools:
  - Bash
---

# Force-pushing safely

_Force-push with `--force-with-lease`, never plain `--force`, and stop to look when the lease rejects the push._

```bash
git push --force-with-lease
```

## Why

`--force-with-lease` checks that the remote tip is what you last
fetched before overwriting it. If a collaborator (or another machine of
yours) pushed in the meantime, the push is rejected instead of silently
clobbering their work. Plain `--force` will happily destroy commits you
have never seen.

## If `--force-with-lease` rejects the push

Stop and investigate; don't "fix" it by upgrading to `--force`.
Fetch, look at the remote tip, decide whether to rebase on top or
coordinate with whoever pushed.

## Close the autofetch hole with `--force-if-includes`

`--force-with-lease` trusts your remote-tracking ref — but a background
`git fetch` (an IDE's autofetch, another tool or session) can advance
that ref to commits you never looked at. The lease then checks against
the *fetched* tip and passes, so you can still clobber a collaborator's
work without seeing it.

```bash
git push --force-with-lease --force-if-includes
```

`--force-if-includes` (Git ≥ 2.30) also requires the remote-tracking tip
to be reachable from the local branch's reflog, that is, integrated into
your branch at some point, so a stray fetch alone no longer satisfies the
check. Pair it with the lease whenever a background fetch is plausible,
which on a shared branch is almost always.

## Pin the expected commit on shared branches

```bash
git push --force-with-lease=<branch>:<expected-sha>
```

Pins the exact SHA you expect to overwrite. This form doesn't consult
the remote-tracking ref at all, so it's also immune to the autofetch
problem above, and `--force-if-includes` has no effect beside it. Use
it when you know precisely what you're replacing.

## Force-pushing without a prompt, off default branches

`force-with-lease-allow-rule.nix`, beside this file, is a Claude Code
settings snippet for a user's Home Manager configuration holding one
allow rule, `Bash(git push --force-with-lease=*)`, so an agent can
force-push its own rebased pull request branch without a prompt.

The rule matches every branch, the default one too. It relies on a
server-side block of default-branch rewrites where GitHub allows one, a
ruleset as `github-policy-protect-default-branch` sets up, and on two
hooks everywhere else: private repositories on GitHub Free, which can't
have rulesets, and forks. Never install the rule without both hooks:

- **`scripts/pre-push`**, a git pre-push hook for every repository,
  through a global `core.hooksPath` pointed at the flake package
  `git-hooks-default-branch-guard`, a folder holding it. It refuses an
  update of the remote's default branch that isn't a fast-forward, a
  push over a remote tip the repository doesn't have among them, and a
  deletion of it. The default branch is `refs/remotes/<remote>/HEAD`'s,
  else the remote's `HEAD` from `git ls-remote --symref`; with neither,
  `master` and `main` are guarded. It then runs the repository's own
  `.git/hooks/pre-push`, which a global `core.hooksPath` hides, with the
  same arguments and stdin, and exits with its status.
- **`scripts/push-hook-bypass-guard.sh`**, a Claude Code PreToolUse hook
  in the repository's `git-skills-hooks` plugin. It denies a `git push`
  that skips the pre-push hook: `--no-verify`, `git -c core.hooksPath=…`,
  `git --config-env`, or a `GIT_CONFIG_*` variable such as
  `GIT_CONFIG_PARAMETERS` set on the command. `git push -n` is
  `--dry-run` and passes. `- Push guard: deny|remind|off` in this
  skill's preferences file turns it down.

A repository whose own config sets `core.hooksPath`, as husky does,
overrides the global one, and the pre-push hook doesn't run there.

When the pre-push hook refuses a push, don't look for a way around it:
push to another branch and open a pull request, or fetch and rebase onto
the remote tip it names.

## When to apply

- About to force-push for any reason.
- After amending a commit on a branch that's already on the remote.
- After interactive-rebasing a branch that's already pushed.
- After squashing a PR's commits into one, as
  `github-hygiene-single-commit-pull-requests` does.
- Setting up the allow rule for `--force-with-lease` and its two hooks.
- When the pre-push hook or the PreToolUse hook refuses a push.

## Your preferences

!`cat "$(dirname "${CLAUDE_SKILL_DIR}")/git-hygiene-push-force-safely.preferences.md" "${CLAUDE_PROJECT_DIR}/.agents/skills/git-hygiene-push-force-safely.preferences.md" 2>/dev/null || true`

If your agent doesn't run the line above, read these files yourself if they
exist: `git-hygiene-push-force-safely.preferences.md` next to this skill's folder, then
`.agents/skills/git-hygiene-push-force-safely.preferences.md` in the project. A project's
file overrides the user's, and the user's overrides this skill's defaults.

The keys this skill reads, with its own defaults:

```markdown
- Push guard: deny
```

`Push guard` is `deny`, `remind` or `off`: what the PreToolUse hook does
with a `git push` that skips the pre-push hook.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `github-hygiene-single-commit-pull-requests`: squashes a PR into one commit, then force-pushes it with a lease.
- `github-policy-protect-default-branch`: the GitHub ruleset that blocks force pushes and deletion of the default branch on the server.
