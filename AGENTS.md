# git-skills

Agent Skills for Git and GitHub workflows.
Each skill is a directory under `skills/` holding a `SKILL.md`, its own `flake.nix`, and any scripts it bundles; the root `flake.nix` aggregates them into packages and packs.
`README.md` describes the packs and how users install the skills.

## Build and test

`nix develop` enters the dev shell, installs skillspkgs' `skill-collections` combination (taken in `skills-devshell/flake.nix`, with no additions) into `.agents/skills/`, and prints `menu`, which lists every command below with a line of help.

- `check` runs `nix flake check`: every flake output, formatting, the skills' tests and `git-skills lint`.
  It must pass before a change is done.
- `fmt` formats Nix, shell and YAML files with treefmt.
- `git-skills test [--language LANGUAGE] [SKILL...]` runs the tests in `tests/`, or those of the named skills, with each language's own tool: `pytest` for Python, `bats` for `.bats` files, and `bb test` in a folder holding a `bb.edn` for Babashka's `clojure.test` tests.
  `--language` is `python`, `bats` or `clojure`.
  `check` runs the same command once per language.
- `git-skills lint [SKILL...]` checks that each folder name is lowercase-with-hyphens under a pack prefix, and that `SKILL.md`'s frontmatter has a `name` matching the folder, a `description`, and `tags` from the README's tag vocabulary.

## Tests

A skill's folder holds only what an installed skill runs. Its tests are
in `tests/<skill>/`, and `git-skills test` picks up a new one there with
no further wiring:

- Python: a `test_*.py` file, run by pytest. It finds the skill's
  scripts through `tests/skill_scripts.py`: `scripts_dir(skill)` for
  their folder and `load_script(skill, filename)` to import a script
  whose name has a dash. Tests may use pytest and any library listed in
  the flake's `testPython`; the skills' own Python scripts import only
  the standard library.
- Shell: a `.bats` file, which reaches the skill's scripts through
  `$BATS_TEST_DIRNAME/../../skills/<skill>/scripts/`.
- Babashka: a `bb.edn` whose `test` task runs the tests, with the
  skill's `scripts/src` on its `:paths`.

`tests/test_layout.py` fails when a test file or folder sits under
`skills/`, when a folder in `tests/` names no skill, or when a skill's
Python script imports anything but the standard library and its sibling
scripts. The repository's own tools in `scripts/` have their tests at
the top of `tests/`, a `.bats` file reaching them through
`$BATS_TEST_DIRNAME/../scripts/`:

- `tests/test_git_skills.py`: the lint, which needs `yq` (yq-go) on
  PATH, as the dev shell and `git-skills` have it.
- `tests/git-skills.bats`: `git-skills test`, `scripts/git-skills.sh`.
- `tests/copy-hook-scripts.bats`: how the hooks plugin's scripts are
  copied in.
