#!/usr/bin/env bash
# Background polling loop for an open pull request. Emits one line per
# delta on check-runs, issue comments, review-thread comments, and PR
# state — then breaks when the PR transitions to MERGED or CLOSED.
#
# Intended to be passed to the `Monitor` tool with `persistent: true`.
#
# Usage:
#   pull-request-monitor.sh [--pr N] [--repo OWNER/REPO] [--sha SHA]
#                           [--interval SECONDS] [--dry-run] [-h|--help]
#
# All flags are optional; defaults are auto-detected from the current
# branch and working tree:
#   --pr        gh pr view --json number   on the current branch
#   --repo      gh repo view --json nameWithOwner
#   --sha       git rev-parse HEAD
#   --interval  30
#
# --dry-run runs each distinct `gh` invocation once with stderr intact
# and exits. Use this before arming the Monitor — a silent failure
# (Unknown JSON field, missing permission, typo) otherwise leaves the
# loop polling forever without emitting events.

set -u
export GIT_OPTIONAL_LOCKS=0

pr=""
repo=""
sha=""
interval=30
dry_run=0

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed -e 's/^# \{0,1\}//' -e '$d'
}

while [ $# -gt 0 ]; do
  case "$1" in
  --pr)
    pr=$2
    shift 2
    ;;
  --repo)
    repo=$2
    shift 2
    ;;
  --sha)
    sha=$2
    shift 2
    ;;
  --interval)
    interval=$2
    shift 2
    ;;
  --dry-run)
    dry_run=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "unknown flag: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [ -z "$repo" ]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || {
    echo "could not auto-detect --repo (gh repo view failed)" >&2
    exit 2
  }
fi

if [ -z "$pr" ]; then
  pr=$(gh pr view --json number --jq .number) || {
    echo "could not auto-detect --pr (no open PR on current branch?)" >&2
    exit 2
  }
fi

if [ -z "$sha" ]; then
  sha=$(git rev-parse HEAD) || {
    echo "could not auto-detect --sha (git rev-parse HEAD failed)" >&2
    exit 2
  }
fi

if [ "$dry_run" -eq 1 ]; then
  # Run each distinct gh invocation once with stderr intact. The point
  # is to surface Unknown-JSON-field / auth / repo-resolution errors
  # *before* arming the Monitor, where 2>/dev/null would swallow them.
  echo "# gh pr view --json state,reviewDecision"
  gh pr view "$pr" --repo "$repo" --json state,reviewDecision
  echo "# gh api repos/$repo/issues/$pr/comments"
  gh api "repos/$repo/issues/$pr/comments"
  echo "# gh api repos/$repo/pulls/$pr/comments"
  gh api "repos/$repo/pulls/$pr/comments"
  echo "# gh api repos/$repo/commits/$sha/check-runs"
  gh api "repos/$repo/commits/$sha/check-runs"
  exit 0
fi

user=$(gh api user --jq .login)
prev_checks=""
max_issue=0
max_review=0
prev_state=""

# Shared jq filter for both comment sources — emits one line per new
# comment, flagging self-comments distinctly.
fmt_comments='.[] | select(.id > $cutoff)
  | "COMMENT-\(if .user.login==$user then "SELF" else .user.login end): \(.body | gsub("\n"; " "))"'

while :; do
  # Check completions — guard against transient empty fetch.
  cur=$(gh api "repos/$repo/commits/$sha/check-runs" 2>/dev/null |
    jq -r '.check_runs[]? | select(.status=="completed") | "\(.name): \(.conclusion)"' | sort)
  if [ -n "$cur" ]; then
    comm -13 <(echo "$prev_checks") <(echo "$cur") | awk 'NF { print "CHECK " $0 }'
    prev_checks=$cur
  fi

  # Issue-level comments (Conversation tab) — fetch once, reuse.
  issue=$(gh api "repos/$repo/issues/$pr/comments" 2>/dev/null)
  if [ -n "$issue" ] && [ "$issue" != "[]" ]; then
    jq -r --arg user "$user" --argjson cutoff "$max_issue" "$fmt_comments" <<<"$issue"
    max_issue=$(jq '[.[].id, 0] | max' <<<"$issue")
  fi

  # Inline review-thread comments (Files Changed tab) — same shape.
  review=$(gh api "repos/$repo/pulls/$pr/comments" 2>/dev/null)
  if [ -n "$review" ] && [ "$review" != "[]" ]; then
    jq -r --arg user "$user" --argjson cutoff "$max_review" "$fmt_comments" <<<"$review"
    max_review=$(jq '[.[].id, 0] | max' <<<"$review")
  fi

  # PR state + review decision.
  state=$(gh pr view "$pr" --repo "$repo" --json state,reviewDecision \
    --jq '"STATE \(.state) REVIEW \(.reviewDecision | if . == null or . == "" then "none" else . end)"' 2>/dev/null)
  if [ -n "$state" ] && [ "$state" != "$prev_state" ]; then
    echo "$state"
    prev_state=$state
  fi
  case "$state" in *MERGED* | *CLOSED*) break ;; esac

  sleep "$interval"
done
