#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="歇会儿"
APP="${APP_NAME}.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译"
swiftc -O \
    -target arm64-apple-macos13.0 \
    -framework AppKit \
    -framework SwiftUI \
    Sources/main.swift \
    Sources/AppDelegate.swift \
    Sources/IdleClock.swift \
    Sources/Presence.swift \
    Sources/Prefs.swift \
    Sources/Habits.swift \
    Sources/LaunchAtLogin.swift \
    Sources/MascotAnimator.swift \
    Sources/MeetingDetector.swift \
    Sources/ReminderPanel.swift \
    Sources/MascotCard.swift \
    Sources/SettingsView.swift \
    -o "$APP/Contents/MacOS/XieHuiEr" \
    -framework AVFoundation \
    -framework CoreAudio

echo "==> 组装 bundle"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# 素材按形象分目录，整目录拷：Contents/Resources/mascots/{a,b,c,d}/*.png
cp -R Resources/mascots "$APP/Contents/Resources/"

echo "==> 临时签名"
codesign --force --deep --sign - "$APP" 2>&1 | tail -1

echo "==> 完成：$(pwd)/$APP"
