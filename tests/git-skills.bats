#!/usr/bin/env bats
# scripts/git-skills.sh run directly, with the two variables the flake's
# `git-skills` package sets from Nix, a stub lint program, and a project
# root in the test's temporary directory.

setup() {
  script="$BATS_TEST_DIRNAME/../scripts/git-skills.sh"
  export GIT_SKILLS_TEST_LANGUAGES="python bats clojure"
  export GIT_SKILLS_PROGRAM="$BATS_TEST_TMPDIR/git_skills.py"
  echo 'import sys; print("lint program:", *sys.argv[1:])' >"$GIT_SKILLS_PROGRAM"
  export PRJ_ROOT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PRJ_ROOT/tests/some-skill"
}

@test "a command other than test goes to the lint program" {
  run "$BASH" "$script" lint some-skill
  [ "$status" -eq 0 ]
  [ "$output" = "lint program: lint some-skill" ]
}

@test "an unknown language is a usage error" {
  run "$BASH" "$script" test --language nope
  [ "$status" -eq 2 ]
  [ "${lines[0]}" = "git-skills: no language nope" ]
  [ "${lines[1]}" = "usage: git-skills test [--language python|bats|clojure] [SKILL...]" ]
}

@test "a skill with no tests folder is a usage error" {
  run "$BASH" "$script" test --language bats other-skill
  [ "$status" -eq 2 ]
  [ "${lines[0]}" = "git-skills: no tests/other-skill folder" ]
  [ "${lines[1]}" = "usage: git-skills test [--language python|bats|clojure] [SKILL...]" ]
}

@test "a selection that runs no test fails" {
  run "$BASH" "$script" test --language bats some-skill
  [ "$status" -eq 1 ]
  [ "$output" = "git-skills: no bats test in tests/some-skill" ]
}

@test "a selected language runs its tests, and a failure fails the run" {
  printf '@test "fails" { false; }\n' >"$PRJ_ROOT/tests/some-skill/fails.bats"
  run "$BASH" "$script" test --language bats some-skill
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "== bats tests/some-skill/fails.bats" ]
  [ "${lines[${#lines[@]} - 1]}" = "git-skills: failed: bats tests/some-skill/fails.bats" ]
}
