---
name: github-hygiene-gh-cli-gotchas
description: |
  Known traps in the `gh` CLI and GitHub API for issue and PR work, with
  workarounds. Body edits through `gh issue edit`, `gh pr edit` or a REST
  PATCH replace the whole body with no conflict check, erasing edits made
  since you fetched it; the bundled `safe-body-edit.sh` checks and merges
  first. `gh pr view --json` accepts only its own field list, so `merged`
  and `reviewThreads` error out, invisibly under a `2>/dev/null` watcher.
  `gh pr edit` before 2.82.1 exits 1 on a Projects (classic) deprecation
  error without applying the edit. GitHub blocks approving your own PR.
  Renaming a branch closes open PRs whose head it is. Use when editing an
  issue or PR body, writing a PR watcher on `gh pr view --json`, approving
  or merging your own PR, or renaming a branch with an open PR.
tags: [reference]
allowed-tools:
  - Bash
  - Read
  - 'Bash(gh api *)'
---

# `gh` CLI gotchas

_Five ways `gh` and the GitHub API fail quietly on issue and PR work, and the workaround for each._

Loading this skill changes nothing by itself; apply a workaround when its trap comes up.

## Body edits replace the whole text, with no conflict check

`gh issue edit --body-file`, `gh pr edit --body-file` and a REST `PATCH`
of `body` all overwrite the body. GitHub has no compare-and-swap for
it: no version or `If-Match` precondition. If someone else edited the
body after you fetched it, such as a maintainer ticking a tracking
issue's checklist as PRs merge, saving your draft erases their edit,
and nothing warns either of you.

Before saving a body that anyone else edits, re-fetch it and compare it
with the copy your draft started from. If it changed, three-way merge
their changes into your draft and review the result before saving.
The bundled `scripts/safe-body-edit.sh` does both, and saves only when
the live body still matches:

```bash
# the copy you draft from; tr drops the CRLF line ends of browser-edited bodies
gh api repos/<owner>/<repo>/issues/<num> --jq .body | tr -d '\r' > base.md
cp base.md new.md   # ...edit new.md...
safe-body-edit.sh <owner>/<repo> <num> base.md new.md
```

- It works for PRs too: the issues endpoint serves a PR's body.
- It PATCHes through REST, so the old `gh pr edit` trap below doesn't apply.
- Unchanged live body: it saves `new.md` and exits 0.
- Changed live body: it prints the diff, writes `new.md.merged`, saves
  nothing, exits 1 and prints the rerun command, with the live copy as
  the new base. Adjacent checklist lines changed on both sides come out
  as a conflict, never as a silent pick.
- A small race is left: an edit that lands between its check and its
  save is still lost. Keep the gap short by running it right after the
  review, not before.

For a one-line change, such as ticking one task-list box, edit that
line in the browser instead of resending the whole body.

## `gh pr view --json` rejects field names that aren't on its list

The fields `gh pr view --json` accepts are a subset of the GraphQL
`pullRequest` type. Two ways to get bitten:

1. **Inventing a field name** because it sounds reasonable. There is
   no `merged`: use `state` (`OPEN`, `MERGED` or `CLOSED`) or
   `mergedAt` (non-null once merged).
2. **Borrowing a field from the GraphQL type** that the CLI doesn't
   expose. `reviewThreads` exists on the GraphQL `pullRequest` but not
   in `gh pr view --json`. Inline review comments come from the REST
   endpoint `repos/<owner>/<repo>/pulls/<num>/comments`.

Either way the CLI exits 1 with `Unknown JSON field: "<name>"` and a
list of the valid fields. A watcher written as
`gh ... 2>/dev/null || echo '{}'` hides that: jq parses an empty `{}`,
the loop polls a state that stays null and never reaches its
terminal-state break. The watcher looks armed but never fires, and a
merge goes unnoticed.

Validate the field list once, with stderr intact, before arming a
watcher on it:

```bash
gh pr view <num> --json state,statusCheckRollup,comments 2>&1 | head -1
```

`gh pr view --help` lists every accepted field under JSON FIELDS, and
so does the error. The list grows across `gh` releases, so trust the
local build over any list written down. Fields a PR watcher usually
needs: `state`, `closed`, `mergedAt`, `mergedBy`, `mergeCommit`,
`mergeStateStatus`, `mergeable`, `isDraft`, `reviewDecision`,
`reviews`, `latestReviews`, `statusCheckRollup`, `comments`, `commits`,
`headRefName`, `headRefOid`, `baseRefName`, `labels`.

## `gh pr edit` before 2.82.1 exits 1 on a Projects (classic) error, without applying the edit

On a `gh` older than 2.82.1 (check `gh --version`), `gh pr edit`
queries the sunset `projectCards` field, and in a repository that
still has a classic project the call fails:

```text
$ gh pr edit 3 --body-file body.md
GraphQL: Projects (classic) is being deprecated in favor of the new
Projects experience, see: https://github.blog/changelog/2024-05-23-...
$ echo $?
1
```

The body is not updated. Upgrade `gh`, or PATCH through the REST API,
which doesn't touch Projects (classic):

```bash
gh api --method PATCH "/repos/<owner>/<repo>/pulls/<num>" \
  -f body="$(cat body.md)"
```

Use `-f` (`--raw-field`), not `-F` (`--field`), for prose: `-F`
converts `true`, `false`, `null` and integers to JSON types, so a body
of `42` becomes the number `42`. Prefer shell substitution
(`$(cat …)`, `$(git log -1 --pretty=%b)`) over `-F body=@path`: no
stale temporary file, no race with a parallel agent.

## GitHub blocks self-approval

Even with admin rights you can't `gh pr review --approve` a PR you
authored; the API rejects it with `Review Can not approve your own pull
request`. In a solo workflow, such as stacked PRs you push and merge
yourself, skip approval and merge directly:

```bash
gh pr merge <num> --merge --delete-branch
```

`--delete-branch` deletes the local and the remote branch after the
merge, which a repo with `github-policy-auto-delete-merged-branches`
applied doesn't need.

## Renaming a branch closes open PRs whose head it is

`POST /repos/{owner}/{repo}/branches/{branch}/rename` succeeds and
retargets open PRs whose base is the branch, but every open PR whose
head is the branch is closed, with a `head_ref_deleted` event, and its
`head.ref` keeps the old name. A PR's head can't be changed after
creation, so recovery means reverting the rename or opening new PRs.

Before running the rename API on any branch, check for open PRs on it,
and stop if there is one:

```bash
gh pr list --state open --head <old> --json number,title
```

To rename a branch that has an open PR, open a new PR instead:

```bash
# 1. Capture the PR's metadata.
gh pr view <num> --json title,body,baseRefName > pr.json

# 2. Rename locally and push the new name from the same tip.
git branch -m <old> <new>
git push -u origin <new>

# 3. Open a new PR with the captured content.
gh pr create --base "$(jq -r .baseRefName pr.json)" \
  --head <new> \
  --title "$(jq -r .title pr.json)" \
  --body "$(jq -r .body pr.json)"

# 4. Comment on the old PR pointing at the new one, then close it.
gh pr comment <old-num> --body "Superseded by #<new-num> after \
renaming the branch from \`<old>\` to \`<new>\`."
gh pr close <old-num>

# 5. Delete the old remote branch.
git push origin --delete <old>
```

The PR number changes; that's unavoidable.

## When to apply

- About to save an issue or PR body that someone else may have edited.
- `gh pr edit` failed with a Projects (classic) error.
- Writing a PR watcher that needs the merged or closed state.
- Approving a PR you authored (you can't).
- Renaming a branch that has an open PR against it.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `github-policy-auto-delete-merged-branches`: enables GitHub's delete-on-merge setting, which makes `gh pr merge --delete-branch` unnecessary.
