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

echo "› 1/9 selfcheck（断言 0 failed 且 ≥58 passed）"
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

echo "› 2/9 截图矩阵（离屏）"
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

echo "› 3/9 desktop / metainfo 校验（缺工具显式 SKIP）"
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

echo "› 4/9 平台探针（正式断言：exit 0 且输出含 backend=）"
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

echo "› 5/9 D2 grep 门（DS::* 单点真相源；排除白名单后命中 >4 判失败）"
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

echo "› 6/9 agent 自测（mock 渠道）"
"$BIN" --agent-selftest | tail -2

echo "› 7/9 verify 接线在（源扫描：判定不许藏回视图，撤入口 ≠ 撤能力）"
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
    if strip_comments "$f" | grep -E "$re" >/dev/null; then
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

echo "› 8/9 图谱 Canvas 契约清单齐（章程 §3.5：方法清单就是移植验收清单）"
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

echo "› 9/9 架构图接线在（源扫描：判定层与接线点必须都在，撤入口 ≠ 撤能力）"
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
    if strip_comments "$f" | grep -E "$re" >/dev/null; then
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
# 新文件必须进了构建（漏登记 = 代码在仓里但没编进去）
for f in src/logic/ArchViewport.cpp src/logic/ArchReceipt.cpp \
         src/ui/ArchCanvasWidget.cpp src/ui/dialogs/ArchDialog.cpp; do
    if ! grep -qF "$f" "$SRC/CMakeLists.txt"; then
        echo "  ✗ 构建未登记：$f" >&2
        ARCH_FAIL=1
    fi
done
if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 架构图接线门失败：取数/判定/渲染/接线任一段被摘掉" >&2
    exit 1
fi
echo "✓ 架构图链路完整（取数 → 判定 → 渲染 → 接线，${ARCH_N} 项）"

echo "✓ CI 门通过：请 git diff docs/snapshots 人工确认视觉变化符合预期"
