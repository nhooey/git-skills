#!/usr/bin/env bash
# Open — or re-sync — a pull request that mirrors the current HEAD commit:
# the PR title is the commit subject and the PR body is the commit body,
# reflowed from 72-col hard wrap to GFM paragraphs. No template, no footer.
#
# Run it to open the PR; run it again after `git commit --amend` (+ force-push)
# and it PATCHes the already-open PR back into line with the reworded commit
# (GitHub never refreshes title/body on its own). It auto-detects which case
# applies from whether an open PR already exists for the head branch.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: create-or-update-pull-request.sh [options]

  --base <branch>      base branch for a new PR (default: repo default)
  --head <branch>      head branch (default: current branch)
  --repo <owner/repo>  target repo (default: current)
  --draft              open as a draft (ignored when re-syncing)
  --verbatim           skip the reflow; send the commit body as-is. Use when
                       the body is already GFM-shaped (blank line after each
                       ## heading, one line per bullet, fenced code blocks).
  -h, --help           show this help

Title is always the commit subject and body the commit body — never a
template. The reflow is an awk paragraph-join: POSIX, no width cap, and never
shadowed the way a dev shell's `fmt`/`nix fmt` command shadows coreutils `fmt`
(which would silently yield an empty body).
EOF
}

base='' head='' repo='' draft='' verbatim=''
while [ $# -gt 0 ]; do
  case "$1" in
  --base) base=$2 && shift 2 ;;
  --head) head=$2 && shift 2 ;;
  --repo) repo=$2 && shift 2 ;;
  --draft) draft=1 && shift ;;
  --verbatim) verbatim=1 && shift ;;
  -h | --help) usage && exit 0 ;;
  *)
    echo "unknown option: $1 (try --help)" >&2
    exit 2
    ;;
  esac
done

reflow() { awk 'BEGIN { RS = ""; ORS = "\n\n" } { gsub(/\n/, " "); print }'; }

title=$(git log -1 --pretty=%s)
if [ -n "$verbatim" ]; then
  body=$(git log -1 --pretty=%b)
else
  body=$(git log -1 --pretty=%b | reflow)
fi

[ -n "$head" ] || head=$(git rev-parse --abbrev-ref HEAD)
# The `gh pr` subcommands below take the repo via the `-R`/`--repo` flag, but
# `gh repo view` takes it as a POSITIONAL arg (it has no `--repo` flag — passing
# one errors `unknown flag: --repo`). Keep the two forms separate.
repo_args=()
[ -n "$repo" ] && repo_args=(--repo "$repo")
repo_pos=()
[ -n "$repo" ] && repo_pos=("$repo")
slug=$(gh repo view "${repo_pos[@]}" --json nameWithOwner --jq .nameWithOwner)

num=$(gh pr list "${repo_args[@]}" --head "$head" --state open --json number --jq '.[0].number // empty')
if [ -n "$num" ]; then
  gh api --method PATCH "repos/$slug/pulls/$num" -f title="$title" -f body="$body" >/dev/null
  action=synced
  url="https://github.com/$slug/pull/$num"
else
  create=(--head "$head" --title "$title" --body "$body")
  [ -n "$base" ] && create+=(--base "$base")
  [ -n "$draft" ] && create+=(--draft)
  url=$(gh pr create "${repo_args[@]}" "${create[@]}")
  num=${url##*/}
  action=created
fi

# Confirm the body actually landed — a reflow that produced nothing (e.g. a
# shadowed `fmt`) would otherwise leave a silently-blank PR.
len=$(gh pr view "$num" "${repo_args[@]}" --json body --jq '.body | length')
printf '%s %s (body: %s chars)\n' "$action" "$url" "$len"
[ "$len" -gt 1 ] || {
  echo "WARNING: PR body is empty — check the commit body / reflow" >&2
  exit 1
}
