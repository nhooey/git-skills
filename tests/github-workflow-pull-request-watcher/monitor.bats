#!/usr/bin/env bats
# pull-request-monitor.sh's events, with `gh` and the body check
# replaced by stubs written into the test's temporary directory. The
# stub `gh` answers each poll from the files `poll` writes for it, and
# past the last one repeats it. With none written, it reports the pull
# request MERGED with no checks or comments, so the loop runs once.

setup() {
  monitor="$BATS_TEST_DIRNAME/../../skills/github-workflow-pull-request-watcher/scripts/pull-request-monitor.sh"
  export GIT_CONFIG_NOSYSTEM=1 HOME="$BATS_TEST_TMPDIR/home"
  export STUB_POLLS="$BATS_TEST_TMPDIR/polls"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin" "$STUB_POLLS"
  cd "$BATS_TEST_TMPDIR"
  git init --quiet --initial-branch feature repo
  cd repo
  git -c user.name=T -c user.email=t@x commit --quiet --allow-empty --message one
  export HEAD_SHA=$(git rev-parse HEAD)

  # Each poll starts with the monitor's `gh pr view`, which advances the
  # stub's poll count; the calls after it answer from that poll.
  {
    printf '#!%s\n' "$BASH"
    cat <<'EOF'
n=$(cat "$STUB_POLLS/count" 2>/dev/null || echo 0)
if [ "$1 $2" = "pr view" ]; then
  n=$((n + 1))
  echo "$n" >"$STUB_POLLS/count"
fi
while [ "$n" -gt 1 ] && [ ! -d "$STUB_POLLS/$n" ]; do n=$((n - 1)); done
poll=$STUB_POLLS/$n
case "$1 $2" in
"api user") echo me ;;
"pr view") printf '%s\tfeature\tSTATE %s REVIEW none\n' "$HEAD_SHA" "$(cat "$poll/state" 2>/dev/null || echo MERGED)" ;;
"api repos/"*/check-runs) cat "$poll/check-runs" 2>/dev/null || echo '{"check_runs": []}' ;;
"api repos/"*/issues/*/comments) cat "$poll/issue-comments" 2>/dev/null || echo '[]' ;;
"api repos/"*/pulls/*/comments) cat "$poll/review-comments" 2>/dev/null || echo '[]' ;;
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

# poll N STATE CHECKS ISSUE-COMMENTS REVIEW-COMMENTS: the stub `gh`'s
# answers on the monitor's Nth poll. CHECKS is a JSON list of completed
# [name, conclusion] pairs, and each list of comments one of
# [id, login, body] triples; the stub's own login is `me`.
poll() {
  local dir=$STUB_POLLS/$1
  mkdir -p "$dir"
  echo "$2" >"$dir/state"
  jq '{check_runs: map({name: .[0], status: "completed", conclusion: .[1]})}' <<<"$3" >"$dir/check-runs"
  jq 'map({id: .[0], user: {login: .[1]}, body: .[2]})' <<<"$4" >"$dir/issue-comments"
  jq 'map({id: .[0], user: {login: .[1]}, body: .[2]})' <<<"$5" >"$dir/review-comments"
}

# poll_with_history N STATE: a poll that already holds a passed check,
# a comment of the stub's own and one of a reviewer's.
poll_with_history() {
  poll "$1" "$2" '[["build", "success"]]' '[[1, "me", "first"]]' '[[2, "alice", "nit"]]'
}

# poll_later N: the poll after poll_with_history, with a failed check
# and a new comment added, and the pull request merged.
poll_later() {
  poll "$1" MERGED '[["build", "success"], ["lint", "failure"]]' \
    '[[1, "me", "first"], [3, "bob", "ship it"]]' '[[2, "alice", "nit"]]'
}

# run_monitor FLAG...: runs the monitor with its body check in sync.
run_monitor() {
  body_check 0
  run bash "$monitor" --pr 7 --repo o/r --interval 0 --body-check "$BATS_TEST_TMPDIR/body-check" "$@"
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

@test "--quiet-initial keeps the first poll's BODY-DRIFT quiet but still emits MERGED" {
  body_check 1
  run bash "$monitor" --pr 7 --repo o/r --interval 0 --quiet-initial --body-check "$BATS_TEST_TMPDIR/body-check"
  [ "$status" -eq 0 ]
  [[ "$output" != *"BODY-DRIFT"* ]]
  [ "$output" = "STATE MERGED REVIEW none" ]
}

@test "the first poll's checks, comments and state are emitted by default" {
  poll_with_history 1 OPEN
  poll_later 2
  run_monitor
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' \
    "CHECK build: success" \
    "COMMENT-SELF: first" \
    "COMMENT-alice: nit" \
    "STATE OPEN REVIEW none" \
    "CHECK lint: failure" \
    "COMMENT-bob: ship it" \
    "STATE MERGED REVIEW none")" ]
}

@test "--quiet-initial emits only what changed after the first poll" {
  poll_with_history 1 OPEN
  poll_later 2
  run_monitor --quiet-initial
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' \
    "CHECK lint: failure" \
    "COMMENT-bob: ship it" \
    "STATE MERGED REVIEW none")" ]
}

@test "--quiet-initial emits nothing for polls with no change" {
  poll_with_history 1 OPEN
  poll_with_history 2 OPEN
  poll_with_history 3 CLOSED
  run_monitor --quiet-initial
  [ "$status" -eq 0 ]
  [ "$output" = "STATE CLOSED REVIEW none" ]
}

@test "--quiet-initial still emits a MERGED state on the first poll" {
  poll_with_history 1 MERGED
  run_monitor --quiet-initial
  [ "$status" -eq 0 ]
  [ "$output" = "STATE MERGED REVIEW none" ]
}

@test "--help lists --quiet-initial and --dry-run" {
  run bash "$monitor" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--quiet-initial"* ]]
  [[ "$output" == *"--dry-run"* ]]
}
