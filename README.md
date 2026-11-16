# git-skills

A collection of small, opinionated [Agent Skills](https://www.anthropic.com/engineering/agent-skills) for Git and GitHub workflows, compatible with Claude Code, Codex, Gemini CLI, Cursor, and the `npx skills` / `gh skill` CLIs.

Each rule lives in its own skill so you can pick and choose. Skills are grouped by lexical prefix:

- `git-hygiene-*` — local style rules (commit format, branch naming, `.gitignore`, force-push safety, SSH remotes)
- `git-workflow-*` — interactive / multi-step procedures (inspect-before-commit, curate unpushed history, branch tidying, push-mode choice)
- `github-hygiene-*` — PR-shape discipline, issue/PR references + `gh` CLI gotchas
- `github-policy-*` — one-time repo configuration (branch ruleset, codeowners, auto-delete, merge-commits-only)
- `github-workflow-*` — PR lifecycle including the agent-driven watcher / status-line / changeset-prompt, browser drafting with a rendered preview, and a user's activity on a repo

Each skill belongs to exactly one pack — the second segment of the name is the pack. Skills that only make sense when an LLM is driving the session carry the `agent` tag (see [Tag vocabulary](#tag-vocabulary)); filter by tag, not by name prefix.


## CC Safety Net rulebooks

Two [CC Safety Net](https://github.com/kenryu42/claude-code-safety-net)
rulebooks enforce `git-hygiene-avoid-sweeping-operations`, on top of CC Safety
Net's built-in git rules:

- [`.cc-safety-net/rules/git-avoid-sweeping-operations/rulebook.json`](.cc-safety-net/rules/git-avoid-sweeping-operations/rulebook.json)
  blocks a subcommand used with a sweeping flag, such as `git add -A`,
  `git commit -a`, `git push --all` and `--no-verify`. It uses rulebook
  format 1, which expands combined short options (`git commit -anm x`) and
  sees past global options (`git -C <dir> add -A`).
- [`.cc-safety-net/rules/git-avoid-sweeping-operations-with-exclusions/rulebook.json`](.cc-safety-net/rules/git-avoid-sweeping-operations-with-exclusions/rulebook.json)
  blocks a bare `git stash` and `git config --global` writes. These rules need
  `exclude_args`, so this rulebook uses format 2. Format 2 doesn't see past
  `git -C <dir>`, so `git -C repo stash` isn't caught.

Run their test fixtures with `cc-safety-net rule verify`. The dev shell
doesn't provide `cc-safety-net`, and `nix flake check` doesn't run them.

```bash
cc-safety-net rule add nhooey/git-skills --only git-avoid-sweeping-operations git-avoid-sweeping-operations-with-exclusions --global
```

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

The default `nix run` is a **read-only preview** — it lists what would be installed and where, without touching your filesystem. To actually install, use the explicit `#install` app. Every app needs `--scope`:

- `--scope=personal` — `~/.claude/skills/`
- `--scope=project` — `<project-root>/.claude/skills/`, where the project root is the nearest ancestor of the current directory holding `.git/` or `flake.nix`
- `--scope=custom --root=<path>` — `<path>`

```sh
# Preview what would be installed (no side effects)
nix run github:nhooey/git-skills -- --scope=personal
nix run 'github:nhooey/git-skills?dir=skills/git-hygiene-push-force-safely' -- --scope=personal

# Actually install
nix run github:nhooey/git-skills#install -- --scope=personal                                  # all skills
nix run github:nhooey/git-skills#install -- --scope=personal git-hygiene-push-force-safely    # just one
nix run 'github:nhooey/git-skills?dir=skills/git-hygiene-push-force-safely#install' -- --scope=personal

# Or build a derivation containing the skill files (no install side-effect)
nix build github:nhooey/git-skills#agent-skill-nhooey-git-hygiene-push-force-safely  # one skill
nix build github:nhooey/git-skills#agent-skills-nhooey-git-all                       # a pack (see below)
```

The installer links each skill into the target directory as a symlink to its store path and registers a per-user GC root so `nix-store --gc` keeps it. With `--profile` it installs each skill into your Nix profile with `nix profile install` and links to `~/.nix-profile/share/claude-skills/` instead. Pass `--help` to any app for its full options.

The flake's other apps take the same `--scope`:

| App | Does |
| --- | --- |
| `reconcile` | Installs or refreshes every skill in the flake and removes managed skills that aren't in it. |
| `uninstall` | Removes the named skills, or every skill in the flake with no names. |
| `reap` | Removes managed skills whose store paths have been garbage-collected, and orphan GC roots. |
| `purge` | Removes every skill any `agent-skill-flake` installer put in the target directory (`--dry-run` lists them first). |

`flake.reconcileScript.<system>` is the `reconcile` command line at `--scope=project`, for another flake's dev shell to run.

Each per-skill package produces `$out/share/claude-skills/<name>/` containing `SKILL.md` and the skill's bundled files, so you can wire skills into a Home Manager module or NixOS configuration without using the installer.

## Starter packs

Curated subsets exposed as flake packages. Build a pack the same way as a single skill. There's no package holding every skill; the `#install` app installs them all.

Five prefix packs partition the 25 skills — each skill is a member of exactly one. The two `*-all` packs are aggregate roll-ups and overlap with the prefix packs by design.

| Pack | Contents | Why |
| --- | --- | --- |
| `agent-skills-nhooey-git-hygiene` | All 8 `git-hygiene-*` skills | Local style rules: commit format, branch naming, gitignore, no history in tracked files, conventional commits, safe force-push, no sweeping commands, SSH remotes. |
| `agent-skills-nhooey-git-workflow` | All 4 `git-workflow-*` skills | Interactive procedures: inspect-before-commit, curate unpushed history, branch tidying, push-mode choice. |
| `agent-skills-nhooey-git-all` | All 12 `git-*` skills | Everything local. |
| `agent-skills-nhooey-github-hygiene` | All 3 `github-hygiene-*` skills | PR-mirrors-commit discipline, issue/PR references + `gh` CLI gotchas. |
| `agent-skills-nhooey-github-policy` | All 4 `github-policy-*` skills | Branch ruleset, auto-delete, codeowners, merge-commits-only. |
| `agent-skills-nhooey-github-workflow` | All 6 `github-workflow-*` skills | PR lifecycle: changeset-prompt, stacked-PR workflow, status-line, background watcher; drafting in the browser; a user's activity on a repo. |
| `agent-skills-nhooey-github-all` | All 13 `github-*` skills (including the four `agent`-tagged ones) | Everything GitHub. |

```sh
nix build github:nhooey/git-skills#agent-skills-nhooey-git-hygiene
```

## Hooks plugin

The skills' Claude Code hooks ship as one hooks-only plugin, `git-skills-hooks`, built by the flake package `hooks-plugin`. A plugin hook runs in every session and inside subagents, whether or not its skill is loaded.

| Hook | Event | Skill | Does |
| --- | --- | --- | --- |
| `pull-request-sync-check.sh` | `PostToolUse` on `Bash` | `github-hygiene-pull-request-mirrors-commit` | After `git commit --amend` or `git push`, flags an open PR whose title or body differs from HEAD's commit. |

```sh
nix build github:nhooey/git-skills#hooks-plugin
```

The plugin's manifest and `hooks/hooks.json` live in [`plugin/`](plugin), not at the repository root, so the plugin doesn't load `skills/` a second time under a namespaced name. Each hook script stays in its skill's `scripts/`, where the skill documents it and the checks test it.

To add a skill's hook:

1. Add the script's path to `hookScripts` in `flake.nix`; the package copies it into the plugin's `scripts/`.
2. Add its entry to `plugin/hooks/hooks.json`, running it as `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<name>"`: a store file has no executable bit to rely on.
3. Keep it fast: every session runs it on every matching tool call, so it exits at once, in well under 50 ms, when the call isn't one it acts on. `nix flake check` checks `hooks.json` and runs each `Bash` hook on a command it should ignore.
4. Give a blocking hook (one that denies or asks) a setting that turns it down to a reminder or off, read from its skill's preferences file: `<skill>.preferences.md` beside the skill's folder for the user, and `.agents/skills/<skill>.preferences.md` in the project, as `coding-agent-skill-references` describes. A plugin enabled in managed settings can't be turned off from a session, so this setting is the only off switch short of a rebuild. A hook that only adds context, like the sync check, needs none.

[agent-plugins-nixpkgs](https://github.com/nhooey/agent-plugins-nixpkgs) takes this repository as an input and passes `hooks-plugin` through. To install it, add that package to `services.agent-plugins.plugins` in a nix-darwin configuration, which lists it in a marketplace in the store and enables it in managed settings. Don't also wire its hooks into `settings.json`: they'd run twice.

## Skills in this repo

One section per pack. The four skills tagged `agent` (only meaningful when an LLM is driving) live under `github-workflow-*`; filter by tag if a human reads this without an agent.

### `git-hygiene-*` — local style rules

| Name | Tags | What |
| --- | --- | --- |
| [git-hygiene-avoid-sweeping-operations](skills/git-hygiene-avoid-sweeping-operations) | safety | Name the paths and refs you act on: no `git add -A`, `git reset --hard`, `git clean -f`, bare `git stash`, `git branch -D` and similar. |
| [git-hygiene-branch-naming](skills/git-hygiene-branch-naming) | style | Long, descriptive, dash-separated, autocomplete-friendly names. |
| [git-hygiene-commit-message-format](skills/git-hygiene-commit-message-format) | style | Subject under 72 chars, blank line, body wrapped at 72, explain WHY not what; body optional except for breaking, security, migration and revert commits. |
| [git-hygiene-conventional-commits](skills/git-hygiene-conventional-commits) | style, team-stance | `type(scope): subject` Conventional Commits format. |
| [git-hygiene-gitignore](skills/git-hygiene-gitignore) | style | Anchor paths, keep personal preferences in `~/.gitignore_global`, compress patterns safely. |
| [git-hygiene-no-history-in-tracked-files](skills/git-hygiene-no-history-in-tracked-files) | style | Tracked files (code, docs, skills, plans, config) state the current state; "added in v3.2" and "used to do X" notes go in commit messages. Changelogs, ADRs and migration guides exempt. |
| [git-hygiene-push-force-safely](skills/git-hygiene-push-force-safely) | safety | Always force-push with `--force-with-lease`, never plain `--force`. |
| [git-hygiene-ssh-remotes](skills/git-hygiene-ssh-remotes) | setup, style | Prefer SSH (`git@github.com:owner/repo.git`) over HTTPS. |

### `git-workflow-*` — interactive procedures

| Name | Tags | What |
| --- | --- | --- |
| [git-workflow-curate-unpushed](skills/git-workflow-curate-unpushed) | workflow, style | Squash noise commits + amend forward to curate unpushed history. |
| [git-workflow-inspect-before-commit](skills/git-workflow-inspect-before-commit) | workflow, safety | `git status` / `git diff` / `git diff --cached` before every commit; catch secrets, debug logging, format churn. |
| [git-workflow-push-mode](skills/git-workflow-push-mode) | workflow, interactive, team-stance | Ask once per repo per session: direct-to-main / PRs-always / ask-each-time. |
| [git-workflow-tidy-branches](skills/git-workflow-tidy-branches) | workflow, interactive, safety | Report, then apply: delete merged branches (squash merges included), rebase branches that replay cleanly onto the base, flag stacks, conflicts and diverged copies. |

### `github-hygiene-*` — PR-shape discipline, issue/PR references + `gh` gotchas

| Name | Tags | What |
| --- | --- | --- |
| [github-hygiene-gh-cli-gotchas](skills/github-hygiene-gh-cli-gotchas) | reference | Known `gh` CLI traps: `pr edit` exit 1, `--json merged` invalid, self-approval blocked, branch rename closes PRs. |
| [github-hygiene-pull-request-mirrors-commit](skills/github-hygiene-pull-request-mirrors-commit) | workflow, style, team-stance | One commit per PR; title = subject, body = body (reflowed to paragraphs by the bundled `create-or-update-pull-request.sh`); re-sync after every amend. |
| [github-hygiene-refer-to-issues-and-pull-requests](skills/github-hygiene-refer-to-issues-and-pull-requests) | style | Name issues/PRs as `#N "title…"` (or `owner/repo#N "title…"`) and commits as short SHA + subject, linked; branches only in parentheses after their PR. |

### `github-policy-*` — one-time repo configuration

| Name | Tags | What |
| --- | --- | --- |
| [github-policy-auto-delete-merged-branches](skills/github-policy-auto-delete-merged-branches) | setup | Enable `delete_branch_on_merge`. |
| [github-policy-codeowners](skills/github-policy-codeowners) | setup | `.github/CODEOWNERS` + `require_code_owner_review` for multi-contributor repos. |
| [github-policy-merge-commits-only](skills/github-policy-merge-commits-only) | setup, team-stance | Disable squash + rebase merges; every PR lands as a merge commit. |
| [github-policy-protect-default-branch](skills/github-policy-protect-default-branch) | setup, safety | Rulesets-API protection: require PR, status checks, block force-push, block deletion. |

### `github-workflow-*` — PR lifecycle, browser drafting and repo activity (includes the agent-tagged skills)

| Name | Tags | What |
| --- | --- | --- |
| [github-workflow-browser-draft-preview](skills/github-workflow-browser-draft-preview) | agent, workflow, interactive | Draft a PR, comment, reply or edit in Chrome via Claude in Chrome; switch to Preview, box the draft in red, raise the tab, ask before posting. |
| [github-workflow-pull-request-changeset-prompt](skills/github-workflow-pull-request-changeset-prompt) | agent, interactive | Multi-select `AskUserQuestion` after every change-set: Stage/Commit/Amend/Push/Force/Open-PR/Re-derive/Monitor. |
| [github-workflow-pull-request-stacked](skills/github-workflow-pull-request-stacked) | workflow, team-stance, reference | Submit dependent PRs on GitHub. Repo you control: `gh stack submit`, merge the top PR, `gh stack sync` (`gt` for branching stacks). Upstream fork-only: draft + `Depends on`, `git rebase --update-refs`. Upstream with topic-branch push grant: `gh stack` or `gt submit --stack`. |
| [github-workflow-pull-request-status-line](skills/github-workflow-pull-request-status-line) | agent, style | Surface PRs as `<status-circle> <url> — **PR #<num>: <title>**` with live state. |
| [github-workflow-pull-request-watcher](skills/github-workflow-pull-request-watcher) | agent, workflow | Background Monitor polling PR check-runs/comments/state; one reaction per event type. |
| [github-workflow-repo-activity](skills/github-workflow-repo-activity) | workflow, reference | `github-repo-activity.py`: one user's comments, reviews, merges, pushes and branches on a repo since a time, from the endpoints of record, not the Events API. |

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

Write the `description` so an agent can decide whether to invoke the skill from that one line — describe both *what it does* and *when to use it*. Pick `tags` from the vocabulary above. In the dev shell (`nix develop`), `git-skills lint` checks these rules and `git-skills test` runs the skills' bundled tests; `menu` lists every dev-shell command.

To make a new skill installable via Nix in isolation, drop a `flake.nix` into the skill folder modeled on `skills/git-hygiene-push-force-safely/flake.nix`. The top-level flake auto-discovers any subdirectory of `skills/` that contains a `SKILL.md`, so a new skill gets its `agent-skill-nhooey-<name>` package and joins the apps without further changes. If the new skill belongs in a starter pack, add its name to the pack's list in the top-level `flake.nix`.
