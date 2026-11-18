#!/usr/bin/env python3
"""Integration tests for tidy-branches.py: run the script against throwaway
repositories with a local bare remote and a fake `gh` on PATH, so they need
git 2.44+ but no network and no GitHub login.

    git-skills test git-workflow-tidy-branches
"""

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

from skill_scripts import scripts_dir

NAME = "git-workflow-tidy-branches"
SCRIPTS = scripts_dir(NAME)
SCRIPT = SCRIPTS / "tidy-branches.py"
PREFS_FILE = f"{NAME}.preferences.md"

GIT_ENV = {
    "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
}

# Prints the open pull requests listed in $FAKE_GH_PRS, as `gh pr list --json` would.
FAKE_GH = f"""#!{sys.executable}
import json, os, sys
names = json.load(open(os.environ["FAKE_GH_PRS"]))
json.dump([{{"headRefName": n}} for n in names], sys.stdout)
"""


class RepoFixture(unittest.TestCase):
    """A repository with one commit on main, pushed to a bare `origin`."""

    def setUp(self):
        self.tmp = pathlib.Path(os.path.realpath(tempfile.mkdtemp()))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.home = self.tmp / "home"
        fake_bin = self.tmp / "bin"
        fake_bin.mkdir()
        (fake_bin / "gh").write_text(FAKE_GH)
        (fake_bin / "gh").chmod(0o755)
        self.prs_file = self.tmp / "prs.json"
        self.open_prs()
        env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE_")}
        self.env = dict(
            env, **GIT_ENV,
            HOME=str(self.home),
            PATH=f"{fake_bin}{os.pathsep}{env.get('PATH', '')}",
            FAKE_GH_PRS=str(self.prs_file),
            CLAUDE_SKILL_DIR=str(self.home / ".claude" / "skills" / NAME),
        )
        self.origin = self.tmp / "origin.git"
        self.repo = self.tmp / "repo"
        self.git(self.tmp, "init", "-q", "--bare", "-b", "main", str(self.origin))
        self.git(self.tmp, "init", "-q", "-b", "main", str(self.repo))
        self.git(self.repo, "remote", "add", "origin", str(self.origin))
        self.commit("a.txt", "1\n2\n3\n", "base")
        self.git(self.repo, "push", "-q", "-u", "origin", "main")
        self.git(self.repo, "remote", "set-head", "origin", "main")

    def git(self, cwd, *args):
        return subprocess.run(["git", *args], cwd=cwd, env=self.env, check=True,
                              capture_output=True, text=True).stdout.strip()

    def commit(self, path, text, msg, cwd=None):
        cwd = cwd or self.repo
        (pathlib.Path(cwd) / path).write_text(text)
        self.git(cwd, "add", path)
        self.git(cwd, "commit", "-q", "-m", msg)
        return self.git(cwd, "rev-parse", "HEAD")

    def open_prs(self, *names):
        self.prs_file.write_text(json.dumps(names))

    def tidy(self, *argv, stdin=""):
        r = subprocess.run([sys.executable, str(SCRIPT), *argv], cwd=self.repo, env=self.env,
                           input=stdin, capture_output=True, text=True)
        return r.returncode, r.stdout

    def report(self):
        code, out = self.tidy("report")
        self.assertEqual(code, 0, out)
        return out

    def refs(self, cwd, prefix="refs/heads"):
        out = self.git(cwd, "for-each-ref", "--format=%(refname:short) %(objectname)", prefix)
        return dict(line.split() for line in out.splitlines())


class Report(RepoFixture):
    def build(self):
        """One branch per case the report tells apart; returns their shas."""
        r = self.repo
        sha = {}
        # merged by ancestry, also on the remote
        self.git(r, "switch", "-q", "-c", "ff")
        sha["ff"] = self.commit("ff.txt", "ff\n", "ff")
        self.git(r, "push", "-q", "origin", "ff")
        self.git(r, "switch", "-q", "main")
        self.git(r, "merge", "-q", "--ff-only", "ff")
        # squash-merged: two commits, landed as one
        self.git(r, "switch", "-q", "-c", "squashed")
        self.commit("sq.txt", "x\n", "sq 1")
        sha["squashed"] = self.commit("sq.txt", "x\ny\n", "sq 2")
        self.git(r, "switch", "-q", "main")
        self.commit("sq.txt", "x\ny\n", "squash of squashed")
        # behind, clean, pushed
        self.git(r, "switch", "-q", "-c", "behind", "HEAD~2")
        sha["behind"] = self.commit("b.txt", "b\n", "behind")
        self.git(r, "push", "-q", "origin", "behind")
        # behind, conflicting
        self.git(r, "switch", "-q", "-c", "conflict", "main~2")
        self.commit("a.txt", "1\nX\n3\n", "conflict")
        # a stack: s2 on s1
        self.git(r, "switch", "-q", "-c", "s1", "main~2")
        self.commit("s.txt", "1\n", "s1")
        self.git(r, "switch", "-q", "-c", "s2")
        self.commit("s.txt", "1\n2\n", "s2")
        # diverged from its remote copy
        self.git(r, "switch", "-q", "-c", "diverged", "main~2")
        self.commit("d.txt", "local\n", "d local")
        self.git(r, "push", "-q", "origin", "HEAD:refs/heads/diverged")
        self.git(r, "commit", "-q", "--amend", "-m", "d local rewritten")
        # behind, checked out in another worktree
        self.busy = self.tmp / "busy"
        self.git(r, "branch", "busy", "main~2")
        self.git(r, "worktree", "add", "-q", str(self.busy), "busy")
        self.commit("busy.txt", "busy\n", "busy", cwd=self.busy)
        self.git(r, "switch", "-q", "main")
        sha["main"] = self.commit("a.txt", "1\nM\n3\n", "main moves")
        self.git(r, "push", "-q", "origin", "main")
        return sha

    def plan(self, sha):
        """The report `build` should produce, line by line."""
        return [
            f"base\torigin/main\t{sha['main']}",
            f"ask\tdelete-local\tff\t{sha['ff']}",
            f"ask\tdelete-local\tsquashed\t{sha['squashed']}",
            f"ask\trebase\tbehind\t{sha['behind']}\t{sha['main']}",
            f"ask\tpush\torigin\tbehind\t{sha['behind']}",
            f"note\tbusy\tbehind origin/main; checked out in {self.busy}, rebase it there",
            "note\tconflict\tbehind origin/main; rebasing it conflicts",
            "note\tdiverged\tdiffers from origin/diverged: each has commits the other lacks",
            "note\ts1\tstacked (1 branch on it); restack with a stack tool",
            "note\ts2\tstacked (on s1); restack with a stack tool",
            f"ask\tdelete-remote\torigin\tff\t{sha['ff']}",
        ]

    def test_plan(self):
        sha = self.build()
        self.assertEqual(self.report().splitlines(), self.plan(sha))

    def test_report_moves_no_branch(self):
        self.build()
        before = (self.refs(self.repo, "refs"), self.refs(self.origin, "refs"))
        self.report()
        self.assertEqual((self.refs(self.repo, "refs"), self.refs(self.origin, "refs")), before)

    def test_open_pull_request_keeps_a_merged_branch(self):
        sha = self.build()
        self.open_prs("ff")
        held = "merged into origin/main, but its pull request is still open"
        expected = [l for l in self.plan(sha) if "\tff\t" not in l]
        expected.insert(1, f"note\tff\t{held}")
        expected.append(f"note\torigin/ff\t{held}")
        self.assertEqual(self.report().splitlines(), expected)

    def test_apply(self):
        sha = self.build()
        local, remote = self.refs(self.repo), self.refs(self.origin)
        plan = self.report()
        code, out = self.tidy("apply", stdin=plan)
        self.assertEqual(code, 0, out)
        actions = [l for l in plan.splitlines() if l.startswith("ask\t")]
        self.assertEqual([l.split("\t")[0] for l in out.splitlines()], ["done"] * len(actions), out)

        after = self.refs(self.repo)
        self.assertEqual(set(after), set(local) - {"ff", "squashed"})
        self.assertEqual(self.git(self.repo, "rev-parse", "behind~1"), sha["main"])
        self.assertEqual(self.git(self.repo, "log", "--format=%s", "main..behind"), "behind")
        for untouched in ("main", "busy", "conflict", "diverged", "s1", "s2"):
            self.assertEqual(after[untouched], local[untouched], untouched)

        on_origin = self.refs(self.origin)
        self.assertEqual(set(on_origin), set(remote) - {"ff"})
        self.assertEqual(on_origin["behind"], after["behind"])
        self.assertEqual(on_origin["diverged"], remote["diverged"])
        self.assertEqual(on_origin["main"], remote["main"])

    def test_apply_skips_a_branch_that_moved(self):
        sha = self.build()
        plan = self.report()
        self.git(self.repo, "branch", "-f", "behind", "main")
        rebase = next(l for l in plan.splitlines() if "\trebase\tbehind\t" in l)
        code, out = self.tidy("apply", stdin=rebase)
        self.assertEqual(code, 1)
        self.assertEqual(out, f"skipped\trebase behind {sha['behind']} {sha['main']}\t"
                              "branch moved since the report\n")
        self.assertEqual(self.refs(self.repo)["behind"], sha["main"])

    def test_fork_base_is_upstream(self):
        # A fork's own main holds branches upstream hasn't taken: measured
        # against it, they'd all look merged.
        r = self.repo
        upstream_main = self.git(r, "rev-parse", "main")
        upstream = self.tmp / "upstream.git"
        self.git(self.tmp, "clone", "-q", "--bare", str(self.origin), str(upstream))
        self.git(r, "remote", "add", "upstream", str(upstream))
        self.git(r, "fetch", "-q", "upstream")
        self.git(r, "switch", "-q", "-c", "feature")
        self.commit("f.txt", "f\n", "feature")
        self.git(r, "switch", "-q", "main")
        self.git(r, "merge", "-q", "--no-ff", "-m", "integrate", "feature")
        self.git(r, "push", "-q", "origin", "main")
        self.assertEqual(self.report(), f"base\tupstream/main\t{upstream_main}\n\n")

    def test_preference_no_rebase(self):
        sha = self.build()
        self.tidy("prefs", "set", "--scope", "project", "rebase", "no")
        expected = self.plan(sha)
        expected.insert(1, "note\t-\tpreference rebase: no")
        expected = [l for l in expected
                    if "\tbehind\t" not in l and not l.startswith("note\tconflict\t")]
        self.assertEqual(self.report().splitlines(), expected)

    def test_preference_yes_is_auto(self):
        sha = self.build()
        self.tidy("prefs", "set", "--scope", "project", "delete merged", "yes")
        expected = [l.replace("ask\tdelete-", "auto\tdelete-") for l in self.plan(sha)]
        self.assertEqual(self.report().splitlines(), expected)


class Prefs(RepoFixture):
    def project_file(self):
        return self.repo / ".agents" / "skills" / PREFS_FILE

    def shown(self):
        code, out = self.tidy("prefs", "show")
        self.assertEqual(code, 0, out)
        return out.splitlines()

    def test_project_scope_writes_file(self):
        code, out = self.tidy("prefs", "set", "--scope", "project", "keep", "main,integration")
        self.assertEqual((code, out), (0, f"wrote\t{self.project_file()}\n"))
        self.assertEqual(self.project_file().read_text(), "- Keep:\n  - main\n  - integration\n")
        self.assertIn("pref\tkeep\tmain, integration\tproject", self.shown())

    def test_user_scope_prints_home_manager_change(self):
        code, out = self.tidy("prefs", "set", "rebase", "no")
        self.assertEqual(code, 0)
        user_file = self.home / ".claude" / "skills" / PREFS_FILE
        self.assertEqual(out, "".join([
            f"# Home Manager generates {user_file}. Add this to the Home Manager config, then switch:\n",
            f'home.file.".claude/skills/{PREFS_FILE}".text = \'\'\n',
            "  - Rebase: no\n",
            "'';\n",
        ]))
        self.assertFalse(user_file.exists())

    def test_installed_in_project_saves_to_project(self):
        self.env["CLAUDE_SKILL_DIR"] = str(self.repo / ".claude" / "skills" / NAME)
        self.assertIn("installed\tproject", self.shown())
        self.tidy("prefs", "set", "rebase", "yes")
        self.assertEqual(self.project_file().read_text(), "- Rebase: yes\n")

    def test_user_file_overridden_by_project(self):
        user = self.home / ".claude" / "skills" / PREFS_FILE
        user.parent.mkdir(parents=True)
        user.write_text("- Rebase: no\n- Push remote: fork\n")
        self.tidy("prefs", "set", "--scope", "project", "rebase", "yes")
        shown = self.shown()
        self.assertIn("installed\tuser", shown)
        self.assertIn("pref\trebase\tyes\tproject", shown)
        self.assertIn("pref\tpush remote\tfork\tuser", shown)
        self.assertIn("pref\tdelete merged\task\tdefault", shown)

    def test_no_preferences_files_runs_on_the_defaults(self):
        shown = self.shown()
        self.assertIn(f"file\tdefault\t{SCRIPTS / 'tidy-branches.defaults.md'}\texists", shown)
        self.assertIn(f"file\tproject\t{self.project_file()}\tabsent", shown)
        prefs = [l for l in shown if l.startswith("pref\t")]
        self.assertEqual(prefs, [
            "pref\tbase\t\tdefault",
            "pref\tpush remote\torigin\tdefault",
            "pref\tkeep\tmain, master, release/*\tdefault",
            "pref\tdelete merged\task\tdefault",
            "pref\trebase\task\tdefault",
            "pref\trebase open pull requests\task\tdefault",
        ])
        code, out = self.tidy("report", "--no-fetch")
        self.assertEqual(code, 0, out)

    def test_unknown_key_is_refused(self):
        self.project_file().parent.mkdir(parents=True)
        self.project_file().write_text("- Rebase: no\n- Push remot: fork\n")
        code, out = self.tidy("report")
        self.assertEqual((code, out), (1, ""))

    def test_bad_mode_is_refused(self):
        self.project_file().parent.mkdir(parents=True)
        self.project_file().write_text("- Rebase: sometimes\n")
        code, out = self.tidy("report")
        self.assertEqual((code, out), (1, ""))


if __name__ == "__main__":
    unittest.main()
