"""Run candidate self-tests and verify that the live taskbar/Dock remain intact."""

import os
import plistlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BACKUP = Path.home() / "Library/Application Support/WindowBar/dock-backup.plist"


def backup():
    return BACKUP.read_bytes() if BACKUP.exists() else None


def preferences():
    result = subprocess.run(
        ["defaults", "export", "com.apple.dock", "-"], capture_output=True
    )
    if result.returncode != 0:
        return None
    values = plistlib.loads(result.stdout)
    return {key: values.get(key) for key in ("autohide", "autohide-delay")}


binary = Path(sys.argv[1]) if len(sys.argv) == 2 else ROOT / "build/candidate/WindowBar.app/Contents/MacOS/WindowBar"
original_backup = backup()
original_preferences = preferences()
pid = plistlib.loads(original_backup)["pid"] if original_backup else None
try:
    subprocess.run([str(binary), "--self-test"], check=True, timeout=30)
finally:
    assert backup() == original_backup, "Candidate changed the live taskbar's Dock snapshot."
    assert preferences() == original_preferences, "Candidate changed Dock preferences."
    if pid:
        os.kill(pid, 0)
print("PASS: candidate tests preserved the live taskbar PID, Dock backup, and Dock preferences")
