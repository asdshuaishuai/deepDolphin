#!/usr/bin/env bash
# ci.sh — deepin 客户端本地 CI 门（DDE-INTEGRATION-PLAN.md §4.1/§4.3）。
#
# 1. --selfcheck：断言「0 failed 且 ≥58 passed」（例数只增不减）
# 2. 截图矩阵（亮/暗 × 4 页）→ docs/snapshots，落盘后人工 diff 基线
# 3. desktop / metainfo 校验：desktop-file-validate / appstream-util 缺工具显式 SKIP
#    （SKIP 不算失败——工具随 deepin 打包环境到位，硬门随之生效）
# 4. --platform-probe 正式断言：exit 0 且输出含 backend= 行
# 5. D2 grep 门：DS::*（DesignTokens）之外出现色值/px 字号即缺陷——排除
#    DesignTokens/CommitTypeComposition/src/platform/ 后命中 >4 判失败
#    （存量 4 处为 M3-3 已登记的字号项，README 决策 72；只减不增）
# 6. --agent-selftest（恒走 mock 渠道）
#
# 用法：scripts/ci.sh [build目录]（默认 build/）
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-$SRC/build}"
BIN="$BUILD/deepDolphin"

# 运行库环境提前到步骤 1 之前：selfcheck 也要加载 sysroot 的 Qt6/DTK6——原先导出
# 在步骤 2，无 sysroot rpath 的环境下步骤 1 的二进制根本起不来。用"无条件前置 +
# 保留旧值"而非 ${VAR:-默认}：预置了 LD_LIBRARY_PATH 的环境（如容器运行时自带
# /opt/... 路径）会原样沿用旧值，sysroot 永远进不去。
export LD_LIBRARY_PATH="$HOME/.local/dd-sysroot/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$HOME/.local/dd-sysroot/usr/lib/x86_64-linux-gnu/qt6/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

echo "› 1/6 selfcheck（断言 0 failed 且 ≥58 passed）"
SELFCHECK_OUT="$("$BIN" --selfcheck || true)"
printf '%s\n' "$SELFCHECK_OUT" | tail -1
SC_PASSED="$(printf '%s\n' "$SELFCHECK_OUT" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '[0-9]+' || true)"
SC_FAILED="$(printf '%s\n' "$SELFCHECK_OUT" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '[0-9]+' || true)"
if [ -z "$SC_PASSED" ] || [ -z "$SC_FAILED" ]; then
    echo "✗ selfcheck 输出无法解析（期待尾行 selfcheck: N passed, M failed——崩溃/早退？）" >&2
    exit 1
fi
if [ "$SC_FAILED" -ne 0 ] || [ "$SC_PASSED" -lt 58 ]; then
    echo "✗ selfcheck 未达标：${SC_PASSED} passed / ${SC_FAILED} failed（要求 0 failed 且 ≥58 passed）" >&2
    exit 1
fi
echo "✓ selfcheck ${SC_PASSED} passed, ${SC_FAILED} failed"

echo "› 2/6 截图矩阵（离屏）"
mkdir -p "$SRC/docs/snapshots"
for theme in light dark; do
    for sec in dashboard board milestones; do
        DEEPDOLPHIN_THEME="$theme" "$BIN" --snapshot \
            "$SRC/docs/snapshots/${theme}-${sec}.png" --section "$sec" \
            | tail -1
    done
done

echo "› 3/6 desktop / metainfo 校验（缺工具显式 SKIP）"
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$SRC/data/cn.deepdolphin.app.desktop" && echo "✓ desktop 合法"
else
    echo "SKIP: desktop-file-validate 未安装（装 desktop-file-validate 包后此门生效）"
fi
if command -v appstream-util >/dev/null 2>&1; then
    appstream-util validate-relax --nonet "$SRC/data/metainfo/cn.deepdolphin.app.metainfo.xml" \
        && echo "✓ metainfo 合法"
else
    echo "SKIP: appstream-util 未安装（README 决策 69 的硬门随工具到位生效）"
fi

echo "› 4/6 平台探针（正式断言：exit 0 且输出含 backend=）"
PROBE_RC=0
PROBE_OUT="$("$BIN" --platform-probe)" || PROBE_RC=$?
printf '%s\n' "$PROBE_OUT"
if [ "$PROBE_RC" -ne 0 ]; then
    echo "✗ platform-probe 退出码 $PROBE_RC（要求 0）" >&2
    exit 1
fi
if ! printf '%s\n' "$PROBE_OUT" | grep -q '^backend='; then
    echo "✗ platform-probe 输出缺 backend= 行" >&2
    exit 1
fi
echo "✓ 平台探针通过（backend=$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^backend=//p')，托盘/主题/字号档位见上，offscreen 下托盘无效属预期）"

echo "› 5/6 D2 grep 门（DS::* 单点真相源；排除白名单后命中 >4 判失败）"
if [ ! -d "$SRC/src" ]; then
    echo "✗ 源码目录不存在：$SRC/src（脚本位置/参数错了——门失效比门失败更糟）" >&2
    exit 1
fi
D2_HITS="$(grep -rnE '#[0-9A-Fa-f]{6}|setPixelSize|font-size: *[0-9]+px' "$SRC/src" \
    | grep -vE 'DesignTokens|CommitTypeComposition|src/platform/|app/SelfCheck.cpp' || true)"
D2_COUNT=0
[ -n "$D2_HITS" ] && D2_COUNT="$(printf '%s\n' "$D2_HITS" | grep -c . || true)"
if [ "$D2_COUNT" -gt 4 ]; then
    echo "✗ D2 命中 ${D2_COUNT} 处（上限 4，存量只减不增），命中清单：" >&2
    printf '%s\n' "$D2_HITS" >&2
    exit 1
fi
echo "✓ D2 命中 ${D2_COUNT}/4（余量仅限已登记字号项，README 决策 72）"

echo "› 6/6 agent 自测（mock 渠道）"
"$BIN" --agent-selftest | tail -2
echo "✓ CI 门通过：请 git diff docs/snapshots 人工确认视觉变化符合预期"
