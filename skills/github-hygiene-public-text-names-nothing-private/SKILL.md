---
name: github-hygiene-public-text-names-nothing-private
description: |
  Load before writing text that goes somewhere public: a public
  repository's files, commits, PR titles and bodies, issues, comments,
  release notes or gists. That text never names a private repository or
  a person's private configuration, nor a local path under a home
  directory. Check a repository's visibility with `gh repo view` before
  naming it, and scan the diff, commit messages and PR body before
  pushing to or opening a PR on a public repository.
tags: [safety]
allowed-tools:
  - Bash
---

# Public text names nothing private

_A public repository's files, commits, pull request titles and bodies, issues, comments, release notes and gists never name a private repository or a person's private configuration, nor a local path under a home directory._

A private repository's name tells strangers what someone keeps private, and a path under `/Users/` or `/home/` names the account and the layout of their machine.
Once pushed, both are copied by forks, caches and search indexes, so a later edit doesn't take them back.

## Check visibility, don't keep a list

Before naming a repository in public text, read the visibility of both the repository named and the one being written to:

```bash
gh repo view <owner>/<repo> --json visibility --jq .visibility
```

- Written to `PUBLIC`, naming a `PRIVATE` or `INTERNAL` one: describe the private one by what it is, never by name.
- A repository `gh` can't see: treat it as private.
- Written to a private repository: the rule doesn't apply there.

No list of private names is kept anywhere; visibility is read fresh each time, so a repository made private later is caught too.

## Describe instead of naming

| Instead of | Write |
| --- | --- |
| `acme/laptop-setup` | "a system configuration" |
| `acme/infra-secrets`'s `settings.nix` | "the account's settings, managed elsewhere" |
| `/Users/alice/src/tool/build.sh` | `build.sh`, or a path from the repository root |
| `~/.config/tool/prefs.toml` | "the user's preferences file" |

A path in a code block or log pasted into an issue counts too: trim it to the part under the repository root.

## Scan before pushing

Before pushing to, or opening a PR on, a public repository, scan everything that will be public for the account's private repository names and for home-directory paths:

```bash
gh repo list <owner> --visibility private --limit 1000 --json name --jq '.[].name'
git diff <base>...HEAD
git log --format=%B <base>..HEAD
```

Search the diff, the commit messages and the PR body for each name and for `/Users/` and `/home/`.
A name that also reads as an ordinary word needs a look at its context, not an automatic rewrite.
Fix a hit before the push: reword the text, and amend or rewrite the unpushed commit.

## Found after it was pushed

Stop and tell the user what leaked and where: the file, commit or PR field.
Then:

- A PR title or body, an issue or a comment: edit it, then say that GitHub keeps the edit history.
- A commit already pushed: propose rewording it and force-pushing with `git push --force-with-lease`, and do it only with the user's yes.
  A merged commit on the default branch needs their decision on rewriting shared history.

## Related skills

When one of these applies and it's in your skill listing, load it without asking.
If it isn't in your listing, tell the user which skill is missing and ask whether to install it from the same collection this skill came from; don't apply it from memory.

- `writing-hygiene-refer-by-canonical-label`: how to name things in text, which this skill limits to what public text may name.
- `github-hygiene-pull-request-mirrors-commit`: a PR's title and body come from its commits, so the scan of the commits covers the PR.
- `git-workflow-inspect-before-commit`: the diff review before each commit, where a private name or home path is cheapest to catch.
- `git-hygiene-push-force-safely`: the `--force-with-lease` push for rewording a commit already pushed.
