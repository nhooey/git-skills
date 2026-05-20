---
name: github-pr-watcher
description: |
  After pushing to a branch with an open or imminent PR, arm a
  background Monitor that polls check-runs, issue-comments, review-
  thread comments, and PR state in a single loop, emitting one line
  per delta and reacting per event type (check red → read log,
  comment from session-user → treat as instruction, merged → fire
  cleanup prompt). Apply on every push to a PR branch.
tags: [agent, workflow]
allowed-tools:
  - Bash
  - Read
  - Monitor
---

# github-pr-watcher

After pushing to a branch with an open (or imminent) PR, arm a
background watcher that emits on *every* PR event — check completions,
comments, reviews, labels, merge, close — and react to each. Don't
wait passively for the merge: by the time it lands, the user has often
been pinging the agent through other channels (a comment on the PR, a
review, a red CI run).

A narrower CI-watching Monitor (e.g. one armed by a
`claude-code-garnix-ci`-style skill against the pushed SHA's check-
runs) does **not** substitute for this watcher — it watches a strict
subset of the surface and never emits on `MERGED` or `CLOSED`. An
agent that arms only the CI watcher and then tries to amend + force-
push will discover, too late and against a deleted branch, that the
PR has already landed. Arm both when both apply; they run in parallel
on different event streams.

## How to load this skill

Active. Loading triggers the arming of a Monitor on the current PR
state. If there's no relevant PR for the current branch, no-op.

## Reactions per event type

- **Check green** — surface 🟢 in the next reply (see
  `github-pr-status-line` for the format).
- **Check red** — read the log (`gh run view <id> --log`), propose a
  fix, surface 🔴.
- **Comment from the session-running user** (identify with
  `gh api user --jq .login` matched against `.user.login` on the
  comment) — treat as a chat instruction. The user is using GitHub as
  the conversation surface (often because they're on mobile or
  reviewing the diff side-by-side). Read it, do the work locally, and
  surface a *comment line* in your chat reply confirming what was
  addressed (format defined in `github-pr-status-line`).
  **Don't post a reply on the PR itself** — that publishes under the
  user's identity, and the safety layer blocks it (rightly: the agent
  shouldn't speak as the user). The chat comment line is the
  substitute: the user sees which comment was handled and how,
  without the agent posting publicly.
- **Comment from anyone else** — surface to the user, don't auto-
  react.
- **Review approved** — surface 🟢; merge unblocked.
- **Review requests changes** — read the review, propose the changes,
  surface 🔴.
- **Blocking label added** (`do-not-merge`, `needs-work`, etc.) —
  hard pause; surface and wait for instruction.
- **Title/body edited or branch updated by someone else** — accept
  the override, re-fetch before any destructive op.
- **Merged** — fire the cleanup prompt below.
- **Closed without merge** — ask whether to reopen, delete the
  branch, or leave it.

## One Monitor, one loop, multiple sources

Poll the check-runs, issue-comments, and PR-state endpoints in a
single loop and emit each delta as a recognizable line:

```bash
PR=<num>; REPO=<owner>/<repo>; SHA=<head-sha>
USER=$(gh api user --jq .login)
prev_checks=""; max_issue=0; max_review=0; prev_state=""

# Shared jq filter for both comment sources — emits one line per
# new comment, flagging self-comments distinctly.
fmt_comments='.[] | select(.id > $cutoff)
  | "COMMENT-\(if .user.login==$user then "SELF" else .user.login end): \(.body | gsub("\n"; " "))"'

while :; do
  # Check completions — guard against transient empty fetch.
  cur=$(gh api "repos/$REPO/commits/$SHA/check-runs" 2>/dev/null \
    | jq -r '.check_runs[]? | select(.status=="completed") | "\(.name): \(.conclusion)"' | sort)
  if [ -n "$cur" ]; then
    comm -13 <(echo "$prev_checks") <(echo "$cur") | awk 'NF { print "CHECK " $0 }'
    prev_checks=$cur
  fi

  # Issue-level comments (Conversation tab) — fetch once, reuse.
  issue=$(gh api "repos/$REPO/issues/$PR/comments" 2>/dev/null)
  if [ -n "$issue" ] && [ "$issue" != "[]" ]; then
    jq -r --arg user "$USER" --argjson cutoff "$max_issue" "$fmt_comments" <<<"$issue"
    max_issue=$(jq '[.[].id, 0] | max' <<<"$issue")
  fi

  # Inline review-thread comments (Files Changed tab) — same shape.
  review=$(gh api "repos/$REPO/pulls/$PR/comments" 2>/dev/null)
  if [ -n "$review" ] && [ "$review" != "[]" ]; then
    jq -r --arg user "$USER" --argjson cutoff "$max_review" "$fmt_comments" <<<"$review"
    max_review=$(jq '[.[].id, 0] | max' <<<"$review")
  fi

  # PR state + review decision
  state=$(gh pr view "$PR" --repo "$REPO" --json state,reviewDecision 2>/dev/null \
    --jq '"STATE \(.state) REVIEW \(.reviewDecision | if . == null or . == "" then "none" else . end)"')
  if [ -n "$state" ] && [ "$state" != "$prev_state" ]; then
    echo "$state"
    prev_state=$state
  fi
  case "$state" in *MERGED*|*CLOSED*) break ;; esac

  sleep 30
done
```

Run via `Monitor` with `persistent: true`; a fixed timeout fires
spuriously on PRs that sit for hours. `state` is the right JSON
accessor — `merged` isn't a valid field (see
`github-gh-cli-gotchas`). Both comment endpoints are fetched exactly
once per iteration: the shared `fmt_comments` jq filter is
parameterized via `--arg` and `--argjson` so issue and inline-review
comments flow through the same emit logic without duplication. The
`reviewDecision` fallback uses an explicit `null`-and-`""` check
rather than jq's `//` operator: GitHub returns `""` (empty string),
not `null`, when no review has been submitted, and `//` only catches
null / false — `(.reviewDecision // "none")` would emit nothing
instead of `none` for unreviewed PRs.

## Guard against transient empty fetches

Each poll guards with `if [ -n "$cur" ]; then …; fi` (and analogous
for the comment fetches): a brief `gh api` failure or rate-limit
hiccup returns an empty body, which would otherwise (a) regress
`prev_checks` to empty and re-emit every check on the next successful
fetch, (b) regress `max_issue` / `max_review` to `0` and re-emit
every existing comment, and (c) cause `comm -13` of a non-empty
`prev_checks` against an empty `cur` to print one empty line that
`sed 's/^/CHECK /'` would render as a bare `CHECK` event. The
`awk 'NF { print … }'` (instead of `sed`) is defence in depth — even
if the guard fails, empty lines never get a prefix.

## Alternative architectures (noted, not prescribed)

The polling Monitor above is the right default for an interactive
agent session. Other paths exist if the surrounding system already
supports them:

- **GitHub Actions** on `pull_request_review_comment`,
  `issue_comment`, `pull_request_review`, etc. — fires the workflow
  with the full event payload as context, no polling. Anthropic ships
  `claude-code-action`; community variants exist.
- **GitHub webhooks** to an external service deliver the same events
  without committing to Actions; needs hosting and an HTTPS endpoint
  reachable from GitHub.
- **GitHub Apps** (e.g. via Probot) add a bot identity that can post
  under its own name rather than the user's, plus persistent state
  across events.

These shift the architecture from agent-polls to event-driven-
invocation. They're heavier to set up, and the agent can't bootstrap
them mid-session, so don't reach for them unless they're already
wired up — stick with the Monitor when running interactively.

## On merge, prompt with `AskUserQuestion` (multi-select)

Three cleanups, all default-checked:

- **Delete locally** — `git branch -d <branch>` (use `-d`; the
  merged-only safety check is the point).
- **Delete on remote** — `git push origin --delete <branch>`. Pre-
  check with `git ls-remote --exit-code origin <branch>` and skip
  the option entirely if the branch is already gone. But
  `github-auto-delete-merged-branches` is asynchronous — the pre-
  check can pass and the branch can vanish in the window between the
  prompt and the user's pick — so the actual `git push --delete`
  must treat `error: unable to delete '<branch>': remote ref does
  not exist` as success, not failure. The desired end-state has been
  reached, just by another mechanism. A no-op question is noise; a
  phantom failure on the cleanup is worse.
- **Rebase local default** — `git checkout <default> && git pull
  --rebase origin <default>`. Bail loudly on a dirty tree.

`git-cleanup-merged-branches` covers the same cleanup from the local
side; this rule fires it at the right moment.

## When to apply

- Just pushed to a branch that has (or is about to have) an open PR.
- Resuming a session where a PR was opened earlier.
- Receiving a notification that a watched PR transitioned state.
