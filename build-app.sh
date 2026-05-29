#!/bin/bash
# 把 SwiftPM 编译出来的可执行文件包装成 macOS .app bundle，
# 用稳定的 Bundle Identifier + ad-hoc 签名锁住 TCC 权限身份，
# 避免每次重新编译都要重新授权「辅助功能 / 输入监控」。
#
# 用法：
#   ./build-app.sh            # debug 构建（默认，编译快）
#   ./build-app.sh release    # release 构建（启动稍快、体积小）
#   ./build-app.sh clean      # 清理 .app 和 SwiftPM 构建产物

set -euo pipefail

APP_NAME="FastEditorApp"
BUNDLE_ID="com.fasteditor.app"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# ---- clean ----
if [ "${1:-}" = "clean" ]; then
    echo "→ cleaning..."
    rm -rf "$APP_NAME.app"
    swift package clean
    echo "✅ cleaned"
    exit 0
fi

CONFIG="${1:-debug}"

# ---- build ----
echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "❌ binary not found at $BIN_PATH"
    exit 1
fi

# ---- assemble .app ----
APP_DIR="$APP_NAME.app"
echo "→ assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# ---- sign (ad-hoc) ----
# 关键：把 designated requirement 显式设成 identifier-based（而不是 ad-hoc 默认的
# cdhash-based）。TCC 在授权时记下这个 DR，之后每次启动按 DR 判断「是不是同一个 App」。
#   - 默认 ad-hoc 的 DR = `cdhash H"..."`：二进制一变 hash 就变 → TCC 当成新 App → 重新授权。
#   - 这里 `-r=designated => identifier "ID"`：只认 bundle ID → 重建后 hash 变了 TCC 仍认旧授权。
# （仅 --identifier 不够：那只改 Identifier 字段，DR 仍是 cdhash。必须显式给 -r。）
echo "→ codesign (ad-hoc, identifier-based DR=$BUNDLE_ID)"
codesign --force --sign - --identifier "$BUNDLE_ID" \
    -r="designated => identifier \"$BUNDLE_ID\"" \
    "$APP_DIR" >/dev/null 2>&1
codesign -dv "$APP_DIR" 2>&1 | grep -E "Identifier|Signature" || true

echo ""
echo "✅ built $APP_DIR"
echo ""
echo "运行： open $APP_DIR"
echo "查看日志： /usr/bin/log stream --predicate 'subsystem == \"$BUNDLE_ID\"' --info"
echo "停止运行： pkill -x $APP_NAME"
echo "重置授权(重测引导)： tccutil reset Accessibility $BUNDLE_ID && tccutil reset ListenEvent $BUNDLE_ID"

# ════════════════════════════════════════════════════════════════════════════
# ⛔ release-notarize 分支 —— 占位，本次不实现（见 CLAUDE.md §8）
# ════════════════════════════════════════════════════════════════════════════
# 需要 Apple 开发者账号 + 钥匙串里的 "Developer ID Application" 证书才能跑。
# 用户当前没有账号，下面任何 codesign --sign "Developer ID..." / notarytool 都会失败，
# 所以这里只留注释占位，等账号到位后另开会话照 CLAUDE.md §8 填充并跑通。
#
# if [ "${1:-}" = "release-notarize" ]; then
#     DEV_ID="Developer ID Application: 你的名字 (TEAMID)"
#     # 1) release 构建 + 组装 .app（复用上面 assemble 逻辑，CONFIG=release）
#     # 2) codesign --force --options runtime --timestamp --sign "$DEV_ID" --identifier "$BUNDLE_ID" "$APP_DIR"
#     #    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
#     # 3) ditto -c -k --keepParent "$APP_DIR" "$APP_NAME.zip"
#     # 4) xcrun notarytool submit "$APP_NAME.zip" --keychain-profile "FE-NOTARY" --wait
#     # 5) xcrun stapler staple "$APP_DIR"
#     # 6) spctl -a -vvv -t install "$APP_DIR"
# fi
