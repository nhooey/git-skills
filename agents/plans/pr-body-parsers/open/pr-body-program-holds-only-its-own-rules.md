---
title: The PR body program holds only its own rules
state: proposed
kind: end-state
touches: [skills/github-hygiene-pull-request-mirrors-commit/scripts]
---

# The PR body program holds only its own rules

Every line of the Babashka program behind
`create-or-update-pull-request.sh` states a rule of this skill. Anything
a maintained library or tool already does, the program asks it for:

| Job                                   | Done by                                          | In a Python 3.9 port                                         |
| ------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------ |
| The program's command line            | `babashka.cli`                                   | `argparse`                                                   |
| `gh`'s command lines, in the guard    | `clojure.tools.cli`, by a spec of `gh`'s flags   | `getopt.gnu_getopt`, by the same spec                        |
| JSON from `gh`, `shfmt`, `flake.lock` | `cheshire`                                       | `json`                                                       |
| Processes and files                   | `babashka.process`, `babashka.fs`                | `subprocess`, `pathlib`                                      |
| Commit subjects, bodies and trailers  | `git log --format`                               | the same command                                             |
| Line diffs                            | `git diff --no-index`                            | the same command, or `difflib`                               |
| Repository, pull requests and stacks  | `gh … --json … --jq`                             | the same commands                                            |
| Sentences                             | `java.text.BreakIterator`                        | none in the standard library: a splitter held to the goldens |
| Markdown, with source positions       | `cmark-gfm --to xml`, read by `clojure.data.xml` | none: `cmark-gfm` isn't a tool everyone has                  |
| Bash command lines                    | `shfmt --to-json`                                | none: `shfmt` isn't a tool everyone has                      |

What is left is the skill's own: which lines of a paragraph join, what a
code reference links to, the footer and its digest, the single-commit
policy, the stack rule, the `flake.lock` section, what the guard denies,
and the words of each message.

A Python port shares `tests/github-hygiene-pull-request-mirrors-commit/golden/` and the bats suites with the
Babashka program. The 2 rows marked none are where a port has to ship
its own reader, and are the reason the Babashka program is the real one.

## Alternatives measured

Each is a proposed node, with what it would save and cost:

- `write-pull-request-bodies-with-a-markdown-writer`: the largest cut,
  about 240 lines, and the only one that changes what a body says.
- `build-pr-body-program-as-native-jvm-binary`: about 120 lines, for a
  second build system.
- `declare-pr-body-data-shapes-with-malli`: adds about 40 lines.
- `state-pr-body-unit-tests-as-data`: about 150 lines of tests.

## Checks

- No namespace under `src/pr_body/` parses a command line, JSON, XML, a
  diff or a commit message by hand.
- `bb test`, `bats tests/github-hygiene-pull-request-mirrors-commit` and `nix flake check` pass.
