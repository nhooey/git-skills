#!/usr/bin/env bash
# Detection helper for `git-workflow-cleanup-merged-branches`. Prints the
# local and remote branches already merged into the base branch, ready to
# feed into the AskUserQuestion prompt. NOT a hook: deleting a branch
# needs the user's per-branch confirmation (some teams keep merged
# branches as release markers), so this only *reports*; it never deletes.
#
# Usage:
#   detect-merged-branches.sh [base-branch]
# If base-branch is omitted, it is inferred from origin/HEAD, falling back
# to main, then master.
#
# Output: two TSV-ish sections on stdout —
#   LOCAL\t<branch>
#   REMOTE\torigin/<branch>
# one line per merged branch, with the current branch and the base branch
# itself excluded. Empty output means nothing to clean up.

set -u
export GIT_OPTIONAL_LOCKS=0

command -v git >/dev/null 2>&1 || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

base="${1:-}"
if [ -z "$base" ]; then
  base=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  if [ -z "$base" ]; then
    if git show-ref -q --verify refs/heads/main; then
      base=main
    elif git show-ref -q --verify refs/heads/master; then
      base=master
    else
      echo "could not infer base branch; pass it as the first argument" >&2
      exit 1
    fi
  fi
fi

# Drop tracking refs whose remote branch is gone, so the remote list below
# reflects reality.
git fetch --prune origin >/dev/null 2>&1 || true

current=$(git symbolic-ref --short -q HEAD 2>/dev/null || true)

# Local branches merged into base, minus the base and the current branch.
git branch --merged "$base" --format='%(refname:short)' 2>/dev/null |
  grep -vxE "${base}|main|master|${current:-$base}" |
  while IFS= read -r b; do
    [ -n "$b" ] && printf 'LOCAL\t%s\n' "$b"
  done

# Remote branches merged into origin/base, minus origin/HEAD and the base.
git branch -r --merged "origin/${base}" --format='%(refname:short)' 2>/dev/null |
  grep -vE 'origin/HEAD' |
  grep -vxE "origin/(${base}|main|master)" |
  while IFS= read -r b; do
    [ -n "$b" ] && printf 'REMOTE\t%s\n' "$b"
  done

exit 0
