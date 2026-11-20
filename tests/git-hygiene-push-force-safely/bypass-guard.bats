#!/usr/bin/env bats
# push-hook-bypass-guard.sh, the PreToolUse hook: which Bash commands it
# denies as skipping the pre-push hook, and that it stays silent for the
# rest.

setup() {
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/config" CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/project"
  hook="$BATS_TEST_DIRNAME/../../skills/git-hygiene-push-force-safely/scripts/push-hook-bypass-guard.sh"
}

# Runs the hook on a Bash tool call of the command "$1".
guard() {
  # This bash by its path: one test runs with a PATH that has none.
  run "$BASH" "$hook" < <(jq -n --arg c "$1" --arg cwd "$BATS_TEST_TMPDIR" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $cwd}')
}

denied() {
  guard "$1"
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$output")" = deny ]
  [[ "$(jq -r .hookSpecificOutput.permissionDecisionReason <<<"$output")" == *"skips the pre-push hook"* ]]
}

allowed() {
  guard "$1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--no-verify, and the abbreviations git takes for it, are denied" {
  denied 'git push --no-verify'
  denied 'git push --force-with-lease=feature --no-verify origin feature'
  denied 'git push --no-verif origin feature'
  denied 'git push --no-veri'
  denied 'git -C repo push --no-verify'
  denied 'cd repo && command git push --no-verify origin feature'
  denied '/usr/bin/git push --no-verify'
}

@test "-c core.hooksPath and --config-env are denied" {
  denied 'git -c core.hooksPath=/dev/null push'
  denied 'git -c core.hookspath= push origin feature'
  denied 'git -c CORE.HOOKSPATH push'
  denied 'git -ccore.hooksPath=/tmp push'
  denied 'git -c "$key"=x push'
  denied 'git --config-env=core.hooksPath=HOOKS push'
  denied 'git --config-env core.hooksPath=HOOKS push'
}

@test "GIT_CONFIG_* and GIT_CONFIG_PARAMETERS set on the command are denied" {
  denied "GIT_CONFIG_PARAMETERS=\"'core.hooksPath'='/dev/null'\" git push"
  denied 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null git push'
  denied 'env GIT_CONFIG_GLOBAL=/tmp/cfg git push origin feature'
  denied 'env -u HOME GIT_CONFIG_COUNT=1 git push'
  denied 'export GIT_CONFIG_PARAMETERS=x; git push'
  denied 'GIT_CONFIG_GLOBAL=/tmp/cfg; git push'
}

@test "a nested shell or eval is read too" {
  denied 'bash -c "git push --no-verify"'
  denied "sh -lc 'git -c core.hooksPath=/dev/null push'"
  denied 'eval git push --no-verify'
  denied 'out=$(git push --no-verify 2>&1)'
}

@test "git push -n is --dry-run, not a bypass, and is allowed" {
  allowed 'git push -n origin feature'
  allowed 'git push --dry-run --force-with-lease=feature origin feature'
}

@test "ordinary pushes and other git commands are allowed" {
  allowed 'git push --force-with-lease=feature origin feature'
  allowed 'git push -u origin feature'
  allowed 'git -c user.name=T push origin feature'
  allowed 'git commit --no-verify -m wip'
  allowed 'GIT_CONFIG_GLOBAL=/tmp/cfg git status'
  allowed 'GIT_TRACE=1 git push origin feature'
  allowed 'ls -la'
}

@test "a mention in a quoted string, comment or here-document is allowed" {
  allowed 'git commit -m "Never git push --no-verify"'
  allowed "echo 'git push --no-verify'"
  allowed 'git push origin feature # not --no-verify'
  allowed $'git commit --file - <<\'EOF\'\nSubject\n\ngit push --no-verify skips hooks.\nEOF\ngit push'
}

@test "without shfmt the text is matched instead" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -s "$(command -v jq)" "$BATS_TEST_TMPDIR/bin/jq"
  for tool in tr sort paste sed; do ln -s "$(command -v "$tool")" "$BATS_TEST_TMPDIR/bin/$tool"; done
  PATH="$BATS_TEST_TMPDIR/bin" denied 'git push --no-verify'
  PATH="$BATS_TEST_TMPDIR/bin" allowed 'git push --force-with-lease=feature origin feature'
}

@test "Push guard: remind in the preferences adds context instead of denying" {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills"
  printf -- '- Push guard: remind\n' >"$CLAUDE_CONFIG_DIR/skills/git-hygiene-push-force-safely.preferences.md"
  guard 'git push --no-verify'
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$output")" = null ]
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$output")" == *"skips the pre-push hook"* ]]
}

@test "the project's Push guard: off wins over the user's" {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills" "$CLAUDE_PROJECT_DIR/.agents/skills"
  printf -- '- Push guard: remind\n' >"$CLAUDE_CONFIG_DIR/skills/git-hygiene-push-force-safely.preferences.md"
  printf -- '- **Push guard**: `off`\n' >"$CLAUDE_PROJECT_DIR/.agents/skills/git-hygiene-push-force-safely.preferences.md"
  allowed 'git push --no-verify'
}
