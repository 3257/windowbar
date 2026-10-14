#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}/.."
mkdir -p docs/screenshots
task_app="${WINDOWBAR_APP_PATH:-$PWD/build/WindowBar.app}"
"$task_app/Contents/MacOS/WindowBar" --render-screenshots docs/screenshots
