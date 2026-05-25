---
name: git-hygiene-commit-message-format
description: |
  Format commit messages with subject under 72 chars, blank line after the
  subject, body wrapped at 72 chars, and explain WHY rather than what.
  Names the common drift modes to cut from the body (diff paraphrase,
  test inventory, while-here paragraph, audit walkthrough) and caps the
  body at ~4 paragraphs. Apply whenever writing or amending any commit
  message. Pair with git-hygiene-conventional-commits if the repo adopts
  that convention.
tags: [style]
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# git-hygiene-commit-message-format

Apply this rule whenever you are about to create or amend a commit. The
goal is a readable history that future readers (including future-you) can
mine for context.

## How to load this skill

Passive reference, not a command. Loading it does **not** mean the user
wants you to commit right now. Do not run `git status`, stage files, or
create commits on load — just internalize the rule and apply it the next
time a commit comes up.

## The rule

- **First line under 72 characters.** Aim for ~50, hard cap at 72 — the
  50/72 convention from [Tim Pope's *A Note About Git Commit Messages*
  (2008)](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html),
  restated by [Chris Beams' *How to Write a Git Commit Message*](https://cbea.ms/git-commit/)
  and *Pro Git* §5.2. GitHub, `git log --oneline`, and most tools
  truncate or wrap past 72 (see `github-hygiene-pull-request-mirrors-commit` for
  the empirical GitHub truncation).
- **Use the imperative mood in the subject.** "Add X", not "Added X" or
  "Adds X". Sanity check: read "If applied, this commit will *<your
  subject>*" — if it parses as a coherent instruction, the mood is right
  (Beams).
- **Capitalize the subject.** Treat it as a title, not a sentence
  fragment. Matches how `git log --oneline` displays a column of
  subjects.
- **No trailing period on the subject.** It's a title, not a sentence —
  the period wastes a character against the 50-char target and reads as
  noise in `git log --oneline`.
- **Blank line after the first line.** Many tools rely on this to
  separate subject from body. No blank line means the body gets glued to
  the subject.
- **Wrap body lines at 72 characters.** `git log` indents the body by 4
  spaces, so wider lines wrap awkwardly in 80-column terminals.
- **Use the body to explain why, not what.** The diff already shows what
  changed. Spend the body on motivation, alternatives considered,
  landmines hit, and links to issues or discussions.

When writing a commit, draft the subject first, then add a blank line,
then write the body wrapped at 72. If a subject feels longer than 72,
the commit is probably doing too much — split it.

## What to cut: common drift modes

The diff, the PR description / design doc, and inline code comments
already own three categories of content: the diff shows the patch
(function signatures, type signatures, file moves, test filenames);
the PR description / design doc holds audit tables and the
file-by-file alternatives walkthrough; inline comments and test names
carry per-line caveats. The commit body is for context that survives
independently of those three — motivation, the one path-not-taken
that wasn't obvious, the landmine future-you would re-step on.
Symptoms that the body has drifted into WHAT:

- **Diff paraphrase.** Sentences that read like a restatement of the
  patch — function signatures, type signatures, file moves, default
  values. `git show` already shows them. Cut.
- **Audit / alternatives walkthrough.** File-by-file rationale and
  long "alternatives weighed" prose belong in the PR description or
  a design doc, not the commit. (If the repo follows
  `github-hygiene-pull-request-mirrors-commit`, commit body = PR body, so this
  content has no home on the PR either — push it to a design doc or
  a follow-up comment, or just cut it.) Keep at most the one
  path-not-taken that's load-bearing for future readers.
- **Test inventory.** Bulleted or comma-list enumerations of tests
  added ("positive case, negative case, glob-no-match, …"). The test
  filenames in the diff are the inventory; well-named tests carry
  their purpose. Only mention a test if its *existence* is
  non-obvious (e.g., a regression guard against a specific past
  incident) — and even then, name the incident, not the test.
- **While-here paragraph.** Secondary changes headed by "While here,"
  / "Also," / "In passing,". Doubles the framing cost for a change
  that fits in a clause. Fold into the main paragraph as a
  parenthetical: "…is plumbed through A and B (which also picks up
  Y while here)."
- **Cross-paragraph echo.** Same WHY point made in two different
  paragraphs. Pick the stronger phrasing; delete the other.
- **Sub-claim stacking.** Three independent facts packed into one
  parenthetical or clause. Split or cut to one.

**Aim for ≤4 body paragraphs.** Over that, the commit is usually
either doing too much (split it — see `git-workflow-curate-unpushed`
for the local-history curation that makes splits cheap) or restating the
diff / PR description (cut it). A change as big as adding a new
public API knob with full test coverage typically lands in 3
paragraphs: motivation, ruled-out alternative, one non-obvious
implementation detail.

## Worked example

A change adding `extraFiles` to a public Nix-flake API and four bats
tests. **Before** (35-line body, six paragraphs) restated the
`extraFiles` type signature in P3, did a glob-vs-allowlist
walkthrough in P4, opened a "While here, also expose `extraDirs` on
`mkAllSkillsFlake`" paragraph in P5, and enumerated all four bats
tests in P6. The same commit, cut:

    Add extraFiles for loose top-level SKILL.md companions

    The strict SKILL.md / references/ / scripts/ + extraDirs
    whitelist silently dropped flat companion files that an upstream
    SKILL.md cross-referenced from its source root, so wrappers
    around collections like obra/superpowers produced installs where
    every [see also X.md] link 404'd.

    extraDirs can't close this gap — there's no directory to opt in
    when the companions are flat. A shipAllToplevel boolean would be
    lossy (flake.nix, flake.lock, .gitignore would slip in),
    defeating the intentional whitelist posture.

    extraFiles is plumbed through mkSkillFlake and mkAllSkillsFlake
    (which also picks up extraDirs while here). The installPhase
    runs extraFiles BEFORE the awk pass on SKILL.md, so a glob like
    ["*.md"] that legitimately matches SKILL.md doesn't clobber the
    frontmatter-normalized canonical version — the one non-obvious
    ordering decision in the change.

What got cut: the type-signature paraphrase (P3 → diff), the
glob-vs-allowlist tradeoff (P4 → PR description), the test
enumeration (P6 → filenames in the diff), and the parallel "While
here, also…" paragraph (P5 → folded to a clause inside P3).

## When to apply

- About to write a commit message.
- About to amend an existing commit message.
- Reviewing someone else's commit message in a PR.
