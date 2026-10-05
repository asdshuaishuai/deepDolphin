#!/usr/bin/env bash
# build.sh —— deepin 客户端编译（Release）。产物：build/deepDolphin。
#
# 典型功能测试动线：
#   scripts/build.sh                 # 编译（首次自动 configure）
#   scripts/build.sh --selfcheck     # 编译后顺带跑模型层自检（58 例）
#   scripts/dev-run.sh               # 真桌面启动（跟随系统主题；-t dark 可强制）
#   scripts/dev-run.sh -o            # 离屏冒烟（无显示环境用）
#
# 引擎：不装 moongit 也能起（面板进安装引导页）；装了（PATH 或 DEEPGIT_BIN）
# 则直接出数据。运行环境（dd-sysroot 运行库）由 dev-run.sh 注入。

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$SRC/build/deepDolphin"
SYSROOT_LIB="$HOME/.local/dd-sysroot/usr/lib/x86_64-linux-gnu"

if [ ! -f "$SRC/build/CMakeCache.txt" ]; then
    echo "› 首次 configure（Release）…"
    cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release
fi
echo "› 编译中（$(nproc) 并行）…"
cmake --build "$SRC/build" --parallel "$(nproc)"
echo "✓ 产物：$BIN"

if [ "${1:-}" = "--selfcheck" ]; then
    if [ -d "$SYSROOT_LIB" ]; then
        export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$SYSROOT_LIB"
        export QT_PLUGIN_PATH="${QT_PLUGIN_PATH:+$QT_PLUGIN_PATH:}$SYSROOT_LIB/qt6/plugins"
    fi
    export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
    "$BIN" --selfcheck | tail -1
fi
