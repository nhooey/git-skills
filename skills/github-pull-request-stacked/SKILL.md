---
name: github-pull-request-stacked
description: |
  Submit a chain of dependent PRs on GitHub. Covers three cases:
  (a) repos you control — `gt submit --stack`, merge bottom-first,
  `gt sync` after each parent merges; (b) upstream fork-only — draft
  + `Depends on` notes to gate merge order, `gt sync` for restacking;
  (c) upstream with topic-branch push grant — full `gt submit --stack`
  under a maintainer-required branch prefix. Apply when the user
  mentions stacked PRs, dependent PRs, `gt`, or asks how to keep
  child-PR diffs small while parents are in flight.
tags: [workflow, team-stance, reference]
allowed-tools:
  - Bash
  - Read
---

# github-pull-request-stacked

This skill captures the workflow for submitting a chain of **dependent**
pull requests — where each PR builds on the previous, and the child
PRs' diffs would otherwise show the cumulative change. The workflow has
three flavors keyed on who controls the merge button:

- **§A — Repo you control.** Full write access, you merge things
  yourself. The easy case: `gt submit --stack`, merge bottom-first,
  `gt sync` after each.
- **§B — Upstream, no push access (fork-only).** You have a fork, you
  push to your fork, but you can't push branches to upstream. The hard
  case: GitHub will only let a PR's base be a branch in the upstream
  repo, so child PRs can't be incremental — diff management happens
  via draft status and `Depends on` notes.
- **§C — Upstream, maintainer-granted topic-branch prefix.** Some
  projects (LLVM is the canonical example) grant contributors push
  access to upstream under a naming prefix (often `users/<username>/`).
  Then full Graphite stacking works against upstream — same shape as
  §A, plus the branch-prefix requirement.

Each PR in the stack is still a single-commit PR — this skill is
compatible with [`github-hygiene-pull-request-mirrors-commit`](../github-hygiene-pull-request-mirrors-commit),
which governs the title/body/commit relationship for any one PR in the
chain. And every restack force-pushes to a branch, so
[`git-hygiene-push-force-safely`](../git-hygiene-push-force-safely) applies — `gt` uses
`--force-with-lease` by default.

## Common setup

Initialize Graphite and set trunk to the repo's default branch:

```bash
gt init
# When prompted for the trunk branch, choose the default (main or master).
gt config --help     # later, to discover trunk / branch-naming settings
```

The `gt config` menu wording changes between Graphite releases, so
`gt config --help` is the durable entry point — don't hard-code menu
paths in advice to the user.

For §B and §C, also make sure the remotes are conventional —
`origin` → your fork, `upstream` → the repo you're contributing to:

```bash
git remote -v        # confirm origin = your fork, upstream = the target
git remote add upstream <url-of-the-repo-you-dont-control>   # if missing
git fetch upstream
```

For §A there is only `origin`, and it points at the repo you control.

## §A — Repo you control

The easy case. Build the stack locally:

```bash
gt checkout main
gt create -am "feat: first change"     # PR #1
gt create -am "feat: second change"    # PR #2, stacked on #1
gt create -am "feat: third change"     # PR #3, stacked on #2
gt submit --stack                      # opens/updates all PRs at once
```

Each PR's base is the branch below it, so child diffs are incremental
and reviewers see only the per-PR change.

**Merge bottom-first.** Click merge on PR #1. Then back in the working
tree:

```bash
gt sync          # pulls the merged change into local trunk,
                 # detects #1 is merged, offers to delete its branch,
                 # restacks the rest of the chain onto the updated trunk
gt submit --stack
```

Repeat for PR #2, then #3.

**Merge-strategy interaction.** `gt sync` detects merged PRs by SHA
when the repo uses merge commits (see
[`github-policy-merge-commits-only`](../github-policy-merge-commits-only)) and by
patch-id when it uses squash merge. Both work cleanly; rebase-merge
also works but is the noisiest of the three for stacking — prefer
merge-commits-only or squash. With
[`github-policy-auto-delete-merged-branches`](../github-policy-auto-delete-merged-branches)
enabled, the remote head branches vanish on merge and `gt sync` will
clean up the local copies.

**When to flatten the stack.** Stacking is for changes that are
independently reviewable. Refactor + use-of-refactor is one PR, not
two, unless the refactor stands on its own and you want it merged
separately. Three or four PRs in a stack is the sweet spot; ten is a
smell.

**Conflicts during restack.** If `gt sync` reports conflicts, resolve
one branch at a time:

```bash
# resolve conflicts in editor → git add <files> → gt continue
```

Or use `gt modify` to edit a branch in the middle of the stack;
children auto-restack on top.

## §B — Upstream, no push access (fork-only)

The hard case. Before giving commands, make sure the user understands
*why* a naive `gt submit` won't work here, because it shapes
everything.

By default Graphite wants to push each branch in the stack to the
**base repository** so it can open one PR per branch with each PR
based on the branch below it — that's what produces the clean small
per-PR diffs in §A. But on a repo you don't control, you can't push
those intermediate branches to upstream. And GitHub will only let a
PR's base be a branch in the upstream repo, so the second-and-later
PRs can't be based on the previous fork branch — they'd be based on
upstream `main` and show the cumulative diff. This is the same wall
we hit without Graphite; `gt` doesn't magically remove it.

The strategy is: keep the stack locally, expose only one PR at a time
as "ready", and rely on draft status to stop maintainers merging out
of order.

Build the local stack against the upstream trunk:

```bash
gt checkout main
gt create -am "feat: first change"     # this becomes PR #1
gt create -am "feat: second change"    # stacked locally on the first
```

Push branches to your fork and open the PRs. Each PR's base will be
upstream `main`, so do the diff management with draft status + clear
dependency notes rather than pretending the diffs will be incremental:

- Open **PR #1** as a normal (ready) PR — it's the only one whose
  diff is honest against `main`.
- Open **each later PR as a draft** so its merge button is disabled,
  and in its description write `Depends on #<parent>` so GitHub
  renders the link and the maintainer sees the chain. Prefix titles
  like `[2/4]` for legibility.

The draft status is the only thing that *actually* blocks an out-of-
order merge from the contributor side; the `Depends on` note is a
courtesy signal, not a gate.

When PR #1 merges, collapse the next child's diff and promote it:

```bash
gt sync          # pulls the merged change into local trunk, restacks the remaining branches
```

After `gt sync` rebases the next child onto the updated upstream
`main`, its diff now shows only its own changes. Push the updated
branch to your fork (Graphite does this as part of submit), then
**mark that child "Ready for review"** in the GitHub UI. Repeat down
the stack as each parent lands.

If `gt sync` reports conflicts during the restack, resolve them one
branch at a time (`gt continue` after each), same as §A.

### Why draft + gt sync rather than the fancier path

`gt submit --stack` against a fork you don't own will try to push
intermediate branches upstream and fail. So in §B you submit branches
to the fork and open PRs manually (or with `gt submit` configured to
target the fork), and lean on draft status for ordering. The value
Graphite adds here is purely `gt sync`'s automatic restacking — it
spares you hand-rebasing every child after each merge.

## §C — Upstream with topic-branch push grant

The workflow Graphite is built for. If the project grants topic-branch
push access, prefer this over §B — it gives the small per-PR diffs the
user wants.

**Branch naming matters.** Many projects that grant this access require
a prefix (often `users/<username>/`) so `gt submit` doesn't litter the
upstream namespace. Set it before submitting (look up the current flag
or interactive path via `gt config --help`), including the trailing
`/`, or submit will fail.

Then build and submit the stack:

```bash
gt checkout main                       # the upstream trunk
gt create -am "feat: first change"     # PR #1
gt create -am "feat: second change"    # PR #2, stacked on #1
gt submit --stack                      # opens/updates all PRs in the stack
```

When a parent PR merges, sync and let Graphite restack the rest onto
the updated trunk:

```bash
gt sync          # pulls trunk, detects merged PRs, offers to delete merged branches and restack
gt submit --stack
```

If a restack hits conflicts, resolve them branch by branch:

```bash
gt modify        # edit a branch; children auto-restack on top
# or, for conflicts during a restack:
#   resolve in editor → git add <files> → gt continue
```

## How to advise the user

When the user asks for help with this workflow, structure the response
as:

1. One sentence identifying which case they're in (§A, §B, or §C) — or
   asking, if unclear. The fastest tell: do they have write access to
   the repo? Yes → §A. No, but maintainers granted a branch prefix →
   §C. No, fork only → §B.
2. The exact `gt` commands for their case, in order.
3. For §B only: the draft / `Depends on` convention.
4. For §B only: a one-line reminder that draft status is the only real
   merge-ordering gate available to a no-access contributor.

Keep it concrete and command-first. Don't re-explain git fundamentals
unless the user signals they're new to forks and remotes.

## Alternatives considered

Mention these if the user pushes back on Graphite or hits friction:

- **ghstack** — Meta's stacking tool; clean but assumes you can push
  intermediate branches somewhere with a stable mapping, so it's a
  poor fit for §B. Better in §A or §C.
- **spr** (Rust/Go variants) — one-commit-per-PR model from the
  Phabricator lineage; opinionated about commit structure, lighter
  than Graphite, same upstream-push limitation as ghstack in §B.
- **Plain `git rebase --update-refs`** (git ≥ 2.38) — no external
  tool; restacks a chain of local branches in one command. Covers the
  "restack children after a parent merges" pain, which is 80% of the
  manual tedium, with zero dependencies. Pairs especially well with
  §A and is a reasonable substitute in §B.

Recommend `git rebase --update-refs` over Graphite for a one-off stack
(less to install for a single use); recommend Graphite when the user
does this regularly, or specifically in §C where its `--stack` submit
against upstream is the whole point.
