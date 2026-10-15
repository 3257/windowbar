#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h:h}"

task_output="${WINDOWBAR_PACKAGE_DIR:-$PWD/build/distribution}"
task_arm_scratch="$task_output/swiftpm-arm64"
task_intel_scratch="$task_output/swiftpm-x86_64"
task_app="$task_output/WindowBar.app"
task_dmg="$task_output/WindowBar.dmg"
task_stage="$task_output/dmg-content"

for task_arch in arm64 x86_64; do
	task_triple="$task_arch-apple-macosx14.0"
	if [[ "$task_arch" == arm64 ]]; then
		task_scratch="$task_arm_scratch"
	else
		task_scratch="$task_intel_scratch"
	fi
	swift build -c release --product WindowBar --triple "$task_triple" --scratch-path "$task_scratch"
	task_bin_dir="$(swift build -c release --show-bin-path --triple "$task_triple" --scratch-path "$task_scratch")"
	[[ -x "$task_bin_dir/WindowBar" ]]
done

task_arm_bin="$(swift build -c release --show-bin-path --triple arm64-apple-macosx14.0 --scratch-path "$task_arm_scratch")/WindowBar"
task_intel_bin="$(swift build -c release --show-bin-path --triple x86_64-apple-macosx14.0 --scratch-path "$task_intel_scratch")/WindowBar"
mkdir -p "$task_output"
rm -rf "$task_app" "$task_dmg" "$task_stage"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
xcrun lipo -create "$task_arm_bin" "$task_intel_bin" -output "$task_app/Contents/MacOS/WindowBar"
cp Info.plist "$task_app/Contents/Info.plist"
codesign --force --sign - --identifier local.windowbar.app "$task_app"
codesign --verify --strict "$task_app"
xcrun lipo "$task_app/Contents/MacOS/WindowBar" -verify_arch arm64 x86_64
mkdir -p "$task_stage"
ditto "$task_app" "$task_stage/WindowBar.app"
ln -s /Applications "$task_stage/Applications"
hdiutil create -volname WindowBar -srcfolder "$task_stage" -ov -format UDZO "$task_dmg"
hdiutil verify "$task_dmg"
print -r -- "Built universal app: $task_app"
print -r -- "Packaged for distribution: $task_dmg"
