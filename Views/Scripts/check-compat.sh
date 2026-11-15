#!/bin/bash
# Compatibility check of the first slice: the same sample file must type-check against real SwiftUI and against the shells.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
echo "== 1. against real SwiftUI (macOS SDK)"
swiftc -typecheck Samples/ColumnScreen.swift
echo "   OK"
echo "== 2. against the shells"
swift build --target ShellUI 2>&1 | tail -8
MODULES="$(swift build --show-bin-path)/Modules"
swiftc -typecheck -D USE_SHELL -I "$MODULES" Samples/ColumnScreen.swift
echo "   OK"
echo "The sample compiles in both."
