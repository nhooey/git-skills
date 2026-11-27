#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  hooks="$BATS_TEST_TMPDIR/hooks"
  bash "$BATS_TEST_DIRNAME/../../scripts/write-forwarding-hooks.sh" \
    "$BATS_TEST_DIRNAME/../../skills/git-hygiene-push-force-safely/scripts" "$hooks"
  git config --global user.name Test
  git config --global user.email test@example.com
  git config --global core.hooksPath "$hooks"
  git init --quiet --initial-branch=master "$BATS_TEST_TMPDIR/work"
  cd "$BATS_TEST_TMPDIR/work"
}

own_hook() {
  printf '#!/bin/sh\n%s\n' "$2" >".git/hooks/$1"
  chmod u+x ".git/hooks/$1"
}

@test "the folder holds a hook for each one git documents" {
  [ -x "$hooks/pre-commit" ]
  [ -x "$hooks/commit-msg" ]
  [ -x "$hooks/post-checkout" ]
  [ -x "$hooks/reference-transaction" ]
}

@test "a commit with no hooks of the repository's own succeeds" {
  run git commit --allow-empty -m one
  [ "$status" -eq 0 ]
}

@test "the repository's own pre-commit and commit-msg run" {
  own_hook pre-commit 'echo "own pre-commit"'
  own_hook commit-msg 'echo "own commit-msg: $(cat "$1")"'
  run git commit --allow-empty -m one
  [ "$status" -eq 0 ]
  [[ "$output" == *"own pre-commit"* ]]
  [[ "$output" == *"own commit-msg: one"* ]]
}

@test "a failing pre-commit of the repository's own fails the commit" {
  own_hook pre-commit 'exit 1'
  run git commit --allow-empty -m one
  [ "$status" -ne 0 ]
  run git rev-parse --verify --quiet HEAD
  [ "$status" -ne 0 ]
}

@test "a failing commit-msg of the repository's own fails the commit" {
  own_hook commit-msg 'exit 1'
  run git commit --allow-empty -m one
  [ "$status" -ne 0 ]
  run git rev-parse --verify --quiet HEAD
  [ "$status" -ne 0 ]
}

@test "a hook gets its stdin through the forward" {
  own_hook post-rewrite 'cat >rewritten'
  git commit --quiet --allow-empty -m one
  git commit --quiet --amend --allow-empty -m two
  [ -s rewritten ]
}

@test "the generated pre-push still guards the default branch" {
  git init --quiet --bare --initial-branch=master "$BATS_TEST_TMPDIR/origin.git"
  git commit --quiet --allow-empty -m one
  git push --quiet "$BATS_TEST_TMPDIR/origin.git" master
  git remote add origin "$BATS_TEST_TMPDIR/origin.git"
  git fetch --quiet origin
  git commit --quiet --amend --allow-empty -m rewritten
  run git push --force origin master
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to rewrite master"* ]]
}

@test "git init prints nothing to stderr" {
  run --separate-stderr git init --quiet "$BATS_TEST_TMPDIR/fresh"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "git init --bare prints nothing to stderr" {
  run --separate-stderr git init --quiet --bare "$BATS_TEST_TMPDIR/fresh.git"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "git clone of a local repository prints nothing to stderr" {
  git commit --quiet --allow-empty -m one
  run --separate-stderr git clone --quiet "$BATS_TEST_TMPDIR/work" "$BATS_TEST_TMPDIR/clone"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  run --separate-stderr git clone --quiet --no-local "$BATS_TEST_TMPDIR/work" "$BATS_TEST_TMPDIR/copy"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}
