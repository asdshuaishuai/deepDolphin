#!/usr/bin/env bash
# ci-wiring.sh — 接线源扫描门（从 ci.sh 第 9 门抽出，可单独跑）。
#
# 【为什么抽出来】这一门是**纯源扫描**：判定层与接线点必须都在，撤入口 ≠ 撤能力。
#   单独成脚本有两个用处：
#   ① 改接线时能秒级验，不用跑完整个 ci.sh（截图矩阵最慢）；
#   ② **负控**能精确打这一门（把接线摘掉 → 这一门必须红）——
#      门内嵌在 ci.sh 里时，负控得跑整条 CI 才看得到红。
#
# 用法：scripts/ci-wiring.sh [源码根目录]（默认脚本所在目录的上一级）
set -uo pipefail
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

# 剥注释再匹配：注释里出现的字样不算接线（否则加一行注释就能骗过门）。
strip_comments() {
    if command -v perl >/dev/null 2>&1; then
        perl -pe 's{//(?!:).*$}{}' "$1"
    else
        sed -e 's|//[^/].*$||' "$1"
    fi
}

echo "› 接线门：架构图 / agent 工具表 / 代码图谱+热力图 / 补丁体检 / 固定文档页 / 引擎自检+进度报告接线在（源扫描：判定层与接线点必须都在，撤入口 ≠ 撤能力）"
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

# 引擎自检（doctor）链路：判定（EngineDoctor 纯函数）→ 取数（引擎 doctor --json）
#   → 接线（设置·通用页「环境自检」卡）。
# ⚠ doctor **发现问题时退出码是 1**（自检必须能失败）但 stdout 仍是合法 JSON，
#   所以客户端必须**读载荷**判成败，不能按退出码。钉调用点。
arch_need "$SRC/src/logic/EngineDoctor.cpp" 'Report parse' '判定层有自检载荷解析'
arch_need "$SRC/src/logic/EngineDoctor.cpp" 'QString summary' '判定层有自检摘要'
arch_need "$SRC/src/logic/EngineDoctor.cpp" 'Tone toneOf' '判定层有自检档位映射'
arch_need "$SRC/src/app/AppModel.h" 'runDoctor' 'AppModel 暴露 runDoctor'
arch_need "$SRC/src/app/AppModel.h" 'doctorFinished' 'AppModel 有自检回执信号'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("doctor"\)' 'AppModel 调引擎 doctor'
arch_need "$SRC/src/app/AppModel.cpp" 'EngineDoctor::parse\(res\.payload->object\(\)\)' '自检读**载荷**判成败（不是按退出码）'
arch_need "$SRC/src/app/AppModel.cpp" 'm_doctor = r' '自检结果落到 AppModel 成员'
# 接线：设置·通用页的「运行自检」钮 —— 盯**构造点**与**调用点**，不是「doctor 这个词出现过」。
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'new DPushButton\(QStringLiteral\("运行自检"\)' '设置页真的造了「运行自检」按钮'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'm_model->runDoctor\(\)' '「运行自检」真的调了引擎自检'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" '&AppModel::doctorFinished' '设置页接了自检回执'
arch_need "$SRC/src/ui/dialogs/AiSettingsDialog.cpp" 'new GeneralPane\(model,' '设置窗把模型传给了通用页'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'new AiSettingsDialog\(m_model,' '面板把模型传给了设置窗'
arch_need "$SRC/src/app/SelfCheck.cpp" 'EngineDoctor::parse' 'SelfCheck 覆盖自检解析'

# 进度报告（report）链路：取数（引擎 report，回执型命令）→ 回执路径提取
#   → 接线（详情页「导出报告」入口 + 报告卡）。
arch_need "$SRC/src/app/AppModel.h" 'exportReport' 'AppModel 暴露 exportReport'
arch_need "$SRC/src/app/AppModel.h" 'reportExported' 'AppModel 有报告回执信号'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("report"\)' 'AppModel 调引擎 report'
arch_need "$SRC/src/app/AppModel.cpp" 'callText\(\{ *QStringLiteral\("report"\)' 'report 走 Text 契约（callText，不是 callJson）'
# ⚠ 回执通道：引擎的 report 把回执写在 **stderr**（arch gen / render arch 才在 stdout）。
#   只认 stdout 的客户端会把「报告已生成」判成「引擎没有回执」—— 成功说成失败。
arch_need "$SRC/src/app/EngineCli.h" 'receiptText' 'EngineCli 有回执通道（stdout 优先，空则 stderr）'
arch_need "$SRC/src/app/EngineCli.cpp" 'r\.receipt = EngineCli::receiptText' '回执走 receiptText（两路兜底）'
arch_need "$SRC/src/app/AppModel.cpp" 'res\.receipt' 'Text 消费点读 receipt（不是 stdOut）'
# 引擎回执带 ANSI 颜色码（引擎不认 NO_COLOR）→ 显示前必须剥。
arch_need "$SRC/src/logic/ArchReceipt.cpp" 'QString plain' '判定层有剥 ANSI 的回执净化'
arch_need "$SRC/src/app/SelfCheck.cpp" 'EngineDoctor::checkLine' 'SelfCheck 覆盖自检行文'
arch_need "$SRC/src/app/SelfCheck.cpp" 'EngineCli::receiptText' 'SelfCheck 覆盖回执通道'
# 接线：详情页的「导出报告」入口 → 面板 → 引擎。盯构造点与调用点。
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'reportExportRequested' '详情页发 reportExportRequested'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'QStringLiteral\("导出报告"\)' '详情页真的造了「导出报告」入口'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'ArchReceipt::filePath' '报告卡经判定层抽落盘路径'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'ArchReceipt::plain' '报告卡剥 ANSI 后再显示'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&ProjectDetailPage::reportExportRequested' 'PanelWindow 接了导出报告入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'm_model->exportReport' 'PanelWindow 真的调了引擎 report'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&AppModel::reportExported' 'PanelWindow 接了报告回执'
# 无头 flag：契约门第 18 组拿真载荷/真回执喂客户端，逐条对判定结果。
arch_need "$SRC/src/main.cpp" '--doctor-parse' '无头 flag 能把 doctor 载荷判成档（契约门用）'
arch_need "$SRC/src/main.cpp" '--receipt-file-path' '无头 flag 能从回执抽落盘路径（契约门用）'

# 新文件必须进了构建（漏登记 = 代码在仓里但没编进去）
for f in src/logic/ArchViewport.cpp src/logic/ArchReceipt.cpp src/logic/AgentToolPlan.cpp \
         src/logic/CodeGraphBuild.cpp src/ui/ArchCanvasWidget.cpp \
         src/ui/dialogs/ArchDialog.cpp src/ui/dialogs/CodeGraphDialog.cpp \
         src/logic/HeatLayout.cpp src/ui/HeatmapWidget.cpp \
         src/logic/PatchCheck.cpp src/ui/dialogs/PatchCheckDialog.cpp \
         src/logic/DocPages.cpp src/ui/dialogs/DocsDialog.cpp \
         src/logic/SyntaxHighlight.cpp src/ui/CodeHighlighter.cpp \
         src/logic/GraphInsight.cpp src/logic/EngineDoctor.cpp; do
    # ⚠ 必须**整词**匹配：`grep -qF "$f"` 是子串匹配，把登记项改成
    #   `src/logic/EngineDoctor.cpp.disabled` 照样命中 —— 门绿着，文件却没编进去。
    #   负控实测过这一条（假阴性）。故用「前后是行首/行尾或空白」的精确匹配。
    if ! grep -qE "(^|[[:space:]])$f([[:space:]]|$)" "$SRC/CMakeLists.txt"; then
        echo "  ✗ 构建未登记：$f" >&2
        ARCH_FAIL=1
    fi
done
if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：取数/判定/渲染/接线任一段被摘掉" >&2
    exit 1
fi
echo "✓ 接线完整（取数 → 判定 → 渲染 → 接线，${ARCH_N} 项）"
