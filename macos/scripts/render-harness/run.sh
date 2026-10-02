#!/bin/bash
# run.sh — 一键跑离屏渲染快照。
#
#   scripts/render-harness/run.sh [输出目录]
#
# 做四件事，缺一不可：
#   1. 造沙箱项目（**只写 /tmp，绝不碰 ~/.deepgit**）
#   2. 用 -DDEEPGIT_RENDER_HARNESS 编译（屏蔽 DeepGitApp 的 @main）
#   3. 装成最小 .app bundle —— 裸可执行文件会在通知系统那里崩
#      （bundleProxyForCurrentProcess is nil），而模型加载路径会请求通知权限
#   4. 以 .prohibited 激活策略运行：不进 Dock、不抢焦点
set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-/tmp/dg-harness}"
SANDBOX_HOME="/tmp/dg-visual"
SANDBOX_PROJECTS="/tmp/dg-visual-projects"
# PKG_DIR = <repo>/clients/macos/deepGit ⇒ 仓库根要上三级
REPO_ROOT="$(cd "$PKG_DIR/../../.." && pwd)"
ENGINE_BIN="$REPO_ROOT/engine/target/release/bin/main"

# 客户端检查/编译前必须 unset SDKROOT（引擎构建才需要它）
unset SDKROOT

if [ ! -x "$ENGINE_BIN" ]; then
  echo "✗ 找不到引擎二进制：$ENGINE_BIN" >&2
  echo "  先构建：cd engine && cjpm build -c release" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}" "$SANDBOX_HOME" "$SANDBOX_PROJECTS/alpha" "$SANDBOX_PROJECTS/beta"

# 沙箱项目：alpha 有 5 次提交（提交构成卡才有内容），beta 只有 1 次。
# 两个项目的「未提交改动」故意留空 —— 脏文件清单那一支在快照里才看得出排版。
if [ ! -d "$SANDBOX_PROJECTS/alpha/.git" ]; then
  ( cd "$SANDBOX_PROJECTS/alpha" && git init -q -b main
    for i in 1 2 3 4 5; do
      echo "line $i" >> a.txt
      git add .
      git -c user.name=t -c user.email=t@t commit -q -m "feat: add line $i"
    done )
fi
if [ ! -d "$SANDBOX_PROJECTS/beta/.git" ]; then
  ( cd "$SANDBOX_PROJECTS/beta" && git init -q -b main
    echo hi > b.txt; git add .
    git -c user.name=t -c user.email=t@t commit -q -m "fix: first" )
fi

export DEEPGIT_HOME="$SANDBOX_HOME"
"$ENGINE_BIN" add "$SANDBOX_PROJECTS/alpha" --name alpha >/dev/null 2>&1
"$ENGINE_BIN" add "$SANDBOX_PROJECTS/beta"  --name beta  >/dev/null 2>&1

SDK="$(xcrun --show-sdk-path --sdk macosx)"
echo "编译 harness（-DDEEPGIT_RENDER_HARNESS）…"
swiftc -swift-version 5 -DDEEPGIT_RENDER_HARNESS -sdk "$SDK" \
  "$PKG_DIR"/Sources/deepGit/*.swift \
  "$PKG_DIR"/scripts/render-harness/main.swift \
  -o "$OUT_DIR/harness" || { echo "✗ 编译失败" >&2; exit 1; }

# 最小 bundle：只要 Bundle.main 能用，UNUserNotificationCenter 才不会抛
# NSInternalInconsistencyException。app 不激活、不上 Dock。
APP="$OUT_DIR/harness.app"
mkdir -p "$APP/Contents/MacOS"
cp "$OUT_DIR/harness" "$APP/Contents/MacOS/harness"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.deepgit.renderharness</string>
  <key>CFBundleName</key><string>deepGitRenderHarness</string>
  <key>CFBundleExecutable</key><string>harness</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

export DEEPGIT_BIN="$ENGINE_BIN"
# 第二个参数原样透传给 harness：传 "window" 改走「装进 NSWindow 但不上屏」那条路。
MODE="${2:-}"
echo "渲染（输出到 ${OUT_DIR}${MODE:+，模式 ${MODE}}）…"
"$APP/Contents/MacOS/harness" "$OUT_DIR/shot.png" $MODE
RC=$?
echo ""
echo "产出："
ls -la "${OUT_DIR}"/*.png 2>/dev/null | awk '{print "  " $NF "  " $5 " bytes"}'
echo ""
echo "注意：快照的已知限制见 scripts/render-harness/main.swift 顶部；"
echo "panel 模式专治顶栏（内容排版回默认模式看，理由见第 6 条）；"
echo "按钮文字与个别行距在离屏下不可信，判断界面最终还是要看真窗口。"
exit $RC
