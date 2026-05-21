---
name: git-hygiene-branch-naming
description: |
  Name branches long, descriptive, dash-separated, autocomplete-friendly:
  `rate-limit-cache-eviction` over `fix-rl` or `2026-04-task-1234`. Avoid
  date prefixes, bare ticket numbers, and counter suffixes — they push
  the topic word past where autocomplete reaches it first. Apply when
  creating a new branch or renaming an existing one.
tags: [style]
allowed-tools:
  - Bash
  - Read
---

# git-hygiene-branch-naming

Favour branch names like `rate-limit-cache-eviction` over short cryptic
ones (`fix-rl`, `wip`) or sterile dated and numeric ones
(`2026-04-task-1234`, `tmp-3`, `feature-7`).

## How to load this skill

Passive reference. Loading it doesn't mean you should create a branch
now — just that when you do, you'll pick a name that holds up six
months later.

## Four properties to hold the name to

- **Long enough to read.** Aim for 3-6 words. Weeks-old branch listings
  are browsable when the names are sentences; opaque when they're
  abbreviations.
- **Descriptive of the change.** The topic word is what your memory
  hangs on by the time you're triaging stale branches — not the date,
  not the ticket number, not a counter.
- **Dash-separated** (`rate-limit-cache-eviction`, not
  `rate_limit_cache_eviction` or `RateLimitCacheEviction`). That's what
  git tooling, autocomplete, and URL slugs expect, and what reads
  cleanly in `git log --first-parent`.
- **Autocomplete-friendly against the branches you already have.**
  Before naming, glance at `git branch -a`: pick a leading word that
  disambiguates from the current set in 1-2 characters. If half the
  open branches start with `fix-`, your next `fix-...` needs most of
  its name typed before `<TAB>` resolves; a more specific topic word at
  the front fixes that.

## Avoid

- **Dates as the leading element** (`2026-04-...`, `q2-...`). The
  year/month is rarely what you remember about a branch, and a date
  prefix pushes the meaningful topic word past where autocomplete
  reaches it first. `git log` already records when.
- **Bare ticket numbers** (`task-1234`, `JIRA-1234`). Only acceptable
  followed by a topic word (`JIRA-1234-streaming-api`), never alone.
- **Counter suffixes** (`tmp-3`, `feature-7`, `wip2`). The number
  disambiguates without describing — you're labelling without naming.

## Read your branch list before opening the PR

If a name doesn't tell you what the work was in one glance six months
later, it's too short or too generic — rename before the PR lands,
because the name then lives forever in `git log --first-parent` as the
merge commit subject.

## When to apply

- About to `git switch -c <name>` or `git checkout -b <name>`.
- About to open a PR — if the branch name is regrettable, rename
  first.
