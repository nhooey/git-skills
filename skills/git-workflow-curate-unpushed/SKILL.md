---
name: git-workflow-curate-unpushed
description: |
  Curate local history before pushing: squash noise commits ("fix typo",
  "oops", trial-and-error iterations), and amend forward into existing
  unpushed commits rather than stacking "fix the previous commit"
  commits. Preserve real lessons in commit bodies or code comments.
  Apply before any push of a feature branch, and to any follow-up change
  on an unpushed commit.
tags: [workflow, style]
allowed-tools:
  - Bash
  - Read
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: bash "${CLAUDE_SKILL_DIR}/scripts/detect-noise-commits.sh"
          timeout: 15
---

# git-workflow-curate-unpushed

Apply when you have unpushed commits and want to clean them up before
they hit the remote. Two complementary moves: squash uninteresting
fixups, and amend forward into existing unpushed commits rather than
stacking new "fix the previous commit" commits.

## How to load this skill

Passive reference. Loading it doesn't mean you should rewrite history
now — just that when you make a follow-up change to unpushed work, or
when you're about to push, you'll curate first.

## 1. Squash uninteresting fixes before pushing

Before pushing a feature branch, review your local commits. Anything
that is just "fix typo", "oops", "actually make it compile", or 4
commits of trial-and-error on the same function is noise — squash it
into the parent commit before pushing.

**But preserve the lessons.** If you hit a real landmine (an
undocumented API quirk, a footgun in the framework, a subtle ordering
requirement), that's valuable. Choose where it belongs:

- **Commit message body** — when the lesson explains why this commit
  looks the way it does. ("Tried passing the buffer directly first; the
  C API silently truncates above 4 KiB, so we chunk.")
- **Code comment** — when the constraint affects future edits. ("Must
  flush before close — the driver drops the last page otherwise.")

Either way, the goal is: future readers benefit from your pain without
having to wade through 6 noise commits to find it.

Use `git rebase -i <base>` (or `git commit --fixup` + `git rebase -i
--autosquash`) to clean up before push. After push, the calculus
changes — coordinate before rewriting public history.

## 2. Amend forward into existing unpushed commits

When you make follow-up changes to code you already touched in a local,
unpushed commit, the default move is to fold the change into that
existing commit, not stack a new "fix the previous commit" commit on
top.

**Why:** the resulting history reads as one coherent change per
concern, not "Add feature" → "Fix feature" → "Actually fix feature" →
"Final fix this time I promise".

**How:**

- Most recent commit: `git commit --amend` (after staging the change).
- Older unpushed commit: `git commit --fixup=<sha>`, then `git rebase
  -i --autosquash <base>`.

**When to break the rule:** if the follow-up is genuinely a different
concern (different file, different intent, different reviewer mental
model), keep it as its own commit. The rule is about avoiding
self-referential noise, not about cramming unrelated work together.

Once a commit has been pushed and others may have pulled it, this rule
flips — rewriting pushed history is a coordination problem (see
`git-hygiene-push-force-safely` for the safety mechanism, and
`github-hygiene-pull-request-mirrors-commit` for re-syncing the PR after the rewrite).

## Deterministic safety net: the `detect-noise-commits.sh` hook

Spotting noise-subject commits is the mechanical half of step 1, so this
skill ships it as a `PreToolUse` hook — `scripts/detect-noise-commits.sh`,
wired in the frontmatter. On any `git push` Bash call, the hook lists the
unpushed commits (`@{push}..HEAD`, falling back to `@{upstream}..HEAD`)
and flags subjects that look like throwaway fixups — `fixup!`/`squash!`
leftovers, "fix typo", "oops", "wip", "actually fix it", "make it
compile", and similar — then emits a non-blocking `systemMessage`
suggesting a squash or amend-forward before the push lands. It never
blocks (always exits 0): squashing is a judgment call, and a commit that
is genuinely a separate concern should stay standalone.

It is silent when there is nothing to push, no upstream is configured
yet, or the subjects are all clean — so it only speaks up when there is
real noise to curate. The decision of *what* to squash, and where to
preserve the lesson, stays with you; the hook only surfaces the
candidates.

Two caveats worth knowing:

- **Skill-frontmatter hooks only fire while the skill is active.** The
  hook registers when this skill is loaded, so it must already be in
  context before the push for it to fire.
- The command resolves the script through `${CLAUDE_SKILL_DIR}`, which
  Claude Code exports for the active skill, so it works regardless of
  the working directory the hook runs in.

## When to apply

- About to push a feature branch (squash noise first).
- Just made a follow-up change to an unpushed commit (amend, don't
  stack).
- About to do `git commit -m "fix typo"` — stop, amend forward instead.
