#!/bin/bash
# 游走在真实面板上到底动不动。跑 3 秒，退出码 0 = 通过。
#
# 素材要拷到可执行文件旁边（MascotAssets 对裸可执行文件走 resourcePath 兜底），
# 否则卡片里的形象是空的，虽然不影响位置测试，但截图/肉眼对不上。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="$(mktemp -d)"
swiftc -O -target arm64-apple-macos13.0 \
    -framework AppKit -framework SwiftUI \
    Sources/MascotAnimator.swift \
    Sources/Prefs.swift \
    Sources/Habits.swift \
    Sources/MascotCard.swift \
    Sources/ReminderPanel.swift \
    Sources/Wander.swift \
    Tools/WanderTest/main.swift \
    -o "$OUT_DIR/run"

cp -R Resources/mascots "$OUT_DIR/"
"$OUT_DIR/run" "${1:-c}"
