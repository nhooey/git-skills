"""The "Your preferences" section: its command line reads both preferences
files from an installed skill.

An installed skill's folder is often a symlink into the Nix store,
`~/.claude/skills/<skill> -> /nix/store/…/<skill>`, with the user's
`<skill>.preferences.md` beside the link. Claude Code puts the link's path
in place of `${CLAUDE_SKILL_DIR}`, so the line must find the user's file
through that path as written, not through the folder the link points to."""

import os
import subprocess

import pytest

from skill_scripts import SKILLS

SECTIONS = tuple(
    sorted(
        path
        for path in SKILLS.glob("*/SKILL.md")
        if "## Your preferences" in path.read_text(encoding="utf-8").splitlines()
    )
)
# Every SKILL.md with a `!` line that reads a preferences file.
READERS = tuple(
    sorted(
        path
        for path in SKILLS.glob("*/SKILL.md")
        if any(
            line.startswith("!`") and ".preferences.md" in line
            for line in path.read_text(encoding="utf-8").splitlines()
        )
    )
)


def section(path):
    """The lines of the file's "Your preferences" section, up to the next
    heading of level 2 or above."""
    lines = path.read_text(encoding="utf-8").splitlines()
    rest = lines[lines.index("## Your preferences") + 1 :]
    ends = [i for i, line in enumerate(rest) if line.startswith(("# ", "## "))]
    return rest[: ends[0]] if ends else rest


def command_line(path):
    """The command in the section's `!` line: the line that is an
    exclamation mark and one code span."""
    lines = [
        line[2:-1]
        for line in section(path)
        if line.startswith("!`") and line.endswith("`") and line.count("`") == 2
    ]
    assert len(lines) == 1, f"{path} has {len(lines)} preferences command lines"
    return lines[0]


def run(line, skill_dir, project):
    """The line's output, after Claude Code's textual substitution of the
    two variables."""
    script = line.replace("${CLAUDE_SKILL_DIR}", str(skill_dir)).replace(
        "${CLAUDE_PROJECT_DIR}", str(project)
    )
    return subprocess.run(
        ["bash", "-c", script],
        capture_output=True,
        text=True,
        check=True,
        env={"PATH": os.environ["PATH"]},
    ).stdout


def test_some_skill_has_a_preferences_section():
    assert SECTIONS


def test_every_preferences_line_is_in_a_preferences_section():
    assert READERS == SECTIONS


@pytest.mark.parametrize("path", SECTIONS, ids=lambda path: path.parent.name)
def test_the_line_prints_nothing_when_neither_file_exists(path, tmp_path):
    skill_dir = tmp_path / "skills" / path.parent.name
    skill_dir.mkdir(parents=True)
    assert run(command_line(path), skill_dir, tmp_path / "project") == ""


@pytest.mark.parametrize("path", SECTIONS, ids=lambda path: path.parent.name)
def test_the_line_reads_both_files_through_a_symlinked_skill_folder(path, tmp_path):
    skill = path.parent.name
    store = tmp_path / "nix" / "store" / "hash-skill" / "share" / "claude-skills" / skill
    store.mkdir(parents=True)
    (store.parent / f"{skill}.preferences.md").write_text("- Store: never\n", encoding="utf-8")
    skills =tmp_path / "home dir" / ".claude" / "skills"
    skills.mkdir(parents=True)
    (skills / skill).symlink_to(store, target_is_directory=True)
    (skills / f"{skill}.preferences.md").write_text("- User: yes\n", encoding="utf-8")
    project = tmp_path / "the project"
    (project / ".agents" / "skills").mkdir(parents=True)
    (project / ".agents" / "skills" / f"{skill}.preferences.md").write_text(
        "- Project: yes\n", encoding="utf-8"
    )

    assert run(command_line(path), skills / skill, project) == "- User: yes\n- Project: yes\n"
