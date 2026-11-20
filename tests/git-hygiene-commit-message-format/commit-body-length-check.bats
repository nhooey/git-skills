#!/usr/bin/env bats
# commit-body-length-check.sh, the PostToolUse hook, run as Claude Code
# would: a JSON payload on stdin, in a throwaway repository, with an
# environment of its own.

setup() {
  hook="$BATS_TEST_DIRNAME/../../skills/git-hygiene-commit-message-format/scripts/commit-body-length-check.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/repo"
  export GIT_CONFIG_NOSYSTEM=1
  mkdir -p "$HOME"
  repo=$CLAUDE_PROJECT_DIR
  git init --quiet --initial-branch main "$repo"
  cd "$repo"
  git config user.name Test
  git config user.email test@example.com
}

# Commits the message on stdin.
commit() {
  git commit --quiet --allow-empty --cleanup=verbatim --file -
}

# Runs the hook after `$1`, a Bash command, with `$2` its exit code.
hook() {
  jq -n --arg cmd "${1:-git commit -F msg}" --arg cwd "$repo" --argjson code "${2:-0}" \
    '{tool_name: "Bash", tool_input: {command: $cmd}, tool_response: {exit_code: $code}, cwd: $cwd}' |
    bash "$hook"
}

# A body of `$1` paragraphs, each of `$2` lines.
paragraphs() {
  local p l
  for ((p = 1; p <= $1; p++)); do
    [ "$p" -gt 1 ] && echo
    for ((l = 1; l <= $2; l++)); do echo "Paragraph $p, line $l."; done
  done
}

prefs() {
  mkdir -p "$1"
  printf '%s\n' "$2" >"$1/git-hygiene-commit-message-format.preferences.md"
}

@test "a body of 4 paragraphs and 25 lines passes" {
  { printf 'Subject\n\n'; paragraphs 4 6; echo extra; } | commit
  run hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a fifth paragraph warns, naming the skill's What to cut list" {
  { printf 'Cut me\n\n'; paragraphs 5 2; } | commit
  run hook
  [ "$status" -eq 0 ]
  sha=$(git rev-parse --short HEAD)
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = PostToolUse ]
  context=$(jq -r .hookSpecificOutput.additionalContext <<<"$output")
  [[ "$context" == *"Commit $sha (\"Cut me\") has a body of 5 paragraphs and 10 lines"* ]]
  [[ "$context" == *'"What to cut"'* ]]
  [[ "$context" == *git-hygiene-commit-message-format* ]]
  [[ "$(jq -r .systemMessage <<<"$output")" == *"What to cut"* ]]
}

@test "a 26th line warns" {
  { printf 'Subject\n\n'; paragraphs 2 13; } | commit
  run hook
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" == *"2 paragraphs and 26 lines"* ]]
}

@test "trailers and Co-Authored-By lines don't count" {
  {
    printf 'Subject\n\n'
    paragraphs 4 6
    printf '\nCo-Authored-By: A <a@example.com>\nSigned-off-by: B <b@example.com>\nRefs: #1\n'
  } | commit
  run hook
  [ -z "$output" ]
  { printf 'Subject\n\n'; paragraphs 4 6; printf 'extra\nCo-Authored-By: A <a@example.com>\n'; } | commit
  run hook
  [ -z "$output" ]
}

@test "a blank line inside a fenced code block doesn't end a paragraph" {
  { printf 'Subject\n\n'; paragraphs 3 1; printf '\n```\na\n\nb\n```\n'; } | commit
  run hook
  [ -z "$output" ]
}

@test "a list with blank lines between its items counts as one paragraph" {
  { printf 'Subject\n\n'; paragraphs 3 1; printf '\n- one\n  wrapped\n\n- two\n\n1. three\n'; } | commit
  run hook
  [ -z "$output" ]
}

@test "the project's preferences set the thresholds, over the user's" {
  prefs "$CLAUDE_CONFIG_DIR/skills" '- Body length warning: 10 paragraphs, 100 lines'
  { printf 'Subject\n\n'; paragraphs 3 1; } | commit
  run hook
  [ -z "$output" ]
  prefs "$repo/.agents/skills" '- **Body length warning:** 2 paragraphs, 12 lines'
  run hook
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" == *"past the 2 paragraphs or 12 lines"* ]]
}

@test "Body length warning: off turns it off" {
  prefs "$repo/.agents/skills" '- Body length warning: off'
  { printf 'Subject\n\n'; paragraphs 9 3; } | commit
  run hook
  [ -z "$output" ]
}

@test "it stays silent for other commands and failed commits" {
  { printf 'Subject\n\n'; paragraphs 9 3; } | commit
  run hook "git status"
  [ -z "$output" ]
  run hook "git commit -F msg" 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a commit with no body passes" {
  printf 'Subject only\n' | commit
  run hook
  [ -z "$output" ]
}
