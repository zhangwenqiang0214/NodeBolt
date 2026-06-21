#!/bin/bash
# NodeBolt 构建脚本:编译 + 组装 .app + ad-hoc 签名
# 用法: ./build.sh [debug|release]   (默认 release)
set -e
cd "$(dirname "$0")"
CONFIG="${1:-release}"

echo "==> 编译 ($CONFIG, Universal: arm64 + x86_64)"
swift build -c "$CONFIG" --arch arm64 --arch x86_64

# 通用二进制输出在 .build/apple/Products/<Config>/
CONFIG_CAP="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"
BIN=".build/apple/Products/$CONFIG_CAP/NodeBolt"
APP="dist/NodeBolt.app"

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NodeBolt"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

echo "==> 完成: $(cd "$(dirname "$APP")" && pwd)/NodeBolt.app"
