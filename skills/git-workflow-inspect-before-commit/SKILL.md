---
name: git-workflow-inspect-before-commit
description: |
  Before turning working-tree changes into a commit, walk three steps:
  inspect (`git status` / `git diff`), stage only what belongs (named paths,
  or hunks with `git add -p` for mixed changes), and review the cached diff
  (`git diff --cached`) for secrets, debug logging and unintended formatting
  churn. Ships a non-blocking hook that scans the diff on `git commit`. Use
  whenever about to `git commit`.
tags: [workflow, safety]
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
            for d in "${CLAUDE_PROJECT_DIR:-.}/.claude/skills/git-workflow-inspect-before-commit"
            "$HOME/.claude/skills/git-workflow-inspect-before-commit";
            do [ -f "$d/scripts/inspect-staged-diff.sh" ] && exec bash "$d/scripts/inspect-staged-diff.sh";
            done; echo "git-workflow-inspect-before-commit: scripts/inspect-staged-diff.sh not found" >&2
          timeout: 15
---

# Inspect before committing

_Read the change, stage only what belongs to this commit, then review the staged diff before it lands._

Loading this skill is not a request to commit now; it applies when a commit comes up.

## 1. Inspect before staging

```bash
git status         # what changed
git diff           # what the changes are
git diff --stat    # if the diff is too large to scan inline
```

A stray `console.log`, an editor's format-on-save or a secret is cheap
to undo before staging and expensive after committing.

## 2. Stage only what belongs in this commit

Name the paths: `git add <paths>`. Never stage with `git add -A`,
`git add --all`, `git add .` or `git commit -a`; repos often hold
untracked working files (plans, agent config, scratch notes) that must
stay out of commits. `git-hygiene-avoid-sweeping-operations` covers
this rule for every git command.

When the working tree mixes concerns (refactor and feature, formatting
and logic, tests and production code), stage by hunks:

```bash
git add -p <paths>               # pick hunks to stage
git restore --staged -p <paths>  # pick hunks to unstage
git restore --staged <path>      # unstage a file
```

`-p` prompts for each hunk, so it needs a terminal to answer it. Without
one, write the hunks you want as a patch and stage it with
`git apply --cached <patch>`.

If you can't describe the staged change in one or two sentences (what
and why), the commit is mixed: unstage some hunks and commit them
separately.

## 3. Review what will be committed

```bash
git diff --cached
```

Look for:

- **Secrets and tokens:** hard-coded API keys, `.env` files, `id_rsa`,
  anything with `password=` or `token=` followed by a long random
  string.
- **Debug logging:** `console.log`, `print(...)`, `dbg!`, commented-out
  experiments left over from local poking.
- **Unrelated formatting churn:** a reformatter ran on save and rewrote
  lines you didn't mean to touch. Move the reformat into its own commit
  (step 2) or revert it.

If the repo has a fast check (a typecheck on the staged files, a
unit-test subset, a linter), run it here too. If anything surfaces a
problem, fix it and re-stage before committing.

## The `inspect-staged-diff.sh` hook

The frontmatter wires `scripts/inspect-staged-diff.sh` as a
`PreToolUse` hook for the two pattern-matchable failure modes. On any
Bash call containing `git commit`, it reads the diff about to be
committed (the index, or `git diff HEAD` for a `-a` commit) and scans
the added lines for:

- **Credentials:** private key blocks, `AKIA…` AWS key ids,
  `password`/`secret`/`token`/`api_key` assigned a long literal, and
  `.env` files other than `.env.example`, `.sample`, `.template` and
  `.dist`.
- **Debug logging:** `console.log`, `debugger;`, `binding.pry`,
  `byebug`, `dbg!`, `var_dump(` and similar.

It emits a `systemMessage` listing what it found and never blocks
(always exits 0). Formatting churn is a judgment call, not a regex, so
step 3 still covers it.

- **It fires only while the skill is active.** A skill-frontmatter hook
  registers when the skill is loaded, so the skill must already be in
  context before the commit.
- **It finds the script in the skill's install places:** the project's
  `.claude/skills/`, through `$CLAUDE_PROJECT_DIR`, then
  `~/.claude/skills/`. Claude Code substitutes `${CLAUDE_SKILL_DIR}`
  only in a skill's body and `allowed-tools`, not in its hooks, and a
  hook runs in Claude's current directory, so neither that variable
  nor a relative path finds the script.

## When to apply

- About to stage and commit changes.
- Reviewing your own working tree before pushing.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `git-hygiene-avoid-sweeping-operations`: name the paths a git command acts on, the rule behind staging by path rather than `git add -A`.
