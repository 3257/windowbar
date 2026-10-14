"""Verify that closing the launching session does not stop the taskbar.

Run with WindowBar closed and Accessibility enabled. Leaves the app closed.
"""

import os
import plistlib
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BACKUP = Path.home() / "Library/Application Support/WindowBar/dock-backup.plist"


def wait_until(condition, description):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.25)
    raise AssertionError(description)


def preferences():
    result = subprocess.run(
        ["defaults", "export", "com.apple.dock", "-"], check=True, capture_output=True
    )
    values = plistlib.loads(result.stdout)
    return {key: values.get(key) for key in ("autohide", "autohide-delay")}


assert not BACKUP.exists(), "Close WindowBar before testing; preserve any existing backup."
original = preferences()
pid = None
# Model a terminal/session that invokes the launcher, then stays alive.
wrapper = (
    "import runpy, signal; "
    "runpy.run_path('scripts/run.py', run_name='__main__'); signal.pause()"
)
parent = subprocess.Popen(
    [sys.executable, "-u", "-c", wrapper], cwd=ROOT, start_new_session=True
)
try:
    wait_until(BACKUP.exists, "App did not replace Dock; check Accessibility permission.")
    snapshot = plistlib.loads(BACKUP.read_bytes())
    pid = snapshot["pid"]
    assert os.getpgid(pid) == pid, "App still belongs to the launching session's process group."
    # Closing the session sends a hangup to every process in that group.
    os.killpg(parent.pid, signal.SIGHUP)
    parent.wait(timeout=12)
    print("Launching session closed; observing the same taskbar PID for 45 seconds...", flush=True)
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        os.kill(pid, 0)
        assert plistlib.loads(BACKUP.read_bytes()) == snapshot, "App quit or restarted."
        assert preferences() == {"autohide": True, "autohide-delay": 3600.0}, "Dock replacement stopped."
        time.sleep(1)
    print("PASS: same taskbar survives launching-session exit with Dock replacement active", flush=True)
finally:
    if parent.poll() is None:
        os.killpg(parent.pid, signal.SIGTERM)
        parent.wait(timeout=12)
    if pid is not None:
        subprocess.run(
            ["osascript", "-e", 'tell application id "local.windowbar.app" to quit'], check=True
        )
        wait_until(
            lambda: not BACKUP.exists() and preferences() == original,
            "Cleanup did not restore original Dock settings.",
        )
