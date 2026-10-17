---
name: github-hygiene-refer-to-issues-and-pull-requests
description: |
  Refer to GitHub issues, pull requests and commits by their canonical
  label, linked: `#206 "Fix new_project.bats on macOS…"` for an issue or
  PR in the same repo, `owner/repo#N "title…"` across repos, and a short
  SHA plus subject for a commit. A branch name only ever appears in
  parentheses after the PR it belongs to, never as the reference. Fetch
  titles and subjects with `gh pr view`, `gh issue view` and `git log`
  rather than guessing. Apply whenever you mention an issue, PR, commit
  or branch in a status report, PR body, review comment, commit message
  or reply.
tags: [style]
---

# github-hygiene-refer-to-issues-and-pull-requests

`#206`, `up/22-bats-copy-path-macos` and `8127188` mean nothing to a
reader until they look each one up. This skill applies
`writing-hygiene-refer-by-canonical-label` to GitHub: every issue, PR
and commit is named by the label the reader would see if they opened
it, with the number or SHA beside it and a link on top.

## How to load this skill

Active whenever you write about an issue, PR, commit or branch. Loading
it doesn't fetch or post anything; it shapes how you name those things
the next time you write.

## The canonical label

| Thing | Canonical label | Machine identifier |
| --- | --- | --- |
| Issue | its title | `#N`, or `owner/repo#N` across repos |
| Pull request | its title | `#N`, or `owner/repo#N` across repos |
| Commit | its subject line | short SHA (7 characters) |
| Branch | none of its own: it belongs to a PR | the branch name, in parentheses after the PR |

Use the label word for word every time. The only allowed variation is
truncating a long title at a word boundary and ending it with `…`.

## Same repo: `#N "title…"`, linked

Put the number first, then the title in quotes, and link the whole
thing to the PR or issue URL:

```markdown
[#206 "Fix new_project.bats on macOS…"](https://github.com/acme/scaffold/pull/206)
```

Before:

> Merged #206 and rebased #208 on top. #208 still fails CI.

After:

> Merged [#206 "Fix new_project.bats on macOS…"](https://github.com/acme/scaffold/pull/206)
> and rebased [#208 "Add a --dry-run flag to new_project"](https://github.com/acme/scaffold/pull/208)
> on top of it. #208 "Add a --dry-run flag to new_project" still fails
> CI.

The second mention repeats the label instead of saying "the second PR"
or "it". The link only needs to be on the first mention in a paragraph.

## Cross-repo: `owner/repo#N "title…"`, linked

A bare `#N` resolves against whatever repo GitHub renders the text on,
so a reference to another repo's issue or PR must carry `owner/repo`:

Before:

> Blocked on #4512 upstream.

After:

> Blocked on [bats-core/bats-core#4512 "cp -r fails on macOS when the target exists"](https://github.com/bats-core/bats-core/issues/4512).

## Commits: short SHA plus subject, linked

Put the short SHA in a code span, then the subject in quotes, all
inside one link:

```markdown
[`8127188` "Copy paths with cp -R on macOS"](https://github.com/acme/scaffold/commit/8127188)
```

Before:

> The regression came in with 8127188; reverting 3fa09c2 didn't help.

After:

> The regression came in with
> [`8127188` "Copy paths with cp -R on macOS"](https://github.com/acme/scaffold/commit/8127188);
> reverting [`3fa09c2` "Quote paths passed to cp"](https://github.com/acme/scaffold/commit/3fa09c2)
> didn't help.

In a commit message body, which isn't rendered as Markdown, drop the
link syntax and keep the SHA and subject: `8127188 ("Copy paths with
cp -R on macOS")`. GitHub autolinks the SHA when it shows the commit.

## Branches: only in parentheses after their PR

A branch name is full of dashes, slashes and ticket numbers; it reads
badly and the reader can't open it the way they open a PR. Name the PR,
and add the branch in parentheses only when the reader needs it (to
check it out, or to tell two PRs from the same author apart):

Before:

> Pushed a fix to up/22-bats-copy-path-macos. feat/dry-run is waiting
> on it.

After:

> Pushed a fix to [#206 "Fix new_project.bats on macOS…"](https://github.com/acme/scaffold/pull/206)
> (`up/22-bats-copy-path-macos`).
> [#208 "Add a --dry-run flag to new_project"](https://github.com/acme/scaffold/pull/208)
> is waiting on it.

A branch with no PR yet has no canonical label: describe the work in a
few words at first mention ("the macOS copy fix, on branch
`up/22-bats-copy-path-macos`") and reuse that phrase from then on.

## On GitHub itself, still add the title

PR bodies, issue comments and review comments autolink `#N` and
`owner/repo#N`, and GitHub shows the title on hover. A reader skimming
the page doesn't hover, so still write the title words:

Before:

> Supersedes #198. Depends on #206.

After:

> Supersedes #198 "Use rsync instead of cp in new_project". Depends on
> #206 "Fix new_project.bats on macOS…".

No explicit link is needed here, because GitHub already makes `#198`
clickable.

## Fetch labels, don't guess them

Copy titles and subjects from the source so they match word for word:

```bash
gh pr view 206 --json number,title,url --jq '"#\(.number) \"\(.title)\" \(.url)"'
gh issue view 4512 --repo bats-core/bats-core --json title,url
git log -1 --format='%h "%s"' 8127188
```

If a title changes after you've written it, use the new title from then
on; it is the label the reader will see.

## When to apply

- Writing a status report, handoff or reply that mentions an issue, PR,
  commit or branch.
- Writing a PR body, issue comment or review comment that points at
  other issues or PRs.
- Writing a commit message body that refers to an earlier commit or to
  an issue it fixes.
- Reviewing text that names things by bare number, SHA or branch:
  propose the labelled form.

## Related skills

When one of these applies and it's in your skill listing, load it
without asking. If it isn't in your listing, tell the user which skill is
missing and ask whether to install it from the same collection this skill
came from; don't apply it from memory.

- `writing-hygiene-refer-by-canonical-label`: the general rule this skill applies, one canonical label per thing, used word for word, identifiers in parentheses.
- `github-hygiene-pull-request-mirrors-commit`: a PR's title is its commit subject, so a PR's canonical label and its commit's label match.
