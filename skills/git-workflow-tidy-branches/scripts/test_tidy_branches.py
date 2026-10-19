#!/usr/bin/env python3
"""Offline self-check for tidy-branches.py: builds throwaway repos with a
local bare remote, so it needs git 2.44+ but no network or `gh`.

    python3 test_tidy_branches.py
"""

import contextlib
import importlib.util
import io
import os
import pathlib
import subprocess
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("tidy", HERE / "tidy-branches.py")
tidy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tidy)
tidy.open_pull_requests = lambda: set()

ENV = {
    "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
}


def sh(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def commit(cwd, path, text, msg):
    (pathlib.Path(cwd) / path).write_text(text)
    sh(cwd, "add", path)
    sh(cwd, "commit", "-q", "-m", msg)
    return sh(cwd, "rev-parse", "HEAD")


class Repo(unittest.TestCase):
    def setUp(self):
        self._env = {k: os.environ.get(k) for k in [*ENV, "CLAUDE_SKILL_DIR", "CLAUDE_PROJECT_DIR", "HOME"]}
        os.environ.update(ENV)
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.home = self.tmp / "home"
        os.environ["HOME"] = str(self.home)
        os.environ["CLAUDE_SKILL_DIR"] = str(self.home / ".claude" / "skills" / tidy.NAME)
        os.environ.pop("CLAUDE_PROJECT_DIR", None)
        self.origin = self.tmp / "origin.git"
        self.repo = self.tmp / "repo"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(self.origin)], check=True)
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.repo)], check=True)
        r = self.repo
        sh(r, "remote", "add", "origin", str(self.origin))
        commit(r, "a.txt", "1\n2\n3\n", "base")
        sh(r, "push", "-q", "-u", "origin", "main")
        sh(r, "remote", "set-head", "origin", "main")
        self.cwd = os.getcwd()
        os.chdir(r)

    def tearDown(self):
        os.chdir(self.cwd)
        for k, v in self._env.items():
            os.environ.pop(k, None) if v is None else os.environ.__setitem__(k, v)

    def call(self, *argv, stdin=""):
        out = io.StringIO()
        old = tidy.sys.stdin
        tidy.sys.stdin = io.StringIO(stdin)
        try:
            with contextlib.redirect_stdout(out):
                code = tidy.main(list(argv))
        finally:
            tidy.sys.stdin = old
        return code, out.getvalue()

    def report(self):
        code, out = self.call("report")
        self.assertEqual(code, 0)
        return out


class Report(Repo):
    def build(self):
        r = self.repo
        # merged by ancestry, also on the remote
        sh(r, "switch", "-q", "-c", "ff")
        commit(r, "ff.txt", "ff\n", "ff")
        sh(r, "push", "-q", "origin", "ff")
        sh(r, "switch", "-q", "main")
        sh(r, "merge", "-q", "--ff-only", "ff")
        # squash-merged: two commits, landed as one
        sh(r, "switch", "-q", "-c", "squashed")
        commit(r, "sq.txt", "x\n", "sq 1")
        commit(r, "sq.txt", "x\ny\n", "sq 2")
        sh(r, "switch", "-q", "main")
        commit(r, "sq.txt", "x\ny\n", "squash of squashed")
        # behind, clean, pushed
        sh(r, "switch", "-q", "-c", "behind", "HEAD~2")
        self.behind = commit(r, "b.txt", "b\n", "behind")
        sh(r, "push", "-q", "origin", "behind")
        # behind, conflicting
        sh(r, "switch", "-q", "-c", "conflict", "main~2")
        commit(r, "a.txt", "1\nX\n3\n", "conflict")
        # a stack: s2 on s1
        sh(r, "switch", "-q", "-c", "s1", "main~2")
        commit(r, "s.txt", "1\n", "s1")
        sh(r, "switch", "-q", "-c", "s2")
        commit(r, "s.txt", "1\n2\n", "s2")
        # diverged from its remote copy
        sh(r, "switch", "-q", "-c", "diverged", "main~2")
        commit(r, "d.txt", "local\n", "d local")
        sh(r, "push", "-q", "origin", "HEAD:refs/heads/diverged")
        sh(r, "commit", "-q", "--amend", "-m", "d local rewritten")
        # behind, checked out in another worktree
        sh(r, "branch", "busy", "main~2")
        sh(r, "worktree", "add", "-q", str(self.tmp / "busy"), "busy")
        commit(self.tmp / "busy", "busy.txt", "busy\n", "busy")
        sh(r, "switch", "-q", "main")
        main = commit(r, "a.txt", "1\nM\n3\n", "main moves")
        sh(r, "push", "-q", "origin", "main")
        return main

    def test_plan(self):
        main = self.build()
        lines = self.report().splitlines()
        self.assertEqual(lines[0], f"base\torigin/main\t{main}")
        body = lines[1:]
        actions = {tuple(l.split("\t")[1:3]) for l in body if not l.startswith("note")}
        notes = {l.split("\t")[1]: l.split("\t")[2] for l in body if l.startswith("note")}
        self.assertIn(("delete-local", "ff"), actions)
        self.assertIn(("delete-local", "squashed"), actions)
        self.assertIn(("delete-remote", "origin"), actions)
        self.assertIn(("rebase", "behind"), actions)
        self.assertIn(("push", "origin"), actions)
        self.assertIn("conflicts", notes["conflict"])
        self.assertIn("stacked (on s1)", notes["s2"])
        self.assertIn("stacked (1 branch on it)", notes["s1"])
        self.assertIn("each has commits", notes["diverged"])
        self.assertIn("checked out in", notes["busy"])
        self.assertNotIn("main", {l.split("\t")[2] for l in body if "\tdelete-local\t" in l})
        for l in body:
            if not l.startswith("note"):
                self.assertEqual(l.split("\t")[0], "ask")

    def test_report_moves_no_branch(self):
        self.build()
        before = sh(self.repo, "for-each-ref", "refs/heads")
        self.report()
        self.assertEqual(sh(self.repo, "for-each-ref", "refs/heads"), before)

    def test_apply(self):
        main = self.build()
        plan = self.report()
        code, out = self.call("apply", stdin=plan)
        self.assertEqual(code, 0, out)
        heads = sh(self.repo, "for-each-ref", "--format=%(refname:short)", "refs/heads").split()
        self.assertNotIn("ff", heads)
        self.assertNotIn("squashed", heads)
        self.assertEqual(sh(self.repo, "rev-parse", "behind~1"), main)
        self.assertEqual(sh(self.origin, "rev-parse", "behind"), sh(self.repo, "rev-parse", "behind"))
        self.assertNotIn("ff", sh(self.origin, "for-each-ref", "--format=%(refname:short)", "refs/heads").split())

    def test_apply_skips_a_branch_that_moved(self):
        self.build()
        plan = self.report()
        sh(self.repo, "branch", "-f", "behind", "main")
        code, out = self.call("apply", stdin="\n".join(l for l in plan.splitlines() if "\tbehind\t" in l))
        self.assertEqual(code, 1)
        self.assertIn("skipped\trebase behind", out)
        self.assertIn("moved since the report", out)

    def test_fork_base_is_upstream(self):
        # A fork's own main holds branches upstream hasn't taken: measured
        # against it, they'd all look merged.
        r = self.repo
        upstream = self.tmp / "upstream.git"
        subprocess.run(["git", "clone", "-q", "--bare", str(self.origin), str(upstream)], check=True)
        sh(r, "remote", "add", "upstream", str(upstream))
        sh(r, "fetch", "-q", "upstream")
        sh(r, "switch", "-q", "-c", "feature")
        commit(r, "f.txt", "f\n", "feature")
        sh(r, "switch", "-q", "main")
        sh(r, "merge", "-q", "--no-ff", "-m", "integrate", "feature")
        sh(r, "push", "-q", "origin", "main")
        out = self.report()
        self.assertTrue(out.startswith("base\tupstream/main\t"), out)
        self.assertNotIn("delete-local\tfeature", out)

    def test_preference_no_rebase(self):
        self.build()
        self.call("prefs", "set", "--scope", "project", "rebase", "no")
        out = self.report()
        self.assertNotIn("\trebase\t", out)
        self.assertIn("preference rebase: no", out)

    def test_preference_yes_is_auto(self):
        self.build()
        self.call("prefs", "set", "--scope", "project", "delete merged", "yes")
        self.assertIn("auto\tdelete-local\tff\t", self.report())


class Prefs(Repo):
    def test_round_trip(self):
        prefs = {"base": "upstream/main", "keep": ["main", "integration"], "rebase": "no"}
        self.assertEqual(tidy.parse_prefs(tidy.render_prefs(prefs)), prefs)

    def test_parse_comma_list_and_backticks(self):
        self.assertEqual(tidy.parse_prefs("- Keep: `main`, release/*\n")["keep"], ["main", "release/*"])

    def test_project_scope_writes_file(self):
        code, out = self.call("prefs", "set", "--scope", "project", "keep", "main,integration")
        self.assertEqual(code, 0)
        path = self.repo / ".agents" / "skills" / f"{tidy.NAME}.preferences.md"
        self.assertEqual(path.read_text(), "- Keep:\n  - main\n  - integration\n")
        _, shown = self.call("prefs", "show")
        self.assertIn("pref\tkeep\tmain, integration\tproject", shown)

    def test_user_scope_prints_home_manager_change(self):
        code, out = self.call("prefs", "set", "rebase", "no")
        self.assertEqual(code, 0)
        self.assertIn(f'home.file.".claude/skills/{tidy.NAME}.preferences.md".text', out)
        self.assertIn("  - Rebase: no\n", out)
        self.assertFalse((self.home / ".claude" / "skills" / f"{tidy.NAME}.preferences.md").exists())

    def test_installed_in_project_saves_to_project(self):
        os.environ["CLAUDE_SKILL_DIR"] = str(self.repo / ".claude" / "skills" / tidy.NAME)
        self.assertEqual(tidy.installed_scope(), "project")
        self.call("prefs", "set", "rebase", "yes")
        self.assertTrue((self.repo / ".agents" / "skills" / f"{tidy.NAME}.preferences.md").exists())

    def test_user_file_overridden_by_project(self):
        user = self.home / ".claude" / "skills" / f"{tidy.NAME}.preferences.md"
        user.parent.mkdir(parents=True)
        user.write_text("- Rebase: no\n- Push remote: fork\n")
        self.call("prefs", "set", "--scope", "project", "rebase", "yes")
        prefs, source = tidy.load_prefs()
        self.assertEqual((prefs["rebase"], source["rebase"]), ("yes", "project"))
        self.assertEqual((prefs["push remote"], source["push remote"]), ("fork", "user"))


if __name__ == "__main__":
    unittest.main()
