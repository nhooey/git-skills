---
name: github
description: |
  Opinionated GitHub repository hygiene plus the agent pull-request
  lifecycle. Apply these rules for ANY GitHub operation — anything
  that reaches a GitHub server: a push, force-push, or fetch against
  a GitHub remote; opening, amending, re-titling, reviewing, or
  merging a pull request; creating or auditing a repo. They cover
  protecting the default branch (block direct/force pushes and
  deletion, require PRs), auto-deleting merged head branches,
  keeping every PR a thin wrapper over its single commit (title =
  commit subject, body = unwrapped commit body, re-synced after each
  amend), surfacing PR URLs with live status, and watching PR state.
  Companion to the `git` skill — load both whenever a local git
  action will talk to a GitHub remote.
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
  - Monitor
---

# github — GitHub Repository Hygiene

Apply these rules when you create a new GitHub repository, when you
notice an existing repo is unprotected, or when stale merged branches
are accumulating on the remote. Companion to the `git` skill, which
covers the local side of the same workflow.

The mechanics below use `gh` (GitHub CLI). Equivalent settings live
under the repo's **Settings → Branches** and **Settings → General →
Pull Requests** UI panels if you'd rather click.

## 1. Protect the default branch

The default branch (`main` or `master`) is what every fresh clone
checks out and what production deploys typically track. An
unprotected default branch lets anyone with write access push
broken commits straight to it, force-push over published history,
or delete the branch entirely. None of those should be possible
in a single keystroke.

**Minimum protection rules to set:**

- **Require a pull request before merging.** Direct pushes to the
  default branch are blocked; every change goes through a PR. This
  is the single most important rule — most of the others enforce
  themselves once direct pushes are gone.
- **Require status checks to pass before merging.** Whatever CI you
  have (tests, type checks, lint, security scans) must be green.
  Pick the specific check names; "require any check" is too loose
  and lets a missing CI run masquerade as success.
- **Require branches to be up to date before merging** when status
  checks are required. Otherwise a PR can merge green against a
  base that has since broken — and you only find out on `main`.
- **Block force-pushes.** Rewriting published history on the default
  branch is almost never what you want; if it is, lift the rule
  deliberately for that one operation and put it back.
- **Block deletions.** Self-explanatory. The default branch should
  not be deletable by anyone short of a repo admin override.
- **Apply rules to administrators too.** Admins shouldn't have a
  side door around the rules they set. Carve out exceptions for
  break-glass moments, not as the default.

**Apply with `gh`** (uses the modern Rulesets API — supersedes the
older branch protection endpoints, which still work but are being
phased out):

```bash
# Replace <owner>/<repo> and adjust the required check name.
gh api -X POST "repos/<owner>/<repo>/rulesets" \
  --input - <<'JSON'
{
  "name": "protect-default-branch",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "bypass_actors": [],
  "rules": [
    { "type": "pull_request" },
    { "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "ci" }
        ]
      }
    },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ]
}
JSON
```

`non_fast_forward` blocks force-pushes; `deletion` blocks branch
deletion. `~DEFAULT_BRANCH` is GitHub's symbolic ref for "whatever
the default branch is right now" — it follows along if you rename
`master` → `main` later.

**Verify** afterward by visiting `Settings → Rules → Rulesets`, or
with:

```bash
gh api "repos/<owner>/<repo>/rulesets" --jq '.[] | {name, enforcement, target}'
```

## 2. Auto-delete head branches after merge

Once a PR is merged, the source branch has done its job. Leaving
it on the remote creates two ongoing costs:

- **`git branch -r` becomes unreadable.** Active branches drown in
  hundreds of merged-and-forgotten ones. `git fetch --prune` only
  helps after someone has deleted them on the remote.
- **Stale branches confuse tooling.** PR-checkers, deploy previews,
  and "open PRs by branch" UIs all key off branch names. Resurrected
  names (`fix-login` reused six months later) collide with stale
  refs and produce surprising behaviour.

GitHub has a per-repo toggle that deletes the head branch
automatically when a PR is merged. Turn it on.

**Apply with `gh`:**

```bash
gh api -X PATCH "repos/<owner>/<repo>" \
  -f delete_branch_on_merge=true
```

**Verify:**

```bash
gh api "repos/<owner>/<repo>" --jq '.delete_branch_on_merge'
# → true
```

In the UI: **Settings → General → Pull Requests → Automatically
delete head branches**.

**Scope.** The setting only deletes the *source* branch of a merged
PR — never the base branch, never branches that close without
merging, never branches with no associated PR. It is safe to enable
on any repo where contributors land changes via PRs.

**Forks are unaffected.** Auto-delete operates on the head branch
in the head repository. When the PR comes from a fork, the
contributor's fork keeps its branch — that's their cleanup.

## 3. Other defaults worth setting once

When you're already in the repo settings, a few low-cost changes
pair naturally with rules 1 and 2:

- **Merge PRs with `--no-ff` (merge commits only).** Disable squash
  and rebase merges so every PR lands as an explicit merge commit,
  even when fast-forward would be possible. Two reasons: the merge
  commit is a clean revert point for the whole PR (`git revert -m 1
  <merge-sha>` undoes the entire feature in one go), and the
  branch's individual commits stay on disk where `git log
  --first-parent`, `git log --graph`, and `git blame` can use them.
  Squash-merge discards those commits and their messages; rebase-
  merge loses the topology. The `git` skill (rules 3 and 5) is
  already telling you to curate those commits — `--no-ff` is what
  makes the curation visible after merge.

  ```bash
  gh api -X PATCH "repos/<owner>/<repo>" \
    -f allow_merge_commit=true \
    -f allow_squash_merge=false \
    -f allow_rebase_merge=false
  ```

  Do **not** add `{ "type": "required_linear_history" }` to the
  ruleset — that rule rejects exactly the merge commits this option
  produces. The two settings are mutually exclusive; pick one.

- **Set up CODEOWNERS** if more than one person can merge. Pairs
  with the ruleset's `require_code_owner_review` flag (flip it to
  `true` once `.github/CODEOWNERS` exists).

## 4. When applying to an existing repo

If the repo has been unprotected for a while, expect cleanup:

1. **Audit local clones.** Run `git fetch --prune` to drop tracking
   refs whose remote branches have already been deleted. See the
   `git` skill's rule 7 for the post-merge local cleanup workflow.
2. **Survey stale remote branches.** Many will already be merged:
   ```bash
   gh api "repos/<owner>/<repo>/branches?protected=false&per_page=100" \
     --jq '.[].name' | head -50
   ```
   Don't bulk-delete without asking. Use `AskUserQuestion` to
   confirm before pruning branches the current session didn't
   create — some teams keep release branches around.
3. **Watch for direct-push patterns.** Once the PR rule is on, any
   contributor whose habit was `git push origin main` will hit a
   wall. Mention rule 1 in the PR/issue you open to announce the
   change.

## 5. `gh` CLI gotchas when landing PRs

Three failure modes worth knowing before they cost a debugging
detour. All observed against `gh` 2.85+ and the current GitHub REST
API.

**`gh pr edit` exits 1 on a Projects-classic deprecation warning,
without applying the edit.** Symptom:

```
$ gh pr edit 3 --body-file body.md
GraphQL: Projects (classic) is being deprecated in favor of the new
Projects experience, see: https://github.blog/changelog/2024-05-23-...
$ echo $?
1
```

The body is *not* updated despite no other error. The warning fires
because `gh pr edit` queries the deprecated
`repository.pullRequest.projectCards` field in its standard request
set. Workaround: skip `gh pr edit` and PATCH directly through the
REST API, which doesn't touch Projects classic:

```bash
gh api --method PATCH "/repos/<owner>/<repo>/pulls/<num>" \
  -f body="$(cat body.md)"
```

Use `-f` (`--raw-field`), not `-F` (`--field`), for prose fields:
`-F` auto-types and silently turns a body of `"42"` into the JSON
number `42`. Prefer shell substitution (`$(cat …)`,
`$(git log -1 --pretty=%b)`) over `--field body=@path` — no stale
`/tmp` file, no race with a parallel agent.

**`gh pr view --json merged` is not a valid field.** The accessor is
`state` (`OPEN` / `MERGED` / `CLOSED`), not `merged`. A merge-watcher
needs:

```bash
gh pr view <num> --json state --jq .state
# emits one of: OPEN, MERGED, CLOSED
```

`mergedAt` (non-null when merged) is also valid. Don't try `merged`
— it errors with `Unknown JSON field: "merged"` and lists every
available field, which is a lot of noise to scroll past when
debugging a watcher script.

**GitHub blocks self-approval.** Even with admin rights you can't
`gh pr review --approve` a PR you authored — the API rejects with
`Review Can not approve your own pull request`. For solo workflows
(stacked PRs you push and merge yourself), skip approval and merge
directly:

```bash
gh pr merge <num> --merge --delete-branch
```

The `--delete-branch` flag deletes both the remote branch and the
local tracking ref in one shot — useful as a one-off if rule 2's
repo-level `delete_branch_on_merge` setting isn't (yet) enabled.

**`POST /repos/{owner}/{repo}/branches/{branch}/rename` auto-closes
open PRs whose head is that branch.** GitHub's docs imply head refs
follow the rename; in practice they don't. Observed 2026-05-13 on
`nhooey/skills-nix`: four `nhooey/2026-04-*` branches were renamed
via `gh api -X POST .../rename`; the API succeeded, the branches
were renamed, every open PR with the old head ref recorded a
`head_ref_deleted` event and was auto-closed. The PR's `head.ref`
field continued to show the old name. Recovery requires either
reverting the rename or recreating the PRs against the new branch.

Since GitHub does not permit changing a PR's `head_ref` after
creation, the procedure for renaming a branch with an open PR is:

```bash
# 1. Capture the PR's metadata.
gh pr view <num> --json title,body,baseRefName > /tmp/pr.json

# 2. Rename locally and push the new name from the same tip.
git branch -m <old> <new>
git push -u origin <new>

# 3. Open a new PR with the captured content.
gh pr create --base "$(jq -r .baseRefName /tmp/pr.json)" \
  --head <new> \
  --title "$(jq -r .title /tmp/pr.json)" \
  --body "$(jq -r .body /tmp/pr.json)"

# 4. Comment-close the old PR pointing at the new one.
gh pr comment <old-num> --body "Superseded by #<new-num> after \
renaming the branch from \`<old>\` to \`<new>\`."
gh pr close <old-num>

# 5. Delete the old remote branch.
git push origin --delete <old>
```

The PR number changes — that's unavoidable. Before running the
rename API on any branch, run
`gh pr list --state open --json headRefName,number` and stop if any
open PR has that branch as its head.

## 6. After pushing to a PR branch, watch and react to state changes

After pushing to a branch with an open (or imminent) PR, arm a
background watcher that emits on *every* PR event — check
completions, comments, reviews, labels, merge, close — and react
to each. Don't wait passively for the merge: by the time it
lands, the user has often been pinging the agent through other
channels (a comment on the PR, a review, a red CI run).

Obvious reactions per event type:

- **Check green** — surface 🟢 in the next reply.
- **Check red** — read the log (`gh run view <id> --log`),
  propose a fix, surface 🔴.
- **Comment from the session-running user** (identify with
  `gh api user --jq .login` matched against `.user.login` on
  the comment) — treat as a chat instruction. The user is using
  GitHub as the conversation surface (often because they're on
  mobile or reviewing the diff side-by-side). Read it, do the
  work locally, and surface a *comment line* in your chat reply
  confirming what was addressed (format defined in rule 8).
  **Don't post a reply on the PR itself** — that publishes
  under the user's identity, and the safety layer blocks it
  (rightly: the agent shouldn't speak as the user). The chat
  comment line is the substitute: the user sees which comment
  was handled and how, without the agent posting publicly.
- **Comment from anyone else** — surface to the user, don't
  auto-react.
- **Review approved** — surface 🟢; merge unblocked.
- **Review requests changes** — read the review, propose the
  changes, surface 🔴.
- **Blocking label added** (`do-not-merge`, `needs-work`, etc.)
  — hard pause; surface and wait for instruction.
- **Title/body edited or branch updated by someone else** —
  accept the override, re-fetch before any destructive op.
- **Merged** — fire the cleanup prompt below.
- **Closed without merge** — ask whether to reopen, delete the
  branch, or leave it.

**One Monitor, one loop, multiple sources.** Poll the check-runs,
issue-comments, and PR-state endpoints in a single loop and emit
each delta as a recognizable line:

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
accessor — `merged` isn't a valid field (see rule 5). Both
comment endpoints are fetched exactly once per iteration: the
shared `fmt_comments` jq filter is parameterized via `--arg` and
`--argjson` so issue and inline-review comments flow through the
same emit logic without duplication. The `reviewDecision`
fallback uses an explicit `null`-and-`""` check rather than jq's
`//` operator: GitHub returns `""` (empty string), not `null`,
when no review has been submitted, and `//` only catches null /
false — `(.reviewDecision // "none")` would emit nothing instead
of `none` for unreviewed PRs.

**Guard against transient empty fetches.** Each poll guards with
`if [ -n "$cur" ]; then …; fi` (and analogous for the comment
fetches): a brief `gh api` failure or rate-limit hiccup returns
an empty body, which would otherwise (a) regress `prev_checks`
to empty and re-emit every check on the next successful fetch,
(b) regress `max_issue` / `max_review` to `0` and re-emit every
existing comment, and (c) cause `comm -13` of a non-empty
`prev_checks` against an empty `cur` to print one empty line
that `sed 's/^/CHECK /'` would render as a bare `CHECK` event.
The `awk 'NF { print … }'` (instead of `sed`) is defence in
depth — even if the guard fails, empty lines never get a prefix.

**Alternative architectures (noted, not prescribed).** The
polling Monitor above is the right default for an interactive
agent session. Other paths exist if the surrounding system
already supports them:

- **GitHub Actions** on `pull_request_review_comment`,
  `issue_comment`, `pull_request_review`, etc. — fires the
  workflow with the full event payload as context, no polling.
  Anthropic ships `claude-code-action`; community variants
  exist.
- **GitHub webhooks** to an external service deliver the same
  events without committing to Actions; needs hosting and an
  HTTPS endpoint reachable from GitHub.
- **GitHub Apps** (e.g. via Probot) add a bot identity that
  can post under its own name rather than the user's, plus
  persistent state across events.

These shift the architecture from agent-polls to
event-driven-invocation. They're heavier to set up, and the
agent can't bootstrap them mid-session, so don't reach for them
unless they're already wired up — stick with the Monitor when
running interactively.

**On merge, prompt with `AskUserQuestion` (multi-select).** Three
cleanups, all default-checked:

- **Delete locally** — `git branch -d <branch>` (use `-d`; the
  merged-only safety check is the point).
- **Delete on remote** — `git push origin --delete <branch>`.
  Pre-check with `git ls-remote --exit-code origin <branch>`
  and skip the option entirely if the branch is already gone.
  But rule 2's `delete_branch_on_merge` is asynchronous — the
  pre-check can pass and the branch can vanish in the window
  between the prompt and the user's pick — so the actual
  `git push --delete` must treat `error: unable to delete
  '<branch>': remote ref does not exist` as success, not
  failure. The desired end-state has been reached, just by
  another mechanism. A no-op question is noise; a phantom
  failure on the cleanup is worse.
- **Rebase local default** — `git checkout <default> && git pull
  --rebase origin <default>`. Bail loudly on a dirty tree.

The `git` skill's rule 7 covers the same cleanup from the local
side; this rule fires it at the right moment.

## 7. Open PRs as a thin wrapper over a single commit

GitHub's default for a one-commit PR is title = commit subject,
body = commit body (trailers included). Match that:

- **One commit per PR.** Squash or amend locally before opening.
- **Title = subject, body = body.** No `## Summary` block, no
  `## Test plan` checklist, no "Generated with Claude Code"
  footer — nothing GitHub wouldn't prefill from the commit.

Anything in the PR description that isn't in the commit message
becomes orphaned state — invisible to `git log`, `git blame`,
`git show`, `git format-patch`, and every fork or mirror. The
commit is the durable record; the PR is the review surface. If
you want a Summary or Test-plan section, put it in the commit
body so both surfaces have it.

**Unwrap hard-wrapped lines before opening.** Commit bodies are
hard-wrapped at ~72 cols for `git log` readability, but GFM
renders single newlines as hard breaks — so the PR description
becomes jagged short lines instead of flowing paragraphs. Re-fill
paragraphs to one long line each (blank-line breaks survive):

```bash
gh pr create \
  --title "$(git log -1 --pretty=%s)" \
  --body "$(git log -1 --pretty=%b | fmt -w 2500)"
```

`fmt -w 2500` is the practical maximum — GNU `fmt` 9.7 rejects
widths much above that with `Result too large`, and 2500 is
already an order of magnitude past any realistic paragraph.
`par` is a fancier alternative if installed; `awk
'BEGIN{RS="";ORS="\n\n"} {gsub(/\n/," ");print}'` has no width
limit at all. **Avoid `gh pr create --fill`** for multi-paragraph
bodies — it passes the message through verbatim, hard wraps and
all.

**The unwrap is not optional just because you hand-build the
payload.** `--fill` is the obvious trap, but constructing the body
yourself reintroduces the same one: a heredoc, a `jq -n --arg
body "$(…)"`, or `gh api … --input -` with a JSON body all preserve
every `\n` verbatim, so a 72-col commit body goes in jagged exactly
as if you'd used `--fill`. The reflow (`fmt -w 2500`, `par`, or the
`awk` one-liner) must run on the body text *before* it is captured
into the variable / heredoc / JSON — there is no rendering surface
between `jq --arg` and GitHub that will re-fill it for you. If you
reach for `jq -n --arg body` to "be safe with quoting," you've
picked the one route that quietly keeps the wrap.

**Re-sync the PR after any commit amend.** Force-pushing an
amended commit does *not* refresh the PR's title or description
— GitHub leaves whatever you opened with, silently violating the
contract above. PATCH both fields after every amend (also the
fix for `--fill` drift, an early body edit, or a template-opened
PR):

```bash
gh api --method PATCH "/repos/<owner>/<repo>/pulls/<num>" \
  -f title="$(git log -1 --pretty=%s)" \
  -f body="$(git log -1 --pretty=%b | fmt -w 2500)"
```

`--pretty=%b` (lowercase) strips the subject line — it belongs
in `title`. `%B` (uppercase) would double-print it. `-f` vs
`-F`, and shell substitution vs `body=@path`: see rule 5.

Caveat: `fmt` unwraps fenced and indented code blocks too. Rare
in commit messages, but if the body has code, run `fmt` only on
the prose.

## 8. Surface PR URLs visibly when you create or refer to one

Whenever the PR comes up in a reply, output its URL on its own
line in this exact format:

```
<status> <url> — **PR #<num>: <PR title>**
```

- **`<status>`** — colored circle reflecting live PR/check
  state. The load-bearing visual; users skim for the dot before
  reading prose:
  - 🟡 checks running, not yet merged
  - 🟢 checks passed, mergeable
  - 🔴 at least one check failed
  - 🟣 merged (matches GitHub's own merged-PR color)
  - ⚪ closed without merge
- **`PR #<num>:`** goes inside the bold span. The number is what
  users grep for when several PRs are open.
- **`<PR title>`** — the literal PR title. Wrap the whole
  `PR #<num>: <title>` in Markdown bold (`**…**`). Don't use
  ANSI codes (`\x1b[95m…\x1b[0m`) — Claude Code's Markdown
  renderer strips ANSI from agent replies, even though the
  terminal itself supports it. (Claude Code's own TUI elements
  like "Thinking…" bypass the Markdown pipeline; agent replies
  don't.) Bold is the reliable cross-renderer visual.

Example for a PR with all checks green, ready to merge:

```
🟢 https://github.com/owner/repo/pull/123 — **PR #123: Document the agent PR lifecycle**
```

**Emit this every time the PR comes up.** On `gh pr create`,
every Monitor event, every citation by number ("PR #9 …"), every
user question about it, and before/after any operation that
changes it (push, force-push, comment, label, merge). Recompute
the status circle from live state each time — a stale 🟡 on a PR
that has actually gone red is worse than no circle. The line is
cheap; skipping it loses the user across several open PRs or
hides state transitions you reacted to in prose without
resurfacing the link.

**Comment block — three lines, indented under the PR line.**
When you react to a PR comment (review-thread or issue-level),
attach a three-line block to the PR line. Each comment becomes
its own little checklist entry hanging off the PR:

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

Anatomy:

- **Indent.** Comment-URL line is indented 2 spaces under the PR
  line; the 🗣 and 🤖 lines are indented 2 spaces further (4
  total). The indent subordinates the comments visually under
  the PR they belong to.
- **🔲 / ✅** is the completeness marker: 🔲 (U+1F532 black
  square button) = outstanding / not yet addressed, ✅ (U+2705
  white heavy check mark) = addressed. The green check on ✅
  echoes 🟢 on the PR line, so a finished comment block reads
  as visually consonant with a mergeable PR.
- **🗣 line** (U+1F5E3 speaking head) carries who said what.
  Bold the author + location if multiple comments are stacked
  and they need disambiguation; plain text otherwise.
- **🤖 line** carries what the agent did about it. Always 🤖
  — the point is to name the actor (the agent) consistently
  against the 🗣 line above; the *what* lives in the prose
  after the glyph.

The comment URL is the `.html_url` field on the comment API
response (e.g. `gh api repos/.../pulls/<num>/comments` →
`.[].html_url`).

This is the workaround for the agent-impersonation guardrail
(see rule 6): `gh pr review --reply` and `gh api ...
/comments/<id>/replies` post under the user's identity and the
safety layer blocks them. The comment block keeps the user in
the loop without anything getting published publicly. Emit one
block per reacted-to comment in the same reply where the
underlying work is reported.

## 9. After a change-set, ask what to do next

Once you've made changes in the work tree, don't auto-decide
whether to stage, commit, push, or follow up on the PR. Present
a multi-select (checkbox) prompt via `AskUserQuestion` —
`multiSelect: true`, never single-select / radio — with these
eight options, in this order:

- **Stage** — `git add` the changed files.
- **Commit** — new commit (`git commit`).
- **Amend** — fold into the last commit (`git commit --amend`).
- **Push** — regular `git push`.
- **Force** — `git push --force-with-lease`.
- **Open Pull Request** — `gh pr create` per rule 7 (single
  commit, `--fill`-equivalent title and unwrapped body).
- **Re-derive PR name + title** — re-PATCH title and body per rule 7.
- **Monitor + react** — arm or re-arm the rule-6 watcher.

`AskUserQuestion` caps each question at 4 options, so split
into three multi-select questions:

- **Local actions** — Stage, Commit, Amend.
- **Push actions** — Push, Force, Open Pull Request.
- **Follow-up** — Re-derive PR name + title, Monitor + react.

Commit and Amend are mutually exclusive in the user's mind; if
both get checked, ask which they meant rather than guessing.
Same for Push and Force. Open Pull Request and Re-derive PR
name + title are likewise mutually exclusive — one applies when
no PR yet exists, the other when one already does.

**Pre-select from the last instance of this question within the
session.** Workflows repeat: refining a single-commit PR
typically loops Stage + Amend + Force + Re-derive PR name + title +
Monitor, and re-clicking those every iteration is friction. On
the first ask of the session (no prior instance), pre-select by
context:

- New branch, no PR yet → Stage + Commit + Push + Open Pull
  Request + Monitor.
- Refining an existing PR → Stage + Amend + Force + Re-derive
  PR name + title + Monitor.
- Trivial doc edit, no PR → Stage + Commit + Push.

Resurface the question after every change-set; the user's last
answer is a hint, not a binding default.

## When to apply

- Creating a new GitHub repo → rules 1, 2, 3 immediately.
- Auditing an existing repo with no branch protection → rule 1.
- Noticing a wall of merged branches on the remote → rule 2.
- Adding a second contributor → rule 1 (raise the review count, add
  CODEOWNERS).
- Renaming the default branch → confirm `~DEFAULT_BRANCH` still
  matches your ruleset's target (it does, by design — but check).
- Pushing to a branch with an open (or imminent) PR → rule 6 (arm
  the merge watcher before moving on).
- Opening any PR from an agent session → rules 7 and 8 (single
  commit, default title/body, surface the URL visibly).
- Finishing any change-set in the work tree → rule 9 (ask before
  committing/pushing rather than auto-deciding).
