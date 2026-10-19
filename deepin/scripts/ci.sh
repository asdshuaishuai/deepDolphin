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

echo "› 5/10 D2 grep 门（DS::* 单点真相源；排除白名单后命中 >4 判失败）"
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

echo "› 6/10 agent 自测（mock 渠道）"
"$BIN" --agent-selftest | tail -2

echo "› 7/10 verify 接线在（源扫描：判定不许藏回视图，撤入口 ≠ 撤能力）"
# 剥注释再匹配：注释里出现的字样不算接线（否则加一行注释就能骗过门）。
strip_comments() {
    if command -v perl >/dev/null 2>&1; then
        perl -pe 's{//(?!:).*$}{}' "$1"
    else
        sed -e 's|//[^/].*$||' "$1"
    fi
}
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
for f in src/logic/GraphToken.cpp src/logic/SceneRender.cpp src/models/GraphScene.cpp src/platform/Canvas2D.cpp; do
    if ! grep -qF "$f" "$SRC/CMakeLists.txt"; then
        echo "  ✗ 构建未登记：$f" >&2
        CANVAS_FAIL=1
    fi
done
if [ "$CANVAS_FAIL" -ne 0 ]; then
    echo "✗ 图谱 Canvas 契约门失败" >&2
    exit 1
fi
echo "✓ Canvas2D 覆盖契约清单 ${CANVAS_N}/26 个方法；logic/ 与 models/ 零 QWidget 头；新文件均已登记构建"

echo "› 9/10 架构图 / agent 工具表 / 代码图谱+热力图 / 补丁体检 / 固定文档页接线在（源扫描：判定层与接线点必须都在，撤入口 ≠ 撤能力）"
# 架构图链路分四段，任一段被摘掉都必须红：
#   引擎取数（AppModel 调 graph arch --format scene）
#   → 判定层（ArchViewport 视口/命中、ArchReceipt 回执提取）
#   → 渲染层（SceneRender + Canvas2D）
#   → 接线层（详情页入口 → PanelWindow → ArchDialog → 画布）
ARCH_FAIL=0
ARCH_N=0
arch_need() { # arch_need <文件> <正则> <说明>
    local f="$1" re="$2" label="$3"
    ARCH_N=$((ARCH_N + 1))
    if [ ! -f "$f" ]; then
        echo "  ✗ $label：文件不存在 $f" >&2
        ARCH_FAIL=1
        return
    fi
    if strip_comments "$f" | grep -E -- "$re" >/dev/null; then
        echo "  ✓ $label"
    else
        echo "  ✗ $label：$f 里找不到 $re" >&2
        ARCH_FAIL=1
    fi
}
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("graph"\).*QStringLiteral\("arch"\)' 'AppModel 调引擎 graph arch 取场景'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("scene"\)' '场景按 scene 契约格式取（--format scene）'
arch_need "$SRC/src/app/AppModel.h" 'loadScene' 'AppModel 暴露 loadScene'
arch_need "$SRC/src/app/AppModel.h" 'genArch' 'AppModel 暴露 genArch（生成）'
arch_need "$SRC/src/app/AppModel.h" 'exportArch' 'AppModel 暴露 exportArch（导出）'
# 生成/导出是**回执型命令**：stdout 是人话不是 JSON → 必须走 Text 契约。
# 拿 callJson 去收，exit==0 也会被判成「引擎输出不是合法 JSON」——成功报成失败。
arch_need "$SRC/src/app/AppModel.cpp" 'callText\(\{ *QStringLiteral\("arch"\), *QStringLiteral\("gen"\)' 'genArch 走 Text 契约（callText）'
arch_need "$SRC/src/app/AppModel.cpp" 'callText\(\{ *QStringLiteral\("render"\), *QStringLiteral\("arch"\)' 'exportArch 走 Text 契约（callText）'
arch_need "$SRC/src/app/EngineCli.h" 'callText' 'EngineCli 提供文本输出通道'
arch_need "$SRC/src/logic/ArchViewport.cpp" 'hitAt' '判定层有命中测试'
arch_need "$SRC/src/logic/ArchReceipt.cpp" 'htmlPath' '判定层有回执路径提取'
arch_need "$SRC/src/ui/ArchCanvasWidget.cpp" 'SceneRender::render' '画布经 SceneRender 渲染'
arch_need "$SRC/src/ui/ArchCanvasWidget.cpp" 'ArchViewport::hitAt' '画布经 ArchViewport 命中'
arch_need "$SRC/src/ui/dialogs/ArchDialog.cpp" 'ArchCanvasWidget' '架构图窗挂了画布'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'archRequested' '详情页发 archRequested'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&ProjectDetailPage::archRequested' 'PanelWindow 接了详情页入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'showArch' 'PanelWindow 有开窗动作'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'ArchDialog' 'PanelWindow 用的是架构图窗'
# 回执按项目路由：两个项目的架构图窗可以同时开着，回执不带项目名就会串台
#（在错误的窗口里显示回执、甚至触发重载）。
arch_need "$SRC/src/app/AppModel.h" 'archActionFinished\(bool ok, const QString &project' '回执信号带项目名'
arch_need "$SRC/src/ui/dialogs/ArchDialog.cpp" 'project != m_project' '架构图窗按项目过滤回执'

# agent 工具表接线：执行走纯函数表；清单能被无头 flag 打印出来（契约第 12 组靠它对位）
arch_need "$SRC/src/ai/AgentCore.cpp" 'AgentToolPlan::planFor' 'AgentCore 经工具表执行'
arch_need "$SRC/src/logic/AgentToolPlan.cpp" 'knownToolNames' '工具表有权威清单出口'
arch_need "$SRC/src/main.cpp" '--agent-tool-names' '客户端能无头打印工具清单（契约对位用）'

# 代码图谱链路：取数（三源）→ 判定（合成 + 可见行）→ 接线（详情页入口 → 面板 → 窗）
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("graph"\), *QStringLiteral\("tree"\)' 'AppModel 调引擎 graph tree 取文件骨架'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("graph"\), *QStringLiteral\("confidence"\)' 'AppModel 调引擎 graph confidence 取置信度'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("graph"\), *QStringLiteral\("functions"\)' 'AppModel 调引擎 graph functions 取函数级图谱'
arch_need "$SRC/src/app/AppModel.h" 'loadCodeGraph' 'AppModel 暴露 loadCodeGraph'
arch_need "$SRC/src/app/AppModel.h" 'genIndex' 'AppModel 暴露 genIndex（生成）'
arch_need "$SRC/src/app/AppModel.h" 'exportIndex' 'AppModel 暴露 exportIndex（导出）'
arch_need "$SRC/src/logic/CodeGraphBuild.cpp" 'symbolId' '判定层有符号 id 构造式（与引擎同形）'
arch_need "$SRC/src/logic/CodeGraphBuild.cpp" 'visibleRows' '判定层有可见行算法（搜索 + 展开态）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'CodeGraphBuild::visibleRows' '代码图谱窗的可见性以判定层为准'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'ArchCanvasWidget|CodeGraphBuild' '代码图谱窗用代码图谱数据层'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'codeGraphRequested' '详情页发 codeGraphRequested'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&ProjectDetailPage::codeGraphRequested' 'PanelWindow 接了代码图谱入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'showCodeGraph' 'PanelWindow 有开代码图谱窗的动作'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'CodeGraphDialog' 'PanelWindow 用的是代码图谱窗'

# 热力图链路：判定（作用域切分 / 铺排 / 走线）→ 渲染（HeatmapWidget + Canvas2D）
#   → 接线（左栏模式切换 + 堆叠页 + 下钻 + 点选）。
# ⚠ 热力图是**左栏的另一种模式**，不是第三栏 —— 形状钉在左栏的堆叠页上。
arch_need "$SRC/src/logic/HeatLayout.cpp" 'scopeCards' '判定层有作用域切分（文件层 / 下钻层）'
arch_need "$SRC/src/logic/HeatLayout.cpp" 'layout' '判定层有卡片铺排'
arch_need "$SRC/src/logic/HeatLayout.cpp" 'routes' '判定层有边走线'
arch_need "$SRC/src/ui/HeatmapWidget.cpp" 'HeatLayout::layout' '画布经 HeatLayout 铺排'
arch_need "$SRC/src/ui/HeatmapWidget.cpp" 'HeatLayout::routes' '画布经 HeatLayout 走线'
arch_need "$SRC/src/ui/HeatmapWidget.cpp" 'Canvas2D' '画布走 D1 的 Canvas2D 内核（不自己造图形栈）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'HeatmapWidget' '代码图谱窗挂了热力图'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '&HeatmapWidget::nodeSelected' '热力图点选信号接上了（→ 右栏详情）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '&HeatmapWidget::drillChanged' '热力图下钻信号接上了（面包屑跟着走）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_leftStack' '左栏是模式切换 + 堆叠页（热力图是左栏的另一种模式）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_heat->setData' '热力图数据源接上了（与树同源）'
arch_need "$SRC/src/app/SelfCheck.cpp" 'HeatLayout::layout' 'SelfCheck 覆盖铺排'
arch_need "$SRC/src/app/SelfCheck.cpp" 'HeatLayout::routes' 'SelfCheck 覆盖走线'

# 补丁体检链路：判定（PatchCheck 纯函数）→ 取数（工作区 diff + 引擎 patchconf）
#   → 接线（详情页入口 → 独立窗 → 人工裁决 → 合并终稿）
arch_need "$SRC/src/logic/PatchCheck.cpp" 'parseLayer1' '判定层有 Layer1 解析'
arch_need "$SRC/src/logic/PatchCheck.cpp" 'parseMerged' '判定层有终稿解析'
arch_need "$SRC/src/logic/PatchCheck.cpp" 'lowConfidenceEntities' '判定层有低置信度筛选'
arch_need "$SRC/src/logic/PatchCheck.cpp" 'agentPayload' '判定层有裁决载荷生成'
arch_need "$SRC/src/logic/PatchCheck.cpp" 'diffSnippet' '判定层有 diff 抽实码'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("patchconf"\)' 'AppModel 调引擎 patchconf'
arch_need "$SRC/src/app/AppModel.cpp" 'workingDiff' 'AppModel 取工作区 diff'
arch_need "$SRC/src/app/AppModel.cpp" 'mergePatchCheck' 'AppModel 有合并终稿动作'
arch_need "$SRC/src/ui/dialogs/PatchCheckDialog.cpp" 'PatchCheck::lowConfidenceEntities' '窗经判定层取低置信度实体'
arch_need "$SRC/src/ui/dialogs/PatchCheckDialog.cpp" 'PatchCheck::agentPayload' '窗经判定层生成裁决载荷'
arch_need "$SRC/src/ui/dialogs/PatchCheckDialog.cpp" 'PatchCheck::diffSnippet' '窗经判定层抽实码'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'patchCheckRequested' '详情页发 patchCheckRequested'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&ProjectDetailPage::patchCheckRequested' 'PanelWindow 接了补丁体检入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'showPatchCheck' 'PanelWindow 有开补丁体检窗的动作'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'PatchCheckDialog' 'PanelWindow 用的是补丁体检窗'
arch_need "$SRC/src/app/SelfCheck.cpp" 'PatchCheck::parseLayer1' 'SelfCheck 覆盖 Layer1 解析'
arch_need "$SRC/src/app/SelfCheck.cpp" 'PatchCheck::diffSnippet' 'SelfCheck 覆盖 diff 抽实码'

# 固定文档页链路：内容（DocPages 纯函数，四类目写死在代码里）→ 渲染（DocsDialog，
#   markdown）→ 接线（面板菜单「关于 / 帮助」）。文档不进引擎 —— 它不是数据。
arch_need "$SRC/src/logic/DocPages.cpp" 'kindKey' '判定层有类目标识'
arch_need "$SRC/src/logic/DocPages.cpp" 'content' '判定层有文档正文'
arch_need "$SRC/src/logic/DocPages.cpp" 'clientRepo' '仓库地址有单一出处'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocPages::content' '窗经判定层取正文'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'setMarkdown' '正文按 markdown 渲染'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'showDocs' 'PanelWindow 有开文档窗的动作'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'DocsDialog' 'PanelWindow 用的是文档窗'
# 入口级检查：光有 showDocs 方法不算数 —— 菜单里没人调它，用户就永远打不开
# （负控实测：只删菜单两行、留着方法，上面两条照样全绿）。
arch_need "$SRC/src/ui/PanelWindow.cpp" 'addAction\(QStringLiteral\("关于 deepDolphin"\)\)' '面板菜单有「关于」入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'addAction\(QStringLiteral\("帮助"\)\)' '面板菜单有「帮助」入口'
arch_need "$SRC/src/app/SelfCheck.cpp" 'DocPages::content' 'SelfCheck 覆盖文档正文'

# 语法高亮链路：判定（SyntaxHighlight 纯函数，九语言与引擎 detectLang 对齐）→
#   涂色（CodeHighlighter，颜色取自 DS 令牌）→ 接线（代码图谱页源码页签）
arch_need "$SRC/src/logic/SyntaxHighlight.cpp" 'languages' '判定层有语言清单'
arch_need "$SRC/src/logic/SyntaxHighlight.cpp" 'keywords' '判定层有关键词表'
arch_need "$SRC/src/logic/SyntaxHighlight.cpp" 'highlight' '判定层有逐行分类'
arch_need "$SRC/src/ui/CodeHighlighter.cpp" 'SyntaxHighlight::highlight' '涂色层经判定层分类'
arch_need "$SRC/src/ui/CodeHighlighter.cpp" 'DS::semColor' '颜色取自 DS 令牌（不是契约色）'
# ⚠ 盯**构造点**（`new CodeHighlighter`）而不是「CodeHighlighter 这个词出现过」——
#   负控实测：只删掉构造那一行、留着 include 与另一个调用点时，后者照样全绿
#   （用户看到的源码页签还是一片纯色）。这已是第三回「门盯名字不盯接线点」。
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'new CodeHighlighter' '代码图谱源码页签真的 new 了一个高亮器'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_highlighter->setLanguage' '高亮语言跟着选中项走'
arch_need "$SRC/src/main.cpp" 'syntax-languages' '无头 flag 暴露语言清单（契约门第 16 组用）'
arch_need "$SRC/src/app/SelfCheck.cpp" 'SyntaxHighlight::highlight' 'SelfCheck 覆盖高亮分类'

# 图谱三件套链路：判定（GraphInsight：id→名字 / overview / symbol / impact）→
#   取数（引擎 graph overview / symbol / impact）→ 接线（代码图谱页关系页签 + 页头概览）
# ⚠ 引擎的 symbol / impact **只认符号名**：传 id 它返回空结果，看着像「没有影响面」。
arch_need "$SRC/src/logic/GraphInsight.cpp" 'symbolNameFromId' '判定层有「id 取名字」（引擎只认名字）'
arch_need "$SRC/src/logic/GraphInsight.cpp" 'parseOverview' '判定层有概览解析'
arch_need "$SRC/src/logic/GraphInsight.cpp" 'parseSymbol' '判定层有符号详情解析'
arch_need "$SRC/src/logic/GraphInsight.cpp" 'parseImpact' '判定层有影响面解析'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("overview"\)' 'AppModel 调引擎 graph overview'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("impact"\)' 'AppModel 调引擎 graph impact'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("symbol"\)' 'AppModel 调引擎 graph symbol'
# ⚠ 盯**调用点**而不是方法名：方法定义还在时 grep 照样命中（这是第四次同类漏洞）。
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '^[[:space:]]*showImpact\(\);[[:space:]]*$' '关系页签真的调用了影响面（不是只定义了方法）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'GraphInsight::symbolNameFromId' '界面按名字问引擎（不传 id）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'loadOverview' '页头接了项目级概览'
arch_need "$SRC/src/app/SelfCheck.cpp" 'GraphInsight::symbolNameFromId' 'SelfCheck 覆盖 id→名字'
# 新文件必须进了构建（漏登记 = 代码在仓里但没编进去）
for f in src/logic/ArchViewport.cpp src/logic/ArchReceipt.cpp src/logic/AgentToolPlan.cpp \
         src/logic/CodeGraphBuild.cpp src/ui/ArchCanvasWidget.cpp \
         src/ui/dialogs/ArchDialog.cpp src/ui/dialogs/CodeGraphDialog.cpp \
         src/logic/HeatLayout.cpp src/ui/HeatmapWidget.cpp \
         src/logic/PatchCheck.cpp src/ui/dialogs/PatchCheckDialog.cpp \
         src/logic/DocPages.cpp src/ui/dialogs/DocsDialog.cpp \
         src/logic/SyntaxHighlight.cpp src/ui/CodeHighlighter.cpp \
         src/logic/GraphInsight.cpp; do
    if ! grep -qF "$f" "$SRC/CMakeLists.txt"; then
        echo "  ✗ 构建未登记：$f" >&2
        ARCH_FAIL=1
    fi
done
if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：取数/判定/渲染/接线任一段被摘掉" >&2
    exit 1
fi
echo "✓ 架构图 + agent 工具表 + 代码图谱/热力图 + 补丁体检 + 固定文档页接线完整（取数 → 判定 → 渲染 → 接线，${ARCH_N} 项）"

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
