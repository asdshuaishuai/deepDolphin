#!/usr/bin/env bash
# run.sh —— 启动 BUI 客户端（真窗口，X11 宿主）。
#
# 前置：scripts/build.sh 已跑过（产物 target/release/deepdolphin-client）。
# 需要图形会话：DISPLAY=:0（Wayland 会话走 XWayland 也可用）。
# 引擎发现顺序（src/engine.rs:1239）：MOONGIT_BIN → DEEPGIT_BIN →
# 可执行文件旁的 moongit/deepgit → PATH。
#
# 用法：scripts/run.sh [-- 测试参数原样透传]

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$HERE/target/release/deepdolphin-client"

[[ -x "$BIN" ]] || { echo "✗ 还没有产物，先跑 scripts/build.sh" >&2; exit 1; }
command -v moongit >/dev/null 2>&1 || [ -n "${MOONGIT_BIN:-}${DEEPGIT_BIN:-}" ] || \
    echo "ℹ 未发现 moongit 引擎（PATH / MOONGIT_BIN / DEEPGIT_BIN 都没有）：客户端会起，但引擎功能不可用" >&2

: "${DISPLAY:=:0}"
export DISPLAY

echo "› 启动 deepDolphin（BUI/X11，DISPLAY=$DISPLAY）"
exec "$BIN" "$@"
