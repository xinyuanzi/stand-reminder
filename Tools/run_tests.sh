#!/bin/bash
# 跑判定机的时间轴用例 + 游走步进。全过退出 0，有失败退出 1。
#
# 这两个模块的共同点是「纯逻辑、不碰 AppKit」——也是它们能在这里被快进、
# 跑 2000 帧还不花一分钱的原因。要测的东西一旦需要真窗口，就该去 Tools/ 下
# 找对应的专用工具（FullscreenTest / PokeTest / WindowShot）。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/presence_test"
swiftc -O \
    Sources/PresenceMachine.swift \
    Sources/SessionStore.swift \
    Sources/Wander.swift \
    Tools/PresenceTest/main.swift \
    -o "$OUT"

"$OUT"
