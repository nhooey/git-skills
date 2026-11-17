---
name: github-hygiene-pull-request-mirrors-commit
description: |
  Keep each PR a thin wrapper over its commit: one commit by default, the
  title is the commit subject and the body is the commit body plus the
  Claude Code footer, with no `## Summary` or `## Test plan` template.
  Gives the generated shape of a multi-commit body. The bundled
  `create-or-update-pull-request.sh` opens the PR from the commit, reflows
  the body to GFM paragraphs, adds the footer, and after an amend PATCHes
  the open PR back in line, since GitHub never refreshes a PR's title or
  body itself; the bundled `pull-request-sync-check.sh` PostToolUse hook
  flags an open PR whose title or body has drifted from HEAD after an
  amend or push. Use when opening a PR from an agent session, amending a
  commit behind an open PR, or reviewing a PR description that has drifted
  from its commit.
tags: [workflow, style, team-stance]
allowed-tools:
  - Bash
  - Read
  - 'Bash(gh api *)'
---

# Pull requests that mirror their commit

_A PR is one commit by default: its title is the commit subject, its body the commit body and the attribution footer, kept in sync by the bundled script._

This is a team stance. Teams that want PR descriptions written apart
from the commits should skip this skill.
Loading it doesn't push or PATCH anything; it applies the next time you
open a PR or amend a commit behind one.

## The rule

GitHub's default for a one-commit PR is title = commit subject, body =
commit body (trailers included). Match that:

- **One commit per PR, by default,** as
  `github-hygiene-single-commit-pull-requests` decides. Squash or amend
  locally before opening.
- **Title = subject, body = body.** Nothing GitHub wouldn't prefill
  from the commit, apart from the attribution footer.

Anything in the PR description that isn't in the commit message is
invisible to `git log`, `git blame`, `git show`, `git format-patch` and
every fork or mirror. The commit is the durable record; the PR is the
review surface. If a section is worth having, put it in the commit body
so both surfaces have it.

## When a PR holds several commits

`github-hygiene-single-commit-pull-requests` decides whether a PR may
hold several commits. When it does, the body is generated, never
written by hand:

1. **Title:** the lead commit's subject, the commit that states what the
   whole PR achieves.
2. **Synthesis:** the lead commit's body.
3. **Commits:** a list of each commit's linked short SHA and subject,
   with its body folded in `<details>`.
4. **Stacks on:** for a stacked PR, a closing line
   `Stacks on owner/repo#N "title"`.

## No default PR template

This rule overrides the Claude Code system prompt's default PR template:

- **No `## Summary` heading.** Write the prose; a heading over a short
  body is overhead.
- **No `## Test plan` checklist,** unless the user asks for one, the
  change is genuinely test-plan-shaped (a schema migration, a large
  refactor, anything where the test approach is the most interesting
  decision), or the team's checked-in PR template requires it.

Attribution to Claude Code is kept: end the PR description with the
`🤖 Generated with [Claude Code](https://claude.com/claude-code)`
footer and the commit with the `Co-Authored-By: Claude …` trailer, as
the session's attribution instructions give them. The footer is the
one line the PR description has that the commit body doesn't.

Default to terse: a typo fix gets a one-line body or none, a new rule
with a non-obvious rationale gets a paragraph. Write what
`git-hygiene-commit-message-format` would write, including its "What to
cut" list: keep the one path not taken a reviewer would otherwise ask
about, and cut diff paraphrase and test inventories.

The body states the semantic delta: what became true and why. The PR
body generator adds the lock, config and closure sections from the
diff; never restate them by hand.

## Subject length: GitHub truncates at about 72 characters

GitHub publishes no subject-length limit, but its UI clips the commit
subject with `…` past about 72 characters in commit lists, the PR
compare view and notification subjects (see
[community discussion #12450](https://github.com/orgs/community/discussions/12450)).
That is where the 72-character cap in
`git-hygiene-commit-message-format` comes from.

If a Conventional Commits subject hits the cap because of a long
`type(scope):` prefix, tighten the summary rather than the scope; the
scope carries the classification.

## Open or re-sync the PR with `create-or-update-pull-request.sh`

Don't hand-build the `gh pr create` call. The script lives in
`scripts/` beside this SKILL.md:

```bash
create-or-update-pull-request.sh [--base <branch>] [--head <branch>] [--repo <owner/repo>] [--draft] [--verbatim] [--footer <text> | --no-footer]
```

It sets the PR title to the HEAD commit's subject and the body to its
body, reflowed from 72-column wrap to GFM paragraphs, ends the body
with the Claude Code footer, then checks that the body landed and
prints `created` or `synced`, the URL and the body length. It exits 1
with a warning if the PR body comes back empty.

- `--footer <text>`: the session's own attribution line, when it
  differs from the default.
- `--no-footer`: where the session gives no attribution line.
- `--draft`: open as a draft; ignored when re-syncing.

It also re-syncs. GitHub derives a PR's title and body from the commit
once, at creation; an amend and force-push refreshes the diff but
leaves the title and body as they were. The script finds an existing
open PR for the head branch and PATCHes it instead of opening a new
one, so re-run it after every amend. The bundled
`pull-request-sync-check.sh` hook (see
[The sync check hook](#the-sync-check-hook-pull-request-sync-checksh))
nudges you when HEAD has drifted from the open PR.

The re-sync overwrites the whole body. If a reviewer or maintainer may
have edited the PR description, check first with `safe-body-edit.sh`
from `github-hygiene-gh-cli-gotchas`, and fold their edit into the
commit message too.

## Shape the body for the reflow; `--verbatim` is an escape hatch

The reflow joins the lines of each paragraph into one. Shape the body
so that join is harmless, as `git-hygiene-commit-message-format`'s
"Shape the body for a reader who skims" says: prose paragraphs, and
lists with a blank line between items.

Pass `--verbatim` only for a body the reflow can't carry, such as one
holding a fenced code block or a table, and check the rendered PR
afterwards. Reaching for it on an ordinary body means the body needs
reshaping instead.

## Mark code for GFM

GitHub renders the commit body as GFM on the PR page, and `git log`
shows the markup as plain characters, so it costs nothing in the
terminal:

- **Code words in backticks:** file paths, program, library and module
  names, identifiers, environment variables, flags and commands. This
  also tells identifiers apart from English words and keeps `_` and `*`
  in a name from turning into emphasis.
- **Code blocks fenced with a language tag** (`bash`, `nix`, `python`,
  `json`) to get syntax highlighting.

## References to other repositories

A bare `#123` links to issue or PR 123 in the repository the text is
rendered on, so a reference to another repository's issue or PR is
written `owner/repo#123`, and a commit there `owner/repo@abcdef1`.
`github-hygiene-refer-to-issues-and-pull-requests` covers how to label
them.

## The sync check hook: `pull-request-sync-check.sh`

A PostToolUse hook for Bash, in `scripts/` beside this SKILL.md, that
enforces the rule above when skill loading doesn't. On a Bash call
containing `git commit --amend` or `git push`, it looks up the branch's
open PR (`gh pr list --head <branch> --state open`), and when HEAD's
subject or body differs from the PR's title or body it emits a
`systemMessage` naming the PR and the difference and saying to re-sync
with `create-or-update-pull-request.sh`.

- **The watcher reminder,** from the same `gh pr list` call: after a
  `git push` that succeeded, it adds `additionalContext` naming the PR
  and the `pull-request-monitor.sh` command that arms
  `github-workflow-pull-request-watcher`, unless the user said
  otherwise. It gives it once per PR per session, recorded under
  `${CLAUDE_PLUGIN_DATA}` (or `$TMPDIR`) by session id, and not for a
  push to the default branch where `git-workflow-push-mode`'s saved
  mode is direct.
- **Silent otherwise:** other Bash calls, which it tests before any
  other process starts; no git repository, a detached HEAD, no `gh` or
  `jq`, no token, or no open PR.
- **Body comparison ignores whitespace** (`tr -s '[:space:]' ' '`), so
  a 72-column commit body matches its reflowed PR body, and it also
  matches when the PR body has one extra closing paragraph, the footer
  that `create-or-update-pull-request.sh` adds.
- **Never exits non-zero:** it nudges, it doesn't block.

The hook comes from the `git-skills-hooks` Claude Code plugin, which
this repository builds as its flake package `hooks-plugin`. It's
installed through agent-plugins-nixpkgs and enabled in managed settings
by the user's nix-darwin configuration (MyNixOS), so it runs in every
session and inside subagents, whether or not this skill is loaded.
Don't add it to `settings.json` as well: it would run twice on every
Bash call.

- **Without the plugin,** as on a machine not configured through Nix,
  nothing checks for drift: re-sync after every amend as this skill
  says, and point the user at the plugin. It's installed by adding
  `git-skills`' `hooks-plugin` to `services.agent-plugins.plugins`.
- **Dependencies:** the script finds `jq`, `gh`, `git` and the usual
  text tools on the user's PATH when the hook runs.

## When to apply

- About to open a PR: run `create-or-update-pull-request.sh`.
- Just amended a commit on a branch with an open PR: re-run the script.
- Reviewing a PR description with `## Summary` or `## Test plan` blocks
  that aren't in the commit message: propose moving them into the commit
  body or removing them.

## Your preferences

!`cat "${CLAUDE_SKILL_DIR}/../github-hygiene-pull-request-mirrors-commit.preferences.md" "${CLAUDE_PROJECT_DIR}/.agents/skills/github-hygiene-pull-request-mirrors-commit.preferences.md" 2>/dev/null || true`

If your agent doesn't run the line above, read these files yourself if they
exist: `github-hygiene-pull-request-mirrors-commit.preferences.md` next to this skill's folder, then
`.agents/skills/github-hygiene-pull-request-mirrors-commit.preferences.md` in the project. A project's
file overrides the user's, and the user's overrides this skill's defaults.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `git-hygiene-commit-message-format`: the commit message rules (72-character subject, why-focused body) that the PR title and body inherit.
- `github-hygiene-gh-cli-gotchas`: `gh` CLI traps, and the `safe-body-edit.sh` check to run before overwriting a body someone else may have edited.
- `github-hygiene-refer-to-issues-and-pull-requests`: how to label issues, PRs and commits, in this repository and across repositories.
- `github-hygiene-single-commit-pull-requests`: decides whether a PR may hold several commits, and squashes one that may not.
- `github-workflow-pull-request-watcher`: the background Monitor that watches the PR's checks, comments and state after a push.
