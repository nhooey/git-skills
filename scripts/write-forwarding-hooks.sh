#!/usr/bin/env bash
# Writes the git-hygiene-push-force-safely hooks folder, for a global
# `core.hooksPath`: its `pre-push` and `forward-hook`, and for every other
# hook git documents a script that runs `forward-hook` with its name, so a
# repository's own hooks still run.
#
# Usage: write-forwarding-hooks.sh <scripts> <out> [githooks-man-page]
#
# - scripts: the skill's scripts/ folder.
# - out: the folder to write, created if missing.
# - githooks-man-page: githooks(5), gzipped or not, whose HOOKS section
#   names one hook per subsection; by default the one of the git on PATH.
#
# The flake's `git-push-force-safely-hooks` package runs it with the
# nixpkgs git's man page.
set -o errexit -o nounset -o pipefail

scripts=$1
out=$2
man_page=${3:-$(git --man-path)/man5/githooks.5.gz}

names=$(
  gzip --decompress --stdout --force "$man_page" |
    sed -n '/^\.SH "HOOKS"/,/^\.SH /s/^\.SS "\(.*\)"$/\1/p' |
    sed 's/\\-/-/g'
)
if ! grep --quiet --line-regexp pre-push <<<"$names"; then
  echo "write-forwarding-hooks: no pre-push hook listed in $man_page" >&2
  exit 1
fi

mkdir -p "$out"
cp "$scripts/pre-push" "$scripts/forward-hook" "$out/"
while IFS= read -r name; do
  [ "$name" = pre-push ] && continue
  # shellcheck disable=SC2016 # the hook expands $0 and $@ when it runs
  printf '#!/bin/sh\nexec "$(dirname "$0")/forward-hook" %s "$@"\n' "$name" >"$out/$name"
done <<<"$names"
chmod u+x,go+rx "$out"/*
