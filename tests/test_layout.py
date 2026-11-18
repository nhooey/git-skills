"""The repository's layout: a skill's folder holds only what an installed
skill runs, its tests are in tests/<skill>/, and its Python scripts import
only the standard library and each other."""

import ast
import sys

import pytest

from skill_scripts import REPO, SKILLS

TESTS = REPO / "tests"
# Folders of tests or of their data; no skill ships a folder by these names.
TEST_DIRS = frozenset({"test", "tests", "golden", "stubs"})
SCRIPTS = tuple(sorted(SKILLS.glob("*/scripts/**/*.py")))


def is_test_path(path):
    """Whether a path is a test file or a folder of tests."""
    if path.is_dir():
        return path.name in TEST_DIRS
    return path.name.startswith("test_") or path.stem.endswith("_test") or path.suffix == ".bats"


def imported_modules(source):
    """The top-level name of each module a Python source imports, relative
    imports by the name they import from their own folder."""
    return frozenset(
        name
        for node in ast.walk(ast.parse(source))
        for name in (
            tuple(alias.name.split(".")[0] for alias in node.names)
            if isinstance(node, ast.Import)
            else (node.module.split(".")[0],)
            if isinstance(node, ast.ImportFrom) and node.level == 0
            else (node.module.split(".")[0],)
            if isinstance(node, ast.ImportFrom) and node.module
            else tuple(alias.name for alias in node.names)
            if isinstance(node, ast.ImportFrom)
            else ()
        )
    )


def sibling_modules(folder):
    """The modules a script in `folder` can import from beside it."""
    return frozenset(p.stem for p in folder.glob("*.py")) | frozenset(
        d.name for d in folder.iterdir() if (d / "__init__.py").is_file()
    )


def test_no_test_is_inside_a_skill():
    found = tuple(str(p.relative_to(REPO)) for p in sorted(SKILLS.rglob("*")) if is_test_path(p))
    assert found == (), "tests belong in tests/<skill>/, not in the skill's folder"


def test_every_test_folder_names_a_skill():
    folders = sorted(d.name for d in TESTS.iterdir() if d.is_dir() and d.name != "__pycache__")
    assert tuple(f for f in folders if not (SKILLS / f).is_dir()) == ()


@pytest.mark.parametrize("script", SCRIPTS, ids=lambda p: str(p.relative_to(SKILLS)))
def test_skill_script_imports_only_the_standard_library(script):
    allowed = sys.stdlib_module_names | sibling_modules(script.parent)
    assert sorted(imported_modules(script.read_text()) - allowed) == []
