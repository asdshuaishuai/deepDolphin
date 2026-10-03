#!/usr/bin/env bash
# smoke.sh — deepDolphin 基础框架冒烟（配置 + 构建 + 二进制自检）。
#
# 用法：scripts/smoke.sh
# 前置：cmake + g++ + Qt6/DTK6 开发环境在 PATH/PKG_CONFIG_PATH 上。
#       （本开发容器没有系统工具链，用 ~/.dd-sysroot/env.sh 提供——见 README「构建环境」）
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$SRC/build"

echo "› 配置：cmake -S $SRC -B $BUILD -DCMAKE_BUILD_TYPE=Release"
cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release

echo "› 构建：cmake --build $BUILD --parallel 4"
cmake --build "$BUILD" --parallel 4

# ★ 冒烟硬约束：可执行文件必须落在 build 根目录
BIN="$BUILD/deepDolphin"
[ -x "$BIN" ] || { echo "✗ 冒烟失败：$BIN 不存在"; exit 1; }
echo "✓ 产物在位：$BIN"

echo "› 二进制自检：$BIN --selfcheck（模型层 fixtures，不需要引擎）"
if "$BIN" --selfcheck; then
    echo "✓ selfcheck 全绿"
else
    echo "✗ selfcheck 有失败"
    exit 1
fi

# 真实引擎对账（contract-check.sh）：引擎缺席 → SKIP 且不算通过（PLAN §8 T12）
if command -v moongit >/dev/null 2>&1 || command -v deepgit >/dev/null 2>&1 || [ -n "${DEEPGIT_BIN:-}" ]; then
    echo "› 真实引擎对账（scripts/contract-check.sh）"
    bash "$SRC/scripts/contract-check.sh" || exit 1
else
    echo "SKIP contract-check：moongit/deepgit 均不在（引擎未安装），本轮冒烟不算全绿——如实记录"
fi
