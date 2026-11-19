#!/usr/bin/env bash
# git-skills test [--language LANGUAGE] [SKILL...]: runs the tests in
# tests/, or in each named skill's folder there, with each language's own
# tool. Any other command goes to the lint program. The flake's
# `git-skills` package sets the two variables from Nix:
#
# - GIT_SKILLS_PROGRAM: scripts/git_skills.py, in the Nix store.
# - GIT_SKILLS_TEST_LANGUAGES: the test languages, separated by spaces.
set -o errexit -o nounset -o pipefail

if [ "${1:-}" != test ]; then
  exec python3 -B "${GIT_SKILLS_PROGRAM:?}" "$@"
fi
shift
read -ra languages <<<"${GIT_SKILLS_TEST_LANGUAGES:?}"
usage() {
  local IFS='|'
  echo "git-skills: $*" >&2
  echo "usage: git-skills test [--language ${all_languages[*]}] [SKILL...]" >&2
  exit 2
}
all_languages=("${languages[@]}")
if [ "${1:-}" = --language ]; then
  case " ${languages[*]} " in
  *" ${2:-} "*) languages=("$2") ;;
  *) usage "no language ${2:-}" ;;
  esac
  shift 2
fi
cd "${PRJ_ROOT:-$(git rev-parse --show-toplevel)}"
export PYTHONDONTWRITEBYTECODE=1
dirs=()
for skill in "$@"; do
  case $skill in
  "" | */* | .* | _*) usage "no tests/$skill folder" ;;
  esac
  [ -d "tests/$skill" ] || usage "no tests/$skill folder"
  dirs+=("tests/$skill")
done
if [ "$#" -eq 0 ]; then dirs=(tests); fi
failed=()
ran=0
run() {
  echo "== $*"
  ran=$((ran + 1))
  "$@" || failed+=("$*")
}
bb_test() { (cd "$1" && bb test); }
# Each tool runs only on the files of its language; pytest's exit 5, for
# no test collected, is a failure like any other.
for language in "${languages[@]}"; do
  case $language in
  python) pattern='test_*.py' ;;
  bats) pattern='*.bats' ;;
  clojure) pattern=bb.edn ;;
  esac
  mapfile -t found < <(find "${dirs[@]}" -name "$pattern" | sort)
  [ "${#found[@]}" -gt 0 ] || continue
  case $language in
  python) run pytest "${found[@]}" ;;
  bats) run bats "${found[@]}" ;;
  clojure) for project in "${found[@]}"; do run bb_test "${project%/bb.edn}"; done ;;
  esac
done
if [ "$ran" -eq 0 ]; then
  echo "git-skills: no ${languages[*]} test in ${dirs[*]}" >&2
  exit 1
fi
if [ "${#failed[@]}" -gt 0 ]; then
  printf 'git-skills: failed: %s\n' "${failed[@]}" >&2
  exit 1
fi
