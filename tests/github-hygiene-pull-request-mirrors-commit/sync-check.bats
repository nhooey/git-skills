#!/usr/bin/env bats
# pull-request-sync-check.sh, the PostToolUse hook, run as Claude Code
# would: a JSON payload on stdin, in a throwaway repository, with an
# environment of its own. PATH holds only the tools the hook and the
# PR body program need and, when a test puts one there, the `gh` stub
# in stubs/: nothing reaches the network. The program,
# create-or-update-pull-request.sh, runs for real.

bats_require_minimum_version 1.5.0

setup() {
  scripts="$BATS_TEST_DIRNAME/../../skills/github-hygiene-pull-request-mirrors-commit/scripts"
  hook="$scripts/pull-request-sync-check.sh"
  bin="$BATS_TEST_TMPDIR/bin"
  subject="Add the widget"
  body="The widget does a thing."
  url="https://github.com/octo/widgets/pull/7"
  export GH_STATE="$BATS_TEST_TMPDIR/gh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CLAUDE_PLUGIN_DATA="$BATS_TEST_TMPDIR/plugin-data"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/repo"
  export GIT_CONFIG_NOSYSTEM=1
  export TMPDIR="$BATS_TEST_TMPDIR"
  mkdir -p "$GH_STATE/issues" "$HOME" "$bin"
  local tool path
  for tool in awk bash cat date diff dirname find git grep head jq mkdir mv rm sed sh tr uname bb cmark-gfm; do
    if path=$(command -v "$tool"); then ln -s "$path" "$bin/$tool"; fi
  done

  # origin/HEAD names the default branch; the hook never fetches, so the
  # refs alone stand in for a remote.
  repo=$CLAUDE_PROJECT_DIR
  git init --quiet --initial-branch main "$repo"
  cd "$repo"
  git config user.name Test
  git config user.email test@example.com
  git commit --quiet --allow-empty --message Start
  git update-ref refs/remotes/origin/main HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git switch --quiet --create feature
  git commit --quiet --allow-empty --message "$subject" --message "$body"
}

# Runs "$@" with only the environment the tests set, and PATH only $bin.
isolated() {
  env -i PATH="$bin" HOME="$HOME" CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" \
    CLAUDE_PLUGIN_DATA="$CLAUDE_PLUGIN_DATA" CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" \
    GH_STATE="$GH_STATE" GIT_CONFIG_NOSYSTEM=1 TMPDIR="$TMPDIR" "$@"
}

# Puts the `gh` stub on PATH. The stub runs under this bash: a sandbox may
# have no /usr/bin/env.
gh_stub() {
  printf '#!%s\nexec %s %q "$@"\n' "$BASH" "$BASH" "$BATS_TEST_DIRNAME/stubs/gh" >"$bin/gh"
  chmod u+x "$bin/gh"
}

# Puts a `gh` on PATH that logs its call and fails, as it does without a
# token.
gh_failing() {
  {
    printf '#!%s\n' "$BASH"
    cat <<'EOF'
printf '%s\n' "$*" >>"$GH_STATE/log"
exit 1
EOF
  } >"$bin/gh"
  chmod u+x "$bin/gh"
}

# The body the PR body program renders for the branch's commits. Its `gh`
# calls go to a state of their own, so the hook's stay countable.
rendered_body() {
  local out
  mkdir -p "$BATS_TEST_TMPDIR/render-gh"
  out=$(GH_STATE="$BATS_TEST_TMPDIR/render-gh" isolated bash "$scripts/create-or-update-pull-request.sh" \
    render --base main --repo octo/widgets) || return
  printf '%s' "${out#*$'\n\n'}"
}

# Opens a pull request for the current branch, number 7 titled $subject
# unless --number or --title say otherwise. Without --body it gets the body
# the PR body program renders, so it starts in sync.
open_pr() {
  local number=7 title=$subject text given=
  while [ "$#" -gt 0 ]; do
    case $1 in
    --number) number=$2 ;;
    --title) title=$2 ;;
    --body) text=$2 given=1 ;;
    esac
    shift 2
  done
  [ -n "$given" ] || text=$(rendered_body)
  jq -n --argjson number "$number" --arg title "$title" --arg body "$text" \
    --arg head "$(git symbolic-ref --short HEAD)" --arg oid "$(git rev-parse HEAD)" \
    '{number: $number, html_url: "https://github.com/octo/widgets/pull/\($number)", title: $title,
      body: $body, head: $head, base: "main", headRefOid: $oid}' >"$GH_STATE/pr.json"
}

# Runs the hook on a Bash call of the command $1 that succeeded, or ended
# as the tool response $4 says, in session $2 (session-1) and directory $3
# (the repository). It must exit 0; its JSON output is in $output.
hook() {
  local payload response=${4:-}
  [ -n "$response" ] || response='{"stdout": "", "stderr": ""}'
  payload=$(jq -n --arg command "$1" --arg session "${2:-session-1}" --arg cwd "${3:-$repo}" \
    --argjson response "$response" \
    '{session_id: $session, hook_event_name: "PostToolUse", tool_name: "Bash",
      tool_input: {command: $command}, tool_response: $response, cwd: $cwd}')
  run --separate-stderr isolated bash "$hook" <<<"$payload"
  [ "$status" -eq 0 ] || {
    echo "$stderr" >&2
    return 1
  }
}

reminder() { jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$output"; }
message() { jq -r '.systemMessage // empty' <<<"$output"; }
gh_calls() { cat "$GH_STATE/log" 2>/dev/null || true; }
gh_writes() { gh_calls | grep -c '^api --method' || true; }

# Commits on main, the default branch, the commit feature has.
on_main() {
  git switch --quiet main
  git commit --quiet --allow-empty --message "$subject" --message "$body"
}

preferences() {
  mkdir -p "$repo/.agents/skills"
  printf '%s\n' "$1" >"$repo/.agents/skills/git-workflow-push-mode.preferences.md"
}

# --- the reminder ----------------------------------------------------------

@test "a push with an open pull request reminds once per session" {
  gh_stub
  open_pr
  hook "git push origin feature"
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = PostToolUse ]
  text=$(reminder)
  [[ $text == *"#7 (octo/widgets)"* ]]
  [[ $text == *"$url"* ]]
  [[ $text == *"pull-request-monitor.sh --pr 7 --repo octo/widgets"* ]]
  [[ ${text,,} == *"unless the user said otherwise"* ]]
  jq -e 'has("systemMessage") | not' <<<"$output"
  hook "git push --force-with-lease"
  [ -z "$output" ]
}

@test "another session, and another pull request, are reminded" {
  gh_stub
  open_pr
  hook "git push"
  [ -n "$(reminder)" ]
  hook "git push" session-2
  [ -n "$(reminder)" ]
  open_pr --number 8
  hook "git push"
  [ -n "$(reminder)" ]
}

@test "an amend alone gives no reminder" {
  gh_stub
  open_pr
  hook "git commit --amend --no-edit"
  [ -z "$output" ]
  [ "$(gh_writes)" -eq 0 ]
}

@test "a failed push gives no reminder" {
  gh_stub
  open_pr
  for response in \
    '{"stdout": "", "stderr": " ! [rejected]        feature -> feature (non-fast-forward)"}' \
    '{"stdout": "", "stderr": "", "interrupted": true}' \
    '{"stdout": "", "stderr": "", "exit_code": 1}'; do
    hook "git push" session-1 "$repo" "$response"
    [ -z "$output" ]
  done
  hook "git push"
  [ -n "$(reminder)" ]
}

# --- silent cases ----------------------------------------------------------

@test "other commands start no gh" {
  gh_stub
  open_pr
  for command in "git status" "ls -la" "git log --oneline" "echo pushed"; do
    hook "$command"
    [ -z "$output" ]
  done
  [ -z "$(gh_calls)" ]
}

@test "outside a repository it is silent" {
  gh_stub
  open_pr
  mkdir "$BATS_TEST_TMPDIR/outside"
  hook "git push" session-1 "$BATS_TEST_TMPDIR/outside"
  [ -z "$output" ]
  [ -z "$(gh_calls)" ]
}

@test "on a detached HEAD it is silent" {
  gh_stub
  open_pr
  git switch --quiet --detach HEAD
  hook "git push origin HEAD:feature"
  [ -z "$output" ]
  [ -z "$(gh_calls)" ]
}

@test "without gh it is silent" {
  hook "git push"
  [ -z "$output" ]
}

@test "with a gh that has no token it is silent" {
  gh_failing
  hook "git push"
  [ -z "$output" ]
  [ "$(gh_calls | wc -l)" -eq 1 ]
}

@test "with no open pull request it is silent" {
  gh_stub
  hook "git push"
  [ -z "$output" ]
  [ "$(gh_calls | wc -l)" -eq 1 ]
}

# --- the default branch and the push mode ----------------------------------

@test "a push to the default branch in direct mode is silent" {
  on_main
  gh_stub
  open_pr
  memory="$CLAUDE_CONFIG_DIR/projects/$(printf '%s' "$repo" | sed 's/[^A-Za-z0-9]/-/g')/memory/push-workflow-mode.md"
  mkdir -p "${memory%/*}"
  preferences "- Mode: 1"
  hook "git push origin main"
  [ -z "$output" ]
  [ -z "$(gh_calls)" ]
  rm "$repo/.agents/skills/git-workflow-push-mode.preferences.md"
  printf -- '---\nname: push-workflow-mode\n---\n\n**Mode:** 1 (direct to main)\n' >"$memory"
  hook "git push origin main"
  [ -z "$output" ]
  [ -z "$(gh_calls)" ]
}

@test "a push to the default branch in pull request mode checks" {
  preferences "- Mode: 2"
  on_main
  gh_stub
  open_pr
  hook "git push"
  [ -n "$(reminder)" ]
}

@test "a push of a branch in direct mode still reminds" {
  preferences "- Mode: 1"
  gh_stub
  open_pr
  hook "git push"
  [ -n "$(reminder)" ]
}

# --- the sync check, beside the reminder -----------------------------------

@test "a drifted title on push is synced" {
  gh_stub
  open_pr --title "Old title"
  hook "git push"
  [[ $(message) == *"Re-synced PR #7 (octo/widgets)"* ]]
  [[ $(message) == *"create-or-update-pull-request.sh"* ]]
  gh_calls | grep -qxF "api --method PATCH repos/octo/widgets/pulls/7 --input -"
  [ "$(jq -r .title "$GH_STATE/pr.json")" = "$subject" ]
  [ -n "$(reminder)" ]
}

@test "a body edited by hand is reported on push, not overwritten" {
  gh_stub
  open_pr --body "Written by a reviewer."
  hook "git push"
  local text
  text=$(message)
  [[ $text == *"holds text its commit message doesn't"* ]]
  [[ $text == *"Fold that text into the commit message"* ]]
  [[ $text == *"--dropped-text-saved"* ]]
  [[ ${text//--force-with-lease/} != *"--force"* ]]
  [ "$(jq -r .body "$GH_STATE/pr.json")" = "Written by a reviewer." ]
}

@test "drift after an amend gives check's diff only" {
  gh_stub
  open_pr
  git commit --quiet --amend --allow-empty --message "$subject" --message "A reworded body."
  hook "git commit --amend -m reworded"
  [[ $(message) == *"no longer matches its commits"* ]]
  [[ $(message) == *"+A reworded body."* ]]
  [ -z "$(reminder)" ]
  [ "$(gh_writes)" -eq 0 ]
}

@test "an added commit is drift" {
  gh_stub
  open_pr
  git commit --quiet --allow-empty --message "fixup! $subject"
  hook "git commit --amend --no-edit"
  [[ $(message) == *"is a fixup! commit"* ]]
}

@test "a rendered body is in sync" {
  gh_stub
  open_pr
  hook "git commit --amend --no-edit"
  [ -z "$output" ]
}

@test "an unwrapped body without the marker is drift" {
  # The old reflow's output: the words match, but there's no marker.
  gh_stub
  open_pr --body "$body"$'\n\n'"🤖 Generated with [Claude Code](https://claude.com/claude-code)"
  hook "git commit --amend --no-edit"
  [[ $(message) == *"no longer matches its commits"* ]]
}
