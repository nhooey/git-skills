---
name: github-workflow-pull-request-stacked
description: |
  Submit a chain of dependent PRs on GitHub, picking the tool by case:
  GitHub's own stacked PRs (`gh stack`) for a same-repo linear chain,
  Graphite (`gt`) for branching stacks or users already on it, and
  plain git for forks. Covers three cases: (a) repos you control, with
  `gh stack submit`, merging the top PR or queueing the stack, and `gh stack
  sync`; (b) upstream fork-only, where native stacks don't reach, so
  draft status and `Depends on` notes gate merge order and
  `git rebase --update-refs` restacks; (c) upstream with a topic-branch
  push grant, using `gh stack` or `gt submit --stack` under the required
  branch prefix. Also covers adopting a hand-built stack into
  `gh stack`, flags for agent sessions, and what to do where
  force-pushing PR branches isn't allowed. Use when the user mentions
  stacked PRs, dependent PRs, `gh stack` or `gt`, or asks how to keep
  child-PR diffs small while parents are in flight.
tags: [workflow, team-stance, reference]
allowed-tools:
  - Bash
  - Read
---

# Stacked pull requests

_A chain of dependent PRs, each building on the one below, kept so every child PR shows only its own change; which tool does it depends on who controls the merge button._

Three cases:

- **§A, a repo you control:** you have write access and merge yourself.
  `gh stack submit`, then merge the stack from the top or through the
  merge queue.
- **§B, upstream with no push access (fork-only):** you push only to
  your fork. A PR's base must be a branch in the upstream repo and
  native stacks don't cross forks, so child PRs can't be incremental;
  draft status and `Depends on` notes manage the order instead.
- **§C, upstream with a topic-branch prefix granted:** some projects
  (LLVM, for one) let contributors push to upstream under a prefix,
  often `users/<username>/`. The branches live upstream, so it works
  like §A plus the prefix.

Each PR in the stack is still a single-commit PR governed by
`github-hygiene-pull-request-mirrors-commit`, and every restack
force-pushes, so `git-hygiene-push-force-safely` applies.

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

The stack's metadata lives in `<git common dir>/gh-stack`, so every
worktree of the clone shares it, and a branch checked out in another
worktree can join a stack without being checked out here. `gh stack`
never stashes, creates worktrees or switches another worktree's branch:
a dirty or busy worktree that owns a branch stops `rebase` and `sync`,
so keep those worktrees idle while it rewrites history.

GitHub also publishes an agent skill for the extension,
`gh skill install github/gh-stack`. It sits alongside this one: it
covers the `gh stack` commands and their flags, and this skill covers
which case and tool apply, forks, force-push policy and the PR
conventions. Where the two differ on a command's behaviour, the
extension's skill and `gh stack <command> --help` win, since they move
with the extension.

**Graphite**, when it's the tool: initialize it with the repo's
default branch as trunk. Submitting needs an auth token, which the user
creates at Graphite's CLI settings page and passes to `gt auth --token`.

```bash
gt init --trunk main     # or master; without --trunk it prompts
```

Other settings, such as a branch prefix, live in `gt config`, an
interactive menu whose `--help` lists none of them and whose wording
changes between releases; have the user run it rather than quoting
menu paths. From an agent session, pass the global `--no-interactive`
flag so `gt` doesn't wait on a prompt.

For §B and §C, make sure `origin` is your fork and `upstream` the repo
you're contributing to:

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

**From an agent session,** where there is no terminal for the editor,
`gh stack submit` needs `--auto`: it skips the editor, uses generated
titles and opens new PRs as drafts unless `--open` is given. Re-sync
each PR's title and body with
`github-hygiene-pull-request-mirrors-commit`'s script afterwards.

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

`sync` fast-forwards the trunk, rebases the stack onto it, pushes,
and links the open PRs into a stack on GitHub; `--prune` deletes local
branches whose PRs merged. On a rebase conflict it restores every
branch and leaves the resolving to `gh stack rebase`. When the local
stack and the one on GitHub have diverged, a non-interactive `sync`
stops without pushing anything and still exits 0, so read its output
("Stack synced" or "Branches synced") rather than its exit status.

**Rules apply to every layer.** Every PR in a stack must meet the
trunk's branch protection, CODEOWNER approvals and required checks,
not only the bottom one. CI for the default branch runs for every PR in
the stack; a workflow can read `github.event.pull_request.stack` to
skip expensive jobs on the upper layers. Merge requirements can't be
bypassed for a stack.

**Automation needs the new merge API.** The legacy pull request merge
endpoints can't merge a stack; scripts and bots must use the
asynchronous merge API.

**Force-pushes.** `gh stack push` pushes every branch in one atomic
`git push` with a `--force-with-lease` check per branch, and `sync`
uses `--force-with-lease` after a rebase. Don't fall back to a plain
`--force` by hand.

**When force-pushing isn't allowed.** Every stacking tool here updates
a stack by rebasing and force-pushing the branches above a change. That
is at odds with a rule against force-pushing to PR branches, the
project's or the user's (`git-hygiene-push-force-safely` covers how to
force-push when it is allowed); it is not at odds
with `github-policy-merge-commits-only`, which governs how each PR
merges into the trunk. Choose by the rule:

- **Force-pushing PR branches is allowed** (with a lease): use
  `gh stack` as above.
- **It isn't:** don't stack with a tool. Open each PR with
  `gh pr create --base <branch below>`, and when a branch below
  changes, `git merge` it into each branch above and push normally.
  The child branches gain merge commits, and the PRs are never linked
  as a stack on GitHub.
- **Unsure:** ask before the first restack, since a force-push can't
  be taken back once a reviewer has fetched the branch.

**When to flatten the stack.** Stacking is for changes that are
independently reviewable. Refactor + use-of-refactor is one PR, not
two, unless the refactor stands on its own and you want it merged
separately. Three or four PRs in a stack is the sweet spot; ten is a
smell.

**Conflicts during restack.** `gh stack rebase` restacks the chain one
branch at a time; resolve each conflict, `git add <files>`, and
`gh stack rebase --continue` (or `--abort` to restore every branch).
To drop, fold, insert, reorder or rename branches, the user runs
`gh stack modify`, an interactive TUI an agent can't drive; it refuses
merged branches and needs a linear history with nothing queued.

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
local copies. On conflicts, resolve, `git add <files>`, `gt continue`.
To change a branch in the middle, check it out and `gt modify`: it
amends the branch and restacks the ones above. `gt submit` pushes with
`--force-with-lease` unless given `--force`.

## §B — Upstream, no push access (fork-only)

Before giving commands, explain why no stacking tool gives small diffs
here, because it shapes everything else.

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

Draft status is the only thing that blocks an out-of-order merge from
the contributor's side; the `Depends on` note is a courtesy, not a
gate.

When PR #1 merges, restack the rest onto the updated upstream trunk in
one command (git ≥ 2.38):

```bash
git fetch upstream
git switch feat-second                         # the top of the stack
git rebase --update-refs upstream/main         # moves every branch in the chain
git push --force-with-lease origin feat-second # and every other branch it moved
```

`--update-refs` skips any branch checked out in another worktree, so
rebase that one on its own or free it first. After the rebase, the next child's diff shows only its own changes.
**Mark that child "Ready for review"** in the GitHub UI, and repeat
down the stack as each parent lands. On conflicts, resolve,
`git add <files>`, `git rebase --continue`.

A user already on Graphite can use `gt sync` for the restack instead;
`gt submit --stack` against a fork you don't own tries to push
intermediate branches upstream and fails, so submit to the fork and
open the PRs by hand.

## §C — Upstream with topic-branch push grant

If the project grants topic-branch push access, prefer this over §B:
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
- **`gt`:** have the user set the prefix in `gt config` first, then:

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
a PR inside a native stack can't be changed through the API.

**Adopting a stack built by hand,** with each PR's base set by
`gh pr create --base` or by another tool, takes two commands:

```bash
gh stack init --base main feat-first feat-second feat-third   # bottom to top; adopts the existing branches
gh stack sync                                                 # links their open PRs into a stack on GitHub
```

`init` adopts branches that already exist, including ones checked out
in other worktrees. `sync` links the PRs once two or more are open; it
never opens PRs, so `gh stack submit` opens any that are missing.
`gh stack link` does it without local tracking: it takes branch names,
PR numbers or URLs, bottom to top, pushes the branches, opens PRs for
any without one, and never removes a PR from a stack, so on an
existing stack it can only add to the top.

## How to advise the user

When the user asks for help with this workflow, structure the response
as:

1. One sentence identifying which case they're in (§A, §B or §C), or
   asking if unclear. The fastest tell: do they have write access to
   the repo? Yes → §A. No, but maintainers granted a branch prefix →
   §C. No, fork only → §B.
2. The tool, by [Choosing a tool](#choosing-a-tool), and its exact
   commands for their case, in order.
3. For §B only: the draft / `Depends on` convention.
4. For §B only: a one-line reminder that draft status is the only real
   merge-ordering gate available to a no-access contributor.

## Alternatives considered

Mention these if the user pushes back on the tools above:

- **ghstack:** Meta's stacking tool; clean, but it assumes you can push
  intermediate branches somewhere with a stable mapping, so it's a
  poor fit for §B and better in §A or §C.
- **spr** (Rust and Go variants): one commit per PR, from the
  Phabricator lineage; opinionated about commit structure, lighter
  than Graphite, with the same upstream-push limit as ghstack in §B.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `git-hygiene-push-force-safely`: push restacked branches with `--force-with-lease`, as `gt` does.
- `github-hygiene-pull-request-mirrors-commit`: one commit per PR, title and body mirroring it; `gh stack submit` sets titles and bodies in its editor, so re-sync them with that skill's script afterwards.
- `github-policy-auto-delete-merged-branches`: deletes each merged head branch on the remote, so `gh stack sync` and `gt sync` clean up the local copies.
- `github-policy-merge-commits-only`: merge commits, which give one merge commit per PR in a native stack and let `gt sync` detect merged PRs by SHA.
