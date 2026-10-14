#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
task_app="${WINDOWBAR_APP_PATH:-$PWD/build/WindowBar.app}"
if [[ -f "$task_app/Contents/MacOS/WindowBar" ]] && /usr/sbin/lsof -t "$task_app/Contents/MacOS/WindowBar" >/dev/null 2>&1; then
  print -u2 'This WindowBar copy is running. Quit it first or set WINDOWBAR_APP_PATH to a separate candidate path.'
  exit 1
fi
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
task_scratch="${WINDOWBAR_BUILD_PATH:-$PWD/build/swiftpm}"
swift build -c release --product WindowBar --scratch-path "$task_scratch"
task_binary_dir="$(swift build -c release --show-bin-path --scratch-path "$task_scratch")"
cp "$task_binary_dir/WindowBar" "$task_app/Contents/MacOS/WindowBar"
cp Info.plist "$task_app/Contents/Info.plist"
codesign --force --sign - --identifier local.windowbar.app "$task_app"
print -r -- "Built: $task_app"
