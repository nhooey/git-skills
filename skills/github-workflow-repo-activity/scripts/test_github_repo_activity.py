#!/usr/bin/env python3
"""Offline self-check for github-repo-activity.py: a fake `gh api` stands in
for GitHub, so this runs without a network or a token.

    python3 test_github_repo_activity.py
"""

import importlib.util
import pathlib
import unittest
from datetime import datetime, timezone

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("activity", HERE / "github-repo-activity.py")
activity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(activity)

SINCE = datetime(2026, 10, 18, tzinfo=timezone.utc)
R = "o/r"


def user(login):
    return {"login": login}


def commit(sha, login, date, message):
    return {
        "sha": sha,
        "html_url": f"https://github.com/{R}/commit/{sha}",
        "author": user(login),
        "committer": user(login),
        "commit": {"message": message, "committer": {"date": date}},
    }


FIXTURES = {
    f"repos/{R}": {"default_branch": "main"},
    f"repos/{R}/issues?state=all&since=2026-10-18T00:00:00Z&per_page=100": [
        {"number": 1, "title": "Merged by maintainer", "user": user("contrib"),
         "created_at": "2026-10-10T00:00:00Z", "html_url": "u1",
         "pull_request": {"merged_at": "2026-10-18T10:00:00Z"}},
        {"number": 2, "title": "Question", "user": user("maint"),
         "created_at": "2026-10-18T12:00:00Z", "html_url": "u2",
         "pull_request": {"merged_at": None}},
        {"number": 3, "title": "Bug", "user": user("contrib"),
         "created_at": "2026-09-01T00:00:00Z", "html_url": "u3"},
    ],
    f"repos/{R}/pulls/1": {"number": 1, "title": "Merged by maintainer", "user": user("contrib"),
                           "merged_by": user("maint"), "merged_at": "2026-10-18T10:00:00Z",
                           "merge_commit_sha": "m1", "html_url": "u1"},
    f"repos/{R}/issues/comments?since=2026-10-18T00:00:00Z&per_page=100": [
        {"user": user("maint"), "issue_url": f"https://api.github.com/repos/{R}/issues/3",
         "created_at": "2026-10-18T11:00:00Z", "updated_at": "2026-10-18T11:00:00Z", "html_url": "c1"},
        {"user": user("maint"), "issue_url": f"https://api.github.com/repos/{R}/issues/3",
         "created_at": "2026-10-01T11:00:00Z", "updated_at": "2026-10-18T13:00:00Z", "html_url": "c2"},
        {"user": user("dependabot[bot]"), "issue_url": f"https://api.github.com/repos/{R}/issues/3",
         "created_at": "2026-10-18T11:00:00Z", "updated_at": "2026-10-18T11:00:00Z", "html_url": "c3"},
    ],
    f"repos/{R}/pulls/comments?since=2026-10-18T00:00:00Z&per_page=100": [],
    f"repos/{R}/pulls/1/reviews?per_page=100": [
        {"user": user("maint"), "state": "APPROVED", "submitted_at": "2026-10-18T09:00:00Z", "html_url": "r1"},
    ],
    f"repos/{R}/pulls/2/reviews?per_page=100": [],
    f"repos/{R}/issues/1/timeline?per_page=100": [
        {"event": "closed", "actor": user("maint"), "created_at": "2026-10-18T10:00:00Z"},
    ],
    f"repos/{R}/issues/2/timeline?per_page=100": [],
    f"repos/{R}/issues/3/timeline?per_page=100": [
        {"event": "closed", "actor": user("maint"), "created_at": "2026-10-18T14:00:00Z"},
    ],
    f"repos/{R}/branches?per_page=100": [{"name": "main"}, {"name": "topic"}],
    f"repos/{R}/commits?sha=main&since=2026-10-18T00:00:00Z&per_page=1": [
        commit("p1", "maint", "2026-10-18T15:00:00Z", "Direct push")],
    f"repos/{R}/commits?sha=topic&since=2026-10-18T00:00:00Z&per_page=1": [
        commit("t1", "maint", "2026-10-18T16:00:00Z", "Topic work")],
    f"repos/{R}/commits?sha=main&since=2026-10-18T00:00:00Z&per_page=100&author=maint": [
        commit("p1", "maint", "2026-10-18T15:00:00Z", "Direct push\n\nbody"),
        commit("m1", "maint", "2026-10-18T10:00:00Z", "Merge pull request #1"),
    ],
    f"repos/{R}/commits?sha=topic&since=2026-10-18T00:00:00Z&per_page=100&author=maint": [
        commit("t1", "maint", "2026-10-18T16:00:00Z", "Topic work")],
    f"repos/{R}/commits/p1/pulls": [],
    f"repos/{R}/commits/old1/pulls": [],
    f"repos/{R}/compare/p0...p1": {"commits": [commit("old1", "maint", "2026-10-17T20:00:00Z", "Made Friday")]},
    f"repos/{R}/compare/main...t1": {"commits": [commit("t1", "maint", "2026-10-18T16:00:00Z", "Topic work")]},
    f"repos/{R}/commits/t1/pulls": [{"number": 2, "merged_at": None}],
}


# Pushed Saturday; "old1" was committed Friday, before --since.
ACTIVITY = [
    {"timestamp": "2026-10-18T16:05:00Z", "activity_type": "branch_creation", "ref": "refs/heads/topic",
     "before": activity.NULL_SHA, "after": "t1", "actor": user("maint")},
    {"timestamp": "2026-10-18T08:00:00Z", "activity_type": "push", "ref": "refs/heads/main",
     "before": "p0", "after": "p1", "actor": user("maint")},
    {"timestamp": "2026-10-17T08:00:00Z", "activity_type": "push", "ref": "refs/heads/main",
     "before": "x0", "after": "p0", "actor": user("maint")},
]


def fake_get(path, paginate=True):
    if path.startswith(f"repos/{R}/activity?"):
        return ACTIVITY
    return FIXTURES[path]


def no_activity_get(path, paginate=True):
    if path.startswith(f"repos/{R}/activity?"):
        raise activity.GhError("HTTP 404")
    return FIXTURES[path]


def kinds(events):
    return sorted((e["kind"], e["number"]) for e in events)


class ActivityTest(unittest.TestCase):
    def setUp(self):
        self.a = activity.Activity(R, "Maint", SINCE, get=fake_get, jobs=2)

    def test_parse_since(self):
        now = datetime(2026, 10, 19, 12, tzinfo=timezone.utc)
        self.assertEqual(activity.parse_since("2026-10-18", now), SINCE)
        self.assertEqual(activity.parse_since("2026-10-18T02:00:00+02:00", now), SINCE)
        self.assertEqual(activity.parse_since("2026-10-18T00:00:00Z", now), SINCE)
        self.assertEqual(activity.parse_since("36h", now), SINCE)

    def test_comments_new_and_edited_without_bots(self):
        self.assertEqual(kinds(self.a.comments()), [("comment", 3), ("comment-edited", 3)])

    def test_merge_credited_to_merger_not_author(self):
        (merge,) = self.a.merges()
        self.assertEqual((merge["actor"], merge["number"], merge["detail"]), ("maint", 1, "by contrib"))

    def test_merged_pr_close_is_not_doubled(self):
        self.assertEqual(kinds(self.a.prs()), [("opened", 2)])
        self.assertEqual(kinds(self.a.issues()), [("closed", 3)])

    def test_commit_made_before_since_but_pushed_after_is_found_at_push_time(self):
        found = {e["detail"]: (e["kind"], e["number"], e["time"]) for e in self.a.commits()}
        self.assertEqual(found, {
            "main old1": ("commit", None, "2026-10-18T08:00:00Z"),
            "topic t1": ("commit-via-pr", 2, "2026-10-18T16:05:00Z"),
        })

    def test_branches_from_activity(self):
        self.assertEqual([(e["kind"], e["title"]) for e in self.a.branches()], [("branch-created", "topic")])

    def test_fallback_by_commit_date_drops_merge_commit_and_notes_it(self):
        a = activity.Activity(R, "maint", SINCE, get=no_activity_get)
        self.assertEqual(kinds(a.commits()), [("commit", None), ("commit-via-pr", 2)])
        self.assertEqual([e["detail"] for e in a.branches()], ["topic -> t1"])
        self.assertTrue(any("commit date" in n for n in a.notes))

    def test_summary_has_every_kind(self):
        self.assertEqual(
            {e["kind"] for e in self.a.summary()},
            {"comment", "comment-edited", "review-approved", "merged", "opened", "closed",
             "commit", "commit-via-pr", "branch-created"},
        )

    def test_everyone_mode_drops_bots_unless_asked(self):
        everyone = activity.Activity(R, None, SINCE, get=fake_get)
        self.assertEqual(len(everyone.comments()), 2)
        with_bots = activity.Activity(R, None, SINCE, include_bots=True, get=fake_get)
        self.assertEqual(len(with_bots.comments()), 3)


if __name__ == "__main__":
    unittest.main()
