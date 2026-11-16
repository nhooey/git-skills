#!/usr/bin/env bash
# PostToolUse hook for Bash. Nudges the agent when an open pull
# request's title or body has drifted from HEAD's commit message
# after a `git commit --amend` or `git push`. Never blocks; always
# exits 0.
#
# The repository's `git-skills-hooks` plugin (flake package
# `hooks-plugin`) copies this script into its scripts/ and runs it from
# plugin/hooks/hooks.json; see the README's "Hooks plugin" section.
#
# Background: this skill, github-hygiene-pull-request-mirrors-commit,
# prescribes a PATCH to the pull request after any amend, but skill
# loading is heuristic — this hook is the deterministic safety net.
# Companion to the `github-workflow-pull-request-watcher` Monitor, which
# watches *external* events (CI, comments, merge) post-push; this
# hook catches local title/body drift even before any push.

set -u
export GIT_OPTIONAL_LOCKS=0

IFS= read -r -d '' payload || true

# Every session runs this on every Bash call, so the common case (no
# `git commit` or `git push` anywhere in the payload) exits here, on
# builtins alone, before forking jq.
case "$payload" in
*"git commit"* | *"git push"*) ;;
*) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

cmd=$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null) || exit 0
cwd=$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null) || exit 0

case "$cmd" in
*"git commit"*"--amend"*) ;;
*"git push"*) ;;
*) exit 0 ;;
esac

[ -d "$cwd" ] || exit 0
cd "$cwd" || exit 0

branch=$(git symbolic-ref --short -q HEAD) || exit 0
[ -n "$branch" ] || exit 0

command -v gh >/dev/null 2>&1 || exit 0

pr=$(gh pr list --head "$branch" --state open \
  --json number,title,body --jq '.[0] // empty' 2>/dev/null)
[ -n "$pr" ] || exit 0

pr_num=$(jq -r '.number' <<<"$pr")
pr_title=$(jq -r '.title' <<<"$pr")
pr_body=$(jq -r '.body // ""' <<<"$pr" | tr -d '\r')

commit_subject=$(git log -1 --pretty=%s)
commit_body_raw=$(git log -1 --pretty=%b)

# Whitespace-normalised body comparison: kills line-wrap-width
# sensitivity (PR body authored via `fmt -w 2500` vs raw 72-col
# commit body should compare equal if the words are identical).
normalize() { tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//'; }
pr_body_norm=$(printf '%s' "$pr_body" | normalize)
commit_body_norm=$(printf '%s' "$commit_body_raw" | normalize)
# create-or-update-pull-request.sh ends the PR body with a footer
# paragraph the commit doesn't have, so the body also matches when
# only its last paragraph is dropped.
pr_body_sans_footer_norm=$(printf '%s\n' "$pr_body" |
  awk 'BEGIN { RS = "" } { p[NR] = $0 } END { for (i = 1; i < NR; i++) print p[i] "\n" }' |
  normalize)

if [ "$pr_body_norm" = "$commit_body_norm" ] ||
  [ "$pr_body_sans_footer_norm" = "$commit_body_norm" ]; then
  body_in_sync=1
else
  body_in_sync=0
fi

if [ "$pr_title" = "$commit_subject" ] && [ "$body_in_sync" -eq 1 ]; then
  exit 0
fi

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || exit 0

diff_summary=$(
  {
    if [ "$pr_title" != "$commit_subject" ]; then
      printf 'title:\n  PR:     %s\n  commit: %s\n' "$pr_title" "$commit_subject"
    fi
    if [ "$body_in_sync" -eq 0 ]; then
      printf 'body diff (PR vs commit, first 8 lines):\n'
      diff <(printf '%s\n' "$pr_body") <(printf '%s\n' "$commit_body_raw") | head -n 8
    fi
  }
)

msg=$(
  cat <<EOF
PR #${pr_num} (${repo}) on branch \`${branch}\` is out of sync with HEAD's commit message. Re-sync it by running \`create-or-update-pull-request.sh\` from the \`github-hygiene-pull-request-mirrors-commit\` skill on this branch; it PATCHes the open PR's title and body.

${diff_summary}
EOF
)

jq -n --arg msg "$msg" '{systemMessage: $msg}'
exit 0
