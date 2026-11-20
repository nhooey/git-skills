#!/usr/bin/env bash
# PreToolUse hook for Bash: denies a `git push` that would skip the
# pre-push hook, the one that keeps force pushes off default branches:
#
# - `--no-verify`, or an abbreviation git takes for it;
# - `git -c core.hooksPath=…`, or any `git --config-env`;
# - a GIT_CONFIG_* variable, GIT_CONFIG_PARAMETERS among them, set on the
#   command, through `env`, or by `export` or an assignment anywhere in
#   the same command line.
#
# `git push -n` is `--dry-run` and passes, as does everything else.
#
# The command line is parsed by `shfmt --to-json` and read with `jq`, so a
# commit message, comment or here-document that only mentions
# `--no-verify` passes; `bash -c`, `sh -c` and `eval` strings are read
# too. When either tool is missing or the line doesn't parse, it falls
# back to matching the text: a line naming git, push and a bypass is
# denied.
#
# `- Push guard: deny|remind|off` in the skill's preferences file turns it
# down: `remind` lets the command run and adds the message as context,
# `off` says nothing. The files read are
# `${CLAUDE_CONFIG_DIR:-~/.claude}/skills/git-hygiene-push-force-safely.preferences.md`
# then `.agents/skills/git-hygiene-push-force-safely.preferences.md` under
# CLAUDE_PROJECT_DIR, or else the payload's cwd; the last item wins.
#
# The repository's `git-skills-hooks` plugin (flake package
# `hooks-plugin`) copies this script into its scripts/ and runs it from
# plugin/hooks/hooks.json.

set -u

skill=git-hygiene-push-force-safely

IFS= read -r -d '' payload || true

# Every session runs this on every Bash call, so the common case exits
# here, on builtins alone.
case "$payload" in
*push*) ;;
*) exit 0 ;;
esac

have() { command -v "$1" >/dev/null 2>&1; }

# The jq program: from shfmt's syntax tree of a command line, one line
# per bypass of a git push in it ("bypass <what>"), and one per string
# a nested shell or eval runs ("script <base64>").
read -r -d '' program <<'JQ'
def wtext: [.Parts[]? |
  if .Type == "Lit" or .Type == "SglQuoted" then .Value
  elif .Type == "DblQuoted" then
    ([.Parts[]? | if .Type == "Lit" then .Value else "$" end] | join(""))
  else "$" end] | join("");
def base: split("/") | last;
def assigned: select(test("^[A-Za-z_][A-Za-z0-9_]*=")) | split("=")[0];
# The words after the wrappers that run their arguments as a command,
# with the names `env` sets.
def unwrap($names):
  if length == 0 then {args: [], names: $names}
  elif (.[0] | base) as $w | ["command", "exec", "nohup", "time", "builtin", "sudo"] | index($w)
  then .[1:] | until(length == 0 or (.[0] | startswith("-") | not); .[1:]) | unwrap($names)
  elif (.[0] | base) == "env"
  then .[1:]
    | (until(length == 0 or (.[0] | (startswith("-") or test("^[A-Za-z_][A-Za-z0-9_]*=")) | not);
        if .[0] == "-u" or .[0] == "-S" or .[0] == "-C" then .[2:] else .[1:] end)) as $rest
    | ([.[: (length - ($rest | length))][] | assigned]) as $set
    | $rest | unwrap($names + $set)
  else {args: ., names: $names} end;
# git's options before its subcommand, and the subcommand's words.
def git_parts:
  {i: 0, c: [], config_env: false, rest: null, a: .}
  | until(.rest != null;
      .a[.i] as $w
      | if $w == null then .rest = []
        elif $w == "-c" then .c += [.a[.i + 1] // ""] | .i += 2
        elif ($w | startswith("-c")) and ($w | startswith("-C") | not) then .c += [$w[2:]] | .i += 1
        elif $w == "--config-env" then .config_env = true | .i += 2
        elif ($w | startswith("--config-env=")) then .config_env = true | .i += 1
        elif ["-C", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--list-cmds"] | index($w)
        then .i += 2
        elif ($w | startswith("-")) then .i += 1
        else .rest = .a[.i:] end)
  | {c, config_env, sub: .rest[0], sub_args: .rest[1:]};
def calls: [.. | objects | select(.Type == "CallExpr")
  | {assigns: [.Assigns[]? | .Name.Value], words: [.Args[]? | wtext]}];
. as $tree
| ([$tree | .. | objects | (.Assigns[]?, (select(.Type == "DeclClause") | .Args[]?)) | .Name.Value? // empty]
   | map(select(startswith("GIT_CONFIG_")))) as $line_config
| calls[]
| . as $call
| (.words | unwrap([])) as $u
| if ($u.args[0] // "" | base) == "git" then
    ($u.args[1:] | git_parts) as $g
    | select($g.sub == "push")
    | (($call.assigns + $u.names + $line_config) | map(select(startswith("GIT_CONFIG_"))) | unique[]
        | "bypass \(.) set on the command"),
      ($g.c[] | select(split("=")[0] | ascii_downcase | . == "core.hookspath" or contains("$"))
        | "bypass git -c \(.)"),
      (select($g.config_env) | "bypass git --config-env"),
      ($g.sub_args | (index("--") // length) as $end | .[:$end][]
        | select(. == "--no-veri" or . == "--no-verif" or . == "--no-verify")
        | "bypass \(.)")
  elif ["bash", "sh", "zsh", "dash", "ksh"] | index($u.args[0] // "" | base) then
    $u.args | (map(test("^-[a-zA-Z]*c[a-zA-Z]*$")) | index(true)) as $i
    | select($i != null) | .[$i + 1] // empty | "script \(@base64)"
  elif ($u.args[0] // "") == "eval" then
    "script \($u.args[1:] | join(" ") | @base64)"
  else empty end
JQ

# The bypasses in the command line "$1", one per line, searched to a
# depth of "$2" nested shells.
bypasses() {
  local tree line
  if [ "$2" -gt 0 ] && tree=$(shfmt --to-json <<<"$1" 2>/dev/null); then
    while IFS= read -r line; do
      case $line in
      "bypass "*) printf '%s\n' "${line#bypass }" ;;
      "script "*) bypasses "$(printf '%s' "${line#script }" | base64 --decode 2>/dev/null)" "$(($2 - 1))" ;;
      esac
    done < <(jq -r "$program" <<<"$tree" 2>/dev/null)
  else
    textual "$1"
  fi
}

# The fallback: the text names git, push and a bypass.
textual() {
  local s
  s=$(tr '[:upper:]' '[:lower:]' <<<"$1")
  case $s in *git*push*) ;; *) return ;; esac
  case $s in *--no-veri*) printf '%s\n' "--no-verify" ;; esac
  case $s in *core.hookspath*) printf '%s\n' "core.hooksPath" ;; esac
  case $s in *--config-env*) printf '%s\n' "git --config-env" ;; esac
  case $s in *git_config_*) printf '%s\n' "a GIT_CONFIG_* variable" ;; esac
}

if have shfmt && have jq; then
  command_line=$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null) || command_line=$payload
  cwd=$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null) || cwd=
  found=$(bypasses "$command_line" 3)
else
  cwd=
  found=$(textual "$payload")
fi
[ -n "$found" ] || exit 0

# The last `Push guard:` item in the user's file, then the project's.
mode=deny
project=${CLAUDE_PROJECT_DIR:-$cwd}
for file in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/$skill.preferences.md" \
  ${project:+"$project/.agents/skills/$skill.preferences.md"}; do
  [ -f "$file" ] || continue
  while IFS= read -r line; do
    shopt -s nocasematch
    if [[ $line =~ ^[[:space:]]*[-*+][[:space:]]+(\*\*)?push\ guard(\*\*)?:[[:space:]]*\`?(deny|remind|off)\`?[[:space:]]*$ ]]; then
      mode=$(tr '[:upper:]' '[:lower:]' <<<"${BASH_REMATCH[3]}")
    fi
    shopt -u nocasematch
  done <"$file"
done
[ "$mode" != off ] || exit 0

what=$(sort -u <<<"$found" | paste -s -d ',' - | sed 's/,/, /g' | tr -d '[:cntrl:]')
reason="Blocked git push that skips the pre-push hook ($what). That hook, in the global core.hooksPath, refuses rewrites and deletions of a default branch, and the allow rule for git push --force-with-lease is safe only with it. Push without $what; if the repository's own pre-push hook fails, fix what it reports. See git-hygiene-push-force-safely."
# The reason holds no quote or backslash, so it goes into JSON as it is.
reason=${reason//\\/}
reason=${reason//\"/}

if [ "$mode" = remind ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$reason"
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
fi
