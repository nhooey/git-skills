# git-skills

Agent Skills for Git and GitHub workflows. Each skill is a directory under
`skills/` holding a `SKILL.md`, its own `flake.nix`, and any scripts it
bundles; the root `flake.nix` aggregates them into packages and packs.
`README.md` describes the packs and how users install the skills.

## Build and test

- `nix flake check` evaluates every flake output and checks formatting. It
  must pass before a change is done.
- `nix fmt` formats Nix, shell and YAML files with treefmt.
- A skill's Python scripts have standard-library `unittest` tests beside
  them: `python3 -m unittest discover -s skills/<skill>/scripts`.
- `nix develop` installs the dev shell's skills, listed in
  `skills-devshell/flake.nix`, into `.agents/skills/`.
