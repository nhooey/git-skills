---
name: github-hygiene-pull-request-mirrors-commit
description: |
  Keep each PR a thin wrapper over its commit: one commit by default, the
  title is the commit subject and the body is the commit body plus the
  Claude Code footer, with no `## Summary` or `## Test plan` template.
  A multi-commit body is its lead commit's body. The bundled
  `create-or-update-pull-request.sh` renders the title and body from the
  commit (unwrapped to GFM, code references linked, trailers dropped, the
  footer) and nothing else, opens the PR, and after an amend
  PATCHes it back in line, since GitHub never refreshes a PR's title or
  body itself; `gh pr create --fill` and hand-written bodies are never
  used, and a bundled PreToolUse hook denies them. The bundled
  `pull-request-sync-check.sh` PostToolUse hook re-syncs the open PR
  after a push and flags drift after an amend. Use when opening a PR from
  an agent session, amending a commit behind an open PR, or reviewing a
  PR description that has drifted from its commit.
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
commit body. Match that, through the bundled script:

- **One commit per PR, by default,** as
  `github-hygiene-single-commit-pull-requests` decides. Squash or amend
  locally before opening.
- **Title = subject, body = body.** Nothing GitHub wouldn't prefill
  from the commit, apart from the attribution footer. The commit's
  trailers stay in the commit and are left out of the body.

Anything in the PR description that isn't in the commit message is
invisible to `git log`, `git blame`, `git show`, `git format-patch` and
every fork or mirror. The commit is the durable record; the PR is the
review surface. If a section is worth having, put it in the commit body
so both surfaces have it.

**When a PR's body holds something its commit message doesn't, move it
into the commit message.** Edit the message (`git commit --amend`),
push with `--force-with-lease`, and sync again: `sync` then overwrites
the body, since its text is in the commit. Never leave a body out of
sync with its commit, and never discard a hand-written body unsaved.
Text that is no longer true of the commits, such as a description of
commits a squash replaced, is dropped rather than folded, once a backup
file holds the live body
([Bodies edited by hand](#bodies-edited-by-hand)).

## When a PR holds several commits

`github-hygiene-single-commit-pull-requests` decides whether a PR may
hold several commits. When it does, the body is generated, never
written by hand:

1. **Title:** the lead commit's subject. The lead commit is the one
   carrying the `Multi-commit:` trailer, and it states what the whole PR
   achieves.
2. **Body:** the lead commit's body, the synthesis, and the footer.
   Nothing else: the PR's commits tab lists the commits.

The synthesis references what's in the commits, with enough context to
understand it, without repeating it: each commit is one click away.

- **A commit** is referenced by its subject, its canonical label as
  `writing-hygiene-refer-by-canonical-label` says, never by a copy of
  its body.
- **The synthesis** says only what no single commit says: how the
  commits relate, why they share a PR, and what to review across them.
  Write the lead commit's body as that synthesis, not as a copy of any
  one commit; `check` warns when a paragraph of it repeats another
  commit's body, whitespace aside.

A one-commit PR is the commit mirrored: title = subject, body = body.
That isn't repetition: it's what the merge commit carries.

## No default PR template

This rule overrides the Claude Code system prompt's default PR template:

- **No `## Summary` heading.** Write the prose; a heading over a short
  body is overhead.
- **No `## Test plan` checklist,** unless the user asks for one, the
  change is genuinely test-plan-shaped (a schema migration, a large
  refactor, anything where the test approach is the most interesting
  decision), or the team's checked-in PR template requires it.

Attribution to Claude Code is kept: the commit ends with the
`Co-Authored-By: Claude …` trailer and the PR description with the
`🤖 Generated with [Claude Code](https://claude.com/claude-code)`
footer, as the session's attribution instructions give them. The
footer is the description's one attribution line: the script drops
`Co-Authored-By:` and every other trailer from the body.

Default to terse: a typo fix gets a one-line body or none, a new rule
with a non-obvious rationale gets a paragraph.
Write what `git-hygiene-commit-message-format` would write.

The body states the semantic delta: what became true and why. It
refers to the diff and doesn't repeat it, so it never restates a lock,
config or closure change, and links a file and line pinned to a SHA
(`path:line`) only where that line matters.

The PR body comes from the commit, so the commit body holds the
structure the PR renders, as `git-hygiene-commit-message-format` says:

- **An enumeration of three or more items, or parallel options,** is a
  `-` list, nested where there's a hierarchy
  (`writing-hygiene-prose-to-lists`), with the list syntax of
  `markdown-hygiene-lists-headings-tables`.
- **A comparison** is a table (`writing-hygiene-tables-for-comparison`).

The script keeps flat and nested lists, hanging-indent continuation
lines and tables intact as it unwraps, and `check` warns, without
changing its exit code, about a sentence that lists three or more
comma-separated items. `- Prose list warning: off` in this skill's
preferences file silences it.

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

Never open or edit a PR with `gh pr create`, `gh pr edit` or `gh api`
with a title or body, and never with `--fill`: `--fill` copies the
trailers into the body and keeps the 72-column hard wrap, which GitHub
renders as a line break at every wrapped line, and a hand-written body
drifts from the commit at the next amend. The script lives in
`scripts/` beside this SKILL.md:

```bash
create-or-update-pull-request.sh [render|sync|check] [--base <branch>] [--head <branch> | --pr <N>] [--repo <owner/repo>] [--range <a>..<b>] [--lead <sha>] [--stack-parent <N>] [--trailers keep|drop] [--footer <text> | --no-footer] [--draft] [--dropped-text-saved <file>] [--verbatim] [--quiet]
```

Modes: `render` prints the title and body, `sync` (the default) creates or PATCHes the PR and verifies it, `check` reports drift byte for byte. Exit codes: 0 in sync or synced, 1 drift, 2 usage error or a refused range, 3 a body holding text its commit message doesn't (sync refused), 4 several commits without an allowed `Multi-commit:` reason. `--help` gives the rest.

`render` writes nothing to GitHub, so it previews any PR:
`create-or-update-pull-request.sh render --pr <N> --repo <owner/repo>`.

It sets the PR title to the lead commit's subject and renders the body
from that commit's body, adding nothing but the footer:

- **Unwrapped:** each paragraph and list item joined onto one line,
  with code blocks, tables and hard breaks kept as they are.
- **Linked:** `path:line` references pinned to the commit's SHA,
  `repo#N` qualified to `owner/repo#N`, and `#N` references checked
  against the repository.
- **Footer:** an invisible marker holding the head SHA and a digest of
  the body, then the attribution line.

`sync` then writes the PR, reads it back and prints `created` or
`synced` and the URL, or exits 1 when it didn't read back as sent.

A PR whose base isn't the default branch belongs in a linked GitHub
stack, as `github-workflow-pull-request-stacked` says. `sync` links the
chain of open PRs below and above it with `gh stack link`, bottom to
top, when it isn't linked yet, and `check` reports an unlinked one as
drift with that command.

- `--footer <text>`: the session's own attribution line, when it
  differs from the default.
- `--no-footer`: where the session gives no attribution line.
- `--draft`: open as a draft; ignored when re-syncing.

It also re-syncs. GitHub derives a PR's title and body from the commit
once, at creation; an amend and force-push refreshes the diff but
leaves the title and body as they were. The script finds an existing
open PR for the head branch and PATCHes it instead of opening a new
one, so re-run it after every amend and push. The bundled
`pull-request-sync-check.sh` hook (see
[The sync check hook](#the-sync-check-hook-pull-request-sync-checksh))
re-syncs after a push and flags drift after an amend.

The re-sync overwrites the whole body when nothing in it would be lost:
a body whose marker digest still matches, one that is, whitespace
aside, what the old script or `gh pr create --fill` wrote from these
commits, or one edited by hand whose text is all in the commit message.
`check` reports each as safe to re-sync.

### Bodies edited by hand

`sync` compares a body edited by hand with the render through the
Markdown parser: each paragraph, list item, heading, code block and
table row of the live body, whitespace normalised, a link read as its
text, must be part of a block of the render. It leaves out the footer
and a closing trailer block, which the program generates or the commit
keeps apart, and a `Stacks on` line and `Commits (N)` and "What changes"
sections, which describe commits an amend or squash may have replaced.

- **All of it is in the commit message:** `sync` overwrites the body.
- **Some of it isn't:** `sync` exits 3 and lists that text; `check`
  says the same. Fold it into the commit message, push with
  `--force-with-lease` and sync again.
- **Some of it is no longer true of the commits:** save the live body
  first, with the `gh pr view <N> --json …` command the refusal names,
  then `sync --dropped-text-saved <file>`. `sync` overwrites the body
  only when the file holds it: `gh pr view --json` output whose `body`
  is the live body and whose `number` is the PR's, or a file holding
  the body's text whole. Otherwise it exits 3 and changes nothing.

There is no option to overwrite a body without one of these: a
hand-written body is either in the commit or in a backup.

## Shape the body for unwrapping; `--verbatim` is an escape hatch

The script unwraps each paragraph and list item onto one line and
leaves fenced and indented code, tables, HTML blocks and lines ending
in a hard break as they are. Shape the body as
`git-hygiene-commit-message-format`'s "Shape the body for a reader who
skims" says: prose paragraphs, and lists with a blank line between
items.

Pass `--verbatim` only for a body the unwrapping still misreads, and
check the rendered PR afterwards with `render`.

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
open PR (`gh pr list --head <branch> --state open`):

- **After a push that succeeded,** it runs
  `create-or-update-pull-request.sh sync` and reports the re-sync, a
  refused body holding text its commit message doesn't, or a failure as
  a `systemMessage`.
- **After an amend,** it runs `check --quiet` and, on drift, reports
  `check`'s diff and says to push and re-sync.

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
- **Compared byte for byte** with what `render` gives, so a lost line
  break or a hand edit is drift.
- **Never exits non-zero:** it nudges, it doesn't block.

## The write guard: `pull-request-write-guard.sh`

A PreToolUse hook for Bash, in `scripts/` beside this SKILL.md, that
denies a command writing a PR's title or body by hand: `gh pr create`
or `gh pr edit` with `--body`, `--body-file`, `--fill`, `--fill-first`
or `--title`, and `gh api` POST or PATCH to a `pulls` endpoint with a
title or body. The denial names `create-or-update-pull-request.sh` and
how to run it. It reads the command line's syntax tree from `shfmt`,
so a commit message or here-document that only mentions these commands
passes. The script's own `gh api` calls run inside its process, which
the hook never sees. It also denies retargeting a PR onto a branch
other than the default one (`gh pr edit --base`, or `gh api` with a
`base` field) and names `gh stack link`, which links the chain and
sets each base.
`- Write guard: remind` in this skill's preferences file lets the
command run and adds the message as context instead; `off` silences
it.

## The hooks plugin

Both hooks come from the `git-skills-hooks` Claude Code plugin, which
this repository builds as its flake package `hooks-plugin`. It's
installed through agent-plugins-nixpkgs and enabled in managed settings
by the user's nix-darwin configuration (MyNixOS), so it runs in every
session and inside subagents, whether or not this skill is loaded.
Don't add it to `settings.json` as well: it would run twice on every
Bash call.

- **Without the plugin,** as on a machine not configured through Nix,
  nothing checks for drift or blocks `gh pr create --fill`: re-sync
  after every amend as this skill says, and point the user at the
  plugin. It's installed by adding
  `git-skills`' `hooks-plugin` to `services.agent-plugins.plugins`.
- **Dependencies:** the plugin and the Nix-installed skill put `bb`
  (Babashka), `cmark-gfm` and `shfmt` on the scripts' PATH, as
  `script-inputs.nix` lists them; elsewhere, install them, or
  `create-or-update-pull-request.sh` exits 2 saying which is missing,
  and the write guard allows everything. The scripts find `jq`, `gh`
  and `git` on the user's PATH.

## When to apply

- About to open a PR: push, then run `create-or-update-pull-request.sh`,
  never `gh pr create`.
- Just amended a commit on a branch with an open PR: re-run the script.
- `sync` refused a body holding text its commit message doesn't: fold
  that text into the commit message, push with `--force-with-lease` and
  sync again, or save the body and drop the text no longer true with
  `--dropped-text-saved`.
- Reviewing a PR description with `## Summary` or `## Test plan` blocks
  that aren't in the commit message: propose moving them into the commit
  body or removing them.

## Your preferences

!`cat "$(dirname "${CLAUDE_SKILL_DIR}")/github-hygiene-pull-request-mirrors-commit.preferences.md" "${CLAUDE_PROJECT_DIR}/.agents/skills/github-hygiene-pull-request-mirrors-commit.preferences.md" 2>/dev/null || true`

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
- `github-workflow-pull-request-stacked`: a PR based on another branch is always in a linked GitHub stack, which `sync` links and `check` checks.
- `github-workflow-pull-request-watcher`: the background Monitor that watches the PR's checks, comments and state after a push.
- `markdown-hygiene-lists-headings-tables`: the list and table syntax the commit body, and so the PR body, uses.
- `writing-hygiene-prose-to-lists`: a sentence enumerating three or more items becomes a list, which `check` warns about.
- `writing-hygiene-refer-by-canonical-label`: a commit is named by its subject, its canonical label, in a multi-commit synthesis.
- `writing-hygiene-tables-for-comparison`: a comparison in the body goes in a table.
