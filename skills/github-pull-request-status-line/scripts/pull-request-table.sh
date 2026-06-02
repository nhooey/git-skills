#!/usr/bin/env bash
# Output a set of pull requests as an aligned, one-line-per-PR table:
#
#   <status> <check> <repo>  #<num>  <title>  <url>
#
# <status> is the status-line circle (🟣 merged · 🟢 passed/mergeable ·
# 🟡 checks running · 🔴 a check failed · ⚪ closed/draft); <check> is the
# checks-status icon (✅ passed · 🟠 running · 🔴 failed · ⚫ none). The repo,
# #num, and title columns are padded to the widest value *in this result set*,
# so the table lines up regardless of which PRs are filtered in.
#
# Usage:
#   pull-request-table.sh [--repo OWNER/REPO]... [gh-pr-list-flags...]
#
# --repo may be repeated to span multiple repositories; all other flags are
# forwarded verbatim to `gh pr list` (e.g. --state merged|open|all, --author
# @me, --search, --limit, --label). With no --repo, the current repo is used.
#
# Examples:
#   pull-request-table.sh --state open
#   pull-request-table.sh --repo nhooey/skillspkgs --repo nhooey/skills-git --state merged --limit 20
set -euo pipefail

repos=()
passthrough=()
while [ $# -gt 0 ]; do
  case "$1" in
  --repo) repos+=("$2") && shift 2 ;;
  --repo=*) repos+=("${1#--repo=}") && shift ;;
  *) passthrough+=("$1") && shift ;;
  esac
done
[ ${#repos[@]} -eq 0 ] && repos=("")

# Per-PR -> TSV: status \t check \t num \t title \t url. Classify each rollup
# entry as run/fail/pass (CheckRun via .status/.conclusion, StatusContext via
# .state), then fold to one icon per axis. Single-quoted on purpose — the $names
# are jq variables, not shell.
# shellcheck disable=SC2016
jq_prog='
  .[]
  | ([ (.statusCheckRollup // [])[]
       | if   (.status=="QUEUED" or .status=="IN_PROGRESS" or .status=="PENDING" or .state=="PENDING") then "run"
         elif (.conclusion=="FAILURE" or .conclusion=="ERROR" or .conclusion=="CANCELLED"
               or .conclusion=="TIMED_OUT" or .conclusion=="ACTION_REQUIRED" or .conclusion=="STARTUP_FAILURE"
               or .state=="FAILURE" or .state=="ERROR") then "fail"
         else "pass" end ]) as $cl
  | ($cl | length) as $tot
  | ([ $cl[] | select(. == "fail") ] | length) as $f
  | ([ $cl[] | select(. == "run")  ] | length) as $r
  | (if $tot==0 then "⚫" elif $f>0 then "🔴" elif $r>0 then "🟠" else "✅" end) as $check
  | (if .state=="MERGED" then "🟣"
     elif .state=="CLOSED" then "⚪"
     elif .isDraft then "⚪"
     elif $f>0 then "🔴"
     elif $r>0 then "🟡"
     else "🟢" end) as $status
  | [$status, $check, (.number|tostring), .title, .url] | @tsv
'

# Collect rows across every requested repo, prefixing each with its repo label,
# then align in a single awk pass so column widths span the whole set.
{
  for r in "${repos[@]}"; do
    if [ -n "$r" ]; then
      label=$r
      gh pr list --repo "$r" "${passthrough[@]}" \
        --json number,title,url,state,isDraft,statusCheckRollup --jq "$jq_prog" |
        awk -v repo="$label" 'BEGIN { FS=OFS="\t" } { print repo, $0 }'
    else
      label=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
      gh pr list "${passthrough[@]}" \
        --json number,title,url,state,isDraft,statusCheckRollup --jq "$jq_prog" |
        awk -v repo="$label" 'BEGIN { FS=OFS="\t" } { print repo, $0 }'
    fi
  done
} | awk -F'\t' '
  # fields: 1=repo 2=status 3=check 4=num 5=title 6=url
  {
    n++
    repo[n]=$1; status[n]=$2; check[n]=$3; num[n]="#" $4; title[n]=$5; url[n]=$6
    if (length(repo[n])  > wr) wr=length(repo[n])
    if (length(num[n])   > wn) wn=length(num[n])
    if (length(title[n]) > wt) wt=length(title[n])
  }
  END {
    for (i=1; i<=n; i++)
      printf "%s %s %-*s  %-*s  %-*s  %s\n", \
        status[i], check[i], wr, repo[i], wn, num[i], wt, title[i], url[i]
  }
'
