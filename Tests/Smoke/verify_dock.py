"""Verify Dock replacement, graceful restoration, and recovery after force-quit.

Run with WindowBar closed. This launches the real app, then leaves it closed.
"""

import os
import plistlib
import signal
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "build/WindowBar.app/Contents/MacOS/WindowBar"
BACKUP = Path.home() / "Library/Application Support/WindowBar/dock-backup.plist"


def preferences():
    result = subprocess.run(
        ["defaults", "export", "com.apple.dock", "-"], check=True, capture_output=True
    )
    values = plistlib.loads(result.stdout)
    return {key: values.get(key) for key in ("autohide", "autohide-delay")}


def wait_until(condition, description):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.25)
    raise AssertionError(description)


def replaced():
    return BACKUP.exists() and preferences() == {"autohide": True, "autohide-delay": 3600.0}


assert not BACKUP.exists(), "Close WindowBar before testing; preserve any existing backup."
original = preferences()
process = None
try:
    process = subprocess.Popen([str(BINARY)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_until(replaced, "WindowBar did not replace Dock. Check Accessibility permission.")
    subprocess.run(
        ["osascript", "-e", 'tell application id "local.windowbar.app" to quit'], check=True
    )
    process.wait(timeout=12)
    wait_until(lambda: not BACKUP.exists() and preferences() == original, "Normal quit did not restore original Dock settings.")
    print("PASS: normal quit restores exact original Dock settings", flush=True)

    process = subprocess.Popen([str(BINARY)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_until(replaced, "WindowBar did not replace Dock on second launch.")
    os.kill(process.pid, signal.SIGKILL)
    process.wait(timeout=12)
    wait_until(lambda: not BACKUP.exists() and preferences() == original, "Background guard did not restore Dock after force-quit.")
    print("PASS: force-quit restores exact original Dock settings", flush=True)
finally:
    if process is not None and process.poll() is None:
        process.terminate()
        process.wait(timeout=12)
        wait_until(lambda: not BACKUP.exists() and preferences() == original, "Cleanup did not restore Dock.")
