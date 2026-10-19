#!/usr/bin/env bash
# Save a new issue or PR body only if nobody has edited the live body since
# the copy your draft started from. GitHub has no compare-and-swap for
# bodies: `gh issue edit --body-file`, `gh pr edit --body-file` and a REST
# PATCH all replace the whole text, so an edit someone else made after you
# fetched it is lost without warning.
#
# If the live body still equals BASE, it PATCHes NEW and exits 0. Otherwise
# it prints what changed, three-way merges those changes into NEW.merged with
# `git merge-file`, saves nothing and exits 1: review NEW.merged, then rerun
# with the printed live copy as BASE and NEW.merged as NEW.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: safe-body-edit.sh <owner/repo> <number> <base-file> <new-file>

  <number>     an issue or PR number (the issues endpoint serves both)
  <base-file>  the body your draft started from, as fetched with
               gh api repos/<owner/repo>/issues/<number> --jq .body
  <new-file>   your draft
EOF
}

[ $# -eq 4 ] || {
  usage
  exit 2
}
repo=$1 num=$2 base=$3 new=$4

live=$(mktemp "${TMPDIR:-/tmp}/body-live.XXXXXX")
# Bodies edited in the browser come back with CRLF line ends
gh api "repos/$repo/issues/$num" --jq .body | tr -d '\r' >"$live"

# -B: `--jq` adds a trailing newline the stored body may not have
if diff -q -B "$base" "$live" >/dev/null; then
  gh api --method PATCH "repos/$repo/issues/$num" -f body="$(cat "$new")" >/dev/null
  echo "saved: the live body was unchanged since $base"
  exit 0
fi

echo "the live body changed since $base:"
diff "$base" "$live" || true
cp "$new" "$new.merged"
if git merge-file -L draft -L base -L live "$new.merged" "$base" "$live"; then
  echo "merged cleanly into $new.merged; nothing saved"
else
  echo "conflicts in $new.merged; resolve them; nothing saved"
fi
echo "then rerun: safe-body-edit.sh $repo $num $live $new.merged"
exit 1
