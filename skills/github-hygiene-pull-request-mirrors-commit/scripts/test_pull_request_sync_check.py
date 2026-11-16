"""Tests for pull-request-sync-check.sh, the PostToolUse hook.

Each test runs the script as Claude Code would, a JSON payload on stdin,
in a throwaway repository. PATH holds only wrappers for the tools the
script needs and, when a test gives one, a `gh` stub that logs its
arguments and prints a fixture in place of `gh pr list --jq` output:
nothing reaches the network.
"""

import json
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "pull-request-sync-check.sh"

TOOLS = [
    "awk", "bash", "cat", "date", "diff", "dirname", "find", "git", "grep",
    "head", "jq", "mkdir", "rm", "sed", "sh", "tr", "uname",
]

URL = "https://github.com/octo/widgets/pull/7"
SUBJECT = "Add the widget"
BODY = "The widget does a thing."
PREFERENCES = Path(".agents", "skills", "git-workflow-push-mode.preferences.md")


def pull_request(title=SUBJECT, body=BODY, number=7, url=URL):
    return {"number": number, "title": title, "body": body, "url": url}


class HookTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.data = self.tmp / "plugin-data"
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        for tool in TOOLS:
            path = shutil.which(tool)
            if path:
                self._write_exec(self.bin / tool, f'#!{shutil.which("sh")}\nexec "{path}" "$@"\n')
        self.gh_log = self.tmp / "gh.log"
        self.gh_fixture = self.tmp / "gh.json"
        self.repo = self.tmp / "repo"
        self._make_repo()

    # -- set-up helpers --------------------------------------------------

    def _write_exec(self, path, text):
        path.write_text(text)
        path.chmod(0o755)

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.repo, env=self.env(), check=True,
            capture_output=True, text=True,
        ).stdout.strip()

    def _make_repo(self):
        # origin/HEAD names the default branch; the hook never fetches,
        # so the refs alone stand in for a remote.
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.com")
        self.git("commit", "-q", "--allow-empty", "-m", "Start")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
        self.git("switch", "-q", "-c", "feature")
        self.git("commit", "-q", "--allow-empty", "-m", f"{SUBJECT}\n\n{BODY}")

    def gh(self, pr=None, fail=False):
        """Put a `gh` stub on PATH; `pr` is what `gh pr list` prints."""
        exit_line = "exit 1" if fail else 'cat "$GH_FIXTURE" 2>/dev/null; exit 0'
        self._write_exec(self.bin / "gh", textwrap.dedent(f"""\
            #!{shutil.which("sh")}
            printf '%s\\n' "$*" >>"$GH_LOG"
            case "$1 $2" in
            "pr list") {exit_line} ;;
            esac
            exit 1
            """))
        if pr is not None:
            self.gh_fixture.write_text(json.dumps(pr))

    def env(self, **extra):
        env = {
            "PATH": str(self.bin),
            "HOME": str(self.home),
            "CLAUDE_CONFIG_DIR": str(self.home / ".claude"),
            "CLAUDE_PLUGIN_DATA": str(self.data),
            "CLAUDE_PROJECT_DIR": str(self.repo),
            "GH_LOG": str(self.gh_log),
            "GH_FIXTURE": str(self.gh_fixture),
            "GIT_CONFIG_NOSYSTEM": "1",
            "TMPDIR": str(self.tmp),
        }
        env.update(extra)
        return env

    def run_hook(self, command, session="session-1", cwd=None, response=None, **env):
        payload = {
            "session_id": session,
            "hook_event_name": "PostToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": command},
            "tool_response": response if response is not None else {"stdout": "", "stderr": ""},
            "cwd": str(cwd or self.repo),
        }
        result = subprocess.run(
            ["bash", str(SCRIPT)], input=json.dumps(payload), env=self.env(**env),
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout) if result.stdout.strip() else None

    def gh_calls(self):
        return self.gh_log.read_text().splitlines() if self.gh_log.exists() else []

    def reminder(self, output):
        return (output or {}).get("hookSpecificOutput", {}).get("additionalContext")

    # -- the reminder ----------------------------------------------------

    def test_push_with_open_pull_request_reminds_once_per_session(self):
        self.gh(pull_request())
        first = self.run_hook("git push origin feature")
        text = self.reminder(first)
        self.assertIsNotNone(text)
        self.assertEqual(first["hookSpecificOutput"]["hookEventName"], "PostToolUse")
        self.assertIn("#7 (octo/widgets)", text)
        self.assertIn(URL, text)
        self.assertIn("pull-request-monitor.sh --pr 7 --repo octo/widgets", text)
        self.assertIn("unless the user said otherwise", text.lower())
        self.assertNotIn("systemMessage", first)
        self.assertIsNone(self.run_hook("git push --force-with-lease"))

    def test_other_session_and_other_pull_request_are_reminded(self):
        self.gh(pull_request())
        self.assertIsNotNone(self.reminder(self.run_hook("git push")))
        self.assertIsNotNone(self.reminder(self.run_hook("git push", session="session-2")))
        self.gh(pull_request(number=8, url="https://github.com/octo/widgets/pull/8"))
        self.assertIsNotNone(self.reminder(self.run_hook("git push")))

    def test_amend_alone_gives_no_reminder(self):
        self.gh(pull_request())
        self.assertIsNone(self.run_hook("git commit --amend --no-edit"))
        self.assertEqual(len(self.gh_calls()), 1)

    def test_failed_push_gives_no_reminder(self):
        self.gh(pull_request())
        for response in (
            {"stdout": "", "stderr": " ! [rejected]        feature -> feature (non-fast-forward)"},
            {"stdout": "", "stderr": "", "interrupted": True},
            {"stdout": "", "stderr": "", "exit_code": 1},
        ):
            with self.subTest(response=response):
                self.assertIsNone(self.run_hook("git push", response=response))
        self.assertIsNotNone(self.reminder(self.run_hook("git push")))

    # -- silent cases ----------------------------------------------------

    def test_other_commands_start_no_gh(self):
        self.gh(pull_request())
        for command in ("git status", "ls -la", "git log --oneline", "echo pushed"):
            with self.subTest(command=command):
                self.assertIsNone(self.run_hook(command))
        self.assertEqual(self.gh_calls(), [])

    def test_no_repository(self):
        self.gh(pull_request())
        outside = self.tmp / "outside"
        outside.mkdir()
        self.assertIsNone(self.run_hook("git push", cwd=outside))
        self.assertEqual(self.gh_calls(), [])

    def test_detached_head(self):
        self.gh(pull_request())
        self.git("switch", "-q", "--detach", "HEAD")
        self.assertIsNone(self.run_hook("git push origin HEAD:feature"))
        self.assertEqual(self.gh_calls(), [])

    def test_no_gh(self):
        self.assertIsNone(self.run_hook("git push"))

    def test_gh_without_token(self):
        self.gh(fail=True)
        self.assertIsNone(self.run_hook("git push"))
        self.assertEqual(len(self.gh_calls()), 1)

    def test_no_open_pull_request(self):
        self.gh()
        self.assertIsNone(self.run_hook("git push"))
        self.assertEqual(len(self.gh_calls()), 1)

    # -- the default branch and the push mode ----------------------------

    def _on_main(self):
        self.git("switch", "-q", "main")
        self.git("commit", "-q", "--allow-empty", "-m", f"{SUBJECT}\n\n{BODY}")

    def _write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def test_direct_mode_push_to_default_branch_is_silent(self):
        memory = (self.home / ".claude" / "projects"
                  / re.sub(r"[^A-Za-z0-9]", "-", str(self.repo))
                  / "memory" / "push-workflow-mode.md")
        cases = {
            self.repo / PREFERENCES: "- Mode: 1\n",
            memory: "---\nname: push-workflow-mode\n---\n\n**Mode:** 1 (direct to main)\n",
        }
        self._on_main()
        self.gh(pull_request())
        for path, text in cases.items():
            with self.subTest(path=path.name):
                self._write(path, text)
                self.assertIsNone(self.run_hook("git push origin main"))
                self.assertEqual(self.gh_calls(), [])
                path.unlink()

    def test_pull_request_mode_push_to_default_branch_checks(self):
        self._write(self.repo / PREFERENCES, "- Mode: 2\n")
        self._on_main()
        self.gh(pull_request())
        self.assertIsNotNone(self.reminder(self.run_hook("git push")))

    def test_direct_mode_branch_push_still_reminds(self):
        self._write(self.repo / PREFERENCES, "- Mode: 1\n")
        self.gh(pull_request())
        self.assertIsNotNone(self.reminder(self.run_hook("git push")))

    # -- the sync check, beside the reminder -----------------------------

    def test_drifted_title_on_push_gives_both(self):
        self.gh(pull_request(title="Old title"))
        output = self.run_hook("git push")
        self.assertIn("out of sync", output["systemMessage"])
        self.assertIn("Old title", output["systemMessage"])
        self.assertIn("create-or-update-pull-request.sh", output["systemMessage"])
        self.assertIsNotNone(self.reminder(output))

    def test_drift_after_amend_gives_sync_message_only(self):
        self.gh(pull_request(body="Something else entirely."))
        output = self.run_hook("git commit --amend --no-edit")
        self.assertIn("out of sync", output["systemMessage"])
        self.assertIsNone(self.reminder(output))

    def test_body_with_footer_is_in_sync(self):
        self.gh(pull_request(body=f"{BODY}\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)"))
        self.assertIsNone(self.run_hook("git commit --amend --no-edit"))


if __name__ == "__main__":
    unittest.main()
