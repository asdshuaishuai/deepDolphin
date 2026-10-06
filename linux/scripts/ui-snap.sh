#!/usr/bin/env bash
# ui-snap.sh —— 拍一页 UI 快照并转成 PNG（无头，SDL dummy 驱动）。
#
# 用法：
#   scripts/ui-snap.sh <名字> <out.png>     # 基础用法：拍仪表盘
#   DD_SNAP_ROOT=board scripts/ui-snap.sh 看板 <out.png>
#   DD_SNAP_PROJECT=atlas DD_SNAP_W=1400 DD_SNAP_H=2400 scripts/ui-snap.sh 详情 <out.png>
#   DD_SNAP_AI=chat scripts/ui-snap.sh AI对话 <out.png>
#   DD_SNAP_ACTION=busy scripts/ui-snap.sh 忙碌态 <out.png>
#
# 可用开关（src/main.cj 快照族）：DD_SNAP_ROOT=board|milestones、
# DD_SNAP_PROJECT=<名>、DD_SNAP_AI=chat|settings、DD_SNAP_ACTION=busy|fail、
# DD_SNAP_ADD=1、DD_SNAP_CONFIRM=1、DD_SNAP_CLICK=<行号>、DD_SNAP_W/H。
# 快照读 tests/fixtures/ 的引擎真实输出（不走子进程）。
#
# 产物：<out.png>（中间 .bmp 落在临时目录，自动清理）。

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${1:?用法：ui-snap.sh <名字> <out.png>}"
OUT="${2:?用法：ui-snap.sh <名字> <out.png>}"

TMP_BMP="$(mktemp --suffix=.bmp)"
trap 'rm -f "$TMP_BMP"' EXIT

DD_FIXTURE_DIR="$HERE/tests/fixtures" \
SDL_VIDEODRIVER=dummy \
bash "$HERE/scripts/dev-launch.sh" --snapshot "$TMP_BMP" >/dev/null 2>&1 \
    || echo "ℹ dev-launch 返回非 0（快照拆卸阶段的 IllegalStateException 属已知噪音，见 VERIFY-ON-LINUX §7）" >&2

python3 "$HERE/scripts/bmp2png.py" "$TMP_BMP" "$OUT"
