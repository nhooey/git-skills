#!/usr/bin/env bats
# scripts/copy-hook-scripts.sh run as the flake's `hooks-plugin` postPatch
# runs it: in a plugin's source folder, on a folder of links like the
# flake's `hookFiles`, to read-only files as in the Nix store.

setup() {
  script="$BATS_TEST_DIRNAME/../scripts/copy-hook-scripts.sh"
  store="$BATS_TEST_TMPDIR/store"
  files="$BATS_TEST_TMPDIR/files"
  plugin="$BATS_TEST_TMPDIR/plugin"
  mkdir -p "$store/src/pr_body" "$files" "$plugin"
  printf '#!/usr/bin/env bash\necho hook\n' >"$store/hook.sh"
  printf '{:paths ["src"]}\n' >"$store/bb.edn"
  printf '(ns pr-body.main)\n' >"$store/src/pr_body/main.clj"
  chmod -R a-w "$store"
  ln -s "$store/hook.sh" "$files/hook.sh"
  ln -s "$store/bb.edn" "$files/bb.edn"
  ln -s "$store/src" "$files/src"
  cd "$plugin"
}

teardown() {
  chmod -R u+w "$store"
}

@test "it copies every file, folders and all, as writable files" {
  run bash "$script" "$files" /tools/bin
  [ "$status" -eq 0 ]
  [ ! -L scripts/hook.sh ]
  [ ! -L scripts/src ]
  [ "$(cat scripts/bb.edn)" = '{:paths ["src"]}' ]
  [ "$(cat scripts/src/pr_body/main.clj)" = "(ns pr-body.main)" ]
  [ -w scripts/src/pr_body/main.clj ]
}

@test "it puts the tools first on each Bash script's PATH, after the shebang" {
  run bash "$script" "$files" /tools/bin:/more/bin
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p scripts/hook.sh)" = "#!/usr/bin/env bash" ]
  # shellcheck disable=SC2016 # the line is compared literally
  [ "$(sed -n 2p scripts/hook.sh)" = 'PATH=/tools/bin:/more/bin${PATH:+:$PATH}; export PATH' ]
  [ "$(sed -n 3p scripts/hook.sh)" = "echo hook" ]
  [ "$(cat scripts/bb.edn)" = '{:paths ["src"]}' ]
}

@test "a copied script runs with the tools first on its PATH" {
  printf '#!/usr/bin/env bash\necho "$PATH"\n' >"$BATS_TEST_TMPDIR/path.sh"
  ln -s "$BATS_TEST_TMPDIR/path.sh" "$files/path.sh"
  bash "$script" "$files" /tools/bin
  # This bash by its path: a sandbox may have no bash in /usr/bin or /bin.
  run env PATH=/usr/bin:/bin "$BASH" scripts/path.sh
  [ "$output" = /tools/bin:/usr/bin:/bin ]
}
