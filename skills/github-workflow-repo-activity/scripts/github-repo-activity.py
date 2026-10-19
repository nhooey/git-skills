#!/usr/bin/env python3
"""List what a GitHub user did on one repository since a given time.

Every fact comes from a REST endpoint that is the source of truth for it, read
through `gh api` (so `gh` owns the token). The Events API is never used: it
keeps only 90 days / 300 events, lags, credits a merge to the PR's author
instead of whoever merged it, and has been seen to drop pushes. Pushes come
from the repository activity endpoint, which records when a ref moved and who
moved it; a commit's own date is when it was made, not when it was pushed.

Standard library only; Python 3.9+.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from typing import Callable, Dict, Iterable, List, Optional

USAGE_EPILOG = """\
subcommands:
  summary    everything below, merged and sorted by time
  comments   issue/PR conversation comments and PR review (diff) comments
  reviews    PR reviews submitted (approve, request changes, comment)
  merges     PRs whose merged_by is the user
  prs        PRs the user opened, closed, reopened or retitled
  issues     issues the user opened, closed, reopened or retitled
  commits    commits the user pushed since the time, at their push time; one
             no PR carries is a direct push (kind `commit`), one on a PR's
             branch is `commit-via-pr`
  branches   branches the user created, deleted or force-pushed

examples:
  %(prog)s summary --repo jlesquembre/clj-nix --user jlesquembre --since 2026-10-18
  %(prog)s merges  --repo jlesquembre/clj-nix --user jlesquembre --since 2d --json
  %(prog)s comments --repo owner/repo --since 2026-10-01T09:00:00+02:00

--since takes an ISO 8601 date or time (a bare date is midnight UTC), or a
relative age like 36h, 2d or 1w. Without --user every user is listed, bots
left out unless --include-bots.
"""

SINCE_RELATIVE = re.compile(r"^(\d+)([hdw])$")
NULL_SHA = "0" * 40
ACTIVITY_PERIODS = (("day", 1), ("week", 7), ("month", 28), ("quarter", 89), ("year", 364))
TIMELINE_KINDS = {
    "closed": "closed",
    "reopened": "reopened",
    "renamed": "retitled",
    "referenced": "referenced",
}


def parse_since(text: str, now: Optional[datetime] = None) -> datetime:
    """Parse --since: ISO 8601 date/time, or a relative age (36h, 2d, 1w)."""
    now = now or datetime.now(timezone.utc)
    rel = SINCE_RELATIVE.match(text.strip())
    if rel:
        n, unit = int(rel.group(1)), rel.group(2)
        hours = {"h": 1, "d": 24, "w": 24 * 7}[unit] * n
        return now - timedelta(hours=hours)
    s = text.strip()
    if s.endswith(("Z", "z")):
        s = s[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        raise argparse.ArgumentTypeError(
            f"--since: not an ISO 8601 time or relative age: {text!r}"
        ) from None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def parse_time(stamp: Optional[str]) -> Optional[datetime]:
    """Parse a GitHub API timestamp (always UTC, `...Z`)."""
    if not stamp:
        return None
    return datetime.fromisoformat(stamp.replace("Z", "+00:00"))


def iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def is_bot(login: Optional[str]) -> bool:
    return bool(login) and (login.endswith("[bot]") or login == "web-flow")


class GhError(RuntimeError):
    pass


def gh_api(path: str, paginate: bool = True) -> object:
    """GET `path` via `gh api`; with paginate, return every page's items."""
    cmd = ["gh", "api", "-H", "Accept: application/vnd.github+json"]
    if paginate:
        cmd += ["--paginate", "--slurp"]
    cmd.append(path)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise GhError(f"gh api {path} failed: {proc.stderr.strip()}")
    data = json.loads(proc.stdout or "null")
    if not paginate:
        return data
    items: List[object] = []
    for page in data or []:
        if isinstance(page, dict) and "items" in page:  # search endpoints
            items.extend(page["items"])
        elif isinstance(page, list):
            items.extend(page)
        else:
            items.append(page)
    return items


class Activity:
    """Collects one user's activity on one repo; `get` is `gh_api` or a fake."""

    def __init__(
        self,
        repo: str,
        user: Optional[str],
        since: datetime,
        include_bots: bool = False,
        get: Callable[..., object] = gh_api,
        jobs: int = 8,
    ):
        self.repo = repo
        self.user = user.lower() if user else None
        self.since = since
        self.include_bots = include_bots
        self.get = get
        self.jobs = jobs
        self._updated: Optional[List[dict]] = None
        self._pulls: Optional[List[dict]] = None
        self._heads: Optional[List[dict]] = None
        self._activity: Optional[List[dict]] = None
        self.notes: List[str] = []
        self._default: Optional[str] = None
        self._titles: Dict[int, str] = {}

    # -- helpers -----------------------------------------------------------

    def wanted(self, login: Optional[str]) -> bool:
        if self.user is not None:
            return (login or "").lower() == self.user
        return self.include_bots or not is_bot(login)

    def recent(self, stamp: Optional[str]) -> bool:
        t = parse_time(stamp)
        return t is not None and t >= self.since

    def event(self, when, kind, number=None, title=None, url=None, actor=None, detail=None):
        return {
            "time": when,
            "kind": kind,
            "number": number,
            "title": title if title is not None else self.title(number),
            "url": url,
            "actor": actor,
            "detail": detail,
        }

    def fetch_many(self, paths: List[str], paginate: bool = True) -> List[object]:
        """GET several paths at once; one `gh` process each, results in order."""
        with ThreadPoolExecutor(max_workers=self.jobs) as pool:
            return list(pool.map(lambda p: self.get(p, paginate=paginate), paths))

    def default_branch(self) -> str:
        if self._default is None:
            self._default = self.get(f"repos/{self.repo}", paginate=False)["default_branch"]
        return self._default

    def updated_items(self) -> List[dict]:
        """Issues and PRs updated since; any comment, review, close or merge bumps this."""
        if self._updated is None:
            self._updated = self.get(
                f"repos/{self.repo}/issues?state=all&since={iso(self.since)}&per_page=100"
            )
            for it in self._updated:
                self._titles[it["number"]] = it["title"]
        return self._updated

    def updated_pulls(self) -> List[dict]:
        return [it for it in self.updated_items() if "pull_request" in it]

    def title(self, number: Optional[int]) -> Optional[str]:
        if number is None:
            return None
        if number not in self._titles:
            self.updated_items()
        if number not in self._titles:
            item = self.get(f"repos/{self.repo}/issues/{number}", paginate=False)
            self._titles[number] = item.get("title", "")
        return self._titles[number]

    # -- subcommands -------------------------------------------------------

    def comments(self) -> List[dict]:
        out = []
        since = iso(self.since)
        for c in self.get(f"repos/{self.repo}/issues/comments?since={since}&per_page=100"):
            login = c["user"]["login"]
            if not self.wanted(login):
                continue
            number = int(c["issue_url"].rsplit("/", 1)[1])
            if self.recent(c["created_at"]):
                out.append(self.event(c["created_at"], "comment", number, url=c["html_url"], actor=login))
            elif self.recent(c["updated_at"]):
                out.append(self.event(c["updated_at"], "comment-edited", number, url=c["html_url"], actor=login))
        for c in self.get(f"repos/{self.repo}/pulls/comments?since={since}&per_page=100"):
            login = c["user"]["login"]
            if not self.wanted(login):
                continue
            number = int(c["pull_request_url"].rsplit("/", 1)[1])
            kind = "review-comment" if self.recent(c["created_at"]) else "review-comment-edited"
            when = c["created_at"] if kind == "review-comment" else c["updated_at"]
            if self.recent(when):
                out.append(self.event(when, kind, number, url=c["html_url"], actor=login,
                                      detail=c.get("path")))
        return out

    def reviews(self) -> List[dict]:
        out = []
        pulls = self.updated_pulls()
        pages = self.fetch_many([f"repos/{self.repo}/pulls/{pr['number']}/reviews?per_page=100" for pr in pulls])
        for pr, reviews in zip(pulls, pages):
            n = pr["number"]
            for r in reviews:
                login = (r.get("user") or {}).get("login")
                if not self.wanted(login) or not self.recent(r.get("submitted_at")):
                    continue
                state = (r.get("state") or "").lower()
                out.append(self.event(r["submitted_at"], f"review-{state}", n,
                                      url=r.get("html_url"), actor=login))
        return out

    def merged_pulls(self) -> List[dict]:
        """Full PR objects merged since; only the single-PR endpoint has merged_by."""
        if self._pulls is None:
            merged = [pr["number"] for pr in self.updated_pulls()
                      if self.recent(pr["pull_request"].get("merged_at"))]
            self._pulls = self.fetch_many([f"repos/{self.repo}/pulls/{n}" for n in merged], paginate=False)
        return self._pulls

    def merges(self) -> List[dict]:
        out = []
        for pr in self.merged_pulls():
            login = (pr.get("merged_by") or {}).get("login")
            if self.wanted(login):
                author = pr["user"]["login"]
                out.append(self.event(pr["merged_at"], "merged", pr["number"], pr["title"],
                                      pr["html_url"], login,
                                      None if author.lower() == (login or "").lower() else f"by {author}"))
        return out

    def items(self, pulls: bool) -> List[dict]:
        out = []
        chosen = [it for it in self.updated_items() if ("pull_request" in it) == pulls]
        timelines = self.fetch_many([f"repos/{self.repo}/issues/{it['number']}/timeline?per_page=100" for it in chosen])
        for it, timeline in zip(chosen, timelines):
            n, login = it["number"], it["user"]["login"]
            if self.wanted(login) and self.recent(it["created_at"]):
                out.append(self.event(it["created_at"], "opened", n, it["title"], it["html_url"], login,
                                      "draft" if it.get("draft") else None))
            for e in timeline:
                kind = TIMELINE_KINDS.get(e.get("event"))
                actor = (e.get("actor") or {}).get("login")
                if not kind or not self.wanted(actor) or not self.recent(e.get("created_at")):
                    continue
                if kind == "closed" and pulls and it["pull_request"].get("merged_at"):
                    continue  # the merge itself is reported by `merges`
                detail = None
                if kind == "retitled":
                    detail = f"from {e['rename']['from']!r}"
                elif kind == "referenced" and e.get("commit_id"):
                    detail = f"commit {e['commit_id'][:7]}"
                out.append(self.event(e["created_at"], kind, n, it["title"], it["html_url"], actor, detail))
        return out

    def prs(self) -> List[dict]:
        return self.items(pulls=True)

    def issues(self) -> List[dict]:
        return self.items(pulls=False)

    def repo_activity(self) -> Optional[List[dict]]:
        """Ref moves since: pushes, force-pushes, branch creations/deletions,
        each with the time GitHub received it and the login that did it.
        None when the endpoint is unavailable (then commit dates stand in)."""
        if self._activity is None:
            age = (datetime.now(timezone.utc) - self.since).days + 1
            period = next((name for name, days in ACTIVITY_PERIODS if age <= days), None)
            query = "per_page=100&direction=desc"
            if period:
                query += f"&time_period={period}"
            if self.user:
                query += f"&actor={self.user}"
            try:
                rows = self.get(f"repos/{self.repo}/activity?{query}")
            except GhError as err:
                self.notes.append(f"repository activity unavailable, using commit dates: {err}")
                return None
            self._activity = [a for a in rows
                              if self.recent(a["timestamp"]) and self.wanted((a.get("actor") or {}).get("login"))]
            self._activity.sort(key=lambda a: a["timestamp"])
        return self._activity

    def branch_heads(self) -> List[dict]:
        """(branch, newest commit since) for every branch whose newest commit is
        dated since; the fallback when repository activity is unavailable."""
        if self._heads is None:
            names = [b["name"] for b in self.get(f"repos/{self.repo}/branches?per_page=100")]
            newest = self.fetch_many(
                [f"repos/{self.repo}/commits?sha={n}&since={iso(self.since)}&per_page=1" for n in names],
                paginate=False,
            )
            self._heads = [{"branch": n, "commit": c[0]} for n, c in zip(names, newest) if c]
        return self._heads

    def pushed_commits(self) -> List[tuple]:
        """(push time, pusher, branch, commit) for each commit the pushes since carried."""
        moves = [a for a in self.repo_activity()
                 if a["activity_type"] in ("push", "force_push", "branch_creation")]
        paths = []
        for a in moves:
            base = self.default_branch() if a["before"] == NULL_SHA else a["before"]
            paths.append(f"repos/{self.repo}/compare/{base}...{a['after']}")
        found, seen = [], set()
        for a, cmp in zip(moves, self.fetch_many(paths, paginate=False)):
            branch = a["ref"].replace("refs/heads/", "", 1)
            for c in cmp.get("commits", []):
                if c["sha"] not in seen:
                    seen.add(c["sha"])
                    found.append((a["timestamp"], a["actor"]["login"], branch, c))
        return found

    def dated_commits(self) -> List[tuple]:
        """(commit time, author, branch, commit) by commit date: misses a commit
        made before --since and pushed after it."""
        self.notes.append("commits are found by commit date; widen --since to catch late pushes")
        heads = self.branch_heads()
        query = f"since={iso(self.since)}&per_page=100"
        if self.user:
            query += f"&author={self.user}"
        pages = self.fetch_many([f"repos/{self.repo}/commits?sha={h['branch']}&{query}" for h in heads])
        found, seen = [], set()
        for head, page in zip(heads, pages):
            for c in page:
                login = (c.get("author") or {}).get("login")
                if c["sha"] not in seen and self.wanted(login):
                    seen.add(c["sha"])
                    found.append((c["commit"]["committer"]["date"], login, head["branch"], c))
        return found

    def commits(self) -> List[dict]:
        found = self.pushed_commits() if self.repo_activity() is not None else self.dated_commits()
        merge_shas = {pr.get("merge_commit_sha") for pr in self.merged_pulls()}
        found = [f for f in found if f[3]["sha"] not in merge_shas]  # reported by `merges`
        prs = self.fetch_many([f"repos/{self.repo}/commits/{c['sha']}/pulls" for _, _, _, c in found])
        out = []
        for (when, login, branch, c), carriers in zip(found, prs):
            carrier = next((p for p in carriers if p.get("merged_at")), carriers[0] if carriers else None)
            subject = c["commit"]["message"].splitlines()[0]
            out.append(self.event(
                when,
                "commit-via-pr" if carrier else "commit",
                carrier["number"] if carrier else None,
                subject, c["html_url"], login, f"{branch} {c['sha'][:7]}",
            ))
        return out

    def branches(self) -> List[dict]:
        moves = self.repo_activity()
        out = []
        if moves is None:
            for head in self.branch_heads():
                if head["branch"] == self.default_branch():
                    continue  # its moves are the commits and merges
                c = head["commit"]
                login = (c.get("author") or {}).get("login")
                if self.wanted(login):
                    out.append(self.event(c["commit"]["committer"]["date"], "branch-updated", None,
                                          c["commit"]["message"].splitlines()[0],
                                          f"https://github.com/{self.repo}/tree/{head['branch']}", login,
                                          f"{head['branch']} -> {c['sha'][:7]}"))
            return out
        kinds = {"branch_creation": "branch-created", "branch_deletion": "branch-deleted",
                 "force_push": "force-pushed"}
        for a in moves:
            kind = kinds.get(a["activity_type"])
            if not kind or not a["ref"].startswith("refs/heads/"):
                continue
            branch = a["ref"][len("refs/heads/"):]
            sha = a["before"] if kind == "branch-deleted" else a["after"]
            out.append(self.event(a["timestamp"], kind, None, branch,
                                  f"https://github.com/{self.repo}/tree/{branch}" if kind != "branch-deleted" else None,
                                  a["actor"]["login"], sha[:7]))
        return out

    def summary(self) -> List[dict]:
        events: List[dict] = []
        for part in (self.comments, self.reviews, self.merges, self.prs, self.issues,
                     self.commits, self.branches):
            events.extend(part())
        return events


def human(events: Iterable[dict], show_actor: bool) -> str:
    lines = []
    for e in events:
        when = parse_time(e["time"]).strftime("%Y-%m-%d %H:%MZ")
        what = f'#{e["number"]} ' if e["number"] is not None else ""
        title = e["title"] or ""
        if len(title) > 60:
            title = title[:59] + "…"
        what += f'"{title}"'
        if e["detail"]:
            what += f' ({e["detail"]})'
        actor = f'{e["actor"]:<16} ' if show_actor else ""
        lines.append(f'{when}  {actor}{e["kind"]:<22} {what}  {e["url"] or ""}')
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--repo", required=True, metavar="OWNER/REPO", help="repository to inspect")
    common.add_argument("--user", metavar="LOGIN", help="GitHub login whose activity to list (default: everyone)")
    common.add_argument("--since", required=True, type=parse_since, metavar="TIME",
                        help="ISO 8601 date/time, or a relative age: 36h, 2d, 1w")
    common.add_argument("--json", action="store_true", help="print a JSON array instead of one line per event")
    common.add_argument("--jobs", type=int, default=8, metavar="N",
                        help="concurrent gh api calls for per-item endpoints (default: 8)")
    common.add_argument("--include-bots", action="store_true",
                        help="keep [bot] accounts and web-flow when --user is not given")

    parser = argparse.ArgumentParser(
        prog="github-repo-activity.py",
        description="List a GitHub user's activity on one repository since a given time, "
                    "without the Events API.",
        epilog=USAGE_EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", metavar="COMMAND", required=True)
    for name in ("summary", "comments", "reviews", "merges", "prs", "issues", "commits", "branches"):
        sub.add_parser(name, parents=[common], help=f"list {name}")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    activity = Activity(args.repo, args.user, args.since, args.include_bots, jobs=args.jobs)
    try:
        events = getattr(activity, args.command)()
    except GhError as err:
        print(err, file=sys.stderr)
        return 1
    for note in dict.fromkeys(activity.notes):
        print(f"note: {note}", file=sys.stderr)
    events.sort(key=lambda e: (e["time"], e["kind"], e["number"] or 0))
    if args.json:
        json.dump(events, sys.stdout, indent=2)
        sys.stdout.write("\n")
    elif events:
        print(human(events, show_actor=args.user is None))
    return 0


if __name__ == "__main__":
    sys.exit(main())
