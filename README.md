# skills-git

A collection of small, opinionated [Agent Skills](https://www.anthropic.com/engineering/agent-skills) for Git and GitHub workflows, compatible with Claude Code, Codex, Gemini CLI, Cursor, and the `npx skills` / `gh skill` CLIs.

Each rule lives in its own skill so you can pick and choose. Skills are grouped by lexical prefix:

- `git-*` — local-only git hygiene (commit messages, history, branches, `.gitignore`, remotes)
- `github-*` — GitHub-side repository hygiene + PR lifecycle (rulesets, merge settings, PR-mirrors-commit, agent PR-watcher / status-line / changeset-prompt)

Skills that are only meaningful when an LLM is driving the session are tagged `agent` (see the [Tag vocabulary](#tag-vocabulary) section). Filter by tag, not by name prefix.

## Install

```sh
# via npx — installs all skills
npx skills add nhooey/skills-git

# via gh CLI extension
gh skill install nhooey/skills-git

# manually
git clone https://github.com/nhooey/skills-git.git
cp -r skills-git/skills/* ~/.claude/skills/
```

### Install via Nix flake

The top-level flake aggregates every skill; each skill directory is *also* its own flake, so you can install one without pulling the others.

The default `nix run` is a **read-only preview** — it lists what would be installed and where, without touching your filesystem. To actually install, use the explicit `#install` app.

```sh
# Preview what would be installed (no side effects)
nix run github:nhooey/skills-git
nix run 'github:nhooey/skills-git?dir=skills/git-push-force-safely'

# Actually install
nix run github:nhooey/skills-git#install                              # all skills
nix run 'github:nhooey/skills-git?dir=skills/git-push-force-safely#install'   # just one

# Or build a derivation containing the skill files (no install side-effect)
nix build github:nhooey/skills-git#all                  # every skill, symlinkJoined
nix build github:nhooey/skills-git#git-push-force-safely # one skill
nix build github:nhooey/skills-git#git-pack-minimal     # a curated subset (see below)
```

The installer copies into `$CLAUDE_SKILLS_DIR` if set, otherwise `~/.claude/skills/`. Existing skill directories with the same name are replaced.

Each skill derivation produces `$out/share/claude-skills/<name>/` containing `SKILL.md`, so you can wire skills into a Home Manager module or NixOS configuration without using the installer.

## Starter packs

Curated subsets exposed as flake packages. Build a pack the same way as a single skill:

| Pack | Contents | Why |
| --- | --- | --- |
| `git-pack-minimal` | `git-commit-message-format`, `git-push-force-safely`, `git-gitignore-discipline`, `git-ssh-remotes` | Near-universally-good git rules. Skips stylistic and team-stance choices. |
| `git-pack-all` | All 11 `git-*` skills | Everything local. |
| `github-pack-setup` | `github-protect-default-branch`, `github-auto-delete-merged-branches`, `github-codeowners` | Apply once per repo at creation. |
| `github-pack-all` | All 9 `github-*` skills (including the three `agent`-tagged ones) | Everything GitHub. |
| `agent-pack` | `github-pr-watcher`, `github-pr-status-line`, `github-changeset-prompt` | The purely agent-behavior skills. Only meaningful when an LLM is driving. |
| `all` | Every skill in the repo | The default `mkAllSkillsFlake` aggregator. |

```sh
nix build github:nhooey/skills-git#git-pack-minimal
nix run github:nhooey/skills-git#agent-pack    # (no install, just build)
```

## Skills in this repo

### `git-*` — local git hygiene

| Name | Tags | What |
| --- | --- | --- |
| [git-commit-message-format](skills/git-commit-message-format) | style | Subject under 72 chars, blank line, body wrapped at 72, explain WHY not what. |
| [git-conventional-commits](skills/git-conventional-commits) | style, team-stance | `type(scope): subject` Conventional Commits format. |
| [git-inspect-before-commit](skills/git-inspect-before-commit) | workflow | `git status` / `git diff` / `git diff --cached` before every commit; catch secrets, debug logging, format churn. |
| [git-no-history-in-code](skills/git-no-history-in-code) | style | Don't embed "added in v3.2" notes in source — put them in commit messages. |
| [git-clean-local-history](skills/git-clean-local-history) | workflow, style | Squash noise commits + amend forward to curate unpushed history. |
| [git-push-force-safely](skills/git-push-force-safely) | safety | Always force-push with `--force-with-lease`, never plain `--force`. |
| [git-branch-naming](skills/git-branch-naming) | style | Long, descriptive, dash-separated, autocomplete-friendly names. |
| [git-cleanup-merged-branches](skills/git-cleanup-merged-branches) | workflow, interactive | Delete merged branches; ask before bulk-cleaning stragglers. |
| [git-gitignore-discipline](skills/git-gitignore-discipline) | style | Anchor paths, keep personal preferences in `~/.gitignore_global`, compress patterns safely. |
| [git-ssh-remotes](skills/git-ssh-remotes) | setup, style | Prefer SSH (`git@github.com:owner/repo.git`) over HTTPS. |
| [git-push-workflow-mode](skills/git-push-workflow-mode) | workflow, interactive, team-stance | Ask once per repo per session: direct-to-main / PRs-always / ask-each-time. |

### `github-*` — GitHub repo hygiene and PR lifecycle

| Name | Tags | What |
| --- | --- | --- |
| [github-protect-default-branch](skills/github-protect-default-branch) | setup, safety | Rulesets-API protection: require PR, status checks, block force-push, block deletion. |
| [github-auto-delete-merged-branches](skills/github-auto-delete-merged-branches) | setup | Enable `delete_branch_on_merge`. |
| [github-merge-commits-only](skills/github-merge-commits-only) | setup, team-stance | Disable squash + rebase merges; every PR lands as a merge commit. |
| [github-codeowners](skills/github-codeowners) | setup | `.github/CODEOWNERS` + `require_code_owner_review` for multi-contributor repos. |
| [github-gh-cli-gotchas](skills/github-gh-cli-gotchas) | reference | Known `gh` CLI traps: `pr edit` exit 1, `--json merged` invalid, self-approval blocked, branch rename closes PRs. |
| [github-pr-mirrors-commit](skills/github-pr-mirrors-commit) | workflow, style, team-stance | One commit per PR; title = subject, body = body (unwrapped via `fmt -w 2500`); re-sync after every amend. |

### `agent`-tagged `github-*` — agent-behavior skills

These three skills only make sense when an LLM is driving the session. They live under the `github-*` prefix like any other GitHub skill, but carry the `agent` tag so non-agent users can filter them out.

| Name | Tags | What |
| --- | --- | --- |
| [github-pr-watcher](skills/github-pr-watcher) | agent, workflow | Background Monitor polling PR check-runs/comments/state; one reaction per event type. |
| [github-pr-status-line](skills/github-pr-status-line) | agent, style | Surface PRs as `<status-circle> <url> — **PR #<num>: <title>**` with live state. |
| [github-changeset-prompt](skills/github-changeset-prompt) | agent, interactive | Multi-select `AskUserQuestion` after every change-set: Stage/Commit/Amend/Push/Force/Open-PR/Re-derive/Monitor. |

## Tag vocabulary

Each skill carries 1–3 tags in its frontmatter. The vocabulary is intentionally small so the filter signal stays useful:

| Tag | Means |
| --- | --- |
| `agent` | Only meaningful when an LLM/agent is driving. A human reading a manpage would have no use for it. |
| `workflow` | Multi-step procedure or state machine; tells you *when* to do things. |
| `interactive` | Will pop an `AskUserQuestion` / prompt the user mid-task. |
| `setup` | One-time configuration (vs. per-action behavior). |
| `reference` | Passive lookup material; no behavior change on load. |
| `safety` | Guards against irreversible / destructive mistakes. |
| `style` | Convention or aesthetics; near-universally-good practice. |
| `team-stance` | A real opinion where another team might legitimately choose differently. Read carefully before adopting. |

Filter for the kind of skill you want:

- "I just want safe defaults" → `safety`, `style`
- "I don't want skills that prompt me" → avoid `interactive`
- "I want one-time repo setup" → `setup`
- "I'm not running an agent" → skip everything tagged `agent`

## Adding a new skill

Each skill lives in its own folder under `skills/`, named with `lowercase-with-hyphens`. The folder must contain a `SKILL.md` whose YAML frontmatter `name` field matches the folder name.

```
skills/
└── my-skill/
    ├── SKILL.md          # required — frontmatter + instructions
    ├── flake.nix         # optional — for standalone installation
    └── flake.lock        # optional — pinned inputs
```

The frontmatter requires three fields:

```yaml
---
name: my-skill
description: What the skill does, and when the model should invoke it.
tags: [style]
---
```

Write the `description` so an agent can decide whether to invoke the skill from that one line — describe both *what it does* and *when to use it*. Pick `tags` from the vocabulary above.

To make a new skill installable via Nix in isolation, drop a `flake.nix` into the skill folder modeled on `skills/git-push-force-safely/flake.nix`. The top-level flake auto-discovers any subdirectory of `skills/` that contains a `SKILL.md`, so the aggregate package picks up new skills without further changes. If the new skill belongs in a starter pack, add its name to the pack's list in the top-level `flake.nix`.
