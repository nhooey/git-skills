---
name: git-hygiene-gitignore
description: |
  Anchor `.gitignore` patterns with a leading `/` when they only apply at
  one location. Keep personal/editor preferences (`.idea/`, `.DS_Store`)
  out of project `.gitignore` — put them in `~/.gitignore_global`.
  Compress patterns to fewer lines, but avoid over-broadening. Apply when
  editing any project `.gitignore`.
tags: [style]
allowed-tools:
  - Bash
  - Read
  - Edit
---

# git-hygiene-gitignore

A project's `.gitignore` should describe **what this project produces or
depends on that should not be tracked** — nothing else. Keep it scoped,
keep it accurate, keep it free of personal taste.

## How to load this skill

Passive reference. Loading it doesn't mean you should edit `.gitignore`
now — just that when you do, you'll follow the rules below.

## Anchor truly-absolute paths with a leading `/`

In a `.gitignore`, a pattern without a leading `/` matches at any depth.
A pattern with a leading `/` is anchored to the directory containing
the `.gitignore` (typically the repo root).

If the path you mean to ignore only exists at one specific location,
write it that way:

```gitignore
# Anchored: only the repo-root build/ directory.
/build/
/dist/
/node_modules/

# Unanchored: any node_modules/ at any depth.
# Only use this form when you really do mean "everywhere".
node_modules/
```

**Why it matters:** an unanchored `build/` will also ignore
`src/components/build/` if a developer ever creates one — silently.
That is the kind of bug that takes an afternoon to track down ("why
aren't my files showing up in `git status`?"). Anchoring eliminates the
surprise.

When in doubt, anchor. Only drop the leading slash when the pattern
genuinely needs to match at every depth (e.g., `node_modules/`,
`__pycache__/`, `*.log`).

## Don't put personal/editor preferences in the project `.gitignore`

The popular convention is to dump every editor's side-effects into the
project `.gitignore`: `.idea/`, `.vscode/`, `.DS_Store`, `*.swp`,
`Thumbs.db`, `*~`, `.netrwhist`, and so on. **Don't.**

These do not belong to the project. They belong to the **developer's
machine and tooling choices**. Putting them in the project `.gitignore`
has real costs:

- The list grows forever as new editors and OSes appear, and nobody
  prunes it, so the file accumulates patterns for editors no current
  contributor uses.
- It implicitly endorses one set of tools. New contributors using a
  tool not on the list assume the project doesn't care, and
  accidentally commit their own editor droppings.
- It mixes two different concerns — "what this project builds" and
  "what Bob's machine happens to leave around" — which makes diffs
  noisier and reviews harder.

**The correct place** is the user's **global gitignore**, configured
once per developer and applied to every repo they touch:

```bash
git config --global core.excludesfile ~/.gitignore_global
# Then add personal patterns to ~/.gitignore_global:
#   .DS_Store
#   .idea/
#   .vscode/
#   *.swp
#   *~
```

Each developer curates their own list once and gets coverage
everywhere. The project `.gitignore` stays focused on the project.

**Exception:** if the project's *toolchain* requires editor config that
all contributors share (e.g., a checked-in `.vscode/settings.json` with
required formatter rules), then `.vscode/` is project-relevant and you
*don't* want to ignore it at all. The rule is: ignore project
artifacts, not personal preferences.

## Use patterns to compress lines, but don't over-broaden

Patterns are leverage. Replacing fifteen explicit log paths with `*.log`
is a clear win — fewer lines, no new file slips through the gap. But
the same instinct, applied carelessly, ignores files you wanted to
keep.

**Good compression:**

```gitignore
# Build outputs across all packages
/packages/*/dist/
/packages/*/build/

# Any compiled Python bytecode, anywhere
__pycache__/
*.py[cod]

# All log files in the logs dir
/logs/*.log
```

**Bad over-broadening:**

```gitignore
# Ignores docs/build.md, src/build.ts, anything containing "build"
*build*

# Ignores legitimate config files like .env.example or .env.sample
.env*

# Ignores .gitignore itself, your shell scripts, everything
*
```

Heuristics:

- Anchor with `/` when the pattern should only apply at one location.
- Constrain by extension or directory (`/logs/*.log`, not `*log*`).
- For "ignore the family but keep one file", use a negation:
  ```gitignore
  .env*
  !.env.example
  ```
- After adding a broad pattern, run `git status --ignored` (or
  `git check-ignore -v <path>`) on a few candidate files to confirm
  you're only catching what you intended.

The test: can you read each line of `.gitignore` and explain in one
sentence what it ignores and why? If a line is too broad to summarize
without saying "and probably some other stuff", tighten it.

## When to apply

- About to edit `.gitignore` for any reason.
- Reviewing a `.gitignore` for over-broad patterns.
- Noticing editor droppings (`.DS_Store`, `.idea/`) in a project
  `.gitignore` — propose moving them to `~/.gitignore_global`.
