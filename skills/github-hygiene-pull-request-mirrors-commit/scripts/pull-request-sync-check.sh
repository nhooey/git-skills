#!/usr/bin/env bash
# PostToolUse hook for Bash. It only adds context: it never blocks and
# always exits 0.
#
# The repository's `git-skills-hooks` plugin (flake package
# `hooks-plugin`) copies this script into its scripts/ and runs it from
# plugin/hooks/hooks.json; see the README's "Hooks plugin" section.
#
# Both of its messages start from one `gh pr list --head <branch>
# --state open` call:
#
# - Sync check: after `git commit --amend` or `git push`, when the
#   open pull request's title or body has drifted from HEAD's commit
#   message, a `systemMessage` saying to re-sync it with
#   `create-or-update-pull-request.sh`, from the same skill as this
#   script, `github-hygiene-pull-request-mirrors-commit`. Skill loading
#   is heuristic; this hook is the deterministic safety net.
# - Watcher reminder: after a `git push` that succeeded, an
#   `additionalContext` naming the pull request and the command that
#   arms `pull-request-monitor.sh` from
#   `github-workflow-pull-request-watcher`. Given once per pull request
#   per session, recorded under `${CLAUDE_PLUGIN_DATA}` by session id
#   (under `$TMPDIR` when no plugin runs it), and not after a push to
#   the default branch in a repository whose push mode
#   (`git-workflow-push-mode`) is direct.

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

# One jq call: whether the command failed, the session id, the working
# directory, and last the command, which may span lines. PostToolUse
# fires only for a Bash call that exited 0, but a non-zero exit code,
# an interrupt, or git's own rejection in stderr still counts as a
# failed push.
fields=$(jq -r '
  (.tool_response as $r
   | if ($r | type) != "object" then "ok"
     elif ($r.interrupted == true) then "failed"
     elif ((($r.exit_code // $r.exitCode // $r.returncode // 0) | tostring) != "0") then "failed"
     elif (($r.stderr // "") | test("\\[rejected\\]|\\[remote rejected\\]|error: failed to push")) then "failed"
     else "ok" end),
  (.session_id // ""),
  (.cwd // ""),
  (.tool_input.command // "")
' <<<"$payload" 2>/dev/null) || exit 0
outcome=${fields%%$'\n'*}
fields=${fields#*$'\n'}
session_id=${fields%%$'\n'*}
fields=${fields#*$'\n'}
cwd=${fields%%$'\n'*}
cmd=${fields#*$'\n'}

is_push=0
is_amend=0
case "$cmd" in *"git push"*) is_push=1 ;; esac
case "$cmd" in *"git commit"*"--amend"*) is_amend=1 ;; esac
[ "$is_push" -eq 1 ] || [ "$is_amend" -eq 1 ] || exit 0

[ -d "$cwd" ] || exit 0
cd "$cwd" || exit 0

branch=$(git symbolic-ref --short -q HEAD) || exit 0
[ -n "$branch" ] || exit 0

# The push mode is kept, first found wins, in the project's and the
# user's `git-workflow-push-mode` preferences files, then in the
# project's auto-memory as `push-workflow-mode.md`. Prints the mode's
# value in lower case, such as `1 (direct to main)`.
push_mode() {
  local project_dir config_dir file value
  project_dir=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
  config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
  for file in \
    "$project_dir/.agents/skills/git-workflow-push-mode.preferences.md" \
    "$config_dir/skills/git-workflow-push-mode.preferences.md" \
    "$config_dir/projects/$(printf '%s' "$project_dir" | sed 's/[^A-Za-z0-9]/-/g')/memory/push-workflow-mode.md"; do
    [ -f "$file" ] || continue
    value=$(awk '{
      l = tolower($0); gsub(/\*/, "", l)
      if (match(l, /^[ \t-]*(push[ -]+)?(workflow[ -]+)?mode[ \t]*:[ \t]*/)) {
        print substr(l, RLENGTH + 1); exit
      }
    }' "$file")
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return
    fi
  done
}

# A push to the default branch in a repository whose push mode is
# direct has no pull request to watch, so it costs no `gh` call.
if [ "$is_amend" -eq 0 ]; then
  default_branch=$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null)
  default_branch=${default_branch#origin/}
  if [ "$branch" = "$default_branch" ]; then
    case "$(push_mode)" in
    1 | 1[!0-9]* | "mode 1"* | direct*) exit 0 ;;
    esac
  fi
fi

command -v gh >/dev/null 2>&1 || exit 0

pr=$(gh pr list --head "$branch" --state open \
  --json number,title,body,url --jq '.[0] // empty' 2>/dev/null)
[ -n "$pr" ] || exit 0

pr_num=$(jq -r '.number' <<<"$pr")
pr_url=$(jq -r '.url // ""' <<<"$pr")
pr_title=$(jq -r '.title' <<<"$pr")
pr_body=$(jq -r '.body // ""' <<<"$pr" | tr -d '\r')
# https://github.com/<owner>/<repo>/pull/<num>
repo=$(printf '%s' "$pr_url" | sed -nE 's|^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*$|\1|p')
pr_label="#${pr_num}${repo:+ ($repo)}"

# --- Watcher reminder ---------------------------------------------------

reminder=
if [ "$is_push" -eq 1 ] && [ "$outcome" = ok ]; then
  record_dir=${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/git-skills-hooks}/pull-request-watcher-reminders
  record=
  if [ -n "$session_id" ]; then
    record="$record_dir/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9._-' '_')"
  fi
  key=${pr_url:-$branch#$pr_num}
  if [ -z "$record" ] || ! grep -qxF -- "$key" "$record" 2>/dev/null; then
    repo_flag=${repo:+ --repo $repo}
    reminder=$(
      cat <<EOF
Pull request ${pr_label} is open for branch \`${branch}\`, which was just pushed${pr_url:+: ${pr_url}}. Unless the user said otherwise, arm its watcher now: dry-run, then start as a background Monitor, \`bash pull-request-monitor.sh --pr ${pr_num}${repo_flag}\` from the \`github-workflow-pull-request-watcher\` skill's scripts/, and react to its events as that skill says.
EOF
    )
    if [ -n "$record" ] && mkdir -p "$record_dir" 2>/dev/null; then
      printf '%s\n' "$key" >>"$record"
      # Session records are a few bytes each; drop the month-old ones.
      find "$record_dir" -type f -mtime +30 -delete 2>/dev/null
    fi
  fi
fi

# --- Sync check ---------------------------------------------------------

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

sync_msg=
if [ "$pr_title" != "$commit_subject" ] || [ "$body_in_sync" -eq 0 ]; then
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
  sync_msg=$(
    cat <<EOF
PR ${pr_label} on branch \`${branch}\` is out of sync with HEAD's commit message. Re-sync it by running \`create-or-update-pull-request.sh\` from the \`github-hygiene-pull-request-mirrors-commit\` skill on this branch; it PATCHes the open PR's title and body.

${diff_summary}
EOF
  )
fi

[ -n "$reminder" ] || [ -n "$sync_msg" ] || exit 0

jq -n --arg sync "$sync_msg" --arg reminder "$reminder" '
  (if $sync != "" then {systemMessage: $sync} else {} end)
  + (if $reminder != "" then
       {hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $reminder}}
     else {} end)
'
exit 0
