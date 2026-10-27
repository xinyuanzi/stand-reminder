#!/bin/bash
# 跑判定机的时间轴用例。全过退出 0，有失败退出 1。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/presence_test"
swiftc -O \
    Sources/PresenceMachine.swift \
    Sources/SessionStore.swift \
    Tools/PresenceTest/main.swift \
    -o "$OUT"

"$OUT"
