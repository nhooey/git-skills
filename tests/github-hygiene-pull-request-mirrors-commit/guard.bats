#!/usr/bin/env bats
# pull-request-write-guard.sh, the PreToolUse hook: which Bash commands
# it denies, and that it stays silent for the rest.

setup() {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/none" CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/none"
  hook="$BATS_TEST_DIRNAME/../../skills/github-hygiene-pull-request-mirrors-commit/scripts/pull-request-write-guard.sh"
}

# Runs the hook on a Bash tool call of the command "$1".
guard() {
  # cwd outside any repository: the default branch is main or master.
  run bash "$hook" < <(jq -n --arg c "$1" --arg cwd "$BATS_TEST_TMPDIR" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $cwd}')
}

denied() {
  guard "$1"
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$output")" = deny ]
  [[ "$(jq -r .hookSpecificOutput.permissionDecisionReason <<<"$output")" == *"create-or-update-pull-request.sh sync"* ]]
}

allowed() {
  guard "$1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "gh pr create with a body, title or fill flag is denied" {
  denied 'gh pr create --fill'
  denied 'gh pr create --fill-first --base main'
  denied 'gh pr create --title "Fix it" --body "Why."'
  denied 'gh pr create --body-file body.md'
  denied 'gh pr create -df'
  denied 'gh pr create --body=Why.'
  denied 'git push -u origin HEAD && gh pr create --fill'
  denied 'cd repo; GH_REPO=o/r command gh pr create -t Title -b Body'
  denied '/opt/bin/gh pr create --fill'
  denied 'url=$(gh pr create --fill)'
}

@test "gh pr edit with a title or body is denied" {
  denied 'gh pr edit 12 --body "New."'
  denied 'gh pr edit --title New'
  denied 'gh pr edit 12 -F body.md'
}

@test "gh api POST or PATCH to pulls with a title or body is denied" {
  denied 'gh api --method PATCH repos/o/r/pulls/12 -f body=New'
  denied 'gh api -X PATCH /repos/o/r/pulls/12 -f title=New'
  denied 'gh api repos/{owner}/{repo}/pulls -f title=T -f head=x -f base=main'
  denied 'gh api --method POST repos/o/r/pulls --input payload.json'
  denied 'gh api -XPATCH repos/o/r/pulls/12 --raw-field=body=New'
}

@test "a shell started with -c is read too" {
  denied 'bash -c "gh pr create --fill"'
}

@test "commands that only read, or change other fields, are allowed" {
  allowed 'gh pr view 12 --json body'
  allowed 'gh pr create --web'
  allowed 'gh pr edit 12 --add-label bug'
  allowed 'gh pr edit 12 --base main'
  allowed 'gh api repos/o/r/pulls/12'
  allowed 'gh api --method PATCH repos/o/r/pulls/12 -f base=main'
  allowed 'gh api repos/o/r/pulls/12/reviews -f body=LGTM -f event=COMMENT'
  allowed 'gh api --method PATCH repos/o/r/issues/12 -f state=closed'
  allowed 'ls -la'
}

@test "a mention in a quoted string, comment or here-document is allowed" {
  allowed 'git commit -m "Never run gh pr create --fill; use the script"'
  allowed "echo 'gh pr edit 1 --body x'"
  allowed 'ls # gh pr create --fill'
  allowed $'git commit --file - <<\'EOF\'\nSubject\n\ngh pr create --fill copies trailers.\nEOF\ngit push'
  allowed 'bash create-or-update-pull-request.sh sync --base main'
}

@test "the program's own gh calls never reach the hook" {
  # It calls `gh api --method PATCH ... --input -` from its Babashka
  # process; the hook sees only the command the agent typed.
  allowed 'bash ~/.claude/skills/github-hygiene-pull-request-mirrors-commit/scripts/create-or-update-pull-request.sh sync'
}

@test "the denial is a PreToolUse hookSpecificOutput" {
  guard 'gh pr create --fill'
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = PreToolUse ]
  [[ "$(jq -r .hookSpecificOutput.permissionDecisionReason <<<"$output")" == "Blocked gh pr create:"* ]]
}

@test "the preferences turn it down to a reminder, or off" {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$CLAUDE_PROJECT_DIR/.agents/skills"
  prefs=github-hygiene-pull-request-mirrors-commit.preferences.md

  printf -- '- Write guard: remind\n' >"$CLAUDE_CONFIG_DIR/skills/$prefs"
  guard 'gh pr create --fill'
  [ "$(jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"$output")" = none ]
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" == "Blocked gh pr create:"* ]]

  printf -- '- **Write guard:** `off`\n' >"$CLAUDE_PROJECT_DIR/.agents/skills/$prefs"
  allowed 'gh pr create --fill'
}

@test "retargeting onto a branch other than the default one is denied, naming gh stack link" {
  denied 'gh pr edit 12 --base feature'
  denied 'gh pr edit 12 -B feature'
  denied 'gh pr edit 12 --base=feature'
  denied 'gh api -X PATCH repos/o/r/pulls/12 -f base=feature'
  [[ "$(jq -r .hookSpecificOutput.permissionDecisionReason <<<"$output")" == *"gh stack link <bottom> … <top>"* ]]
  allowed 'gh pr edit 12 --base main'
  allowed 'gh pr edit 12 --base master'
}

@test "the default branch comes from the repository at cwd" {
  repo="$BATS_TEST_TMPDIR/repo"
  git init --quiet "$repo"
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
  run bash "$hook" < <(jq -n --arg cwd "$repo" '{tool_input: {command: "gh pr edit 1 --base trunk"}, cwd: $cwd}')
  [ -z "$output" ]
  run bash "$hook" < <(jq -n --arg cwd "$repo" '{tool_input: {command: "gh pr edit 1 --base main"}, cwd: $cwd}')
  [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$output")" = deny ]
}
