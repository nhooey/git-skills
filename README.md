# skills-git

A collection of [Agent Skills](https://www.anthropic.com/engineering/agent-skills) for Git and GitHub workflows, compatible with Claude Code, Codex, Gemini CLI, Cursor, and the `npx skills` / `gh skill` CLIs.

## Install

```sh
# via npx
npx skills add nhooey/skills-git

# via gh CLI extension
gh skill install nhooey/skills-git

# manually
git clone https://github.com/nhooey/skills-git.git
cp -r skills-git/skills/* ~/.claude/skills/
```

### Install via Nix flake

The repo is also a Nix flake. The top-level flake aggregates every skill; each skill directory is *also* its own flake, so you can install one without pulling the others.

The default `nix run` is a **read-only preview** — it lists what would be installed and where, without touching your filesystem. To actually install, use the explicit `#install` app.

```sh
# Preview what would be installed (no side effects)
nix run github:nhooey/skills-git
nix run 'github:nhooey/skills-git?dir=skills/github'

# Actually install
nix run github:nhooey/skills-git#install                       # all skills
nix run 'github:nhooey/skills-git?dir=skills/github#install'   # just one

# Or build a derivation containing the skill files (no install side-effect)
nix build github:nhooey/skills-git#all       # all skills, symlinkJoined
nix build github:nhooey/skills-git#github    # one skill
```

The installer copies into `$CLAUDE_SKILLS_DIR` if set, otherwise `~/.claude/skills/`. Existing skill directories with the same name are replaced.

Each skill derivation produces `$out/share/claude-skills/<name>/` containing `SKILL.md` (and `references/` / `scripts/` if the skill ships them), so you can also wire skills into a Home Manager module or NixOS configuration without using the installer.

## Skills in this repo

| Name | Description | Link |
| --- | --- | --- |
| git | Opinionated Git hygiene — commit messages, history cleanliness, force-push safety, branch naming, `.gitignore` discipline, SSH remotes. | [skills/git](skills/git) |
| github | GitHub repo hygiene — protect the default branch, require PRs, block force-pushes and deletions, auto-delete head branches after merge. | [skills/github](skills/github) |

## Adding a new skill

Each skill lives in its own folder under `skills/`, named with `lowercase-with-hyphens`. The folder must contain a `SKILL.md` whose YAML frontmatter `name` field matches the folder name.

```
skills/
└── my-skill/
    ├── SKILL.md          # required — frontmatter + instructions
    ├── references/       # optional — long-form docs
    └── scripts/          # optional — executable helpers
```

The frontmatter requires two fields:

```yaml
---
name: my-skill
description: What the skill does, and when the model should invoke it.
---
```

Write the `description` so an agent can decide whether to invoke the skill from that one line — describe both *what it does* and *when to use it*.

To make a new skill installable via Nix in isolation, drop a `flake.nix` into the skill folder modeled on `skills/git/flake.nix`. The top-level flake auto-discovers any subdirectory of `skills/` that contains a `SKILL.md`, so the aggregate package picks up new skills without further changes.
