---
name: git-hygiene-gitignore
description: |
  Anchor `.gitignore` patterns with a leading `/` when they only apply at
  one location. Keep personal and editor droppings (`.idea/`, `.DS_Store`)
  out of a project `.gitignore`; they go in the user's global excludes
  file. Compress patterns to fewer lines, but avoid over-broadening. Use
  when editing or reviewing any project `.gitignore`.
tags: [style]
allowed-tools:
  - Bash
  - Read
  - Edit
---

# Project .gitignore files

_A project's `.gitignore` lists what this project produces or depends on that shouldn't be tracked, anchored where it lives, and nothing from anyone's personal tools._

## Anchor truly-absolute paths with a leading `/`

In a `.gitignore`, a pattern with no `/` except a trailing one matches at
any depth. A pattern with a `/` at the start or in the middle is anchored
to the directory containing the `.gitignore` (typically the repo root).

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

An unanchored `build/` also silently ignores `src/components/build/`
if a developer ever creates one, which takes an afternoon to track down
("why aren't my files showing up in `git status`?").

When in doubt, anchor. Only drop the leading slash when the pattern
genuinely needs to match at every depth (e.g., `node_modules/`,
`__pycache__/`, `*.log`).

## Don't put personal/editor preferences in the project `.gitignore`

The popular convention is to dump every editor's side-effects into the
project `.gitignore`: `.idea/`, `.vscode/`, `.DS_Store`, `*.swp`,
`Thumbs.db`, `*~`, `.netrwhist`, and so on. Don't.

These belong to the developer's machine and tooling choices, not to the
project. Putting them in the project `.gitignore` has real costs:

- The list grows forever as new editors and OSes appear, and nobody
  prunes it, so the file accumulates patterns for editors no current
  contributor uses.
- It implicitly endorses one set of tools. New contributors using a
  tool not on the list assume the project doesn't care, and
  accidentally commit their own editor droppings.
- It mixes two different concerns, "what this project builds" and
  "what Bob's machine happens to leave around", which makes diffs
  noisier and reviews harder.

They go in the user's global excludes file, which applies to every repo
they touch. Git reads `$XDG_CONFIG_HOME/git/ignore`, or
`~/.config/git/ignore` when that variable is unset, with no configuration;
`core.excludesFile` points it at another file, such as
`~/.gitignore_global`. Either is a change to the user's machine, not the
project, so propose the patterns to the user rather than writing the file
or running `git config --global` yourself.

Exception: if the project's toolchain requires editor config that all
contributors share (e.g., a checked-in `.vscode/settings.json` with
required formatter rules), then `.vscode/` is project-relevant and you
don't want to ignore it at all. Ignore project artifacts, not personal
preferences.

## Use patterns to compress lines, but don't over-broaden

Patterns are leverage. Replacing fifteen explicit log paths with `*.log`
is a clear win — fewer lines, no new file slips through the gap. But
the same instinct, applied carelessly, ignores files you wanted to
keep.

Good compression:

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

Bad over-broadening:

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
  A negation can't re-include a file whose parent directory is ignored,
  so ignore `dir/*` rather than `dir/` when something inside must stay.
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
  `.gitignore`: propose moving them to the user's global excludes file.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `shell-hygiene-no-machine-wide-changes`: asking before a change outside the project, such as the global excludes file or `git config --global`.
