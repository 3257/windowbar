#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
task_app="$PWD/build/WindowBar.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
swift build -c release --product WindowBar --scratch-path build/swiftpm
task_binary_dir="$(swift build -c release --show-bin-path --scratch-path build/swiftpm)"
cp "$task_binary_dir/WindowBar" "$task_app/Contents/MacOS/WindowBar"
cp Info.plist "$task_app/Contents/Info.plist"
codesign --force --sign - --identifier local.windowbar.app "$task_app"
print -r -- "Built: $task_app"
