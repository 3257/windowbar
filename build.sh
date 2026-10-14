#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
task_app="$PWD/build/WindowBar.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources" "$PWD/build/module-cache"
xcrun swiftc -swift-version 5 -O -module-cache-path "$PWD/build/module-cache" \
    -target arm64-apple-macosx14.0 -framework AppKit -framework ApplicationServices -framework QuartzCore \
    Sources/WindowBar.swift -o "$task_app/Contents/MacOS/WindowBar"
cp Info.plist "$task_app/Contents/Info.plist"
codesign --force --sign - --identifier local.windowbar.app "$task_app"
print -r -- "Built: $task_app"
