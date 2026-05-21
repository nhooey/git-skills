---
name: github-pull-request-status-line
description: |
  Whenever a PR comes up in a reply, surface it on its own line:
  `<status> <url> — **PR #<num>: <title>**` where status is one of
  🟡/🟢/🔴/🟣/⚪ reflecting live PR + check state. Also defines a
  three-line comment-block format (🔲/✅ + 🗣 + 🤖) for surfacing
  reacted-to PR comments without posting them publicly. Apply on
  every PR creation, every Monitor event, every PR citation.
tags: [agent, style]
allowed-tools:
  - Bash
  - Read
---

# github-pull-request-status-line

Whenever the PR comes up in a reply, output its URL on its own line
in this exact format:

```
<status> <url> — **PR #<num>: <PR title>**
```

## How to load this skill

Active. Loading shapes future replies that mention a PR; nothing is
posted or emitted on load itself.

## The status line components

- **`<status>`** — colored circle reflecting live PR/check state.
  The load-bearing visual; users skim for the dot before reading
  prose:
  - 🟡 checks running, not yet merged
  - 🟢 checks passed, mergeable
  - 🔴 at least one check failed
  - 🟣 merged (matches GitHub's own merged-PR color)
  - ⚪ closed without merge
- **`PR #<num>:`** goes inside the bold span. The number is what
  users grep for when several PRs are open.
- **`<PR title>`** — the literal PR title. Wrap the whole `PR #<num>:
  <title>` in Markdown bold (`**…**`). Don't use ANSI codes
  (`\x1b[95m…\x1b[0m`) — Claude Code's Markdown renderer strips ANSI
  from agent replies, even though the terminal itself supports it.
  (Claude Code's own TUI elements like "Thinking…" bypass the Markdown
  pipeline; agent replies don't.) Bold is the reliable cross-renderer
  visual.

Example for a PR with all checks green, ready to merge:

```
🟢 https://github.com/owner/repo/pull/123 — **PR #123: Document the agent PR lifecycle**
```

## Emit this every time the PR comes up

On `gh pr create`, every Monitor event, every citation by number ("PR
#9 …"), every user question about it, and before/after any operation
that changes it (push, force-push, comment, label, merge). Recompute
the status circle from live state each time — a stale 🟡 on a PR that
has actually gone red is worse than no circle. The line is cheap;
skipping it loses the user across several open PRs or hides state
transitions you reacted to in prose without resurfacing the link.

## Comment block — three lines, indented under the PR line

When you react to a PR comment (review-thread or issue-level), attach
a three-line block to the PR line. Each comment becomes its own
little checklist entry hanging off the PR:

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

## Anatomy

- **Indent.** Comment-URL line is indented 2 spaces under the PR
  line; the 🗣 and 🤖 lines are indented 2 spaces further (4 total).
  The indent subordinates the comments visually under the PR they
  belong to.
- **🔲 / ✅** is the completeness marker: 🔲 (U+1F532 black square
  button) = outstanding / not yet addressed, ✅ (U+2705 white heavy
  check mark) = addressed. The green check on ✅ echoes 🟢 on the PR
  line, so a finished comment block reads as visually consonant with
  a mergeable PR.
- **🗣 line** (U+1F5E3 speaking head) carries who said what. Bold the
  author + location if multiple comments are stacked and they need
  disambiguation; plain text otherwise.
- **🤖 line** carries what the agent did about it. Always 🤖 — the
  point is to name the actor (the agent) consistently against the 🗣
  line above; the *what* lives in the prose after the glyph.

The comment URL is the `.html_url` field on the comment API response
(e.g. `gh api repos/.../pulls/<num>/comments` → `.[].html_url`).

This is the workaround for the agent-impersonation guardrail (see
`github-pull-request-watcher`): `gh pr review --reply` and `gh api ...
/comments/<id>/replies` post under the user's identity and the safety
layer blocks them. The comment block keeps the user in the loop
without anything getting published publicly. Emit one block per
reacted-to comment in the same reply where the underlying work is
reported.

## When to apply

- Creating a PR (output the line immediately after `gh pr create`).
- Every Monitor event from `github-pull-request-watcher`.
- Every prose citation of a PR by number.
- Before and after any operation that changes the PR (push, label,
  merge).
