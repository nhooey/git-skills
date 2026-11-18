---
name: github-workflow-pull-request-status-line
description: |
  Load when a reply reports on pull requests (on creating one, each
  Monitor event, before and after a push, label or merge, listing
  several, reacting to PR comments) or names any PR or issue, which then
  opens with a References list. Live status lines, a table for a set,
  comment blocks. For the inline label,
  `github-hygiene-refer-to-issues-and-pull-requests`.
tags: [agent, style]
allowed-tools:
  - Bash
  - Read
  - 'Bash(gh api *)'
---

# Pull request status line

_A PR mentioned in a reply gets its own line with a live status circle, its URL and its bold number and title; a set of PRs gets the bundled script's table._

Loading this skill shapes future replies that mention a PR; nothing is
posted on load.

The status line has this exact format:

```
<status> <url> — **PR #<num>: <PR title>**
```

## The bundled script

`pull-request-table.sh` is in `scripts/` beside this `SKILL.md`
(`~/.claude/skills/github-workflow-pull-request-status-line/scripts/`
for a user install). Below it is named by its filename alone.

## The status line components

- **`<status>`**: a colored circle for the live PR and check state.
  Users skim for the dot before reading prose:
  - 🟡 checks running, not yet merged
  - 🟢 checks passed, mergeable
  - 🔴 at least one check failed
  - 🟣 merged (GitHub's own merged-PR color)
  - ⚪ closed without merge, or still a draft (`pull-request-table.sh`
    folds both into ⚪: a draft isn't ready to judge on check state, so
    it gets the neutral dot)
- **`PR #<num>:`** goes inside the bold span. The number is what
  users grep for when several PRs are open.
- **`<PR title>`**: the literal PR title. Wrap the whole `PR #<num>:
  <title>` in Markdown bold (`**…**`), not ANSI codes: Claude Code's
  Markdown renderer strips ANSI from agent replies.

Example for a PR with all checks green, ready to merge:

```
🟢 https://github.com/owner/repo/pull/123 — **PR #123: Document the agent PR lifecycle**
```

## A set of PRs: run the table script

The status line is for a single PR mentioned in prose. For a set of PRs
(a session summary, an audit, "list the open PRs"), don't hand-format a
table, since hand alignment drifts as soon as a title or repo name is
longer than guessed. Run the script:

```
pull-request-table.sh [--repo OWNER/REPO]... [gh pr list flags]
```

It prints one line per PR, every column padded to the widest value in
the result set:

```
<status> <check> <repo>  #<num>  <title>  <url>
```

- `--repo` may be repeated to span repositories; every other flag is
  forwarded verbatim to `gh pr list` (`--state merged|open|all`,
  `--author @me`, `--search`, `--label`, `--limit`). With no `--repo`,
  the current repo is used.
- **`<status>`** uses the same circles as the status line, recomputed
  from live PR and check state.
- **`<check>`** is the checks-status icon: ✅ passed, 🟠 running, 🔴
  failed, ⚫ none, folded from each PR's `statusCheckRollup`.

Example, a session's merged work across three repos:

```
pull-request-table.sh \
  --repo nhooey/skillspkgs --repo nhooey/agent-skill-flake --repo nhooey/git-skills \
  --state merged --limit 10
```

## References section at the top of the reply

When a reply mentions any PR or issue, open it with a **References**
list, one entry per entity: a status circle, then the entity's
cross-repo label as `github-hygiene-refer-to-issues-and-pull-requests`
sets it out, linked to the PR or issue:

```
<status> [<owner>/<repo>#<num> "<title>"](<url>)
```

Example:

```
- 🔴 [jlesquembre/clj-nix#181 "Update babashka version"](https://github.com/jlesquembre/clj-nix/pull/181)
```

The list always uses the `owner/repo#N` form, even for the current
repo, so each entry reads the same and names its repo on its own.

Keep the status circle, recomputed from live state each time: a stale
🟡 on a PR that has gone red is worse than no circle. Issues use 🟢
open, 🟣 closed as completed, ⚪ closed as not planned. In the body,
refer to each entity as `github-hygiene-refer-to-issues-and-pull-requests`
says, by number and title. The single-PR status line and the table
script still apply to PR creation, Monitor events and PR sets.

## Comment block: three lines, indented under the PR line

When you react to a PR comment (review-thread or issue-level), attach
a three-line block to the PR line, one per comment:

```
<pr-line>
  🔲|✅ <comment-url>
    🗣 <author> on <path>:<line>: <comment gist>
    🤖 <one-line summary of the agent's reaction>
```

For issue-level comments not anchored to a file, drop the
`on <path>:<line>` and use `on PR #<num>`:

```
<pr-line>
  🔲|✅ <comment-url>
    🗣 <author> on PR #<num>: <comment gist>
    🤖 <reaction summary>
```

### Anatomy

- **Indent.** The comment-URL line is indented 2 spaces under the PR
  line; the 🗣 and 🤖 lines 2 spaces further (4 total).
- **🔲 / ✅** is the completeness marker: 🔲 (U+1F532 black square
  button) is outstanding, ✅ (U+2705 white heavy check mark) is
  addressed.
- **🗣 line** (U+1F5E3 speaking head) carries who said what. Bold the
  author and location when several stacked comments need telling
  apart; plain text otherwise.
- **🤖 line** carries what the agent did about it. Always 🤖, naming
  the actor consistently against the 🗣 line; the what lives in the
  prose after the glyph.

The comment URL is the `.html_url` field on the comment API response
(e.g. `gh api repos/.../pulls/<num>/comments` → `.[].html_url`).

The block is the workaround for the agent-impersonation guardrail (see
`github-workflow-pull-request-watcher`): `gh pr review --reply` and
`gh api .../comments/<id>/replies` post under the user's identity and
the safety layer blocks them. The block keeps the user in the loop
without publishing anything. Emit one block per reacted-to comment in
the same reply where the underlying work is reported.

## When to apply

- Creating a PR (output the line immediately after it is created).
- Every Monitor event from `github-workflow-pull-request-watcher`.
- Every reply that mentions a PR or issue (References section).
- Before and after any operation that changes the PR (push, label,
  merge).

## Your preferences

!`cat "${CLAUDE_SKILL_DIR}/../github-workflow-pull-request-status-line.preferences.md" "${CLAUDE_PROJECT_DIR}/.agents/skills/github-workflow-pull-request-status-line.preferences.md" 2>/dev/null || true`

If your agent doesn't run the line above, read these files yourself if they
exist: `github-workflow-pull-request-status-line.preferences.md` next to this skill's folder, then
`.agents/skills/github-workflow-pull-request-status-line.preferences.md` in the project. A project's
file overrides the user's, and the user's overrides this skill's defaults.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `github-hygiene-refer-to-issues-and-pull-requests`: the `owner/repo#N "title"` label each References entry uses, and how to name each PR and issue in the body of a reply.
- `github-workflow-pull-request-watcher`: the Monitor whose every event is surfaced with this status line and comment-block format.
