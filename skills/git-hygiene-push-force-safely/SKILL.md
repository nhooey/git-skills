---
name: git-hygiene-push-force-safely
description: |
  Force-push only with `git push --force-with-lease`, never plain
  `git push --force` or `-f`. The lease rejects the push if the remote tip
  changed since your last fetch, so a collaborator's commits aren't
  silently clobbered; `--force-if-includes` also covers a background fetch.
  Use whenever about to force-push.
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

## Let agents force-push without a prompt

A Claude Code allow rule in the user's settings lets an agent force-push its own rebased branches without asking:

```json
{ "permissions": { "allow": ["Bash(git push --force-with-lease=*)"] } }
```

The rule matches any branch, so it goes in only together with the bundled `scripts/pre-push` hook, in a folder set as the global `core.hooksPath`.
For a push to a remote's default branch, read from `refs/remotes/<remote>/HEAD`, else `master` or `main`, the hook refuses a deletion and any push that isn't a fast-forward, then runs the repository's own `.git/hooks/pre-push`.

A global `core.hooksPath` makes git skip every hook in a repository's `.git/hooks`, so the folder holds a hook for each one git documents in githooks(5).
Each runs the bundled `scripts/forward-hook`, which runs the repository's own hook of that name, if it has an executable one, with the same arguments and stdin, and exits with its status.
The root flake's `git-push-force-safely-hooks` package is that folder, for Home Manager's `programs.git.extraConfig.core.hooksPath`.
The hooks don't run for `git push --no-verify` or `git commit --no-verify`, nor in a repository whose own `core.hooksPath` overrides the global one.

## When to apply

- About to force-push for any reason.
- After amending a commit on a branch that's already on the remote.
- After interactive-rebasing a branch that's already pushed.
- After squashing a PR's commits into one, as
  `github-hygiene-single-commit-pull-requests` does.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `github-hygiene-single-commit-pull-requests`: squashes a PR into one commit, then force-pushes it with a lease.
