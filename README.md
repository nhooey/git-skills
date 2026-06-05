# git-skills

[![built with garnix](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fgarnix.io%2Fapi%2Fbadges%2Fnhooey%2Fgit-skills)](https://garnix.io/repo/nhooey/git-skills)

A collection of small, opinionated [Agent Skills](https://www.anthropic.com/engineering/agent-skills) for Git and GitHub workflows, compatible with Claude Code, Codex, Gemini CLI, Cursor, and the `npx skills` / `gh skill` CLIs.

Each rule lives in its own skill so you can pick and choose. Skills are grouped by lexical prefix:

- `git-hygiene-*` — local style rules (commit format, branch naming, `.gitignore`, force-push safety, SSH remotes)
- `git-workflow-*` — interactive / multi-step procedures (inspect-before-commit, curate unpushed history, post-merge cleanup, push-mode choice)
- `github-hygiene-*` — PR-shape discipline + `gh` CLI gotchas
- `github-policy-*` — one-time repo configuration (branch ruleset, codeowners, auto-delete, merge-commits-only)
- `github-pull-request-*` — PR lifecycle including the agent-driven watcher / status-line / changeset-prompt

Each skill belongs to exactly one pack — the second segment of the name is the pack. Skills that only make sense when an LLM is driving the session carry the `agent` tag (see [Tag vocabulary](#tag-vocabulary)); filter by tag, not by name prefix.

## Install

```sh
# via npx — installs all skills
npx skills add nhooey/git-skills

# via gh CLI extension
gh skill install nhooey/git-skills

# manually
git clone https://github.com/nhooey/git-skills.git
cp -r git-skills/skills/* ~/.claude/skills/
```

### Install via Nix flake

The top-level flake aggregates every skill; each skill directory is *also* its own flake, so you can install one without pulling the others.

The default `nix run` is a **read-only preview** — it lists what would be installed and where, without touching your filesystem. To actually install, use the explicit `#install` app.

```sh
# Preview what would be installed (no side effects)
nix run github:nhooey/git-skills
nix run 'github:nhooey/git-skills?dir=skills/git-hygiene-push-force-safely'

# Actually install
nix run github:nhooey/git-skills#install                              # all skills
nix run 'github:nhooey/git-skills?dir=skills/git-hygiene-push-force-safely#install'   # just one

# Or build a derivation containing the skill files (no install side-effect)
nix build github:nhooey/git-skills#all                  # every skill, symlinkJoined
nix build github:nhooey/git-skills#git-hygiene-push-force-safely # one skill
nix build github:nhooey/git-skills#agent-skills-git-all         # a curated subset (see below)
```

The installer copies into `$CLAUDE_SKILLS_DIR` if set, otherwise `~/.claude/skills/`. Existing skill directories with the same name are replaced.

Each skill derivation produces `$out/share/claude-skills/<name>/` containing `SKILL.md`, so you can wire skills into a Home Manager module or NixOS configuration without using the installer.

## Starter packs

Curated subsets exposed as flake packages. Build a pack the same way as a single skill.

Five prefix packs partition the 21 skills — each skill is a member of exactly one. The two `*-all` packs are aggregate roll-ups and overlap with the prefix packs by design.

| Pack | Contents | Why |
| --- | --- | --- |
| `agent-skills-git-hygiene` | All 7 `git-hygiene-*` skills | Local style rules: commit format, branch naming, gitignore, no-history-in-code, conventional commits, safe force-push, SSH remotes. |
| `agent-skills-git-workflow` | All 4 `git-workflow-*` skills | Interactive procedures: inspect-before-commit, curate unpushed history, post-merge cleanup, push-mode choice. |
| `agent-skills-git-all` | All 11 `git-*` skills | Everything local. |
| `agent-skills-github-hygiene` | All 2 `github-hygiene-*` skills | PR-mirrors-commit discipline + `gh` CLI gotchas. |
| `agent-skills-github-policy` | All 4 `github-policy-*` skills | Branch ruleset, auto-delete, codeowners, merge-commits-only. |
| `agent-skills-github-pull-request` | All 4 `github-pull-request-*` skills | PR lifecycle: changeset-prompt, stacked-PR workflow, status-line, background watcher. |
| `agent-skills-github-all` | All 10 `github-*` skills (including the three `agent`-tagged ones) | Everything GitHub. |
| `all` | Every skill in the repo | The default `mkAllSkillsFlake` aggregator. |

```sh
nix build github:nhooey/git-skills#agent-skills-git-hygiene
nix run github:nhooey/git-skills#agent-skills-github-policy    # (no install, just build)
```

## Skills in this repo

One section per pack. The three skills tagged `agent` (only meaningful when an LLM is driving) live under `github-pull-request-*`; filter by tag if a human reads this without an agent.

### `git-hygiene-*` — local style rules

| Name | Tags | What |
| --- | --- | --- |
| [git-hygiene-branch-naming](skills/git-hygiene-branch-naming) | style | Long, descriptive, dash-separated, autocomplete-friendly names. |
| [git-hygiene-commit-message-format](skills/git-hygiene-commit-message-format) | style | Subject under 72 chars, blank line, body wrapped at 72, explain WHY not what. |
| [git-hygiene-conventional-commits](skills/git-hygiene-conventional-commits) | style, team-stance | `type(scope): subject` Conventional Commits format. |
| [git-hygiene-gitignore](skills/git-hygiene-gitignore) | style | Anchor paths, keep personal preferences in `~/.gitignore_global`, compress patterns safely. |
| [git-hygiene-no-history-in-code](skills/git-hygiene-no-history-in-code) | style | Don't embed "added in v3.2" notes in source — put them in commit messages. |
| [git-hygiene-push-force-safely](skills/git-hygiene-push-force-safely) | safety | Always force-push with `--force-with-lease`, never plain `--force`. |
| [git-hygiene-ssh-remotes](skills/git-hygiene-ssh-remotes) | setup, style | Prefer SSH (`git@github.com:owner/repo.git`) over HTTPS. |

### `git-workflow-*` — interactive procedures

| Name | Tags | What |
| --- | --- | --- |
| [git-workflow-cleanup-merged-branches](skills/git-workflow-cleanup-merged-branches) | workflow, interactive | Delete merged branches; ask before bulk-cleaning stragglers. |
| [git-workflow-curate-unpushed](skills/git-workflow-curate-unpushed) | workflow, style | Squash noise commits + amend forward to curate unpushed history. |
| [git-workflow-inspect-before-commit](skills/git-workflow-inspect-before-commit) | workflow | `git status` / `git diff` / `git diff --cached` before every commit; catch secrets, debug logging, format churn. |
| [git-workflow-push-mode](skills/git-workflow-push-mode) | workflow, interactive, team-stance | Ask once per repo per session: direct-to-main / PRs-always / ask-each-time. |

### `github-hygiene-*` — PR-shape discipline + `gh` gotchas

| Name | Tags | What |
| --- | --- | --- |
| [github-hygiene-gh-cli-gotchas](skills/github-hygiene-gh-cli-gotchas) | reference | Known `gh` CLI traps: `pr edit` exit 1, `--json merged` invalid, self-approval blocked, branch rename closes PRs. |
| [github-hygiene-pull-request-mirrors-commit](skills/github-hygiene-pull-request-mirrors-commit) | workflow, style, team-stance | One commit per PR; title = subject, body = body (unwrapped via `fmt -w 2500`); re-sync after every amend. |

### `github-policy-*` — one-time repo configuration

| Name | Tags | What |
| --- | --- | --- |
| [github-policy-auto-delete-merged-branches](skills/github-policy-auto-delete-merged-branches) | setup | Enable `delete_branch_on_merge`. |
| [github-policy-codeowners](skills/github-policy-codeowners) | setup | `.github/CODEOWNERS` + `require_code_owner_review` for multi-contributor repos. |
| [github-policy-merge-commits-only](skills/github-policy-merge-commits-only) | setup, team-stance | Disable squash + rebase merges; every PR lands as a merge commit. |
| [github-policy-protect-default-branch](skills/github-policy-protect-default-branch) | setup, safety | Rulesets-API protection: require PR, status checks, block force-push, block deletion. |

### `github-pull-request-*` — PR lifecycle (includes agent-tagged trio)

| Name | Tags | What |
| --- | --- | --- |
| [github-pull-request-changeset-prompt](skills/github-pull-request-changeset-prompt) | agent, interactive | Multi-select `AskUserQuestion` after every change-set: Stage/Commit/Amend/Push/Force/Open-PR/Re-derive/Monitor. |
| [github-pull-request-stacked](skills/github-pull-request-stacked) | workflow, team-stance, reference | Submit dependent PRs on GitHub. Repo you control: `gt submit --stack`, merge bottom-first, `gt sync`. Upstream fork-only: draft + `Depends on`. Upstream with topic-branch push grant: full `gt submit --stack`. |
| [github-pull-request-status-line](skills/github-pull-request-status-line) | agent, style | Surface PRs as `<status-circle> <url> — **PR #<num>: <title>**` with live state. |
| [github-pull-request-watcher](skills/github-pull-request-watcher) | agent, workflow | Background Monitor polling PR check-runs/comments/state; one reaction per event type. |

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

To make a new skill installable via Nix in isolation, drop a `flake.nix` into the skill folder modeled on `skills/git-hygiene-push-force-safely/flake.nix`. The top-level flake auto-discovers any subdirectory of `skills/` that contains a `SKILL.md`, so the aggregate package picks up new skills without further changes. If the new skill belongs in a starter pack, add its name to the pack's list in the top-level `flake.nix`.
