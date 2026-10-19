#!/usr/bin/env bash
# PreToolUse hook for Bash. Before a `git push` runs, inspects the
# commits that are about to be pushed (those ahead of the upstream) and
# flags the ones whose subjects look like throwaway noise — "fix typo",
# "oops", "wip", "fixup!"/"squash!" leftovers, etc. — that
# `git-workflow-curate-unpushed` says to squash or amend forward before
# they hit the remote. Emits a non-blocking `systemMessage` nudge; never
# blocks, always exits 0. Squashing is a judgment call (some "fix typo"
# commits are genuinely separate concerns), so the agent decides.
#
# Only fires on unpushed commits, so it is silent once history is clean
# or when there is nothing new to push. Wired as a skill-frontmatter hook
# (see this skill's SKILL.md); resolves via $CLAUDE_SKILL_DIR.

set -u
export GIT_OPTIONAL_LOCKS=0

payload=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

cmd=$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null) || exit 0
cwd=$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null) || exit 0

case "$cmd" in
*"git push"*) ;;
*) exit 0 ;;
esac

[ -d "$cwd" ] && cd "$cwd" 2>/dev/null
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Determine the range of unpushed commits. Prefer @{push} (the branch's
# push destination), fall back to @{upstream}; if neither is configured
# (brand-new branch with no upstream yet) there is nothing to compare
# against, so stay silent rather than scanning all of history.
range=""
if git rev-parse --verify -q '@{push}' >/dev/null 2>&1; then
  range='@{push}..HEAD'
elif git rev-parse --verify -q '@{upstream}' >/dev/null 2>&1; then
  range='@{upstream}..HEAD'
else
  exit 0
fi

subjects=$(git log --format='%s' "$range" 2>/dev/null)
[ -n "$subjects" ] || exit 0

# Noise subject patterns: trial-and-error and self-referential fixups
# that should fold into their parent commit.
noise=$(printf '%s\n' "$subjects" | grep -iE \
  '^(fixup!|squash!|amend!|wip\b|oops|typo|fix typo|temp\b|tmp\b|test\b|asdf|stash|debug\b|revert me|do not merge)|fix(ing)? (the )?(previous|last|prior|above)|actually (fix|work|compile)|(make|made) it (compile|work|build)|more (fixes|tweaks)|minor (fix|tweak)' ||
  true)
[ -n "$noise" ] || exit 0

count=$(printf '%s\n' "$noise" | grep -c .)
listed=$(printf '%s\n' "$noise" | sed 's/^/  - /')

msg=$(
  cat <<EOF
\`git-workflow-curate-unpushed\`: ${count} unpushed commit subject(s) on \`${range}\` look like throwaway noise:

${listed}

Consider squashing these into their parent (or amending forward) before pushing — \`git rebase -i\`, or \`git commit --fixup=<sha>\` + \`git rebase -i --autosquash\`. Preserve any real lesson in the surviving commit's body. This is a nudge, not a block; keep a commit standalone if it is genuinely a separate concern.
EOF
)

jq -n --arg msg "$msg" '{systemMessage: $msg}'
exit 0
