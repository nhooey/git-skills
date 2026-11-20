#!/usr/bin/env bash
# PostToolUse hook for Bash: after a `git commit` that succeeded, reads
# the new commit's message with `git log -1` and warns when its body
# runs past the length the `git-hygiene-commit-message-format` skill
# caps it at: 4 paragraphs or 25 lines by default. It only adds
# context: it never blocks and always exits 0.
#
# The repository's `git-skills-hooks` plugin (flake package
# `hooks-plugin`) copies this script into its scripts/ and runs it from
# plugin/hooks/hooks.json; see the README's "Hooks plugin" section.
#
# What counts:
#
# - the body is the message after the subject's paragraph;
# - a closing block of trailers (`Key: value` lines) and any
#   `Co-Authored-By:` line count for nothing;
# - a paragraph is a run of non-blank lines; a blank line inside a
#   fenced code block doesn't end one, and list blocks parted by blank
#   lines count as one paragraph together;
# - a line is a non-blank line of the body.
#
# The thresholds come from the skill's preferences files, the last
# found winning: beside the installed skill, the user's under
# `${CLAUDE_CONFIG_DIR:-~/.claude}/skills/`, then the project's under
# `.agents/skills/`. `- Body length warning: 4 paragraphs, 25 lines`
# sets them, and `- Body length warning: off` turns the warning off.

set -u
export GIT_OPTIONAL_LOCKS=0

IFS= read -r -d '' payload || true

# Every session runs this on every Bash call, so the common case exits
# here, on builtins alone, before forking jq.
case "$payload" in
*"git commit"*) ;;
*) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

# One jq call: whether the command failed, the working directory, and
# last the command, which may span lines.
fields=$(jq -r '
  (.tool_response as $r
   | if ($r | type) != "object" then "ok"
     elif ($r.interrupted == true) then "failed"
     elif ((($r.exit_code // $r.exitCode // $r.returncode // 0) | tostring) != "0") then "failed"
     else "ok" end),
  (.cwd // ""),
  (.tool_input.command // "")
' <<<"$payload" 2>/dev/null) || exit 0
outcome=${fields%%$'\n'*}
fields=${fields#*$'\n'}
cwd=${fields%%$'\n'*}
cmd=${fields#*$'\n'}

case "$cmd" in *"git commit"*) ;; *) exit 0 ;; esac
[ "$outcome" = ok ] || exit 0
[ -d "$cwd" ] || exit 0
cd "$cwd" || exit 0

skill=git-hygiene-commit-message-format

# The `Body length warning` value of the last preferences file that
# sets it, in lower case, or nothing.
setting() {
  local here project_dir config_dir file value found=
  case ${BASH_SOURCE[0]} in
  */*) here=${BASH_SOURCE[0]%/*} ;;
  *) here=. ;;
  esac
  project_dir=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}
  config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
  for file in \
    "$here/../../$skill.preferences.md" \
    "$config_dir/skills/$skill.preferences.md" \
    "$project_dir/.agents/skills/$skill.preferences.md"; do
    [ -f "$file" ] || continue
    value=$(awk '{
      l = tolower($0); gsub(/[*`]/, "", l)
      if (match(l, /^[ \t]*[-*+][ \t]+body[ \t]+length[ \t]+warning[ \t]*:[ \t]*/)) {
        print substr(l, RLENGTH + 1); exit
      }
    }' "$file")
    [ -n "$value" ] && found=$value
  done
  printf '%s\n' "$found"
}

value=$(setting)
case "$value" in off*) exit 0 ;; esac
max_paragraphs=$(sed -nE 's/^(.*[^0-9])?([0-9]+)[ \t]*paragraph.*/\2/p' <<<"$value")
max_lines=$(sed -nE 's/^(.*[^0-9])?([0-9]+)[ \t]*line.*/\2/p' <<<"$value")
: "${max_paragraphs:=4}" "${max_lines:=25}"

message=$(git log -1 --format=%B 2>/dev/null) || exit 0
subject=$(git log -1 --format=%s 2>/dev/null)
sha=$(git rev-parse --short HEAD 2>/dev/null)

# "<paragraphs> <lines>" of the body, as the header says.
counts=$(awk '
  function blank(s) { return s ~ /^[ \t]*$/ }
  { line[NR] = $0 }
  END {
    i = 1
    while (i <= NR && !blank(line[i])) i++
    while (i <= NR && blank(line[i])) i++
    n = NR
    while (n >= i && blank(line[n])) n--
    j = n
    while (j >= i && !blank(line[j])) j--
    trailers = (j < n)
    for (k = j + 1; k <= n; k++)
      if (line[k] !~ /^[A-Za-z0-9][A-Za-z0-9-]*:[ \t]/ && !(k > j + 1 && line[k] ~ /^[ \t]+[^ \t]/)) trailers = 0
    if (trailers) n = j
    paragraphs = 0; lines = 0; fence = 0; prev_blank = 1; prev_list = 0
    for (k = i; k <= n; k++) {
      if (tolower(line[k]) ~ /^[ \t]*co-authored-by:/) continue
      if (blank(line[k]) && !fence) { prev_blank = 1; continue }
      if (!blank(line[k])) lines++
      if (prev_blank) {
        is_list = (line[k] ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/ || line[k] ~ /^[ \t]+[^ \t]/)
        if (!(is_list && prev_list)) paragraphs++
        prev_list = is_list
        prev_blank = 0
      }
      if (line[k] ~ /^[ \t]*(```|~~~)/) fence = !fence
    }
    print paragraphs, lines
  }
' <<<"$message")
paragraphs=${counts%% *}
lines=${counts##* }

[ "$paragraphs" -gt "$max_paragraphs" ] || [ "$lines" -gt "$max_lines" ] || exit 0

context="Commit ${sha} (\"${subject}\") has a body of ${paragraphs} paragraphs and ${lines} lines, past the ${max_paragraphs} paragraphs or ${max_lines} lines that \`${skill}\` caps a body at. Cut it with that skill's \"What to cut\" list (diff paraphrase, audit or alternatives walkthrough, test inventory, while-here paragraph, cross-paragraph echo, sub-claim stacking, narration filler), or split the commit, then amend it. Trailers and Co-Authored-By lines don't count."

jq -n --arg context "$context" --arg brief "Commit ${sha}'s body runs ${paragraphs} paragraphs and ${lines} lines, past ${max_paragraphs} paragraphs or ${max_lines} lines: see \"What to cut\" in ${skill}." '
  {systemMessage: $brief,
   hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}}
'
exit 0
