#!/usr/bin/env bash
# Copies a hooks plugin's scripts into its scripts/ folder, and puts the
# tools they run first on each Bash script's PATH, by a line after its
# shebang. Not makeWrapper: hooks.json runs `bash <script>`, and the bash
# on PATH may be macOS's 3.2, which misreads makeWrapper's PATH edits.
#
# Usage: copy-hook-scripts.sh <files> <bin-path>
#
# - files: a folder of the files to copy, links followed, such as the
#   flake's `hookFiles`.
# - bin-path: the folders to put first on PATH, separated by colons.
#
# Run it in the plugin's source folder, as the flake's `hooks-plugin`
# postPatch does.
set -o errexit -o nounset -o pipefail

files=$1
bin_path=$2

mkdir -p scripts
cp -RL "$files/." scripts/
chmod -R u+w scripts
for script in scripts/*.sh; do
  {
    IFS= read -r shebang
    printf '%s\n' "$shebang"
    # shellcheck disable=SC2016 # the script expands $PATH when it runs
    printf 'PATH=%s${PATH:+:$PATH}; export PATH\n' "$bin_path"
    cat
  } <"$script" >"$script.new"
  cat "$script.new" >"$script"
  rm "$script.new"
done
