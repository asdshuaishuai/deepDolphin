#!/bin/sh
# 构建 deepGit.app —— macOS 客户端（菜单栏常驻 + 主面板窗口），双击即用。
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

APP_NAME="deepGit"
BUILD_DIR=".build/release"
APP_BUNDLE="$DIR/$APP_NAME.app"

echo "› 编译 Swift 包…"
swift build -c release

echo "› 组装 .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 应用图标 + models.dev 目录快照（AI 设置选择器数据骨干）
if [ -f "$DIR/AppIcon.icns" ]; then
  cp "$DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
if [ -f "$DIR/Resources/models-dev.json" ]; then
  cp "$DIR/Resources/models-dev.json" "$APP_BUNDLE/Contents/Resources/models-dev.json"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>deepGit</string>
    <key>CFBundleDisplayName</key><string>deepGit</string>
    <key>CFBundleIdentifier</key><string>cn.deepgit.app</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST

# 可选地把引擎二进制打包进 app（独立分发；找不到时 app 会按
# DEEPGIT_BIN → 内嵌副本 → ~/.local/bin → PATH 的顺序自行发现引擎）
for CANDIDATE in \
  "$(command -v deepgit 2>/dev/null || true)" \
  "$HOME/.local/bin/deepgit" \
  "$DIR/../../../engine/target/release/bin/main"; do
  if [ -n "$CANDIDATE" ] && [ -x "$CANDIDATE" ]; then
    cp "$CANDIDATE" "$APP_BUNDLE/Contents/Resources/deepgit"
    echo "   已内嵌引擎：$CANDIDATE"
    break
  fi
done

# 内嵌引擎所需的仓颉运行时（若存在），使 app 可独立运行
CJ_HOME="${CANGJIE_HOME:-$HOME/.local/share/cangjie/current}"
CJ_RUNTIME="$CJ_HOME/runtime/lib/darwin_aarch64_cjnative"
if [ -d "$CJ_RUNTIME" ]; then
  mkdir -p "$APP_BUNDLE/Contents/Frameworks"
  cp "$CJ_RUNTIME/"*.dylib "$APP_BUNDLE/Contents/Frameworks/" 2>/dev/null || true
  # 让内嵌引擎优先从 app 自己的 Frameworks 目录加载运行时，
  # 这样分发给别人时无需安装仓颉 SDK。
  if [ -x "$APP_BUNDLE/Contents/Resources/deepgit" ]; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
      "$APP_BUNDLE/Contents/Resources/deepgit" 2>/dev/null || true
    echo "   已把 @executable_path/../Frameworks 写入引擎 rpath"
  fi
  echo "   已内嵌仓颉运行时（$(ls "$APP_BUNDLE/Contents/Frameworks" | wc -l | tr -d ' ') 个 dylib）"
fi

# 广告（ad-hoc）签名：本机运行足够
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "✓ 构建完成：$APP_BUNDLE"
echo "  安装：cp -R \"$APP_BUNDLE\" /Applications/ && open /Applications/$APP_NAME.app"
