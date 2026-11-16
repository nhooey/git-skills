"""Tests for git_skills.py: its argument parsing and its pure core."""

import contextlib
import io
import pathlib
import unittest

import git_skills
from git_skills import Skill

GOOD = """---
name: git-hygiene-example
description: |
  Does a thing.
  tags: [not-a-key, because-indented]
tags: [style, safety]
---

# Body
name: not-frontmatter
"""


def skill(text=GOOD, name="git-hygiene-example", has_tests=False):
    return Skill(name=name, skill_md=text, has_tests=has_tests)


class Frontmatter(unittest.TestCase):
    def test_reads_top_level_keys_only(self):
        self.assertEqual(
            git_skills.frontmatter(GOOD),
            {"name": "git-hygiene-example", "description": "|", "tags": "[style, safety]"},
        )

    def test_none_without_opening_fence(self):
        self.assertIsNone(git_skills.frontmatter("name: x\n"))

    def test_none_without_closing_fence(self):
        self.assertIsNone(git_skills.frontmatter("---\nname: x\n"))

    def test_none_for_empty_file(self):
        self.assertIsNone(git_skills.frontmatter(""))


class FlowList(unittest.TestCase):
    def test_splits_items(self):
        self.assertEqual(git_skills.flow_list("[a, b ,c]"), ("a", "b", "c"))

    def test_empty_list(self):
        self.assertEqual(git_skills.flow_list("[]"), ())

    def test_none_for_scalar(self):
        self.assertIsNone(git_skills.flow_list("style"))


class Lint(unittest.TestCase):
    def test_clean_skill(self):
        self.assertEqual(git_skills.lint(skill()), ())

    def test_missing_skill_md(self):
        self.assertEqual(git_skills.lint(skill(text=None)), ("has no SKILL.md",))

    def test_missing_frontmatter(self):
        self.assertEqual(
            git_skills.lint(skill(text="# Title\n")),
            ("SKILL.md has no YAML frontmatter between `---` lines",),
        )

    def test_name_differs_from_folder(self):
        self.assertEqual(
            git_skills.lint(skill(name="git-hygiene-other")),
            ("frontmatter name `git-hygiene-example` isn't the folder name",),
        )

    def test_folder_case_and_pack(self):
        text = GOOD.replace("git-hygiene-example", "Misc_Thing")
        self.assertEqual(
            git_skills.lint(skill(text=text, name="Misc_Thing")),
            (
                "folder name isn't lowercase-with-hyphens",
                "name starts with none of the packs: " + ", ".join(git_skills.PACKS),
            ),
        )

    def test_missing_keys(self):
        self.assertEqual(
            git_skills.lint(skill(text="---\nname: git-hygiene-example\n---\n")),
            ("frontmatter has no `description`", "frontmatter has no `tags`"),
        )

    def test_unknown_tag(self):
        self.assertEqual(
            git_skills.lint(skill(text=GOOD.replace("safety", "shiny"))),
            ("tag `shiny` isn't in the README's tag vocabulary",),
        )

    def test_tags_not_a_flow_list(self):
        self.assertEqual(
            git_skills.lint(skill(text=GOOD.replace("[style, safety]", "style"))),
            ("tags isn't a flow list such as `[style, safety]`",),
        )


class Select(unittest.TestCase):
    SKILLS = (skill(name="a"), skill(name="b"), skill(name="c"))

    def test_all_without_names(self):
        self.assertEqual(git_skills.select(self.SKILLS, ()), (self.SKILLS, ()))

    def test_named_in_given_order(self):
        chosen, unknown = git_skills.select(self.SKILLS, ("c", "a"))
        self.assertEqual(tuple(s.name for s in chosen), ("c", "a"))
        self.assertEqual(unknown, ())

    def test_reports_unknown(self):
        self.assertEqual(git_skills.select(self.SKILLS, ("a", "zz"))[1], ("zz",))


class Parser(unittest.TestCase):
    def parse(self, *argv):
        return git_skills.parser().parse_args(argv)

    def test_test_with_skills(self):
        args = self.parse("test", "x", "y")
        self.assertEqual((args.command, args.skills), ("test", ["x", "y"]))

    def test_lint_without_skills(self):
        self.assertEqual(self.parse("lint").skills, [])

    def test_list_tested(self):
        self.assertTrue(self.parse("list", "--tested").tested)

    def test_root(self):
        self.assertEqual(self.parse("--root", "/r", "lint").root, pathlib.Path("/r"))

    def test_command_required(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as e:
            self.parse()
        self.assertEqual(e.exception.code, 2)

    def test_help_lists_commands(self):
        text = git_skills.parser().format_help()
        for command in ("test", "lint", "list", "--root"):
            self.assertIn(command, text)


if __name__ == "__main__":
    unittest.main()
