---
name: github-workflow-repo-activity
description: |
  List what one GitHub user did on one repository since a given time —
  comments, review comments, reviews, merges they performed, PRs and
  issues they opened, closed or retitled, commits they pushed (direct to
  a branch or onto a PR), branches they created or deleted — merged into
  one time-sorted list. Run the bundled `github-repo-activity.py`
  (Python stdlib, reads through `gh api`). Use for "what has <user> done
  on <repo> since <time>", checking whether a maintainer replied, merged
  or reviewed, or catching up on a repo after time away. Never reach for
  the GitHub Events API for this: it truncates, lags, misattributes
  merges and drops pushes.
tags: [workflow, reference]
allowed-tools:
  - Bash
  - Read
---

# github-workflow-repo-activity

Answer "what has this person done on this repo since then?" from the
endpoints that are the record for each kind of activity, not from the
Events API.

## Where the bundled script installs

This skill bundles `github-repo-activity.py` and its offline self-check
`test_github_repo_activity.py`, in a `scripts/` directory alongside this
`SKILL.md`:

- **User scope:** `~/.claude/skills/github-workflow-repo-activity/scripts/github-repo-activity.py`
- **Project scope:** `<project-root>/.claude/skills/github-workflow-repo-activity/scripts/github-repo-activity.py`

Below, the script is named by its filename alone; resolve it against the
path that matches your install. It needs Python 3.9+ and an authenticated
`gh`; it never handles a token itself.

## Run it

```bash
github-repo-activity.py summary --repo jlesquembre/clj-nix --user jlesquembre --since 2026-10-18
```

```text
2026-10-18 11:23Z  commit                 "fixes" (main 9cced1f)  https://github.com/…/commit/9cced1f…
2026-10-18 11:32Z  merged                 #205 "Pass extra arguments through in mkGraalBin" (by nhooey)  https://github.com/…/pull/205
2026-10-18 19:47Z  commit-via-pr          #214 "Format Clojure and Nix files with default formatters" (reformat a589577)  …
2026-10-18 19:51Z  opened                 #214 "Format Clojure and Nix files with default formatters"  https://github.com/…/pull/214
```

One line per event: time (UTC), kind, `#N "title"`, detail in
parentheses, URL. `--json` prints the same events as an array of
`{time, kind, number, title, url, actor, detail}`. `--help` on the script
and on each subcommand lists every option.

| Subcommand | Lists                                                                                  |
| ---------- | -------------------------------------------------------------------------------------- |
| `summary`  | everything below, merged and sorted by time                                            |
| `comments` | conversation comments (`comment`, `comment-edited`) and diff comments (`review-comment`) |
| `reviews`  | `review-approved`, `review-changes_requested`, `review-commented`, `review-dismissed`  |
| `merges`   | `merged`: PRs whose `merged_by` is the user, with the PR author when someone else      |
| `prs`      | PRs `opened`, `closed` unmerged, `reopened`, `retitled`, `referenced`                   |
| `issues`   | the same kinds for issues                                                              |
| `commits`  | `commit` (no PR carries it: a direct push) and `commit-via-pr`, at the time pushed     |
| `branches` | `branch-created`, `branch-deleted`, `force-pushed`                                     |

Options on every subcommand:

- `--since` takes an ISO 8601 date or time (a bare date is midnight
  UTC) or a relative age: `36h`, `2d`, `1w`.
- `--user` is optional; without it every user is listed, with `[bot]`
  accounts and `web-flow` left out unless `--include-bots`.
- `--jobs N` sets how many `gh api` calls run at once for the per-item
  endpoints (default 8).

Notes about a degraded source go to stderr as `note: …`, so `--json`
output stays parseable.

## Why each endpoint

| Activity          | Endpoint                                                  | Why this one                                                                                                                                       |
| ----------------- | --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| what changed      | `repos/{r}/issues?state=all&since=`                        | Every issue and PR updated since, in one paginated call. A comment, review, close or merge bumps `updated_at`, so this bounds the per-item calls.   |
| comments          | `repos/{r}/issues/comments?since=`, `repos/{r}/pulls/comments?since=` | Repo-wide and filtered server-side by `updated_at`, so edits count too. Diff comments live only in the second.                        |
| reviews           | `repos/{r}/pulls/{n}/reviews`, per updated PR              | The only place a review's state and `submitted_at` are kept; no repo-wide reviews endpoint exists.                                                  |
| merges            | `repos/{r}/pulls/{n}`, per PR merged since                 | Only the single-PR object carries `merged_by`. The list endpoint, search and the Events API credit the PR's author instead.                         |
| close, reopen, retitle | `repos/{r}/issues/{n}/timeline`, per updated item     | The timeline names the `actor` of each state change; the issue object only says that it closed.                                                     |
| pushes            | `repos/{r}/activity?actor=`                                | Records each ref move with the time GitHub received it and the login that pushed, including branch creation, deletion and force-push.               |
| pushed commits    | `repos/{r}/compare/{before}...{after}`, per push           | The commits a push carried, from the push's own before and after SHAs.                                                                              |
| direct or via PR  | `repos/{r}/commits/{sha}/pulls`                            | Names the PR that carries a commit, so a commit with none is a direct push.                                                                         |

### Commit date is not push time

A commit's committer date is set on the author's machine when the commit
is made. A commit made Friday and pushed Sunday is dated Friday, so
`repos/{r}/commits?since=Saturday` never shows it. The script takes push
times from `repos/{r}/activity` instead, which any reader of the repo can
query.

When that endpoint fails, the script falls back to
`repos/{r}/commits?sha=<branch>&author=&since=` on every branch, lists
commits at their commit date, and prints a `note:` saying so. Under the
fallback, widen `--since` by a day or two, or check against `git log` on
a freshly fetched remote:

```bash
git fetch origin && git log --remotes --author=<login-or-email> --since=<time> --format='%h %cI %s'
```

### Why not the Events API

`repos/{r}/events` and `users/{u}/events` are a notification feed, not a
record:

- They keep at most 90 days and 300 events, so a busy repo loses events
  inside the window.
- Events arrive minutes to hours late.
- A merge shows up as a `PullRequestEvent` closed by the PR's author,
  not the person who merged it.
- It has been seen to drop a `PushEvent` outright.

## Checking it works

```bash
python3 test_github_repo_activity.py
```

This runs offline against a fake `gh api`. It covers the merger-versus-
author attribution, a commit made before `--since` but pushed after it,
the commit-date fallback, and bot filtering.

## When to apply

- The user asks what someone has done on a repo, or whether a maintainer
  has replied, reviewed or merged since a given time.
- Catching up on a repo after time away, before replying on it.
- Any time you'd otherwise chain `gh api` calls per PR or reach for
  `events`.
