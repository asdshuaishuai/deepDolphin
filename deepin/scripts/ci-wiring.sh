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
# ⚠ **按文件类型分派**：C++ 源文件是 `//`，shell 脚本是 `#`。
#   以前只有 C++ 版 → 扫 ci.sh 时**整份脚本的 `#` 注释都留着**，
#   于是「注释里提过 ci-d2.sh」被当成「ci.sh 调了 ci-d2.sh」→ 门被骗过（负控实测）。
strip_comments() {
    case "$1" in
    *.sh|*.txt)
        # shell 注释：行首（可含空白）的 # 到行尾。shell 脚本里没有 #include，
        # 所以整段剥掉是安全的。
        # ⚠ `.txt` 也要走这一支（批 S 实测）：依赖清单 `deb-deps.txt` 用 `#` 写注释，
        #   若按默认分支只剥 `//`，**注释里提到的包名会顶替真条目** ——
        #   门项「清单里有 dde-qt6integration」在清单真条目被删后照样绿（负控实测，
        #   「子串/注释互相顶替」的又一形态）。
        sed -e 's/^[[:space:]]*#.*$//' "$1" ;;
    *)
        if command -v perl >/dev/null 2>&1; then
        # ⚠ `(?<!:)` 排除 `://` —— 否则字符串里的 URL（https://…）
        #   会被当成行注释整段剥掉，门就看不见它了（负控实测）。
            perl -pe 's{(?<!:)(//)(?!:).*$}{}' "$1"
        else
            sed -e 's|//[^/].*$||' "$1"
        fi
        ;;
    esac
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
# arch_need_count：盯「**恰好出现 N 次**」。
# ⚠ 为什么需要它：arch_need 盯的是「这个 token 出现过」—— 但同名 token 在一个文件里
#   常出现多处（`SemColors::shallow()` 在 Derived.cpp 有 2 处、`FixedColors::iconFallback()`
#   在 IconLoader.cpp 有 2 处）。变异只拿掉其中一处时，arch_need 照样绿 —— **门被骗过**
#   （负控实测，第八次「同名/子串互相顶替」）。改成「必须恰好 N 次」：
#   少一处、多一处都红。
arch_need_count() { # arch_need_count <文件> <正则> <期望次数> <说明>
    local f="$1" re="$2" want="$3" label="$4"
    ARCH_N=$((ARCH_N + 1))
    if [ ! -f "$f" ]; then
        echo "  ✗ $label：文件不存在 $f" >&2
        ARCH_FAIL=1
        return
    fi
    local got
    got="$(strip_comments "$f" | grep -oE -- "$re" | grep -c . || true)"
    got="${got:-0}"
    if [ "$got" = "$want" ]; then
        echo "  ✓ $label"
    else
        echo "  ✗ $label：$f 里 $re 出现 $got 次（期望 $want 次）" >&2
        ARCH_FAIL=1
    fi
}
# arch_forbid：盯「**不该有的东西没了**」—— 收敛类改动光靠 arch_need（查「在」）
# 看不出来：把写死的色值又写回去，「它还在」这件事没有正向条目能抓。
arch_forbid() { # arch_forbid <文件> <正则> <说明>
    local f="$1" re="$2" label="$3"
    ARCH_N=$((ARCH_N + 1))
    if [ ! -f "$f" ]; then
        echo "  ✗ $label：文件不存在 $f" >&2
        ARCH_FAIL=1
        return
    fi
    if strip_comments "$f" | grep -E -- "$re" >/dev/null; then
        echo "  ✗ $label：$f 里仍有 $re（该收敛的又写回去了）" >&2
        ARCH_FAIL=1
    else
        echo "  ✓ $label"
    fi
}
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("graph"\).*QStringLiteral\("arch"\)' 'AppModel 调引擎 graph arch 取场景'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("scene"\)' '场景按 scene 契约格式取（--format scene）'
arch_need "$SRC/src/app/AppModel.h" '\bloadScene\b' 'AppModel 暴露 loadScene'
arch_need "$SRC/src/app/AppModel.h" '\bgenArch\b' 'AppModel 暴露 genArch（生成）'
arch_need "$SRC/src/app/AppModel.h" '\bexportArch\b' 'AppModel 暴露 exportArch（导出）'
# 生成/导出是**回执型命令**：stdout 是人话不是 JSON → 必须走 Text 契约。
# 拿 callJson 去收，exit==0 也会被判成「引擎输出不是合法 JSON」——成功报成失败。
arch_need "$SRC/src/app/AppModel.cpp" 'callText\(\{ *QStringLiteral\("arch"\), *QStringLiteral\("gen"\)' 'genArch 走 Text 契约（callText）'
arch_need "$SRC/src/app/AppModel.cpp" 'callText\(\{ *QStringLiteral\("render"\), *QStringLiteral\("arch"\)' 'exportArch 走 Text 契约（callText）'
arch_need "$SRC/src/app/EngineCli.h" '\bcallText\b' 'EngineCli 提供文本输出通道'
arch_need "$SRC/src/logic/ArchViewport.cpp" '\bhitAt\b' '判定层有命中测试'
arch_need "$SRC/src/logic/ArchReceipt.cpp" '\bhtmlPath\b' '判定层有回执路径提取'
arch_need "$SRC/src/ui/ArchCanvasWidget.cpp" '\bSceneRender::render\b' '画布经 SceneRender 渲染'
arch_need "$SRC/src/ui/ArchCanvasWidget.cpp" '\bArchViewport::hitAt\b' '画布经 ArchViewport 命中'
arch_need "$SRC/src/ui/dialogs/ArchDialog.cpp" '\bArchCanvasWidget\b' '架构图窗挂了画布'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" '\barchRequested\b' '详情页发 archRequested'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&ProjectDetailPage::archRequested\b' 'PanelWindow 接了详情页入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" '\bshowArch\b' 'PanelWindow 有开窗动作'
arch_need "$SRC/src/ui/PanelWindow.cpp" '\bArchDialog\b' 'PanelWindow 用的是架构图窗'
# 回执按项目路由：两个项目的架构图窗可以同时开着，回执不带项目名就会串台
#（在错误的窗口里显示回执、甚至触发重载）。
arch_need "$SRC/src/app/AppModel.h" 'archActionFinished\(bool ok, const QString &project\b' '回执信号带项目名'
arch_need "$SRC/src/ui/dialogs/ArchDialog.cpp" 'project != m_project\b' '架构图窗按项目过滤回执'

# agent 工具表接线：执行走纯函数表；清单能被无头 flag 打印出来（契约第 12 组靠它对位）
arch_need "$SRC/src/ai/AgentCore.cpp" '\bAgentToolPlan::planFor\b' 'AgentCore 经工具表执行'
arch_need "$SRC/src/logic/AgentToolPlan.cpp" '\bknownToolNames\b' '工具表有权威清单出口'
arch_need "$SRC/src/main.cpp" '--agent-tool-names\b' '客户端能无头打印工具清单（契约对位用）'

# 代码图谱链路：取数（三源）→ 判定（合成 + 可见行）→ 接线（详情页入口 → 面板 → 窗）
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("graph"\), *QStringLiteral\("tree"\)' 'AppModel 调引擎 graph tree 取文件骨架'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("graph"\), *QStringLiteral\("confidence"\)' 'AppModel 调引擎 graph confidence 取置信度'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("graph"\), *QStringLiteral\("functions"\)' 'AppModel 调引擎 graph functions 取函数级图谱'
arch_need "$SRC/src/app/AppModel.h" '\bloadCodeGraph\b' 'AppModel 暴露 loadCodeGraph'
arch_need "$SRC/src/app/AppModel.h" '\bgenIndex\b' 'AppModel 暴露 genIndex（生成）'
arch_need "$SRC/src/app/AppModel.h" '\bexportIndex\b' 'AppModel 暴露 exportIndex（导出）'
arch_need "$SRC/src/logic/CodeGraphBuild.cpp" '\bsymbolId\b' '判定层有符号 id 构造式（与引擎同形）'
arch_need "$SRC/src/logic/CodeGraphBuild.cpp" '\bvisibleRows\b' '判定层有可见行算法（搜索 + 展开态）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '\bCodeGraphBuild::visibleRows\b' '代码图谱窗的可见性以判定层为准'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'ArchCanvasWidget|CodeGraphBuild\b' '代码图谱窗用代码图谱数据层'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" '\bcodeGraphRequested\b' '详情页发 codeGraphRequested'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&ProjectDetailPage::codeGraphRequested\b' 'PanelWindow 接了代码图谱入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" '\bshowCodeGraph\b' 'PanelWindow 有开代码图谱窗的动作'
arch_need "$SRC/src/ui/PanelWindow.cpp" '\bCodeGraphDialog\b' 'PanelWindow 用的是代码图谱窗'

# 热力图链路：判定（作用域切分 / 铺排 / 走线）→ 渲染（HeatmapWidget + Canvas2D）
#   → 接线（左栏模式切换 + 堆叠页 + 下钻 + 点选）。
# ⚠ 热力图是**左栏的另一种模式**，不是第三栏 —— 形状钉在左栏的堆叠页上。
arch_need "$SRC/src/logic/HeatLayout.cpp" '\bscopeCards\b' '判定层有作用域切分（文件层 / 下钻层）'
arch_need "$SRC/src/logic/HeatLayout.cpp" '\blayout\b' '判定层有卡片铺排'
arch_need "$SRC/src/logic/HeatLayout.cpp" '\broutes\b' '判定层有边走线'
arch_need "$SRC/src/ui/HeatmapWidget.cpp" '\bHeatLayout::layout\b' '画布经 HeatLayout 铺排'
arch_need "$SRC/src/ui/HeatmapWidget.cpp" '\bHeatLayout::routes\b' '画布经 HeatLayout 走线'
arch_need "$SRC/src/ui/HeatmapWidget.cpp" '\bCanvas2D\b' '画布走 D1 的 Canvas2D 内核（不自己造图形栈）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '\bHeatmapWidget\b' '代码图谱窗挂了热力图'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '&HeatmapWidget::nodeSelected\b' '热力图点选信号接上了（→ 右栏详情）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '&HeatmapWidget::drillChanged\b' '热力图下钻信号接上了（面包屑跟着走）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '\bm_leftStack\b' '左栏是模式切换 + 堆叠页（热力图是左栏的另一种模式）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_heat->setData\b' '热力图数据源接上了（与树同源）'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bHeatLayout::layout\b' 'SelfCheck 覆盖铺排'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bHeatLayout::routes\b' 'SelfCheck 覆盖走线'

# 补丁体检链路：判定（PatchCheck 纯函数）→ 取数（工作区 diff + 引擎 patchconf）
#   → 接线（详情页入口 → 独立窗 → 人工裁决 → 合并终稿）
arch_need "$SRC/src/logic/PatchCheck.cpp" '\bparseLayer1\b' '判定层有 Layer1 解析'
arch_need "$SRC/src/logic/PatchCheck.cpp" '\bparseMerged\b' '判定层有终稿解析'
arch_need "$SRC/src/logic/PatchCheck.cpp" '\blowConfidenceEntities\b' '判定层有低置信度筛选'
arch_need "$SRC/src/logic/PatchCheck.cpp" '\bagentPayload\b' '判定层有裁决载荷生成'
arch_need "$SRC/src/logic/PatchCheck.cpp" '\bdiffSnippet\b' '判定层有 diff 抽实码'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("patchconf"\)' 'AppModel 调引擎 patchconf'
arch_need "$SRC/src/app/AppModel.cpp" '\bworkingDiff\b' 'AppModel 取工作区 diff'
arch_need "$SRC/src/app/AppModel.cpp" '\bmergePatchCheck\b' 'AppModel 有合并终稿动作'
arch_need "$SRC/src/ui/dialogs/PatchCheckDialog.cpp" '\bPatchCheck::lowConfidenceEntities\b' '窗经判定层取低置信度实体'
arch_need "$SRC/src/ui/dialogs/PatchCheckDialog.cpp" '\bPatchCheck::agentPayload\b' '窗经判定层生成裁决载荷'
arch_need "$SRC/src/ui/dialogs/PatchCheckDialog.cpp" '\bPatchCheck::diffSnippet\b' '窗经判定层抽实码'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" '\bpatchCheckRequested\b' '详情页发 patchCheckRequested'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&ProjectDetailPage::patchCheckRequested\b' 'PanelWindow 接了补丁体检入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" '\bshowPatchCheck\b' 'PanelWindow 有开补丁体检窗的动作'
arch_need "$SRC/src/ui/PanelWindow.cpp" '\bPatchCheckDialog\b' 'PanelWindow 用的是补丁体检窗'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bPatchCheck::parseLayer1\b' 'SelfCheck 覆盖 Layer1 解析'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bPatchCheck::diffSnippet\b' 'SelfCheck 覆盖 diff 抽实码'

# 固定文档页链路：内容（DocPages 纯函数，四类目写死在代码里）→ 渲染（DocsDialog，
#   markdown）→ 接线（面板菜单「关于 / 帮助」）。文档不进引擎 —— 它不是数据。
arch_need "$SRC/src/logic/DocPages.cpp" '\bkindKey\b' '判定层有类目标识'
arch_need "$SRC/src/logic/DocPages.cpp" '\bcontent\b' '判定层有文档正文'
arch_need "$SRC/src/logic/DocPages.cpp" '\bclientRepo\b' '仓库地址有单一出处'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" '\bDocPages::content\b' '窗经判定层取正文'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" '\bsetMarkdown\b' '正文按 markdown 渲染'
arch_need "$SRC/src/ui/PanelWindow.cpp" '\bshowDocs\b' 'PanelWindow 有开文档窗的动作'
arch_need "$SRC/src/ui/PanelWindow.cpp" '\bDocsDialog\b' 'PanelWindow 用的是文档窗'
# 入口级检查：光有 showDocs 方法不算数 —— 菜单里没人调它，用户就永远打不开
# （负控实测：只删菜单两行、留着方法，上面两条照样全绿）。
arch_need "$SRC/src/ui/PanelWindow.cpp" 'addAction\(QStringLiteral\("关于 deepDolphin"\)\)' '面板菜单有「关于」入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'addAction\(QStringLiteral\("帮助"\)\)' '面板菜单有「帮助」入口'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bDocPages::content\b' 'SelfCheck 覆盖文档正文'

# 语法高亮链路：判定（SyntaxHighlight 纯函数，九语言与引擎 detectLang 对齐）→
#   涂色（CodeHighlighter，颜色取自 DS 令牌）→ 接线（代码图谱页源码页签）
arch_need "$SRC/src/logic/SyntaxHighlight.cpp" '\blanguages\b' '判定层有语言清单'
arch_need "$SRC/src/logic/SyntaxHighlight.cpp" '\bkeywords\b' '判定层有关键词表'
arch_need "$SRC/src/logic/SyntaxHighlight.cpp" '\bhighlight\b' '判定层有逐行分类'
arch_need "$SRC/src/ui/CodeHighlighter.cpp" '\bSyntaxHighlight::highlight\b' '涂色层经判定层分类'
arch_need "$SRC/src/ui/CodeHighlighter.cpp" '\bDS::semColor\b' '颜色取自 DS 令牌（不是契约色）'
# ⚠ 盯**构造点**（`new CodeHighlighter`）而不是「CodeHighlighter 这个词出现过」——
#   负控实测：只删掉构造那一行、留着 include 与另一个调用点时，后者照样全绿
#   （用户看到的源码页签还是一片纯色）。这已是第三回「门盯名字不盯接线点」。
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'new CodeHighlighter\b' '代码图谱源码页签真的 new 了一个高亮器'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_highlighter->setLanguage\b' '高亮语言跟着选中项走'
arch_need "$SRC/src/main.cpp" 'syntax-languages\b' '无头 flag 暴露语言清单（契约门第 16 组用）'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bSyntaxHighlight::highlight\b' 'SelfCheck 覆盖高亮分类'

# 图谱三件套链路：判定（GraphInsight：id→名字 / overview / symbol / impact）→
#   取数（引擎 graph overview / symbol / impact）→ 接线（代码图谱页关系页签 + 页头概览）
# ⚠ 引擎的 symbol / impact **只认符号名**：传 id 它返回空结果，看着像「没有影响面」。
arch_need "$SRC/src/logic/GraphInsight.cpp" '\bsymbolNameFromId\b' '判定层有「id 取名字」（引擎只认名字）'
arch_need "$SRC/src/logic/GraphInsight.cpp" '\bparseOverview\b' '判定层有概览解析'
arch_need "$SRC/src/logic/GraphInsight.cpp" '\bparseSymbol\b' '判定层有符号详情解析'
arch_need "$SRC/src/logic/GraphInsight.cpp" '\bparseImpact\b' '判定层有影响面解析'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("overview"\)' 'AppModel 调引擎 graph overview'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("impact"\)' 'AppModel 调引擎 graph impact'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("symbol"\)' 'AppModel 调引擎 graph symbol'
# ⚠ 盯**调用点**而不是方法名：方法定义还在时 grep 照样命中（这是第四次同类漏洞）。
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '^[[:space:]]*showImpact\(\);[[:space:]]*$' '关系页签真的调用了影响面（不是只定义了方法）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '\bGraphInsight::symbolNameFromId\b' '界面按名字问引擎（不传 id）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '\bloadOverview\b' '页头接了项目级概览'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bGraphInsight::symbolNameFromId\b' 'SelfCheck 覆盖 id→名字'

# 引擎自检（doctor）链路：判定（EngineDoctor 纯函数）→ 取数（引擎 doctor --json）
#   → 接线（设置·通用页「环境自检」卡）。
# ⚠ doctor **发现问题时退出码是 1**（自检必须能失败）但 stdout 仍是合法 JSON，
#   所以客户端必须**读载荷**判成败，不能按退出码。钉调用点。
arch_need "$SRC/src/logic/EngineDoctor.cpp" 'Report parse\b' '判定层有自检载荷解析'
arch_need "$SRC/src/logic/EngineDoctor.cpp" 'QString summary\b' '判定层有自检摘要'
arch_need "$SRC/src/logic/EngineDoctor.cpp" 'Tone toneOf\b' '判定层有自检档位映射'
arch_need "$SRC/src/app/AppModel.h" '\brunDoctor\b' 'AppModel 暴露 runDoctor'
arch_need "$SRC/src/app/AppModel.h" '\bdoctorFinished\b' 'AppModel 有自检回执信号'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("doctor"\)' 'AppModel 调引擎 doctor'
arch_need "$SRC/src/app/AppModel.cpp" 'EngineDoctor::parse\(res\.payload->object\(\)\)' '自检读**载荷**判成败（不是按退出码）'
arch_need "$SRC/src/app/AppModel.cpp" 'm_doctor = r\b' '自检结果落到 AppModel 成员'
# 接线：设置·通用页的「运行自检」钮 —— 盯**构造点**与**调用点**，不是「doctor 这个词出现过」。
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'new DPushButton\(QStringLiteral\("运行自检"\)' '设置页真的造了「运行自检」按钮'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'm_model->runDoctor\(\)' '「运行自检」真的调了引擎自检'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" '&AppModel::doctorFinished\b' '设置页接了自检回执'
arch_need "$SRC/src/ui/dialogs/AiSettingsDialog.cpp" 'new GeneralPane\(model,' '设置窗把模型传给了通用页'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'new AiSettingsDialog\(m_model,' '面板把模型传给了设置窗'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bEngineDoctor::parse\b' 'SelfCheck 覆盖自检解析'

# 进度报告（report）链路：取数（引擎 report，回执型命令）→ 回执路径提取
#   → 接线（详情页「导出报告」入口 + 报告卡）。
arch_need "$SRC/src/app/AppModel.h" '\bexportReport\b' 'AppModel 暴露 exportReport'
arch_need "$SRC/src/app/AppModel.h" '\breportExported\b' 'AppModel 有报告回执信号'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("report"\)' 'AppModel 调引擎 report'
arch_need "$SRC/src/app/AppModel.cpp" 'callText\(\{ *QStringLiteral\("report"\)' 'report 走 Text 契约（callText，不是 callJson）'
# ⚠ 回执通道：引擎的 report 把回执写在 **stderr**（arch gen / render arch 才在 stdout）。
#   只认 stdout 的客户端会把「报告已生成」判成「引擎没有回执」—— 成功说成失败。
arch_need "$SRC/src/app/EngineCli.h" '\breceiptText\b' 'EngineCli 有回执通道（stdout 优先，空则 stderr）'
arch_need "$SRC/src/app/EngineCli.cpp" 'r\.receipt = EngineCli::receiptText\b' '回执走 receiptText（两路兜底）'
arch_need "$SRC/src/app/AppModel.cpp" 'res\.receipt\b' 'Text 消费点读 receipt（不是 stdOut）'
# 引擎回执带 ANSI 颜色码（引擎不认 NO_COLOR）→ 显示前必须剥。
arch_need "$SRC/src/logic/ArchReceipt.cpp" 'QString plain\b' '判定层有剥 ANSI 的回执净化'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bEngineDoctor::checkLine\b' 'SelfCheck 覆盖自检行文'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bEngineCli::receiptText\b' 'SelfCheck 覆盖回执通道'
# 接线：详情页的「导出报告」入口 → 面板 → 引擎。盯构造点与调用点。
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" '\breportExportRequested\b' '详情页发 reportExportRequested'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'QStringLiteral\("导出报告"\)' '详情页真的造了「导出报告」入口'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" '\bArchReceipt::filePath\b' '报告卡经判定层抽落盘路径'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" '\bArchReceipt::plain\b' '报告卡剥 ANSI 后再显示'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&ProjectDetailPage::reportExportRequested\b' 'PanelWindow 接了导出报告入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'm_model->exportReport\b' 'PanelWindow 真的调了引擎 report'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&AppModel::reportExported\b' 'PanelWindow 接了报告回执'
# 无头 flag：契约门第 18 组拿真载荷/真回执喂客户端，逐条对判定结果。
arch_need "$SRC/src/main.cpp" '--doctor-parse\b' '无头 flag 能把 doctor 载荷判成档（契约门用）'
arch_need "$SRC/src/main.cpp" '--receipt-file-path\b' '无头 flag 能从回执抽落盘路径（契约门用）'

# 引擎配置（config list / config set）链路：判定（EngineConfig 纯函数）
#   → 取数（引擎 config list --json）→ 写（引擎 config set，回执型）
#   → 接线（设置·通用页「引擎配置」卡）。
arch_need "$SRC/src/logic/EngineConfig.cpp" 'Config parse\b' '判定层有配置载荷解析'
arch_need "$SRC/src/logic/EngineConfig.cpp" '\bwritableKeys\b' '判定层有可写键清单（与引擎同一份）'
arch_need "$SRC/src/logic/EngineConfig.cpp" '\bisWritable\b' '判定层能判键可不可写'
arch_need "$SRC/src/app/AppModel.h" '\bloadEngineConfig\b' 'AppModel 暴露 loadEngineConfig'
arch_need "$SRC/src/app/AppModel.h" '\bsetEngineConfig\b' 'AppModel 暴露 setEngineConfig'
arch_need "$SRC/src/app/AppModel.h" '\bengineConfigChanged\b' 'AppModel 有配置变化信号'
arch_need "$SRC/src/app/AppModel.h" '\bengineConfigSaved\b' 'AppModel 有配置写入回执信号'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("config"\), *QStringLiteral\("list"\)' 'AppModel 调引擎 config list'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("config"\), *QStringLiteral\("set"\)' 'AppModel 调引擎 config set'
# ⚠ config set 是**回执型命令**（回执在 stderr）→ 必须走 Text 契约。
#   拿 callJson 去收，exit==0 也会被判成「引擎输出不是合法 JSON」—— 成功报成失败。
arch_need "$SRC/src/app/AppModel.cpp" 'callText\(\{ *QStringLiteral\("config"\), *QStringLiteral\("set"\)' 'config set 走 Text 契约（callText）'
# 键白名单：客户端先拦一道，界面才不会给用户一个引擎根本不认的键。
arch_need "$SRC/src/app/AppModel.cpp" 'EngineConfig::isWritable\(key\)' 'setEngineConfig 有键白名单'
# ⚠ `res.receipt` 在 AppModel 里有多处（架构图/索引/报告都读它）——
#   盯泛化的 `res\.receipt` 的话，摘掉配置这一处门照样绿。故盯到本行。
arch_need "$SRC/src/app/AppModel.cpp" 'emit engineConfigSaved\(true, res\.receipt\);' '配置写入读 receipt（不是 stdOut）'
# 接线：设置页的「引擎配置」卡 —— 盯构造点与调用点。
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'new DPushButton\(QStringLiteral\("读取引擎配置"\)' '设置页真的造了「读取引擎配置」按钮'
# ⚠ 「读取引擎配置」有**两个**调用点（按钮 / 打开本页自动读）。盯名字会互相顶替：
#   摘掉其中一处，门照样绿（同名调用点替另一个顶了）—— 这是第五次同类漏洞。
#   故分别盯：**按钮 → 读**（单行 connect，正则含 connect 头）与 **打开本页 → 读**
#   （整行独占的正则），再盯**读的方法体**真的调了引擎。
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'connect\(m_configButton, &DPushButton::clicked, this, \[this\] \{ reloadEngineConfig\(\); \}\);' '「读取引擎配置」按钮真的接上了读'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" '^[[:space:]]*reloadEngineConfig\(\);[[:space:]]*$' '打开设置·通用页会自动读一次配置'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'm_model->loadEngineConfig\(\)' '读取引擎配置的方法真的调了引擎 config list'
# ⚠ 同理：两个可写键是**两次**调用。只盯 `setEngineConfig(` 的话，摘掉其中
#   一次调用门照样绿。故按键分别盯。
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'setEngineConfig\(QStringLiteral\("update\.maxShallowBranches"\)' '设置页真的写回了分支上限'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'setEngineConfig\(QStringLiteral\("update\.backupKeep"\)' '设置页真的写回了备份份数'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" '&AppModel::engineConfigChanged\b' '设置页接了配置变化信号'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" '&AppModel::engineConfigSaved\b' '设置页接了配置写入回执'
arch_need "$SRC/src/main.cpp" '--engine-config-parse\b' '无头 flag 能把 config 载荷判成值（契约门用）'
arch_need "$SRC/src/main.cpp" '--receipt-plain\b' '无头 flag 能把回执净化成干净文本（契约门用）'
# 用户手改输入框后，重读**不得回填**（否则点「应用」写回第一个键会触发重读，
# 把用户刚填的第二个还没写回的值冲掉 → 用户以为「改了没用」而反复点）。
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'if \(!m_configInputsDirty\)' '手改未写回的输入框不被重读冲掉'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bEngineConfig::parse\b' 'SelfCheck 覆盖配置解析'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bEngineConfig::writableKeys\b' 'SelfCheck 覆盖可写键清单'

# 持久化代码索引的状态（index overview / index update）链路：
#   判定（IndexStatus 纯函数）→ 取数（引擎 index overview / index update）
#   → 接线（代码图谱页「增量更新」钮 + 索引状态行）。
arch_need "$SRC/src/logic/IndexStatus.cpp" 'Overview parseOverview\b' '判定层有索引概览解析'
arch_need "$SRC/src/logic/IndexStatus.cpp" 'UpdateResult parseUpdate\b' '判定层有索引更新解析'
arch_need "$SRC/src/logic/IndexStatus.cpp" 'QString summary\b' '判定层有索引摘要'
arch_need "$SRC/src/app/AppModel.h" '\bloadIndexOverview\b' 'AppModel 暴露 loadIndexOverview'
arch_need "$SRC/src/app/AppModel.h" '\bupdateIndex\b' 'AppModel 暴露 updateIndex'
arch_need "$SRC/src/app/AppModel.h" '\bindexStatusChanged\b' 'AppModel 有索引状态信号'
arch_need "$SRC/src/app/AppModel.h" '\bindexUpdated\b' 'AppModel 有索引更新结果信号'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("index"\), *QStringLiteral\("overview"\)' 'AppModel 调引擎 index overview'
arch_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("index"\), *QStringLiteral\("update"\)' 'AppModel 调引擎 index update'
# ⚠ 「已最新」≠「已更新」：fresh 时引擎**什么都没重建**，界面不能说成「更新好了」。
arch_need "$SRC/src/app/AppModel.cpp" 'if \(u\.fresh\)' '索引更新区分「已最新」与「已重建」'
# 接线：代码图谱页的「增量更新」钮 + 索引状态行。盯构造点与调用点。
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'QStringLiteral\("增量更新"\)' '代码图谱页真的造了「增量更新」按钮'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_model->updateIndex\(' '「增量更新」真的调了引擎 index update'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_model->loadIndexOverview\(' '代码图谱页真的读了索引状态'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '&AppModel::indexStatusChanged\b' '代码图谱页接了索引状态信号'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '&AppModel::indexUpdated\b' '代码图谱页接了索引更新结果'
arch_need "$SRC/src/main.cpp" '--index-status-parse\b' '无头 flag 能把索引概览判成值（契约门用）'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bIndexStatus::parseOverview\b' 'SelfCheck 覆盖索引概览解析'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bIndexStatus::parseUpdate\b' 'SelfCheck 覆盖索引更新解析'

# 批 M · 性能审计：Canvas 字体路径（解析在判定层 + QFont 缓存 + 同串跳过）
#   与热力图每帧分配（索引缓存 / 静态字体串 / 成员比较）。
# ⚠ Canvas 的 font 简写是**浏览器 CSS 口径**（px 与 pt 都认）——
#   解析器只认 px 时，"11pt" 会被当成字体族名吞掉，字号根本没设上。
arch_need "$SRC/src/logic/CanvasFont.cpp" 'Spec parse\b' '判定层有 Canvas font 简写解析'
arch_need "$SRC/src/logic/CanvasFont.cpp" '\bptRe\b' '字体解析认 pt 单位（CSS 口径）'
# 平台层必须**走判定层**解析（不许自己再 split 一份 —— 那会造出第二个真相源）
arch_need "$SRC/src/platform/Canvas2D.cpp" '\bCanvasFont::parse\b' 'Canvas2D 走判定层解析字体'
# QFont 缓存：Canvas2D 每帧新建，实例级缓存等于每帧重建 → 必须静态。
arch_need "$SRC/src/platform/Canvas2D.cpp" 'static QHash<QString, QFont> cache\b' 'Canvas2D 有静态字体缓存'
# ⚠ 盯**跳过的那一行**，不是「m_fontKey 这个名字出现过」—— 只盯名字的话，
#   把 `if (f == m_fontKey) return;` 换成注释（名字还在）门照样绿。
arch_need "$SRC/src/platform/Canvas2D.cpp" 'if \(f == m_fontKey\)' '同串连着来时跳过重复设置'
# 热力图：每帧的分配（三处）
# ⚠ 盯**值里没有 % 占位**（只盯「有 kFontCard 这个常量」的话，把它改回
#   QStringLiteral("%1pt sans-serif") 门照样绿 —— 而那正是每帧拼字符串的写法）。
arch_need "$SRC/src/ui/HeatmapWidget.cpp" 'kFontCard = QStringLiteral\("[^%"]*"\)' '热力图字体串是静态常量（不是每帧拼）'
arch_need "$SRC/src/ui/HeatmapWidget.cpp" 'kFontSub = QStringLiteral\("[^%"]*"\)' '热力图次级字体串是静态常量'
# ⚠ 盯**绘制路径引用缓存索引**那一行 —— 只盯「m_cardById 出现过」的话，
#   把 paintRoutes 改回每帧建 QHash（成员还在 rebuild 里）门照样绿。
arch_need "$SRC/src/ui/HeatmapWidget.cpp" 'const QHash<QString, const HeatLayout::Card \*> &byId = m_cardById;' '热力图绘制用的是缓存索引（不是每帧建）'
arch_need "$SRC/src/ui/HeatmapWidget.cpp" 'm_cacheW != width\(\)' '热力图缓存判据逐项比较成员（不是拼字符串键）'
# formatter 静态化（mac 性能审计 21c7082 同款）
arch_need "$SRC/src/ui/dialogs/AddMilestoneDialog.cpp" 'toString\(Qt::ISODate\)' '日期格式化走 ISODate 枚举（不建格式串）'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bCanvasFont::parse\b' 'SelfCheck 覆盖字体解析'

# 批 N · 设计系统存量清零（DS 单一真相源）：四处散值收进 token，
#   D2 门上限降到 0，且门独立成 scripts/ci-d2.sh（负控能精确打）。
arch_need "$SRC/src/ui/DesignTokens.h" 'namespace FontPx\b' 'DS 有 QSS 字号 token（QSS 只能写字面量）'
arch_need "$SRC/src/ui/DualTrackButtons.cpp" '\bDS::FontPx::badge\b' '胶囊徽章字号走 token'
arch_need "$SRC/src/ui/common/Chip.h" '\bDS::FontPx::badge\b' '小标签字号走 token'
arch_need "$SRC/src/ui/common/MarkdownView.h" '\.arg\(DS::MD_H3\);' 'Markdown h4-h6 与 h3 同档（走 token）'
arch_need "$SRC/src/ui/pages/ProjectProgressCard.cpp" '\bDS::FontPx::code\b' '等宽项目名字号走 token'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bDS::FontPx::badge\b' 'SelfCheck 钉住 token 值'

# 批 N · 透明度入 token（色进了 DS 而 alpha 没进 = 同一语义散成 N 个真相源）
arch_need "$SRC/src/ui/DesignTokens.h" 'namespace Alpha\b' 'DS 有透明度 token'
arch_need "$SRC/src/ui/DesignTokens.h" '\baccentTintRgba\b' 'DS 提供 rgba 拼装（调用方不拼字面量）'
arch_need "$SRC/src/ui/dialogs/AgentDialog.cpp" '\bDS::accentTintRgba\b' '用户气泡底色走 token 拼装'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bDS::Alpha::accentTint\b' 'SelfCheck 钉住透明度 token'

# 批 N · 底轨遮罩 + 热力图画布色收口（原散在 HeatmapWidget 的 7 处）
arch_need "$SRC/src/ui/DesignTokens.h" '\btrackMask\b' 'DS 有底轨遮罩色'
arch_need "$SRC/src/ui/common/SegmentedBar.h" '\bDS::trackMask\b' '分段条底轨走 token'
arch_need "$SRC/src/logic/HeatLayout.h" 'namespace Canvas\b' '热力图画布配色有唯一出处'
arch_need "$SRC/src/ui/HeatmapWidget.cpp" '\bHeatLayout::Canvas::cardBase\b' '热力图卡底色走 HeatLayout'
arch_need "$SRC/src/ui/HeatmapWidget.cpp" '\bHeatLayout::Canvas::cardText\b' '热力图卡片文字色走 HeatLayout'

# 批 N · 散值门必须真在 CI 流程里（门写好不接 = 没有门）
arch_need "$SRC/scripts/ci.sh" 'sh "\$SRC/scripts/ci-d2\.sh"' 'CI 流程调用独立散值门'
arch_need "$SRC/scripts/ci-d2.sh" 'D2_EXEMPT=.src/ui/DesignTokens\.h\b' '散值门有显式豁免清单（豁免是登记的）'
arch_need "$SRC/scripts/ci-d2.sh" '豁免已失效：\$_p\b' '散值门自检豁免不腐化（归零即红）'

# 批 O · 状态语义色单一真相源：固定色下沉到 logic/SemColors（判定层纯色、零 UI 依赖），
#   DS::semColor 转发它；判定层 / 托盘 / 平台层都不再自己写字面色值。
arch_need "$SRC/src/logic/SemColors.h" 'namespace SemColors [{]' '固定色有唯一出处（判定层纯色）'
arch_need "$SRC/src/logic/SemColors.h" 'namespace FixedColors [{]' '固定非语义色有唯一出处'
# ⚠ 下面这五条用**精确计数**而不是「出现过」：同名 token 在文件里有多处
#   （Derived 的 shallow ×2、IconResolver 的 iconFallback ×2），
#   变异只摘掉其中一处时「出现过」照样绿（负控实测，第八次同类问题）。
arch_need_count "$SRC/src/ui/DesignTokens.cpp" 'SemColors::shallow\(\)' 1 'DS::semColor 转发唯一出处（恰好 1 处）'
arch_need_count "$SRC/src/logic/Derived.cpp" 'SemColors::shallow\(\)' 2 '判定层状态色走唯一出处（恰好 2 处）'
arch_need_count "$SRC/src/tray/TrayController.cpp" 'SemColors::stale\(\)' 1 '托盘状态色走唯一出处（恰好 1 处）'
arch_need_count "$SRC/src/tray/TrayPopupWindow.cpp" 'FixedColors::trayAccent\(\)' 1 '托盘强调色走唯一出处（恰好 1 处）'
arch_need_count "$SRC/src/platform/IconResolver.cpp" 'FixedColors::iconFallback\(\)' 2 '图标兜底色走唯一出处（恰好 2 处）'
arch_need "$SRC/src/app/SelfCheck.cpp" 'SemColors::stale\(\)' 'SelfCheck 钉住唯一出处的值'
# 「不该有的东西没了」：写死的色值又写回去 → 必须红（正向条目抓不到这种回退）
arch_forbid "$SRC/src/logic/Derived.cpp" 'QColor\(0[xX][0-9A-Fa-f]' '判定层不再自己写字面色值'
arch_forbid "$SRC/src/tray/TrayController.cpp" 'QColor\(0[xX][0-9A-Fa-f]' '托盘不再自己写字面色值'
arch_forbid "$SRC/src/tray/TrayPopupWindow.cpp" 'QColor\(0[xX][0-9A-Fa-f]' '托盘弹层不再自己写字面色值'
arch_forbid "$SRC/src/platform/IconResolver.cpp" 'QColor\(0[xX][0-9A-Fa-f]' '平台层不再自己写字面色值'
arch_forbid "$SRC/src/ui/DesignTokens.cpp" 'QColor\(0[xX][0-9A-Fa-f]' 'DS 不再自己写语义色字面量'

# 批 R · 跨端状态色取值对齐：UI 层（有状态词，颜色只做辅助）按 mac 活代码的口径，
#   托盘（图标无文字，颜色是唯一信号）保留独立档 —— 托盘那一档已由批 O 的
#   「托盘状态色走唯一出处（恰好 1 处）」盯着，本批只补**边界**。
# ⚠ 「陈旧红只许托盘用」是**边界**不是风格 —— 判定层一旦挂回 #EF4444，
#   UI 上就同时出现两个肉眼几乎分不出的红（#EF4444 / #DC2626），读者分不出谁是谁。
arch_forbid "$SRC/src/logic/Derived.cpp" 'SemColors::stale\(' '陈旧红是托盘专用档（判定层不挂这一档）'

# 门项正则的**引号形式必须统一用单引号** —— 批量加固（加词边界）按形式分派，
#   双引号那一批会被漏掉 ⇒ 那批门项仍是「加后缀可顶替」的状态
#   （负控实测：「形式互相顶替」的又一次变体 —— 同一个门脚本里两种写法混用）。
arch_forbid "$SRC/scripts/ci-wiring.sh" '^arch_[a-z_]+ "\$SRC/[^"]*" "' '门项正则统一用单引号（形式不许混）'

# 批 R · 状态色样张（补上面板快照的**空门**）：面板快照拍的是空态（引擎注册项目数 0），
#   状态点一个都没画进去 —— 改状态色它不红。这张色卡把每档都画出来。
# ⚠ 色卡**必须走判定层取色**：自己写死色值 = 第二份定义（改了判定层色卡不变 = 门是假的）。
# ⚠ 正则一律**卡 token 边界**（带括号 / 带引号 / 带空格）：裸 `--color-sample` 会被
#   `--color-sampleX` 顶替、裸 `Derived::livenessColor` 会被 `…ColorImpl` 顶替
#   （负控实测，**第十二次**「子串互相顶替」）。
arch_need "$SRC/src/ui/ColorSampleSheet.cpp" 'Derived::livenessColor\(' '色卡 liveness 档走判定层取色'
arch_need "$SRC/src/ui/ColorSampleSheet.cpp" 'Derived::branchStatusColor\(' '色卡分支状态档走判定层取色'
arch_need "$SRC/src/ui/ColorSampleSheet.cpp" 'Derived::livenessKinds\(\)' '色卡 liveness 档按判定层清单画（不抄一份）'
arch_need "$SRC/src/ui/ColorSampleSheet.cpp" 'Derived::branchStatusKinds\(\)' '色卡分支状态档按判定层清单画（不抄一份）'
arch_forbid "$SRC/src/ui/ColorSampleSheet.cpp" 'QColor\(0[xX][0-9A-Fa-f]' '色卡不自己写色值'
arch_need "$SRC/src/main.cpp" '"--color-sample"' '无头入口可拍状态色样张'
arch_need "$SRC/scripts/ci.sh" '--color-sample ' 'CI 截图矩阵含状态色样张'

# 批 S · deb 打包（D7 达分的必经）：依赖清单是**唯一出处**，且必须与二进制实际依赖一致。
# ⚠ 漏声明 DTK 的两个插件包最隐蔽：不报错，只是**静默降级**成「纯 Qt 感」。
arch_need "$SRC/scripts/build-deb.sh" 'deb-deps\.txt\b' 'deb 依赖清单是唯一出处（脚本只读它）'
arch_need "$SRC/scripts/deb-deps.txt" 'dde-qt6integration\b' 'DTK 样式插件包在依赖清单里（缺 = 静默降级）'
arch_need "$SRC/scripts/deb-deps.txt" 'dde-qt6xcb-plugin\b' 'DTK xcb 插件包在依赖清单里（缺 = 退回 Qt 原生 xcb）'
# ⚠ 正则盯**具体那一行调用**（`grep -c 'not found'`），不是「出现过 not found」——
#   `not found` 在脚本里出现两次（这一行 + die 消息里那句），
#   只改这一行时「出现过」照样绿（同名多处互相顶替，负控实测）。
arch_need "$SRC/scripts/build-deb.sh" 'grep -c .not found\b' 'deb 构建校验解包后无缺失库（D7 核心）'
arch_need "$SRC/scripts/build-deb.sh" 'rpath|runpath' 'deb 构建检查包内二进制无 RPATH'
arch_need "$SRC/scripts/ci.sh" 'build-deb\.sh\b' 'CI 流程构建 deb（D7 达标必经）'

# 批 T · 面板快照夹具：基线要**可重现** ⇒ 快照走固定夹具，不走真引擎
#   （真引擎取数让基线取决于「本机注册了什么项目」——此前拍的是空态，
#     对状态色/布局全是空门）。
arch_need "$SRC/src/logic/SnapshotFixture.h" 'namespace SnapshotFixture [{]' '快照夹具有判定层（纯数据）'
arch_need "$SRC/src/app/AppModel.cpp" 'useSnapshotFixture' 'AppModel 提供夹具注入'
arch_need "$SRC/src/main.cpp" 'useSnapshotFixture\(\)' '快照走夹具（不走真引擎）'
# 取数与判定分层：夹具与引擎必须共用**同一段解析**，否则夹具测不到真路径
arch_need "$SRC/src/app/AppModel.cpp" 'applyStatusPayload' '载荷应用抽成一层（夹具与引擎共用）'
arch_need "$SRC/src/app/AppModel.cpp" 'applyDashboardPayload' '载荷应用抽成一层（夹具与引擎共用）'
arch_need "$SRC/src/app/AppModel.cpp" 'applyMilestonesPayload' '载荷应用抽成一层（夹具与引擎共用）'
# 拍到空态必须响亮失败（否则空图被固化成基线 = 又一个空门）
arch_need "$SRC/src/main.cpp" '夹具没有项目' '快照拍到空态要响亮失败（别固化空基线）'
# ⚠ Qt 的 arg 重载陷阱：`arg(QString, int)` 命中 **arg(a1, fieldWidth) 重载**
#   ⇒ 第二个占位符原样留在界面上（提交构成图例曾一直显示「feat ×%2」）。
#   正则要求**同一个 arg(...) 内部**有逗号 —— 链式 `.arg(a).arg(b)` 不该被误伤。
arch_forbid "$SRC/src/ui/pages/ProjectProgressCard.cpp" '\.arg\([^;]*?,\s*entries\.at\(i\)\.second' '提交构成图例不许用 arg(QString,int)（会命中 fieldWidth 重载）'

# 批 T 续 · **基线必须逐字节可重现** —— 基线带墙钟就等于没有基线：
#   CI 每次都出 diff ⇒ 人就学会忽略 diff ⇒ 基线退化成空门（比没门更糟）。
#   墙钟有两处出口，各钉一处：
#   ① 侧栏「上次刷新 HH:mm」= epoch 的**本地时区**渲染 ⇒ 固定 epoch + 固定 TZ；
#   ② 里程碑「目标 YYYY-MM-DD」= 绝对日期 ⇒ 锚定固定基准日。
# ⚠ 正则盯**具体那一句**（不是「出现过 fixedRefreshedMs」）——
#   拿掉赋值只留声明时，「出现过」照样绿（负控实测，第十四次「同名/子串互相顶替」）。
arch_need "$SRC/src/app/AppModel.cpp" 'm_lastRefreshedMs = SnapshotFixture::fixedRefreshedMs\(\)' '快照刷新时刻用固定值（不用墙钟）'
# ⚠ 精确计数：AppModel 里**只有生产取数路径**那 3 处可以用墙钟。
#   夹具路径多一处 ⇒ 计数变 4 ⇒ 红。
arch_need_count "$SRC/src/app/AppModel.cpp" 'm_lastRefreshedMs = QDateTime::currentMSecsSinceEpoch\(\)' 3 '墙钟刷新时刻只许出现在生产取数路径（夹具路径不许有）'
arch_need "$SRC/src/main.cpp" 'qputenv\("TZ", "UTC"\)' '快照进程固定时区（换台机器拍出同一张）'
arch_need "$SRC/src/logic/SnapshotFixture.cpp" 'kAnchorDate\[\] = "2026-01-15"' '夹具有固定基准日（绝对日期的唯一起点）'
# ⚠ 精确计数：夹具里**只有 lastCommitAt 那两条**能碰真实 now
#   （天数组要拿它跟真实现在比 epoch，写死就天天漂）。
#   多一处 currentDateTimeUtc() ⇒ 说明又有人引入了「今天」⇒ 红。
arch_need_count "$SRC/src/logic/SnapshotFixture.cpp" 'currentDateTimeUtc\(\)' 2 '夹具里只有 lastCommitAt 跟真实 now 走（绝对日期不许跟今天走）'
# 里程碑是「同一个对象」⇒ 两处载荷只许有一份文本（之前各写一份，cygnus 的
#   targetDate 一边有日期一边空 ⇒ 同一件事两套说法）。
arch_need_count "$SRC/src/logic/SnapshotFixture.cpp" '"projectId":"p_atlas"' 1 '里程碑条目只写一份（dashboard 与 milestone list 共用）'
arch_need "$SRC/src/app/SelfCheck.cpp" '绝对日期锚定基准日' 'SelfCheck 钉住绝对日期锚定（跨天也抓得住）'
arch_need "$SRC/src/app/SelfCheck.cpp" '刷新时刻固定' 'SelfCheck 钉住刷新时刻固定'
# 「重拍比字节」这道门盯的是**行为**（两次拍出同一张图），不是文件里的字样。
# ⚠ 精确计数：ci.sh 里 `cmp -s` 出现**两处**（比基线 / 比换时区那张）——
#   只拿掉一处时「出现过」照样绿 ⇒ 门被骗过（负控实测，第十五次「同名互相顶替」）。
arch_need_count "$SRC/scripts/ci.sh" 'cmp -s' 2 'CI 有「重拍比字节」门（基线必须可重现）'
# ⚠ 换时区那张必须挑**两个互相不同**的时区：拿「宿主时区」当其中一个时，
#   宿主恰好就是那个时区 ⇒ 两张必然相同 ⇒ 门永远绿（负控实测：宿主就是 Asia/Shanghai）。
arch_need "$SRC/scripts/ci.sh" 'America/New_York' 'CI 的跨时区对比用两个互不相同的时区'

# 批 U · M1-2 图标统一入口：图标名**只许**在判定层 `logic/IconNames` 里出现一次。
# ⚠ 这两道门是**多文件**扫描（UI 下有十几个文件）—— 单文件的 arch_forbid 覆盖不到。
#   ① UI 里不许再直接 `QIcon::fromTheme(...)`（那会绕过候选链与缺失告警）；
#   ② 统一入口的入参必须是**枚举** `IconNames::Id`（字符串拼错编译期发现不了）。
ICON_RAW=0
ICON_STR=0
for f in "$SRC"/src/ui/*.cpp "$SRC"/src/ui/*.h "$SRC"/src/ui/pages/*.cpp "$SRC"/src/ui/pages/*.h \
         "$SRC"/src/ui/common/*.cpp "$SRC"/src/ui/common/*.h "$SRC"/src/ui/dialogs/*.cpp \
         "$SRC"/src/ui/dialogs/*.h "$SRC"/src/ui/dialogs/panes/*.cpp; do
    [ -f "$f" ] || continue
    if strip_comments "$f" | grep -qE 'QIcon::fromTheme'; then
        echo "  ✗ UI 里还有裸 QIcon::fromTheme（图标必须走 platform::icon）：$f" >&2
        ICON_RAW=1
    fi
    if strip_comments "$f" | grep -qE 'platform::icon\(QStringLiteral'; then
        echo "  ✗ 统一入口入参用了字符串（拼错编译期发现不了）：$f" >&2
        ICON_STR=1
    fi
done
ARCH_N=$((ARCH_N + 1))
if [ "$ICON_RAW" -eq 0 ]; then
    echo "  ✓ 图标取用统一走 platform::icon（UI 里无裸 QIcon::fromTheme）"
else
    ARCH_FAIL=1
fi
ARCH_N=$((ARCH_N + 1))
if [ "$ICON_STR" -eq 0 ]; then
    echo "  ✓ 统一入口入参是枚举（拼错编译不过）"
else
    ARCH_FAIL=1
fi
# ⚠ 必须带 **token 边界**（`[{]`）：裸 `enum class Id` 会被 `enum class IdX` 顶替
#   （负控实测，**第十六次**「子串互相顶替」）—— 改名后门照样绿。
arch_need "$SRC/src/logic/IconNames.h" 'enum class Id [{]' '图标逻辑名是枚举（拼错编译不过）'
arch_need "$SRC/src/logic/IconNames.cpp" 'QStringList fallbacks\(Id id\)' '候选链按枚举取（单一出处）'
arch_need "$SRC/src/platform/IconResolver.h" 'QIcon icon\(IconNames::Id id' '统一入口收枚举'
arch_need "$SRC/src/platform/IconResolver.cpp" 'DDciIcon::fromTheme' '图标解析 DDci 优先（deepin 自己的图标集）'
# ⚠ 「这台机器没有图标主题」是**环境事实**，不是图标名错 ⇒ 不算缺失、不画占位圆点
#   （圆点会把离屏基线污染成「到处都是圆点」，反而看不出真问题）。
arch_need "$SRC/src/platform/IconResolver.cpp" 'QIcon::themeName\(\)\.isEmpty\(\)' '无图标主题时不算缺失（环境事实 ≠ 图标名错）'
arch_need "$SRC/src/platform/IconResolver.cpp" '图标解析不到' '解析不到必须告警（缺失可见，不是静默空图标）'
arch_need "$SRC/src/main.cpp" 'iconMissing=' '探针报图标缺失数（缺失可见）'
# 死代码 IconLoader 已删（零调用点）—— 不许复活。
arch_forbid "$SRC/CMakeLists.txt" 'IconLoader' '死代码 IconLoader 不许复活'

# 批 P · 引擎获取链（GitHub Releases 下载安装）：判定层出结论，执行层只管跑，
#   界面只读结论。⚠ URL / 资产名 / 校验和 / 落盘位置**一处**说了算。
arch_need "$SRC/src/logic/EngineDownload.h" 'namespace EngineDownload [{]' '引擎下载有判定层（结论一处）'
arch_need "$SRC/src/logic/EngineDownload.cpp" 'parseRelease\(const QByteArray &json\)' '判定层从 release 载荷挑本平台资产'
arch_need "$SRC/src/logic/EngineDownload.cpp" 'digestMatches\(const QString &expected\b' '判定层做 sha256 校验'
arch_need "$SRC/src/app/EngineInstaller.cpp" '\bEngineDownload::parseRelease\b' '执行层走判定层挑资产'
arch_need "$SRC/src/app/EngineInstaller.cpp" '\bEngineDownload::digestMatches\b' '执行层走判定层校验'
arch_need "$SRC/src/app/EngineInstaller.cpp" '\bEngineDownload::packagedBinName\b' '包内文件名走判定层'
arch_need "$SRC/src/app/AppModel.cpp" '\bEngineDownload::releaseApiUrl\b' 'AppModel 走判定层取发布信息 URL'
arch_need "$SRC/src/app/AppModel.cpp" 'void AppModel::downloadEngine\(\)' 'AppModel 暴露下载引擎'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'm_model->downloadEngine\b' '设置页有下载引擎入口'
arch_need "$SRC/src/app/EngineLocator.cpp" 'libexec/deepdolphin/moongit\b' '发现链认得下载链装的位置'
# ⚠ 用**精确计数**（两个调用点都要在）：`--engine-download` 在 main.cpp 出现两次
#   （contains 与 indexOf），只盯「出现过」时变异改掉其中一处门照样绿
#   （负控实测，第九次「同名/子串互相顶替」）。
arch_need_count "$SRC/src/main.cpp" 'QStringLiteral\("--engine-download"\)' 2 '无头入口可端到端验下载链（两个调用点都在）'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bEngineDownload::parseRelease\b' 'SelfCheck 覆盖下载判定层'
# 「同一件事只许一个出处」：发布信息 URL 只在判定层写一次。
# ⚠ 曾经给「界面」和「发现链」也加了同款 forbid —— 那是**空门**：
#   这两处根本没有写 URL 的机会（界面拿不到执行层、发现链不碰下载），
#   空门比没门更糟（给人虚假的安全感）。改成盯**真会发生的违规**。
arch_forbid "$SRC/src/app/EngineInstaller.cpp" 'api\.github\.com\b' '执行层不自己写发布信息 URL'
arch_forbid "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" '\bEngineInstaller\b' '界面不绕过 AppModel 直接用执行层'
arch_forbid "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" '\bEngineDownload::\b' '界面不自己读判定层（结论经 AppModel 传上来）'

# 批 Q · 引擎钩子（post-commit / post-merge 托管块）：判定层出结论，
#   执行层只管跑，界面只读结论。⚠ 卸载**只删托管块**（用户的钩子逻辑留着）——
#   这条一旦不成立，界面的「卸载」按钮就是删用户数据。
arch_need "$SRC/src/logic/EngineHook.h" 'namespace EngineHook [{]' '引擎钩子有判定层（结论一处）'
arch_need "$SRC/src/logic/EngineHook.cpp" 'parseStatus\(const QByteArray &json\)' '判定层解析 hook status 载荷'
arch_need_count "$SRC/src/logic/EngineHook.cpp" 'arr\.at\(0\)\.toBool\(\)' 1 '钩子位置约定：installed[0] = post-commit（恰好一处）'
arch_need_count "$SRC/src/logic/EngineHook.cpp" 'arr\.at\(1\)\.toBool\(\)' 1 '钩子位置约定：installed[1] = post-merge（恰好一处）'
arch_need "$SRC/src/app/AppModel.cpp" '\bEngineHook::parseStatus\b' '执行层走判定层解析钩子状态'
arch_need "$SRC/src/app/AppModel.cpp" 'void AppModel::loadHookStatus\(\)' 'AppModel 暴露查钩子状态'
arch_need "$SRC/src/app/AppModel.cpp" 'void AppModel::installHooksAll\(\)' 'AppModel 暴露装钩子'
arch_need "$SRC/src/app/AppModel.cpp" 'void AppModel::uninstallHooksAll\(\)' 'AppModel 暴露卸钩子'
arch_need "$SRC/src/ui/dialogs/panes/AutomationPane.cpp" 'm_model->installHooksAll\b' '自动化页有装钩子入口'
arch_need "$SRC/src/ui/dialogs/panes/AutomationPane.cpp" 'm_model->uninstallHooksAll\b' '自动化页有卸钩子入口'
arch_need "$SRC/src/main.cpp" '--hook-status-parse"' '无头入口可验钩子判定层'
arch_need "$SRC/src/app/SelfCheck.cpp" '\bEngineHook::parseStatus\b' 'SelfCheck 覆盖钩子判定层'
arch_forbid "$SRC/src/ui/dialogs/panes/AutomationPane.cpp" '\bEngineCli\b' '界面不自己调引擎（经 AppModel）'

# 新文件必须进了构建（漏登记 = 代码在仓里但没编进去）
for f in src/logic/ArchViewport.cpp src/logic/ArchReceipt.cpp src/logic/AgentToolPlan.cpp \
         src/logic/CodeGraphBuild.cpp src/ui/ArchCanvasWidget.cpp \
         src/ui/dialogs/ArchDialog.cpp src/ui/dialogs/CodeGraphDialog.cpp \
         src/logic/HeatLayout.cpp src/ui/HeatmapWidget.cpp \
         src/logic/PatchCheck.cpp src/ui/dialogs/PatchCheckDialog.cpp \
         src/logic/DocPages.cpp src/ui/dialogs/DocsDialog.cpp \
         src/logic/SyntaxHighlight.cpp src/ui/CodeHighlighter.cpp \
         src/logic/GraphInsight.cpp src/logic/EngineDoctor.cpp \
         src/logic/EngineConfig.cpp src/logic/IndexStatus.cpp \
         src/logic/CanvasFont.cpp; do
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
