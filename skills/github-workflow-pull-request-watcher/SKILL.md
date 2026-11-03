---
name: github-workflow-pull-request-watcher
description: |
  MANDATORY after every push to a branch with an open or imminent PR:
  immediately arm `pull-request-monitor.sh`
  as a background Monitor. This is non-negotiable — the description IS
  the standing instruction; the user does not need to ask, and "they
  only asked me to push" is not a valid skip reason. Skipping leaves
  the agent blind to red CI, user comments posted as the review
  surface (treated as chat instructions), and the merge event.

  The Monitor polls check-runs, issue-comments, review-thread
  comments, and PR state in a single loop, emitting one line per
  delta and reacting per event type (check red → read log, comment
  from session-user → treat as instruction, merged or closed → clean
  up as the project's preferences file says, asking only the first
  time and saving the answer there).
tags: [agent, workflow]
allowed-tools:
  - Bash
  - Read
  - Monitor
  - AskUserQuestion
  - Edit
  - Write
---

# github-workflow-pull-request-watcher

After pushing to a branch with an open (or imminent) PR, arm a
background watcher that emits on *every* PR event — check completions,
comments, reviews, labels, merge, close — and react to each. Don't
wait passively for the merge: by the time it lands, the user has often
been pinging the agent through other channels (a comment on the PR, a
review, a red CI run).

A narrower CI-watching Monitor (e.g. one armed against the pushed
SHA's check-runs) does **not** substitute for this watcher — it
watches a strict subset of the surface and never emits on `MERGED` or
`CLOSED`. An agent that arms only the CI watcher and then tries to
amend + force-push will discover, too late and against a deleted
branch, that the PR has already landed. Arm both when both apply; they
run in parallel on different event streams.

Conversely, this watcher does **not** substitute for the
`pull-request-sync-check.sh` PostToolUse hook shipped with this
skill (see "Companion hook" below): the
watcher arms only after a push and watches external events (CI,
comments, merge), while the hook fires on local
`git commit --amend` and catches title/body drift even before any
push happens.

## How to load this skill

Active. Loading triggers the arming of a Monitor on the current PR
state. If there's no relevant PR for the current branch, no-op.

## Where the bundled scripts install

This skill bundles two scripts, `pull-request-monitor.sh` and
`pull-request-sync-check.sh`. Both install in a `scripts/` directory
alongside this `SKILL.md`, so their absolute paths depend on the scope
this skill was installed to:

- **User scope:** `~/.claude/skills/github-workflow-pull-request-watcher/scripts/<filename>`
- **Project scope:** `<project-root>/.claude/skills/github-workflow-pull-request-watcher/scripts/<filename>`

Everywhere below each script is named by its filename alone; resolve
`pull-request-monitor.sh` or `pull-request-sync-check.sh` against
whichever path above matches your install before running it. The one
exception is the `settings.json` hook snippet at the end of this skill:
a hook command runs outside any agent working directory, so it needs
the absolute path spelled out — use the matching scope's path from the
list above.

## Reactions per event type

- **Check green** — surface 🟢 in the next reply (see
  `github-workflow-pull-request-status-line` for the format).
- **Check red** — read the log (`gh run view <id> --log`), propose a
  fix, surface 🔴.
- **Comment from the session-running user** (identify with
  `gh api user --jq .login` matched against `.user.login` on the
  comment) — treat as a chat instruction. The user is using GitHub as
  the conversation surface (often because they're on mobile or
  reviewing the diff side-by-side). Read it, do the work locally, and
  surface a *comment line* in your chat reply confirming what was
  addressed (format defined in `github-workflow-pull-request-status-line`).
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
- **Merged** — clean up as the preferences say, asking only the
  first time (see "On merge or close" below).
- **Closed without merge** — reopen, delete the branch or leave it,
  as the preferences say, asking only the first time.

## One Monitor, one loop, multiple sources

Poll the check-runs, issue-comments, and PR-state endpoints in a
single loop and emit each delta as a recognizable line. The loop is
shipped as `pull-request-monitor.sh` alongside this skill;
arm the `Monitor` tool with `persistent: true` and invoke it:

```bash
bash pull-request-monitor.sh
```

All flags are optional and auto-detect from the current branch /
HEAD: `--pr <num>` (from `gh pr view --json number`), `--repo
<owner/repo>` (from `gh repo view --json nameWithOwner`), `--sha
<sha>` (from `git rev-parse HEAD`), `--interval <seconds>` (default
30). Pass them explicitly to watch a PR other than the one on the
current branch.

`persistent: true` matters because a fixed Monitor timeout fires
spuriously on PRs that sit for hours. Each line of output is a
single recognizable event: `CHECK <name>: <conclusion>` on check
completions, `COMMENT-<login>: <body>` (or `COMMENT-SELF` when the
comment was posted by the session-running user), and `STATE <state>
REVIEW <decision>` on PR-state transitions. The loop breaks when
state reaches `MERGED` or `CLOSED`.

Three design notes worth knowing — all load-bearing for the silent-
stuck failure mode below:

- Checks come from `commits/<sha>/check-runs`, but a fine-grained
  personal access token has no Checks permission, so on a private repo
  that endpoint answers HTTP 403. After the first 403 the loop reads
  `actions/runs?head_sha=<sha>` instead, which needs only "Actions:
  Read", and emits the same `CHECK <name>: <conclusion>` lines: one per
  workflow run rather than per job, and nothing for checks posted by
  apps outside Actions. Without it, a private repo's CI would never
  emit, and silence reads as green.
- `state` is the right `--json` accessor; `merged` isn't a valid
  field (see `github-hygiene-gh-cli-gotchas`).
- The `reviewDecision` fallback uses an explicit `null`-and-`""`
  check rather than jq's `//` operator: GitHub returns `""` (empty
  string), not `null`, when no review has been submitted, and `//`
  only catches null / false — `(.reviewDecision // "none")` would
  emit nothing instead of `none` for unreviewed PRs.

## Guard against transient empty fetches

The script guards every fetch with `if [ -n "$cur" ]; then …; fi` (and
analogous for the comment fetches): a brief `gh api` failure or rate-
limit hiccup returns an empty body, which would otherwise (a) regress
`prev_checks` to empty and re-emit every check on the next successful
fetch, (b) regress `max_issue` / `max_review` to `0` and re-emit every
existing comment, and (c) cause `comm -13` of a non-empty `prev_checks`
against an empty `cur` to print one empty line that a naive
`sed 's/^/CHECK /'` would render as a bare `CHECK` event. The
`awk 'NF { print … }'` (instead of `sed`) is defence in depth — even
if the guard fails, empty lines never get a prefix.

## Dry-run before arming `Monitor`

The empty-fetch guard above protects against *intermittent* failures
(network hiccup, rate-limit ping). It does **not** protect against
*systematic* failures — an invalid `--json` field, a typo in the
endpoint path, a missing repo permission. Those return non-zero
*every* poll; `2>/dev/null` swallows the stderr; the empty-body
guard keeps the previous (empty) state; the loop polls silently
forever, never emitting events and never reaching its terminal-state
break. The watcher looks "armed" but is brain-dead — and the failure
mode is silent enough that the user is often the one who notices,
not the agent.

The script's `--dry-run` flag runs every distinct gh invocation it
contains exactly once with stderr **intact**, then exits:

```bash
bash pull-request-monitor.sh --dry-run
```

If any prints `Unknown JSON field:`, `HTTP 4xx`, or `Could not
resolve to a Repository`, fix the query and re-dry-run before
arming the Monitor. Specifically, don't substitute `gh pr view
--json reviewThreads` for the dedicated `pulls/$PR/comments` REST
endpoint — `reviewThreads` exists on the GraphQL `pullRequest` type
but is *not* exposed by `gh pr view --json`, and the resulting
`Unknown JSON field` error is exactly the silent-stuck failure mode
this section warns about. See `github-hygiene-gh-cli-gotchas` for
the full `--json`-field inventory.

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

## On merge or close: ask once, then follow the answer

What to do when a PR merges or closes is the same choice every time in
a project, so the user makes it once. Each action below has a key in
this skill's preferences file (see "Your preferences" below):

- **Key set to an answer:** do what it says, without a picker, and
  report what was done in the next reply.
- **Key missing or `ask`:** ask, act on the answer, then save the answer
  to the project's preferences file, so the picker doesn't open again
  in this project.

### On merge

| Key                     | Action                                                                                     | Values             |
| ----------------------- | ------------------------------------------------------------------------------------------ | ------------------ |
| `Delete local branch`   | `git branch -d <branch>`, and `git worktree remove <path>` first if a worktree holds it    | `yes`, `no`, `ask` |
| `Delete remote branch`  | `git push origin --delete <branch>`                                                        | `yes`, `no`, `ask` |
| `Update default branch` | `git checkout <default> && git pull --rebase origin <default>`, in the main checkout only  | `yes`, `no`, `ask` |

- **Delete local branch:** use `-d`, never `-D`; the merged-only safety
  check is the point.
- **Delete remote branch:** pre-check with `git ls-remote --exit-code
  origin <branch>` and skip it, unasked, when the branch is already
  gone. `github-policy-auto-delete-merged-branches` is asynchronous, so
  the branch can still vanish between the check and the push: treat
  `remote ref does not exist` as success, since the end state was
  reached by another path.
- **Update default branch:** bail loudly on a dirty tree, and never
  switch a checkout that has another branch's work in progress.

When any of these keys is unanswered, ask them all in one multi-select
picker, with `All` and `None` first:

> PR `[#N]` merged into `[base-branch]`. Cleanup actions? Your answer is
> saved for `[project]`.

with options `Delete local branch [branch-name]`, `Delete remote branch
[branch-name]` and `Update local [default-branch] from origin`, leaving
out an option whose key is already answered. Save each offered key as
`yes` when picked and `no` when not.

`git-workflow-tidy-branches` covers the same cleanup from the local
side, for branches that piled up; this fires it for one PR at the
moment it lands.

### On close without merge

| Key                      | Values                                    |
| ------------------------ | ----------------------------------------- |
| `On close without merge` | `reopen`, `delete branch`, `leave`, `ask` |

When it's `ask` or missing, ask in a single-select picker:

> PR `[#N]` was closed without merging. What now? Your answer is saved
> for `[project]`.

with options `Reopen PR [#N]` (`gh pr reopen`), `Delete branch
[branch-name] locally and on remote` and `Leave branch [branch-name]
alone`.

Saving `reopen` makes a reopen happen with no one asked, which fights a
deliberate close; offer it, but save it only when the user picked it
and said to keep doing it. Otherwise save `ask` after a reopen.

### Saving the answer

Write the key into the project's file,
`<project>/.agents/skills/github-workflow-pull-request-watcher.preferences.md`,
where `<project>` is the session's project directory
(`$CLAUDE_PROJECT_DIR`), not the PR's repository when the two differ: the
file is read from there when this skill loads. Keep the file a Markdown
list, one `- Key: value` line per key, and change only the keys just
answered:

```markdown
- Delete local branch: yes
- Delete remote branch: yes
- Update default branch: no
- On close without merge: leave
```

Then commit it in the project, on its own, with a subject such as `Save
the PR watcher's on-merge answers`; push only as the project's push
rules allow. Tell the user in the same reply that the answer is saved
and that editing the file changes it.

The user's own file, next to this skill's folder, is generated by their
Home Manager config, so don't write it: when the user wants an answer
for every project, propose the `home.file` entry for it instead, as
`coding-agent-skill-references` says.

## Companion hook: `pull-request-sync-check.sh`

This skill ships a PostToolUse hook, `pull-request-sync-check.sh`,
that closes the local-amend
gap the Monitor can't reach. The Monitor watches GitHub-side events
after a push; the hook fires on the *local* `git commit --amend`
and `git push` Bash calls and probes
`gh pr list --head <branch> --state open`. If an open PR exists
and HEAD's commit subject or body has drifted from the PR's
title/body, the hook emits a `systemMessage` with the exact
`gh api --method PATCH …` invocation to re-sync (per
`github-hygiene-pull-request-mirrors-commit`).

Behaviour contract:

- Gate on the command pattern (`git commit --amend` or
  `git push`); other Bash calls exit 0 silent.
- Skip silently when there's no git repo, no current branch
  (detached HEAD), no `gh` available, or no open PR.
- Body comparison is whitespace-normalised (`tr -s '[:space:]' ' '`)
  so a 72-col commit body and a `fmt -w 2500`-unwrapped PR body
  compare equal when the words match.
- Never exits non-zero. Blocking would be hostile; the agent just
  needs the nudge.

To wire it up, add this to your Claude Code `settings.json`, using the
absolute install path for your scope (see "Where the bundled scripts
install" above) — a hook command runs outside any agent working
directory, so the bare filename won't resolve here. The user-scope
path is shown below; swap in the project-scope path if that's where
this skill lives:

```json
"hooks": {
  "PostToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash ~/.claude/skills/github-workflow-pull-request-watcher/scripts/pull-request-sync-check.sh",
          "timeout": 15
        }
      ]
    }
  ]
}
```

Nix users: the script ships via `agent-skill-flake` standard
`installPhase` — the `scripts/` directory is auto-copied into
`$out/share/claude-skills/github-workflow-pull-request-watcher/scripts/`.
The bash shebang plus standard tools (`jq`, `gh`, `git`, `tr`,
`sed`, `diff`, `head`, `fmt`) resolve via the user's PATH at hook-
exec time; no wrapper is needed in the typical case. If you want
fully-pinned dependencies, wrap the script with
`pkgs.writeShellApplication` in a downstream module — the script
itself has no Nix-specific assumptions.

## When to apply

- Arm IMMEDIATELY after every push to a branch with an open or
  imminent PR. No exceptions, including pushes the user explicitly
  requested without asking for a watcher.
- Arm on resuming a session where a PR was opened earlier and the
  prior session ended without a watcher running.
- Re-arm on receiving a notification that a watched PR transitioned
  state (the previous loop may have terminated).

## Your preferences

!`cat "${CLAUDE_SKILL_DIR}/../github-workflow-pull-request-watcher.preferences.md" "${CLAUDE_PROJECT_DIR}/.agents/skills/github-workflow-pull-request-watcher.preferences.md" 2>/dev/null || true`

If your agent doesn't run the line above, read these files yourself if they
exist: `github-workflow-pull-request-watcher.preferences.md` next to this skill's folder, then
`.agents/skills/github-workflow-pull-request-watcher.preferences.md` in the project. A project's
file overrides the user's, and the user's overrides this skill's defaults.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `coding-agent-skill-references`: where this skill's preferences files live, and why the user's own file is proposed to Home Manager rather than written.
- `coding-agent-questions-as-first-class-prompts`: the first-time question goes through the picker, `All` and `None` first.

- `git-workflow-tidy-branches`: the local branch cleanup the on-merge prompt offers.
- `github-hygiene-gh-cli-gotchas`: `gh pr view --json` field limits and other traps that break a watcher silently.
- `github-hygiene-pull-request-mirrors-commit`: re-syncing the PR's title and body, which the companion sync-check hook nudges you to do.
- `github-policy-auto-delete-merged-branches`: GitHub's delete-on-merge setting, which decides whether the remote branch is already gone on merge.
- `github-workflow-pull-request-status-line`: the status line and comment-block format used to report each Monitor event.
