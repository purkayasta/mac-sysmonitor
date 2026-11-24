import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/publish-private.sh"
PRIVATE_REMOTE = "https://github.com/test-owner/mac-sysmonitor.git"
OTHER_REMOTE = "https://github.com/test-owner/other.git"


class PublishPrivateTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="mac-sysmonitor-publish-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.repo = self.root / "repo"
        scripts = self.repo / "scripts"
        scripts.mkdir(parents=True)
        self.script = scripts / SCRIPT.name
        shutil.copyfile(SCRIPT, self.script)
        self.log = self.root / "push.log"
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        self.real_git = shutil.which("git")
        self.env = {
            **os.environ,
            "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "TEST_GIT": self.real_git,
            "TEST_PUSH_LOG": str(self.log),
            "TEST_VISIBILITY": "PRIVATE",
        }
        commands = {
            "gh": '''
case "$1 $2" in
    "auth status") exit 0 ;;
    "api user") echo test-owner ;;
    "repo view") echo "$TEST_VISIBILITY" ;;
    *) exit 1 ;;
esac
''',
            "git": '''
for arg in "$@"; do
    if [ "$arg" = push ]; then
        printf '%s\n' "$@" > "$TEST_PUSH_LOG"
        exit 0
    fi
done
exec "$TEST_GIT" "$@"
''',
        }
        for name, body in commands.items():
            command = bin_dir / name
            command.write_text("#!/bin/bash\n" + body)
            command.chmod(0o755)
        self.git("init", "-b", "main")
        self.git("remote", "add", "origin", PRIVATE_REMOTE)

    def git(self, *args):
        result = subprocess.run(
            [self.real_git, *args], cwd=self.repo, env=self.env,
            check=True, capture_output=True, text=True,
        )
        return result.stdout.strip()

    def commit(self):
        self.git("add", "scripts")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.test", "commit", "-m", "Initial commit")
        return self.git("rev-parse", "HEAD")

    def publish(self):
        return subprocess.run(
            ["bash", str(self.script)], cwd=self.repo, env=self.env,
            capture_output=True, text=True,
        )

    def test_requires_a_commit(self):
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("on main first", result.stderr)
        self.assertFalse(self.log.exists())

    def test_pushes_only_committed_main_and_preserves_local_edits(self):
        head = self.commit()
        staged = self.repo / "scripts/staged.txt"
        staged.write_text("staged")
        self.git("add", str(staged))
        (self.repo / "scripts/local.txt").write_text("untracked")
        before = self.git("status", "--porcelain")

        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Publishing committed changes only", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertEqual(self.git("status", "--porcelain"), before)
        self.assertEqual(self.log.read_text().splitlines()[-6:], [
            "push", "--no-follow-tags", "--recurse-submodules=no",
            "-u", "origin", "refs/heads/main:refs/heads/main",
        ])

    def test_rejects_unexpected_push_url(self):
        self.commit()
        self.git("config", "remote.origin.pushurl", OTHER_REMOTE)
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exactly one origin push URL", result.stderr)
        self.assertFalse(self.log.exists())

    def test_rejects_multiple_push_urls(self):
        self.commit()
        self.git("config", "--add", "remote.origin.pushurl", PRIVATE_REMOTE)
        self.git("config", "--add", "remote.origin.pushurl", OTHER_REMOTE)
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exactly one origin push URL", result.stderr)
        self.assertFalse(self.log.exists())

    def test_rejects_rewritten_push_url(self):
        self.commit()
        self.git("config", f"url.{OTHER_REMOTE}.pushInsteadOf", PRIVATE_REMOTE)
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exactly one origin push URL", result.stderr)
        self.assertFalse(self.log.exists())

    def test_rejects_public_repository(self):
        self.commit()
        self.env["TEST_VISIBILITY"] = "PUBLIC"
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Repository is not private", result.stderr)
        self.assertFalse(self.log.exists())
