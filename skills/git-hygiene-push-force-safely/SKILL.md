---
name: git-hygiene-push-force-safely
description: |
  Never run plain `git push --force` or `git push -f`. Always use
  `git push --force-with-lease`, which rejects the push if the remote
  tip changed since your last fetch — preventing silent clobbering of a
  collaborator's commits. Apply whenever about to force-push.
tags: [safety]
allowed-tools:
  - Bash
---

# git-hygiene-push-force-safely

Never run plain `git push --force` or `git push -f`. Always:

```bash
git push --force-with-lease
```

## How to load this skill

Passive reference. Loading it doesn't mean the user wants you to
force-push now — just that when you do force-push, you'll use the safer
flag.

## Why

`--force-with-lease` checks that the remote tip is what you last
fetched before overwriting it. If a collaborator (or another machine of
yours) pushed in the meantime, the push is rejected instead of silently
clobbering their work. Plain `--force` will happily destroy commits you
have never seen.

## If `--force-with-lease` rejects the push

**Stop and investigate** — do not "fix" it by upgrading to `--force`.
Fetch, look at the remote tip, decide whether to rebase on top or
coordinate with whoever pushed.

## Close the autofetch hole with `--force-if-includes`

`--force-with-lease` trusts your remote-tracking ref — but a background
`git fetch` (an IDE autofetch, `fetch.prune`, another tool) can advance
that ref to commits you never looked at. The lease then checks against
the *fetched* tip and passes, so you can still clobber a collaborator's
work without seeing it.

```bash
git push --force-with-lease --force-if-includes
```

`--force-if-includes` (Git ≥ 2.30) additionally requires that the remote
commits being overwritten are reachable from a local ref you've actually
integrated — so a stray fetch alone no longer satisfies the check. Pair
it with lease whenever a background fetch is plausible, which on a shared
branch is almost always.

## Extra paranoia on shared branches

```bash
git push --force-with-lease=<branch>:<expected-sha>
```

Pins the exact SHA you expect to overwrite. This form doesn't consult
the remote-tracking ref at all, so it's also immune to the autofetch
problem above — use it when you know precisely what you're replacing.

## When to apply

- About to force-push for any reason.
- After amending a commit on a branch that's already on the remote.
- After interactive-rebasing a branch that's already pushed.
