---
name: github-hygiene-pull-request-mirrors-commit
description: |
  Keep each PR a thin wrapper over a single commit: title = subject,
  body = commit body, no `## Summary` / `## Test plan` / Claude-Code
  footer. Open and re-sync PRs with the bundled
  `create-or-update-pull-request.sh` — it mirrors the commit, reflows the
  body to GFM paragraphs, and re-PATCHes an open PR after an amend
  (GitHub never refreshes title/body itself). Apply when opening a PR
  from an agent session, or amending a commit behind an open PR.
tags: [workflow, style, team-stance]
allowed-tools:
  - Bash
  - Read
---

# github-hygiene-pull-request-mirrors-commit

A team-stance: this skill takes the position that each PR is a thin
wrapper over a single commit. The PR title is the commit subject, the
PR body is the commit body, and there is no separate "PR description"
to write or maintain. Teams that prefer multi-commit PRs with rich
prose descriptions independent of the commits should skip this skill.

## How to load this skill

Active when opening a PR or amending a commit behind one. Loading
doesn't push or PATCH; it just makes you apply the rule the next time
either happens.

## Where the bundled script installs

This skill bundles one script, `create-or-update-pull-request.sh`. It
installs in a `scripts/` directory alongside this `SKILL.md`, so its
absolute path depends on the scope this skill was installed to:

- **User scope:** `~/.claude/skills/github-hygiene-pull-request-mirrors-commit/scripts/create-or-update-pull-request.sh`
- **Project scope:** `<project-root>/.claude/skills/github-hygiene-pull-request-mirrors-commit/scripts/create-or-update-pull-request.sh`

Everywhere below the script is named by its filename alone; resolve
`create-or-update-pull-request.sh` against whichever path above matches
your install before running it.

## The rule

GitHub's default for a one-commit PR is title = commit subject, body =
commit body (trailers included). Match that:

- **One commit per PR.** Squash or amend locally before opening.
- **Title = subject, body = body.** No `## Summary` block, no `## Test
  plan` checklist, no "Generated with Claude Code" footer — nothing
  GitHub wouldn't prefill from the commit.

Anything in the PR description that isn't in the commit message becomes
orphaned state — invisible to `git log`, `git blame`, `git show`,
`git format-patch`, and every fork or mirror. The commit is the
durable record; the PR is the review surface. If you want a Summary or
Test-plan section, put it in the commit body so both surfaces have it.

## Override Claude Code's default PR template

This rule overrides the Claude Code system prompt's default PR
template. That template ships boilerplate that this skill rejects:

- ❌ `## Summary` heading with bullet points. If the body is short
  enough that the heading takes more visual space than the content,
  the heading is overhead. Just write the prose.
- ❌ `## Test plan` checklist. Skip it for typical PRs. Only include
  one when (a) the user asks for it, (b) the change is genuinely
  test-plan-shaped (schema migration, large refactor, anything where
  the test approach is the most interesting decision), or (c) the
  team has a checked-in PR template that requires it. For a normal
  one-or-two-file change, a Test plan is busywork.
- ❌ `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
  footer. Not load-bearing on the change; adds noise to PR pages and
  `git log`.
- ❌ `Co-Authored-By: Claude <model> <noreply@anthropic.com>` trailer
  on commits. Only include when the user explicitly wants attribution
  for the AI assist. The change stands on its own; the model version
  is ephemeral and rotating it through commit history adds no value.

**Default to terse.** A PR that fixes a typo gets a one-line
description (or none — the title is enough). A PR that adds a new rule
with a non-obvious rationale gets a paragraph. A PR that restructures
something risky earns the team a Test plan because *that's where the
risk lives*, not because the template said so.

If the user wants the structured template (e.g., their team requires
Summary/Test-plan blocks), they will say so. Until then, write what
`git-hygiene-commit-message-format` would write.

## Subject length: GitHub truncates at ~72 chars

GitHub itself doesn't publish a subject-length limit, but its UI clips
the commit subject with `…` past ~72 chars across commit lists, the PR
compare-view title, and notification subjects — see
[community discussion #12450](https://github.com/orgs/community/discussions/12450).
The 72-char hard-cap in `git-hygiene-commit-message-format` derives
from that empirical limit.

If a Conventional Commits subject is bumping into the cap because of a
long `type(scope):` prefix, tighten the summary side rather than the
scope; the scope carries the load-bearing classification.

## Open or re-sync the PR with `create-or-update-pull-request.sh`

Don't hand-build the `gh pr create` call — the bundled script does it, so the
title and body always mirror the commit and the reflow can't be fumbled:

```bash
create-or-update-pull-request.sh [--base <branch>] [--draft] [--repo <owner/repo>] [--verbatim]
```

It sets the PR **title to the commit subject** and the **body to the commit
body**, reflowed from 72-col wrap to GFM paragraphs (an `awk` paragraph-join:
POSIX and, unlike `fmt`, never shadowed by a dev shell's `nix fmt` command),
then verifies the body actually landed.

**It also re-syncs.** GitHub derives a PR's title/body from the commit *once*,
at creation; a later `git commit --amend` + force-push refreshes the diff but
leaves the title and body frozen. The script auto-detects an existing open PR
for the head branch and PATCHes it instead of opening a new one — so just
**re-run it after every amend**. The `pull-request-sync-check.sh` PostToolUse
hook (shipped by `github-pull-request-watcher`) nudges you when HEAD has drifted
from the open PR; re-running the script is the fix. (`gh api` quoting traps —
`-f` vs `-F` etc. — see `github-hygiene-gh-cli-gotchas`.)

## When the body uses GFM structure, pass `--verbatim`

The reflow joins every line within a paragraph into one line, which mangles
three GFM constructs: fenced/indented **code blocks** (unwrapped into prose),
**`##` headings with no blank line below** (`## Changes` runs into the next
line), and **bullets with hanging-indent continuations** (split at the indent).

Two ways to stay clean:

- **(a) Plain prose** in the commit body — no headings or bullets — which the
  default reflow handles. Best for short, focused commits.
- **(b) GFM-shape from the start** — a blank line after every `##`, each bullet
  on one long line — then run the script with `--verbatim` to skip the reflow
  and send the body as-is. Reach for this when the change genuinely needs headed
  sections.

## Mark "computer words" and code segments for GFM

GitHub renders the commit body through GFM on the PR page. Two markup
conventions pay off whenever the body refers to code:

- **Computer words in backticks.** File paths, binary / library /
  module names, identifiers, env vars, flags, command names — wrap
  each one in `backticks` so GFM renders monospace. Side benefits:
  disambiguates identifiers that read as English in plain `git log`
  ("install matter" vs. "install `matter`"), and shields against
  Markdown's accidental interpretation of `_` or `*` inside the name.
- **Code segments in fenced blocks with a language tag.** Triple
  backticks plus a language hint (`bash`, `nix`, `python`, `json`,
  etc.) yields syntax highlighting on the PR page; omitting the
  language only gets a plain monospace box.

  ````
  ```bash
  gh pr view 20 --json state,mergedAt
  ```
  ````

`git log` shows the backticks and fences as plain characters either
way, so this costs nothing on the terminal side. Treat it as part of
commit-body craft, not PR-only polish — the PR is just the surface
that happens to render it.

## Cross-repo PR/issue refs need `owner/repo#N`

`#123` in a commit body or PR description auto-links to PR or issue
123 *in the current repository only*. Writing `#123` to point at
another repo's PR silently links the wrong thing — the number resolves
against whatever repo GitHub is rendering the body on, not whatever
repo you had in mind.

To reference a PR or issue in a different repository, qualify it:

- `owner/repo#123` — GitHub renders this as a link to PR/issue 123 in
  `owner/repo`. Compact and idiomatic; safe in both commit bodies and
  PR descriptions.
- Full URL (`https://github.com/owner/repo/pull/123`) — also fine,
  GitHub auto-collapses the display text to `owner/repo#123` on
  rendered surfaces.

The same rule applies to commit SHAs (`owner/repo@abcdef1`) and to
@-mentions of teams (`@org/team`). A bare `@username`, by contrast, is
global — no qualification needed.

## When to apply

- About to open a PR — run `create-or-update-pull-request.sh`.
- Just amended a commit on a branch that has an open PR — re-run the
  script to re-sync the title and body.
- Reviewing a PR description that has `## Summary` / `## Test plan`
  blocks not present in the commit message — propose moving them into
  the commit body or removing them.
