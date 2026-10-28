#!/bin/bash
# 动作引擎行为测试。跑约 35 秒，退出码 0 = 通过。
#
# 为什么要脚本而不是手敲 swiftc：这个测试里有一半是「跑一段真循环看它动没动」，
# 参数里少一个文件就编译不过，多一个 -O 之外的优化项又会把时序跑偏。
# 手敲过一次 64 位参数错误、一次忘了 -framework AppKit，都浪费在排查上。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="$(mktemp -d)"
swiftc -O -target arm64-apple-macos13.0 \
    -framework AppKit -framework SwiftUI \
    Sources/MascotAnimator.swift \
    Tools/AnimTest/main.swift \
    -o "$OUT_DIR/run"

"$OUT_DIR/run"
