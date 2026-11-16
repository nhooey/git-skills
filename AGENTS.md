# git-skills

Agent Skills for Git and GitHub workflows. Each skill is a directory under
`skills/` holding a `SKILL.md`, its own `flake.nix`, and any scripts it
bundles; the root `flake.nix` aggregates them into packages and packs.
`README.md` describes the packs and how users install the skills.

## Build and test

`nix develop` enters the dev shell, installs its skills (listed in
`skills-devshell/flake.nix`) into `.agents/skills/`, and prints `menu`,
which lists every command below with a line of help.

- `check` runs `nix flake check`: every flake output, formatting, the
  skills' tests and `git-skills lint`. It must pass before a change is
  done.
- `fmt` formats Nix, shell and YAML files with treefmt.
- `git-skills test [SKILL...]` runs the standard-library `unittest`
  suites beside a skill's scripts (`scripts/test_*.py`). A new suite is
  picked up by it and by `check` without further wiring.
- `git-skills lint [SKILL...]` checks that each folder name is
  lowercase-with-hyphens under a pack prefix, and that `SKILL.md`'s
  frontmatter has a `name` matching the folder, a `description`, and
  `tags` from the README's tag vocabulary.
- `git-skills list [--tested]` prints the skills.
