---
name: git
version: 0.1.0
description: |
  Opinionated Git hygiene: commit message formatting, history cleanliness,
  safe force-pushing, branch naming for tab completion, post-merge
  branch cleanup, `.gitignore` discipline, and SSH-over-HTTPS remotes.
  Apply these whenever creating commits, force-pushing, naming branches,
  merging, noticing stale merged branches, editing `.gitignore`, or
  adding/cloning remotes.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - AskUserQuestion
---

# git — Git Hygiene Rules

Apply these rules whenever you are about to create a commit, force-push,
name a branch, merge, or notice stale merged branches. The goal is a clean,
readable history that future readers (including future-you) can mine for
context.

## How to load this skill

This skill is a passive reference, not a command. Loading it does **not**
mean the user wants you to perform a git operation right now. Do not run
`git status`, stage files, create commits, push, or rewrite history on
load. Just internalize the rules below and apply them the next time a git
operation comes up — whether that is later in this turn, the next turn, or
several turns from now.

If the user invokes this skill and there is no pending git work in the
conversation, acknowledge briefly (or say nothing) and continue. Wait for
an explicit request before acting.

## 1. Commit log messages

- **First line under 72 characters.** Aim for ~50, hard cap at 72 — the
  50/72 convention from [Tim Pope's *A Note About Git Commit Messages*
  (2008)](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html),
  restated by [Chris Beams' *How to Write a Git Commit Message*](https://cbea.ms/git-commit/)
  and *Pro Git* §5.2. GitHub, `git log --oneline`, and most tools truncate
  or wrap past 72 (see the `github` skill rule 7 for the empirical GitHub
  truncation). Use the imperative mood ("Add X", not "Added X").
- **Blank line after the first line.** Many tools rely on this to separate
  subject from body. No blank line means the body gets glued to the subject.
- **Wrap body lines at 72 characters.** `git log` indents the body by 4
  spaces, so wider lines wrap awkwardly in 80-column terminals.
- **Use the body to explain why, not what.** The diff already shows what
  changed. Spend the body on motivation, alternatives considered, landmines
  hit, and links to issues or discussions.
- **Conventional Commits is recommended when applicable.** The
  `type(scope): subject` format (`docs`, `feat`, `fix`, `refactor`,
  `chore`, …) compresses meta into the subject, signals intent at a
  glance, and plays well with changelog generators. When a repo's
  `git log` already follows a different convention, match it instead —
  consistency within a repo beats matching an external standard. The
  `type(scope):` prefix eats into the ~50-char budget; tighten the
  summary side rather than allowing the subject past 72.

When writing a commit, draft the subject first, then add a blank line, then
write the body wrapped at 72. If a subject feels longer than 72, the commit
is probably doing too much — split it.

### 1a. PR descriptions follow the same rule (override the Claude Code template)

PR descriptions are commit messages with a different rendering surface.
Apply rule 1 to them the same way: subject (the PR title), blank line,
body explaining *why* in 1–2 short paragraphs — or no body at all if
the title plus the diff already say enough.

**This rule overrides the Claude Code system prompt's default PR
template.** That template ships boilerplate that this skill rejects:

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
  footer. Not load-bearing on the change; adds noise to PR pages
  and `git log`.
- ❌ `Co-Authored-By: Claude <model> <noreply@anthropic.com>` trailer
  on commits. Only include when the user explicitly wants attribution
  for the AI assist. The change stands on its own; the model version
  is ephemeral and rotating it through commit history adds no value.

**Default to terse.** A PR that fixes a typo gets a one-line
description (or none — the title is enough). A PR that adds a new
rule with a non-obvious rationale gets a paragraph. A PR that
restructures something risky earns the team a Test plan because
*that's where the risk lives*, not because the template said so.

If the user wants the structured template (e.g., their team
requires Summary/Test-plan blocks), they will say so. Until then,
write what rule 1 would write.

This standard doesn't stop applying once the PR is open. If you
later amend the commit behind an open PR, the PR title and body do
not follow automatically — bring them back to these standards by
hand. See rule 5a.

### 1b. Inspect, stage, and review before writing the message

Before turning a working-tree change into a commit, walk three small
steps. None of them takes more than a few seconds; together they catch
the failure modes that show up later as "why is this in my diff?",
"why did I commit my `.env`?", or "this commit does three things at
once."

**1. Inspect before staging.**

```bash
git status         # what changed
git diff           # what the changes are
git diff --stat    # if the diff is too large to scan inline
```

Don't reach for `git add` before reading these. Surprises in `git diff`
— a stray `console.log`, an editor's auto-format-on-save, a secret
that crept in — are cheap to undo before staging and expensive to undo
after committing.

**2. Stage only what belongs in this commit.**

When the changes are clean and all belong together, `git add <paths>`
is fine. When the working tree mixes concerns (refactor + feature,
formatting + logic, tests + prod code), stage by hunks instead:

```bash
git add -p                   # iterate hunk-by-hunk, accept/reject each
git restore --staged -p      # unstage by hunk
git restore --staged <path>  # unstage a file
```

The 1-2-sentence test (step 3) is the forcing function for whether to
split: if you can't describe the staged change in 1-2 sentences (what
+ why), the commit is mixed; unstage some hunks and write a separate
commit for them.

**3. Review what will actually be committed.**

```bash
git diff --cached    # the diff that's about to be committed
```

Scan for three failure modes that often slip past `git diff` in step 1
but become embarrassing after the push:

- **Secrets / tokens.** Hard-coded API keys, `.env` files, `id_rsa`,
  anything with `password=` or `token=` followed by a long random
  string.
- **Debug logging.** `console.log`, `print(...)`, `dbg!`,
  commented-out experiments left over from local poking.
- **Unrelated formatting churn.** A reformatter ran on save and
  rewrote 200 lines you didn't intend to touch. Either separate the
  reformat into its own commit (per step 2) or revert it.

If the repo has a fast meaningful check (a typecheck on the staged
files, a unit-test subset, a `lint --since=HEAD`), run it here too —
cheaper to find a broken commit before it lands in history than after
it does.

If any of these surface a problem, fix and re-stage. Don't commit
"and clean it up next time" — next time is harder.

## 2. Keep historical / diachronic and migration-related info OUT of the code

Resist embedding sentences like "added in v3.2", "TODO: remove after Q4
migration", "this used to do X but we changed it" into source files. That
kind of context belongs in the commit message that introduced or changed
the code. Once it lives in source, it rots: future edits drift, comments
contradict the code, and nobody trusts them.

**Instead:**

- Put the historical context in the commit message body. `git log`,
  `git blame -w -C -C`, and `git log -L :function:file` will surface it
  later for anyone who needs it.
- If a specific line really needs a pointer, leave a short reference rather
  than the history itself: e.g., `// see commit log for migration context`
  or `// blame this line for rationale`. Then a reader can run
  `git blame <file>` on the line to find the commit and read its full
  message.

The test: if you delete the comment, does a curious reader lose anything
they couldn't recover from `git log` / `git blame`? If no, don't write it.

## 3. Squash uninteresting fixes before pushing

Before pushing a feature branch, review your local commits. Anything that
is just "fix typo", "oops", "actually make it compile", or 4 commits of
trial-and-error on the same function is noise — squash it into the parent
commit before pushing.

**But preserve the lessons.** If you hit a real landmine (an undocumented
API quirk, a footgun in the framework, a subtle ordering requirement),
that's valuable. Choose where it belongs:

- **Commit message body** — when the lesson explains why this commit looks
  the way it does. ("Tried passing the buffer directly first; the C API
  silently truncates above 4 KiB, so we chunk.")
- **Code comment** — when the constraint affects future edits. ("Must
  flush before close — the driver drops the last page otherwise.")

Either way, the goal is: future readers benefit from your pain without
having to wade through 6 noise commits to find it.

Use `git rebase -i <base>` (or `git commit --fixup` + `git rebase -i
--autosquash`) to clean up before push. After push, the calculus changes —
see rule 4.

## 4. Always use `--force-with-lease` for force-pushing

Never run plain `git push --force` or `git push -f`. Always:

```
git push --force-with-lease
```

`--force-with-lease` checks that the remote tip is what you last fetched
before overwriting it. If a collaborator (or another machine of yours)
pushed in the meantime, the push is rejected instead of silently
clobbering their work. Plain `--force` will happily destroy commits you
have never seen.

If `--force-with-lease` rejects the push, **stop and investigate** — do
not "fix" it by upgrading to `--force`. Fetch, look at the remote tip,
decide whether to rebase on top or coordinate with whoever pushed.

For extra paranoia on shared branches:
`git push --force-with-lease=<branch>:<expected-sha>` pins the exact SHA
you expect to overwrite.

## 5. Amend forward into existing unpushed commits

When you make follow-up changes to code you already touched in a local,
unpushed commit, the default move is to fold the change into that
existing commit, not stack a new "fix the previous commit" commit on top.

**Why:** the resulting history reads as one coherent change per concern,
not "Add feature" → "Fix feature" → "Actually fix feature" → "Final fix
this time I promise".

**How:**

- Most recent commit: `git commit --amend` (after staging the change).
- Older unpushed commit: `git commit --fixup=<sha>`, then
  `git rebase -i --autosquash <base>`.

**When to break the rule:** if the follow-up is genuinely a different
concern (different file, different intent, different reviewer mental
model), keep it as its own commit. The rule is about avoiding
self-referential noise, not about cramming unrelated work together.

Once a commit has been pushed and others may have pulled it, this rule
flips — see rule 4 about why rewriting pushed history is a coordination
problem.

### 5a. Re-sync the PR title and body after amending

Amending (or rebasing) rewrites the commit message, but it does **not**
update an already-open PR. GitHub derives the PR title and body from the
commit message exactly once, at PR-creation time:

- **Single-commit branch:** title from the commit subject, body from
  the commit message body.
- **Multi-commit branch:** title from the branch name, body left empty.

After that point the PR title and body are independent text. A later
`git commit --amend` + force-push refreshes the diff and the commits
tab but leaves the title and description frozen at their original
wording. If you reworded the commit, the PR page now misrepresents what
it ships.

So whenever you amend a commit on a branch that already has an open PR,
also bring the PR into line with what GitHub *would* derive from the
amended message on a fresh PR:

```
gh pr edit <number> --title "<new subject>" --body "<new body>"
```

Hold the re-synced title and body to rule 1 and rule 1a — they are a
commit message on a different rendering surface, so the same
subject / blank-line / why-not-what discipline applies.

## 6. Branch names: long, descriptive, dash-separated, autocomplete-friendly

Favour branch names like `rate-limit-cache-eviction` over short
cryptic ones (`fix-rl`, `wip`) or sterile dated and numeric ones
(`2026-04-task-1234`, `tmp-3`, `feature-7`). Four properties to
hold the name to:

- **Long enough to read.** Aim for 3-6 words. Weeks-old branch
  listings are browsable when the names are sentences; opaque
  when they're abbreviations.
- **Descriptive of the change.** The topic word is what your
  memory hangs on by the time you're triaging stale branches —
  not the date, not the ticket number, not a counter.
- **Dash-separated** (`rate-limit-cache-eviction`, not
  `rate_limit_cache_eviction` or `RateLimitCacheEviction`).
  That's what git tooling, autocomplete, and URL slugs expect,
  and what reads cleanly in `git log --first-parent`.
- **Autocomplete-friendly against the branches you already
  have.** Before naming, glance at `git branch -a`: pick a
  leading word that disambiguates from the current set in 1-2
  characters. If half the open branches start with `fix-`, your
  next `fix-...` needs most of its name typed before `<TAB>`
  resolves; a more specific topic word at the front fixes that.

**Avoid:**

- **Dates as the leading element** (`2026-04-...`, `q2-...`).
  The year/month is rarely what you remember about a branch,
  and a date prefix pushes the meaningful topic word past where
  autocomplete reaches it first. `git log` already records when.
- **Bare ticket numbers** (`task-1234`, `JIRA-1234`). Only
  acceptable followed by a topic word
  (`JIRA-1234-streaming-api`), never alone.
- **Counter suffixes** (`tmp-3`, `feature-7`, `wip2`). The
  number disambiguates without describing — you're labelling
  without naming.

Read your branch list before opening the PR. If a name doesn't
tell you what the work was in one glance six months later, it's
too short or too generic — rename before the PR lands, because
the name then lives forever in `git log --first-parent` as the
merge commit subject.

## 7. Delete merged branches; flag stragglers

**After merging your own branch into the main branch:**

1. Delete the local branch: `git branch -d <branch>` (use `-d`, not `-D`
   — the lowercase form refuses if the branch isn't merged, which is the
   safety check you want).
2. Delete the remote branch: `git push origin --delete <branch>` (or
   enable auto-delete on the hosting platform).

**When you notice merged branches that this session didn't create**
(e.g., from `git branch --merged main` or `git branch -r --merged
origin/main` showing branches whose tips are reachable from main), flag
them to the user and ask before cleaning up:

> Found N local branches and M remote branches already merged into main:
> [list]. Want me to delete them? (y/n, or pick which ones)

Use `AskUserQuestion` for the prompt — never auto-delete branches the
user didn't explicitly ask you to clean up in this session, even if Git
reports them as merged. Some teams keep merged branches around as
release markers or for historical reasons.

Useful detection commands:

```
git fetch --prune origin
git branch --merged main | grep -v '^\*\|^  main$\|^  master$'
git branch -r --merged origin/main | grep -v 'origin/HEAD\|origin/main\|origin/master'
```

## 8. `.gitignore` discipline

A project's `.gitignore` should describe **what this project produces or
depends on that should not be tracked** — nothing else. Keep it scoped,
keep it accurate, keep it free of personal taste.

### 8a. Anchor truly-absolute paths with a leading `/`

In a `.gitignore`, a pattern without a leading `/` matches at any depth.
A pattern with a leading `/` is anchored to the directory containing the
`.gitignore` (typically the repo root).

If the path you mean to ignore only exists at one specific location, write
it that way:

```gitignore
# Anchored: only the repo-root build/ directory.
/build/
/dist/
/node_modules/

# Unanchored: any node_modules/ at any depth.
# Only use this form when you really do mean "everywhere".
node_modules/
```

**Why it matters:** an unanchored `build/` will also ignore
`src/components/build/` if a developer ever creates one — silently. That
is the kind of bug that takes an afternoon to track down ("why aren't my
files showing up in `git status`?"). Anchoring eliminates the surprise.

When in doubt, anchor. Only drop the leading slash when the pattern
genuinely needs to match at every depth (e.g., `node_modules/`,
`__pycache__/`, `*.log`).

### 8b. Don't put personal/editor preferences in the project `.gitignore`

The popular convention is to dump every editor's side-effects into the
project `.gitignore`: `.idea/`, `.vscode/`, `.DS_Store`, `*.swp`,
`Thumbs.db`, `*~`, `.netrwhist`, and so on. **Don't.**

These do not belong to the project. They belong to the **developer's
machine and tooling choices**. Putting them in the project `.gitignore`
has real costs:

- The list grows forever as new editors and OSes appear, and nobody
  prunes it, so the file accumulates patterns for editors no current
  contributor uses.
- It implicitly endorses one set of tools. New contributors using a tool
  not on the list assume the project doesn't care, and accidentally
  commit their own editor droppings.
- It mixes two different concerns — "what this project builds" and "what
  Bob's machine happens to leave around" — which makes diffs noisier and
  reviews harder.

**The correct place** is the user's **global gitignore**, configured once
per developer and applied to every repo they touch:

```bash
git config --global core.excludesfile ~/.gitignore_global
# Then add personal patterns to ~/.gitignore_global:
#   .DS_Store
#   .idea/
#   .vscode/
#   *.swp
#   *~
```

Each developer curates their own list once and gets coverage everywhere.
The project `.gitignore` stays focused on the project.

**Exception:** if the project's *toolchain* requires editor config that
all contributors share (e.g., a checked-in `.vscode/settings.json` with
required formatter rules), then `.vscode/` is project-relevant and you
*don't* want to ignore it at all. The rule is: ignore project artifacts,
not personal preferences.

### 8c. Use patterns to compress lines, but don't over-broaden

Patterns are leverage. Replacing fifteen explicit log paths with `*.log`
is a clear win — fewer lines, no new file slips through the gap. But the
same instinct, applied carelessly, ignores files you wanted to keep.

**Good compression:**

```gitignore
# Build outputs across all packages
/packages/*/dist/
/packages/*/build/

# Any compiled Python bytecode, anywhere
__pycache__/
*.py[cod]

# All log files in the logs dir
/logs/*.log
```

**Bad over-broadening:**

```gitignore
# Ignores docs/build.md, src/build.ts, anything containing "build"
*build*

# Ignores legitimate config files like .env.example or .env.sample
.env*

# Ignores .gitignore itself, your shell scripts, everything
*
```

Heuristics:

- Anchor with `/` when the pattern should only apply at one location
  (rule 8a).
- Constrain by extension or directory (`/logs/*.log`, not `*log*`).
- For "ignore the family but keep one file", use a negation:
  ```gitignore
  .env*
  !.env.example
  ```
- After adding a broad pattern, run `git status --ignored` (or
  `git check-ignore -v <path>`) on a few candidate files to confirm
  you're only catching what you intended.

The test: can you read each line of `.gitignore` and explain in one
sentence what it ignores and why? If a line is too broad to summarize
without saying "and probably some other stuff", tighten it.

## 9. Use SSH remotes, not HTTPS

When adding a remote (or cloning), prefer the SSH form:

```
git@github.com:<owner>/<repo>.git
```

over the HTTPS form:

```
https://github.com/<owner>/<repo>.git
```

**Why:** HTTPS prompts for a username and a Personal Access Token on every
push and fetch, unless you've installed and configured a credential helper
(macOS Keychain, `git-credential-manager`, etc.). SSH uses the key already
loaded in your `ssh-agent` — no prompt, no token to rotate, no helper to
configure per machine. If your other repos "just work" without prompting,
they almost certainly use SSH.

**Switch an existing remote:**

```
git remote set-url origin git@github.com:<owner>/<repo>.git
git remote -v   # verify
```

**For tools that default to HTTPS** (e.g. `gh repo clone`, `gh repo create
--source=. --push`), either pass `--ssh` / configure
`gh config set git_protocol ssh`, or fix the remote afterward with
`set-url`.

**Good reasons to use HTTPS instead** (the "unless" cases):

- A network or firewall blocks port 22 (corporate proxies sometimes do).
  GitHub offers SSH-over-443 at `ssh.github.com:443` as a workaround
  before falling back to HTTPS — try that first.
- The host doesn't support SSH at all (rare for major forges).
- A short-lived ephemeral environment (CI runner, Codespace) where setting
  up a deploy key is more friction than a token. Even then, prefer
  short-lived OIDC tokens or `gh auth` over a long-lived PAT.

When you do use HTTPS for a real reason, set up a credential helper so
you're not re-typing tokens. On macOS:
`git config --global credential.helper osxkeychain`.

The default should be SSH; the burden of justification is on HTTPS.

## 10. Choose a push workflow before pushing

Before pushing anything to a remote, know which workflow this repo uses.
The choice has real consequences (PR history, review surface, what goes
on the main branch), so don't guess. If you don't already know the mode
for this repo, **ask the user once** and remember the answer for the
rest of the session. A reasonable detection probe to inform the question:

```bash
gh pr list --state all --limit 1 --json number --jq 'length'
```

`0` means no PRs have ever been opened (mode 1 is plausible default).
`1` means the repo has used PRs at least once (mode 2 is plausible
default).

### The three modes

**Mode 1 — Direct-to-main (no-PR-history repo).**
The repo has never had a pull request opened. Default to pushing
straight to the main branch. Subcases:

- *On main, with new commits:* push main.
- *On a feature branch, with new commits:* **push the branch to its
  own remote tracking branch only.** Do not auto-merge into main, do
  not auto-fast-forward main, do not open a PR. The user will merge
  it themselves if they want to. (If you just created the branch in
  this session for a specific task, ask whether to merge it back to
  main before pushing — but otherwise leave it alone.)

**Mode 2 — PR-always (never push to main).**
The repo uses pull requests as its review boundary. Never push commits
directly to main. Subcases:

- *On main, with new commits:* this is anomalous — commits should not
  be landing on main locally. Stop and ask. Likely fix: move the
  commits to a feature branch (`git switch -c <branch>`), reset main
  to its remote tip, push the branch, open a PR.
- *On a feature branch, with new commits:* push the branch, then
  **ask the user whether to open a PR** (`gh pr create`). If a PR
  for the branch already exists (`gh pr list --head <branch>`), just
  push — the existing PR's diff updates automatically, but its title
  and body do not. If you amended or reworded the commit, re-sync
  them per rule 5a.

**Mode 3 — Ask each time.**
The user wants a per-push prompt. Before any push, ask: "Push to main
directly, or open a PR?" — with the current branch state baked into
the question.

### What to ask, when

- **First push of the session in a repo whose mode you don't know:**
  ask the user which mode to use (see "Question script" below). Offer
  the three modes and recommend the one suggested by the `gh pr list`
  probe above. Remember the answer.
- **First time on a feature branch in modes 1 or 2:** the on-branch
  behavior is a sub-decision; ask the relevant follow-up from the
  question script if you don't already know the user's preference.
- **Every subsequent push in that session:** apply the chosen mode
  silently — the whole point of picking a mode is to stop asking.
  Exception: Mode 3, which always asks.
- **Anomalous states** (on main with PR-always mode, on a detached
  HEAD, mid-rebase, etc.): always stop and ask, regardless of mode.

### Question script

Use these exact questions (via `AskUserQuestion` or equivalent) so
the user gets a consistent prompt across sessions and repos. The
recommended option is marked; pick whichever the `gh pr list` probe
suggests, or fall back to "Ask each time" when in doubt.

**Q1 — Primary mode (ask once per repo per session):**

> Which Git push workflow do you want to use for this repo?
>
> - **Mode 1 — Direct to main:** This repo has never had a PR opened;
>   just push commits straight to the main branch. (Recommend if
>   `gh pr list --state all --limit 1` returns 0.)
> - **Mode 2 — PRs always:** Never push directly to main. Always go
>   through a feature branch + pull request. (Recommend if the repo
>   has any PR history.)
> - **Mode 3 — Ask each time:** Prompt before every push.

**Q2 — On-branch follow-up (ask only if Mode 1 was picked AND the
user is on a feature branch):**

> In Mode 1 (no PRs ever opened — just push to main), what should
> happen when you're sitting on a feature branch with new commits
> and ask Claude to push?
>
> - **Push the branch only:** Push the current branch to its remote
>   (creating an upstream if needed). Don't touch main. The branch
>   lives independently; user merges it themselves later if they
>   want.
> - **Fast-forward main, push main:** If main can fast-forward to
>   the branch tip, do that locally, push main, then delete the
>   feature branch. If it can't FF, fall back to asking.
> - **Merge into main, push main:** Switch to main, merge the
>   feature branch (FF or merge commit), push main, delete the
>   feature branch. Closest to "just push to main" behavior.
> - **Ask in this case:** Mode 1 covers main-only pushes; if you're
>   on a branch, the situation is ambiguous enough that Claude
>   should ask each time anyway.

**Q3 — On-branch follow-up (ask only if Mode 2 was picked AND the
user is on a feature branch):**

> In Mode 2 (PRs always — never push to main), what should happen
> when you're on a feature branch and ask Claude to push?
>
> - **Push branch + open PR:** Push the branch and, if no PR is
>   open for it yet, open one with `gh pr create`. If a PR already
>   exists, just push — the diff updates, but re-sync the title and
>   body per rule 5a if you amended the commit message.
> - **Push branch only:** Just push the branch. Don't auto-open a
>   PR — leave that to the user. (Useful if the user prefers to
>   write PR descriptions themselves or uses a non-`gh` flow.)
> - **Ask whether to open PR:** Push the branch, then ask whether
>   to open a PR. Sub-question per push.

After collecting answers, hold them in working memory for the rest
of the session. Don't re-ask. If the user later says something
inconsistent with the answer ("actually, open a PR for this one"),
treat that as a one-off override, not a mode change — unless they
explicitly say "switch modes".

### Why this rule exists

Pushing is the action with the largest blast radius in this skill —
it's the moment work becomes visible to others, gets attached to a
review process (or doesn't), and starts showing up in history that
future readers can't easily rewrite. A repo that uses PRs has a
social contract around review; bypassing it with a direct push is
expensive to undo and signals disrespect for the contract. A repo
that doesn't use PRs has a different contract — opening one
unprompted creates noise. Picking the right path requires knowing
the repo's norms, and the cheapest way to know is to ask once.

## When to apply

- About to write a commit message → rules 1, 2, 3
- About to stage and commit changes → rule 1b
- About to add a "historical note" comment → rule 2
- About to force-push → rule 4
- Made a follow-up change to unpushed work → rule 5
- Amended/reworded a commit on a branch with an open PR → rules 5a, 1a
- About to create a new branch → rule 6
- A PR just merged, or `git branch --merged` shows stragglers → rule 7
- About to edit `.gitignore`, or reviewing one → rule 8
- About to add a remote, clone a repo, or hitting credential prompts → rule 9
- About to push anything to a remote → rule 10
