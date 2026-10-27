#!/bin/bash
# 全屏 Space 验证：卡片能不能浮在全屏窗口之上。
# 会短暂切一次全屏，桌面闪一下，约 6 秒。跑完自动退出。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="$(mktemp -d)"
swiftc -O \
    -target arm64-apple-macos13.0 \
    -framework AppKit -framework SwiftUI \
    Sources/MascotAnimator.swift \
    Sources/Prefs.swift \
    Sources/Habits.swift \
    Sources/MascotCard.swift \
    Sources/ReminderPanel.swift \
    Tools/FullscreenTest/main.swift \
    -o "$OUT_DIR/run"

# 裸可执行文件没有 bundle，素材目录要拷到二进制旁边
cp -R Resources/mascots "$OUT_DIR/"
"$OUT_DIR/run"
