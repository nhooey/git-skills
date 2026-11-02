---
name: github-workflow-pull-request-stacked
description: |
  Submit a chain of dependent PRs on GitHub, picking the tool by case:
  GitHub's own stacked PRs (`gh stack`) for a same-repo linear chain,
  Graphite (`gt`) for branching stacks or users already on it, and
  plain git for forks. Covers three cases: (a) repos you control —
  `gh stack submit`, merge the top PR or queue the stack, `gh stack
  sync`; (b) upstream fork-only — native stacks don't support forks,
  so draft + `Depends on` notes gate merge order and
  `git rebase --update-refs` restacks; (c) upstream with a topic-branch
  push grant — `gh stack` or `gt submit --stack` under the required
  branch prefix. Apply when the user mentions stacked PRs, dependent
  PRs, `gh stack`, `gt`, or asks how to keep child-PR diffs small while
  parents are in flight.
tags: [workflow, team-stance, reference]
allowed-tools:
  - Bash
  - Read
---

# github-workflow-pull-request-stacked

This skill captures the workflow for submitting a chain of **dependent**
pull requests — where each PR builds on the previous, and the child
PRs' diffs would otherwise show the cumulative change. The workflow has
three flavors keyed on who controls the merge button:

- **§A — Repo you control.** Full write access, you merge things
  yourself. The easy case: `gh stack submit`, then merge the stack
  from the top or through the merge queue.
- **§B — Upstream, no push access (fork-only).** You have a fork, you
  push to your fork, but you can't push branches to upstream. The hard
  case: GitHub will only let a PR's base be a branch in the upstream
  repo, and native stacks don't cross forks, so child PRs can't be
  incremental — diff management happens via draft status and
  `Depends on` notes.
- **§C — Upstream, maintainer-granted topic-branch prefix.** Some
  projects (LLVM is the canonical example) grant contributors push
  access to upstream under a naming prefix (often `users/<username>/`).
  The branches then live in upstream, so stacking works against it —
  same shape as §A, plus the branch-prefix requirement.

Each PR in the stack is still a single-commit PR — this skill is
compatible with `github-hygiene-pull-request-mirrors-commit`,
which governs the title/body/commit relationship for any one PR in the
chain. And every restack force-pushes to a branch, so
`git-hygiene-push-force-safely` applies.

## Choosing a tool

| | `gh stack` (GitHub's own stacks) | Graphite `gt` | `git rebase --update-refs` |
| --- | --- | --- | --- |
| Stack lives | on GitHub, as a stack object linking the PRs | in local `.git` metadata | only in your branches |
| Merge | top PR merges the stack atomically; merge queue aware | each PR merged normally | each PR merged normally |
| Rules and CI | trunk's rules and checks apply to every layer | each PR's own base | each PR's own base |
| Forks | ❌ not supported | PRs open, but child diffs aren't incremental | works locally |
| Branching stacks | ❌ linear chain only | ✅ | ✅ |
| Cost | free, no extra account | free for personal repos; organization repos need a paid plan | free |

The rule:

- **Same repository, linear chain:** `gh stack`.
- **Fork-only, or a stack that branches:** plain git, or `gt` if the
  user already uses Graphite.
- **The user already runs Graphite on this repo:** keep `gt`; don't
  switch tools mid-stack (see [Mixing tools](#mixing-tools)).

Sources: GitHub's
[about stacked PRs](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs),
the [stacked PRs reference](https://docs.github.com/en/pull-requests/reference/stacked-pull-requests),
the [CLI commands](https://docs.github.com/en/pull-requests/reference/stacked-prs-cli-commands),
and [Graphite's pricing](https://graphite.com/pricing).

## Common setup

**`gh stack`** is a GitHub CLI extension. Repositories need no enabling:

```bash
gh extension install github/gh-stack
gh stack init        # tracks the stack locally; also turns on git rerere
```

**Graphite**, when it's the tool: initialize it and set trunk to the
repo's default branch.

```bash
gt init
# When prompted for the trunk branch, choose the default (main or master).
gt config --help     # later, to discover trunk / branch-naming settings
```

The `gt config` menu wording changes between Graphite releases, so
`gt config --help` is the durable entry point — don't hard-code menu
paths in advice to the user. Graphite's free plan covers personal
repositories only; an organization's repositories need a paid seat per
user.

For §B and §C, also make sure the remotes are conventional —
`origin` → your fork, `upstream` → the repo you're contributing to:

```bash
git remote -v        # confirm origin = your fork, upstream = the target
git remote add upstream <url-of-the-repo-you-dont-control>   # if missing
git fetch upstream
```

For §A there is only `origin`, and it points at the repo you control.

## §A — Repo you control

The easy case. Build the stack locally with `gh stack`:

```bash
gh stack init
gh stack add -Am "feat: first change"     # PR #1
gh stack add -Am "feat: second change"    # PR #2, stacked on #1
gh stack add -Am "feat: third change"     # PR #3, stacked on #2
gh stack submit                           # opens a PR per branch and links them as a stack
gh stack view                             # branches, PR links and states
```

Each PR's base is the branch below it, so child diffs are incremental
and reviewers see only the per-PR change. GitHub marks each PR with its
layer number and draws a stack map in the merge box.

**Merging.** Stacks merge bottom up:

- **Merge the top PR** to merge the whole stack at once, or
  `gh stack merge`. It is all-or-nothing.
- **Merge a PR in the middle** to merge it and everything below it; the
  PRs above retarget the trunk and are rebased automatically.
- **Merge queue:** a stack enters the queue as a unit.
- **Merge method:** merge commits give one merge commit per PR, as if
  each were merged on its own (see `github-policy-merge-commits-only`).

Then bring the local branches up to date:

```bash
gh stack sync        # fetch, rebase the rest, push, and update PR state
```

**Rules apply to every layer.** Every PR in a stack must meet the
trunk's branch protection, CODEOWNER approvals and required checks,
not only the bottom one. CI for the default branch runs for every PR in
the stack; a workflow can read `github.event.pull_request.stack` to
skip expensive jobs on the upper layers. Merge requirements can't be
bypassed for a stack.

**Automation needs the new merge API.** The legacy pull request merge
endpoints can't merge a stack; scripts and bots must use the
asynchronous merge API.

**Unverified:** whether `gh stack push` and `sync` force-push with
`--force-with-lease`. Check the extension's help before relying on it,
and never fall back to a plain `--force` by hand.

**When to flatten the stack.** Stacking is for changes that are
independently reviewable. Refactor + use-of-refactor is one PR, not
two, unless the refactor stands on its own and you want it merged
separately. Three or four PRs in a stack is the sweet spot; ten is a
smell.

**Conflicts during restack.** `gh stack rebase` restacks the chain one
branch at a time; resolve each conflict, `git add <files>`, and
continue. To reorder or edit a branch in the middle, use
`gh stack modify`; it refuses merged branches and needs a linear
history with nothing queued.

### With Graphite

For a stack that branches, or a user already on Graphite:

```bash
gt checkout main
gt create -am "feat: first change"     # PR #1
gt create -am "feat: second change"    # PR #2, stacked on #1
gt submit --stack                      # opens/updates all PRs at once
```

Merge PR #1, then:

```bash
gt sync          # pulls trunk, detects #1 is merged, offers to delete its
                 # branch, restacks the rest onto the updated trunk
gt submit --stack
```

Repeat for each PR. `gt sync` detects merged PRs by SHA with merge
commits and by patch-id with squash merges; rebase-merge works but is
the noisiest. With `github-policy-auto-delete-merged-branches` enabled,
the remote head branches vanish on merge and `gt sync` cleans up the
local copies. On conflicts, resolve, `git add <files>`, `gt continue`;
`gt modify` edits a branch in the middle and restacks its children.
`gt` force-pushes with `--force-with-lease` by default.

## §B — Upstream, no push access (fork-only)

The hard case. Before giving commands, make sure the user understands
*why* stacking tools can't give small diffs here, because it shapes
everything.

GitHub will only let a PR's base be a branch in the upstream repo. On a
repo you don't control, you can't push the intermediate branches there,
so the second-and-later PRs are based on upstream `main` and show the
cumulative diff. GitHub's own stacks don't help: cross-fork stacks
aren't supported (see
[github/gh-stack#46](https://github.com/github/gh-stack/issues/46)).
Graphite hits the same wall.

The strategy is: keep the stack locally, expose only one PR at a time
as "ready", and rely on draft status to stop maintainers merging out
of order.

Build the local stack against the upstream trunk as plain branches:

```bash
git switch -c feat-first upstream/main
# ...commit the first change...
git switch -c feat-second
# ...commit the second change, stacked locally on the first...
git push -u origin feat-first feat-second
```

Open the PRs from your fork. Each PR's base will be upstream `main`, so
do the diff management with draft status + clear dependency notes
rather than pretending the diffs will be incremental:

- Open **PR #1** as a normal (ready) PR — it's the only one whose
  diff is honest against `main`.
- Open **each later PR as a draft** so its merge button is disabled,
  and in its description write `Depends on #<parent>` so GitHub
  renders the link and the maintainer sees the chain. Prefix titles
  like `[2/4]` for legibility.

The draft status is the only thing that *actually* blocks an out-of-
order merge from the contributor side; the `Depends on` note is a
courtesy signal, not a gate.

When PR #1 merges, restack the rest onto the updated upstream trunk in
one command (git ≥ 2.38):

```bash
git fetch upstream
git switch feat-second                         # the top of the stack
git rebase --update-refs upstream/main         # moves every branch in the chain
git push --force-with-lease origin feat-second # each moved branch
```

After the rebase, the next child's diff shows only its own changes.
**Mark that child "Ready for review"** in the GitHub UI, and repeat
down the stack as each parent lands. On conflicts, resolve,
`git add <files>`, `git rebase --continue`.

A user already on Graphite can use `gt sync` for the restack instead;
`gt submit --stack` against a fork you don't own tries to push
intermediate branches upstream and fails, so submit to the fork and
open the PRs by hand.

## §C — Upstream with topic-branch push grant

If the project grants topic-branch push access, prefer this over §B —
it gives the small per-PR diffs the user wants. The branches live in
upstream, so both `gh stack` and `gt` work here; follow the project's
documented tool if it has one (LLVM documents Graphite).

**Branch naming matters.** Projects that grant this access usually
require a prefix (often `users/<username>/`), so branches don't litter
the upstream namespace. Include the trailing `/`, or the push fails.

- **`gh stack`:** name each branch with the prefix when adding it, then
  `gh stack submit`, merging as in §A. **Unverified:** whether
  `gh stack` has a setting that applies the prefix itself, and whether
  a contributor who isn't a collaborator can create a stack. If
  `submit` refuses, fall back to `gt` or §B.
- **`gt`:** set the prefix first (look up the current flag or
  interactive path via `gt config --help`), then:

  ```bash
  gt checkout main                       # the upstream trunk
  gt create -am "feat: first change"     # PR #1
  gt create -am "feat: second change"    # PR #2, stacked on #1
  gt submit --stack                      # opens/updates all PRs in the stack
  ```

  When a parent merges, `gt sync` then `gt submit --stack`; on
  conflicts, `gt modify` or resolve and `gt continue`.

**Check how the project merges.** With `gh stack`, every layer is held
to the trunk's rules, and a project whose bots merge through the legacy
merge endpoints can't merge a stack. Ask, or look at its merge
tooling, before choosing native stacks there.

## Mixing tools

Don't run `gt` and `gh stack` on the same stack: each keeps its own
idea of the chain and retargets PR bases its own way, and the base of
a PR inside a native stack can't be changed through the API. To bring
PRs made by another tool into a native stack, `gh stack link` takes
branch names or PR numbers, bottom to top; it can only add PRs to the
top of an existing stack.

## How to advise the user

When the user asks for help with this workflow, structure the response
as:

1. One sentence identifying which case they're in (§A, §B, or §C) — or
   asking, if unclear. The fastest tell: do they have write access to
   the repo? Yes → §A. No, but maintainers granted a branch prefix →
   §C. No, fork only → §B.
2. The tool, by [Choosing a tool](#choosing-a-tool), and its exact
   commands for their case, in order.
3. For §B only: the draft / `Depends on` convention.
4. For §B only: a one-line reminder that draft status is the only real
   merge-ordering gate available to a no-access contributor.

Keep it concrete and command-first. Don't re-explain git fundamentals
unless the user signals they're new to forks and remotes.

## Alternatives considered

Mention these if the user pushes back on the tools above:

- **ghstack** — Meta's stacking tool; clean but assumes you can push
  intermediate branches somewhere with a stable mapping, so it's a
  poor fit for §B. Better in §A or §C.
- **spr** (Rust/Go variants) — one-commit-per-PR model from the
  Phabricator lineage; opinionated about commit structure, lighter
  than Graphite, same upstream-push limitation as ghstack in §B.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `git-hygiene-push-force-safely`: push restacked branches with `--force-with-lease`, as `gt` does.
- `github-hygiene-pull-request-mirrors-commit`: one commit per PR, title and body mirroring it; `gh stack submit` sets titles and bodies in its editor, so re-sync them with that skill's script afterwards.
- `github-policy-auto-delete-merged-branches`: deletes each merged head branch on the remote, so `gh stack sync` and `gt sync` clean up the local copies.
- `github-policy-merge-commits-only`: merge commits, which give one merge commit per PR in a native stack and let `gt sync` detect merged PRs by SHA.
