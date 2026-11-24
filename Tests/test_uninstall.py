"""Run with python3 -m unittest discover -s Tests -p 'test_*.py'."""
import os
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/uninstall.sh"


class UninstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mac-sysmonitor-uninstall-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "folder with spaces" / "mac-sysmonitor.app"
        contents = self.app / "Contents"
        contents.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "dev.local.mac-sysmonitor",
        }))
        self.sentinel = self.root / "keep.txt"
        self.sentinel.write_text("keep")
        self.trash = self.root / "Trash"
        self.trash.mkdir()
        self.log = self.root / "operations.log"
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        self.env = {
            **os.environ,
            "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
            "TEST_TRASH": str(self.trash),
            "TEST_LOG": str(self.log),
            "TEST_TRASH_FAIL": "0",
        }
        commands = {
            "pgrep": "exit 1",
            "swift": '''
[ "${1##*/}" = move-to-trash.swift ] || exit 2
echo trash >> "$TEST_LOG"
[ "$TEST_TRASH_FAIL" = 0 ] || exit 1
/bin/mv "$2" "$TEST_TRASH/"
''',
            "defaults": 'echo "$1 $2" >> "$TEST_LOG"',
        }
        for name, body in commands.items():
            command = bin_dir / name
            command.write_text("#!/bin/bash\n" + body + "\n")
            command.chmod(0o755)

    def run_script(self, *options, app=None):
        return subprocess.run(
            ["bash", str(SCRIPT), "--app", str(app or self.app), *options],
            capture_output=True, text=True, env=self.env,
        )

    def test_dry_run_preserves_bundle_and_describes_purge(self):
        result = self.run_script("--dry-run", "--purge")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.app.exists())
        self.assertIn("Would move to Trash:", result.stdout)
        self.assertIn("Would delete preferences:", result.stdout)
        self.assertFalse(self.log.exists())

    def test_removal_is_scoped_and_repeatable(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.app.exists())
        moved = self.trash / self.app.name
        self.assertTrue((moved / "Contents/Info.plist").is_file())
        self.assertTrue(self.sentinel.exists())
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already absent", result.stdout)
        self.assertEqual(self.log.read_text().splitlines(), ["trash"])

    def test_purge_runs_only_after_successful_move(self):
        result = self.run_script("--purge")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), [
            "trash", "read dev.local.mac-sysmonitor", "delete dev.local.mac-sysmonitor",
        ])

    def test_failed_move_preserves_bundle_and_preferences(self):
        self.env["TEST_TRASH_FAIL"] = "1"
        result = self.run_script("--purge")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Saved settings were kept", result.stderr)
        self.assertTrue(self.app.exists())
        self.assertEqual(self.log.read_text().splitlines(), ["trash"])

    def test_absent_bundle_does_not_purge(self):
        result = self.run_script("--purge", app=self.root / "missing/mac-sysmonitor.app")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already absent", result.stdout)
        self.assertFalse(self.log.exists())

    def test_rejects_other_bundle_identifier(self):
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "example.other.app",
        }))
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertTrue(self.app.exists())

    def test_rejects_symlink(self):
        link = self.root / "mac-sysmonitor.app"
        link.symlink_to(self.app, target_is_directory=True)
        self.assertNotEqual(self.run_script(app=link).returncode, 0)
        self.assertTrue(self.app.exists())

    def test_rejects_wrong_name_and_unknown_option(self):
        self.assertNotEqual(self.run_script(app=self.root).returncode, 0)
        self.assertNotEqual(self.run_script("--unknown").returncode, 0)
        self.assertTrue(self.app.exists())
