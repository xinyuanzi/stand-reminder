#!/bin/bash
# 打 dmg。先跑 build.sh，再把 .app 和一个 Applications 软链接一起塞进镜像。
#
# 用法：
#   ./package.sh            # 产出 dist/歇会儿-<版本>.dmg
#   ./package.sh --no-build # 跳过编译，直接拿现成的 .app 打包
#
# 没有签名/公证的话，别人打开会被 Gatekeeper 拦。README 里给了
# `xattr -dr com.apple.quarantine` 的绕行说明——发布前记得同步。
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="歇会儿"
APP="${APP_NAME}.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="dist/${APP_NAME}-${VERSION}.dmg"

if [[ "${1:-}" != "--no-build" ]]; then
    ./build.sh
fi

[[ -d "$APP" ]] || { echo "找不到 $APP，先跑一次 ./build.sh"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$DMG"

# 优先用新的 diskutil（hdiutil create 已标记弃用）；老系统上没有就退回去。
# 注意 source 是**文件夹**、format 用 UDZO（压缩只读），体积最小。
if diskutil image create from --help > /dev/null 2>&1; then
    diskutil image create from --volumeName "$APP_NAME" --format UDZO \
        "$STAGE" "$DMG" > /dev/null 2>&1 || { echo "diskutil 打包失败"; exit 1; }
else
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ \
        -format UDZO -ov "$DMG" > /dev/null || { echo "hdiutil 打包失败"; exit 1; }
fi

echo "==> $DMG  ($(du -h "$DMG" | cut -f1))"
echo
echo "发给别人之前确认："
echo "  · 已签名 + 公证 → 双击直接打开"
echo "  · 未签名 → 对方需要右键「打开」，或运行："
echo "      xattr -dr com.apple.quarantine /Applications/${APP}"
