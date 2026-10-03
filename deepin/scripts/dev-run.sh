#!/usr/bin/env bash
# dev-run.sh — deepin 客户端开发启动脚本：一键带环境起面板。
#
# 用法（都在 deepin/ 目录下）：
#   scripts/dev-run.sh                  # 二进制不在就先构建；跟随系统主题直启
#   scripts/dev-run.sh -b               # 先重新构建再启动
#   scripts/dev-run.sh -t dark          # 强制主题（DEEPDOLPHIN_THEME=dark；light 同理）
#   scripts/dev-run.sh -o               # 离屏运行（无显示环境/纯看日志用）
#   scripts/dev-run.sh -p               # 只跑 --platform-probe 就退出（不起面板）
#   scripts/dev-run.sh -- --selfcheck   # “--”之后原样透传给 deepDolphin
#   scripts/dev-run.sh -- --version
#
# 说明：
# · 开发容器（~/.local/dd-sysroot 存在）自动注入 LD_LIBRARY_PATH/QT_PLUGIN_PATH；
#   真机系统 Qt6/DTK6 下这两项本来就不需要，目录不存在时不会设。
# · 引擎未安装时照样能起：面板会进「引擎未找到」安装引导页（诚实降级，不是报错）。
# · 应用是单实例：已开着面板时再执行，参数会转发给现有实例（深链语义）。
# 退出码 = deepDolphin 的退出码。

set -euo pipefail

SRC="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$SRC/build/deepDolphin"
SYSROOT_LIB="$HOME/.local/dd-sysroot/usr/lib/x86_64-linux-gnu"

BUILD=0
THEME=""
OFFSCREEN=0
PROBE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -b | --build) BUILD=1 ;;
        -t | --theme)
            [ $# -ge 2 ] || {
                echo "--theme 需要 light|dark" >&2
                exit 2
            }
            THEME="$2"
            shift
            ;;
        -o | --offscreen) OFFSCREEN=1 ;;
        -p | --probe) PROBE=1 ;;
        -h | --help)
            sed -n '2,18p' "$0"
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "未知参数：$1（“--”之后的参数会原样透传给 deepDolphin，见 -h）" >&2
            exit 2
            ;;
    esac
    shift
done

# ── 构建：缺二进制自动建，-b 强制重建 ──
if [ "$BUILD" = 1 ] || [ ! -x "$BIN" ]; then
    echo "› 构建中…"
    if [ ! -f "$SRC/build/CMakeCache.txt" ]; then
        cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release
    fi
    cmake --build "$SRC/build" --parallel "$(nproc)"
fi

# ── 运行环境 ──
# sysroot 运行库只在开发容器需要；目录不存在（真机系统 Qt6/DTK6）就不设
if [ -d "$SYSROOT_LIB" ]; then
    export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-$SYSROOT_LIB}"
    export QT_PLUGIN_PATH="${QT_PLUGIN_PATH:-$SYSROOT_LIB/qt6/plugins}"
fi
if [ "$OFFSCREEN" = 1 ]; then
    export QT_QPA_PLATFORM=offscreen
fi
if [ -n "$THEME" ]; then
    case "$THEME" in
        light | dark) export DEEPDOLPHIN_THEME="$THEME" ;;
        *)
            echo "--theme 只认 light|dark（不传 = 跟随系统）" >&2
            exit 2
            ;;
    esac
fi

# 引擎提示（只提示，不拦——面板自己有安装引导页）
if [ -z "${DEEPGIT_BIN:-}" ] && ! command -v moongit >/dev/null 2>&1; then
    echo "ℹ 未发现 moongit 引擎（PATH 与 DEEPGIT_BIN 都没有）：面板会进安装引导页。" >&2
fi

if [ "$PROBE" = 1 ]; then
    exec "$BIN" --platform-probe
fi

echo "› 启动 deepDolphin（主题=${THEME:-跟随系统}，离屏=$OFFSCREEN，二进制=$BIN）"
exec "$BIN" "$@"
