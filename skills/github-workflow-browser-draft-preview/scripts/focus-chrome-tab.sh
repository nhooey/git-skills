#!/usr/bin/env bash
# Bring the browser tab whose URL starts with the given prefix to the front:
# make it its window's active tab, raise that window above the browser's
# others, and activate the browser. Claude in Chrome can drive a tab but has
# no tool to raise it, so a draft waiting for the user's review would
# otherwise sit behind whatever window they were using. The extension runs in
# any Chromium browser, so every running one with Chrome's AppleScript
# dictionary is searched. macOS only (AppleScript).
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: focus-chrome-tab.sh <url-prefix> [--app <name>]...

  <url-prefix>   focus the first tab whose URL starts with this, e.g.
                 https://github.com/owner/repo/pull/12
  --app <name>   search only this browser; repeatable (default: every
                 running one of Google Chrome, Brave Browser, Chromium,
                 Microsoft Edge, Vivaldi, Google Chrome Beta, Google Chrome
                 Canary)
  -h, --help     show this help

Exits 0 when a tab was focused, 1 when no tab matched, 2 on bad usage.
EOF
}

prefix='' apps=()
while [ $# -gt 0 ]; do
  case "$1" in
  --app) apps+=("$2") && shift 2 ;;
  -h | --help) usage && exit 0 ;;
  -*)
    echo "unknown option: $1 (try --help)" >&2
    exit 2
    ;;
  *) prefix=$1 && shift ;;
  esac
done
[ -n "$prefix" ] || {
  usage
  exit 2
}
[ "$(uname)" = Darwin ] || {
  echo "focus-chrome-tab.sh: macOS only" >&2
  exit 2
}

[ ${#apps[@]} -gt 0 ] || apps=("Google Chrome" "Brave Browser" "Chromium" "Microsoft Edge"
  "Vivaldi" "Google Chrome Beta" "Google Chrome Canary")

# Raise the first tab whose URL starts with $2 in browser $1; print "yes" if
# one matched. The name is spliced into the script rather than passed in, so
# AppleScript compiles against that browser's own dictionary.
focus_in() {
  local name=${1//\"/} script
  script=$(
    cat <<EOF
on run argv
  set wanted to item 1 of argv
  tell application "$name"
    repeat with w in windows
      set i to 0
      repeat with t in tabs of w
        set i to i + 1
        if (URL of t) starts with wanted then
          set active tab index of w to i
          set index of w to 1
          activate
          return "yes"
        end if
      end repeat
    end repeat
  end tell
  return "no"
end run
EOF
  )
  osascript -e "$script" "$2"
}

for name in "${apps[@]}"; do
  # Ask only a running browser: naming one that isn't installed makes
  # AppleScript open a "Where is <app>?" dialog and wait on it.
  pgrep -qf "/$name.app/Contents/MacOS/$name" || continue
  if [ "$(focus_in "$name" "$prefix")" = yes ]; then
    echo "focused in $name"
    exit 0
  fi
done
echo "no tab starts with $prefix in a running one of: ${apps[*]}" >&2
exit 1
