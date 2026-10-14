#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}/.."
mkdir -p build/smoke build/module-cache
case "${1:-}" in
  dock) python3 Tests/Smoke/verify_dock.py ;;
  tabs|menus)
    task_suite="${(C)1}"
    xcrun swiftc -swift-version 5 -module-cache-path build/module-cache \
      Tests/Smoke/Support.swift "Tests/Smoke/$task_suite/main.swift" -o "build/smoke/$1"
    "build/smoke/$1"
    ;;
  *) print -u2 'Usage: zsh scripts/smoke.sh dock|tabs|menus'; exit 2 ;;
esac
