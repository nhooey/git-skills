#!/usr/bin/env bats
# The pre-push hook as a global core.hooksPath runs it: real pushes from
# a clone to a bare remote whose default branch is master, through a
# hooks folder holding a copy of the script, made executable as the
# flake package's is.

setup() {
  export GIT_CONFIG_NOSYSTEM=1 HOME="$BATS_TEST_TMPDIR/home"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/hooks"
  hook="$BATS_TEST_TMPDIR/hooks/pre-push"
  cp "$BATS_TEST_DIRNAME/../../skills/git-hygiene-push-force-safely/scripts/pre-push" "$hook"
  chmod u+x "$hook"
  git config --global user.name T
  git config --global user.email t@x
  git config --global core.hooksPath "$BATS_TEST_TMPDIR/hooks"

  cd "$BATS_TEST_TMPDIR"
  git init --quiet --bare --initial-branch master remote.git
  git clone --quiet remote.git repo 2>/dev/null
  cd repo
  git commit --quiet --allow-empty --message one
  git push --quiet origin master
  git remote set-head origin master
  git switch --quiet --create feature
  git commit --quiet --allow-empty --message two
  git push --quiet origin feature
  git switch --quiet master
}

remote_tip() { git --git-dir "$BATS_TEST_TMPDIR/remote.git" rev-parse "$1"; }

@test "a fast-forward of the default branch is allowed" {
  git commit --quiet --allow-empty --message three
  run git push origin master
  [ "$status" -eq 0 ]
  [ "$(remote_tip master)" = "$(git rev-parse master)" ]
}

@test "a rewrite of the default branch is refused" {
  before=$(remote_tip master)
  git commit --quiet --amend --allow-empty --message one-amended
  run git push --force-with-lease origin master
  [ "$status" -ne 0 ]
  [[ $output == *"refusing to rewrite master, the default branch of origin"* ]]
  [ "$(remote_tip master)" = "$before" ]
}

@test "a deletion of the default branch is refused" {
  run git push origin --delete master
  [ "$status" -ne 0 ]
  [[ $output == *"refusing to delete master, the default branch of origin"* ]]
  remote_tip master
}

@test "a rewrite of another branch is allowed" {
  git switch --quiet feature
  git commit --quiet --amend --allow-empty --message two-amended
  run git push --force-with-lease origin feature
  [ "$status" -eq 0 ]
  [ "$(remote_tip feature)" = "$(git rev-parse feature)" ]
}

@test "a deletion of another branch is allowed" {
  run git push origin --delete feature
  [ "$status" -eq 0 ]
  run remote_tip feature
  [ "$status" -ne 0 ]
}

@test "an update over a remote tip this repository lacks is refused" {
  # Another clone moves master on; this one never fetches it.
  git clone --quiet "$BATS_TEST_TMPDIR/remote.git" "$BATS_TEST_TMPDIR/other" 2>/dev/null
  git -C "$BATS_TEST_TMPDIR/other" commit --quiet --allow-empty --message elsewhere
  git -C "$BATS_TEST_TMPDIR/other" push --quiet origin master
  git commit --quiet --allow-empty --message three
  run git push --force origin master
  [ "$status" -ne 0 ]
  [[ $output == *"isn't in this repository"* ]]
}

@test "without origin/HEAD the remote's HEAD names the default branch" {
  git remote set-head origin --delete
  git commit --quiet --amend --allow-empty --message one-amended
  run git push --force origin master
  [ "$status" -ne 0 ]
  [[ $output == *"refusing to rewrite master"* ]]
}

@test "the remote's HEAD names a default branch other than master" {
  git push --quiet origin master:trunk
  git --git-dir "$BATS_TEST_TMPDIR/remote.git" symbolic-ref HEAD refs/heads/trunk
  git remote set-head origin --auto >/dev/null
  git commit --quiet --amend --allow-empty --message one-amended
  run git push --force origin master
  [ "$status" -eq 0 ]
  run git push --force origin master:trunk
  [ "$status" -ne 0 ]
  [[ $output == *"refusing to rewrite trunk"* ]]
}

@test "with no default branch known, master and main are guarded" {
  zero=0000000000000000000000000000000000000000
  sha=$(git rev-parse HEAD)
  for branch in master main; do
    run bash "$hook" nowhere nowhere <<<"refs/heads/x $zero refs/heads/$branch $sha"
    [ "$status" -ne 0 ]
    [[ $output == *"refusing to delete $branch, the default branch of nowhere"* ]]
  done
  run bash "$hook" nowhere nowhere <<<"refs/heads/x $zero refs/heads/trunk $sha"
  [ "$status" -eq 0 ]
}

@test "the repository's own pre-push hook runs with the same arguments and stdin" {
  {
    printf '#!%s\n' "$BASH"
    printf 'printf "%%s\\n" "$*" >"%s/args"\n' "$BATS_TEST_TMPDIR"
    printf 'cat >"%s/stdin"\n' "$BATS_TEST_TMPDIR"
    printf 'exit 0\n'
  } >.git/hooks/pre-push
  chmod u+x .git/hooks/pre-push
  git commit --quiet --allow-empty --message three
  run git push origin master
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/args")" = "origin $BATS_TEST_TMPDIR/remote.git" ]
  read -r local_ref local_sha remote_ref _ <"$BATS_TEST_TMPDIR/stdin"
  [ "$local_ref $local_sha $remote_ref" = "refs/heads/master $(git rev-parse master) refs/heads/master" ]
}

@test "the repository's own pre-push hook's failure fails the push" {
  printf '#!%s\necho own hook failed >&2\nexit 3\n' "$BASH" >.git/hooks/pre-push
  chmod u+x .git/hooks/pre-push
  git commit --quiet --allow-empty --message three
  before=$(remote_tip master)
  run git push origin master
  [ "$status" -ne 0 ]
  [[ $output == *"own hook failed"* ]]
  [ "$(remote_tip master)" = "$before" ]
}

@test "a refused push doesn't run the repository's own hook" {
  printf '#!%s\ntouch "%s/ran"\n' "$BASH" "$BATS_TEST_TMPDIR" >.git/hooks/pre-push
  chmod u+x .git/hooks/pre-push
  run git push origin --delete master
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}
