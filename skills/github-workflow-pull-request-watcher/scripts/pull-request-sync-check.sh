#!/usr/bin/env bash
# PostToolUse hook for Bash. Nudges the agent when an open pull
# request's title or body has drifted from HEAD's commit message
# after a `git commit --amend` or `git push`. Never blocks; always
# exits 0.
#
# Wire this in as a PostToolUse hook with the *literal* install path
# for your scope — a hook command runs outside any agent working
# directory, so a bare filename won't resolve. This matches the
# "Where the bundled scripts install" section of the skill's SKILL.md:
#
#   - user scope:    ~/.claude/skills/github-workflow-pull-request-watcher/scripts/pull-request-sync-check.sh
#   - project scope: <project>/.claude/skills/github-workflow-pull-request-watcher/scripts/pull-request-sync-check.sh
#
#   {
#     "matcher": "Bash",
#     "hooks": [{
#       "type": "command",
#       "command": "bash ~/.claude/skills/github-workflow-pull-request-watcher/scripts/pull-request-sync-check.sh",
#       "timeout": 15
#     }]
#   }
#
# (Claude Code does not set `$CLAUDE_SKILLS_DIR` — if you prefer a
# variable over a literal path, export it yourself first.)
#
# Background: skills/github-hygiene-pull-request-mirrors-commit
# prescribes a PATCH to the pull request after any amend, but skill
# loading is heuristic — this hook is the deterministic safety net.
# Companion to the `github-workflow-pull-request-watcher` Monitor, which
# watches *external* events (CI, comments, merge) post-push; this
# hook catches local title/body drift even before any push.

set -u
export GIT_OPTIONAL_LOCKS=0

payload=$(cat)
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

if [ "$pr_title" = "$commit_subject" ] && [ "$pr_body_norm" = "$commit_body_norm" ]; then
  exit 0
fi

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || exit 0

diff_summary=$(
  {
    if [ "$pr_title" != "$commit_subject" ]; then
      printf 'title:\n  PR:     %s\n  commit: %s\n' "$pr_title" "$commit_subject"
    fi
    if [ "$pr_body_norm" != "$commit_body_norm" ]; then
      printf 'body diff (PR vs commit, first 8 lines):\n'
      diff <(printf '%s\n' "$pr_body") <(printf '%s\n' "$commit_body_raw") | head -n 8
    fi
  }
)

msg=$(
  cat <<EOF
PR #${pr_num} on branch \`${branch}\` is out of sync with HEAD's commit message. Re-sync per \`github-hygiene-pull-request-mirrors-commit\`:

  gh api --method PATCH "/repos/${repo}/pulls/${pr_num}" \\
    -f title="\$(git log -1 --pretty=%s)" \\
    -f body="\$(git log -1 --pretty=%b | fmt -w 2500)"

${diff_summary}
EOF
)

jq -n --arg msg "$msg" '{systemMessage: $msg}'
exit 0
