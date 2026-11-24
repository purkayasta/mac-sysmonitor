"""Run with python3 -m unittest discover -s Tests -p 'test_*.py'."""
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

    def run_script(self, *options, app=None):
        return subprocess.run(
            ["bash", str(SCRIPT), "--app", str(app or self.app), *options],
            capture_output=True, text=True,
        )

    def test_dry_run_preserves_bundle_and_describes_purge(self):
        result = self.run_script("--dry-run", "--purge")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.app.exists())
        self.assertIn("Would remove:", result.stdout)
        self.assertIn("Would delete preferences:", result.stdout)

    def test_removal_is_scoped_and_repeatable(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.app.exists())
        self.assertTrue(self.sentinel.exists())
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already absent", result.stdout)

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
