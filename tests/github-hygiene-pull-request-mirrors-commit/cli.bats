#!/usr/bin/env bats
# The command line of create-or-update-pull-request.sh, run against a
# throwaway repository with the `gh` stub in stubs/ on PATH.

setup() {
  script="$BATS_TEST_DIRNAME/../../skills/github-hygiene-pull-request-mirrors-commit/scripts/create-or-update-pull-request.sh"
  export GH_STATE="$BATS_TEST_TMPDIR/gh"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/repo"
  export HOME="$BATS_TEST_TMPDIR/home"
  export GIT_CONFIG_NOSYSTEM=1
  mkdir -p "$GH_STATE/issues" "$CLAUDE_CONFIG_DIR" "$HOME" "$BATS_TEST_TMPDIR/bin"
  # The stub runs under this bash: a sandbox may have no /usr/bin/env.
  printf '#!%s\nexec %s %q "$@"\n' "$BASH" "$BASH" "$BATS_TEST_DIRNAME/stubs/gh" >"$BATS_TEST_TMPDIR/bin/gh"
  chmod u+x "$BATS_TEST_TMPDIR/bin/gh"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  repo="$CLAUDE_PROJECT_DIR"
  git init --quiet --initial-branch main "$repo"
  cd "$repo"
  git config user.name Test
  git config user.email test@example.com
  git remote add origin git@github.com:octo/widgets.git
  git commit --quiet --allow-empty --message Start
  git update-ref refs/remotes/origin/main HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git switch --quiet --create feature
  printf 'one\ntwo\nthree\n' >notes.txt
  git add notes.txt
  git commit --quiet --file - <<'EOF'
Add the notes

The notes list three things, wrapped here at a narrow width so the
body has to be unwrapped; `notes.txt:2-3` are the last two.

Co-Authored-By: Ada <ada@example.com>
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
}

open_pr() {
  jq -n --arg head "$(git rev-parse HEAD)" --arg body "$1" \
    '{number: 7, html_url: "https://github.com/octo/widgets/pull/7", title: "Add the notes",
      body: $body, head: "feature", base: "main", headRefOid: $head}' >"$GH_STATE/pr.json"
}

@test "--help lists the modes and exit codes" {
  run bash "$script" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"render"*"sync"*"check"* ]]
  [[ "$output" == *"4  several commits"* ]]
}

@test "a usage error exits 2" {
  run bash "$script" --trailers maybe
  [ "$status" -eq 2 ]
  [[ "$output" == *"--trailers takes keep or drop"* ]]
}

@test "without bb it says how to get it" {
  mkdir "$BATS_TEST_TMPDIR/empty"
  run env PATH="$BATS_TEST_TMPDIR/empty" "$BASH" "$script" render
  [ "$status" -eq 2 ]
  [[ "$output" == "bb not found: install babashka or use the Nix-installed skill" ]]
}

@test "render unwraps the body, links the lines and drops the trailers" {
  run bash "$script" render
  [ "$status" -eq 0 ]
  sha=$(git rev-parse HEAD)
  [ "${lines[0]}" = "Add the notes" ]
  [[ "$output" == *"so the body has to be unwrapped; [\`notes.txt:2-3\`](https://github.com/octo/widgets/blob/$sha/notes.txt#L2-L3) are"* ]]
  [[ "$output" != *"Co-Authored-By"* ]]
  [[ "$output" == *"[//]: # (pr-body: generated from $sha; digest "* ]]
}

@test "sync creates the pull request, and check then finds it in sync" {
  run bash "$script" sync
  [ "$status" -eq 0 ]
  [ "$output" = "created https://github.com/octo/widgets/pull/7" ]
  grep --quiet -- "api --method POST repos/octo/widgets/pulls --input -" "$GH_STATE/log"
  [ "$(jq -r .base "$GH_STATE/pr.json")" = main ]
  jq '.head = "feature" | .headRefOid = ""' "$GH_STATE/pr.json" >"$GH_STATE/pr.json.new"
  mv "$GH_STATE/pr.json.new" "$GH_STATE/pr.json"

  run bash "$script" check --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an amend is drift: check reports it, sync PATCHes it" {
  bash "$script" render | tail -n +3 >"$BATS_TEST_TMPDIR/body"
  open_pr "$(cat "$BATS_TEST_TMPDIR/body")"
  git commit --quiet --amend --message "Add the notes file" --message "Now one paragraph."

  run bash "$script" check --quiet
  [ "$status" -eq 1 ]
  [ -z "$output" ]

  run bash "$script" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"has drifted"*"render: Add the notes file"* ]]

  run bash "$script" sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"synced https://github.com/octo/widgets/pull/7"* ]]
  [ "$(jq -r .title "$GH_STATE/pr.json")" = "Add the notes file" ]
}

@test "a body edited by hand is refused with exit 3, and --force overwrites it" {
  open_pr "Written by a reviewer."
  run bash "$script" sync
  [ "$status" -eq 3 ]
  [[ "$output" == *"no pr-body marker and isn't what an older tool generated"* ]]
  [ "$(jq -r .body "$GH_STATE/pr.json")" = "Written by a reviewer." ]

  run bash "$script" sync --force
  [ "$status" -eq 0 ]
  [[ "$(jq -r .body "$GH_STATE/pr.json")" == "The notes list"* ]]
}

@test "a fixup! commit in the range is refused" {
  git commit --quiet --allow-empty --message "fixup! Add the notes"
  run bash "$script" render
  [ "$status" -eq 2 ]
  [[ "$output" == *"is a fixup! commit"* ]]
}

@test "several commits without a reason exit 4 by default" {
  git commit --quiet --allow-empty --message "Second change"
  open_pr "x"
  run bash "$script" check
  [ "$status" -eq 4 ]
  [[ "$output" == *"github-hygiene-single-commit-pull-requests"*"git rebase --autosquash origin/main"* ]]
  run bash "$script" render
  [ "$status" -eq 4 ]
  [[ "$output" == *"no commit carries a \`Multi-commit:\` reason"* ]]
}

@test "warn prints the policy message and goes on; allow says nothing" {
  git commit --quiet --allow-empty --message "Second change"
  open_pr "x"
  mkdir -p .agents/skills
  printf -- '- Multiple commits: warn\n' >.agents/skills/github-hygiene-single-commit-pull-requests.preferences.md
  run bash "$script" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"this range holds 2 commits"* ]]

  printf -- '- Multiple commits: allow\n' >.agents/skills/github-hygiene-single-commit-pull-requests.preferences.md
  run bash "$script" check
  [ "$status" -eq 1 ]
  [[ "$output" != *"this range holds"* ]]
}

@test "the commit carrying Multi-commit allows the range and leads the body" {
  git commit --quiet --allow-empty --message "Second change" --message "Why the pair." \
    --message "Multi-commit: refactor-split"
  open_pr "x"
  run bash "$script" check
  [ "$status" -eq 1 ]
  [[ "$output" != *"this range holds"* ]]
  run bash "$script" render
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Second change" ]
  [[ "$output" == *$'Why the pair.\n\n## Commits (2)\n\n- [`'* ]]
  [[ "$output" != *"Multi-commit"* ]]
  # Each commit is its linked SHA and subject; its message stays in it.
  [[ "$output" != *"<details>"* ]]
  [[ "$output" != *"The notes list three things"* ]]
}

@test "check warns about a sentence listing three or more items, and the exit code stays" {
  git commit --quiet --amend --message "Add the notes" \
    --message "It covers the reader, the writer, the queue and the cache."
  bash "$script" render | tail -n +3 >"$BATS_TEST_TMPDIR/body"
  open_pr "$(cat "$BATS_TEST_TMPDIR/body")"
  run bash "$script" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"lists three or more items in one sentence"*"writing-hygiene-prose-to-lists"*'"It covers the reader, the writer, the queue and the cache."'* ]]

  mkdir -p .agents/skills
  printf -- '- Prose list warning: off\n' >.agents/skills/github-hygiene-pull-request-mirrors-commit.preferences.md
  run bash "$script" check
  [ "$status" -eq 0 ]
  [[ "$output" != *"lists three or more items"* ]]
}

@test "check stays quiet about a list, an address, a number and a code span" {
  git commit --quiet --amend --file - <<'EOF'
Add the notes

It ships to 1 Main St, Springfield, IL 62701. It reads 1,024,000 rows
of 2,048 columns and 1,024 pages. It calls `f(a, b, c and d)`. It
covers:

- the reader, the writer, the queue and the cache
EOF
  run bash "$script" check
  [ "$status" -eq 0 ]
  [[ "$output" != *"lists three or more items"* ]]
}

@test "check warns when a multi-commit synthesis repeats a commit's body" {
  git commit --quiet --allow-empty --message "Second change" \
    --message "Why the two share a pull request." --message "Multi-commit: refactor-split"
  run bash "$script" check
  [[ "$output" != *"repeats a commit's message"* ]]

  git commit --quiet --amend --allow-empty --message "Second change" \
    --message "The notes list three things, wrapped here at a narrow width so
the body has to be unwrapped; \`notes.txt:2-3\` are the last two." --message "Multi-commit: refactor-split"
  run bash "$script" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"the synthesis repeats a commit's message"*"name a commit by its subject"* ]]
}

@test "a body the old script or gh pr create --fill wrote is safe to re-sync" {
  open_pr "$(git log -1 --format=%b)"
  run bash "$script" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"generated by the old create-or-update-pull-request.sh or gh pr create --fill: safe to re-sync"* ]]
  run bash "$script" sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"synced "* ]]

  git commit --quiet --allow-empty --message "Second change" --message "Multi-commit: refactor-split"
  open_pr $'- Add the notes\n- Second change'
  run bash "$script" sync
  [ "$status" -eq 0 ]
  [[ "$(jq -r .body "$GH_STATE/pr.json")" == *"## Commits (2)"* ]]
}

@test "a stacked branch names its parent" {
  git switch --quiet --create stacked
  git commit --quiet --allow-empty --message "On top"
  jq -n '{number: 41, title: "Add the notes", head: "feature", base: "main",
    html_url: "https://github.com/octo/widgets/pull/41"}' >"$GH_STATE/parent.json"
  run bash "$script" render --base feature
  [ "$status" -eq 0 ]
  [[ "$output" == *'Stacks on octo/widgets#41 "Add the notes"'* ]]
}

# A pull request for branch `stacked`, based on `feature`, whose own pull
# request (#41, based on main) is open; the body is in sync.
stacked_pr() {
  jq -n '{number: 41, title: "Add the notes", head: "feature", base: "main",
    html_url: "https://github.com/octo/widgets/pull/41"}' >"$GH_STATE/parent.json"
  git switch --quiet --create stacked
  git commit --quiet --allow-empty --message "On top"
  bash "$script" render --base feature | tail -n +3 >"$BATS_TEST_TMPDIR/body"
  jq -n --arg head "$(git rev-parse HEAD)" --rawfile body "$BATS_TEST_TMPDIR/body" \
    '{number: 7, html_url: "https://github.com/octo/widgets/pull/7", title: "On top",
      body: ($body | rtrimstr("\n")), head: "stacked", base: "feature", headRefOid: $head}' >"$GH_STATE/pr.json"
}

@test "check reports a pull request on another branch outside a stack" {
  stacked_pr
  run bash "$script" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"isn't in a linked GitHub stack"*"gh stack link 41 7"* ]]
  [[ "$output" != *"has drifted"* ]]

  echo '[{"number": 3, "open": true, "pull_requests": [{"number": 41}, {"number": 7}]}]' >"$GH_STATE/stacks.json"
  run bash "$script" check
  [ "$status" -eq 0 ]
  [[ "$output" == "in sync: "* ]]
}

@test "sync links the chain into a stack, bottom to top" {
  stacked_pr
  run bash "$script" sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"linked stack: #41 #7"* ]]
  grep --quiet --line-regexp -- "stack link 41 7" "$GH_STATE/log"
  run bash "$script" check --quiet
  [ "$status" -eq 0 ]
}

@test "sync says how to link when gh stack link fails" {
  stacked_pr
  touch "$GH_STATE/stack-link-fails"
  run bash "$script" sync
  [ "$status" -eq 1 ]
  [[ "$output" == *"couldn't link the stack"*"gh stack link 41 7"* ]]
}

@test "a chain whose branch below has no open pull request can't be linked" {
  stacked_pr
  rm "$GH_STATE/parent.json"
  run bash "$script" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ends at feature, which has no open pull request"* ]]
}
