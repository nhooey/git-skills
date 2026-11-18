"""Finds the scripts a skill ships, for the tests in tests/<skill>/, and
loads one whose file name isn't a module name, such as `tidy-branches.py`."""

import importlib.util
import pathlib

REPO = pathlib.Path(__file__).resolve().parent.parent
SKILLS = REPO / "skills"


def scripts_dir(skill):
    """The `scripts/` folder of the skill named `skill`."""
    return SKILLS / skill / "scripts"


def load_script(skill, filename):
    """The Python script `filename` in a skill's `scripts/`, loaded as a
    module named after the file."""
    path = scripts_dir(skill) / filename
    spec = importlib.util.spec_from_file_location(path.stem.replace("-", "_"), path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
