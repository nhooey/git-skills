---
name: github-hygiene-pull-request-mirrors-commit
description: |
  Keep each PR a thin wrapper over a single commit: title = subject,
  body = body (unwrapped from 72-col to GFM-paragraph form via
  `fmt -w 2500`). No `## Summary` / `## Test plan` / Claude-Code footer.
  Re-sync the PR title and body via REST PATCH after any commit amend
  — GitHub does not refresh them automatically. Apply when opening any
  PR from an agent session, or amending a commit behind an open PR.
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

## Unwrap hard-wrapped lines before opening

Commit bodies are hard-wrapped at ~72 cols for `git log` readability,
but GFM renders single newlines as hard breaks — so the PR description
becomes jagged short lines instead of flowing paragraphs. Re-fill
paragraphs to one long line each (blank-line breaks survive):

```bash
gh pr create \
  --title "$(git log -1 --pretty=%s)" \
  --body "$(git log -1 --pretty=%b | fmt -w 2500)"
```

`fmt -w 2500` is the practical maximum — GNU `fmt` 9.7 rejects widths
much above that with `Result too large`, and 2500 is already an order
of magnitude past any realistic paragraph. `par` is a fancier
alternative if installed; `awk 'BEGIN{RS="";ORS="\n\n"} {gsub(/\n/,"
");print}'` has no width limit at all. **Avoid `gh pr create --fill`**
for multi-paragraph bodies — it passes the message through verbatim,
hard wraps and all.

**The unwrap is not optional just because you hand-build the payload.**
`--fill` is the obvious trap, but constructing the body yourself
reintroduces the same one: a heredoc, a `jq -n --arg body "$(…)"`, or
`gh api … --input -` with a JSON body all preserve every `\n`
verbatim, so a 72-col commit body goes in jagged exactly as if you'd
used `--fill`. The reflow (`fmt -w 2500`, `par`, or the `awk`
one-liner) must run on the body text *before* it is captured into the
variable / heredoc / JSON — there is no rendering surface between
`jq --arg` and GitHub that will re-fill it for you. If you reach for
`jq -n --arg body` to "be safe with quoting," you've picked the one
route that quietly keeps the wrap.

## Re-sync the PR after any commit amend

Amending (or rebasing) rewrites the commit message, but it does **not**
update an already-open PR. GitHub derives the PR title and body from
the commit message exactly once, at PR-creation time:

- **Single-commit branch:** title from the commit subject, body from
  the commit message body.
- **Multi-commit branch:** title from the branch name, body left
  empty.

After that point the PR title and body are independent text. A later
`git commit --amend` + force-push refreshes the diff and the commits
tab but leaves the title and description frozen at their original
wording. If you reworded the commit, the PR page now misrepresents
what it ships.

So whenever you amend a commit on a branch that already has an open
PR, also bring the PR into line with what GitHub *would* derive from
the amended message on a fresh PR. PATCH both fields after every amend
(also the fix for `--fill` drift, an early body edit, or a
template-opened PR):

```bash
gh api --method PATCH "/repos/<owner>/<repo>/pulls/<num>" \
  -f title="$(git log -1 --pretty=%s)" \
  -f body="$(git log -1 --pretty=%b | fmt -w 2500)"
```

`--pretty=%b` (lowercase) strips the subject line — it belongs in
`title`. `%B` (uppercase) would double-print it. `-f` vs `-F`, and
shell substitution vs `body=@path`: see `github-hygiene-gh-cli-gotchas`.

## How to detect there's an open PR for the current branch

The re-sync rule above assumes the agent already knows a PR exists.
Two ways to detect:

1. **Active probe** — before any `git commit --amend` on a feature
   branch, run:
   ```bash
   gh pr list --head "$(git branch --show-current)" --state open \
     --json number,title,body --jq '.[0] // empty'
   ```
   Empty output → no open PR, no PATCH needed. Non-empty → grab
   `.number` and PATCH after the amend.

2. **Hook-driven nudge** — the `pull-request-sync-check.sh`
   PostToolUse hook shipped by `github-pull-request-watcher` (wired
   into `~/.claude/settings.json`) runs the same probe automatically
   on every `git commit --amend` and `git push`, and emits a system
   reminder if HEAD's commit message has diverged from the PR's
   title or body. Treat the reminder as authoritative and run the
   PATCH it suggests. See `github-pull-request-watcher`'s "Companion
   hook" section for wiring instructions.

The active probe is the right discipline; the hook is the safety net
for when the discipline lapses.

## Caveat: `fmt` reflows by paragraph and breaks on three GFM constructs

`fmt -w 2500` joins all lines within a paragraph (text between blank
lines) into one long line. That works for plain prose but breaks when
the commit body uses GFM block structure:

- **Fenced and indented code blocks** are unwrapped along with prose.
- **`##` headings without a blank line below them** flow into the
  next line — `## Changes\n- First bullet` becomes `## Changes -
  First bullet`.
- **Bullets with hanging-indent continuations** get split at the
  indent change — `fmt` treats the 2-space-indented continuation as a
  separate paragraph from the bullet's 0-indented `- ` start, so a
  multi-line bullet renders as two short lines instead of one
  flowing one.

Two reliable workarounds:

- **(a) Plain narrative prose in the commit body.** No headings, no
  bullets. `fmt -w 2500` reflows it cleanly. Best for short / focused
  commits.
- **(b) GFM-shape from the start.** Blank line after every `##`
  heading, each bullet on a single long line (no hard-wrap inside the
  bullet), then *skip* `fmt` and pass the body through verbatim:
  ```bash
  gh api --method PATCH "/repos/<owner>/<repo>/pulls/<num>" \
    -f title="$(git log -1 --pretty=%s)" \
    -f body="$(git log -1 --pretty=%b)"
  ```
  Costs slightly longer lines in `git log` (a 100-char bullet is
  harmless; terminals wrap dynamically) but renders identically on
  both surfaces.

Pick (a) by default; reach for (b) when the body genuinely needs
structure (e.g., a refactor touching several files that benefits from
headed sections).

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

- About to open a PR with `gh pr create`.
- Just amended a commit on a branch that has an open PR — PATCH the
  title and body.
- Reviewing a PR description that has `## Summary` / `## Test plan`
  blocks not present in the commit message — propose moving them into
  the commit body or removing them.
