---
name: github-hygiene-gh-cli-gotchas
description: |
  Known traps in the `gh` CLI for PR workflows: `gh pr edit` exits 1
  on a Projects-classic deprecation warning without applying the edit
  (workaround: REST PATCH); `gh pr view --json` accepts a narrower set
  of fields than the GraphQL `pullRequest` type, so `merged` and
  `reviewThreads` (among others) error out — and the failure is
  invisible under `2>/dev/null` watchers; GitHub blocks self-approval;
  the `branches/<branch>/rename` API auto-closes open PRs whose head
  is that branch. Passive reference — load when using `gh` for non-
  trivial PR operations.
tags: [reference]
allowed-tools:
  - Bash
  - Read
---

# github-hygiene-gh-cli-gotchas

Four failure modes worth knowing before they cost a debugging detour.
All observed against `gh` 2.85+ and the current GitHub REST API.

## How to load this skill

Passive reference. Loading it doesn't trigger any action — just gives
you the workarounds when these specific traps come up.

## `gh pr edit` exits 1 on a Projects-classic deprecation warning, without applying the edit

Symptom:

```
$ gh pr edit 3 --body-file body.md
GraphQL: Projects (classic) is being deprecated in favor of the new
Projects experience, see: https://github.blog/changelog/2024-05-23-...
$ echo $?
1
```

The body is *not* updated despite no other error. The warning fires
because `gh pr edit` queries the deprecated
`repository.pullRequest.projectCards` field in its standard request
set.

**Workaround:** skip `gh pr edit` and PATCH directly through the REST
API, which doesn't touch Projects classic:

```bash
gh api --method PATCH "/repos/<owner>/<repo>/pulls/<num>" \
  -f body="$(cat body.md)"
```

Use `-f` (`--raw-field`), not `-F` (`--field`), for prose fields:
`-F` auto-types and silently turns a body of `"42"` into the JSON
number `42`. Prefer shell substitution (`$(cat …)`, `$(git log -1
--pretty=%b)`) over `--field body=@path` — no stale `/tmp` file, no
race with a parallel agent.

## `gh pr view --json` rejects field names that aren't on its allow-list

The fields `gh pr view --json` exposes are a strict subset of the
GraphQL `pullRequest` type. Two ways to get bitten:

1. **Inventing a field name** because it sounds reasonable.
   `--json merged` is the classic — the accessor is `state` (emits
   `OPEN` / `MERGED` / `CLOSED`) or `mergedAt` (non-null when
   merged), not `merged`.
2. **Borrowing a field from the GraphQL type** that `gh pr view
   --json` doesn't surface. `reviewThreads` is the canonical
   example: it exists on the GraphQL `pullRequest`, but the CLI
   doesn't expose it. Inline review-thread comments live behind
   the REST endpoint `repos/<owner>/<repo>/pulls/<num>/comments`,
   not behind `gh pr view --json reviewThreads`.

In both cases the CLI exits 1 with `Unknown JSON field: "<name>"`
and dumps the full list of valid fields. That dump is easy to miss
when debugging a watcher that suppresses stderr — the canonical
`gh ... 2>/dev/null || echo '{}'` pattern leaves jq parsing an
empty `{}` and the loop polls a permanently-null state forever,
never reaching its terminal-state break. The watcher looks armed
but is brain-dead. Observed 2026-05-27 on a PR #24 watcher in
`nhooey/skills-nix`: `--json …,reviewThreads` masked the merge
event for ~10 minutes until the user pointed out the silence.

Validate the field list up front, with stderr intact:

```bash
gh pr view <num> --json state,statusCheckRollup,comments 2>&1 | head -1
```

If you see `Unknown JSON field:`, fix the query before arming a
Monitor against it. To enumerate what's currently valid, run
`gh pr view <num> --json invalid` once — the error output lists
every accepted field. The set has grown over `gh` releases; the
authoritative list is whatever the local `gh` build emits, not
anything pinned in this document.

The currently-known PR-watcher-relevant fields are: `state`,
`mergedAt`, `mergedBy`, `mergeCommit`, `mergeStateStatus`,
`mergeable`, `isDraft`, `reviewDecision`, `reviews`,
`latestReviews`, `statusCheckRollup`, `comments`, `commits`,
`headRefName`, `headRefOid`, `baseRefName`, `labels`.

## GitHub blocks self-approval

Even with admin rights you can't `gh pr review --approve` a PR you
authored — the API rejects with `Review Can not approve your own pull
request`. For solo workflows (stacked PRs you push and merge
yourself), skip approval and merge directly:

```bash
gh pr merge <num> --merge --delete-branch
```

The `--delete-branch` flag deletes both the remote branch and the
local tracking ref in one shot — useful as a one-off if
`github-policy-auto-delete-merged-branches` isn't (yet) enabled.

## `POST /repos/{owner}/{repo}/branches/{branch}/rename` auto-closes open PRs whose head is that branch

GitHub's docs imply head refs follow the rename; in practice they
don't. Observed 2026-05-13 on `nhooey/skills-nix`: four
`nhooey/2026-04-*` branches were renamed via `gh api -X POST
.../rename`; the API succeeded, the branches were renamed, every open
PR with the old head ref recorded a `head_ref_deleted` event and was
auto-closed. The PR's `head.ref` field continued to show the old
name. Recovery requires either reverting the rename or recreating the
PRs against the new branch.

Since GitHub does not permit changing a PR's `head_ref` after
creation, the procedure for renaming a branch with an open PR is:

```bash
# 1. Capture the PR's metadata.
gh pr view <num> --json title,body,baseRefName > /tmp/pr.json

# 2. Rename locally and push the new name from the same tip.
git branch -m <old> <new>
git push -u origin <new>

# 3. Open a new PR with the captured content.
gh pr create --base "$(jq -r .baseRefName /tmp/pr.json)" \
  --head <new> \
  --title "$(jq -r .title /tmp/pr.json)" \
  --body "$(jq -r .body /tmp/pr.json)"

# 4. Comment-close the old PR pointing at the new one.
gh pr comment <old-num> --body "Superseded by #<new-num> after \
renaming the branch from \`<old>\` to \`<new>\`."
gh pr close <old-num>

# 5. Delete the old remote branch.
git push origin --delete <old>
```

The PR number changes — that's unavoidable. Before running the rename
API on any branch, run `gh pr list --state open --json
headRefName,number` and stop if any open PR has that branch as its
head.

## When to apply

- About to use `gh pr edit` for a body or title update.
- Writing a PR watcher that needs the merged/closed state.
- Approving a PR you authored (you can't).
- Renaming a branch that has an open PR against it.
