#!/usr/bin/env python3
"""Unit tests for tidy-branches.py's pure parts: the plan, stack detection and
preferences, fed values instead of a repository. The git-backed tests are in
test_tidy_branches_git.py.

    python3 test_tidy_branches.py
"""

import importlib.util
import pathlib
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("tidy", HERE / "tidy-branches.py")
tidy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tidy)


class Graph:
    """A commit graph as child -> parents, answering what `tidy.Git` answers."""

    def __init__(self, parents, squashed=(), merges=(), conflicts=()):
        self.parents = parents
        self.squashed = set(squashed)
        self.merge_tips = set(merges)
        self.conflicts = set(conflicts)

    def ancestor(self, a, b):
        todo = [b]
        while todo:
            c = todo.pop()
            if c == a:
                return True
            todo += self.parents.get(c, [])
        return False

    def merged(self, tip, base):
        return self.ancestor(tip, base) or tip in self.squashed

    def has_merges(self, base, tip):
        return tip in self.merge_tips

    def replays(self, branch, onto):
        return branch not in self.conflicts


# Base history m0 <- m1 <- m2; every other commit sits on m0 unless noted.
GRAPH = Graph(
    {
        "m1": ["m0"], "m2": ["m1"], "n1": ["m2"],
        "q1": ["m0"], "b1": ["m0"], "g1": ["m0"], "x1": ["m0"], "w1": ["m0"],
        "k1": ["m0"], "o1": ["m0"], "r1": ["m0"], "u1": ["m0"],
        "c0": ["m0"], "c1": ["c0"],
        "p0": ["m0"], "p1": ["p0"],
        "d0": ["m0"], "d1": ["d0"], "d2": ["d0"],
        "s1": ["m0"], "s2": ["s1"],
    },
    squashed=["q1"],
    merges=["x1"],
    conflicts=["conflict"],
)

BRANCHES = [
    ("behind", "b1", ""),          # rebased, then pushed over its remote copy
    ("busy-merged", "m1", ""),     # merged, but checked out
    ("conflict", "k1", ""),
    ("current", "n1", ""),         # already on the base
    ("diverged", "d1", ""),
    ("ff", "m1", ""),              # merged by ancestry
    ("gone", "g1", "[gone]"),      # unmerged with its upstream gone: still rebased
    ("main", "m2", ""),
    ("merges", "x1", ""),
    ("merged-pr", "m1", ""),
    ("open-pr", "o1", ""),
    ("pull-first", "p0", ""),
    ("release/1", "r1", ""),
    ("s1", "s1", ""),
    ("s2", "s2", ""),
    ("squashed", "q1", ""),
    ("unpushed", "c1", ""),        # ahead of its remote copy
    ("worktree", "w1", ""),
]

REMOTE_BRANCHES = {
    "HEAD": "m2", "behind": "b1", "diverged": "d2", "ff": "m1", "main": "m2",
    "merged-pr": "m1", "pull-first": "p1", "remote-only": "u1", "unpushed": "c0",
}

TREES = {"busy-merged": "/wt/a", "worktree": "/wt/b"}
PRS = {"merged-pr", "open-pr"}
PREFS = dict(tidy.DEFAULTS, rebase="yes")

FULL_PLAN = [
    "auto\tprune-worktrees",
    "note\tbusy-merged\tmerged into origin/main, but checked out in /wt/a",
    "ask\tdelete-local\tff\tm1",
    "note\tmerged-pr\tmerged into origin/main, but its pull request is still open",
    "ask\tdelete-local\tsquashed\tq1",
    "auto\trebase\tbehind\tb1\tm2",
    "auto\tpush\torigin\tbehind\tb1",
    "note\tconflict\tbehind origin/main; rebasing it conflicts",
    "note\tdiverged\tdiffers from origin/diverged: each has commits the other lacks",
    "note\tgone\tits upstream branch is gone, but it isn't merged",
    "auto\trebase\tgone\tg1\tm2",
    "note\tmerges\tbehind origin/main, but has merge commits; rebase by hand",
    "ask\trebase\topen-pr\to1\tm2",
    "note\tpull-first\torigin/pull-first has commits it lacks; pull first",
    "note\ts1\tstacked (1 branch on it); restack with a stack tool",
    "note\ts2\tstacked (on s1); restack with a stack tool",
    "auto\trebase\tunpushed\tc1\tm2",
    "note\tunpushed\thas commits not on origin; push it yourself after the rebase",
    "note\tworktree\tbehind origin/main; checked out in /wt/b, rebase it there",
    "ask\tdelete-remote\torigin\tff\tm1",
    "note\torigin/merged-pr\tmerged into origin/main, but its pull request is still open",
]


def plan(prefs=PREFS, prs=PRS, prunable=True):
    return tidy.plan(prefs, "origin/main", "main", "m2", BRANCHES, REMOTE_BRANCHES,
                     trees=TREES, prs=prs, prunable=prunable, graph=GRAPH)


class Plan(unittest.TestCase):
    def test_every_case(self):
        self.assertEqual(plan(), FULL_PLAN)

    def test_nothing_to_prune(self):
        self.assertEqual(plan(prunable=False), FULL_PLAN[1:])

    def test_unknown_pull_requests(self):
        # Without gh, merged-pr is an ordinary merged branch and open-pr an
        # ordinary behind one, under the `rebase` preference.
        becomes = {
            "note\tmerged-pr\tmerged into origin/main, but its pull request is still open":
                "ask\tdelete-local\tmerged-pr\tm1",
            "note\torigin/merged-pr\tmerged into origin/main, but its pull request is still open":
                "ask\tdelete-remote\torigin\tmerged-pr\tm1",
            "ask\trebase\topen-pr\to1\tm2": "auto\trebase\topen-pr\to1\tm2",
        }
        expected = ["note\t-\tgh unavailable: open pull requests unknown"]
        expected += [becomes.get(line, line) for line in FULL_PLAN]
        self.assertEqual(plan(prs=None), expected)

    def test_open_pull_requests_have_their_own_mode(self):
        lines = plan(prefs=dict(PREFS, **{"rebase open pull requests": "no"}))
        self.assertEqual(lines, ["note\t-\tpreference rebase open pull requests: no"]
                         + [l for l in FULL_PLAN if "\topen-pr\t" not in l])

    def test_all_no_leaves_only_notes(self):
        prefs = dict(PREFS, **{k: "no" for k in tidy.MODE_KEYS})
        lines = plan(prefs=prefs)
        self.assertEqual(sorted(lines[:3]), sorted(f"note\t-\tpreference {k}: no" for k in tidy.MODE_KEYS))
        acting = [l for l in lines[3:] if not l.startswith("note")]
        self.assertEqual(acting, ["auto\tprune-worktrees"])
        # A rebase that isn't wanted isn't tried, so its conflict isn't reported.
        self.assertNotIn("note\tconflict\tbehind origin/main; rebasing it conflicts", lines)
        self.assertIn("note\tworktree\tbehind origin/main; checked out in /wt/b, rebase it there", lines)

    def test_keep_patterns_and_base_name_are_never_touched(self):
        prefs = dict(PREFS, keep=["re*/*"], **{"delete merged": "yes"})
        lines = plan(prefs=prefs)
        touched = {l.split("\t")[2] for l in lines if l.split("\t")[0] in ("ask", "auto") and len(l.split("\t")) > 2}
        self.assertNotIn("release/1", touched)
        self.assertNotIn("main", touched)  # the base's own name is always kept
        self.assertIn("auto\tdelete-local\tff\tm1", lines)


class FindStacks(unittest.TestCase):
    def test_chain_names_nearest_parent_and_count(self):
        g = Graph({"t2": ["t1"], "t3": ["t2"], "t4": ["t0"]})
        stacks = tidy.find_stacks({"a": "t1", "b": "t2", "c": "t3", "lone": "t4"}, g.ancestor)
        self.assertEqual(stacks, {
            "a": ["2 branches on it"],
            "b": ["on a", "1 branch on it"],
            "c": ["on b"],
        })

    def test_no_stack(self):
        g = Graph({"t1": ["t0"], "t2": ["t0"]})
        self.assertEqual(tidy.find_stacks({"a": "t1", "b": "t2"}, g.ancestor), {})


class Prefs(unittest.TestCase):
    def test_round_trip(self):
        prefs = {"base": "upstream/main", "keep": ["main", "integration"], "rebase": "no"}
        self.assertEqual(tidy.parse_prefs(tidy.render_prefs(prefs)), prefs)

    def test_render_is_in_defaults_order(self):
        text = tidy.render_prefs({"rebase": "no", "keep": ["main"], "base": "b"})
        self.assertEqual(text, "- Base: b\n- Keep:\n  - main\n- Rebase: no\n")

    def test_parse_comma_list_and_backticks(self):
        self.assertEqual(tidy.parse_prefs("- Keep: `main`, release/*\n")["keep"], ["main", "release/*"])

    def test_later_layer_wins_and_records_its_scope(self):
        prefs, source = tidy.layer_prefs([
            ("user", {"rebase": "no", "push remote": "fork", "unknown": "x"}),
            ("project", {"rebase": "yes"}),
        ])
        self.assertEqual(prefs, dict(tidy.DEFAULTS, rebase="yes", **{"push remote": "fork"}))
        self.assertEqual(source, dict({k: "default" for k in tidy.DEFAULTS},
                                      rebase="project", **{"push remote": "user"}))


if __name__ == "__main__":
    unittest.main()
