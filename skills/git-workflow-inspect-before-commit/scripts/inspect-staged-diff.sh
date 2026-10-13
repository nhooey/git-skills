#!/usr/bin/env bash
# PreToolUse hook for Bash. Before a `git commit` runs, scans the diff
# that is about to be committed for two of the three failure modes from
# `git-workflow-inspect-before-commit`: hard-coded secrets and leftover
# debug logging. (The third — unrelated formatting churn — is judgment,
# not pattern-matchable, so it stays a human/agent review step.) Emits a
# non-blocking `systemMessage` nudge listing what it found; never blocks,
# always exits 0. The agent still owns the decision to fix or proceed.
#
# Wired as a skill-frontmatter hook (see this skill's SKILL.md). The
# command resolves the script via $CLAUDE_SKILL_DIR, which Claude Code
# exports for the active skill, so it works regardless of the cwd the
# hook runs in.

set -u
export GIT_OPTIONAL_LOCKS=0

payload=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

cmd=$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null) || exit 0
cwd=$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null) || exit 0

# Gate: only act on a `git commit`. `git commit --help`, `git log`,
# etc. fall through to a silent exit.
case "$cmd" in
*"git commit"*) ;;
*) exit 0 ;;
esac

[ -d "$cwd" ] && cd "$cwd" 2>/dev/null
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# `git commit -a` / `--all` stages tracked changes during the commit, so
# at PreToolUse time they are not yet in the index — diff against HEAD to
# see what such a commit would capture. Otherwise inspect the index.
case "$cmd" in
*" -a"* | *"--all"* | *" -am"* | *" -ma"*) diff=$(git diff HEAD 2>/dev/null) ;;
*) diff=$(git diff --cached 2>/dev/null) ;;
esac

# Only inspect added lines (`+...`, excluding the `+++` file header) — a
# secret or debug line being *removed* is not a problem.
added=$(printf '%s\n' "$diff" | grep -E '^\+' | grep -Ev '^\+\+\+')
[ -n "$added" ] || exit 0

findings=""
add_finding() { findings="${findings}  - $1"$'\n'; }

# --- Secrets / tokens ---
if printf '%s\n' "$added" | grep -qE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----'; then
  add_finding 'private key block (`-----BEGIN ... PRIVATE KEY-----`)'
fi
if printf '%s\n' "$added" | grep -qE 'AKIA[0-9A-Z]{16}'; then
  add_finding 'AWS access key id (`AKIA...`)'
fi
if printf '%s\n' "$added" | grep -qiE '(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token)["'\'' ]*[:=]["'\'' ]*[^"'\'' ]{8,}'; then
  add_finding 'hard-coded credential (a `password`/`secret`/`token`/`api_key` assigned a long literal)'
fi

# `.env` (but not `.env.example` / `.env.sample` / `.env.template`)
# entering the commit.
case "$cmd" in
*" -a"* | *"--all"* | *" -am"* | *" -ma"*) staged_files=$(git diff HEAD --name-only 2>/dev/null) ;;
*) staged_files=$(git diff --cached --name-only 2>/dev/null) ;;
esac
envfiles=$(printf '%s\n' "$staged_files" |
  grep -E '(^|/)\.env($|\.)' |
  grep -Ev '\.(example|sample|template|dist)$' |
  paste -sd', ' -)
[ -n "$envfiles" ] && add_finding "dotenv file in the commit: ${envfiles}"

# --- Debug logging ---
if printf '%s\n' "$added" | grep -qE 'console\.(log|debug|trace)\(|debugger;|\bbinding\.pry\b|\bbyebug\b|\bdbg!|var_dump\(|console\.dir\('; then
  add_finding 'debug logging (e.g. `console.log`, `debugger`, `binding.pry`, `dbg!`)'
fi

[ -n "$findings" ] || exit 0

msg=$(
  cat <<EOF
\`git-workflow-inspect-before-commit\`: the staged diff for this commit contains things worth a second look before it lands:

${findings}
Review \`git diff --cached\` (or \`git diff HEAD\` for a \`-a\` commit), and either remove these or confirm they belong. This is a nudge, not a block.
EOF
)

jq -n --arg msg "$msg" '{systemMessage: $msg}'
exit 0
