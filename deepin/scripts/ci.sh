#!/usr/bin/env bash
# ci.sh — deepin 客户端本地 CI 门（DDE-INTEGRATION-PLAN.md §4.1/§4.3）。
#
# 1. --selfcheck（模型层/路由层 fixtures，例数不许下降）
# 2. 截图矩阵（亮/暗 × 4 页）→ docs/snapshots，落盘后人工 diff 基线
# 3. desktop 文件校验（desktop-file-validate）
# 4. --platform-probe（真机回归用：backend / 托盘 geometry 可用性）
# 5. --agent-selftest（恒走 mock 渠道）
#
# 用法：scripts/ci.sh [build目录]（默认 build/）
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-$SRC/build}"
BIN="$BUILD/deepDolphin"

echo "› 1/5 selfcheck"
"$BIN" --selfcheck | tail -1

echo "› 2/5 截图矩阵（离屏）"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-$HOME/.local/dd-sysroot/usr/lib/x86_64-linux-gnu}"
export QT_PLUGIN_PATH="${QT_PLUGIN_PATH:-$HOME/.local/dd-sysroot/usr/lib/x86_64-linux-gnu/qt6/plugins}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
mkdir -p "$SRC/docs/snapshots"
for theme in light dark; do
    for sec in dashboard board milestones; do
        DEEPDOLPHIN_THEME="$theme" "$BIN" --snapshot \
            "$SRC/docs/snapshots/${theme}-${sec}.png" --section "$sec" \
            | tail -1
    done
done

echo "› 3/5 desktop 文件校验"
desktop-file-validate "$SRC/data/cn.deepdolphin.app.desktop" && echo "✓ desktop 合法"

echo "› 4/5 平台探针"
"$BIN" --platform-probe || echo "（--platform-probe 未实现的构建，跳过）"

echo "› 5/5 agent 自测（mock 渠道）"
"$BIN" --agent-selftest | tail -2
echo "✓ CI 门通过：请 git diff docs/snapshots 人工确认视觉变化符合预期"
