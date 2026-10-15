#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
task_app="${WINDOWBAR_APP_PATH:-$PWD/build/WindowBar.app}"
if [[ -f "$task_app/Contents/MacOS/WindowBar" ]]; then
  python3 - "$task_app/Contents/MacOS/WindowBar" <<'PYGUARD'
import os, subprocess, sys
try:
    processes = subprocess.run(["/bin/ps", "-axo", "comm="], capture_output=True, text=True, timeout=3, check=True).stdout
except (subprocess.SubprocessError, OSError):
    raise SystemExit("Could not verify running copies; choose a new candidate path.")
target = os.path.realpath(sys.argv[1])
if any(os.path.realpath(command.strip()) == target for command in processes.splitlines() if command.strip().endswith("/WindowBar")):
    raise SystemExit("This WindowBar copy is running. Quit it first or set WINDOWBAR_APP_PATH to a separate candidate path.")
PYGUARD
fi
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
task_scratch="${WINDOWBAR_BUILD_PATH:-$PWD/build/swiftpm}"
swift build -c release --product WindowBar --scratch-path "$task_scratch"
task_binary_dir="$(swift build -c release --show-bin-path --scratch-path "$task_scratch")"
cp "$task_binary_dir/WindowBar" "$task_app/Contents/MacOS/WindowBar"
cp Info.plist "$task_app/Contents/Info.plist"
codesign --force --sign - --identifier local.windowbar.app "$task_app"
print -r -- "Built: $task_app"
