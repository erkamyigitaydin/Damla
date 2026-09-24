#!/usr/bin/env python3
"""Installer integration checks use a temporary home, never real agent settings."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("install-agent-hooks.py")
spec = importlib.util.spec_from_file_location("installer", SCRIPT)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def test_preserves_existing_settings_and_hooks(self):
        old = {"permissions": {"deny": ["Bash(rm *)"]}, "disableAllHooks": True,
               "hooks": {"Stop": [{"matcher": "*", "hooks": [{"type": "command", "command": "existing"}]}]}}
        result = installer.merge(old, "claude", Path("/tmp/Project With Spaces/Damla"))
        self.assertEqual(result["permissions"], old["permissions"])
        self.assertTrue(result["disableAllHooks"])
        self.assertEqual(result["hooks"]["Stop"][0], old["hooks"]["Stop"][0])
        self.assertEqual(len(old["hooks"]["Stop"]), 1)
        self.assertEqual(result, installer.merge(result, "claude", Path("/tmp/Project With Spaces/Damla")))
        self.assertTrue(result["hooks"]["Stop"][-1]["hooks"][0]["command"].startswith("'/tmp/Project With Spaces/Damla'"))

    def test_never_installs_approval_decisions_or_async_races(self):
        result = installer.merge({}, "codex", Path("/tmp/Damla"))
        self.assertIn("Interrupt", result["hooks"])
        self.assertNotIn("Notification", result["hooks"])
        encoded = json.dumps(result)
        for forbidden in ["behavior", "allow", "trust", "async", "SubagentStop", "--agent-approval"]:
            self.assertNotIn(forbidden, encoded)
        # Codex never gets the approval hook, even when asked; Claude only gets it when asked.
        self.assertNotIn("--agent-approval", json.dumps(installer.merge({}, "codex", Path("/tmp/Damla"), True)))
        self.assertNotIn("--agent-approval", json.dumps(installer.merge({}, "claude", Path("/tmp/Damla"))))

    def test_approval_hook_is_opt_in_and_removable(self):
        with_approvals = installer.merge({}, "claude", Path("/tmp/Damla"), True)
        groups = with_approvals["hooks"]["PermissionRequest"]
        approval = [h for g in groups for h in g["hooks"] if "--agent-approval" in h["command"]]
        self.assertEqual(len(approval), 1)
        self.assertEqual(approval[0]["timeout"], installer.APPROVAL_TIMEOUT)
        self.assertNotIn("async", approval[0])
        # The static hook entry never carries a decision; decisions only come from a click at run time.
        self.assertNotIn("behavior", json.dumps(with_approvals))
        self.assertEqual(with_approvals, installer.merge(with_approvals, "claude", Path("/tmp/Damla"), True))
        # Re-running without --approvals takes it out again and leaves the status hooks.
        without = installer.merge(with_approvals, "claude", Path("/tmp/Damla"))
        self.assertNotIn("--agent-approval", json.dumps(without))
        self.assertIn("--agent-event", json.dumps(without["hooks"]["PermissionRequest"]))

    def test_apply_backups_and_idempotence(self):
        with tempfile.TemporaryDirectory(prefix="Damla-installer-test-") as tmp:
            root = Path(tmp)
            binary = root / "Damla app"
            binary.write_bytes(b"fixture")
            settings = root / ".claude/settings.json"
            settings.parent.mkdir()
            original = b'{"model":"unchanged", "permissions":{"deny":["private"]}}\n'
            settings.write_bytes(original)
            command = [sys.executable, str(SCRIPT), "--home", tmp, "--binary", str(binary)]
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(settings.read_bytes(), original)
            subprocess.run(command + ["--apply"], check=True, capture_output=True)
            after = settings.read_bytes()
            backups = list(settings.parent.glob("*.damla-backup-*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), original)
            subprocess.run(command + ["--apply"], check=True, capture_output=True)
            self.assertEqual(settings.read_bytes(), after)
            self.assertEqual(len(list(settings.parent.glob("*.damla-backup-*"))), 1)
            self.assertEqual(settings.stat().st_mode & 0o777, 0o600)
            self.assertFalse((root / ".codex/config.toml").exists())

    def test_invalid_second_config_prevents_any_write(self):
        with tempfile.TemporaryDirectory(prefix="Damla-installer-test-") as tmp:
            root = Path(tmp); binary = root / "Damla"; binary.touch()
            (root / ".codex").mkdir(); (root / ".codex/hooks.json").write_text("invalid")
            result = subprocess.run([sys.executable, str(SCRIPT), "--home", tmp, "--binary", str(binary), "--apply"], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / ".claude/settings.json").exists())


if __name__ == "__main__":
    unittest.main()
