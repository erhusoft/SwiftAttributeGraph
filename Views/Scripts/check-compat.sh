#!/bin/bash
# Compatibility check: every sample file must type-check against real SwiftUI and against the shells.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
echo "== 1. against real SwiftUI (macOS SDK)"
swiftc -typecheck Samples/*.swift
echo "   OK"
echo "== 2. against the shells"
swift build --target ShellUI 2>&1 | tail -8
MODULES="$(swift build --show-bin-path)/Modules"
swiftc -typecheck -D USE_SHELL -I "$MODULES" Samples/*.swift
echo "   OK"
echo "Every sample compiles in both."
