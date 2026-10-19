#!/usr/bin/env python3
"""Report and apply the deterministic branch cleanups of
`git-workflow-tidy-branches`.

    tidy-branches.py report [--no-fetch]   print the plan; moves no branch
    tidy-branches.py apply                 run the plan lines read from stdin
    tidy-branches.py prefs show            the preferences in effect, and where from
    tidy-branches.py prefs set [--scope user|project] KEY VALUE...

The plan is tab-separated, one item per line:

    <mode>  delete-local   <branch>  <sha>
    <mode>  delete-remote  <remote>  <branch>  <sha>
    <mode>  rebase         <branch>  <old-sha>  <onto-sha>
    <mode>  push           <remote>  <branch>  <expected-remote-sha>
    auto    prune-worktrees
    note    <ref>  <reason>

<mode> is `ask` or `auto`, from the preferences. `report` fetches with
--prune, then checks each rebase with `git replay --ref-action=print`, which
writes objects but moves no ref. `apply` checks every sha it is given before
it acts, so a ref that moved after the report is skipped, never overwritten.

Python 3.9+ standard library, git 2.44+ (for `git replay`); `gh` is optional
and only used to find branches with open pull requests.
"""

import argparse
import fnmatch
import json
import os
import pathlib
import re
import subprocess
import sys

NAME = "git-workflow-tidy-branches"

# Preference keys, in the order a preferences file is written.
DEFAULTS = {
    "base": "",
    "push remote": "origin",
    "keep": ["main", "master", "release/*"],
    "delete merged": "ask",
    "rebase": "ask",
    "rebase open pull requests": "ask",
}
LIST_KEYS = {"keep"}
MODE_KEYS = {"delete merged", "rebase", "rebase open pull requests"}
MODES = {"ask": "ask", "yes": "auto"}  # "no" emits no action


# --- git ---------------------------------------------------------------------


def run(*args, input=None):
    return subprocess.run(list(args), capture_output=True, text=True, input=input)


def git(*args):
    r = run("git", *args)
    if r.returncode:
        sys.exit(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout.strip()


def ok(*args):
    return run("git", *args).returncode == 0


def rev(ref):
    return run("git", "rev-parse", "--verify", "-q", f"{ref}^{{commit}}").stdout.strip() or None


def ancestor(a, b):
    return ok("merge-base", "--is-ancestor", a, b)


def merged(tip, base):
    """True when every change on `tip` is already in `base`: by ancestry, or,
    after a squash or rebase merge, because merging it would change nothing."""
    if ancestor(tip, base):
        return True
    r = run("git", "merge-tree", "--write-tree", base, tip)
    return r.returncode == 0 and r.stdout.split("\n", 1)[0].strip() == git("rev-parse", f"{base}^{{tree}}")


def replay(branch, onto):
    """The commit `branch` would point at once rebased onto `onto`, or None
    when a commit conflicts. Moves no ref."""
    rng = f"{onto}..refs/heads/{branch}"
    r = run("git", "replay", "--ref-action=print", "--onto", onto, rng)
    if r.returncode and "ref-action" in r.stderr:  # git before --ref-action printed by default
        r = run("git", "replay", "--onto", onto, rng)
    if r.returncode:
        return None
    for line in r.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "update" and parts[1] == f"refs/heads/{branch}":
            return parts[2]
    return None


def worktrees():
    """Branch name -> path of the worktree it is checked out in."""
    out, path = {}, None
    for line in git("worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree "):]
        elif line.startswith("branch refs/heads/"):
            out[line[len("branch refs/heads/"):]] = path
    return out


def open_pull_requests():
    """Head branch names of open pull requests, or None without `gh`."""
    try:
        r = run("gh", "pr", "list", "--state", "open", "--limit", "1000", "--json", "headRefName")
    except FileNotFoundError:
        return None
    if r.returncode:
        return None
    return {p["headRefName"] for p in json.loads(r.stdout)}


# --- preferences -------------------------------------------------------------


def skill_dir():
    # abspath, not resolve: the installed skill is usually a symlink into a
    # read-only store, and its preferences sit beside the link, not the target.
    env = os.environ.get("CLAUDE_SKILL_DIR")
    return pathlib.Path(env) if env else pathlib.Path(os.path.abspath(__file__)).parent.parent


def project_dir():
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env:
        return pathlib.Path(env)
    r = run("git", "rev-parse", "--show-toplevel")
    return pathlib.Path(r.stdout.strip()) if r.returncode == 0 else None


def prefs_paths():
    paths = {"user": skill_dir().parent / f"{NAME}.preferences.md"}
    proj = project_dir()
    if proj:
        paths["project"] = proj / ".agents" / "skills" / f"{NAME}.preferences.md"
    return paths


def installed_scope():
    proj = project_dir()
    # The skills folder itself, not the skill: an installed skill is often a
    # link into a store outside the project.
    if proj and os.path.realpath(skill_dir().parent).startswith(os.path.realpath(proj) + os.sep):
        return "project"
    return "user"


def parse_prefs(text):
    prefs, key = {}, None
    for line in text.splitlines():
        m = re.match(r"^[-*] ([^:]+):\s*(.*)$", line)
        if m:
            key = m.group(1).strip().lower()
            value = m.group(2).strip().strip("`")
            if key in LIST_KEYS:
                prefs[key] = [v.strip().strip("`") for v in value.split(",") if v.strip()]
            else:
                prefs[key] = value
            continue
        m = re.match(r"^\s+[-*] (.+)$", line)
        if m and key in LIST_KEYS:
            prefs[key].append(m.group(1).strip().strip("`"))
    return prefs


def render_prefs(prefs):
    lines = []
    for key in DEFAULTS:
        if key not in prefs:
            continue
        label = key[0].upper() + key[1:]
        if key in LIST_KEYS:
            lines.append(f"- {label}:")
            lines += [f"  - {v}" for v in prefs[key]]
        else:
            lines.append(f"- {label}: {prefs[key]}")
    return "\n".join(lines) + "\n"


def read_prefs_file(path):
    try:
        return parse_prefs(path.read_text())
    except OSError:
        return {}


def load_prefs():
    """Defaults, then the user's file, then the project's: later wins."""
    prefs, source = dict(DEFAULTS), {k: "default" for k in DEFAULTS}
    for scope, path in prefs_paths().items():
        for k, v in read_prefs_file(path).items():
            if k in DEFAULTS:
                prefs[k], source[k] = v, scope
    for k in MODE_KEYS:
        if prefs[k] not in ("ask", "yes", "no"):
            sys.exit(f"preference {k!r} must be ask, yes or no, not {prefs[k]!r}")
    return prefs, source


def cmd_prefs(args):
    if args.action == "show":
        prefs, source = load_prefs()
        for scope, path in prefs_paths().items():
            print(f"file\t{scope}\t{path}\t{'exists' if path.exists() else 'absent'}")
        print(f"installed\t{installed_scope()}")
        for k in DEFAULTS:
            v = ", ".join(prefs[k]) if k in LIST_KEYS else prefs[k]
            print(f"pref\t{k}\t{v}\t{source[k]}")
        return 0

    key = args.key.lower()
    if key not in DEFAULTS:
        sys.exit(f"unknown preference {args.key!r}; known: {', '.join(DEFAULTS)}")
    value = [v for item in args.value for v in item.split(",") if v] if key in LIST_KEYS else " ".join(args.value)
    if key in MODE_KEYS and value not in ("ask", "yes", "no"):
        sys.exit(f"preference {key!r} must be ask, yes or no")
    scope = args.scope or installed_scope()
    paths = prefs_paths()
    if scope not in paths:
        sys.exit("not in a project: no project preferences file")
    path = paths[scope]
    prefs = read_prefs_file(path)
    prefs[key] = value
    text = render_prefs(prefs)

    if scope == "project":
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print(f"wrote\t{path}")
        return 0

    # The user's file is generated by Home Manager: a direct write would be
    # refused (a store path) or lost on the next switch. Print the change.
    home = pathlib.Path.home()
    try:
        target = path.relative_to(home)
    except ValueError:
        target = path
    print(f"# Home Manager generates {path}. Add this to the Home Manager config, then switch:")
    print(f'home.file."{target}".text = \'\'')
    print("".join(f"  {line}\n" if line else "\n" for line in text.splitlines()), end="")
    print("'';")
    return 0


# --- report ------------------------------------------------------------------


def resolve_base(prefs):
    """The `Base` preference, else the default branch of `upstream` (a fork's
    source) or of the push remote, else a local main or master."""
    if prefs["base"]:
        if not rev(prefs["base"]):
            sys.exit(f"base {prefs['base']!r} not found")
        return prefs["base"]
    for r in dict.fromkeys(("upstream", prefs["push remote"])):
        if not ok("remote", "get-url", r):
            continue
        head = run("git", "symbolic-ref", "-q", "--short", f"refs/remotes/{r}/HEAD").stdout.strip()
        for cand in (head, f"{r}/main", f"{r}/master"):
            if cand and rev(f"refs/remotes/{cand}"):
                return cand
    for b in ("main", "master"):
        if rev(f"refs/heads/{b}"):
            return b
    sys.exit("could not find the base branch; set the `Base` preference")


def cmd_report(args):
    prefs, _ = load_prefs()
    remote = prefs["push remote"]
    base = resolve_base(prefs)
    base_remote, _, base_name = base.partition("/") if rev(f"refs/remotes/{base}") else ("", "", base)
    base_name = base_name or base

    if not args.no_fetch:
        for r in dict.fromkeys(x for x in (remote, base_remote) if x):
            if ok("remote", "get-url", r):
                run("git", "fetch", "--prune", "--quiet", r)

    base_sha = rev(base)
    keep = list(prefs["keep"]) + [base_name]
    kept = lambda b: any(fnmatch.fnmatchcase(b, pat) for pat in keep)
    trees = worktrees()
    prs = open_pull_requests()
    out = []

    def note(ref, reason):
        out.append(f"note\t{ref}\t{reason}")

    if prs is None:
        note("-", "gh unavailable: open pull requests unknown")
    for k in MODE_KEYS:
        if prefs[k] == "no":
            note("-", f"preference {k}: no")

    if run("git", "worktree", "prune", "--dry-run").stdout.strip():
        out.append("auto\tprune-worktrees")

    branches = []
    fmt = "%(refname:short)\t%(objectname)\t%(upstream:track)"
    for line in git("for-each-ref", "--format", fmt, "refs/heads").splitlines():
        name, tip, track = (line.split("\t") + [""])[:3]
        if not kept(name):
            branches.append((name, tip, track))

    unmerged = []
    open_prs = prs or set()
    for name, tip, track in branches:
        if merged(tip, base_sha):
            if name in open_prs:
                note(name, f"merged into {base}, but its pull request is still open")
            elif name in trees:
                note(name, f"merged into {base}, but checked out in {trees[name]}")
            elif prefs["delete merged"] != "no":
                out.append(f"{MODES[prefs['delete merged']]}\tdelete-local\t{name}\t{tip}")
        else:
            unmerged.append((name, tip, track))

    # A branch built on another unmerged branch is a stack: rebasing either
    # onto the base alone would split it, so stacks are left to a stack tool.
    tips = dict((n, t) for n, t, _ in unmerged)
    below = {b: [a for a in tips if a != b and ancestor(tips[a], tips[b])] for b in tips}
    stacked = {}
    for b, parents in below.items():
        # the nearest: a parent no other parent is built on
        near = sorted(p for p in parents if not any(q != p and tips[q] != tips[p] and ancestor(tips[p], tips[q]) for q in parents))
        if near:
            stacked.setdefault(b, []).append(f"on {', '.join(near)}")
    for a in tips:
        n = sum(a in parents for parents in below.values())
        if n:
            stacked.setdefault(a, []).append(f"{n} branch{'es' if n > 1 else ''} on it")

    for name, tip, track in unmerged:
        if "gone" in track:
            note(name, "its upstream branch is gone, but it isn't merged")
        if name in stacked:
            note(name, f"stacked ({', '.join(stacked[name])}); restack with a stack tool")
            continue
        if ancestor(base_sha, tip):
            continue  # already on the base
        remote_tip = rev(f"refs/remotes/{remote}/{name}")
        if remote_tip and remote_tip != tip:
            if ancestor(tip, remote_tip):
                note(name, f"{remote}/{name} has commits it lacks; pull first")
                continue
            if not ancestor(remote_tip, tip):
                note(name, f"differs from {remote}/{name}: each has commits the other lacks")
                continue
        if run("git", "rev-list", "--merges", "-n1", f"{base_sha}..{tip}").stdout.strip():
            note(name, f"behind {base}, but has merge commits; rebase by hand")
            continue
        if name in trees:
            note(name, f"behind {base}; checked out in {trees[name]}, rebase it there")
            continue
        has_pr = prs is not None and name in prs
        mode = prefs["rebase open pull requests" if has_pr else "rebase"]
        if mode == "no":
            continue
        if not replay(name, base_sha):
            note(name, f"behind {base}; rebasing it conflicts")
            continue
        out.append(f"{MODES[mode]}\trebase\t{name}\t{tip}\t{base_sha}")
        if remote_tip == tip:
            out.append(f"{MODES[mode]}\tpush\t{remote}\t{name}\t{remote_tip}")
        elif remote_tip:
            note(name, f"has commits not on {remote}; push it yourself after the rebase")

    for line in git("for-each-ref", "--format", "%(refname)\t%(objectname)", f"refs/remotes/{remote}").splitlines():
        ref, tip = line.split("\t")
        name = ref[len(f"refs/remotes/{remote}/"):]
        if name == "HEAD" or kept(name) or not merged(tip, base_sha):
            continue
        if name in open_prs:
            note(f"{remote}/{name}", f"merged into {base}, but its pull request is still open")
        elif prefs["delete merged"] != "no":
            out.append(f"{MODES[prefs['delete merged']]}\tdelete-remote\t{remote}\t{name}\t{tip}")

    print(f"base\t{base}\t{base_sha}")
    print("\n".join(out))
    return 0


# --- apply -------------------------------------------------------------------


def cmd_apply(_args):
    trees = worktrees()
    failed = 0

    def result(status, item, why=""):
        nonlocal failed
        failed += status == "skipped"
        print("\t".join(x for x in (status, item, why) if x))

    for line in sys.stdin:
        f = line.rstrip("\n").split("\t")
        if len(f) < 2 or f[0] not in ("ask", "auto"):
            continue
        action, item = f[1], " ".join(f[1:])
        if action == "prune-worktrees":
            git("worktree", "prune")
            result("done", item)
        elif action == "delete-local":
            name, sha = f[2], f[3]
            if rev(f"refs/heads/{name}") != sha:
                result("skipped", item, "branch moved since the report")
            elif name in trees:
                result("skipped", item, f"checked out in {trees[name]}")
            elif ok("update-ref", "-d", f"refs/heads/{name}", sha):
                result("done", item)
            else:
                result("skipped", item, "update-ref refused")
        elif action == "delete-remote":
            remote, name, sha = f[2], f[3], f[4]
            r = run("git", "push", "--quiet", f"--force-with-lease=refs/heads/{name}:{sha}",
                    remote, "--delete", f"refs/heads/{name}")
            result("done", item) if r.returncode == 0 else result("skipped", item, r.stderr.strip().splitlines()[-1])
        elif action == "rebase":
            name, old, onto = f[2], f[3], f[4]
            if rev(f"refs/heads/{name}") != old:
                result("skipped", item, "branch moved since the report")
            elif name in trees:
                result("skipped", item, f"checked out in {trees[name]}")
            else:
                new = replay(name, onto)
                if not new:
                    result("skipped", item, "rebase conflicts")
                elif ok("update-ref", "-m", f"tidy-branches: rebase onto {onto}", f"refs/heads/{name}", new, old):
                    result("done", item, new)
                else:
                    result("skipped", item, "update-ref refused")
        elif action == "push":
            remote, name, expected = f[2], f[3], f[4]
            r = run("git", "push", "--quiet", f"--force-with-lease=refs/heads/{name}:{expected}",
                    remote, f"refs/heads/{name}:refs/heads/{name}")
            result("done", item) if r.returncode == 0 else result("skipped", item, r.stderr.strip().splitlines()[-1])
        else:
            result("skipped", item, "unknown action")
    return 1 if failed else 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("report")
    r.add_argument("--no-fetch", action="store_true")
    sub.add_parser("apply")
    pr = sub.add_parser("prefs")
    psub = pr.add_subparsers(dest="action", required=True)
    psub.add_parser("show")
    ps = psub.add_parser("set")
    ps.add_argument("--scope", choices=("user", "project"))
    ps.add_argument("key")
    ps.add_argument("value", nargs="+")
    args = p.parse_args(argv)
    return {"report": cmd_report, "apply": cmd_apply, "prefs": cmd_prefs}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
