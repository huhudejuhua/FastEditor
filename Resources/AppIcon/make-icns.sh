#!/bin/bash
# 把 icon-1024.png 切成多尺寸 .iconset 再用 iconutil 编译成 AppIcon.icns。
# 纯 macOS 自带工具（sips + iconutil），零第三方依赖。
# 类比 Android：相当于把一张大图切成 mdpi/hdpi/xhdpi… 各档，打进一个标准容器。
#
# 用法： ./make-icns.sh      （在本目录运行）
# 产出： AppIcon.icns（同目录），供 build-app.sh 拷进 .app

set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

SRC="icon-1024.png"
[ -f "$SRC" ] || { echo "❌ 缺少 $SRC（先跑 swift make-icon.swift \"\$PWD/icon-1024.png\"）"; exit 1; }

ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"

# macOS 图标标准要求的尺寸矩阵（pt@scale → 实际像素）
gen() { sips -z "$2" "$2" "$SRC" --out "$ICONSET/$1" >/dev/null; }
gen icon_16x16.png        16
gen icon_16x16@2x.png     32
gen icon_32x32.png        32
gen icon_32x32@2x.png     64
gen icon_128x128.png      128
gen icon_128x128@2x.png   256
gen icon_256x256.png      256
gen icon_256x256@2x.png   512
gen icon_512x512.png      512
gen icon_512x512@2x.png   1024

iconutil -c icns "$ICONSET" -o AppIcon.icns
rm -rf "$ICONSET"
echo "✅ wrote $DIR/AppIcon.icns"
