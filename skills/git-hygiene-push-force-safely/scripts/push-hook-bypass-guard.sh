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
# It also denies a force push (`--force`, `-f`, `--force-with-lease`, a
# `+` refspec) from a repository where the pre-push hook doesn't run:
# where the effective `core.hooksPath`, read with `git config --get` in
# the folder the push runs in (its `cd` and `-C` targets applied to the
# payload's cwd) and made absolute, holds no executable `pre-push`
# carrying the marker line `# git-hooks-default-branch-guard pre-push`.
# A repository-local core.hooksPath, as lefthook and husky set, replaces
# the global one, so it hides the hook. A push that doesn't force, or a
# dry run, is never denied for this.
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

marker='# git-hooks-default-branch-guard pre-push'

# The jq program: from shfmt's syntax tree of a command line, one line
# per bypass of a git push in it ("bypass <what>"), one per force push
# ("force", then a tab before each `cd` or `-C` folder it runs under,
# after the folders in $base), and one per string a nested shell or eval
# runs ("script <base64 of its folders> <base64 of the string>").
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
  {i: 0, c: [], dirs: [], config_env: false, rest: null, a: .}
  | until(.rest != null;
      .a[.i] as $w
      | if $w == null then .rest = []
        elif $w == "-c" then .c += [.a[.i + 1] // ""] | .i += 2
        elif $w == "-C" then .dirs += [.a[.i + 1] // ""] | .i += 2
        elif ($w | startswith("-c")) and ($w | startswith("-C") | not) then .c += [$w[2:]] | .i += 1
        elif $w == "--config-env" then .config_env = true | .i += 2
        elif ($w | startswith("--config-env=")) then .config_env = true | .i += 1
        elif ["--git-dir", "--work-tree", "--namespace", "--super-prefix", "--list-cmds"] | index($w)
        then .i += 2
        elif ($w | startswith("-")) then .i += 1
        else .rest = .a[.i:] end)
  | {c, dirs, config_env, sub: .rest[0], sub_args: .rest[1:]};
# Whether a push's words force an update without a dry run.
def forces:
  (index("--") // length) as $end
  | .[:$end] as $opts
  | ($opts | any(. == "--dry-run" or test("^-[46nquvf]*n[46nquvf]*$")) | not)
    and (($opts | any(. == "--force" or test("^--force-w") or test("^-[46nquvf]*f[46nquvf]*$")))
      or any(.[]; startswith("+")));
def calls: [.. | objects | select(.Type == "CallExpr")
  | {assigns: [.Assigns[]? | .Name.Value], words: [.Args[]? | wtext]}];
. as $tree
| ([$tree | .. | objects | (.Assigns[]?, (select(.Type == "DeclClause") | .Args[]?)) | .Name.Value? // empty]
   | map(select(startswith("GIT_CONFIG_")))) as $line_config
| ($base | split("\t") | map(select(. != ""))) as $base_dirs
| calls as $calls
| range(0; $calls | length) as $k
| $calls[$k] as $call
# The folders the `cd` and `pushd` calls before this one change to.
| ($base_dirs + [$calls[:$k][] | .words
    | select(length > 1 and ((.[0] | base) == "cd" or (.[0] | base) == "pushd"))
    | [.[1:][] | select(startswith("-") | not)] | last // empty]) as $dirs
| ($call.words | unwrap([])) as $u
| if ($u.args[0] // "" | base) == "git" then
    ($u.args[1:] | git_parts) as $g
    | select($g.sub == "push")
    | (select($g.sub_args | forces) | "force" + ([($dirs + $g.dirs)[] | "\t" + .] | join(""))),
      (($call.assigns + $u.names + $line_config) | map(select(startswith("GIT_CONFIG_"))) | unique[]
        | "bypass \(.) set on the command"),
      ($g.c[] | select(split("=")[0] | ascii_downcase | . == "core.hookspath" or contains("$"))
        | "bypass git -c \(.)"),
      (select($g.config_env) | "bypass git --config-env"),
      ($g.sub_args | (index("--") // length) as $end | .[:$end][]
        | select(. == "--no-veri" or . == "--no-verif" or . == "--no-verify")
        | "bypass \(.)")
  elif ["bash", "sh", "zsh", "dash", "ksh"] | index($u.args[0] // "" | base) then
    $u.args | (map(test("^-[a-zA-Z]*c[a-zA-Z]*$")) | index(true)) as $i
    | select($i != null) | .[$i + 1] // empty
    | "script \($dirs | join("\t") | @base64) \(@base64)"
  elif ($u.args[0] // "") == "eval" then
    "script \($dirs | join("\t") | @base64) \($u.args[1:] | join(" ") | @base64)"
  else empty end
JQ

# The bypasses and force pushes in the command line "$1", one per line
# as the jq program prints them, searched to a depth of "$2" nested
# shells, under the tab-separated folders "$3".
findings() {
  local tree line rest
  if [ "$2" -gt 0 ] && tree=$(shfmt --to-json <<<"$1" 2>/dev/null); then
    while IFS= read -r line; do
      case $line in
      "script "*)
        rest=${line#script }
        findings "$(printf '%s' "${rest#* }" | base64 --decode 2>/dev/null)" "$(($2 - 1))" \
          "$(printf '%s' "${rest%% *}" | base64 --decode 2>/dev/null)"
        ;;
      *) printf '%s\n' "$line" ;;
      esac
    done < <(jq -r --arg base "${3-}" "$program" <<<"$tree" 2>/dev/null)
  else
    textual "$1"
  fi
}

# The fallback: the text names git, push and a bypass, or a force.
textual() {
  local s
  s=$(tr '[:upper:]' '[:lower:]' <<<"$1")
  case $s in *git*push*) ;; *) return ;; esac
  case $s in *--no-veri*) printf '%s\n' "bypass --no-verify" ;; esac
  case $s in *core.hookspath*) printf '%s\n' "bypass core.hooksPath" ;; esac
  case $s in *--config-env*) printf '%s\n' "bypass git --config-env" ;; esac
  case $s in *git_config_*) printf '%s\n' "bypass a GIT_CONFIG_* variable" ;; esac
  case $s in *--force* | *" -f"* | *" +"*) printf '%s\n' force ;; esac
}

# The folder "$1" with the `cd` and `-C` folders after it applied.
resolve_dir() {
  local dir=$1 step
  shift
  for step in "$@"; do
    case $step in
    "~") step=$HOME ;;
    "~/"*) step=$HOME/${step#"~/"} ;;
    esac
    case $step in
    /*) dir=$step ;;
    *) dir=$dir/$step ;;
    esac
  done
  printf '%s\n' "$dir"
}

has_marker() {
  local line
  while IFS= read -r line; do
    [ "$line" != "$marker" ] || return 0
  done <"$1"
  return 1
}

# Nothing when a push from the folder "$1" runs the pre-push guard, a
# folder that doesn't exist among them, since that push fails anyway;
# else the effective core.hooksPath, absolute, or nothing after a colon
# when none is set.
hooks_gap() {
  local dir=$1 path top
  [ -d "$dir" ] || return 0
  path=$(git -C "$dir" config --get core.hooksPath 2>/dev/null) || path=
  if [ -z "$path" ]; then
    printf ':\n'
    return
  fi
  case $path in
  "~") path=$HOME ;;
  "~/"*) path=$HOME/${path#"~/"} ;;
  esac
  if [[ $path != /* ]]; then
    top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || top=$dir
    path=$top/$path
  fi
  [ ! -d "$path" ] || path=$(cd "$path" && pwd -P)
  [ -f "$path/pre-push" ] && [ -x "$path/pre-push" ] && has_marker "$path/pre-push" && return
  printf '%s\n' "$path"
}

if have shfmt && have jq; then
  command_line=$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null) || command_line=$payload
  cwd=$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null) || cwd=
  lines=$(findings "$command_line" 3 "")
else
  cwd=
  lines=$(textual "$payload")
fi

found=
gaps=
checked=
while IFS= read -r line; do
  case $line in
  "bypass "*) found+="${line#bypass }"$'\n' ;;
  force*)
    IFS=$'\t' read -r -a steps <<<"${line#force}"
    dir=$(resolve_dir "${cwd:-$PWD}" ${steps[@]+"${steps[@]}"})
    case $'\n'$checked in *$'\n'"$dir"$'\n'*) continue ;; esac
    checked+="$dir"$'\n'
    gap=$(hooks_gap "$dir")
    [ -z "$gap" ] || gaps+="$dir"$'\t'"$gap"$'\n'
    ;;
  esac
done <<<"$lines"
[ -n "$found$gaps" ] || exit 0

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

reason=
if [ -n "$found" ]; then
  what=$(sed '/^$/d' <<<"$found" | sort -u | paste -s -d ',' - | sed 's/,/, /g' | tr -d '[:cntrl:]')
  reason="Blocked git push that skips the pre-push hook ($what). That hook, in the global core.hooksPath, refuses rewrites and deletions of a default branch, and the allow rule for git push --force-with-lease is safe only with it. Push without $what; if the repository's own pre-push hook fails, fix what it reports."
fi
while IFS=$'\t' read -r dir gap; do
  [ -n "$dir" ] || continue
  if [ "$gap" = : ]; then
    reason+="${reason:+ }Blocked force push in $dir: no core.hooksPath is set there, so the pre-push guard that refuses default-branch rewrites doesn't run. Set the global core.hooksPath to the flake package git-hooks-default-branch-guard."
  else
    reason+="${reason:+ }Blocked force push in $dir: its core.hooksPath is $gap, which holds no executable pre-push carrying the line $marker, so the pre-push guard that refuses default-branch rewrites doesn't run there. Run the default-branch check from that repository's own hook manager too, from a pre-push in $gap that carries that line, or remove the local core.hooksPath (git -C $dir config --unset core.hooksPath) so the global one applies."
  fi
done <<<"$gaps"
reason+=" See git-hygiene-push-force-safely."
# The reason holds no quote, backslash or control character, so it goes
# into JSON as it is.
reason=$(tr -d '[:cntrl:]' <<<"$reason")
reason=${reason//\\/}
reason=${reason//\"/}

if [ "$mode" = remind ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$reason"
else
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
fi
