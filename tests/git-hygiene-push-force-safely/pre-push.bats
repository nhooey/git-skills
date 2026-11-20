#!/usr/bin/env bats

setup() {
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  git config --global user.name Test
  git config --global user.email test@example.com
  git config --global core.hooksPath "$BATS_TEST_DIRNAME/../../skills/git-hygiene-push-force-safely/scripts"
  cd "$BATS_TEST_TMPDIR"
  git init --quiet --bare --initial-branch=master origin.git
  git init --quiet --initial-branch=master seed
  git -C seed commit --quiet --allow-empty -m one
  git -C seed push --quiet ../origin.git master
  git clone --quiet origin.git work
  cd work
}

@test "a fast-forward of the default branch is allowed" {
  git commit --quiet --allow-empty -m two
  run git push origin master
  [ "$status" -eq 0 ]
}

@test "a rewrite of the default branch is refused" {
  git commit --quiet --amend --allow-empty -m rewritten
  run git push --force-with-lease origin master
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to rewrite master"* ]]
}

@test "a deletion of the default branch is refused" {
  run git push origin :master
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to delete master"* ]]
}

@test "a rewrite of another branch is allowed" {
  git switch --quiet --create feature
  git commit --quiet --allow-empty -m feature
  git push --quiet origin feature
  git commit --quiet --amend --allow-empty -m rewritten
  run git push --force-with-lease origin feature
  [ "$status" -eq 0 ]
}

@test "the repository's own pre-push hook runs after the check" {
  printf '#!/bin/sh\necho "own hook: $1"\nexit 1\n' >.git/hooks/pre-push
  chmod u+x .git/hooks/pre-push
  git commit --quiet --allow-empty -m two
  run git push origin master
  [ "$status" -ne 0 ]
  [[ "$output" == *"own hook: origin"* ]]
}
