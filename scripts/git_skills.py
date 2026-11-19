#!/usr/bin/env python3
"""Lint this repository's skills: `git-skills lint [SKILL...]`.

    git-skills lint [SKILL...]   check each skill's folder name and frontmatter

With no SKILL, it covers every skill under `skills/`. The repository root
is `--root`, else `$PRJ_ROOT` (set by the dev shell), else the current git
work tree. Exit status: 0 when every check passes, 1 when one fails, 2 for
a usage error. `git-skills test`, which runs the tests in `tests/`, is the
dev shell command's own shell script, `scripts/git-skills.sh`.

Python 3.9+ standard library, with yq-go on PATH to parse the frontmatter.
"""

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Optional

# The README's "Tag vocabulary" table and its pack prefixes.
TAGS = frozenset(
    {"agent", "workflow", "interactive", "setup", "reference", "safety", "style", "team-stance"}
)
PACKS = (
    "git-hygiene",
    "git-workflow",
    "github-hygiene",
    "github-policy",
    "github-workflow",
)
REQUIRED_KEYS = ("name", "description", "tags")
FOLDER_NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")


@dataclass(frozen=True)
class Frontmatter:
    data: object  # the parsed YAML value, None when it is empty or invalid
    error: Optional[str]  # yq's message when the block isn't valid YAML


@dataclass(frozen=True)
class Skill:
    name: str
    skill_md: Optional[str]  # SKILL.md's text, or None when it is missing
    # SKILL.md's frontmatter, or None when the file or its frontmatter is missing
    frontmatter: Optional[Frontmatter] = None


# --- core --------------------------------------------------------------------


def frontmatter_block(text):
    """The text between a SKILL.md's opening and closing `---` lines, or None
    when the file opens without frontmatter."""
    lines = tuple(text.splitlines())
    if not lines or lines[0].strip() != "---":
        return None
    end = next((i for i, line in enumerate(lines[1:], 1) if line.strip() == "---"), None)
    if end is None:
        return None
    return "\n".join(lines[1:end]) + "\n"


def string_list(value):
    """The items of a YAML sequence of strings, in flow or block style, or
    None when the value isn't one."""
    if not (isinstance(value, list) and all(isinstance(item, str) for item in value)):
        return None
    return tuple(value)


def lint(skill):
    """Each problem with one skill, as a tuple of messages."""
    if skill.skill_md is None:
        return ("has no SKILL.md",)
    if skill.frontmatter is None:
        return ("SKILL.md has no YAML frontmatter between `---` lines",)
    if skill.frontmatter.error is not None:
        return (f"frontmatter isn't valid YAML: {skill.frontmatter.error}",)
    keys = {} if skill.frontmatter.data is None else skill.frontmatter.data
    if not isinstance(keys, dict):
        return ("frontmatter isn't a YAML mapping",)
    tags = string_list(keys.get("tags"))
    return tuple(
        problem
        for problem in (
            None
            if FOLDER_NAME.fullmatch(skill.name)
            else "folder name isn't lowercase-with-hyphens",
            None
            if skill.name.startswith(tuple(f"{p}-" for p in PACKS))
            else f"name starts with none of the packs: {', '.join(PACKS)}",
            *(f"frontmatter has no `{k}`" for k in REQUIRED_KEYS if not keys.get(k)),
            None
            if not keys.get("name") or keys["name"] == skill.name
            else f"frontmatter name `{keys['name']}` isn't the folder name",
            None
            if not keys.get("tags") or tags is not None
            else "tags isn't a list of tags such as `[style, safety]`",
            *(
                f"tag `{t}` isn't in the README's tag vocabulary"
                for t in (tags or ())
                if t not in TAGS
            ),
        )
        if problem
    )


def select(skills, names):
    """The skills named, in the order given, or all of them with no names;
    and the names that match no skill."""
    by_name = {s.name: s for s in skills}
    return (
        tuple(by_name[n] for n in names if n in by_name) if names else tuple(skills),
        tuple(n for n in names if n not in by_name),
    )


def parser():
    p = argparse.ArgumentParser(
        prog="git-skills",
        description="Lint this repository's skills.",
    )
    p.add_argument(
        "--root",
        type=pathlib.Path,
        help="repository root (default: $PRJ_ROOT, else the git work tree)",
    )
    sub = p.add_subparsers(dest="command", required=True, metavar="COMMAND")
    check = sub.add_parser("lint", help="check each skill's folder name and frontmatter")
    check.add_argument("skills", nargs="*", metavar="SKILL")
    return p


# --- shell -------------------------------------------------------------------


def repo_root(given):
    if given:
        return given
    if os.environ.get("PRJ_ROOT"):
        return pathlib.Path(os.environ["PRJ_ROOT"])
    found = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True
    )
    return pathlib.Path(found.stdout.strip() if found.returncode == 0 else ".")


def load_frontmatter(text):
    """SKILL.md's frontmatter parsed by yq-go as YAML, or None when the file
    is missing or opens without frontmatter."""
    block = None if text is None else frontmatter_block(text)
    if block is None:
        return None
    parsed = subprocess.run(
        ["yq", "--input-format=yaml", "--output-format=json", "."],
        input=block,
        capture_output=True,
        text=True,
    )
    if parsed.returncode != 0:
        return Frontmatter(data=None, error=parsed.stderr.strip())
    return Frontmatter(data=json.loads(parsed.stdout), error=None)


def skill_from_dir(d):
    text = (d / "SKILL.md").read_text() if (d / "SKILL.md").is_file() else None
    return Skill(
        name=d.name,
        skill_md=text,
        frontmatter=load_frontmatter(text),
    )


def read_skills(root):
    return tuple(
        skill_from_dir(d) for d in sorted(d for d in (root / "skills").iterdir() if d.is_dir())
    )


def report_lint(skills):
    problems = tuple((s.name, p) for s in skills for p in lint(s))
    print("\n".join(f"{name}: {p}" for name, p in problems) or f"{len(skills)} skill(s) clean")
    return 1 if problems else 0


def main(argv=None):
    args = parser().parse_args(argv)
    root = repo_root(args.root)
    if not (root / "skills").is_dir():
        print(f"git-skills: no skills/ directory under {root}", file=sys.stderr)
        return 2
    chosen, unknown = select(read_skills(root), args.skills)
    if unknown:
        print(f"git-skills: no such skill: {', '.join(unknown)}", file=sys.stderr)
        return 2
    return report_lint(chosen)


if __name__ == "__main__":
    sys.exit(main())
