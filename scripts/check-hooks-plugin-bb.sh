#!/usr/bin/env bash
# Checks that a built hooks plugin's write guard finds `bb` with no PATH
# at all: run by this bash with an empty environment, it must deny
# `gh pr create --fill`, which it can only do by running the PR body
# program.
#
# Usage: check-hooks-plugin-bb.sh <plugin-dir>
set -o errexit -o nounset -o pipefail

plugin=$1

decision=$(printf '%s' '{"tool_input":{"command":"gh pr create --fill"}}' |
  env -i "$BASH" "$plugin/scripts/pull-request-write-guard.sh")
case $decision in
*'"permissionDecision":"deny"'*) ;;
*)
  echo "check-hooks-plugin-bb: the plugin's guard found no bb: $decision" >&2
  exit 1
  ;;
esac
