---
name: git-hygiene-commit-message-format
description: |
  Format commit messages with a subject under 72 chars, a blank line after
  it, and a body wrapped at 72 chars that explains why rather than what.
  Skip the body when the subject says it all, but always write one for
  breaking, security, migration and revert commits. Names the common drift
  modes to cut from the body (diff paraphrase, test inventory, while-here
  paragraph, audit walkthrough, narration filler) and caps the body at
  about 4 paragraphs. Use whenever writing, amending or reviewing a commit
  message. Pair with git-hygiene-conventional-commits if the repo adopts
  that convention.
tags: [style]
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# Commit message format

_A short imperative subject, a blank line, and a body wrapped at 72 that says why the change was made, kept to what the diff can't tell a later reader._

Loading this skill is not a request to commit: apply it the next time you
write or amend a commit message.

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
  subjects. Behind a Conventional Commits prefix,
  `git-hygiene-conventional-commits` sets the case instead.
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
  landmines hit, and links to issues or discussions. For a fix, the
  previous behavior often carries the why in one clause: "Previously X;
  that broke Y."
- **A commit is a delta.** The body states what is now true and why,
  as before → after where it helps (`timeout: 30s → 60s`), never the
  steps taken to get there. `writing-hygiene-declarative-statements`
  holds the vocabulary.
- **Skip the body when the subject is the whole story.** A typo fix,
  dependency bump, or rename needs no body. Always write one for
  breaking changes, security fixes, data migrations, reverts, and any
  change whose motivation can't be recovered from the diff — those are
  the commits future debuggers land on.
- **Name the technical symptom, never the customer.** No customer or
  organization names, emails, or pasted ticket text: history outlives
  access controls and gets mirrored and forked. "Import fails on CSVs
  with a BOM" beats "Fix Acme's broken upload".

Before drafting, state the change in one sentence: "<what> so that
<why>". If you can't, or the subject won't fit in 72, the commit mixes
changes: split it. If you can, the "<what>" half is your subject; when
the diff makes the why obvious, you may not need a body at all.

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
- **Narration filler.** "This commit…", "This change…", "I"/"we",
  "As requested by…", and "now" or "currently" as a time stamp
  ("currently we…"). The subject already frames the change, and the
  commit date already says when. Start at the reason: "X dropped Y
  because…", not "This commit fixes an issue where…". "X now does Y"
  is a valid delta and stays. Credit goes in a trailer
  (`Reported-by:`, `Co-authored-by:`), not prose.

**Aim for ≤4 body paragraphs.** Over that, the commit is usually
either doing too much (split it — see `git-workflow-curate-unpushed`
for the local-history curation that makes splits cheap) or restating the
diff / PR description (cut it). A change as big as adding a new
public API knob with full test coverage typically lands in 3
paragraphs: motivation, ruled-out alternative, one non-obvious
implementation detail.

## Shape the body for a reader who skims

The body is read raw in `git log` and rendered as GFM on the PR, and
the PR tooling unwraps each paragraph into one line. Shape it for both:

- **Synthesis first:** the opening paragraph says what became true and
  why; detail follows for whoever reads on.
- **Enumerations as lists:** a body that enumerates three or more
  items, or parallel options, uses a `-` list rather than one sentence
  of commas (`writing-hygiene-prose-to-lists`), nested where the items
  have a hierarchy, with the list syntax of
  `markdown-hygiene-lists-headings-tables`.
- **Comparisons as tables:** options weighed against the same criteria
  go in a table (`writing-hygiene-tables-for-comparison`).
- **No headings in a body under about 15 lines.**
- **Lists and tables that survive unwrapping:** each item wrapped at 72
  columns with its continuation lines indented under the item's text
  (a hanging indent), each table row on one line, and a blank line
  above and below either.
- **Code words in backticks:** paths, identifiers, flags, commands.

## Code references

Point at code as plain `path:line` or `path:start-end`, from the
repository root, in backticks: `src/cache.rs:118-140`. Never a URL:
the PR generator links each one, pinned to the commit's SHA, so it
keeps pointing at the lines the commit meant.

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

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `git-hygiene-conventional-commits`: the `type(scope): subject` prefix to pair with this format when the repo has adopted Conventional Commits.
- `git-workflow-curate-unpushed`: splitting or squashing commits before push, when a message is hard to write because the commit does too much.
- `github-hygiene-pull-request-mirrors-commit`: the PR title and body mirror this commit message, so its 72-char subject and body rules carry over to the PR.
- `markdown-hygiene-lists-headings-tables`: the list and table syntax a body's lists and tables use, so they render as meant on the PR.
- `writing-hygiene-declarative-statements`: the snapshot-or-delta vocabulary, the before → after notation and the narration word list behind "a commit is a delta".
- `writing-hygiene-prose-to-lists`: rewriting a sentence that enumerates three or more items, or parallel options, as a list.
- `writing-hygiene-refer-by-canonical-label`: naming a commit, pull request or file by its canonical label, and pointing at code with a pinned permalink instead of restating the diff.
- `writing-hygiene-tables-for-comparison`: when a comparison goes in a table, and how to shape it.
