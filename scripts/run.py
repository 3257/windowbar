#!/usr/bin/env python3
"""Launch the built app independently of the terminal or coding session."""

import subprocess
import sys
from pathlib import Path


def main():
    binary = Path(__file__).resolve().parents[1] / "build/WindowBar.app/Contents/MacOS/WindowBar"
    if not binary.is_file():
        raise SystemExit("Build WindowBar first with: zsh build.sh")

    log_path = Path.home() / "Library/Logs/WindowBar/app.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("ab") as log:
        process = subprocess.Popen(
            [str(binary)],
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=log,
            start_new_session=True,
            close_fds=True,
        )
    try:
        status = process.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        print(f"WindowBar launched independently (PID {process.pid}). Log: {log_path}")
        return
    print(f"WindowBar exited with status {status}. Check {log_path}", file=sys.stderr)
    raise SystemExit(status or 1)


if __name__ == "__main__":
    main()
