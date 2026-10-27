#!/bin/bash
# 验证「程序移动窗口」和「用户拖窗口」在 AppKit 眼里长得一模一样。
# 这是修「游走被误判成拖拽」那条 bug 的事实依据，退出码 0 = 通过。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="$(mktemp -d)"
swiftc -O -target arm64-apple-macos13.0 \
    -framework AppKit \
    Sources/Wander.swift \
    Tools/MoveNotifyTest/main.swift \
    -o "$OUT_DIR/run"

"$OUT_DIR/run"
