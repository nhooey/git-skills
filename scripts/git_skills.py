#!/usr/bin/env python3
"""Lint this repository's skills: `git-skills lint [SKILL...]`.

    git-skills lint [SKILL...]   check each skill's folder name and frontmatter

With no SKILL, it covers every skill under `skills/`. The repository root
is `--root`, else `$PRJ_ROOT` (set by the dev shell), else the current git
work tree. Exit status: 0 when every check passes, 1 when one fails, 2 for
a usage error. `git-skills test`, which runs the tests in `tests/`, is the
dev shell command's own shell, in `flake.nix`.

Python 3.9+ standard library.
"""

import argparse
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
TOP_LEVEL_KEY = re.compile(r"([A-Za-z_][\w-]*):(.*)")


@dataclass(frozen=True)
class Skill:
    name: str
    skill_md: Optional[str]  # SKILL.md's text, or None when it is missing


# --- core --------------------------------------------------------------------


def frontmatter(text):
    """The top-level keys of a SKILL.md's YAML frontmatter, mapped to the
    raw text after the colon, or None when the file opens without one."""
    lines = tuple(text.splitlines())
    if not lines or lines[0].strip() != "---":
        return None
    end = next((i for i, line in enumerate(lines[1:], 1) if line.strip() == "---"), None)
    if end is None:
        return None
    matches = (TOP_LEVEL_KEY.fullmatch(line) for line in lines[1:end])
    return {m.group(1): m.group(2).strip() for m in matches if m}


def flow_list(value):
    """The items of a YAML flow sequence such as `[style, safety]`, or None
    when the value isn't one."""
    if not (value.startswith("[") and value.endswith("]")):
        return None
    return tuple(item.strip() for item in value[1:-1].split(",") if item.strip())


def lint(skill):
    """Each problem with one skill, as a tuple of messages."""
    if skill.skill_md is None:
        return ("has no SKILL.md",)
    keys = frontmatter(skill.skill_md)
    if keys is None:
        return ("SKILL.md has no YAML frontmatter between `---` lines",)
    tags = flow_list(keys.get("tags", ""))
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
            if keys.get("name", skill.name) in ("", skill.name)
            else f"frontmatter name `{keys['name']}` isn't the folder name",
            None
            if "tags" not in keys or tags is not None
            else "tags isn't a flow list such as `[style, safety]`",
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


def read_skills(root):
    dirs = sorted(d for d in (root / "skills").iterdir() if d.is_dir())
    return tuple(
        Skill(
            name=d.name,
            skill_md=(d / "SKILL.md").read_text() if (d / "SKILL.md").is_file() else None,
        )
        for d in dirs
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
