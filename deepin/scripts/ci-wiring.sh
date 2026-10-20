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
# arch_need_any：盯「**任一** selfcheck 分片里都有这条判据」。
# ⚠ 为什么需要它（批 AJ 实测）：拆 SelfCheck.cpp 时，44 条门项红了 ——
#   它们盯的是「判据在 **SelfCheck.cpp 这个文件**里」，
#   而这些门项的**意图**是「**判据覆盖了某个判定层**」⇒ 与文件位置无关。
#   ⇒ 判据被搬到分片后，门红 ⇒ 门与结构耦合 ⇒ 逼着人「把代码搬回去」而不是「把门改对」。
#   ⚠ 强度**不变**：判据集合没变（ci.sh 的 SC_MIN 盯着条数）⇒
#   真删掉一条判据，这里照样红。
arch_need_any() { # arch_need_any <正则> <说明> [文件通配（相对 SRC，默认 src/app/SelfCheck*.cpp）]
    local re="$1" label="$2" glob="${3:-src/app/SelfCheck*.cpp}"
    ARCH_N=$((ARCH_N + 1))
    local hits
    hits="$(grep -lE -- "$re" "$SRC"/$glob 2>/dev/null | head -3 | sed "s|$SRC/||" | tr '\n' ' ')"
    if [ -n "$hits" ]; then
        echo "  ✓ $label"
    else
        echo "  ✗ $label：SelfCheck*.cpp 里都找不到 $re" >&2
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
# arch_need_count_in_fn：盯「**某个函数体内**恰好出现 N 次」。
# ⚠ 为什么还需要它（批 X 踩到，第九次「同名/子串互相顶替」）：
#   同一批属性名在一个文件里**合法地出现多处** ——
#   `requiredProperties()`（必填表）里列 IconPixmap/AttentionIconPixmap/OverlayIconPixmap，
#   `hostReadProperties()`（宿主会读的属性表）里**也**列这三个（实测宿主确实读它们），
#   平台层 `propertyValue()` 里三处 + PropertiesChanged 通知里两处。
#   ⇒ 全文计数（arch_need_count）必然 > 期望值 ⇒ 门恒红；
#   而如果把期望值调大到「全文次数」，变异掉「必填表里少一个」就**照样绿** —— 门被骗过。
#   ⇒ 必须把计数范围收窄到**具体那个函数体**：范围用「签名行（行首锚定）+ 花括号配平」切，
#   避免匹配到调用处（`g_item->propertyValue(...)`）而算错范围。
arch_need_count_in_fn() { # arch_need_count_in_fn <文件> <签名正则> <正则> <期望次数> <说明>
    local f="$1" sig="$2" re="$3" want="$4" label="$5"
    ARCH_N=$((ARCH_N + 1))
    if [ ! -f "$f" ]; then
        echo "  ✗ $label：文件不存在 $f" >&2
        ARCH_FAIL=1
        return
    fi
    local body got
    body="$(strip_comments "$f" | awk -v sig="$sig" '
        !started && $0 ~ sig { started = 1; depth = 0; seenb = 0 }
        started {
            t = $0
            ob = gsub(/\{/, "", t)
            cb = gsub(/\}/, "", t)
            depth += ob - cb
            print
            if (depth > 0) seenb = 1
            if (seenb && depth <= 0) exit
        }
    ')"
    if [ -z "$body" ]; then
        echo "  ✗ $label：$f 里找不到函数 $sig" >&2
        ARCH_FAIL=1
        return
    fi
    got="$(printf "%s\n" "$body" | grep -oE -- "$re" | grep -c . || true)"
    got="${got:-0}"
    if [ "$got" = "$want" ]; then
        echo "  ✓ $label"
    else
        echo "  ✗ $label：$f 的 $sig 函数体里 $re 出现 $got 次（期望 $want 次）" >&2
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
# arch_forbid_tree：盯「**整个源码树**里不该有的东西」。
# ⚠ 为什么不能只用单文件版 arch_forbid：同一个散落模式会出现在**另一个文件**里
#   （面板收编了、弹窗还留着）—— 单文件门全绿，毛病还在。
# ⚠ 必须剥注释再匹配：注释里提一嘴就红 ⇒ 门被「说明文字」顶替
#   （与「同名/子串互相顶替」同款，已累计 16 次）。
arch_forbid_tree() { # arch_forbid_tree <正则> <说明> <允许存在的文件…>
    local re="$1" label="$2"; shift 2
    ARCH_N=$((ARCH_N + 1))
    local allow=" $* "
    local bad=""
    for f in $(cd "$SRC" && find src \( -name '*.cpp' -o -name '*.h' \) | sort); do
        case "$allow" in *" $f "*) continue ;; esac
        if strip_comments "$SRC/$f" | grep -E -- "$re" >/dev/null; then
            bad="$bad $f"
        fi
    done
    if [ -n "$bad" ]; then
        echo "  ✗ $label：这些文件里还有 $re ——$bad" >&2
        ARCH_FAIL=1
    else
        echo "  ✓ $label"
    fi
}
# arch_forbid_han：盯「**文件里不许有中文**」（汉字与中文标点）。
#
# ⚠ 为什么不能只盯「某种写法」（arch_forbid 'QStringLiteral\('）：
#   盯**写法**能被 QString::fromUtf8("中文") / tr("中文") / 直接字面量绕开
#   ⇒ 门必须盯**内容**（字符本身），不是盯 API 名字。
#   ⚠ 教训：批 AA 的文档写「接线门盯 UI 里一个中文字面量都不许有」，
#     实际那道门盯的是 `QStringLiteral(` —— **说法比门宽** ⇒ 门有洞。
#
# ⚠ 必须剥**块注释**：单行版 strip_comments 只剥行注释（perl -pe 逐行）
#   ⇒ 块注释里的中文说明会**假红**（门一加就红 ⇒ 门会被当成噪音关掉）。
#
# ⚠ 范围要写清：这条门只管**文档窗**（四语言的那一块）。
#   其它 UI 里的中文属 M2-5（全应用 i18n，1008 串要人工翻译）——
#   ⚠ 不许拿「全应用禁中文」当已达成，那不是事实。
arch_forbid_han() { # arch_forbid_han <文件> <说明>
    local f="$1" label="$2"
    ARCH_N=$((ARCH_N + 1))
    if [ ! -f "$f" ]; then
        echo "  ✗ $label：文件不存在 $f" >&2
        ARCH_FAIL=1
        return
    fi
    if ! command -v perl >/dev/null 2>&1; then
        # ⚠ 没有 perl ⇒ 剥不掉块注释 ⇒ 硬跑会假红 ⇒ 显式 SKIP（不算通过）
        echo "  ‣ SKIP $label：没有 perl（剥不掉块注释，跑就是假红）"
        return
    fi
    # ⚠ 字节范围 U+3000–U+9FFF（中文标点 + 汉字 + 假名）：UTF-8 里是 E3–E9 开头
    if perl -0777 -pe 's{/\*.*?\*/}{}gs; s{(?<!:)(//)(?!:)[^\n]*}{}g' "$f" \
        | grep -q -P '[\x{3000}-\x{9fff}]'; then
        echo "  ✗ $label：$f 里还有中文（文案必须走判定层）" >&2
        ARCH_FAIL=1
    else
        echo "  ✓ $label"
    fi
}
# arch_forbid_text_dup：盯「**判定层已有的文案，界面层不许再抄一遍**」。
#
# ⚠ 为什么要有这道门（批 AH 实测）：同一个动作标签「下载并安装引擎」在
#   **三处**各写了一遍（首屏 1 + 设置页 2），悬停说明还**逐字**抄了两遍。
#   ⇒ 同一句话有两个真相源 ⇒ 改一处漏一处（批 AG 写的原话）。
#   ⚠ 盯**内容**（字面量逐字相同），不是盯 API 名字 —— 与批 AG 同款道理。
#
# ⚠ 清单来源是**判定层**（唯一真相源）：判定层改了文案，界面层的副本自动进清单
#   ⇒ 不需要手工维护名单（手工名单会漏，漏了就等于没门）。
# ⚠ 范围要写清：清单只取 `src/logic/EngineDownload.cpp`（本批的下载文案真相源），
#   且长度门槛 ≥4 个字符 ⇒ 短词（如「引擎」）不进清单，避免误伤。
#   其它判定层的中文串（失败分类文案等）**不在**本门范围里。
# arch_forbid_raw：盯「**连注释里也不许有的字样**」。
# ⚠ 为什么需要单独一个：arch_forbid 用 strip_comments（**剥行注释**）⇒
#   住在**注释里**的过时说法它永远看不见 ⇒ 门永远绿 ⇒ **空门**
#   （空门比没门更糟：给人虚假的安全感）。
#   ⇒ 盯「注释里的旧说法」时必须用这道**不剥注释**的门。
arch_forbid_raw() { # arch_forbid_raw <文件> <正则> <说明>
    local f="$1" re="$2" label="$3"
    ARCH_N=$((ARCH_N + 1))
    if [ ! -f "$f" ]; then
        echo "  ✗ $label：文件不存在 $f" >&2
        ARCH_FAIL=1
        return
    fi
    if grep -E -- "$re" "$f" >/dev/null; then
        echo "  ✗ $label：$f 里仍有 $re（连注释里也不许留）" >&2
        ARCH_FAIL=1
    else
        echo "  ✓ $label"
    fi
}
arch_forbid_text_dup() { # arch_forbid_text_dup <判定层文件> <相对SRC的目录> <说明>
    local srcf="$1" dir="$2" label="$3"
    ARCH_N=$((ARCH_N + 1))
    if [ ! -f "$srcf" ]; then
        echo "  ✗ $label：文件不存在 $srcf" >&2
        ARCH_FAIL=1
        return
    fi
    if [ ! -d "$SRC/$dir" ]; then
        echo "  ✗ $label：目录不存在 $SRC/$dir" >&2
        ARCH_FAIL=1
        return
    fi
    if ! command -v perl >/dev/null 2>&1; then
        # ⚠ 没有 perl ⇒ 取不出字面量清单 ⇒ 硬跑等于**假绿** ⇒ 显式 SKIP（不算通过）
        echo "  ‣ SKIP $label：没有 perl（取不出字面量清单，跑就是假绿）"
        return
    fi
    local tmp hits
    tmp="$(mktemp)"
    # 取判定层里所有**含中文**的字符串字面量（≥4 字符）
    perl -0777 -Mopen=':std,:encoding(UTF-8)' -ne \
        'while (/"([^"\n]{4,})"/g) { my $t = $1; print "$t\n" if $t =~ /[\x{3000}-\x{9fff}]/; }' \
        "$srcf" >"$tmp" 2>/dev/null || true
    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        echo "  ✗ $label：判定层里没取到任何中文字面量（清单为空 = 门形同虚设）" >&2
        ARCH_FAIL=1
        return
    fi
    # 扫界面层：先剥**块注释 + 行注释**（注释里提到这句话不算抄）
    hits="$(perl -e '
        use strict; use warnings;
        my $listfile = shift @ARGV;
        open(my $lf, "<:encoding(UTF-8)", $listfile) or exit 0;
        my @texts = grep { length($_) >= 4 } map { chomp; $_ } <$lf>;
        close $lf;
        binmode(STDOUT, ":encoding(UTF-8)");
        for my $f (@ARGV) {
            open(my $fh, "<:encoding(UTF-8)", $f) or next;
            local $/; my $body = <$fh>; close $fh;
            $body =~ s{/\*.*?\*/}{}gs;
            $body =~ s{(?<!:)(//)(?!:)[^\n]*}{}g;
            for my $t (@texts) {
                next unless index($body, $t) >= 0;
                print "$f\t$t\n";
            }
        }' "$tmp" $(find "$SRC/$dir" \( -name '*.cpp' -o -name '*.h' \) | sort) 2>/dev/null || true)"
    rm -f "$tmp"
    if [ -n "$hits" ]; then
        echo "  ✗ $label：界面层抄了判定层的文案（同一句话两个真相源）——" >&2
        printf '%s\n' "$hits" | sed 's/^/      /' >&2
        ARCH_FAIL=1
    else
        echo "  ✓ $label"
    fi
}
arch_need_any 'QStringLiteral\("graph"\).*QStringLiteral\("arch"\)' 'AppModel 调引擎 graph arch 取场景' 'src/app/AppModel*.cpp'
arch_need_any 'QStringLiteral\("scene"\)' '场景按 scene 契约格式取（--format scene）' 'src/app/AppModel*.cpp'
arch_need "$SRC/src/app/AppModel.h" '\bloadScene\b' 'AppModel 暴露 loadScene'
arch_need "$SRC/src/app/AppModel.h" '\bgenArch\b' 'AppModel 暴露 genArch（生成）'
arch_need "$SRC/src/app/AppModel.h" '\bexportArch\b' 'AppModel 暴露 exportArch（导出）'
# 生成/导出是**回执型命令**：stdout 是人话不是 JSON → 必须走 Text 契约。
# 拿 callJson 去收，exit==0 也会被判成「引擎输出不是合法 JSON」——成功报成失败。
arch_need_any 'callText\(\{ *QStringLiteral\("arch"\), *QStringLiteral\("gen"\)' 'genArch 走 Text 契约（callText）' 'src/app/AppModel*.cpp'
arch_need_any 'callText\(\{ *QStringLiteral\("render"\), *QStringLiteral\("arch"\)' 'exportArch 走 Text 契约（callText）' 'src/app/AppModel*.cpp'
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
arch_need_any 'QStringLiteral\("graph"\), *QStringLiteral\("tree"\)' 'AppModel 调引擎 graph tree 取文件骨架' 'src/app/AppModel*.cpp'
arch_need_any 'QStringLiteral\("graph"\), *QStringLiteral\("confidence"\)' 'AppModel 调引擎 graph confidence 取置信度' 'src/app/AppModel*.cpp'
arch_need_any 'QStringLiteral\("graph"\), *QStringLiteral\("functions"\)' 'AppModel 调引擎 graph functions 取函数级图谱' 'src/app/AppModel*.cpp'
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
arch_need_any '\bHeatLayout::layout\b' 'SelfCheck 覆盖铺排'
arch_need_any '\bHeatLayout::routes\b' 'SelfCheck 覆盖走线'

# 补丁体检链路：判定（PatchCheck 纯函数）→ 取数（工作区 diff + 引擎 patchconf）
#   → 接线（详情页入口 → 独立窗 → 人工裁决 → 合并终稿）
arch_need "$SRC/src/logic/PatchCheck.cpp" '\bparseLayer1\b' '判定层有 Layer1 解析'
arch_need "$SRC/src/logic/PatchCheck.cpp" '\bparseMerged\b' '判定层有终稿解析'
arch_need "$SRC/src/logic/PatchCheck.cpp" '\blowConfidenceEntities\b' '判定层有低置信度筛选'
arch_need "$SRC/src/logic/PatchCheck.cpp" '\bagentPayload\b' '判定层有裁决载荷生成'
arch_need "$SRC/src/logic/PatchCheck.cpp" '\bdiffSnippet\b' '判定层有 diff 抽实码'
arch_need_any 'QStringLiteral\("patchconf"\)' 'AppModel 调引擎 patchconf' 'src/app/AppModel*.cpp'
arch_need_any '\bworkingDiff\b' 'AppModel 取工作区 diff' 'src/app/AppModel*.cpp'
arch_need_any '\bmergePatchCheck\b' 'AppModel 有合并终稿动作' 'src/app/AppModel*.cpp'
arch_need "$SRC/src/ui/dialogs/PatchCheckDialog.cpp" '\bPatchCheck::lowConfidenceEntities\b' '窗经判定层取低置信度实体'
arch_need "$SRC/src/ui/dialogs/PatchCheckDialog.cpp" '\bPatchCheck::agentPayload\b' '窗经判定层生成裁决载荷'
arch_need "$SRC/src/ui/dialogs/PatchCheckDialog.cpp" '\bPatchCheck::diffSnippet\b' '窗经判定层抽实码'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" '\bpatchCheckRequested\b' '详情页发 patchCheckRequested'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&ProjectDetailPage::patchCheckRequested\b' 'PanelWindow 接了补丁体检入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" '\bshowPatchCheck\b' 'PanelWindow 有开补丁体检窗的动作'
arch_need "$SRC/src/ui/PanelWindow.cpp" '\bPatchCheckDialog\b' 'PanelWindow 用的是补丁体检窗'
arch_need_any '\bPatchCheck::parseLayer1\b' 'SelfCheck 覆盖 Layer1 解析'
arch_need_any '\bPatchCheck::diffSnippet\b' 'SelfCheck 覆盖 diff 抽实码'

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
arch_need_any '\bDocPages::content\b' 'SelfCheck 覆盖文档正文'

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
arch_need_any '\bSyntaxHighlight::highlight\b' 'SelfCheck 覆盖高亮分类'

# 图谱三件套链路：判定（GraphInsight：id→名字 / overview / symbol / impact）→
#   取数（引擎 graph overview / symbol / impact）→ 接线（代码图谱页关系页签 + 页头概览）
# ⚠ 引擎的 symbol / impact **只认符号名**：传 id 它返回空结果，看着像「没有影响面」。
arch_need "$SRC/src/logic/GraphInsight.cpp" '\bsymbolNameFromId\b' '判定层有「id 取名字」（引擎只认名字）'
arch_need "$SRC/src/logic/GraphInsight.cpp" '\bparseOverview\b' '判定层有概览解析'
arch_need "$SRC/src/logic/GraphInsight.cpp" '\bparseSymbol\b' '判定层有符号详情解析'
arch_need "$SRC/src/logic/GraphInsight.cpp" '\bparseImpact\b' '判定层有影响面解析'
arch_need_any 'QStringLiteral\("overview"\)' 'AppModel 调引擎 graph overview' 'src/app/AppModel*.cpp'
arch_need_any 'QStringLiteral\("impact"\)' 'AppModel 调引擎 graph impact' 'src/app/AppModel*.cpp'
arch_need_any 'QStringLiteral\("symbol"\)' 'AppModel 调引擎 graph symbol' 'src/app/AppModel*.cpp'
# ⚠ 盯**调用点**而不是方法名：方法定义还在时 grep 照样命中（这是第四次同类漏洞）。
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '^[[:space:]]*showImpact\(\);[[:space:]]*$' '关系页签真的调用了影响面（不是只定义了方法）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '\bGraphInsight::symbolNameFromId\b' '界面按名字问引擎（不传 id）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '\bloadOverview\b' '页头接了项目级概览'
arch_need_any '\bGraphInsight::symbolNameFromId\b' 'SelfCheck 覆盖 id→名字'

# 引擎自检（doctor）链路：判定（EngineDoctor 纯函数）→ 取数（引擎 doctor --json）
#   → 接线（设置·通用页「环境自检」卡）。
# ⚠ doctor **发现问题时退出码是 1**（自检必须能失败）但 stdout 仍是合法 JSON，
#   所以客户端必须**读载荷**判成败，不能按退出码。钉调用点。
arch_need "$SRC/src/logic/EngineDoctor.cpp" 'Report parse\b' '判定层有自检载荷解析'
arch_need "$SRC/src/logic/EngineDoctor.cpp" 'QString summary\b' '判定层有自检摘要'
arch_need "$SRC/src/logic/EngineDoctor.cpp" 'Tone toneOf\b' '判定层有自检档位映射'
arch_need "$SRC/src/app/AppModel.h" '\brunDoctor\b' 'AppModel 暴露 runDoctor'
arch_need "$SRC/src/app/AppModel.h" '\bdoctorFinished\b' 'AppModel 有自检回执信号'
arch_need_any 'QStringLiteral\("doctor"\)' 'AppModel 调引擎 doctor' 'src/app/AppModel*.cpp'
arch_need_any 'EngineDoctor::parse\(res\.payload->object\(\)\)' '自检读**载荷**判成败（不是按退出码）' 'src/app/AppModel*.cpp'
arch_need_any 'm_doctor = r\b' '自检结果落到 AppModel 成员' 'src/app/AppModel*.cpp'
# 接线：设置·通用页的「运行自检」钮 —— 盯**构造点**与**调用点**，不是「doctor 这个词出现过」。
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'new DPushButton\(QStringLiteral\("运行自检"\)' '设置页真的造了「运行自检」按钮'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'm_model->runDoctor\(\)' '「运行自检」真的调了引擎自检'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" '&AppModel::doctorFinished\b' '设置页接了自检回执'
arch_need "$SRC/src/ui/dialogs/AiSettingsDialog.cpp" 'new GeneralPane\(model,' '设置窗把模型传给了通用页'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'new AiSettingsDialog\(m_model,' '面板把模型传给了设置窗'
arch_need_any '\bEngineDoctor::parse\b' 'SelfCheck 覆盖自检解析'

# 进度报告（report）链路：取数（引擎 report，回执型命令）→ 回执路径提取
#   → 接线（详情页「导出报告」入口 + 报告卡）。
arch_need "$SRC/src/app/AppModel.h" '\bexportReport\b' 'AppModel 暴露 exportReport'
arch_need "$SRC/src/app/AppModel.h" '\breportExported\b' 'AppModel 有报告回执信号'
arch_need_any 'QStringLiteral\("report"\)' 'AppModel 调引擎 report' 'src/app/AppModel*.cpp'
arch_need_any 'callText\(\{ *QStringLiteral\("report"\)' 'report 走 Text 契约（callText，不是 callJson）' 'src/app/AppModel*.cpp'
# ⚠ 回执通道：引擎的 report 把回执写在 **stderr**（arch gen / render arch 才在 stdout）。
#   只认 stdout 的客户端会把「报告已生成」判成「引擎没有回执」—— 成功说成失败。
arch_need "$SRC/src/app/EngineCli.h" '\breceiptText\b' 'EngineCli 有回执通道（stdout 优先，空则 stderr）'
arch_need "$SRC/src/app/EngineCli.cpp" 'r\.receipt = EngineCli::receiptText\b' '回执走 receiptText（两路兜底）'
arch_need_any 'res\.receipt\b' 'Text 消费点读 receipt（不是 stdOut）' 'src/app/AppModel*.cpp'
# 引擎回执带 ANSI 颜色码（引擎不认 NO_COLOR）→ 显示前必须剥。
arch_need "$SRC/src/logic/ArchReceipt.cpp" 'QString plain\b' '判定层有剥 ANSI 的回执净化'
arch_need_any '\bEngineDoctor::checkLine\b' 'SelfCheck 覆盖自检行文'
arch_need_any '\bEngineCli::receiptText\b' 'SelfCheck 覆盖回执通道'
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
arch_need_any 'QStringLiteral\("config"\), *QStringLiteral\("list"\)' 'AppModel 调引擎 config list' 'src/app/AppModel*.cpp'
arch_need_any 'QStringLiteral\("config"\), *QStringLiteral\("set"\)' 'AppModel 调引擎 config set' 'src/app/AppModel*.cpp'
# ⚠ config set 是**回执型命令**（回执在 stderr）→ 必须走 Text 契约。
#   拿 callJson 去收，exit==0 也会被判成「引擎输出不是合法 JSON」—— 成功报成失败。
arch_need_any 'callText\(\{ *QStringLiteral\("config"\), *QStringLiteral\("set"\)' 'config set 走 Text 契约（callText）' 'src/app/AppModel*.cpp'
# 键白名单：客户端先拦一道，界面才不会给用户一个引擎根本不认的键。
arch_need_any 'EngineConfig::isWritable\(key\)' 'setEngineConfig 有键白名单' 'src/app/AppModel*.cpp'
# ⚠ `res.receipt` 在 AppModel 里有多处（架构图/索引/报告都读它）——
#   盯泛化的 `res\.receipt` 的话，摘掉配置这一处门照样绿。故盯到本行。
arch_need_any 'emit engineConfigSaved\(true, res\.receipt\);' '配置写入读 receipt（不是 stdOut）' 'src/app/AppModel*.cpp'
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
arch_need_any '\bEngineConfig::parse\b' 'SelfCheck 覆盖配置解析'
arch_need_any '\bEngineConfig::writableKeys\b' 'SelfCheck 覆盖可写键清单'

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
arch_need_any 'QStringLiteral\("index"\), *QStringLiteral\("overview"\)' 'AppModel 调引擎 index overview' 'src/app/AppModel*.cpp'
arch_need_any 'QStringLiteral\("index"\), *QStringLiteral\("update"\)' 'AppModel 调引擎 index update' 'src/app/AppModel*.cpp'
# ⚠ 「已最新」≠「已更新」：fresh 时引擎**什么都没重建**，界面不能说成「更新好了」。
arch_need_any 'if \(u\.fresh\)' '索引更新区分「已最新」与「已重建」' 'src/app/AppModel*.cpp'
# 接线：代码图谱页的「增量更新」钮 + 索引状态行。盯构造点与调用点。
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'QStringLiteral\("增量更新"\)' '代码图谱页真的造了「增量更新」按钮'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_model->updateIndex\(' '「增量更新」真的调了引擎 index update'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_model->loadIndexOverview\(' '代码图谱页真的读了索引状态'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '&AppModel::indexStatusChanged\b' '代码图谱页接了索引状态信号'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '&AppModel::indexUpdated\b' '代码图谱页接了索引更新结果'
arch_need "$SRC/src/main.cpp" '--index-status-parse\b' '无头 flag 能把索引概览判成值（契约门用）'
arch_need_any '\bIndexStatus::parseOverview\b' 'SelfCheck 覆盖索引概览解析'
arch_need_any '\bIndexStatus::parseUpdate\b' 'SelfCheck 覆盖索引更新解析'

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
arch_need_any '\bCanvasFont::parse\b' 'SelfCheck 覆盖字体解析'

# 批 N · 设计系统存量清零（DS 单一真相源）：四处散值收进 token，
#   D2 门上限降到 0，且门独立成 scripts/ci-d2.sh（负控能精确打）。
arch_need "$SRC/src/ui/DesignTokens.h" 'namespace FontPx\b' 'DS 有 QSS 字号 token（QSS 只能写字面量）'
arch_need "$SRC/src/ui/DualTrackButtons.cpp" '\bDS::FontPx::badge\b' '胶囊徽章字号走 token'
arch_need "$SRC/src/ui/common/Chip.h" '\bDS::FontPx::badge\b' '小标签字号走 token'
arch_need "$SRC/src/ui/common/MarkdownView.h" '\.arg\(DS::MD_H3\);' 'Markdown h4-h6 与 h3 同档（走 token）'
arch_need "$SRC/src/ui/pages/ProjectProgressCard.cpp" '\bDS::FontPx::code\b' '等宽项目名字号走 token'
arch_need_any '\bDS::FontPx::badge\b' 'SelfCheck 钉住 token 值'

# 批 N · 透明度入 token（色进了 DS 而 alpha 没进 = 同一语义散成 N 个真相源）
arch_need "$SRC/src/ui/DesignTokens.h" 'namespace Alpha\b' 'DS 有透明度 token'
arch_need "$SRC/src/ui/DesignTokens.h" '\baccentTintRgba\b' 'DS 提供 rgba 拼装（调用方不拼字面量）'
arch_need "$SRC/src/ui/dialogs/AgentDialog.cpp" '\bDS::accentTintRgba\b' '用户气泡底色走 token 拼装'
arch_need_any '\bDS::Alpha::accentTint\b' 'SelfCheck 钉住透明度 token'

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
arch_need_any 'SemColors::stale\(\)' 'SelfCheck 钉住唯一出处的值'
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
arch_need_any 'useSnapshotFixture' 'AppModel 提供夹具注入' 'src/app/AppModel*.cpp'
arch_need "$SRC/src/main.cpp" 'useSnapshotFixture\(\)' '快照走夹具（不走真引擎）'
# 取数与判定分层：夹具与引擎必须共用**同一段解析**，否则夹具测不到真路径
arch_need_any 'applyStatusPayload' '载荷应用抽成一层（夹具与引擎共用）' 'src/app/AppModel*.cpp'
arch_need_any 'applyDashboardPayload' '载荷应用抽成一层（夹具与引擎共用）' 'src/app/AppModel*.cpp'
arch_need_any 'applyMilestonesPayload' '载荷应用抽成一层（夹具与引擎共用）' 'src/app/AppModel*.cpp'
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
arch_need_any 'm_lastRefreshedMs = SnapshotFixture::fixedRefreshedMs\(\)' '快照刷新时刻用固定值（不用墙钟）' 'src/app/AppModel*.cpp'
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
arch_need_any '绝对日期锚定基准日' 'SelfCheck 钉住绝对日期锚定（跨天也抓得住）'
arch_need_any '刷新时刻固定' 'SelfCheck 钉住刷新时刻固定'
# 「重拍比字节」这道门盯的是**行为**（两次拍出同一张图），不是文件里的字样。
# ⚠ 精确计数：ci.sh 里 `cmp -s` 出现**四处**（批 AN 补齐了缺口）：
#   ① 比 git 基线（本次产物 vs 基线 ⇒ 视觉改动必须有人看过并提交）
#   ② 比基线（单次运行内的重拍）
#   ③ 比换时区那张（跨时区必须一致）
#   ④ **跨运行**（新进程再拍一次，比基线 ⇒ 抓跨进程漂移）
#   只拿掉一处时「出现过」照样绿 ⇒ 门被骗过（负控实测，第十五次「同名互相顶替」）。
#   ⚠ 第四处是批 AN 加的：前三处都在**同一次运行内**比 ⇒ 抓不到「有时拍出另一种字节」
#   的漂移（实测真发生过：同机并发下 4 种字节）⇒ 必须有跨进程那一处。
arch_need_count "$SRC/scripts/ci.sh" 'cmp -s' 4 'CI 有「重拍比字节」门（基线必须可重现，含跨运行复拍）'
# ⚠ 换时区那张必须挑**两个互相不同**的时区：拿「宿主时区」当其中一个时，
#   宿主恰好就是那个时区 ⇒ 两张必然相同 ⇒ 门永远绿（负控实测：宿主就是 Asia/Shanghai）。
arch_need "$SRC/scripts/ci.sh" 'America/New_York' 'CI 的跨时区对比用两个互不相同的时区'
# ⚠ **跨运行复拍**这一段必须留着（批 AN）：前两处 `cmp` 都在**同一次运行内**比，
#   抓不到「有时拍出另一种字节」的漂移 ⇒ 少了这一处，门就退回「只能抓单次运行内的漂」。
arch_need "$SRC/scripts/ci.sh" '跨运行复拍' 'CI 有「跨运行复拍」段（新进程再拍一次比基线）'
# ⚠⚠ **快照进程失败必须报出来**（批 AN 实测踩出来的盲点）：
#   ① `| tail -1` 的退出码是 **tail 的** ⇒ 快照进程退出码非 0 会被**静默吞掉**
#      ⇒ 拍出半张图也不报（拍出来是「空态」还是「失败态」分不清）。
#   ② `>/dev/null 2>&1` 把 **stderr 丢了** ⇒ 失败时**看不到原因**
#      ⇒ 下次再遇到只能从头猜（批 AN 查那个偶发失败查了很久就卡在这）。
#   ⇒ 门盯两件事：脚本里**不许**再用 `| tail -1` 接快照命令；**必须**有 stderr 落盘。
#   ⚠ 正则里的 `|` 在 grep -E 里是**或**、不是字面量 ⇒ 写成 `[|]`。
#   ⚠ 门项正则一律**单引号**（仓里的既有纪律：形式不许混）。
arch_forbid "$SRC/scripts/ci.sh" '--snapshot.*[|] *tail' '快照命令不许用「| tail -1」（管道退出码是 tail 的 ⇒ 失败被吞）'
arch_need "$SRC/scripts/ci.sh" 'stderr\.txt' '快照失败时 stderr 要落盘并打出来（否则只知道「失败」不知道「为什么」）'

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
arch_need_any '\bEngineDownload::releaseApiUrl\b' 'AppModel 走判定层取发布信息 URL' 'src/app/AppModel*.cpp'
arch_need_any 'void AppModel::downloadEngine\(\)' 'AppModel 暴露下载引擎' 'src/app/AppModel*.cpp'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'm_model->downloadEngine\b' '设置页有下载引擎入口'
arch_need "$SRC/src/app/EngineLocator.cpp" 'libexec/deepdolphin/moongit\b' '发现链认得下载链装的位置'
# ⚠ 用**精确计数**（两个调用点都要在）：`--engine-download` 在 main.cpp 出现两次
#   （contains 与 indexOf），只盯「出现过」时变异改掉其中一处门照样绿
#   （负控实测，第九次「同名/子串互相顶替」）。
arch_need_count "$SRC/src/main.cpp" 'QStringLiteral\("--engine-download"\)' 2 '无头入口可端到端验下载链（两个调用点都在）'
arch_need_any '\bEngineDownload::parseRelease\b' 'SelfCheck 覆盖下载判定层'
# 「同一件事只许一个出处」：发布信息 URL 只在判定层写一次。
# ⚠ 曾经给「界面」和「发现链」也加了同款 forbid —— 那是**空门**：
#   这两处根本没有写 URL 的机会（界面拿不到执行层、发现链不碰下载），
#   空门比没门更糟（给人虚假的安全感）。改成盯**真会发生的违规**。
arch_forbid "$SRC/src/app/EngineInstaller.cpp" 'api\.github\.com\b' '执行层不自己写发布信息 URL'
arch_forbid "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" '\bEngineInstaller\b' '界面不绕过 AppModel 直接用执行层'
arch_forbid "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" '\bEngineDownload::\b' '界面不自己读判定层（结论经 AppModel 传上来）'

# ── 批 AH · 引擎缺失首屏接上下载入口 + 安装指引文案归判定层 ──
#
# ⚠ 起因（实测）：引擎缺失时用户**第一眼**看到的是首屏，而下载链只在设置页
#   ⇒ 用户得先知道「设置里有」才用得上；首屏的提示还让人去跑仓库里的 install.sh
#   （拿 deb 的普通用户**没有那个仓库**）⇒ 指了一条走不通的路。
# ⚠ 这段盯四件事：
#   ① 判定层持有**全部**下载文案（真相源一处）；
#   ② AppModel 转发（界面不自己读判定层 —— 与 GeneralPane 同一纪律）；
#   ③ 首屏**真的有**下载入口且**接上了**下载链；
#   ④ 界面层**不许再抄**判定层的文案（同一句话两个真相源）。
arch_need "$SRC/src/logic/EngineDownload.h" 'QString installHint\(\);' '判定层持有引擎缺失时的安装指引文案'
arch_need "$SRC/src/logic/EngineDownload.h" 'QString downloadActionLabel\(\);' '判定层持有下载动作标签'
arch_need "$SRC/src/logic/EngineDownload.h" 'QString downloadActionTooltip\(\);' '判定层持有下载动作悬停说明'
arch_need "$SRC/src/logic/EngineDownload.h" 'QString downloadBusyLabel\(\);' '判定层持有下载中按钮文案'
arch_need "$SRC/src/logic/EngineDownload.h" 'QString downloadStatusText\(bool found, bool pending, bool downloading\);' '判定层持有引擎状态四态文案'
arch_need "$SRC/src/app/AppModel.h" 'QString engineDownloadActionLabel\(\) const' 'AppModel 转发下载动作标签'
arch_need "$SRC/src/app/AppModel.h" 'QString engineDownloadActionTooltip\(\) const' 'AppModel 转发下载动作悬停说明'
arch_need "$SRC/src/app/AppModel.h" 'QString engineDownloadBusyLabel\(\) const' 'AppModel 转发下载中按钮文案'
arch_need "$SRC/src/app/AppModel.h" 'QString engineStatusText\(\) const' 'AppModel 转发引擎状态说明'
arch_need "$SRC/src/app/AppModel.h" '\bEngineDownload::downloadStatusText\b' 'AppModel 的状态说明走判定层四态'
# ⚠ 首屏**真的有**下载入口：光有文案不算，用户得有地方点。
arch_need "$SRC/src/ui/pages/SetupGuidePage.cpp" 'new DPushButton\(downloadLabel' '首屏真的造了「下载并安装引擎」主操作按钮'
arch_need "$SRC/src/ui/pages/SetupGuidePage.h" 'void downloadClicked\(\);' '首屏发得出「点了下载」这个信号'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&SetupGuidePage::downloadClicked' '面板接了首屏的下载点击'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'm_model->downloadEngine\(\)' '首屏下载点下去真的跑下载链'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'engineDownloadActionLabel\(\)' '面板把判定层文案传给首屏（首屏不自己写）'
# ⚠ 首屏**不许**直接读判定层：与设置页同一纪律（结论经 AppModel 传上来）。
arch_forbid "$SRC/src/ui/pages/SetupGuidePage.cpp" '\bEngineDownload::\b' '首屏不自己读判定层（文案经 AppModel 传上来）'
arch_forbid "$SRC/src/ui/pages/SetupGuidePage.h" '\bEngineDownload::\b' '首屏头文件不自己读判定层'
# ⚠ **同一句话不许有两个真相源**（本批实测三处重复标签 + 两处逐字重复悬停说明）。
arch_forbid_text_dup "$SRC/src/logic/EngineDownload.cpp" 'src/ui' '界面层不许抄判定层的下载文案（标签/悬停/状态）'

# ── 批 AI · M1-4 收尾（通知显示时长可配）+ 通知顶替规则下沉判定层 ──
#
# ⚠ 起因：PLAN M1-4 的四个子项里三个已做（desktop-entry hint / image-path /
#   replaceId 顶替），只剩「timeOut 由 Settings 驱动」⇒ 硬编码 5000。
# ⚠ 顺带照出一处**说法与实现相反**：`Notifier.h` 头注释写着「每条通知独立送达、
#   互不顶替、**不用 replaceId**」—— 而实现一直**用着** replaceId 顶替状态型通知。
#   ⇒ 头注释是过时的（照批 AG 的教训：说法要与实现对齐，否则下一个人会照注释改代码）。
# ⚠ 顶替规则原来写在执行层（要 D-Bus 会话才跑得到 ⇒ 无头测不到）⇒ 下沉到判定层。
arch_need "$SRC/src/logic/Notifications.h" 'namespace Notifications [{]' '通知有判定层（顶替规则与时长归一一处）'
arch_need "$SRC/src/logic/Notifications.h" 'int normalizeTimeoutMs\(int ms\);' '判定层归一通知时长（0 = 永不消失，不能原样传）'
arch_need "$SRC/src/logic/Notifications.h" 'QString categoryOf\(const QString &title\);' '判定层判通知类别（状态型）'
arch_need "$SRC/src/logic/Notifications.h" 'bool replacesPrevious\(const QString &title\);' '判定层判「这条要不要顶替前一条」'
arch_need "$SRC/src/app/Notifier.cpp" '\bNotifications::replacesPrevious\b' '执行层的顶替判定走判定层'
arch_need "$SRC/src/app/Notifier.cpp" '\bNotifications::categoryOf\b' '执行层的类别判定走判定层'
arch_need "$SRC/src/app/Notifier.cpp" 'Settings::instance\(\)\.notifyTimeoutMs\(\)' '通知时长来自设置（不是硬编码）'
arch_need "$SRC/src/app/Settings.h" 'int notifyTimeoutMs\(\) const;' '设置层暴露通知时长'
arch_need "$SRC/src/app/Settings.h" 'void setNotifyTimeoutMs\(int ms\);' '设置层可写通知时长'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'm_notifyTimeout = new DComboBox' '设置·通用页有通知时长选择器'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'setNotifyTimeoutMs\(' '通知时长选择器真的写回设置'
arch_need_any '\bNotifications::normalizeTimeoutMs\b' 'SelfCheck 覆盖通知时长归一'
arch_need_any '\bNotifications::replacesPrevious\b' 'SelfCheck 覆盖通知顶替规则'
# ⚠ 时长不许再硬编码 5000（设置驱动）。
arch_forbid "$SRC/src/app/Notifier.cpp" '\.timeOut\(5000\)' '通知时长不许硬编码（由设置驱动）'
# ⚠ **过时说法不许复活**（头注释曾写「互不顶替、不用 replaceId」，与实现相反）。
#   ⚠ 这道门**不剥注释**（用 arch_forbid_raw）：过时说法住在注释里，
#   剥了就永远绿 ⇒ 又一个空门（空门比没门更糟）。
arch_forbid_raw "$SRC/src/app/Notifier.h" '不用 replaceId' 'Notifier 头注释不许再写「不用 replaceId」（与实现相反）'

# ── 批 AJ · 判据只许增不许减 + 拆掉 3800 行大函数（M4a 的第一步）──
#
# ⚠ 起因：① 「判据不许被删」这句话**从来没有门** —— ci.sh 只断言「≥58 passed」
#   ⇒ 删掉 300 条判据照样全绿；② `SelfCheck.cpp` 是**一个 3800 多行的函数**。
# ⚠ 拆分的**验收标准是「条数不变」，不是「编译通过」**（编译通过只证明没搬坏语法）。
#   ⇒ 拆分必须配一条「条数不许少」的门，两者一起才是完整验收。
arch_need "$SRC/scripts/ci.sh" 'SC_MIN=' 'ci.sh 有判据条数基线（判据只许增不许减）'
arch_need "$SRC/scripts/ci.sh" '有判据被删了' 'ci.sh 的判据基线**真会红**（不是摆设）'
# ⚠ 拆分基础设施：「记一条判据」**必须只有一份实现** ——
#   各分片各写一份 check() ⇒ 计数各数各的 ⇒ 汇总出来是错的
#   ⇒ 而且是「同名两处互相顶替」的老坑。
arch_need "$SRC/src/app/SelfCheckInternal.h" 'inline void check\(' '判据记录只有一份实现（共享底座）'
arch_need "$SRC/src/app/SelfCheckInternal.h" 'inline int g_pass' '判据计数是共享的（inline 变量，不各数各的）'
arch_forbid "$SRC/src/app/SelfCheckDocs.cpp" 'void check\(' '分片不许自己写一份 check（计数会各数各的）'
arch_forbid "$SRC/src/app/SelfCheckEngine.cpp" 'void check\(' '分片不许自己写一份 check（计数会各数各的）'
arch_forbid "$SRC/src/app/SelfCheckGraph.cpp" 'void check\(' '分片不许自己写一份 check（计数会各数各的）'
arch_need "$SRC/src/app/SelfCheckInternal.h" 'void checkDocs\(QStringList &log\);' '共享底座声明了文档页分片'
arch_need "$SRC/src/app/SelfCheckInternal.h" 'void checkEngine\(QStringList &log\);' '共享底座声明了引擎分片'
arch_need "$SRC/src/app/SelfCheckDocs.cpp" 'void checkDocs\(QStringList &log\)' '文档页分片真的实现了'
arch_need "$SRC/src/app/SelfCheckEngine.cpp" 'void checkEngine\(QStringList &log\)' '引擎分片真的实现了'
arch_need_any 'SelfCheckInternal::checkDocs\(log\)' '主片调用了文档页分片（不是把代码搬走就忘接）'
arch_need_any 'SelfCheckInternal::checkEngine\(log\)' '主片调用了引擎分片'
arch_need "$SRC/CMakeLists.txt" 'src/app/SelfCheckDocs\.cpp' '文档页分片已登记构建'
arch_need "$SRC/CMakeLists.txt" 'src/app/SelfCheckEngine\.cpp' '引擎分片已登记构建'

# ── 批 AK · M4a 第二步：图谱/热力图/补丁体检再拆一片（主文件降到 ~1450 行）──
arch_need "$SRC/src/app/SelfCheckInternal.h" 'void checkGraph\(QStringList &log\);' '共享底座声明了图谱分片'
arch_need "$SRC/src/app/SelfCheckGraph.cpp" 'void checkGraph\(QStringList &log\)' '图谱分片真的实现了'
arch_need "$SRC/src/app/SelfCheck.cpp" 'SelfCheckInternal::checkGraph\(log\)' '主片调用了图谱分片（不是把代码搬走就忘接）'
arch_need "$SRC/CMakeLists.txt" 'src/app/SelfCheckGraph\.cpp' '图谱分片已登记构建'
# ⚠ 判据夹具的**期望色值**在分片里 ⇒ D2 散值门必须**逐条登记豁免**（路径写错 ⇒ 门红），
#   否则「判据夹具豁免」这个约定会在拆分时静默失效（批 AJ 实测踩过）。
arch_need "$SRC/scripts/ci-d2.sh" 'src/app/SelfCheckGraph\.cpp\|keep' '图谱分片的判据夹具已登记 D2 豁免'

# ── 批 AM · M3c「响应式」两条：AgentDialog 可缩放 + KPI 网格的过时注释订正 ──
#
# ⚠ 起因（实测照出两处「说法与实现不是一回事」）：
#   ① PLAN §3c 写「KPI 网格按窗宽 1/2/4 列（`resizeEvent` 改写列数）」，
#      而 deepin 侧**根本没有 resizeEvent**（4 张卡写死在 2×2）；
#      且 mac 侧是**固定 4 列**（`macos/.../DetailViews.swift:902-903` `LazyVGrid(count:4)`）
#      ⇒ 「1/2/4」是 deepin 侧的提案，**无 mac 对位** ⇒ 不做，改校准 PLAN。
#   ② `DashboardPage` 的注释写着「宽 <980 由 resizeEvent 折 2 列」——**与实现相反**
#      （与批 AI 的 `Notifier.h` 同类：注释比实现还自信）⇒ 已订正 + 门盯住。
#   ③ `AgentDialog` 是全仓**最后一个**固定尺寸的对话框（其余 8 个都用 setMinimumSize），
#      而 AI 助手的回复一长就被裁掉 ⇒ 照同仓先例 `AiResultDialog.cpp:15` 改可缩放。
arch_forbid "$SRC/src/ui/dialogs/AgentDialog.cpp" 'setFixedSize\(' 'AI 助手对话框不许固定尺寸（长回复会被裁掉；同仓先例 AiResultDialog.cpp:15）'
arch_need_count "$SRC/src/ui/dialogs/AgentDialog.cpp" 'setMinimumSize\(' 1 'AI 助手对话框有最小尺寸（可放大、不可缩到读不了）'
arch_need_count "$SRC/src/ui/pages/DashboardPage.cpp" 'kpiGrid->addWidget' 4 'KPI 网格是 2×2 四卡（4 次入格）——将来做响应式时这条会红，提醒更新约定'
# ⚠ 过时说法不许复活（**不剥注释**：那句话住在注释里，剥了就永远绿 ⇒ 又一个空门）
arch_forbid_raw "$SRC/src/ui/pages/DashboardPage.cpp" '由 resizeEvent 折' 'DashboardPage 注释不许再写「由 resizeEvent 折」（代码里没有 resizeEvent）'
# ⚠ 定宽截断必须**用省略号**，不许硬裁（PLAN §3c「响应式」那条的另一半）。
#   ⚠ 实测：全仓 `elidedText` **零命中** ⇒ 这条此前完全没做；
#   侧栏项目名原来只 `setMaximumWidth(120)` ⇒ QLabel 默认**直接切掉后半截**（半个字、无提示）。
arch_need "$SRC/src/ui/SidebarNav.cpp" 'elidedText\(' '侧栏项目名定宽截断用省略号（不硬裁）'
arch_need "$SRC/src/ui/SidebarNav.cpp" 'setToolTip\(p\.name\)' '被省略的完整项目名可从 tooltip 看到'

# ── 批 AN · 快照基线「逐字节可重现」：关掉 DTK 标题栏阴影带 ──
#
# ⚠ 起因（实测照出「基线这道门其实形同虚设」）：
#   同一份代码在同机跑，**并发混主题**时 setupguide 段会拍出 **4 种字节**，
#   串行也有 ≈0.5% 概率出变体 ⇒ docs/snapshots 的基线会**悄悄漂**，
#   而 ci.sh 的「两次重拍逐字节一致」只在**单次运行内**比 ⇒ 跨运行的漂移它抓不到。
#
#   根因（逐层实测，不是猜的）：
#     ① 两张变体图逐像素 diff ⇒ 差异 **100% 集中在 y[50..69]**（带外 0 行不同）；
#     ② 那 20px 正是 DTK `DShadowLine` 画的**标题栏下沿阴影带**
#        （`DShadowLine::paintEvent` 读内嵌 SVG `titlebar_shadow_20px.svg`，
#          渐变 stop-opacity .1 → 0）；实测关掉阴影带后该区域变成纯背景色 ⇒ 坐实；
#     ③ SVG 渐变带在不同负载下**铺开的高度不同**（整条渐变被压短/拉长）
#        ⇒ 不是「还没画完」，是**渲染结果本身不确定** ⇒ 等多久都没用。
#
#   修法：快照路径调 `DMainWindow::setTitlebarShadowEnabled(false)`
#        （**公开** API：dmainwindow.h:108 public 段，不是私有符号 ⇒ DTK 升级不会断）。
#   为什么可以关：阴影带是**标题栏的装饰**，不承载任何信息；
#        基线的价值在「界面改了它会红」，装饰带的像素抖动只会制造**假红**。
#   ⚠ 门盯的是**「快照路径必须显式关掉它」**，不是「某个文件里有这句话」——
#     关的动作一旦被人删掉，基线立刻又开始漂 ⇒ 门必须红。
arch_need "$SRC/src/main.cpp" 'setTitlebarShadowEnabled\(false\)' '快照必须关掉标题栏阴影带（DTK 的 SVG 渐变渲染不确定 ⇒ 基线会漂）'
# ⚠ 拍前条件必须是「已停在首屏」而不是「等够 300ms」——
#   以前只在**拍完**才断言 showingSetupGuide()，偶发没切过去时报的是「重拍失败」
#   （假红），而本可以继续等它切过去 ⇒ 判据前移到拍前。
arch_need "$SRC/src/main.cpp" 'settle\.elapsed\(\) >= 300 && panel\.showingSetupGuide\(\)' 'setupguide 段拍前就要求「已停在首屏」（拍后断言保留作最后一道）'

# 批 Q · 引擎钩子（post-commit / post-merge 托管块）：判定层出结论，
#   执行层只管跑，界面只读结论。⚠ 卸载**只删托管块**（用户的钩子逻辑留着）——
#   这条一旦不成立，界面的「卸载」按钮就是删用户数据。
arch_need "$SRC/src/logic/EngineHook.h" 'namespace EngineHook [{]' '引擎钩子有判定层（结论一处）'
arch_need "$SRC/src/logic/EngineHook.cpp" 'parseStatus\(const QByteArray &json\)' '判定层解析 hook status 载荷'
arch_need_count "$SRC/src/logic/EngineHook.cpp" 'arr\.at\(0\)\.toBool\(\)' 1 '钩子位置约定：installed[0] = post-commit（恰好一处）'
arch_need_count "$SRC/src/logic/EngineHook.cpp" 'arr\.at\(1\)\.toBool\(\)' 1 '钩子位置约定：installed[1] = post-merge（恰好一处）'
arch_need_any '\bEngineHook::parseStatus\b' '执行层走判定层解析钩子状态' 'src/app/AppModel*.cpp'
arch_need_any 'void AppModel::loadHookStatus\(\)' 'AppModel 暴露查钩子状态' 'src/app/AppModel*.cpp'
arch_need_any 'void AppModel::installHooksAll\(\)' 'AppModel 暴露装钩子' 'src/app/AppModel*.cpp'
arch_need_any 'void AppModel::uninstallHooksAll\(\)' 'AppModel 暴露卸钩子' 'src/app/AppModel*.cpp'
arch_need "$SRC/src/ui/dialogs/panes/AutomationPane.cpp" 'm_model->installHooksAll\b' '自动化页有装钩子入口'
arch_need "$SRC/src/ui/dialogs/panes/AutomationPane.cpp" 'm_model->uninstallHooksAll\b' '自动化页有卸钩子入口'
arch_need "$SRC/src/main.cpp" '--hook-status-parse"' '无头入口可验钩子判定层'
arch_need_any '\bEngineHook::parseStatus\b' 'SelfCheck 覆盖钩子判定层'
arch_forbid "$SRC/src/ui/dialogs/panes/AutomationPane.cpp" '\bEngineCli\b' '界面不自己调引擎（经 AppModel）'

# ── 批 V · M1-7 平台层（后端分档 / 窗口激活 / 托盘弹窗定位 / 任务栏几何）─────
# 这一段盯的是**收口**类改动：光有「统一入口在」不够，还得盯住
#   ① 旧的散落写法**真的没了**（收敛类改动没有正向条目能抓）；
#   ② 平台层**真的调判定层**（不是自己又算一遍）；
#   ③ 判据/探针**真的接上了**（结论可离线测、动作有可见面）。
arch_need "$SRC/src/logic/Backend.h" 'namespace Backend [{]' '平台判定层有自己的命名空间'
# ⚠ token 边界：`enum class Kind` 后面必须跟 `{` —— 少了它，`enum class KindX`
#   照样被匹配（第十六次「子串互相顶替」的同款形态）。
arch_need "$SRC/src/logic/Backend.h" 'enum class Kind [{]' '平台判定层有后端分档枚举'
arch_need "$SRC/src/logic/Backend.cpp" 'Kind classify\(const QString &platformName\)' '后端分档判定有唯一入口'
arch_need "$SRC/src/logic/Backend.h" 'Activation activationFor\(Kind kind\)' '激活动作计划有唯一入口'
arch_need "$SRC/src/logic/Backend.h" 'Insets reservedInsets\(const QRect &screen, const QRect &available\)' '任务栏边距有唯一入口'
arch_need "$SRC/src/logic/Backend.h" 'PopupPlacement placePopup\(' '托盘弹窗落点有唯一入口'
arch_need "$SRC/src/logic/Backend.cpp" 'bool trayGeometryUsable\(const QRect &trayIconGeometry\)' '托盘几何可用性有唯一入口'

arch_need "$SRC/src/platform/Backend.h" 'using BackendKind = ::Backend::Kind;' '平台层用别名引用判定层分档（不重名遮蔽）'
arch_need "$SRC/src/platform/Backend.cpp" 'void activate\(QWidget \*w\)' '平台层有窗口激活入口'
# ⚠ **盯住具体那一行**：最小化恢复就靠这一行（`show()` 拉不回最小化窗口）。
#   盯「函数在」不够 —— 函数在而这一行没了，缺陷照样复发。
arch_need "$SRC/src/platform/Backend.cpp" '& ~Qt::WindowMinimized' '激活入口会先摘掉最小化位（show() 拉不回最小化窗口）'
arch_need "$SRC/src/platform/Backend.cpp" 'requestActivate\(\)' 'Wayland 分支走 requestActivate'
arch_need "$SRC/src/platform/Backend.cpp" 'QRect trayIconGeometry\(const QSystemTrayIcon \*icon\)' '托盘几何经平台层判可用性'
# 平台层必须**调判定层**出结论，不自己再算一遍（两处算法 = 两处真相）。
arch_need "$SRC/src/platform/Backend.cpp" 'Backend::placePopup\(' '平台层的弹窗落点走判定层'
arch_need "$SRC/src/platform/Backend.cpp" 'Backend::reservedInsets\(' '平台层的任务栏边距走判定层'
arch_need "$SRC/src/platform/Backend.cpp" 'Backend::classify\(' '平台层的后端分档走判定层'

arch_need "$SRC/src/tray/TrayPopupWindow.cpp" 'platform::trayPopupTarget\(' '托盘弹窗定位走平台层'
arch_forbid "$SRC/src/tray/TrayPopupWindow.cpp" 'QGuiApplication::screenAt' '托盘弹窗不再自己查屏幕（可用区由平台层给）'
arch_need "$SRC/src/tray/TrayController.cpp" 'platform::trayIconGeometry\(' '托盘入口的托盘几何经平台层判可用性'
arch_need "$SRC/src/tray/TrayGeometry.h" 'constexpr Backend::PopupGeometry popupGeometry\(\)' '弹窗定位参数由托盘域 token 打包（数值唯一出处）'
# ⚠ **盯数值不盯名字**：判据层与平台层必然出现这些**成员名**（参数形状），
#   盯名字会把「参数结构」也判成违规（第一版就踩了：门一上就红，红的是门自己）。
#   真正要防的是**数值另抄一份** ⇒ 盯「非零字面量赋给这几个成员」。
arch_forbid_tree '\b(dockGap|edgeMargin|fallbackDx|fallbackDy)\b[ ]*=[ ]*-?[1-9]' '弹窗定位 token 的数值只在托盘域出现（数值单一真相源）' src/tray/TrayGeometry.h
arch_need_count "$SRC/src/tray/TrayGeometry.h" 'g\.(dockGap|edgeMargin|fallbackDx|fallbackDy) = TrayGeometry::' 4 '弹窗定位参数四个值都从托盘 token 取（不是另抄一份）'

# ⚠ **激活只走统一入口**：整棵树里 `activateWindow()` 只许出现在平台层本身。
#   收编类改动最典型的失败是「改了一个文件，另一个文件还散着一份」。
arch_forbid_tree 'activateWindow\(\)' '窗口激活只走 platform::activate（散落的 activateWindow 已收口）' src/platform/Backend.cpp
arch_need_count "$SRC/src/ui/PanelWindow.cpp" 'platform::activate\(' 7 '面板的 7 处激活动作都走统一入口'
arch_need_count "$SRC/src/tray/TrayPopupWindow.cpp" 'platform::activate\(' 1 '托盘弹窗的激活动作走统一入口'
arch_forbid_tree '[^_a-zA-Z]raise\(\);' 'raise 不再散落在界面代码里（叠放次序归平台层）' src/platform/Backend.cpp

# 判据/探针可见面：结论可离线测、平台事实有可见面。
arch_need_any 'Backend::classify\(' 'SelfCheck 覆盖后端分档判定'
arch_need_any 'Backend::activationFor\(' 'SelfCheck 覆盖激活动作计划'
arch_need_any 'Backend::placePopup\(' 'SelfCheck 覆盖托盘弹窗落点'
arch_need_any 'Backend::reservedInsets\(' 'SelfCheck 覆盖任务栏边距'
arch_need "$SRC/src/main.cpp" 'backendKind=' '无头探针报出后端分档（平台事实可见）'

# ── 批 W · M1-8 Wayland 分支 + DDE 面板真几何 ──────────────────────
# 面板几何是**面板自己报的**（D-Bus），不是我们推算的；落点与失焦兜底都挂在这上面。
arch_need "$SRC/src/logic/PanelGeometry.h" 'namespace PanelGeometry [{]' '面板几何判定层有自己的命名空间'
# ⚠ token 边界：`enum class Edge` 后面必须跟 `{`（少了它，`enum class EdgeX` 照样匹配）
arch_need "$SRC/src/logic/PanelGeometry.h" 'enum class Edge [{]' '面板几何判定层有边枚举'
arch_need "$SRC/src/logic/PanelGeometry.cpp" 'Edge edgeFromPosition\(int position\)' '面板位置枚举到边的判定有唯一入口'
arch_need "$SRC/src/logic/PanelGeometry.h" 'QRect usableArea\(const QRect &screen, const Panel &panel\)' '扣掉面板后的可用区有唯一入口'
arch_need "$SRC/src/logic/PanelGeometry.h" 'QRect effectiveAvailable\(' 'QPA 可用区与面板真几何的合成有唯一入口'

arch_need "$SRC/src/platform/DdePanel.h" 'namespace DdePanel [{]' '面板取数层有自己的命名空间'
# ⚠ **盯住具体那一行**：QRect 的 (iiii) 只能靠 qdbus_cast 解档。
#   自己 `arg >> x >> y` 会走进 libdbus 的「type struct not a basic type」并 abort
#   （实测崩过一次）—— 换成别的写法就抓不到了。
arch_need "$SRC/src/platform/DdePanel.cpp" 'qdbus_cast<QRect>' '面板矩形用 qdbus_cast 解档（裸 >> int 会 abort）'
arch_forbid "$SRC/src/platform/DdePanel.cpp" 'QDBusArgument.*>>' '面板取数层不裸拆 D-Bus 结构体（会 abort）'
# ⚠ D-Bus 同步读必须有**超时**：面板服务卡住时不能把 GUI 线程一起卡住。
#   `QDBusInterface::property()` **没有**超时参数 ⇒ 禁用。
arch_need "$SRC/src/platform/DdePanel.cpp" 'QDBus::Block, 2000' '面板属性读带 2s 超时（不卡 GUI 线程）'
arch_forbid "$SRC/src/platform/DdePanel.cpp" 'QDBusInterface::property|\.property\(' '面板属性读不用无超时的 property()'

arch_need "$SRC/src/platform/Backend.cpp" 'DdePanel::current\(\)' '平台的落点用面板真几何'
arch_need "$SRC/src/platform/Backend.cpp" 'effectiveAvailable\(' '平台的可用区用面板真几何修正（Wayland 场景）'
arch_need "$SRC/src/platform/Backend.cpp" 'QCursor::pos\(\)' '托盘几何不可用时按光标所在屏定位'
arch_need "$SRC/src/logic/Backend.h" 'const PanelGeometry::Panel &panel =' '落点判定接面板参数'
arch_need "$SRC/src/tray/TrayPopupWindow.cpp" 'applicationStateChanged' '弹窗失焦收起有应用级兜底（Wayland 失焦事件可能不送）'
arch_need "$SRC/src/tray/TrayPopupWindow.cpp" 'Qt::ApplicationInactive' '兜底只在转成 Inactive 时收起（不误收刚弹出的窗）'
# ⚠ 兜底那一段必须**真拿得到** QGuiApplication（qobject_cast）——
#   只盯 `applicationStateChanged` 这个**字符串**不够：把守卫改成拿不到实例，
#   那行字还在，兜底却**永远不执行**（负控实测，第十九次同类问题）。
arch_need "$SRC/src/tray/TrayPopupWindow.cpp" 'qobject_cast<QGuiApplication \*>' '兜底拿得到 QGuiApplication（否则那段代码永远不跑）'
arch_need "$SRC/src/main.cpp" 'panelRect=' '无头探针报出面板矩形'
arch_need "$SRC/src/main.cpp" 'panelEdge=' '无头探针报出面板所在边'
arch_need "$SRC/src/main.cpp" 'trayPopupTarget=' '无头探针报出托盘弹窗落点'
arch_need_any 'PanelGeometry::usableArea\(' 'SelfCheck 覆盖面板可用区'
arch_need_any 'usedPanelGeometry' 'SelfCheck 覆盖面板感知落点'

# 新文件必须进了构建（漏登记 = 代码在仓里但没编进去）
for f in src/logic/ArchViewport.cpp src/logic/ArchReceipt.cpp src/logic/AgentToolPlan.cpp \
         src/logic/CodeGraphBuild.cpp src/ui/ArchCanvasWidget.cpp \
         src/ui/dialogs/ArchDialog.cpp src/ui/dialogs/CodeGraphDialog.cpp \
         src/logic/HeatLayout.cpp src/ui/HeatmapWidget.cpp \
         src/logic/PatchCheck.cpp src/ui/dialogs/PatchCheckDialog.cpp \
         src/logic/DocPages.cpp src/ui/dialogs/DocsDialog.cpp \
         src/ui/dialogs/DocsDialogProbe.cpp \
         src/logic/SyntaxHighlight.cpp src/ui/CodeHighlighter.cpp \
         src/logic/GraphInsight.cpp src/logic/EngineDoctor.cpp \
         src/logic/EngineConfig.cpp src/logic/IndexStatus.cpp \
         src/logic/CanvasFont.cpp src/logic/Backend.cpp src/logic/PanelGeometry.cpp \
         src/platform/Backend.cpp src/platform/DdePanel.cpp; do
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
# ⚠ 这里报的是**本段**的项数（批 X 段还没跑）⇒ 末尾那行才报**总项数**。
#   批 X 照出：文档里写的「N 项」原先**没法自证** —— 脚本自己报的那个数
#   是中途的计数，批 X 段又加了项却没报总账 ⇒ 「371 项」这种说法不可核。
#   ⇒ 末尾统一报总项数（见文件末尾）。
echo "✓ 接线完整（取数 → 判定 → 渲染 → 接线，前段 ${ARCH_N} 项）"

# ── 批 X · M1-3 SNI 托盘（DDE 只认 SNI；旧协议一个像素都不显示）──────
# 实测事实（批 X 照出来的，写进门项的依据）：
#   ① DDE 的 `_NET_SYSTEM_TRAY_S0` 选区**不存在** ⇒ 没有 XEmbed 宿主
#      ⇒ `QSystemTrayIcon` 在 DDE 上**一个像素都不显示**（全屏差分 0 像素）；
#   ② DDE 的 watcher 是 **ayatana 变体**（单参数注册 + 已注册项是属性 + ProtocolVersion 0）；
#   ③ 宿主注册后主动读 IconPixmap/AttentionIconPixmap/OverlayIconPixmap
#      —— **缺一个当场被注销**（实测：发 Unregistered）；
#   ④ Qt 6.8 的 `Q_PROPERTY` 导出在处理**外来进程**的 `Properties.Get` 时会**静默退出**
#      ⇒ 必须用 `QDBusVirtualObject`（`registerVirtualObject`）。
arch_need "$SRC/src/logic/TraySni.h" 'namespace TraySni [{]' 'SNI 判定层有自己的命名空间'
# ⚠ token 边界：`enum class Host` 后面必须跟 `{`（少了它 `enum class HostX` 照样匹配）
arch_need "$SRC/src/logic/TraySni.h" 'enum class Host [{]' 'SNI 判定层有 host 变体枚举'
arch_need "$SRC/src/logic/TraySni.h" 'enum class Registration [{]' 'SNI 判定层有注册方式枚举'
arch_need "$SRC/src/logic/TraySni.cpp" 'Host classifyHost\(const HostCaps &caps\)' 'host 变体判定有唯一入口'
arch_need "$SRC/src/logic/TraySni.h" 'Registration registrationFor\(Host host\)' '注册方式判定有唯一入口'
arch_need "$SRC/src/logic/TraySni.h" 'QString registrationArgument\(' '注册参数取值有唯一入口'
arch_need "$SRC/src/logic/TraySni.h" 'QStringList requiredProperties\(\)' '必填属性表有唯一入口'
arch_need "$SRC/src/logic/TraySni.h" 'QStringList missingRequired\(' '缺属性诊断有唯一入口'
arch_need "$SRC/src/logic/TraySni.h" 'QByteArray encodeArgb32NetworkOrder\(' '像素编码有唯一入口'

# ⚠⚠ **像素编码不许直接读原始字节**：`QIcon::pixmap().toImage()` 是**预乘**格式，
#   按非预乘去解释会读出一堆错值 ⇒ 整张图编成全 0 的透明图 ⇒ 宿主拿到空图就不画它
#   （实测踩过）。必须先 convertToFormat 再按 0xAARRGGBB 取值。
arch_forbid "$SRC/src/logic/TraySni.cpp" 'constScanLine' '像素编码不直接读原始字节（预乘图会读错）'
arch_need "$SRC/src/logic/TraySni.cpp" 'convertToFormat\(QImage::Format_ARGB32\)' '像素编码先转成非预乘 ARGB32'
arch_need "$SRC/src/logic/TraySni.cpp" 'argb\.pixel\(x, y\)' '像素编码按 0xAARRGGBB 取值（不依赖平台字节序）'

# ⚠⚠ **必须用 registerVirtualObject**：`registerObject` + `Q_PROPERTY` 那条路，
#   在处理**外来进程**的 Properties.Get 时会让进程静默退出（名字失去 owner ⇒ 被注销）。
arch_need "$SRC/src/platform/TraySni.cpp" 'registerVirtualObject' 'SNI 对象用 registerVirtualObject 导出'
arch_forbid "$SRC/src/platform/TraySni.cpp" 'registerObject' 'SNI 对象不用 registerObject（外来调用会静默退出）'
# 宿主注册后主动读这三个 pixmap 属性 ⇒ 缺一个当场被注销 ⇒ 三个都得暴露。
# ⚠ 计数范围**只取 requiredProperties() 函数体**：hostReadProperties() 里复用同一份表，
#   平台层也有同名字面量 ⇒ 全文计数必然对不上（第九次「同名互相顶替」）。
arch_need_count_in_fn "$SRC/src/logic/TraySni.cpp" '^[[:space:]]*QStringList requiredProperties\(\)' 'QStringLiteral\("IconPixmap"\)|QStringLiteral\("AttentionIconPixmap"\)|QStringLiteral\("OverlayIconPixmap"\)' 3 '判定层必填表里三个 pixmap 属性都在（缺一个当场被注销）'
arch_need "$SRC/src/logic/TraySni.h" 'QString primaryPixmapProperty\(\)' '主图标 pixmap 属性名有唯一入口'
# ⚠ 「宿主会读的属性表」必须**复用**必填表 —— 两张表各写一份时，
#   改了必填表忘了改读表 ⇒ 宿主读到一个我们没暴露的属性 ⇒ 当场被注销。
arch_need_count_in_fn "$SRC/src/logic/TraySni.cpp" '^[[:space:]]*QStringList hostReadProperties\(\)' 'requiredProperties\(\)' 1 '宿主会读的属性表复用必填表（改一张表不会漏另一张）'
# ⚠⚠ **pixmap 属性名只能有一处真相源**（判定层的必填表）：
#   平台层若自己再写一份「IconPixmap」字面量，两处迟早走偏 ——
#   改了一处忘了另一处 ⇒ 宿主按 introspect XML 找不到属性 ⇒ 当场注销我们
#   （真缺陷，且肉眼看代码极难发现：两个字符串长得一样）。
arch_need "$SRC/src/platform/TraySni.cpp" 'TraySni::requiredProperties\(\)' '平台层用判定层的必填属性表'
arch_forbid "$SRC/src/platform/TraySni.cpp" 'QStringLiteral\("IconPixmap"\)|QStringLiteral\("AttentionIconPixmap"\)|QStringLiteral\("OverlayIconPixmap"\)' '平台层不硬写 pixmap 属性名（真相源唯一）'
# ⚠ 平台层必须**逐个**暴露这三个属性（宿主读不到就注销）⇒ propertyValue() 里按必填表分发。
arch_need_count_in_fn "$SRC/src/platform/TraySni.cpp" '^[[:space:]]*bool propertyValue\(' 'pixProps\.contains\(prop\)' 1 '平台层按必填表逐个暴露三个 pixmap 属性（宿主读不到就注销）'
# introspect XML 必须**按必填表生成**三个 pixmap 声明（宿主按 XML 找属性，缺了直接不读）。
arch_need_count_in_fn "$SRC/src/platform/TraySni.cpp" '^[[:space:]]*QString introspect\(' 'TraySni::requiredProperties\(\)' 1 '平台层 introspect 按必填表生成三个 pixmap 声明'
# D-Bus 读必须带超时：`QDBusInterface::property()` 没有超时参数 ⇒ 禁用。
arch_need "$SRC/src/platform/TraySni.cpp" 'QDBus::Block, 2000' 'watcher 读带 2s 超时（不卡 GUI 线程）'
arch_forbid "$SRC/src/platform/TraySni.cpp" 'QDBusInterface::property|\.property\(' 'watcher 读不用无超时的 property()'
# 结构体签名推不出来 ⇒ 必须显式注册（否则 D-Bus 侧签名是空的）。
arch_need "$SRC/src/platform/TraySni.cpp" 'registerCustomType' '自定义结构体显式注册 D-Bus 签名'

# ⚠⚠ **托盘图标绘制必须用 QRect 重载**：`drawEllipse(qreal,qreal,qreal,qreal)` 的
#   前两个参数是**圆心**不是左上角 ⇒ 旧写法把圆画到画布外 ⇒ **图标一直是空白的**
#   （实测：中心像素 0x00000000；这跟平台无关，所有桌面都是空白图标）。
# ⚠ 门项盯「**两处**都是 QRect 重载」：只盯「至少有一处」的话，
#   把**其中一处**改回圆心语义（负控实测）门照样绿 ⇒ 门被骗过。
arch_need_count "$SRC/src/tray/TrayController.cpp" 'drawEllipse\(QRect\(' 2 '托盘图标用 QRect 重载画圆（int 重载是圆心语义）·两处都是'
arch_forbid "$SRC/src/tray/TrayController.cpp" 'drawEllipse\(TrayGeometry::icon' '托盘图标不按圆心语义画圆（会画到画布外）'

# SNI 与旧协议**二选一**：DDE 上旧的画不出来，两套并存等于多一个空图标。
arch_need "$SRC/src/tray/TrayController.cpp" 'platform::probeTraySni\(\)' '托盘控制器先探桌面是不是 SNI 托盘'
# ⚠ 「走哪条托盘路」必须**由判定层结论决定** —— 写死 true/false 都等于没探
#   （负控实测：把探针调用留着、但把判定写死，门照样绿 ⇒ 门被骗过）。
#   ⚠ 批 Y 起这层判定搬到 logic/DeepinTray 的 chooseBackend（deepin 选区优先于 watcher）
#   ⇒ 门项跟着改盯新入口（写死后端照样骗得过门）。
arch_need "$SRC/src/tray/TrayController.cpp" 'm_backend = TraySni::chooseBackend\(' '托盘后端由判定层结论决定（不写死）'
arch_forbid "$SRC/src/tray/TrayController.cpp" 'm_backend = TraySni::Backend::(Sni|DeepinWindow)' '托盘后端不许在控制器里写死（必须走判定层）'
arch_need "$SRC/src/tray/TrayController.cpp" 'platform::publishTraySni\(' 'SNI 模式经平台层发布'
arch_need "$SRC/src/platform/TraySni.h" 'TraySniStatus publishTraySni\(' 'SNI 发布有唯一入口'

# 判据/探针可见面
arch_need_any 'TraySni::classifyHost\(' 'SelfCheck 覆盖 host 变体判定'
arch_need_any 'TraySni::encodeArgb32NetworkOrder\(' 'SelfCheck 覆盖像素编码'
arch_need_any 'TraySni::requiredProperties\(' 'SelfCheck 覆盖必填属性表'
arch_need "$SRC/src/main.cpp" 'sniWatcher=' '无头探针报出 SNI watcher 状态'
arch_need "$SRC/src/main.cpp" 'sniHost=' '无头探针报出 host 变体'
arch_need_any 'typeToSignature' 'SelfCheck 覆盖 D-Bus 签名声明（不声明宿主会按 av 解）'

# ⚠⚠ **字节级判据只能放真机端到端探针**：`--selfcheck` 跑在 QApplication 构造之前
#   ⇒ 没有总线；且 `QDBusArgument` 一旦写入就是**只写**的 ⇒ 同一份数据读不回来
#   ⇒ 放 selfcheck 里只会得到一个「永远红/永远绿」的假判据。
#   ⇒ 探针必须**从总线另一端**（外部进程 gdbus）读 IconPixmap。
arch_need "$SRC/scripts/probe-sni-icon.sh" 'IconPixmap' '端到端探针脚本在（字节级判据放真机探针）'
# ⚠ 探针必须统计**整张图**的非零字节 —— 只看开头几行会误判：
#   圆形图标的**边缘像素本来就是透明的**（实测踩过：据此误判成「整张全 0」）。
arch_need "$SRC/scripts/probe-sni-icon.sh" '非零字节' '探针统计整张图非零字节（不靠肉眼看开头几行）'

# ⚠⚠⚠ **脚本必须以门的结果退出**（批 X 照出）：
#   批 X 的门项在「接线完整（…）」那段**之后**，而那段自己 `exit 1` ——
#   于是**批 X 的门项红了，脚本退出码仍是 0** ⇒ CI 里这一门**形同虚设**
#   （负控实测：门项明明打 ✗，判定却读成「没红」）。
#   ⇒ 末尾必须显式 `exit $ARCH_FAIL`。
if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 X 段有门项红（上面带 ✗ 的行）" >&2
    exit 1
fi
echo "✓ 批 X 段门项全绿（SNI 托盘）；门项合计 ${ARCH_N} 项（含前段）"

# ── 批 Y · M1-3 deepin 托盘**窗口协议**（DDE 25 真正的解法）──────────
# 实测事实（批 Y 查明，写进门项的依据）：
#   ① DDE 25 的托盘区画的是**应用自绘的 X11 窗口**，不是 SNI 图标；
#   ② 注册方式：向 `_NET_SYSTEM_TRAY_S0` 选区持有者发 ClientMessage
#      `_NET_SYSTEM_TRAY_OPCODE`，**`l[1]`=opcode(0)、`l[2]`=窗口 id**
#      —— **比经典 XEmbed 偏移一位**（照抄经典布局 ⇒ daemon 静默忽略）；
#   ③ 托管方是 dde-session-daemon（`org.deepin.dde.TrayManager1`），
#      它持有选区并维护 `TrayIcons` 属性；dock 插件读它并 reparent 图标窗口。
arch_need "$SRC/src/logic/DeepinTray.h" 'namespace TraySni [{]' 'deepin 托盘判定层有自己的命名空间'
arch_need "$SRC/src/logic/DeepinTray.h" 'enum class DockField [{]' 'dock 报文字段有独立枚举（不许散落数字）'
arch_need "$SRC/src/logic/DeepinTray.h" 'enum class Backend [{]' '托盘后端有独立枚举（三态）'
# ⚠⚠ **字段偏移是本协议最大的坑** ⇒ 门项必须盯死「opcode 在 1、窗口 id 在 2」。
arch_need "$SRC/src/logic/DeepinTray.h" 'return field == DockField::Opcode \? 1 : 2;' 'dock 字段偏移固定为 l[1]/l[2]（比经典 XEmbed 偏移一位）'
arch_need "$SRC/src/logic/DeepinTray.h" '_NET_SYSTEM_TRAY_S0' '选区名是 S0 变体（无后缀那个没有持有者）'
arch_need "$SRC/src/logic/DeepinTray.h" 'return 0;' 'dock 操作码是 0（REQUEST_DOCK）'
arch_need "$SRC/src/logic/DeepinTray.h" 'Backend chooseBackend\(' '后端选择有唯一入口'
# ⚠⚠ **后端选择的优先级**：deepin 选区在场 ⇒ 必须走窗口协议，**哪怕 watcher 也在**
#   （DDE 25 上 watcher 在但不画 SNI 图标 ⇒ 反着选 ⇒ 图标永远不出现；批 X 踩过）。
arch_need "$SRC/src/logic/DeepinTray.cpp" 'if \(deepinSelectionPresent\)' 'deepin 选区优先于 SNI watcher（选后端时先看选区）'
arch_forbid "$SRC/src/logic/DeepinTray.cpp" 'if \(watcherPresent\) \{\s*return Backend::Sni;' '后端选择不许「先看 watcher」（那会让 DDE 走错路）'

# 平台层：窗口 + 报文
arch_need "$SRC/src/platform/DeepinTray.h" 'DeepinTrayStatus publishDeepinTray\(' 'deepin 托盘发布有唯一入口'
arch_need "$SRC/src/platform/DeepinTray.cpp" 'xcb_get_selection_owner' '用 XGetSelectionOwner 查选区持有者（xprop 查不到选区）'
arch_need "$SRC/src/platform/DeepinTray.cpp" '_NET_SYSTEM_TRAY_OPCODE' '用 _NET_SYSTEM_TRAY_OPCODE 发 dock 请求'
arch_need "$SRC/src/platform/DeepinTray.cpp" 'dockFieldIndex\(TraySni::DockField::Opcode\)' 'opcode 的下标取自判定层（平台层不许写死数字）'
arch_need "$SRC/src/platform/DeepinTray.cpp" 'dockFieldIndex\(TraySni::DockField::WindowId\)' '窗口 id 的下标取自判定层（平台层不许写死数字）'
arch_forbid "$SRC/src/platform/DeepinTray.cpp" 'data\.l\[0\] = [^0]' 'ClientMessage 的 l[0] 不用（deepin 从 l[1] 读）'
# ⚠⚠ **`values[]` 的顺序必须按 mask 位升序** —— 写反了 ⇒ 32 位 ARGB 窗口
#   「建了却不存在」（GetWindowAttributes 报 BadWindow）⇒ daemon 认不出它。
arch_need "$SRC/src/platform/DeepinTray.cpp" 'XCB_CW_BORDER_PIXEL \| XCB_CW_EVENT_MASK \| XCB_CW_COLORMAP' '建窗的 value_mask 按位升序（values 顺序错 ⇒ 窗口建不出来）'
arch_need "$SRC/src/platform/DeepinTray.cpp" 'advertisedVisual' '用 daemon 广告的 _NET_SYSTEM_TRAY_VISUAL（协议要求）'
arch_need "$SRC/src/platform/DeepinTray.cpp" 'xcb_send_event' '发 dock 请求（ClientMessage）'
# 已建过就只重画 ⇒ 不许每次刷新都新建窗口（会攒一堆野窗口 + 反复 dock 请求）
# ⚠⚠ **第十次「同名多处互相顶替」**：`if (g_x11.window)` 在本文件里**出现两次**
#   （`closeX11` 的清理 + `publishDeepinTray` 的「已建过就只重画」）
#   ⇒ 全文匹配的话，把**清理那处**改坏门照样绿（负控实测）⇒ 必须钉到函数体。
#   ⚠ 而且本文件里**有两个同名 publishDeepinTray**（`#ifndef DD_HAVE_XCB` 的桩 +
#   真实现）⇒ 签名要**带参数名**才切得中真实现那处（否则先撞上桩）。
arch_need_count_in_fn "$SRC/src/platform/DeepinTray.cpp" '^DeepinTrayStatus publishDeepinTray\(const QImage &icon' 'if \(g_x11\.window\)' 1 '图标窗口只建一次（publishDeepinTray 里先判已存在）'

# 接线：托盘控制器按后端二选一
arch_need "$SRC/src/tray/TrayController.cpp" 'TraySni::chooseBackend\(' '托盘控制器按判定层结论选后端'
arch_need "$SRC/src/tray/TrayController.cpp" 'platform::publishDeepinTray\(' 'deepin 后端经平台层发布'
arch_need "$SRC/src/tray/TrayController.cpp" 'platform::updateDeepinTrayIcon\(' 'deepin 后端支持换图标'
# ⚠ **SNI 与窗口协议二选一**：DDE 上绝不能同时建 QSystemTrayIcon（旧协议一个像素都不显示）
arch_need "$SRC/src/tray/TrayController.cpp" 'm_backend == TraySni::Backend::DeepinWindow' 'deepin 后端单独一个分支（不与 SNI 并存）'

# 判据/探针可见面
arch_need_any 'dockFieldIndex' 'SelfCheck 覆盖 dock 字段偏移'
arch_need_any 'chooseBackend' 'SelfCheck 覆盖后端选择'
arch_need_any 'dockSelectionName' 'SelfCheck 覆盖选区名'
arch_need "$SRC/src/main.cpp" 'deepinTraySelection=' '无头探针报出 deepin 托盘选区状态'
arch_need "$SRC/scripts/probe-deepin-tray.sh" 'TrayIcons' '端到端探针在（判据放在真机探针）'
arch_need "$SRC/scripts/probe-deepin-tray.sh" 'WM_NAME' '端到端探针核 X 侧窗口名（不靠 daemon 侧那张表）'
arch_need "$SRC/scripts/probe-deepin-tray.sh" 'GetName' '端到端探针核 daemon 侧 GetName'

# ── 批 Y 补 · 托盘后端的**强制指定**（测试钩子）────────────────────────
# ⚠ 背景：DDE 25 上自动选的是 deepin 窗口协议 ⇒ **SNI 那条路走不到**
#   ⇒ 批 X 的「IconPixmap 字节级」端到端判据在 DDE 上**永远假红**（服务不上线）
#   ⇒ 必须有个显式强制的口子，探针才能在本机上仍然验 SNI 路径。
#   ⚠ 纪律：解析规则在**判定层**（纯函数）；平台层只读环境变量，不自己判值。
arch_need "$SRC/src/logic/DeepinTray.h" 'using BackendOverride = std::optional<Backend>;' '后端强制开关用 optional（None 是合法取值，不能拿它当哨兵）'
arch_need "$SRC/src/logic/DeepinTray.h" 'BackendOverride parseBackendOverride\(' '强制开关的解析在判定层（纯函数、可离线测）'
arch_need "$SRC/src/logic/DeepinTray.cpp" 'if \(forced\.has_value\(\)\)' '强制**优先于**自动选择（否则探针走不到要验的那条路）'
arch_need "$SRC/src/platform/TrayBackend.cpp" 'DEEPDOLPHIN_TRAY_BACKEND' '环境变量名只写一处（平台层）'
arch_need "$SRC/src/platform/TrayBackend.cpp" 'parseBackendOverride' '平台层不自己判值（解析在判定层）'
arch_need "$SRC/src/tray/TrayController.cpp" 'platform::trayBackendOverride\(' '控制器经平台层取强制开关'
# ⚠ **应用要自报走的后端** —— 探针的「强制生效了吗」只能靠这一行判
arch_need "$SRC/src/tray/TrayController.cpp" '托盘后端 =' '应用自报走的后端（探针盯这一段）'
arch_need "$SRC/scripts/probe-sni-icon.sh" 'DEEPDOLPHIN_TRAY_BACKEND=sni' 'SNI 探针强制走 SNI 那条路'
arch_need "$SRC/scripts/probe-sni-icon.sh" '托盘后端 = ' 'SNI 探针核对应用自报的后端（强制没生效 ⇒ 判据红）'
arch_need "$SRC/scripts/probe-deepin-tray.sh" 'deepin-window' 'deepin 探针核对自动选路的结果'
arch_need_any 'parseBackendOverride' 'SelfCheck 覆盖强制开关的解析'
# 构建登记：新文件必须编进去（漏登记 = 代码在仓里但没编）
for f in src/logic/DeepinTray.cpp src/logic/DeepinTray.h src/platform/DeepinTray.cpp src/platform/DeepinTray.h src/platform/TrayBackend.cpp src/platform/TrayBackend.h; do
    if ! grep -qE "(^|[[:space:]])$f([[:space:]]|$)" "$SRC/CMakeLists.txt"; then
        echo "  ✗ 构建未登记：$f" >&2
        ARCH_FAIL=1
    fi
done
arch_need "$SRC/CMakeLists.txt" 'find_path\(XCB_INCLUDE_DIR' 'xcb 用 find_path 找（pkg-config 解不开 Requires.private 链）'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 Y 段有门项红（上面带 ✗ 的行）" >&2
    exit 1
fi
echo "✓ 批 Y 段门项全绿（deepin 托盘窗口协议）；门项合计 ${ARCH_N} 项（含前段）"

# ── 批 AA · 固定文档页四语言 + 页内语言切换 ───────────────────────────
# 纪律（本批的判据来自这几条）：
#   · **文案全在判定层**：UI 里一个中文字面量都不许有（否则「四语言」只是
#     换了个标题，正文和按钮还是中文 ⇒ 中英混杂，比不做更糟）。
#   · **判定层零 UI 依赖**：`logic/DocPages` 不许碰 QWidget 家族，也不许碰 Settings
#     （解析在判定层、持久化在设置层、渲染在 UI 层，三层各管各的）。
#   · **不静默回落**：语言键认不出 ⇒ 判定层返回 nullopt；落地方案在
#     `resolveLanguage`（回落 + 标记），UI 据此说一句。
arch_need "$SRC/src/logic/DocPages.h" 'enum class Language' '判定层有文档语言枚举'
arch_need "$SRC/src/logic/DocPages.h" 'QVector<Language> languages\(\)' '判定层有语言清单（单一真相源）'
arch_need "$SRC/src/logic/DocPages.h" 'QString languageKey\(' '判定层出语言持久化 key'
arch_need "$SRC/src/logic/DocPages.h" 'std::optional<Language> languageFromKey\(' '认不出的语言返回 nullopt（不猜）'
arch_need "$SRC/src/logic/DocPages.h" 'LanguageResolution resolveLanguage\(' '判定层出语言解析方案（回落 + 标记）'
arch_need "$SRC/src/logic/DocPages.h" 'QString kindTitle\(Kind k, Language' '类目显示名按语言取'
arch_need "$SRC/src/logic/DocPages.h" 'QString content\(Kind k, Language' '正文按语言取'
# 16 篇正文常量（4 类 × 4 语言）—— 少了任何一篇，那个语言就是「回落成中文」
arch_need_count "$SRC/src/logic/DocPages.cpp" 'const char \*const k[A-Za-z]+ = R"MD\(' 16 '判定层有 16 篇正文（4 类 × 4 语言）'
arch_need_count "$SRC/src/logic/DocPages.cpp" 'const char \*const k[A-Za-z]+ZhCN = R"MD\(' 4 '四篇简体中文正文'
arch_need_count "$SRC/src/logic/DocPages.cpp" 'const char \*const k[A-Za-z]+En = R"MD\(' 4 '四篇英文正文'
arch_need_count "$SRC/src/logic/DocPages.cpp" 'const char \*const k[A-Za-z]+ZhTW = R"MD\(' 4 '四篇繁体中文正文'
arch_need_count "$SRC/src/logic/DocPages.cpp" 'const char \*const k[A-Za-z]+Ja = R"MD\(' 4 '四篇日文正文'
# 判定层纪律：零 UI 头、零设置层依赖
arch_forbid "$SRC/src/logic/DocPages.h" 'QWidget|QDialog|DDialog|DtkWidget|QPushButton|QComboBox' '判定层不许引入 UI 头（纯函数层）'
arch_forbid "$SRC/src/logic/DocPages.cpp" 'QWidget|QDialog|DDialog|QComboBox' '判定层不许碰 UI 控件'
arch_forbid "$SRC/src/logic/DocPages.cpp" 'Settings::|#include +"[^"]*Settings' '判定层不许碰设置层（解析在判定层、持久化在设置层）'
# UI 接线：语言选择器 + 按语言取 + 写回设置 + 外壳文案跟着换
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'QComboBox' '文档窗有语言选择器'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocPages::languageLabel' '语言项显示名来自判定层'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocPages::resolveLanguage' '语言解析走判定层（UI 不自己判值）'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocPages::content\(k, m_language\)' '正文按当前语言取'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocPages::kindTitle\(all\.at\(i\), m_language\)' '类目分段名按当前语言取'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocPages::windowTitle' '窗口标题按当前语言取'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'setButtonText' '按钮文字按当前语言换（不许留中文按钮）'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocPages::recoveredNotice' '语言键认不出时说一句（不静默吞掉）'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'setToolTip\(DocPages::languageSelectorTip' '语言选择器如实说明作用域（不承诺没做到的事）'
# ⚠ 写回设置必须**盯在「换语言」这个函数体里**：构造函数里也有一次
#   `setAppLanguageKey`（坏值自愈）—— 只盯「出现过」的话，摘掉换语言那次
#   照样绿（第十一次「同名互相顶替」）。
arch_need_count_in_fn "$SRC/src/ui/dialogs/DocsDialog.cpp" 'void DocsDialog::onLanguagePicked' 'setAppLanguageKey' 1 '换语言时写回设置（恰好一处）'
arch_need_count_in_fn "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocsDialog::DocsDialog\(QWidget \*parent\)' 'appLanguageKey' 1 '开窗时读设置里的语言（恰好一处）'
arch_need_count_in_fn "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocsDialog::DocsDialog\(QWidget \*parent\)' 'DocPages::resolveLanguage' 1 '语言解析走判定层（恰好一处）'
# ⚠ 外壳文案的两处「换」也盯函数体（否则摘掉其中一处，另一处会顶替）
arch_need_count_in_fn "$SRC/src/ui/dialogs/DocsDialog.cpp" 'void DocsDialog::applyLanguage' 'setButtonText\(0,' 1 '「关闭」按钮文字按语言换（恰好一处）'
arch_need_count_in_fn "$SRC/src/ui/dialogs/DocsDialog.cpp" 'void DocsDialog::applyLanguage' 'setButtonText\(i,' 1 '类目分段名按语言换（恰好一处）'
# ⚠ 文案不许写在 UI 里（四语言共用判定层那份）
arch_forbid "$SRC/src/ui/dialogs/DocsDialog.cpp" 'QStringLiteral\(' '文档窗不许自己写死文案（文案全在判定层）'
# 设置层：app.language 键
arch_need "$SRC/src/app/Settings.cpp" 'app\.language' '设置层有 app.language 键（与 mac UserDefaults 逐字对齐）'
arch_need "$SRC/src/app/Settings.h" 'appLanguageKey' '设置层暴露语言读写接口'
# 分段按钮要能改档位文字（否则换语言时分段名换不掉）
arch_need "$SRC/src/ui/common/SegmentedButton.h" 'setButtonText' '分段按钮支持改档位文字（语言切换用）'
# 判据覆盖
arch_need_any 'DocPages::resolveLanguage' 'SelfCheck 覆盖语言解析三态'
arch_need_any 'DocPages::languageFromKey' 'SelfCheck 覆盖「认不出 ⇒ nullopt」'
arch_need_any 'DocPages::languageKey' 'SelfCheck 覆盖语言 key 稳定性'
arch_need_any 'DocPages::kindTitle' 'SelfCheck 覆盖类目显示名按语言取'
# ── 批 AA 补 · 文档语言**行为**探针（接线门是源码扫描，证不了「界面真换了」）──
arch_need "$SRC/src/ui/dialogs/DocsDialog.h" 'QStringList probeValues\(\) const' '文档窗有只读呈现出口（探针要看实际呈现）'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'QStringList DocsDialog::probeValues\(\) const' '呈现出口有实现'
arch_need "$SRC/src/ui/dialogs/DocsDialogProbe.h" 'docsLangProbeReport' '探针文件在（机器格式归它，文档窗里不留字面量）'
arch_need "$SRC/src/ui/dialogs/DocsDialogProbe.cpp" 'box->setCurrentIndex\(i\)' '探针走**真实信号路径**（currentIndexChanged）'
arch_need "$SRC/src/ui/common/SegmentedButton.h" 'QString buttonText\(int id\) const' '分段按钮能读回档位名（探针要看分段名换了没有）'
arch_need "$SRC/src/main.cpp" 'headlessDocsLangProbe' 'main 有文档语言探针'
arch_need "$SRC/src/main.cpp" 'rawArgs.contains\(QStringLiteral\("--docs-lang-probe"\)\)' '无头分支认得 --docs-lang-probe（不然会落进 GUI 常驻，CI 挂死）'
arch_need "$SRC/src/main.cpp" 'QStandardPaths::setTestModeEnabled\(true\)' '探针隔离设置（切语言会写 app.language ⇒ 不许碰用户真实设置）'
arch_need "$SRC/scripts/ci-docs-lang-probe.sh" 'docs-lang-probe' '文档语言断言脚本在'
arch_need "$SRC/scripts/ci-docs-lang-probe.sh" 'grep -Pq' '断言脚本真查汉字（英文档回落成中文要能抓住）'
arch_need "$SRC/scripts/ci.sh" 'ci-docs-lang-probe\.sh' 'CI 真跑了这一门（脚本在但不跑 = 没有门）'
# ── 批 AG · 「文案全在判定层」这条纪律**要有牙**（批 AA 只盯了写法）──
# ⚠ 批 AA 写下的纪律是「UI 里一个中文字面量都不许有，接线门 arch_forbid 盯着」，
#   实际那道门盯的是 `QStringLiteral(` —— **说法比门宽**：
#   QString::fromUtf8("中文") / tr("中文") / 直接字面量都能绕过去。
# ⇒ 补一条**盯内容**的门（汉字/中文标点本身），让纪律与门对齐。
# ⚠ 范围只在**文档窗**（四语言的那一块）：其它 UI 的中文属 M2-5（人工翻译），
#   那是「待做」，不是「已达成」—— 不许在这里写成已达成。
arch_forbid_han "$SRC/src/ui/dialogs/DocsDialog.cpp" '文档窗不许有中文字面量（盯内容，不是盯写法）'
arch_forbid_han "$SRC/src/ui/dialogs/DocsDialog.h" '文档窗头文件不许有中文字面量'
arch_forbid_han "$SRC/src/ui/dialogs/DocsDialogProbe.cpp" '文档窗探针不许有中文字面量（机器格式）'
arch_forbid_han "$SRC/src/ui/dialogs/DocsDialogProbe.h" '文档窗探针头不许有中文字面量'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 AA 段有门项红（上面带 ✗ 的行）" >&2
    exit 1
fi
echo "✓ 批 AA 段门项全绿（固定文档页四语言）；门项合计 ${ARCH_N} 项（含前段）"
exit 0
