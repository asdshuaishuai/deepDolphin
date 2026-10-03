#!/usr/bin/env bash
# build-system.sh — 用**系统** Qt6/DTK6（无 sysroot）构建（M0-8）。
#
# 为什么要有这条：开发容器里的 Qt6/DTK6 全在 ~/.local/dd-sysroot，缺 libqt6svg6-dev
# → `DD_HAVE_QTSVG` 图标染色分支**从未被编译过**。真机/打包环境一定带 Qt6Svg，
# 那条路径第一次上线才编译 = 把未知留在发布路径上。
#
# 用法：scripts/build-system.sh [build目录]   （干净 deepin 25 / UOS 上跑）
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-$SRC/build-system}"

echo "› 系统工具链：$(command -v cmake) $(command -v g++)"
cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --parallel "$(nproc)"

BIN="$BUILD/deepDolphin"
"$BIN" --selfcheck
"$BIN" --version
echo "✓ 系统 Qt6/DTK6 矩阵通过（$BIN）"
