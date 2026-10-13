#!/usr/bin/env bash
# Detection probe for `git-workflow-push-mode`. Reports the signals that
# inform the push-workflow-mode question — whether the repo has any PR
# history, and the PR/branch state of the current branch — and prints a
# recommended default mode. NOT a hook: which mode applies is a one-time
# user decision saved to project memory, and Mode 3 / anomalous states
# need an interactive prompt. This only gathers the facts the agent uses
# to ask (or to apply a saved mode).
#
# Output: KEY=value lines on stdout, e.g.
#   pr_history=yes|no|unknown
#   branch=<current-branch>|DETACHED
#   open_pr=<number>|none|unknown
#   recommended_mode=1|2
# `unknown` means `gh` was unavailable or the call failed.

set -u
export GIT_OPTIONAL_LOCKS=0

command -v git >/dev/null 2>&1 || {
  echo "pr_history=unknown"
  echo "recommended_mode=2"
  exit 0
}
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "pr_history=unknown"
  echo "recommended_mode=2"
  exit 0
}

branch=$(git symbolic-ref --short -q HEAD 2>/dev/null || echo "DETACHED")
echo "branch=${branch}"

if ! command -v gh >/dev/null 2>&1; then
  echo "pr_history=unknown"
  echo "open_pr=unknown"
  echo "recommended_mode=2" # safer default when we cannot tell
  exit 0
fi

# Has this repo ever had a PR? 0 -> Mode 1 plausible; >=1 -> Mode 2.
history_count=$(gh pr list --state all --limit 1 --json number --jq 'length' 2>/dev/null)
if [ -z "$history_count" ]; then
  echo "pr_history=unknown"
  echo "open_pr=unknown"
  echo "recommended_mode=2"
  exit 0
fi

if [ "$history_count" -ge 1 ]; then
  echo "pr_history=yes"
  recommended=2
else
  echo "pr_history=no"
  recommended=1
fi

# Is there already an open PR for the current branch?
if [ "$branch" != "DETACHED" ]; then
  open_pr=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty' 2>/dev/null)
  echo "open_pr=${open_pr:-none}"
else
  echo "open_pr=none"
fi

echo "recommended_mode=${recommended}"
exit 0
