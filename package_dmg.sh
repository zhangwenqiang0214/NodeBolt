#!/bin/bash
# 打包 NodeBolt 为 .dmg(拖入 Applications 即可安装)
set -e
cd "$(dirname "$0")"

./build.sh release

APP="dist/NodeBolt.app"
DMG="dist/NodeBolt.dmg"
[ -d "$APP" ] || { echo "找不到 $APP"; exit 1; }

rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"     # 方便拖拽安装

hdiutil create -volname "NodeBolt" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ 生成: $(cd "$(dirname "$DMG")" && pwd)/NodeBolt.dmg  ($(du -h "$DMG" | cut -f1))"
