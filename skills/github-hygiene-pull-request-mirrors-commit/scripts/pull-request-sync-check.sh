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
# - Sync: `create-or-update-pull-request.sh`, beside this script in
#   `github-hygiene-pull-request-mirrors-commit`, renders the pull
#   request from the branch's commits. After a `git push` that
#   succeeded, the hook runs its `sync` mode and reports a re-sync, a
#   refusal (a body edited by hand) or a failure as a `systemMessage`.
#   After `git commit --amend`, it runs `check --quiet` and, on drift,
#   reports `check`'s diff. Skill loading is heuristic; this hook is the
#   deterministic safety net.
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
# `git push` or `git commit --amend` anywhere in the payload) exits
# here, on builtins alone, before forking jq.
case "$payload" in
*"git push"* | *"git commit"*"--amend"*) ;;
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
# Compromise: plan node move-sync-check-hook-parsing-into-the-program
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
  --json number,url --jq '.[0] // empty' 2>/dev/null)
[ -n "$pr" ] || exit 0

pr_num=$(jq -r '.number' <<<"$pr")
pr_url=$(jq -r '.url // ""' <<<"$pr")
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

# The generator compares byte for byte against the render of every
# commit on the branch, not only HEAD, so an added commit or a lost
# line break counts as drift, as does a pull request on a branch other
# than the default one that isn't in a linked GitHub stack; `sync`
# links it. Its exit codes: 0 in sync or synced, 1 drift or a failed
# sync, 2 usage or a refused range, 3 a body edited
# by hand, 4 several commits without an allowed reason.
generator=${BASH_SOURCE[0]%/*}/create-or-update-pull-request.sh
tool='`create-or-update-pull-request.sh` from `github-hygiene-pull-request-mirrors-commit`'
generator_args=(--head "$branch")
[ -n "$repo" ] && generator_args+=(--repo "$repo")

sync_msg=
if [ -f "$generator" ] && [ "$is_push" -eq 1 ] && [ "$outcome" = ok ]; then
  out=$(bash "$generator" sync "${generator_args[@]}" 2>&1)
  rc=$?
  case $rc in
  0)
    case "$out" in
    *"synced "*) sync_msg="Re-synced PR ${pr_label}'s title and body with the commits on \`${branch}\`, by running ${tool} in sync mode." ;;
    esac
    case "$out" in
    *"linked stack: "*) sync_msg="${sync_msg:+$sync_msg }Linked PR ${pr_label} into a GitHub stack: ${out##*linked stack: }." ;;
    esac
    ;;
  3) sync_msg="PR ${pr_label}'s body was edited by hand, so ${tool} didn't overwrite it after this push. Fold the edit into the commit message and run its sync mode again, or rerun it with --force to discard the edit."$'\n\n'"$out" ;;
  *) sync_msg="Syncing PR ${pr_label} with the commits on \`${branch}\` after this push failed (exit ${rc} from ${tool}):"$'\n\n'"$out" ;;
  esac
elif [ -f "$generator" ] && [ "$is_amend" -eq 1 ]; then
  if ! bash "$generator" check --quiet "${generator_args[@]}" >/dev/null 2>&1; then
    out=$(bash "$generator" check "${generator_args[@]}" 2>&1)
    sync_msg="PR ${pr_label} on branch \`${branch}\` no longer matches its commits, or isn't linked into its stack. Push, then re-sync it by running ${tool} in sync mode, which links the stack too."$'\n\n'"$out"
  fi
fi

[ -n "$reminder" ] || [ -n "$sync_msg" ] || exit 0

jq -n --arg sync "$sync_msg" --arg reminder "$reminder" '
  (if $sync != "" then {systemMessage: $sync} else {} end)
  + (if $reminder != "" then
       {hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $reminder}}
     else {} end)
'
exit 0
