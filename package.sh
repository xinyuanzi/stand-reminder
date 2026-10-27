#!/bin/bash
# 打 dmg。先跑 build.sh，再把 .app、一个 Applications 软链接、和一份首次打开说明
# 一起塞进镜像。
#
# 用法：
#   ./package.sh            # 产出 dist/歇会儿-<版本>.dmg
#   ./package.sh --no-build # 跳过编译，直接拿现成的 .app 打包
#
# 没有签名/公证（不买 Apple 开发者账号），别人打开会被 Gatekeeper 拦。
# 镜像里那份「先看我.html」就是给这个场景准备的：双击用浏览器打开，
# 里面有右键打开、系统设置放行、xattr 三条路，以及「不放心就自己编译」。
# 改完说明记得在两个架构上都双击试一次。
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="歇会儿"
APP="${APP_NAME}.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="dist/${APP_NAME}-${VERSION}.dmg"
README_HTML="packaging/先看我.html"

if [[ "${1:-}" != "--no-build" ]]; then
    ./build.sh
fi

[[ -d "$APP" ]] || { echo "找不到 $APP，先跑一次 ./build.sh"; exit 1; }
[[ -f "$README_HTML" ]] || { echo "找不到 $README_HTML"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$README_HTML" "$STAGE/先看我.html"

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
echo "镜像内容：${APP} / Applications / 先看我.html"
echo
echo "未签名分发（当前策略，不买 ¥688/年 的开发者账号）："
echo "  · 对方双击 dmg 会先看到「先看我.html」，里面三条路都写了"
echo "  · 最省事的一条：拖进应用程序 → Control 点图标 → 打开"
echo "  · 兜底：xattr -dr com.apple.quarantine /Applications/${APP}"
echo
echo "发出前自测：把 dmg 拷到另一台机器（或新建用户），"
echo "双击 → 挂载 → 拖走 → Control 点打开，全程不查文档也能装上。"
