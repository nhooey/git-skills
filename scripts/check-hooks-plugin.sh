#!/usr/bin/env bash
# Checks a built hooks plugin: its manifest names it, hooks/hooks.json has
# the shape Claude Code reads, every command runs a script the plugin
# holds, and every Bash hook exits 0 with no output for a command it
# doesn't act on.
#
# Usage: check-hooks-plugin.sh <plugin-dir> <expected-plugin-name>
set -euo pipefail

plugin=$1
expected_name=$2
manifest="$plugin/.claude-plugin/plugin.json"
hooks="$plugin/hooks/hooks.json"

fail() {
  printf 'check-hooks-plugin: %s\n' "$*" >&2
  exit 1
}

[ -f "$manifest" ] || fail "missing $manifest"
[ -f "$hooks" ] || fail "missing $hooks"

name=$(jq -er '.name' "$manifest") || fail "plugin.json has no name"
[ "$name" = "$expected_name" ] || fail "plugin.json names '$name', expected '$expected_name'"
jq -e '.version | type == "string"' "$manifest" >/dev/null || fail "plugin.json has no version"

# Every event maps to a list of { matcher?, hooks: [ { type: "command",
# command, timeout? } ] }, under a known event name: the names in Claude
# Code's `HookInput['hook_event_name']`.
jq -e '
  def known: [
    "PreToolUse", "PostToolUse", "PostToolUseFailure", "PostToolBatch",
    "PermissionDenied", "Notification", "UserPromptSubmit",
    "UserPromptExpansion", "SessionStart", "SessionEnd", "Stop",
    "StopFailure", "SubagentStart", "SubagentStop", "PreCompact",
    "PostCompact", "PreModelSwitch", "PostModelSwitch", "PermissionRequest",
    "Setup", "TeammateIdle", "TaskCreated", "TaskCompleted", "Elicitation",
    "ElicitationResult", "ConfigChange", "InstructionsLoaded",
    "WorktreeCreate", "WorktreeRemove", "CwdChanged", "FileChanged",
    "DirectoryAdded", "MessageDisplay"
  ];
  (.hooks | type == "object")
  and (.hooks | keys | all(. as $k | known | index($k)))
  and ([.hooks[][]] | all(
    (.matcher == null or (.matcher | type == "string"))
    and (.hooks | type == "array" and length > 0)
    and (.hooks | all(
      .type == "command"
      and (.command | type == "string")
      and (.timeout == null or (.timeout | type == "number"))
    ))
  ))
' "$hooks" >/dev/null || fail "hooks/hooks.json doesn't have the shape of a hooks file"

# Each command is `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>"`, and the
# plugin holds that script.
while IFS= read -r command; do
  # shellcheck disable=SC2016 # the variable is matched literally
  case "$command" in
  'bash "${CLAUDE_PLUGIN_ROOT}/scripts/'*'"') ;;
  *) fail "command doesn't run a plugin script with bash: $command" ;;
  esac
  script=${command#'bash "${CLAUDE_PLUGIN_ROOT}/'}
  script=${script%'"'}
  [ -f "$plugin/$script" ] || fail "command runs $script, which the plugin doesn't hold"
  bash -n "$plugin/$script" || fail "$script doesn't parse"
done < <(jq -r '.hooks[][].hooks[].command' "$hooks")

# A Bash hook must stay silent and exit at once for a command it doesn't
# act on: every session runs it on every Bash call.
payload='{"tool_name":"Bash","tool_input":{"command":"ls -la"},"cwd":"/"}'
while IFS= read -r script; do
  out=$(CLAUDE_PLUGIN_ROOT=$plugin bash "$plugin/$script" <<<"$payload") ||
    fail "$script exited non-zero for an unrelated Bash command"
  [ -z "$out" ] || fail "$script printed output for an unrelated Bash command: $out"
done < <(
  jq -r '
    .hooks | to_entries[]
    | select(.key == "PreToolUse" or .key == "PostToolUse")
    | .value[] | select(.matcher == "Bash") | .hooks[].command
  ' "$hooks" |
    sed -e 's|^bash "${CLAUDE_PLUGIN_ROOT}/||' -e 's|"$||'
)

printf 'check-hooks-plugin: %s ok\n' "$name"
