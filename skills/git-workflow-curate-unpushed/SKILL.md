---
name: git-workflow-curate-unpushed
description: |
  Curate local history before pushing: squash noise commits ("fix typo",
  "oops", trial-and-error iterations) into their parent, and amend forward
  into existing unpushed commits rather than stacking "fix the previous
  commit" commits, keeping any real lesson in a commit body or code
  comment. Ships a non-blocking hook that lists noise subjects on `git
  push`. Use before pushing a feature branch, and when making a follow-up
  change to an unpushed commit.
tags: [workflow, style]
allowed-tools:
  - Bash
  - Read
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          # ${CLAUDE_SKILL_DIR} isn't substituted in hooks, so try the
          # skill's install places in turn: the project's, then the user's.
          command: >-
            for d in "${CLAUDE_PROJECT_DIR:-.}/.claude/skills/git-workflow-curate-unpushed"
            "$HOME/.claude/skills/git-workflow-curate-unpushed";
            do [ -f "$d/scripts/detect-noise-commits.sh" ] && exec bash "$d/scripts/detect-noise-commits.sh";
            done; echo "git-workflow-curate-unpushed: scripts/detect-noise-commits.sh not found" >&2
          timeout: 15
---

# Curate unpushed commits

_Before work reaches the remote, each commit is one coherent change: noise folds into its parent, follow-ups amend forward, and the lessons survive in the message or the code._

Loading this skill is not a request to rewrite history now; it applies when you make a follow-up change to unpushed work or are about to push.

## 1. Squash noise before pushing

Before pushing a feature branch, review your local commits.
Anything that is just "fix typo", "oops", "actually make it compile", or several commits of trial-and-error on the same function is noise: squash it into the parent commit by marking it `fixup` (or `squash`, to edit the message) in `git rebase -i <base>`.
Without an editor to drive, set `GIT_SEQUENCE_EDITOR` to a `sed` command that rewrites those `pick` lines.

Keep the lessons.
If you hit a real landmine (an undocumented API quirk, a footgun in the framework, a subtle ordering requirement), put it where it belongs:

- **Commit message body:** when the lesson explains why this commit looks the way it does.
  ("Tried passing the buffer directly first; the C API silently truncates above 4 KiB, so we chunk.")
- **Code comment:** when the constraint affects future edits.
  ("Must flush before close; the driver drops the last page otherwise.")

## 2. Amend forward into existing unpushed commits

When you change code you already touched in a local, unpushed commit, fold the change into that commit rather than stacking a new "fix the previous commit" commit on top, so the history reads as one change per concern.

- Most recent commit: stage the change, then `git commit --amend`.
- Older unpushed commit: `git commit --fixup=<sha>`, then `git rebase --autosquash <base>`.
  From Git 2.44 `--autosquash` works without `-i`, so no editor is needed; older Git ignores it without `-i` and squashes nothing, so there run `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash <base>`, which applies the fixups without opening an editor.

If the follow-up is a different concern (different intent, different reviewer mental model), keep it as its own commit.
The rule is about self-referential noise, not about cramming unrelated work together.

Once a commit has been pushed and others may have pulled it, rewriting it is a coordination problem: see `git-hygiene-push-force-safely` for the lease, and `github-hygiene-pull-request-mirrors-commit` for re-syncing the PR after the rewrite.

## The `detect-noise-commits.sh` hook

The frontmatter wires `scripts/detect-noise-commits.sh` as a `PreToolUse` hook.
On any Bash call containing `git push`, it lists the unpushed commits (`@{push}..HEAD`, falling back to `@{upstream}..HEAD`) and flags subjects that look like throwaway fixups: `fixup!`, `squash!` and `amend!` leftovers, "fix typo", "oops", "wip", "actually fix it", "make it compile" and similar.
It then emits a `systemMessage` suggesting a squash or amend-forward.
It never blocks (always exits 0): what to squash, and where the lesson goes, stays your call.

It is silent when there is nothing to push, no upstream is configured yet, or every subject is clean.

- **It fires only while the skill is active.** A skill-frontmatter hook registers when the skill is loaded, so the skill must already be in context before the push.
- **It finds the script in the skill's install places:** the project's `.claude/skills/`, through `$CLAUDE_PROJECT_DIR`, then `~/.claude/skills/`.
  Claude Code substitutes `${CLAUDE_SKILL_DIR}` only in a skill's body and `allowed-tools`, not in its hooks, and a hook runs in Claude's current directory, so neither that variable nor a relative path finds the script.

## When to apply

- About to push a feature branch: squash noise first.
- Just made a follow-up change to an unpushed commit: amend, don't stack.
- About to run `git commit -m "fix typo"`: amend forward instead.

## Related skills

When one of these applies and it's in your skill listing, load it without asking.
If it isn't in your listing, tell the user which skill is missing and ask whether to install it from the same collection this skill came from; don't apply it from memory.

- `git-hygiene-push-force-safely`: push with `--force-with-lease` when curating rewrites commits that were already pushed.
- `github-hygiene-pull-request-mirrors-commit`: re-sync an open PR's title and body after a rewrite changes the commit message.
