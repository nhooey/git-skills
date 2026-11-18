#!/usr/bin/env bats
# pull-request-monitor.sh's BODY-DRIFT line, with `gh` and the body
# check replaced by stubs written into the test's temporary directory.
# The stub `gh` reports the pull request MERGED, so the loop runs once.

setup() {
  monitor="$BATS_TEST_DIRNAME/../../skills/github-workflow-pull-request-watcher/scripts/pull-request-monitor.sh"
  export GIT_CONFIG_NOSYSTEM=1 HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  cd "$BATS_TEST_TMPDIR"
  git init --quiet --initial-branch feature repo
  cd repo
  git -c user.name=T -c user.email=t@x commit --quiet --allow-empty --message one
  export HEAD_SHA=$(git rev-parse HEAD)

  {
    printf '#!%s\n' "$BASH"
    cat <<'EOF'
case "$1 $2" in
"api user") echo me ;;
"pr view") printf '%s\tfeature\tSTATE MERGED REVIEW none\n' "$HEAD_SHA" ;;
"api repos/"*/check-runs) echo '{"check_runs": []}' ;;
*) echo '[]' ;;
esac
EOF
  } >"$BATS_TEST_TMPDIR/bin/gh"
  chmod u+x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

body_check() {
  printf '#!%s\nexit %s\n' "$BASH" "$1" >"$BATS_TEST_TMPDIR/body-check"
}

@test "drift at the head emits BODY-DRIFT" {
  body_check 1
  run bash "$monitor" --pr 7 --repo o/r --interval 0 --body-check "$BATS_TEST_TMPDIR/body-check"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BODY-DRIFT PR #7's title or body differs from its commits at ${HEAD_SHA:0:7}"* ]]
  [[ "$output" == *"STATE MERGED REVIEW none"* ]]
}

@test "several commits without a reason emit BODY-DRIFT too" {
  body_check 4
  run bash "$monitor" --pr 7 --repo o/r --interval 0 --body-check "$BATS_TEST_TMPDIR/body-check"
  [[ "$output" == *"BODY-DRIFT PR #7 holds several commits"* ]]
}

@test "in sync, or a head the local branch isn't at, emits none" {
  body_check 0
  run bash "$monitor" --pr 7 --repo o/r --interval 0 --body-check "$BATS_TEST_TMPDIR/body-check"
  [[ "$output" != *"BODY-DRIFT"* ]]

  body_check 1
  git -c user.name=T -c user.email=t@x commit --quiet --allow-empty --message two
  run bash "$monitor" --pr 7 --repo o/r --interval 0 --body-check "$BATS_TEST_TMPDIR/body-check"
  [[ "$output" != *"BODY-DRIFT"* ]]
}
