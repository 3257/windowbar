#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}/.."
mkdir -p docs/screenshots
build/WindowBar.app/Contents/MacOS/WindowBar --render-screenshots docs/screenshots
