#!/usr/bin/env bash
# ci.sh — deepin 客户端本地 CI 门（DDE-INTEGRATION-PLAN.md §4.1/§4.3）。
#
# 1. --selfcheck：断言「0 failed 且 ≥58 passed」（例数只增不减）
# 2. 截图矩阵（亮/暗 × 4 页）→ docs/snapshots，落盘后人工 diff 基线
# 3. desktop / metainfo 校验：desktop-file-validate / appstream-util 缺工具显式 SKIP
#    （SKIP 不算失败——工具随 deepin 打包环境到位，硬门随之生效）
# 4. --platform-probe 正式断言：exit 0 且输出含 backend= 行
# 5. D2 grep 门：DS::*（DesignTokens）之外出现色值/px 字号即缺陷 —— 独立成
#    scripts/ci-d2.sh（可单独跑，负控能精确打）。批 N 已把 M3-3 登记的 4 处存量
#    全收进 token，上限降到 0（只减不增）
# 6. --agent-selftest（恒走 mock 渠道）
# 7. verify 接线源扫描门：引擎 verify 的判定层与接线点必须都在（判定不许藏回视图）
# 8. 图谱 Canvas 契约门：Canvas2D 覆盖契约清单 24 个方法 + logic/models 零 QWidget 头
#  9. 架构图接线门：取数（graph arch --format scene）→ 判定（视口/命中/回执）→
#     渲染（SceneRender）→ 接线（详情页入口 → 面板 → 架构图窗 → 画布）四段都在；
#     生成/导出必须走 Text 契约（回执型命令，stdout 是人话不是 JSON）
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

echo "› 1/10 selfcheck（断言 0 failed 且 ≥58 passed）"
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

echo "› 2/10 截图矩阵（离屏）"
# ⚠ 这一步**强制** offscreen，不继承环境里的 QT_QPA_PLATFORM。
#   理由（决策 86）：基线是离屏拍的；若宿主已设 QT_QPA_PLATFORM=dxcb;xcb，
#   快照会带 DTK 原生窗口装饰与 chameleon 样式 —— 同一份代码拍出另一张脸，
#   视觉 diff 门被环境牵着走。离屏才是「同机位」的可复现前提。
#   注意：第 4 步的平台探针**要**真实 backend，故那里不强制 offscreen。
mkdir -p "$SRC/docs/snapshots"
for theme in light dark; do
    for sec in dashboard board milestones; do
        QT_QPA_PLATFORM=offscreen DEEPDOLPHIN_THEME="$theme" "$BIN" --snapshot \
            "$SRC/docs/snapshots/${theme}-${sec}.png" --section "$sec" \
            | tail -1
    done
    # 状态色样张（批 R）：**面板快照拍的是空态**（本机引擎注册项目数 0，
    # 快照里只有「仪表盘还没有数据」）—— 状态点一个都没画进去。
    # ⇒ 面板快照对状态色是**空门**：改色它不红，说「视觉已评审」是假的。
    #   这张色卡把**每一档**都画出来，改色 ⇒ 色卡 diff 红。
    QT_QPA_PLATFORM=offscreen DEEPDOLPHIN_THEME="$theme" "$BIN" --color-sample \
        "$SRC/docs/snapshots/${theme}-colors.png" | tail -1
done

echo "› 3/10 desktop / metainfo 校验（缺工具显式 SKIP）"
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

echo "› 4/10 平台探针（正式断言：exit 0 且输出含 backend=）"
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

strip_comments() {
    if command -v perl >/dev/null 2>&1; then
        perl -pe 's{//(?!:).*$}{}' "$1"
    else
        sed -e 's|//[^/].*$||' "$1"
    fi
}

echo "› 5/10 D2 grep 门（DS::* 单点真相源；散值上限 0，存量已清零）"
# 散值门独立成 scripts/ci-d2.sh：可单独跑，负控也能精确打它。
if ! sh "$SRC/scripts/ci-d2.sh" "$SRC"; then
    echo "✗ 设计系统散值门失败：src/ 下出现色值/硬编码 px 字号" >&2
    exit 1
fi

echo "› 6/10 agent 自测（mock 渠道）"
"$BIN" --agent-selftest | tail -2

echo "› 7/10 verify 接线在（源扫描：判定不许藏回视图，撤入口 ≠ 撤能力）"
# 剥注释再匹配：注释里出现的字样不算接线（否则加一行注释就能骗过门）。
WIRING_HITS=0
WIRING_FAIL=0
wire_need() { # wire_need <文件> <正则> <说明>
    local f="$1" re="$2" label="$3"
    if [ ! -f "$f" ]; then
        echo "  ✗ $label：文件不存在 $f" >&2
        WIRING_FAIL=1
        return
    fi
    # ⚠ 不用 `grep -q`：它一匹配就退出，剥注释的 perl 会收 SIGPIPE，
    #   配 set -o pipefail 整个管道判失败（接线明明在却报 ✗ —— 门自己坏了比门放水更糟）。
    if strip_comments "$f" | grep -E -- "$re" >/dev/null; then
        echo "  ✓ $label"
        WIRING_HITS=$((WIRING_HITS + 1))
    else
        echo "  ✗ $label：$f 里找不到 $re" >&2
        WIRING_FAIL=1
    fi
}
wire_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("verify"\)' 'AppModel 调引擎 verify 命令'
wire_need "$SRC/src/app/AppModel.h" 'loadVerify' 'AppModel 暴露 loadVerify'
wire_need "$SRC/src/ui/PanelWindow.cpp" '&AppModel::verifyChanged' 'PanelWindow 消费 verifyChanged 信号'
wire_need "$SRC/src/ui/PanelWindow.cpp" 'loadVerify\(' 'PanelWindow 进详情时发起校验'
wire_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'addWidget\(buildIntegrityCard\(\)\)' '详情页挂了文档完整性卡'
wire_need "$SRC/src/app/SelfCheck.cpp" 'DocumentIntegrity::stateOf' 'SelfCheck 覆盖四态判定'
if [ "$WIRING_FAIL" -ne 0 ]; then
    echo "✗ verify 接线门失败：判定层或接线被摘掉（撤入口 ≠ 撤能力）" >&2
    exit 1
fi
echo "✓ verify 接线完整（$WIRING_HITS 项）"

echo "› 8/10 图谱 Canvas 契约清单齐（章程 §3.5：方法清单就是移植验收清单）"
# 契约清单（引擎 docs/graph-scene-schema.md 的渲染契约层）：26 个标准 Canvas2D 方法。
# 「少实现一项，渲染器就跑不完」——本门逐个核 Canvas2D 是否声明为 override。
CANVAS_METHODS="setTransform fillRect strokeRect rect beginPath moveTo lineTo arcTo closePath arc bezierCurveTo fill stroke fillText createLinearGradient addColorStop setLineDash setLineDashOffset setShadowBlur setShadowColor setGlobalAlpha setLineWidth setStrokeStyle setFillStyle setFont setTextAlign"
CANVAS_FAIL=0
CANVAS_N=0
for m in $CANVAS_METHODS; do
    CANVAS_N=$((CANVAS_N + 1))
    # 匹配「<空白或指针星号>方法名( … override」—— 返回类型随方法而变
    # （void / QLinearGradient *），方法名前可能是空格也可能是紧贴的 '*'。
    if ! grep -qE "[[:space:]\*]$m\(.*override" "$SRC/src/platform/Canvas2D.h"; then
        echo "  ✗ Canvas2D 缺契约方法：$m" >&2
        CANVAS_FAIL=1
    fi
done
# 判定层（logic/）零 QWidget 头 —— 分层纪律不能因为新加了图谱层而破。
GW_HITS="$(grep -rlE '#include[[:space:]]*<[Qq]Widget|#include[[:space:]]*<[A-Za-z]*Widget' \
    "$SRC/src/logic" "$SRC/src/models" 2>/dev/null || true)"
if [ -n "$GW_HITS" ]; then
    echo "✗ logic/ 或 models/ 出现了 QWidget 头（分层纪律）：" >&2
    printf '%s\n' "$GW_HITS" >&2
    CANVAS_FAIL=1
fi
# 新文件必须进了构建（漏登记 = 代码在仓里但没编进去）
# ⚠ 必须**整词**匹配：`grep -qF "$f"` 是子串匹配，把登记项改成
#   `src/logic/GraphToken.cpp.disabled` 照样命中 —— 门绿着，文件却没编进去。
for f in src/logic/GraphToken.cpp src/logic/SceneRender.cpp src/models/GraphScene.cpp src/platform/Canvas2D.cpp; do
    if ! grep -qE "(^|[[:space:]])$f([[:space:]]|$)" "$SRC/CMakeLists.txt"; then
        echo "  ✗ 构建未登记：$f" >&2
        CANVAS_FAIL=1
    fi
done
if [ "$CANVAS_FAIL" -ne 0 ]; then
    echo "✗ 图谱 Canvas 契约门失败" >&2
    exit 1
fi
echo "✓ Canvas2D 覆盖契约清单 ${CANVAS_N}/26 个方法；logic/ 与 models/ 零 QWidget 头；新文件均已登记构建"

echo "› 9/10 接线门（源扫描：判定层与接线点必须都在，撤入口 ≠ 撤能力）"
# 接线门独立成 scripts/ci-wiring.sh：可单独跑，负控也能精确打它。
if sh "$SRC/scripts/ci-wiring.sh" "$SRC"; then
    :
else
    echo "✗ 接线门失败：取数/判定/渲染/接线任一段被摘掉" >&2
    exit 1
fi

echo "› 10/10 引擎契约门（真引擎沙箱；引擎缺席显式 SKIP 且不算通过）"
# contract-check.sh 之前是**游离脚本** —— CI 从来没跑过它，契约漂移不会被拦。
# 接进 CI 后：引擎在 → 真跑（32 条）；引擎不在 → 脚本自己 SKIP 并如实说明
# 「本组未验证」（不是静默通过）。
if [ -n "${DEEPGIT_BIN:-}" ] || command -v moongit >/dev/null || command -v deepgit >/dev/null; then
    # ⚠ 别写成 `if cmd | tail -3` —— 那样 if 判的是 tail 的退出码（永远 0），
    #   契约挂了门也是绿的。必须拿脚本自己的退出码。
    _cc_log="$BUILD/contract-check.log"
    if DEEPGIT_CLIENT_BIN="$BIN" sh "$SRC/scripts/contract-check.sh" > "$_cc_log" 2>&1; then
        tail -3 "$_cc_log"
        echo "✓ 引擎契约门通过"
    else
        tail -20 "$_cc_log" >&2
        echo "✗ 引擎契约门失败" >&2
        exit 1
    fi
else
    echo "‣ SKIP 引擎契约门：未找到 moongit/deepgit（可设 DEEPGIT_BIN 指定）"
    echo "‣ 本组**未验证**，不算通过"
fi

echo "✓ CI 门通过：请 git diff docs/snapshots 人工确认视觉变化符合预期"
