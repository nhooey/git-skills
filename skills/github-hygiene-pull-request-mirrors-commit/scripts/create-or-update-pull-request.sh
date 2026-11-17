#!/usr/bin/env bash
# Build a pull request's title and body from its commits, and open or
# re-sync the pull request with them. Modes: `render` prints them, `sync`
# (the default) creates or PATCHes the pull request and verifies it,
# `check` reports drift byte for byte. `--help` lists the options and
# exit codes.
#
# The program is the Babashka project beside this script (bb.edn, src/);
# this entry point only finds `bb` and the tools the program runs, and
# runs it. The Nix-built skill and the hooks plugin put them on its PATH
# (script-inputs.nix). Run from a checkout without them, it runs itself
# again through `nix shell`, with them at the revisions the skill
# flake's lock pins; without Nix, it needs them installed.
set -euo pipefail

# Builtins only, so that the message below still shows on a bare PATH.
case ${BASH_SOURCE[0]} in
*/*) here=${BASH_SOURCE[0]%/*} ;;
*) here=. ;;
esac
here=$(cd "$here" && pwd)

# The tools of script-inputs.nix, by the nixpkgs attribute each comes from.
tools=(bb:babashka cmark-gfm:cmark-gfm shfmt:shfmt)
missing=()
for tool in "${tools[@]}"; do
  command -v "${tool%%:*}" >/dev/null 2>&1 || missing+=("nixpkgs#${tool#*:}")
done

if [ "${#missing[@]}" -gt 0 ] && [ -z "${PR_BODY_TOOLS_FROM_NIX:-}" ] &&
  [ -f "$here/../flake.lock" ] && command -v nix >/dev/null 2>&1; then
  PR_BODY_TOOLS_FROM_NIX=1 exec nix shell --inputs-from "$here/.." "${missing[@]}" \
    --command bash "$here/${BASH_SOURCE[0]##*/}" "$@"
fi

if ! command -v bb >/dev/null 2>&1; then
  echo "bb not found: install babashka or use the Nix-installed skill" >&2
  exit 2
fi

exec bb --config "$here/bb.edn" --main pr-body.main "$@"
