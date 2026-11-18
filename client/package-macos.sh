#!/bin/sh
# 构建 deepDolphin.app（BUI 客户端 + 内嵌 moongit 引擎）。
#
#   sh package-macos.sh            # 只产出 client/dist/deepDolphin.app
#   sh package-macos.sh --install  # 再安装到 /Applications（不会启动它）
#
# 三条硬约束（与 AGENTS.md / README「设计边界」一致）：
#   1. 内嵌引擎的 rpath 只许 bundle 相对路径 —— 只读校验跨不过 AMFI/dyld，
#      必须 env -i 真跑一次才算数（见 build.sh 里那段长注释的由来）。
#   2. Contents/ 下的可执行文件各自签名：--deep 不覆盖 Resources，
#      这里引擎放在 Contents/MacOS，仍显式签一次再整体签。
#   3. 引擎运行时用到的仓颉 dylib 必须随包；不随包就只能在这台装了 SDK
#      的机器上跑起来 —— 那证明的是开发机，不是 app。
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
APP_NAME="deepDolphin"
BUNDLE="$DIR/dist/$APP_NAME.app"
INSTALL=0
if [ "${1:-}" = "--install" ]; then
  INSTALL=1
fi

echo "› 编译客户端（release）…"
cd "$DIR"
cargo build --release

echo "› 检查引擎与仓颉运行时…"
ENGINE="${MOONGIT_BIN:-$ROOT/moonGit/target/release/bin/main}"
if [ ! -x "$ENGINE" ]; then
  echo "✗ 找不到引擎：$ENGINE" >&2
  echo "  先 cd moonGit && cjpm build，或用 MOONGIT_BIN 指定。" >&2
  exit 1
fi
CJ_HOME="${CANGJIE_HOME:-$HOME/.local/share/cangjie/current}"
CJ_RUNTIME="$CJ_HOME/runtime/lib/darwin_aarch64_cjnative"
for lib in libcangjie-runtime.dylib libboundscheck.dylib; do
  if [ ! -f "$CJ_RUNTIME/$lib" ]; then
    echo "✗ 找不到仓颉运行时：$CJ_RUNTIME/$lib" >&2
    echo "  内嵌引擎没有它就只能靠开发机的绝对路径跑。" >&2
    exit 1
  fi
done

echo "› 组装 $APP_NAME.app…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Frameworks" "$BUNDLE/Contents/Resources/licenses"
cp "$DIR/target/release/deepdolphin-client" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ENGINE" "$BUNDLE/Contents/MacOS/moongit"
cp "$CJ_RUNTIME/libcangjie-runtime.dylib" "$CJ_RUNTIME/libboundscheck.dylib" "$BUNDLE/Contents/Frameworks/"
chmod +x "$BUNDLE/Contents/MacOS/$APP_NAME" "$BUNDLE/Contents/MacOS/moongit"

# 图标 + 许可（HarmonyOS Sans 许可要求随包保留）
ICON="$DIR/../assets/icon/out/macos/AppIcon.icns"
if [ ! -f "$ICON" ]; then
  echo "✗ 找不到图标：${ICON}（先跑 python3 assets/icon/make-icons.py）" >&2
  exit 1
fi
cp "$ICON" "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "$DIR/assets/fonts/LICENSE.txt" "$BUNDLE/Contents/Resources/licenses/HarmonyOS-Sans-LICENSE.txt"
cat > "$BUNDLE/Contents/Resources/licenses/NOTICE.txt" <<'NOTICE'
deepDolphin client
==================
This application bundles the BUI UI runtime (GPL-3.0-or-later), so the
client as a whole is distributed under GPL-3.0-or-later.
License: https://www.gnu.org/licenses/gpl-3.0.html

The moonGit engine is a separate process and is invoked via CLI only.

HarmonyOS Sans Fonts are used in this product.
Copyright 2021 Huawei Device Co., Ltd.
See licenses/HarmonyOS-Sans-LICENSE.txt (must be kept when redistributing).
NOTICE

# Info.plist（无引号 heredoc 便于插值；正文里不能出现反引号）
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>cn.deepdolphin.app</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>CFBundleLocalizations</key><array><string>zh_CN</string></array>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# ── 内嵌引擎 rpath：删光再加 bundle 相对路径 ──────────────────────────
# 引擎在 Contents/MacOS，@executable_path/../Frameworks 即 Contents/Frameworks。
EMBEDDED="$BUNDLE/Contents/MacOS/moongit"
rpaths() {
  otool -l "$1" 2>/dev/null | awk '$1 == "path" { print $2 }'
}
# install_name_tool 拒改已签名二进制；剥签名失败（本来就没签）不算错。
codesign --remove-signature "$EMBEDDED" 2>/dev/null || true
while :; do
  FIRST_RPATH="$(rpaths "$EMBEDDED" | head -1)"
  if [ -z "$FIRST_RPATH" ]; then
    break
  fi
  # -delete_rpath 收路径字符串不收序号；失败时退出码仍是 0，所以靠下一轮再读。
  install_name_tool -delete_rpath "$FIRST_RPATH" "$EMBEDDED" 2>/dev/null || break
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$EMBEDDED"
LEFT="$(rpaths "$EMBEDDED")"
if printf '%s\n' "$LEFT" | grep -q '^/'; then
  echo "✗ 内嵌引擎 rpath 仍含构建机绝对路径：" >&2
  printf '%s\n' "$LEFT" | sed 's/^/  /' >&2
  exit 1
fi

# ── 签名 ──────────────────────────────────────────────────────────────
if ! codesign --force --sign - "$EMBEDDED" 2>/dev/null; then
  echo "✗ 内嵌引擎签名失败（未签名的 arm64 会被 AMFI 直接杀掉）" >&2
  exit 1
fi
if ! codesign --force --deep --sign - "$BUNDLE" 2>/dev/null; then
  echo "✗ bundle 签名失败" >&2
  exit 1
fi
codesign --verify --deep --strict "$BUNDLE"
codesign --verify --strict "$EMBEDDED"

# ── 冒烟：空环境真跑一次（验证自包含，而不是“这台机器装了 SDK”）──
SMOKE="$(mktemp -d "${TMPDIR:-/tmp}/deepdolphin-smoke.XXXXXX")"
if SMOKE_OUT="$(env -i HOME="$SMOKE" PATH=/usr/bin:/bin \
      DEEPGIT_HOME="$SMOKE/home" "$EMBEDDED" status --json --quiet 2>&1)"; then
  if printf '%s' "$SMOKE_OUT" | grep -q '"projects"'; then
    echo "✓ 内嵌引擎脱离 SDK 可执行（env -i status --json）"
  else
    echo "✗ 内嵌引擎冒烟输出不是 status JSON：" >&2
    printf '%s\n' "$SMOKE_OUT" | head -5 | sed 's/^/  /' >&2
    exit 1
  fi
else
  SMOKE_RC=$?
  echo "✗ 内嵌引擎在空环境下跑不起来（exit=${SMOKE_RC}）" >&2
  case "$SMOKE_RC" in
    137) echo "  137=SIGKILL：未签名被 AMFI 杀掉" >&2 ;;
    139) echo "  139=SIGSEGV：Frameworks 里的 dylib 没解析到" >&2 ;;
  esac
  printf '%s\n' "$SMOKE_OUT" | head -5 | sed 's/^/  /' >&2
  exit 1
fi
rm -rf "$SMOKE"

# 客户端 --help 在开窗前就 return，不会弹窗；顺手证明它可执行。
"$BUNDLE/Contents/MacOS/$APP_NAME" --help >/dev/null
echo "✓ 客户端可执行（--help，未开窗）"

echo "✓ 已产出：$BUNDLE"

# ── 安装 ──────────────────────────────────────────────────────────────
if [ "$INSTALL" = "1" ]; then
  TARGET="/Applications/$APP_NAME.app"
  if [ -e "$TARGET" ]; then
    mkdir -p "$HOME/.Trash"
    BACKUP="$HOME/.Trash/$APP_NAME-old-$(date +%Y%m%d-%H%M%S).app"
    mv "$TARGET" "$BACKUP"
    echo "  旧版本已移到回收站：$BACKUP"
  fi
  cp -R "$BUNDLE" "$TARGET"
  codesign --verify --deep --strict "$TARGET"
  echo "✓ 已安装：${TARGET}（未启动）"
fi
