#!/usr/bin/env bash
# PreToolUse hook for Bash: denies a command that writes a pull
# request's title or body by hand (`gh pr create` or `gh pr edit` with
# --body, --body-file, --fill, --fill-first or --title, or `gh api`
# POST or PATCH to a `pulls` endpoint with a title or body), naming
# create-or-update-pull-request.sh, beside this script, instead. It also
# denies retargeting a pull request onto a branch other than the
# default one (`gh pr edit --base`, or `gh api` with a `base` field),
# naming `gh stack link`: such a pull request belongs in a linked stack.
#
# The repository's `git-skills-hooks` plugin (flake package
# `hooks-plugin`) copies this script into its scripts/ and runs it from
# plugin/hooks/hooks.json. The decision is made by `pr-body.guard` in
# src/, which reads the command line's syntax tree from `shfmt
# --to-json`; this script only gates on builtins and starts it.
#
# create-or-update-pull-request.sh calls `gh api` from inside its own
# process, which this hook never sees, so it passes without a marker.
# Without `bb` or `shfmt` the hook allows everything.

set -u

IFS= read -r -d '' payload || true

# Every session runs this on every Bash call, so the common case exits
# here, on builtins alone.
case "$payload" in
*gh*" pr "* | *gh*" api "*) ;;
*) exit 0 ;;
esac

case ${BASH_SOURCE[0]} in
*/*) here=${BASH_SOURCE[0]%/*} ;;
*) here=. ;;
esac

here=$(cd "$here" && pwd) || exit 0
command -v bb >/dev/null 2>&1 || exit 0
bb --config "$here/bb.edn" --main pr-body.guard "$here/create-or-update-pull-request.sh" <<<"$payload" || true
