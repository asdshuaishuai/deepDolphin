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
# ⚠ 仓根（`macos/` 与 `deepin/` 同仓）—— 跨目录盯 mac 侧的源码门用它。
ROOT="$(cd "$SRC/.." && pwd)"

# ⚠⚠⚨ 批 CG · **剥注释失败**必须被看见（工具失败 ≠ 没找到）。
#   ⇒ 管道里**拿不到** strip_comments 的退出码（管道退出码 = 最右命令的）
#   ⇒ 而「输出为空」与「工具失败」在下游**长得一模一样** ⇒
#     · forbid 门会判「没找到」⇒ **静默变绿**（假绿）
#     · count 门会判「出现 0 次」⇒ **红，但诊断指错方向**（批 CE 纪律：诊断不许失真）
#   ⇒ ⚠⚠⚨ **实测的洞**：一个装着真实违例的源文件，只要对工具**不可读**
#   ⇒ 违例对门来说等于**不存在** ⇒ 整条接线门 **rc=0 全绿**
#     （实测：探针文件放 `src/logic/` 且 chmod 000 ⇒ 违例 `raise();` 完全没被看见）。
#   ⇒ 批 BI 实测：落盘写法比管道慢 20 倍（30ms vs 1.5ms）⇒ 2511 次 ⇒ 84 秒
#   ⇒ CI 不可接受；「懒探测」又只验「工具活着」，盖不住**这一次调用**失败。
#   ⇒ 现在：**失败时才留标记**（跨子 shell ⇒ 必须用文件，变量传不出去）
#   ⇒ 正常路径**零开销**；脚本末尾统一检查 ⇒ 有 ⇒ 判红 + 指名道姓。
#   ⚠ `$$` 在**子 shell 里是同一个值**（POSIX）⇒ 管道里的失败也写得到同一个文件。
STRIP_FAIL_FILE="${TMPDIR:-/tmp}/deepdolphin-strip-fail.$$"
trap '_ch_rc=$?; if [ -s "$STRIP_FAIL_FILE" ]; then echo "✗ 剥注释失败（工具失败 ≠ 没找到）——这些文件的匹配结果**不可信**：$(sort -u "$STRIP_FAIL_FILE" | tr "\n" " ")" >&2; _ch_rc=1; fi; rm -f "$STRIP_FAIL_FILE"; exit $_ch_rc' EXIT

# ⚠⚠⚨ 批 CF · 剥注释口径的**前提**是 perl 在（默认分支靠它剥 C++ 的 `//` 注释）。
#   ⇒ 以前 perl 缺席时会**静默降级**到 sed 兜底 ⇒ **口径变了**
#     （sed 兜底会把 `https://…` 整段剥掉，perl 口径不会）。
#   ⇒ 那时**门侧与审计器不再同口径**（批 AS：同一条命令、不复刻）⇒ 判定不可信，
#     而且**没有任何一条消息说「perl 缺失」** ⇒ 排障方向被带偏（批 CE 纪律：诊断不许失真）。
#   ⇒ 现在：缺 perl ⇒ **响亮失败**（工具失败 = 没验过；与批 CB/CC/CD/CE 同款口径：
#     **未验证不许被当成通过**）。
command -v perl >/dev/null 2>&1 || {
    echo "✗ 没有 perl（剥注释工具）⇒ 判据口径无法确定 ⇒ **未验证不许被当成通过**" >&2
    exit 1
}

# 剥注释再匹配：注释里出现的字样不算接线（否则加一行注释就能骗过门）。
# ⚠ **按文件类型分派**：C++ 源文件是 `//`，shell 脚本是 `#`。
#   以前只有 C++ 版 → 扫 ci.sh 时**整份脚本的 `#` 注释都留着**，
#   于是「注释里提过 ci-d2.sh」被当成「ci.sh 调了 ci-d2.sh」→ 门被骗过（负控实测）。
strip_comments() {
    # ⚠⚠⚨ 批 CG · **读不了**必须**先验**（不是靠工具的退出码！）
    #   ⇒ ⚠⚠⚨ **实测**：perl 打不开文件时**退出码仍是 0**（只往 stderr 打一句
    #     "Can't open …: 权限不够"）⇒ **靠退出码抓不住「读不了」**
    #     （对照：sed 读不了是 2、grep 读不了是 2 ⇒ 只有 perl 是 0）
    #   ⇒ 所以必须**先验可读性**（批 CD / 批 CE 同款口径：扫描之前先验）
    #   ⇒ 失败 ⇒ **写标记文件**（跨子 shell ⇒ 必须用文件，变量传不出去）
    #   ⇒ 正常路径**零开销**；脚本末尾统一检查 ⇒ 有 ⇒ 判红 + 指名道姓。
    if [ ! -r "$1" ]; then
        printf '%s\n' "$1" >> "$STRIP_FAIL_FILE"
        return 1
    fi
    case "$1" in
    *.sh|*.txt|*.py)
        # ⚠⚠⚨ 批 CG：失败**必须被看见**（工具失败 ≠ 没找到）
        #   ⇒ 失败 ⇒ **写标记文件**（跨子 shell ⇒ 必须用文件，变量传不出去）
        #   ⇒ 正常路径**零开销**；脚本末尾统一检查 ⇒ 有 ⇒ 判红 + 指名道姓。
        # ⚠⚠⚨ **批 CP · 141 = SIGPIPE**（消费者**提前收工**）⇒ **不是「工具坏了」**
        #   ⇒ 以前把 141 也当成「剥注释失败」⇒ 记标记 ⇒ 末尾判红 ⇒ ⚠⚠⚨ **假红**
        #     （批 BS 纪律：假红比假绿更坏 ⇒ 逼人把承诺改弱）
        #   ⇒ ⚠⚠⚨ **实测的引爆点**：`arch_need_count_in_fn` / `arch_need_count_in_step`
        #     的 awk 读完函数体/步正文就 `exit` ⇒ sed 还在写 ⇒ 被 SIGPIPE 打断
        #     ⇒ ⚠ **门项文件越写越大 ⇒ 越容易触发** ⇒ 这是颗**时间炸弹**
        #   ⇒ 现在：141 一律**不算工具失败**（那些消费者**故意**只取一部分 ⇒
        #     截断是预期的）⇒ 其余非 0（sed/perl 崩了、文件读不了）⇒ 照旧判红。
        sed -e 's/^[[:space:]]*#.*$//' "$1"
        _strip_rc=$?
        if [ "$_strip_rc" -ne 0 ] && [ "$_strip_rc" -ne 141 ]; then
            printf '%s\n' "$1" >> "$STRIP_FAIL_FILE"
            return 1
        fi
        ;;
    *)
        # ⚠ `(?<!:)` 排除 `://` —— 否则字符串里的 URL（https://…）
        #   会被当成行注释整段剥掉，门就看不见它了（负控实测）。
        # ⚠⚠⚨ 批 CF：**不再静默降级** —— 以前 perl 缺席就换 sed 兜底 ⇒ **口径变了**
        #   ⇒ 门侧与审计器不再同口径（批 AS）⇒ 同一个门项两边可能**结论相反**
        #   （实测：同一份源码、同一个门项 ⇒ ci.sh 口径命中 0、ci-wiring.sh 口径命中 1）。
        #   ⇒ 顶层已 preflight「perl 必须存在」⇒ 这里缺 perl 属于**不可能状态**；
        #   ⇒ **不许换个口径蒙混过关**。
        # ⚠⚠⚨ **不要在这个函数体里写独占一行的 `}`** ——
        #   `ci.sh` / `ci-d2.sh` 按 `sed -n '/^strip_comments() {/,/^}/p'` 抽取本函数
        #   ⇒ 独占的 `}` 会让它们**抽到残缺函数** ⇒ 那两处的抽取自检会当场红。
        # ⚠⚠⚨ 批 CG：失败**必须被看见**（工具失败 ≠ 没找到）—— 同上。
        # ⚠⚠⚨ 批 CP：141（SIGPIPE，消费者提前收工）**不算工具失败** —— 同上。
        perl -pe 's{(?<!:)(//)(?!:).*$}{}' "$1"
        _strip_rc=$?
        if [ "$_strip_rc" -ne 0 ] && [ "$_strip_rc" -ne 141 ]; then
            printf '%s\n' "$1" >> "$STRIP_FAIL_FILE"
            return 1
        fi
        ;;
    esac
}


# ⚠ 剥注释工具的存活状态（懒探测 ⇒ 第一次用到时探一次）。
# ⚠ **不带引号赋值** ⇒ 不会混进「三态赋值只有一份」那条门的计数里。
PROBE_STRIP_ALIVE=1
PROBE_STRIP_CHECKED=0

# ⚠⚠⚠ probe_scan_find / probe_scan_state_of / probe_scan_report：
#   forbid 家族共用的「查找 + 三态判定」（**判定只有一份**）。
#
# 【为什么要有它 —— 实测取证，不是推演（批 BI）】
#   forbid 门判的是「**不该有的东西没了**」⇒ 目标串出现 >0 本来就红
#   ⇒ ⚠⚠⚠ **「没找到」是常态、是绿** ⇒ **工具坏了也长成「没找到」的样子**
#   ⇒ 工具一坏 ⇒ 门**静默变绿** ⇒ 门形同虚设（比没门更糟：给人虚假的安全感）。
#   ⚠ **实测（批 BI 可复现）**：把「剥注释」的 perl 改成语法错误
#     ⇒ 被盯的文件里**确实有中文** ⇒ 门仍输出「✓」⇒ 接线门 rc=0 ⇒ CI 全绿。
#
# 【三态】
#   found  = 找到了 ⇒ forbid ⇒ **红**
#   absent = 没找到 ⇒ **绿**
#   broken = **工具坏了** ⇒ **红**（⚠ 绝不能绿：工具坏了 ≠ 没找到）
#   missing = 文件不存在 ⇒ **红**
#
# 【为什么叫 probe_ 而不是 arch_】
#   `arch_` 开头的是**门项** ⇒ 审计器按行首 `arch_` 数门项的**物理行数**
#   ⇒ 辅助代码里若出现 `arch_xxx ` 就会被**算成门项** ⇒ 门项总数基线漂。
#   ⇒ 辅助函数一律用 `probe_` 前缀。
#
# ⚠ **退出码口径统一成 grep/perl 的同一套**：0 = 命中；1 = 没命中；其它 = 工具坏了。
#   ⇒ 6 个 forbid 门（连同走 perl 的中文门与文案重门）都能走同一套判定。
probe_scan_state_of() { # probe_scan_state_of <退出码> ⇒ 设 PROBE_SCAN_STATE
    case "$1" in
    0) PROBE_SCAN_STATE="found" ;;
    1) PROBE_SCAN_STATE="absent" ;;
    *) PROBE_SCAN_STATE="broken" ;;
    esac
}

# probe_scan_find：查一个文件（可剥注释、可压行）⇒ 设 PROBE_SCAN_STATE。
# 用法：probe_scan_find <文件> <正则> <ml:0|1> <raw:0|1>
# probe_strip_alive：剥注释工具（perl 那一支）**自己还活着吗**？
# ⚠ 为什么需要它（批 BI 的实测结论）：
#   管道里**看不见**剥注释工具的退出码 ⇒ 工具坏了 ⇒ 输出为空 ⇒ 看着像「没找到」
#   ⇒ **静默绿**。而落盘写法虽能看见退出码，却比管道慢 20 倍（实测 30ms vs 1.5ms）
#   ⇒ 2511 次调用 ⇒ 84 秒 ⇒ CI 不可接受 ⇒ 只能走管道 ⇒ 用探测兜住。
# ⚠ 探测用**同一个** strip_comments ⇒ 有人把剥注释的正则改坏 ⇒ 探测当场失败。
probe_strip_alive() { # probe_strip_alive ⇒ 0 = 活着
    local d f
    d="$(mktemp -d)"
    f="$d/probe.cpp"
    printf 'int x; // c\n' >"$f"
    if strip_comments "$f" >/dev/null 2>&1; then
        rm -f "$f"
        rmdir "$d" 2>/dev/null
        return 0
    fi
    rm -f "$f"
    rmdir "$d" 2>/dev/null
    return 1
}
probe_scan_find() { # probe_scan_find <文件> <正则> <ml> <raw>
    local f="$1" re="$2" ml="$3" raw="$4"
    local rc
    PROBE_SCAN_STATE=missing
    if [ ! -f "$f" ]; then
        return
    fi
    # ⚠⚠⚠ **剥注释工具的存活探测**（批 BI 性能修正后的补丁）：
    #   管道下**看不见**剥注释工具的退出码（管道退出码 = 最右命令的）
    #   ⇒ 剥注释工具坏了 ⇒ 输出为空 ⇒ 「没找到」⇒ **静默绿**（批 BI 的洞）。
    #   ⇒ 这里**懒探测一次**：脚本是短命的 ⇒ 一次探测覆盖全脚本。
    #   ⚠⚠ **实测**：落盘到 tmpfs 比管道慢 20 倍（30ms vs 1.5ms/次）
    #   ⇒ 2511 次调用 ⇒ 84 秒 ⇒ CI 不可接受 ⇒ 只能走管道 ⇒ 只能靠探测兜。
    if [ "$raw" != "1" ] && [ "$PROBE_STRIP_CHECKED" != "1" ]; then
        PROBE_STRIP_CHECKED=1
        if ! probe_strip_alive; then
            PROBE_STRIP_ALIVE=0
        fi
    fi
    if [ "$raw" != "1" ] && [ "$PROBE_STRIP_ALIVE" != "1" ]; then
        PROBE_SCAN_STATE=broken
        return
    fi
    if [ "$raw" = "1" ]; then
        grep -E -- "$re" "$f" >/dev/null 2>&1
        rc=$?
    elif [ "$ml" = "1" ]; then
        strip_comments "$f" | tr '\n' ' ' | grep -E -- "$re" >/dev/null 2>&1
        rc=$?
    else
        strip_comments "$f" | grep -E -- "$re" >/dev/null 2>&1
        rc=$?
    fi
    probe_scan_state_of "$rc"
}

# probe_scan_report：单文件版呈现（**三态 ⇒ 结论的翻译只有一份**）。
# 用法：probe_scan_report <状态> <文件> <正则> <说明> <命中时的补充说明>
probe_scan_report() { # probe_scan_report <状态> <文件> <正则> <说明> <补充>
    local st="$1" f="$2" re="$3" label="$4" extra="$5"
    case "$st" in
    found)
        echo "  ✗ $label：$f 里仍有 $re（$extra）" >&2
        ARCH_FAIL=1 ;;
    absent)
        echo "  ✓ $label" ;;
    missing)
        echo "  ✗ $label：文件不存在 $f" >&2
        ARCH_FAIL=1 ;;
    *)
        echo "  ✗ $label：查找工具在 $f 上失败（工具坏了 ≠ 没找到）" >&2
        ARCH_FAIL=1 ;;
    esac
}

# probe_scan_report_many：聚合版呈现（forbid_tree 一次扫一棵树）。
# 用法：probe_scan_report_many <命中文件列表> <坏工具文件列表> <正则> <说明>
probe_scan_report_many() { # probe_scan_report_many <命中列表> <坏工具列表> <正则> <说明>
    local hit="$1" broken="$2" re="$3" label="$4"
    if [ -n "$broken" ]; then
        echo "  ✗ $label：查找工具在这些文件上失败（工具坏了 ≠ 没找到）——$broken" >&2
        ARCH_FAIL=1
        return
    fi
    if [ -n "$hit" ]; then
        echo "  ✗ $label：这些文件里还有 $re ——$hit" >&2
        ARCH_FAIL=1
    else
        echo "  ✓ $label"
    fi
}

# probe_scan_selftest：三态判定**自己证明自己有牙**（批 BF 纪律）。
# ⚠ 合成样例必须**同时**含「该判为命中」与「该判为没命中」
#   ⇒ 只测前者 ⇒ 全判成命中也能过；只测后者 ⇒ 全判成没命中也能过。
# ⚠ 还要含「工具坏了」这一档 ⇒ 否则「工具坏了一律当没命中」也能过。
probe_scan_selftest() { # probe_scan_selftest ⇒ 0 = 自检过
    local bad=0 tmp
    tmp="$(mktemp -d)"
    printf 'ascii only here\n' >"$tmp/plain.txt"
    printf 'hit me\n' >"$tmp/marked.txt"
    probe_scan_find "$tmp/marked.txt" 'hit me' 0 1
    if [ "$PROBE_SCAN_STATE" != "found" ]; then
        echo "  ✗ 公共查找自检失败：该判为 found，实得 $PROBE_SCAN_STATE" >&2
        bad=1
    fi
    probe_scan_find "$tmp/plain.txt" 'hit me' 0 1
    if [ "$PROBE_SCAN_STATE" != "absent" ]; then
        echo "  ✗ 公共查找自检失败：该判为 absent，实得 $PROBE_SCAN_STATE" >&2
        bad=1
    fi
    probe_scan_find "$tmp/plain.txt" '[unclosed' 0 1
    if [ "$PROBE_SCAN_STATE" != "broken" ]; then
        echo "  ✗ 公共查找自检失败：该判为 broken，实得 $PROBE_SCAN_STATE" >&2
        bad=1
    fi
    rm -f "$tmp/plain.txt" "$tmp/marked.txt"
    rmdir "$tmp" 2>/dev/null
    return $bad
}

echo "› 接线门：架构图 / agent 工具表 / 代码图谱+热力图 / 补丁体检 / 固定文档页 / 引擎自检+进度报告接线在（源扫描：判定层与接线点必须都在，撤入口 ≠ 撤能力）"
# ⚠⚠⚠ **自检放在最前**（批 BI 修的坑）：判定逻辑坏了 ⇒ 立刻红；
#   且**不被前面某段的 exit 短路**（批 BG 教训：审计器先跑会短路后面段落的门项）
#   ⇒ 自检若放在段末尾 ⇒ 前面的门一红就退出 ⇒ 自检永远没机会跑 ⇒ 自检形同虚设。
# 架构图链路分四段，任一段被摘掉都必须红：
#   引擎取数（AppModel 调 graph arch --format scene）
#   → 判定层（ArchViewport 视口/命中、ArchReceipt 回执提取）
#   → 渲染层（SceneRender + Canvas2D）
#   → 接线层（详情页入口 → PanelWindow → ArchDialog → 画布）
ARCH_FAIL=0
ARCH_N=0
# ⚠⚠⚨ 批 CP · **全局红过标志**（段级 trailer 不再提前 exit ⇒ 末尾统一判红）
#   ⇒ **一处红不再遮住后面的门项** ⇒ 排障可以「改一个 ⇒ 跑一次 ⇒ 再改一个」
#   ⇒ ⚠ 段级 `ARCH_FAIL` 现在是**段内作用域**（每段末清零）⇒ 段归属不失真
ARCH_ANY_FAIL=0
# ⚠⚠⚠ **自检放在门项之前**（批 BI 修的坑，两个理由）：
#   ① 判定逻辑坏了 ⇒ 立刻红；
#   ② **不被前面某段的 exit 短路**（批 BG 教训：审计器先跑会短路后面段落的门项）
#      ⇒ 自检若放在段末尾 ⇒ 前面的门一红就退出 ⇒ 自检永远没机会跑 ⇒ 自检形同虚设。
#   ⚠ 必须在 ARCH_FAIL 初始化**之后** ⇒ 否则自检设的红会被重置掉。
#   ⚠⚠⚨ 批 CP：自检的红**自己成段**（下面那个 trailer）⇒ 它的归属不许混进后面任何一段。
# ⚠ 自检：三态判定自己证明自己有牙（合成样例 ⇒ 判定逻辑坏了当场红）。
if ! probe_scan_selftest; then
    echo "  ✗ 公共查找自检失败：三态判定没有牙（这道门不可信）" >&2
    ARCH_FAIL=1
fi
# ⚠⚠⚨ 批 CP · **自检自己成段**（不许混进后面任何一段的归属里 ⇒ 诊断不许失真）
if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：公共查找自检段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 公共查找自检段通过（三态判定有牙）"
fi
ARCH_FAIL=0
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
# arch_forbid_ml：**跨行**匹配的 arch_forbid。
#   ⚠ 为什么需要它（批 AN 实测踩出来的）：grep -E 是**按行**匹配的 ⇒
#   shell 里的**续行**写法（`--snapshot \` 换行 `... \` 换行 `| tail -1`）
#   在「同一行正则」下**匹配不到** ⇒ 门在变异后**照样绿** ⇒ 门没牙（负控实测）。
#   ⇒ 这里把（剥完注释的）内容**换行压成一行**再匹配 ⇒ 跨行才算。
#   ⚠ 正则里要用 `[^;]*` 之类**不跨分号**的片段 ⇒ 免得一处违规把整份脚本都算进去。
arch_forbid_ml() { # arch_forbid_ml <文件> <正则> <说明>
    local f="$1" re="$2" label="$3"
    ARCH_N=$((ARCH_N + 1))
    probe_scan_find "$f" "$re" 1 0
    probe_scan_report "$PROBE_SCAN_STATE" "$f" "$re" "$label" '该收敛的又写回去了'
}

# arch_need_ml：**跨行**匹配的 arch_need（剥完注释后把换行压成一行再匹配）。
#   ⚠ 为什么需要它（批 AO 实测踩出来的）：grep -E **按行**匹配 ⇒ 代码折行时
#   `elidedText(` 与参数不在同一行 ⇒ 门**匹配不到** ⇒ 门没牙（负控实测）。
arch_need_ml() { # arch_need_ml <文件> <正则> <说明>
    local f="$1" re="$2" label="$3"
    ARCH_N=$((ARCH_N + 1))
    if [ ! -f "$f" ]; then
        echo "  ✗ $label：文件不存在 $f" >&2
        ARCH_FAIL=1
        return
    fi
    if strip_comments "$f" | tr '\n' ' ' | grep -E -- "$re" >/dev/null; then
        echo "  ✓ $label"
    else
        echo "  ✗ $label：$f 里找不到 $re" >&2
        ARCH_FAIL=1
    fi
}

# any_hits：数「**glob 范围内总命中数**」（所有匹配文件**加总**），**剥注释**。
# ⚠ 为什么是「**总**命中数」而不是「某个文件里几次」（批 AV 实测）：
#   跨文件多现**同样是洞** —— glob 范围里这个串出现 7 次（`res.receipt`），
#   删掉其中一处、别的还在 ⇒ 门照样绿 ⇒ 门被骗过。
#   ⇒ 老 `arch_need_any` 判的是「**任一**匹配文件里有」⇒ 门红 = 「**所有**文件里都没有」
#      ⇒ 它对「别处顶替」**完全没牙**（批 AV 实测 82 条里 42 条有这洞）。
# ⚠ 为什么**必须剥注释**（与 arch_need / arch_need_ml / arch_need_count 同一口径）：
#   老实现用 `grep -lE`（**不剥注释**）⇒ 注释里提一嘴就顶替（批 AP 同形状）。
#   批 AV 实测：AppModel.cpp 的 `applyStatusPayload` 在**注释**里也有一处
#   ⇒ raw 命中 4 次 / 真实命中 3 次。
#   ⚠ 门侧与审计侧**用同一条口径**（都走 strip_comments）⇒ 审计器能直接对拍。
any_hits() { # any_hits <正则> <glob（相对 SRC）>
    local re="$1" glob="$2"
    local total=0 f n
    for f in "$SRC"/$glob; do
        [ -f "$f" ] || continue
        n="$(strip_comments "$f" | grep -oE -- "$re" | grep -c . || true)"
        total=$((total + ${n:-0}))
    done
    printf '%s' "$total"
}
# arch_need_any_count：盯「**glob 范围内**这个正则**恰好**命中 N 次」。
# ⚠ 用途：**接线点**类判据（「AppModel 调引擎 X」）—— 接线**应当唯一**，
#   重复接线 = 隐患 ⇒ 「恰好一次」才能同时抓「删掉」和「多了一处」。
# ⚠ **不与文件位置耦合**（批 AJ 纪律）：glob 可以覆盖多个文件，
#   意图是「这个能力被接上了」，不是「在这个文件里被接上了」。
arch_need_any_count() { # arch_need_any_count <正则> <期望次数> <说明> [文件通配（相对 SRC，默认 src/app/SelfCheck*.cpp）]
    local re="$1" want="$2" label="$3" glob="${4:-src/app/SelfCheck*.cpp}"
    ARCH_N=$((ARCH_N + 1))
    local got
    got="$(any_hits "$re" "$glob")"
    if [ "$got" = "$want" ]; then
        echo "  ✓ $label"
    else
        echo "  ✗ $label：$glob 范围里 $re 命中 $got 次（期望 $want 次）" >&2
        ARCH_FAIL=1
    fi
}
# arch_need_any_min：盯「**glob 范围内**这个正则**至少**命中 N 次」。
# ⚠ 用途：**判据**类（「SelfCheck 覆盖了 X」）—— 同一判定层被**多条断言**覆盖是正常的
#   ⇒ 用「至少 N 次」：删一条断言 ⇒ 红；加一条断言 ⇒ 仍绿（不拦正常演进）。
# ⚠ N 必须**配准**（== 当前命中数）⇒ 下限定低了门**没牙**（删一处仍够 ⇒ 不红）。
#   这条校准由 `ci-wiring-audit.py` 盯着（批 AU 已给单文件版 `arch_need_min` 配上，
#   批 AV 把它**扩到跨文件版**）。
arch_need_any_min() { # arch_need_any_min <正则> <下限次数> <说明> [文件通配（相对 SRC，默认 src/app/SelfCheck*.cpp）]
    local re="$1" want="$2" label="$3" glob="${4:-src/app/SelfCheck*.cpp}"
    ARCH_N=$((ARCH_N + 1))
    local got
    got="$(any_hits "$re" "$glob")"
    if [ "$got" -ge "$want" ]; then
        echo "  ✓ $label"
    else
        echo "  ✗ $label：$glob 范围里 $re 命中 $got 次（至少要 $want 次）" >&2
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
# arch_need_min：盯「**至少**出现 N 次」。
# ⚠ 为什么需要它（批 AS 实测踩出来的，**第四次同一形状**）：
#   arch_need_count 盯的是「**恰好** N 次」⇒ 语义是「不许增不许减」——
#   将来**正常加一条断言**，这条门反而会红 ⇒ 门会被人随手调数字 ⇒ 门就废了。
#   而「**至少 N 次**」才是这类门该有的语义：
#   **削减**（把断言掏空 / 删掉）⇒ 红；**增加**（补新断言）⇒ 绿。
# ⚠⚠⚨ 批 BZ · **配对门**：盯「**报错行数 == 计数行数** == 期望」
#   ⚠ **为什么需要它**（不是推演，是批 BY 留下的**具体**洞）：
#     两个**独立**的「恰好 N 次」门**彼此不知道对方**
#     ⇒ 「新增一条**只报错不计数**的失败路径」（有人新写了一条 `echo "  ✗ …"`
#       却忘了加 `fail=$((fail+1))`）
#     ⇒ 报错门红、计数门绿 ⇒ 人把**报错门**的期望值改大 ⇒ 两门都绿
#     ⇒ 但那条新报错**永远不计数** ⇒ 末尾判定恒真 ⇒ **CI 假绿**
#   ⇒ 必须有**一条**门**同时**盯住两个数 ⇒ 它们的差恒为 0
#   ⚠ 口径：**行数**（不是出现次数）⇒ 一行里写两次只算 1 行
#   ⚠ 期望值是**不许增不许减**的基线（批 BB 口径）
arch_need_count_pair() { # arch_need_count_pair <文件> <报错行正则> <计数行正则> <期望次数> <说明>
    local f="$1" ra="$2" rb="$3" want="$4" label="$5"
    ARCH_N=$((ARCH_N + 1))
    if [ ! -f "$f" ]; then
        echo "  ✗ $label：文件不存在 $f" >&2
        ARCH_FAIL=1
        return
    fi
    local na nb
    na="$(strip_comments "$f" | grep -cE -- "$ra" || true)"
    nb="$(strip_comments "$f" | grep -cE -- "$rb" || true)"
    na="${na:-0}"
    nb="${nb:-0}"
    if [ "$na" = "$want" ] && [ "$nb" = "$want" ]; then
        echo "  ✓ $label"
    else
        echo "  ✗ $label：$f 里 报错行 $na 次 / 计数行 $nb 次（两者都必须是 $want 次 ⇒ 差必须恒为 0）" >&2
        ARCH_FAIL=1
    fi
}
arch_need_min() { # arch_need_min <文件> <正则> <下限次数> <说明>
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
    if [ "$got" -ge "$want" ]; then
        echo "  ✓ $label"
    else
        echo "  ✗ $label：$f 里 $re 出现 $got 次（至少要 $want 次）" >&2
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
# arch_need_count_in_step：盯「**某一步的正文里**」有没有那个动作（批 BE 新门型）。
# ⚠⚠⚠ **为什么必须新门型（批 BE 实测取证，不是推演）**：
#   批 BA 的 per-step 门盯的是「该串在**整个文件**里恰好出现 1 次」⇒
#   ⚠⚠⚠ **实测：把第 8 步的标记串 `CANVAS_METHODS=` 整行挪到第 12 步，
#     命中数仍是 1 ⇒ 接线门照样全绿（rc=0）** ⇒
#   那道门只能证明「**这个串还在**」，**证明不了「它还在这一步里**」。
#   ⇒ 本门型按打点行把文件切段，**在第 N 步的正文里**数 ⇒ 挪走就红。
#   ⚠ **与已有的文件级门互补，两个都要**：
#     文件级「恰好 1 次」⇒ 抓「被**复制**到别处」；步内「恰好 1 次」⇒ 抓「被**挪**到别处」。
# ⚠ **打点行的识别口径（实测）**：`^echo "› [0-9]+/[0-9]+ `
#   —— ⚠ 宽松写法（`^echo "[^"]*[0-9]+/[0-9]+ `）会**误匹配**普通行
#     （实测 `echo "普通行 3/4 不是打点"` 也会命中）⇒ 必须紧锚定 `› `。
#   —— ⚠ 本机 awk 是 **mawk 1.3.4**（实测认得多字节 `›` 的正则与 sub）。
arch_need_count_in_step() { # arch_need_count_in_step <文件> <步号> <正则> <期望次数> <说明>
    local f="$1" step="$2" re="$3" want="$4" label="$5"
    ARCH_N=$((ARCH_N + 1))
    if [ ! -f "$f" ]; then
        echo "  ✗ $label：文件不存在 $f" >&2
        ARCH_FAIL=1
        return
    fi
    local body got
    body="$(strip_comments "$f" | awk -v step="$step" '
        /^echo "› [0-9]+\/[0-9]+ / {
            s = $0
            sub(/^echo "› /, "", s)
            n = s
            sub(/\/.*$/, "", n)
            cur = n + 0
            if (cur == step) in_seg = 1
            else if (in_seg) exit
        }
        in_seg { print }
    ')"
    got="$(printf "%s\n" "$body" | grep -oE -- "$re" | grep -c . || true)"
    got="${got:-0}"
    if [ "$got" = "$want" ]; then
        echo "  ✓ $label"
    else
        echo "  ✗ $label：$f 的第 $step 步正文里 $re 出现 $got 次（期望 $want 次）" >&2
        ARCH_FAIL=1
    fi
}
# arch_forbid：盯「**不该有的东西没了**」—— 收敛类改动光靠 arch_need（查「在」）
# 看不出来：把写死的色值又写回去，「它还在」这件事没有正向条目能抓。
arch_forbid() { # arch_forbid <文件> <正则> <说明>
    local f="$1" re="$2" label="$3"
    ARCH_N=$((ARCH_N + 1))
    probe_scan_find "$f" "$re" 0 0
    probe_scan_report "$PROBE_SCAN_STATE" "$f" "$re" "$label" '该收敛的又写回去了'
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
    local hit="" broken="" f
    for f in $(cd "$SRC" && find src \( -name '*.cpp' -o -name '*.h' \) | sort); do
        case "$allow" in *" $f "*) continue ;; esac
        probe_scan_find "$SRC/$f" "$re" 0 0
        case "$PROBE_SCAN_STATE" in
        found) hit="$hit $f" ;;
        broken) broken="$broken $f" ;;
        esac
    done
    probe_scan_report_many "$hit" "$broken" "$re" "$label"
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
        # ⚠⚠⚨ 批 CN：没有 perl ⇒ 这道门**根本没跑** ⇒ 必须**判红**
        #   （批 CB / CC / BI 口径：工具坏了 ≠ 没找到；未验证不许被当成通过）。
        #   ⇒ 以前这里是「显式 SKIP（不算通过）」⇒ 那**正是**批 CB/CC 要收的旧口径；
        #   ⇒ ⚠ 以前它只是**碰巧**不可达（脚本顶部 preflight「没有 perl ⇒ exit 1」先兜住）
        #   ⇒ ⇒ **顶部 preflight 一旦被摘掉**（或 perl 中途消失）⇒ 这里就**静默放行 ⇒ 假绿**。
        echo "  ✗ $label：没有 perl（剥不掉块注释 ⇒ 这道门没跑 ⇒ 未验证不许被当成通过）" >&2
        ARCH_FAIL=1
        return 1
    fi
    # ⚠ 剥块注释 + 剥行注释 + 查中文，**一次 perl 做完** ⇒ 只有一个工具 ⇒ 只有一个失败点。
    #   退出码：0 = 有中文；1 = 没中文；其它 = perl 坏了 ⇒ 门必须红（**不是绿**）。
    # ⚠ 字节范围 U+3000–U+9FFF（中文标点 + 汉字 + 假名）：UTF-8 里是 E3–E9 开头
    local err rc
    err="$(mktemp)"
    perl -CSD -0777 -ne '
        s{/\*.*?\*/}{}gs;
        s{(?<!:)(//)(?!:)[^\n]*}{}g;
        exit(/[\x{3000}-\x{9fff}]/ ? 0 : 1);
    ' "$f" >/dev/null 2>"$err"
    rc=$?
    probe_scan_state_of "$rc"
    if [ "$PROBE_SCAN_STATE" = "broken" ]; then
        echo "  ✗ $label：查中文的 perl 失败（工具坏了 ≠ 没找到）——$(head -2 "$err" 2>/dev/null | tr '\n' ' ')" >&2
        rm -f "$err"
        ARCH_FAIL=1
        return
    fi
    rm -f "$err"
    probe_scan_report "$PROBE_SCAN_STATE" "$f" '中文字符' "$label" '文案必须走判定层'
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
    probe_scan_find "$f" "$re" 0 1
    probe_scan_report "$PROBE_SCAN_STATE" "$f" "$re" "$label" '连注释里也不许留'
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
        # ⚠⚠⚨ 批 CN：同款 ⇒ 没有 perl ⇒ 这道门**根本没跑** ⇒ 必须**判红**
        #   （批 CB / CC / BI 口径：工具坏了 ≠ 没找到；未验证不许被当成通过）。
        echo "  ✗ $label：没有 perl（取不出字面量清单 ⇒ 这道门没跑 ⇒ 未验证不许被当成通过）" >&2
        ARCH_FAIL=1
        return 1
    fi
    local tmp hitsf err rc
    tmp="$(mktemp)"
    hitsf="$(mktemp)"
    err="$(mktemp)"
    # 取判定层里所有**含中文**的字符串字面量（≥4 字符）
    # ⚠⚠ perl 失败必须**红**：工具坏了 ≠ 判定层没文案 ⇒ 两件事要分开。
    if ! perl -0777 -Mopen=':std,:encoding(UTF-8)' -ne \
        'while (/"([^"\n]{4,})"/g) { my $t = $1; print "$t\n" if $t =~ /[\x{3000}-\x{9fff}]/; }' \
        "$srcf" >"$tmp" 2>"$err"; then
        echo "  ✗ $label：取判定层文案的 perl 失败（工具坏了 ≠ 没找到）——$(head -2 "$err" | tr '\n' ' ')" >&2
        rm -f "$tmp" "$hitsf" "$err"
        ARCH_FAIL=1
        return
    fi
    if [ ! -s "$tmp" ]; then
        rm -f "$tmp" "$hitsf" "$err"
        echo "  ✗ $label：判定层里没取到任何中文字面量（清单为空 = 门形同虚设）" >&2
        ARCH_FAIL=1
        return
    fi
    # 扫界面层：先剥**块注释 + 行注释**（注释里提到这句话不算抄）
    # ⚠⚠ perl 退出码：0 = 抄了；1 = 没抄；其它 = 扫描器坏了 ⇒ 必须红（**不是绿**）。
    perl -e '
        use strict; use warnings;
        my $listfile = shift @ARGV;
        open(my $lf, "<:encoding(UTF-8)", $listfile) or exit 2;
        my @texts = grep { length($_) >= 4 } map { chomp; $_ } <$lf>;
        close $lf;
        binmode(STDOUT, ":encoding(UTF-8)");
        my $found = 0;
        for my $f (@ARGV) {
            open(my $fh, "<:encoding(UTF-8)", $f) or next;
            local $/; my $body = <$fh>; close $fh;
            $body =~ s{/\*.*?\*/}{}gs;
            $body =~ s{(?<!:)(//)(?!:)[^\n]*}{}g;
            for my $t (@texts) {
                next unless index($body, $t) >= 0;
                print "$f\t$t\n";
                $found = 1;
            }
        }
        exit($found ? 0 : 1);
    ' "$tmp" $(find "$SRC/$dir" \( -name '*.cpp' -o -name '*.h' \) | sort) >"$hitsf" 2>"$err"
    rc=$?
    probe_scan_state_of "$rc"
    rm -f "$tmp" "$err"
    if [ "$PROBE_SCAN_STATE" = "broken" ]; then
        echo "  ✗ $label：扫界面层的 perl 失败（工具坏了 ≠ 没找到）" >&2
        rm -f "$hitsf"
        ARCH_FAIL=1
        return
    fi
    if [ -s "$hitsf" ]; then
        echo "  ✗ $label：界面层抄了判定层的文案（同一句话两个真相源）——" >&2
        sed 's/^/      /' "$hitsf" >&2
        rm -f "$hitsf"
        ARCH_FAIL=1
    else
        rm -f "$hitsf"
        echo "  ✓ $label"
    fi
}
# ⚠⚠⚨ 批 CM · **接线门必须真的跑一次未验证出口盘点**（批 BD 纪律：
#   「多了一份没人跑的断言」与「少了一份断言」是同一个洞的两头 ⇒ 从**集合**这一层堵）
#   ⇒ 盘点脚本**在仓内常驻**（`ci-unverified-audit.py` + 逐组带理由的登记册）
#     ⇒ 数字**可复核**（批 CL 实测坐实的起因：那个数字原先只存在于 /tmp 的
#       一次性脚本里 ⇒ 仓内没有任何东西能重算它）；
#   ⇒ ⚠⚠⚨ **位置必须在所有门项段之前** ⇒ 否则前面某段红 ⇒ 提前 exit ⇒
#     **盘点根本没人跑**（那就还是「多了一份没人跑的断言」）。
if ! python3 "$SRC/scripts/ci-unverified-audit.py"; then
    echo "✗ 未验证出口盘点失败（盘点脚本跑不起来 ⇒ 没有 python3；或盘点与登记册对不上 ⇒ 看上面带 ✗ 的行）" >&2
    ARCH_FAIL=1
    # ⚠⚠⚨ 批 CM 的理由是「紧跟 exit 1」（诊断不许失真）：只打不退出 ⇒ 会落到**后面**那个
    #   通用守卫 ⇒ 那句文案是「取数/判定/渲染/接线任一段被摘掉」⇒ **指错方向**。
    # ⚠⚠⚨ **批 CP 订正**：但那个 `exit 1` 本身就是「**先红遮后红**」的另一个实例 ——
    #   盘点一红 ⇒ 后面 1000 多条门项**根本没跑** ⇒ 一次只看得见一个洞。
    #   ⇒ 现在改成「**只打红 + 继续跑**」⇒ 归属交给**紧跟其后的盘点段 trailer**
    #   （文案指名道姓 ⇒ 诊断精度**不丢**）⇒ 而后面所有门项**照跑**。
fi
# ⚠⚠⚨ 批 CP · **盘点自己成段**（它的红不许落到「接线门」段头上 ⇒ 诊断不许失真）
if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：出口盘点段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 出口盘点段通过（登记册与实测对得上）"
fi
ARCH_FAIL=0

arch_need_any_count 'QStringLiteral\("graph"\).*QStringLiteral\("arch"\)' 1 'AppModel 调引擎 graph arch 取场景' 'src/app/AppModel*.cpp'
arch_need_any_count 'QStringLiteral\("scene"\)' 1 '场景按 scene 契约格式取（--format scene）' 'src/app/AppModel*.cpp'
arch_need "$SRC/src/app/AppModel.h" '\bloadScene\b' 'AppModel 暴露 loadScene'
arch_need "$SRC/src/app/AppModel.h" '\bgenArch\b' 'AppModel 暴露 genArch（生成）'
arch_need "$SRC/src/app/AppModel.h" '\bexportArch\b' 'AppModel 暴露 exportArch（导出）'
# 生成/导出是**回执型命令**：stdout 是人话不是 JSON → 必须走 Text 契约。
# 拿 callJson 去收，exit==0 也会被判成「引擎输出不是合法 JSON」——成功报成失败。
arch_need_any_count 'callText\(\{ *QStringLiteral\("arch"\), *QStringLiteral\("gen"\)' 1 'genArch 走 Text 契约（callText）' 'src/app/AppModel*.cpp'
arch_need_any_count 'callText\(\{ *QStringLiteral\("render"\), *QStringLiteral\("arch"\)' 1 'exportArch 走 Text 契约（callText）' 'src/app/AppModel*.cpp'
arch_need "$SRC/src/app/EngineCli.h" '\bcallText\b' 'EngineCli 提供文本输出通道'
arch_need "$SRC/src/logic/ArchViewport.cpp" '\bhitAt\b' '判定层有命中测试'
arch_need "$SRC/src/logic/ArchReceipt.cpp" '\bhtmlPath\b' '判定层有回执路径提取'
arch_need "$SRC/src/ui/ArchCanvasWidget.cpp" '\bSceneRender::render\b' '画布经 SceneRender 渲染'
arch_need "$SRC/src/ui/ArchCanvasWidget.cpp" '\bArchViewport::hitAt\b' '画布经 ArchViewport 命中'
arch_need "$SRC/src/ui/dialogs/ArchDialog.cpp" 'new ArchCanvasWidget\(' '架构图窗**真的造了画布**（盯构造点，不盯类名 —— 类名在 include/成员/信号三处都出现 ⇒ 盯名字会被别处顶替）'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" '\barchRequested\b' '详情页发 archRequested'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&ProjectDetailPage::archRequested\b' 'PanelWindow 接了详情页入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'showArch\(p\);' 'PanelWindow 把「详情页请求架构图」**接到**开窗动作上（盯接线那一行）'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'new ArchDialog\(' 'PanelWindow **真的造了**架构图窗（盯构造点）'
# 回执按项目路由：两个项目的架构图窗可以同时开着，回执不带项目名就会串台
#（在错误的窗口里显示回执、甚至触发重载）。
arch_need "$SRC/src/app/AppModel.h" 'archActionFinished\(bool ok, const QString &project\b' '回执信号带项目名'
arch_need "$SRC/src/ui/dialogs/ArchDialog.cpp" 'project != m_project\b' '架构图窗按项目过滤回执'

# agent 工具表接线：执行走纯函数表；清单能被无头 flag 打印出来（契约第 12 组靠它对位）
arch_need "$SRC/src/ai/AgentCore.cpp" '\bAgentToolPlan::planFor\b' 'AgentCore 经工具表执行'
arch_need "$SRC/src/logic/AgentToolPlan.cpp" '\bknownToolNames\b' '工具表有权威清单出口'
arch_need "$SRC/src/main.cpp" '--agent-tool-names\b' '客户端能无头打印工具清单（契约对位用）'

# 代码图谱链路：取数（三源）→ 判定（合成 + 可见行）→ 接线（详情页入口 → 面板 → 窗）
arch_need_any_count 'QStringLiteral\("graph"\), *QStringLiteral\("tree"\)' 1 'AppModel 调引擎 graph tree 取文件骨架' 'src/app/AppModel*.cpp'
arch_need_any_count 'QStringLiteral\("graph"\), *QStringLiteral\("confidence"\)' 1 'AppModel 调引擎 graph confidence 取置信度' 'src/app/AppModel*.cpp'
arch_need_any_count 'QStringLiteral\("graph"\), *QStringLiteral\("functions"\)' 1 'AppModel 调引擎 graph functions 取函数级图谱' 'src/app/AppModel*.cpp'
arch_need "$SRC/src/app/AppModel.h" '\bloadCodeGraph\b' 'AppModel 暴露 loadCodeGraph'
arch_need "$SRC/src/app/AppModel.h" '\bgenIndex\b' 'AppModel 暴露 genIndex（生成）'
arch_need "$SRC/src/app/AppModel.h" '\bexportIndex\b' 'AppModel 暴露 exportIndex（导出）'
arch_need "$SRC/src/logic/CodeGraphBuild.cpp" 'sym\.id = sid\.isEmpty\(\) \? symbolId\(path, sline, sname\)' '判定层**真的用**符号 id 构造式（与引擎同形）—— 盯调用那一行（盯定义的话，调用被摘了门照样绿）'
arch_need "$SRC/src/logic/CodeGraphBuild.cpp" '\bvisibleRows\b' '判定层有可见行算法（搜索 + 展开态）'
arch_need_min "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '\bCodeGraphBuild::visibleRows\b' 2 '代码图谱窗的可见性以判定层为准 —— 两处**一字不差**同形 ⇒ 行级构造分不开 ⇒ 意图天然是「至少 2 次」；⚠ 这条门**不在审计器覆盖内**'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" '\bcodeGraphRequested\b' '详情页发 codeGraphRequested'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&ProjectDetailPage::codeGraphRequested\b' 'PanelWindow 接了代码图谱入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'showCodeGraph\(p\);' 'PanelWindow 把「详情页请求代码图谱」**接到**开窗动作上（盯接线那一行）'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'new CodeGraphDialog\(' 'PanelWindow **真的造了**代码图谱窗（盯构造点）'

# 热力图链路：判定（作用域切分 / 铺排 / 走线）→ 渲染（HeatmapWidget + Canvas2D）
#   → 接线（左栏模式切换 + 堆叠页 + 下钻 + 点选）。
# ⚠ 热力图是**左栏的另一种模式**，不是第三栏 —— 形状钉在左栏的堆叠页上。
arch_need "$SRC/src/logic/HeatLayout.cpp" '\bscopeCards\b' '判定层有作用域切分（文件层 / 下钻层）'
arch_need "$SRC/src/logic/HeatLayout.cpp" '\blayout\b' '判定层有卡片铺排'
arch_need "$SRC/src/logic/HeatLayout.cpp" '\broutes\b' '判定层有边走线'
arch_need "$SRC/src/ui/HeatmapWidget.cpp" '\bHeatLayout::layout\b' '画布经 HeatLayout 铺排'
arch_need "$SRC/src/ui/HeatmapWidget.cpp" '\bHeatLayout::routes\b' '画布经 HeatLayout 走线'
arch_need_min "$SRC/src/ui/HeatmapWidget.cpp" '\bCanvas2D\b' 4 '画布走 D1 的 Canvas2D 内核（不自己造图形栈）—— **三处同形**（`Canvas2D canvas(&p);`）⇒ 行级构造分不开 ⇒ 意图天然是「至少 N 次」；⚠ **下限是 4 不是 3**（文件里 `Canvas2D` 命中 4 次 = include + 3 处构造）—— 下限定低了门**没牙**（删一处构造仍剩 3 ⇒ 不红），负控实测抓到的；⚠ 这条门**不在审计器覆盖内**'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_heat = new HeatmapWidget\(heatPage\);' '代码图谱窗挂了热力图 —— 盯**造热力图**那一行（之前盯「HeatmapWidget」这个词 ⇒ 信号连接里也有 ⇒ 改一处骗得过门）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '&HeatmapWidget::nodeSelected\b' '热力图点选信号接上了（→ 右栏详情）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '&HeatmapWidget::drillChanged\b' '热力图下钻信号接上了（面包屑跟着走）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_leftStack = new QStackedWidget\(left\);' '左栏是模式切换 + 堆叠页（热力图是左栏的另一种模式）—— 盯**造堆叠页**那一行'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_heat->setData\(nullptr\);' '热力图数据源接上了（与树同源）—— 盯**清空**那一行（没数据时必须清空 ⇒ 否则留上一份旧图）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_heat->setData\(m_model \? m_model->codeGraphFor\(m_project\) : nullptr\);' '热力图数据源接上了 —— 盯**喂判定层数据**那一行（**同源**是这儿的要害）'
arch_need_any_min '\bHeatLayout::layout\b' 4 'SelfCheck 覆盖铺排'
arch_need_any_min '\bHeatLayout::routes\b' 1 'SelfCheck 覆盖走线'

# 补丁体检链路：判定（PatchCheck 纯函数）→ 取数（工作区 diff + 引擎 patchconf）
#   → 接线（详情页入口 → 独立窗 → 人工裁决 → 合并终稿）
arch_need "$SRC/src/logic/PatchCheck.cpp" '\bparseLayer1\b' '判定层有 Layer1 解析'
arch_need "$SRC/src/logic/PatchCheck.cpp" '\bparseMerged\b' '判定层有终稿解析'
arch_need "$SRC/src/logic/PatchCheck.cpp" '\blowConfidenceEntities\b' '判定层有低置信度筛选'
arch_need "$SRC/src/logic/PatchCheck.cpp" '\bagentPayload\b' '判定层有裁决载荷生成'
arch_need "$SRC/src/logic/PatchCheck.cpp" '\bdiffSnippet\b' '判定层有 diff 抽实码'
arch_need_any_min 'QStringLiteral\("patchconf"\)' 3 'AppModel 调引擎 patchconf' 'src/app/AppModel*.cpp'
arch_need_any_min '\bworkingDiff\b' 3 'AppModel 取工作区 diff' 'src/app/AppModel*.cpp'
arch_need_any_count '\bmergePatchCheck\b' 1 'AppModel 有合并终稿动作' 'src/app/AppModel*.cpp'
arch_need "$SRC/src/ui/dialogs/PatchCheckDialog.cpp" '\bPatchCheck::lowConfidenceEntities\b' '窗经判定层取低置信度实体'
arch_need "$SRC/src/ui/dialogs/PatchCheckDialog.cpp" '\bPatchCheck::agentPayload\b' '窗经判定层生成裁决载荷'
arch_need "$SRC/src/ui/dialogs/PatchCheckDialog.cpp" '\bPatchCheck::diffSnippet\b' '窗经判定层抽实码'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" '\bpatchCheckRequested\b' '详情页发 patchCheckRequested'
arch_need "$SRC/src/ui/PanelWindow.cpp" '&ProjectDetailPage::patchCheckRequested\b' 'PanelWindow 接了补丁体检入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'showPatchCheck\(p\);' 'PanelWindow 把「详情页请求补丁体检」**接到**开窗动作上（盯接线那一行）'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'new PatchCheckDialog\(' 'PanelWindow **真的造了**补丁体检窗（盯构造点）'
arch_need_any_min '\bPatchCheck::parseLayer1\b' 3 'SelfCheck 覆盖 Layer1 解析'
arch_need_any_min '\bPatchCheck::diffSnippet\b' 2 'SelfCheck 覆盖 diff 抽实码'

# 固定文档页链路：内容（DocPages 纯函数，四类目写死在代码里）→ 渲染（DocsDialog，
#   markdown）→ 接线（面板菜单「关于 / 帮助」）。文档不进引擎 —— 它不是数据。
arch_need "$SRC/src/logic/DocPages.cpp" 'const QString id = kindKey\(k\);' '判定层**真的按 kind 取**类目标识 —— 盯调用那一行'
arch_need "$SRC/src/logic/DocPages.cpp" 'QString content\(Kind k, Language lang\)' '判定层有文档正文 —— 盯**定义**那一行（之前盯「content」这个词，英文错误消息里也有 ⇒ 改一处骗得过门）'
arch_need "$SRC/src/logic/DocPages.cpp" '\bclientRepo\b' '仓库地址有单一出处'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" '\bDocPages::content\b' '窗经判定层取正文'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" '\bsetMarkdown\b' '正文按 markdown 渲染'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'showDocs\(0\);' 'PanelWindow 把「面板菜单『关于』」**接到**文档窗上（盯接线那一行；「帮助」入口另有一条门盯 addAction）'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'new DocsDialog\(' 'PanelWindow **真的造了**文档窗（盯构造点）'
# 入口级检查：光有 showDocs 方法不算数 —— 菜单里没人调它，用户就永远打不开
# （负控实测：只删菜单两行、留着方法，上面两条照样全绿）。
arch_need "$SRC/src/ui/PanelWindow.cpp" 'addAction\(QStringLiteral\("关于 deepDolphin"\)\)' '面板菜单有「关于」入口'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'addAction\(QStringLiteral\("帮助"\)\)' '面板菜单有「帮助」入口'
arch_need_any_min '\bDocPages::content\b' 14 'SelfCheck 覆盖文档正文'

# 语法高亮链路：判定（SyntaxHighlight 纯函数，九语言与引擎 detectLang 对齐）→
#   涂色（CodeHighlighter，颜色取自 DS 令牌）→ 接线（代码图谱页源码页签）
arch_need "$SRC/src/logic/SyntaxHighlight.cpp" '\blanguages\b' '判定层有语言清单'
arch_need "$SRC/src/logic/SyntaxHighlight.cpp" 'const QSet<QString> kws = keywords\(lang\);' '判定层**真的取**关键词表 —— 盯调用那一行'
arch_need "$SRC/src/logic/SyntaxHighlight.cpp" '\bhighlight\b' '判定层有逐行分类'
arch_need "$SRC/src/ui/CodeHighlighter.cpp" '\bSyntaxHighlight::highlight\b' '涂色层经判定层分类'
arch_need "$SRC/src/ui/CodeHighlighter.cpp" 'm_keyword\.setForeground\(DS::semColor\(DS::SemColor::deep\)\);' '颜色取自 DS 令牌（不是契约色）—— 盯**关键字**那一行'
arch_need "$SRC/src/ui/CodeHighlighter.cpp" 'm_string\.setForeground\(DS::semColor\(DS::SemColor::shallow\)\);' '颜色取自 DS 令牌 —— 盯**字符串**那一行'
arch_need "$SRC/src/ui/CodeHighlighter.cpp" 'm_number\.setForeground\(DS::semColor\(DS::SemColor::yellow\)\);' '颜色取自 DS 令牌 —— 盯**数字**那一行'
# ⚠ 盯**构造点**（`new CodeHighlighter`）而不是「CodeHighlighter 这个词出现过」——
#   负控实测：只删掉构造那一行、留着 include 与另一个调用点时，后者照样全绿
#   （用户看到的源码页签还是一片纯色）。这已是第三回「门盯名字不盯接线点」。
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'new CodeHighlighter\b' '代码图谱源码页签真的 new 了一个高亮器'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_highlighter->setLanguage\b' '高亮语言跟着选中项走'
arch_need "$SRC/src/main.cpp" 'syntax-languages\b' '无头 flag 暴露语言清单（契约门第 16 组用）'
arch_need_any_min '\bSyntaxHighlight::highlight\b' 10 'SelfCheck 覆盖高亮分类'

# 图谱三件套链路：判定（GraphInsight：id→名字 / overview / symbol / impact）→
#   取数（引擎 graph overview / symbol / impact）→ 接线（代码图谱页关系页签 + 页头概览）
# ⚠ 引擎的 symbol / impact **只认符号名**：传 id 它返回空结果，看着像「没有影响面」。
arch_need "$SRC/src/logic/GraphInsight.cpp" '\bsymbolNameFromId\b' '判定层有「id 取名字」（引擎只认名字）'
arch_need "$SRC/src/logic/GraphInsight.cpp" '\bparseOverview\b' '判定层有概览解析'
arch_need "$SRC/src/logic/GraphInsight.cpp" '\bparseSymbol\b' '判定层有符号详情解析'
arch_need "$SRC/src/logic/GraphInsight.cpp" '\bparseImpact\b' '判定层有影响面解析'
arch_need_any_count 'QStringLiteral\("graph"\), *QStringLiteral\("overview"\)' 1 'AppModel 调引擎 graph overview' 'src/app/AppModel*.cpp'
arch_need_any_count 'QStringLiteral\("impact"\)' 1 'AppModel 调引擎 graph impact' 'src/app/AppModel*.cpp'
arch_need_any_count 'QStringLiteral\("symbol"\)' 1 'AppModel 调引擎 graph symbol' 'src/app/AppModel*.cpp'
# ⚠ 盯**调用点**而不是方法名：方法定义还在时 grep 照样命中（这是第四次同类漏洞）。
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '^[[:space:]]*showImpact\(\);[[:space:]]*$' '关系页签真的调用了影响面（不是只定义了方法）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '\bGraphInsight::symbolNameFromId\b' '界面按名字问引擎（不传 id）'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '\bloadOverview\b' '页头接了项目级概览'
arch_need_any_min '\bGraphInsight::symbolNameFromId\b' 3 'SelfCheck 覆盖 id→名字'

# 引擎自检（doctor）链路：判定（EngineDoctor 纯函数）→ 取数（引擎 doctor --json）
#   → 接线（设置·通用页「环境自检」卡）。
# ⚠ doctor **发现问题时退出码是 1**（自检必须能失败）但 stdout 仍是合法 JSON，
#   所以客户端必须**读载荷**判成败，不能按退出码。钉调用点。
arch_need "$SRC/src/logic/EngineDoctor.cpp" 'Report parse\b' '判定层有自检载荷解析'
arch_need "$SRC/src/logic/EngineDoctor.cpp" 'QString summary\b' '判定层有自检摘要'
arch_need "$SRC/src/logic/EngineDoctor.cpp" 'Tone toneOf\b' '判定层有自检档位映射'
arch_need "$SRC/src/app/AppModel.h" '\brunDoctor\b' 'AppModel 暴露 runDoctor'
arch_need "$SRC/src/app/AppModel.h" '\bdoctorFinished\b' 'AppModel 有自检回执信号'
arch_need_any_count 'QStringLiteral\("doctor"\)' 1 'AppModel 调引擎 doctor' 'src/app/AppModel*.cpp'
arch_need_any_count 'EngineDoctor::parse\(res\.payload->object\(\)\)' 1 '自检读**载荷**判成败（不是按退出码）' 'src/app/AppModel*.cpp'
arch_need_any_min 'm_doctor = r\b' 2 '自检结果落到 AppModel 成员' 'src/app/AppModel*.cpp'
# 接线：设置·通用页的「运行自检」钮 —— 盯**构造点**与**调用点**，不是「doctor 这个词出现过」。
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'new DPushButton\(QStringLiteral\("运行自检"\)' '设置页真的造了「运行自检」按钮'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'm_model->runDoctor\(\)' '「运行自检」真的调了引擎自检'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" '&AppModel::doctorFinished\b' '设置页接了自检回执'
arch_need "$SRC/src/ui/dialogs/AiSettingsDialog.cpp" 'new GeneralPane\(model,' '设置窗把模型传给了通用页'
arch_need "$SRC/src/ui/PanelWindow.cpp" 'new AiSettingsDialog\(m_model,' '面板把模型传给了设置窗'
arch_need_any_min '\bEngineDoctor::parse\b' 4 'SelfCheck 覆盖自检解析'

# 进度报告（report）链路：取数（引擎 report，回执型命令）→ 回执路径提取
#   → 接线（详情页「导出报告」入口 + 报告卡）。
arch_need "$SRC/src/app/AppModel.h" '\bexportReport\b' 'AppModel 暴露 exportReport'
arch_need "$SRC/src/app/AppModel.h" '\breportExported\b' 'AppModel 有报告回执信号'
arch_need_any_count 'QStringLiteral\("report"\)' 1 'AppModel 调引擎 report' 'src/app/AppModel*.cpp'
arch_need_any_count 'callText\(\{ *QStringLiteral\("report"\)' 1 'report 走 Text 契约（callText，不是 callJson）' 'src/app/AppModel*.cpp'
# ⚠ 回执通道：引擎的 report 把回执写在 **stderr**（arch gen / render arch 才在 stdout）。
#   只认 stdout 的客户端会把「报告已生成」判成「引擎没有回执」—— 成功说成失败。
arch_need "$SRC/src/app/EngineCli.h" '\breceiptText\b' 'EngineCli 有回执通道（stdout 优先，空则 stderr）'
arch_need "$SRC/src/app/EngineCli.cpp" 'r\.receipt = EngineCli::receiptText\b' '回执走 receiptText（两路兜底）'
arch_need_any_min 'res\.receipt\b' 7 'Text 消费点读 receipt（不是 stdOut）' 'src/app/AppModel*.cpp'
# 引擎回执带 ANSI 颜色码（引擎不认 NO_COLOR）→ 显示前必须剥。
arch_need "$SRC/src/logic/ArchReceipt.cpp" 'QString plain\b' '判定层有剥 ANSI 的回执净化'
arch_need_any_min '\bEngineDoctor::checkLine\b' 2 'SelfCheck 覆盖自检行文'
arch_need_any_min '\bEngineCli::receiptText\b' 3 'SelfCheck 覆盖回执通道'
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
arch_need "$SRC/src/main.cpp" 'rawArgs\.contains\(QStringLiteral\("--receipt-file-path"\)\)' '无头 flag 能从回执抽落盘路径（契约门用）—— 盯**认得这个 flag**那一行'
arch_need "$SRC/src/main.cpp" 'rawArgs\.indexOf\(QStringLiteral\("--receipt-file-path"\)\)' '无头 flag 真的**取到了** flag 的位置（只认不取 ⇒ 拿到的是空路径）'

# 引擎配置（config list / config set）链路：判定（EngineConfig 纯函数）
#   → 取数（引擎 config list --json）→ 写（引擎 config set，回执型）
#   → 接线（设置·通用页「引擎配置」卡）。
arch_need "$SRC/src/logic/EngineConfig.cpp" 'Config parse\b' '判定层有配置载荷解析'
arch_need "$SRC/src/logic/EngineConfig.cpp" 'QStringList writableKeys\(\)' '判定层有可写键清单（与引擎同一份）—— 盯**定义**那一行'
arch_need "$SRC/src/logic/EngineConfig.cpp" '\bisWritable\b' '判定层能判键可不可写'
arch_need "$SRC/src/app/AppModel.h" '\bloadEngineConfig\b' 'AppModel 暴露 loadEngineConfig'
arch_need "$SRC/src/app/AppModel.h" '\bsetEngineConfig\b' 'AppModel 暴露 setEngineConfig'
arch_need "$SRC/src/app/AppModel.h" '\bengineConfigChanged\b' 'AppModel 有配置变化信号'
arch_need "$SRC/src/app/AppModel.h" '\bengineConfigSaved\b' 'AppModel 有配置写入回执信号'
arch_need_any_count 'QStringLiteral\("config"\), *QStringLiteral\("list"\)' 1 'AppModel 调引擎 config list' 'src/app/AppModel*.cpp'
arch_need_any_count 'QStringLiteral\("config"\), *QStringLiteral\("set"\)' 1 'AppModel 调引擎 config set' 'src/app/AppModel*.cpp'
# ⚠ config set 是**回执型命令**（回执在 stderr）→ 必须走 Text 契约。
#   拿 callJson 去收，exit==0 也会被判成「引擎输出不是合法 JSON」—— 成功报成失败。
arch_need_any_count 'callText\(\{ *QStringLiteral\("config"\), *QStringLiteral\("set"\)' 1 'config set 走 Text 契约（callText）' 'src/app/AppModel*.cpp'
# 键白名单：客户端先拦一道，界面才不会给用户一个引擎根本不认的键。
arch_need_any_count 'EngineConfig::isWritable\(key\)' 1 'setEngineConfig 有键白名单' 'src/app/AppModel*.cpp'
# ⚠ `res.receipt` 在 AppModel 里有多处（架构图/索引/报告都读它）——
#   盯泛化的 `res\.receipt` 的话，摘掉配置这一处门照样绿。故盯到本行。
arch_need_any_count 'emit engineConfigSaved\(true, res\.receipt\);' 1 '配置写入读 receipt（不是 stdOut）' 'src/app/AppModel*.cpp'
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
arch_need_any_min '\bEngineConfig::parse\b' 4 'SelfCheck 覆盖配置解析'
arch_need_any_min '\bEngineConfig::writableKeys\b' 1 'SelfCheck 覆盖可写键清单'

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
arch_need_any_count 'QStringLiteral\("index"\), *QStringLiteral\("overview"\)' 1 'AppModel 调引擎 index overview' 'src/app/AppModel*.cpp'
arch_need_any_count 'QStringLiteral\("index"\), *QStringLiteral\("update"\)' 1 'AppModel 调引擎 index update' 'src/app/AppModel*.cpp'
# ⚠ 「已最新」≠「已更新」：fresh 时引擎**什么都没重建**，界面不能说成「更新好了」。
arch_need_any_count 'if \(u\.fresh\)' 1 '索引更新区分「已最新」与「已重建」' 'src/app/AppModel*.cpp'
# 接线：代码图谱页的「增量更新」钮 + 索引状态行。盯构造点与调用点。
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'QStringLiteral\("增量更新"\)' '代码图谱页真的造了「增量更新」按钮'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_model->updateIndex\(' '「增量更新」真的调了引擎 index update'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" 'm_model->loadIndexOverview\(' '代码图谱页真的读了索引状态'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '&AppModel::indexStatusChanged\b' '代码图谱页接了索引状态信号'
arch_need "$SRC/src/ui/dialogs/CodeGraphDialog.cpp" '&AppModel::indexUpdated\b' '代码图谱页接了索引更新结果'
arch_need "$SRC/src/main.cpp" '--index-status-parse\b' '无头 flag 能把索引概览判成值（契约门用）'
arch_need_any_min '\bIndexStatus::parseOverview\b' 6 'SelfCheck 覆盖索引概览解析'
arch_need_any_min '\bIndexStatus::parseUpdate\b' 3 'SelfCheck 覆盖索引更新解析'

# 批 M · 性能审计：Canvas 字体路径（解析在判定层 + QFont 缓存 + 同串跳过）
#   与热力图每帧分配（索引缓存 / 静态字体串 / 成员比较）。
# ⚠ Canvas 的 font 简写是**浏览器 CSS 口径**（px 与 pt 都认）——
#   解析器只认 px 时，"11pt" 会被当成字体族名吞掉，字号根本没设上。
arch_need "$SRC/src/logic/CanvasFont.cpp" 'Spec parse\b' '判定层有 Canvas font 简写解析'
arch_need "$SRC/src/logic/CanvasFont.cpp" 'm = ptRe\.match\(s\);' '字体解析认 pt 单位（CSS 口径）—— 盯**用**它的那一行'
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
arch_need_any_min '\bCanvasFont::parse\b' 8 'SelfCheck 覆盖字体解析'

# 批 N · 设计系统存量清零（DS 单一真相源）：四处散值收进 token，
#   D2 门上限降到 0，且门独立成 scripts/ci-d2.sh（负控能精确打）。
arch_need "$SRC/src/ui/DesignTokens.h" 'namespace FontPx\b' 'DS 有 QSS 字号 token（QSS 只能写字面量）'
arch_need "$SRC/src/ui/DualTrackButtons.cpp" '\bDS::FontPx::badge\b' '胶囊徽章字号走 token'
arch_need "$SRC/src/ui/common/Chip.h" '\bDS::FontPx::badge\b' '小标签字号走 token'
arch_need "$SRC/src/ui/common/MarkdownView.h" '\.arg\(DS::MD_H3\);' 'Markdown h4-h6 与 h3 同档（走 token）'
arch_need "$SRC/src/ui/pages/ProjectProgressCard.cpp" '\bDS::FontPx::code\b' '等宽项目名字号走 token'
arch_need_any_min '\bDS::FontPx::badge\b' 1 'SelfCheck 钉住 token 值'

# 批 N · 透明度入 token（色进了 DS 而 alpha 没进 = 同一语义散成 N 个真相源）
arch_need "$SRC/src/ui/DesignTokens.h" 'namespace Alpha\b' 'DS 有透明度 token'
arch_need "$SRC/src/ui/DesignTokens.h" '\baccentTintRgba\b' 'DS 提供 rgba 拼装（调用方不拼字面量）'
arch_need "$SRC/src/ui/dialogs/AgentDialog.cpp" '\bDS::accentTintRgba\b' '用户气泡底色走 token 拼装'
arch_need_any_min '\bDS::Alpha::accentTint\b' 1 'SelfCheck 钉住透明度 token'

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
arch_need_any_min 'SemColors::stale\(\)' 8 'SelfCheck 钉住唯一出处的值'
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
arch_need "$SRC/scripts/build-deb.sh" '^_re_out="\$\(readelf -d "\$PKG\/usr\/bin\/deepDolphin" 2>&1\)" \|\| _re_rc=\$\?$' 'deb 构建**真的查了**包内二进制的 RPATH（⚠⚠⚨ **批 CC 原地替换**：形态从「管道直接判」改成「**接住 readelf 的退出码 + 分诊**」—— ⚠⚠⚨ 旧形态里 readelf **失败** ⇒ 管道无输出 ⇒ **静默判「没带 RPATH」⇒ 假绿**⇒ 现在非 0 ⇒ **判失败**（工具失败 = 没验过））（⚠ **批 CE：正则已跟着形态改** —— 现在盯的是「**接住 readelf 的退出码**」那一行 ⇒ 旧形态的管道判法被摘掉 ⇒ 门红）'
arch_need "$SRC/scripts/ci.sh" 'build-deb\.sh\b' 'CI 流程构建 deb（D7 达标必经）'

# 批 T · 面板快照夹具：基线要**可重现** ⇒ 快照走固定夹具，不走真引擎
#   （真引擎取数让基线取决于「本机注册了什么项目」——此前拍的是空态，
#     对状态色/布局全是空门）。
arch_need "$SRC/src/logic/SnapshotFixture.h" 'namespace SnapshotFixture [{]' '快照夹具有判定层（纯数据）'
arch_need_any_count 'useSnapshotFixture' 1 'AppModel 提供夹具注入' 'src/app/AppModel*.cpp'
arch_need "$SRC/src/main.cpp" 'useSnapshotFixture\(\)' '快照走夹具（不走真引擎）'
# 取数与判定分层：夹具与引擎必须共用**同一段解析**，否则夹具测不到真路径
arch_need_any_min 'applyStatusPayload' 3 '载荷应用抽成一层（夹具与引擎共用）' 'src/app/AppModel*.cpp'
arch_need_any_min 'applyDashboardPayload' 3 '载荷应用抽成一层（夹具与引擎共用）' 'src/app/AppModel*.cpp'
arch_need_any_min 'applyMilestonesPayload' 3 '载荷应用抽成一层（夹具与引擎共用）' 'src/app/AppModel*.cpp'
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
arch_need_any_count 'm_lastRefreshedMs = SnapshotFixture::fixedRefreshedMs\(\)' 1 '快照刷新时刻用固定值（不用墙钟）' 'src/app/AppModel*.cpp'
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
arch_need_any_min '绝对日期锚定基准日' 1 'SelfCheck 钉住绝对日期锚定（跨天也抓得住）'
arch_need_any_min '刷新时刻固定' 1 'SelfCheck 钉住刷新时刻固定'
# 「重拍比字节」这道门盯的是**行为**（两次拍出同一张图），不是文件里的字样。
# ⚠ 精确计数：ci.sh 里 `cmp -s` 出现**四处**（批 AN 补齐了缺口）：
#   ① 比 git 基线（本次产物 vs 基线 ⇒ 视觉改动必须有人看过并提交）
#   ② 比基线（单次运行内的重拍）
#   ③ 比换时区那张（跨时区必须一致）
#   ④ **跨运行**（新进程再拍一次，比基线 ⇒ 抓跨进程漂移）
#   只拿掉一处时「出现过」照样绿 ⇒ 门被骗过（负控实测，第十五次「同名互相顶替」）。
#   ⚠ 第四处是批 AN 加的：前三处都在**同一次运行内**比 ⇒ 抓不到「有时拍出另一种字节」
#   的漂移（实测真发生过：同机并发下 4 种字节）⇒ 必须有跨进程那一处。
arch_need_count "$SRC/scripts/ci.sh" '^    if ! cmp -s "\$BASE_DIR/\$name" "\$f"; then$' 1 'CI 有「重拍比字节」门（基线必须可重现，含跨运行复拍）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^        if ! cmp -s "\$BASE_DIR/\$\{theme\}-\$\{sec\}\.png" "\$again"; then$' 1 'CI 有「重拍比字节」门（基线必须可重现，含跨运行复拍）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^        if ! cmp -s "\$again" "\$other"; then$' 1 'CI 有「重拍比字节」门（基线必须可重现，含跨运行复拍）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^        if ! cmp -s "\$BASE_DIR/\$\{theme\}-\$\{sec\}\.png" "\$shot"; then$' 1 'CI 有「重拍比字节」门（基线必须可重现，含跨运行复拍）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
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
arch_forbid_ml "$SRC/scripts/ci.sh" '--(snapshot|color-sample)[^;]*[|] *tail' '快照/色卡命令不许接「| tail -1」（管道退出码是 tail 的 ⇒ 失败被吞）'
arch_need "$SRC/scripts/ci.sh" '2>"\$REPRO_DIR/stderr\.txt"' '快照失败时 stderr 要**落盘**（盯重定向那一行 —— 盯「stderr.txt」这个串，它在多处出现 ⇒ 改一处骗得过门）'

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
    # ⚠⚠⚨ 批 CE：**工具读不了文件 ⇒ 后面所有 grep 都会静默跳过它** ⇒ 漏检 ⇒ 假绿。
    #   ⇒ ⚠⚠⚨ **实测的洞**：把某个 `src/ui/*.cpp` 对 grep **不可读**（chmod 000
    #     ⇒ grep rc=2）⇒ `strip_comments "$f" | grep -qE 'QIcon::fromTheme'`
    #     **无输出** ⇒ **不进 then 分支** ⇒ **裸 QIcon::fromTheme 漏检**
    #     ⇒ 门照样绿（⚠ 与批 CD 的「假绿」同款：不是门坏了，是**门没看见**）。
    #   ⇒ 所以在扫之前**先验可读性**：读不了 ⇒ 判失败，**不许当成「没有裸图标」**
    #     （⚠ 与批 CB/CC/CD 同款口径：**未验证不许被当成通过**）。
    if [ ! -r "$f" ]; then
        echo "  ✗ 源文件不可读：$f ⇒ grep 会静默跳过它 ⇒ 图标收口检查会漏检 ⇒ **未验证不许当成通过**" >&2
        ICON_RAW=1
        ICON_STR=1
    fi
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
arch_need "$SRC/src/app/EngineInstaller.cpp" 'r\.bin = m_installDir \+ QStringLiteral\("/"\) \+ EngineDownload::packagedBinName\(\);' '包内文件名走判定层 —— 盯**真正拼出落盘路径**那一行'
arch_need_any_count '\bEngineDownload::releaseApiUrl\b' 1 'AppModel 走判定层取发布信息 URL' 'src/app/AppModel*.cpp'
arch_need_any_count 'void AppModel::downloadEngine\(\)' 1 'AppModel 暴露下载引擎' 'src/app/AppModel*.cpp'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'm_model->downloadEngine\b' '设置页有下载引擎入口'
arch_need "$SRC/src/app/EngineLocator.cpp" 'libexec/deepdolphin/moongit\b' '发现链认得下载链装的位置'
# ⚠ 用**精确计数**（两个调用点都要在）：`--engine-download` 在 main.cpp 出现两次
#   （contains 与 indexOf），只盯「出现过」时变异改掉其中一处门照样绿
#   （负控实测，第九次「同名/子串互相顶替」）。
arch_need_count "$SRC/src/main.cpp" 'QStringLiteral\("--engine-download"\)' 2 '无头入口可端到端验下载链（两个调用点都在）'
arch_need_any_min '\bEngineDownload::parseRelease\b' 3 'SelfCheck 覆盖下载判定层'
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
arch_need "$SRC/src/app/Notifier.cpp" 'm_replaceIds\.value\(Notifications::categoryOf\(title\), 0\)' '执行层的类别判定走判定层 —— 盯**查已登记的 id**那一行'
arch_need "$SRC/src/app/Notifier.cpp" 'm_replaceIds\.insert\(Notifications::categoryOf\(title\), id\)' '执行层的类别判定走判定层 —— 盯**登记 id**那一行（只查不登记 ⇒ 永远查不到 ⇒ 永远合并不了）'
arch_need "$SRC/src/app/Notifier.cpp" 'Settings::instance\(\)\.notifyTimeoutMs\(\)' '通知时长来自设置（不是硬编码）'
arch_need "$SRC/src/app/Settings.h" 'int notifyTimeoutMs\(\) const;' '设置层暴露通知时长'
arch_need "$SRC/src/app/Settings.h" 'void setNotifyTimeoutMs\(int ms\);' '设置层可写通知时长'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'm_notifyTimeout = new DComboBox' '设置·通用页有通知时长选择器'
arch_need "$SRC/src/ui/dialogs/panes/GeneralPane.cpp" 'setNotifyTimeoutMs\(' '通知时长选择器真的写回设置'
arch_need_any_min '\bNotifications::normalizeTimeoutMs\b' 5 'SelfCheck 覆盖通知时长归一'
arch_need_any_min '\bNotifications::replacesPrevious\b' 4 'SelfCheck 覆盖通知顶替规则'
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
# ⚠⚠⚠ **这条门原来盯的是错误消息里的「有判据被删了」** ⇒ 批 BB 改了消息文案就把它打断了
#   （审计器的「命中 0 ⇒ 红」当场抓到 —— 这正是批 AX 建的那道防静默失效的门在干活 ✔）。
#   ⚠ **盯消息文案本身就是脆的**（改个措辞就断）⇒ 改成盯**判定本身**，
#   并挪到「批 BB 段」去（那里有更强的三条：判定形式 + 基线唯一 + failed 恒 0）。
#   ⇒ 这里只留指针，别再盯文案。
#   （批 BB 段的门：`SC_PASSED" -ne "\$SC_MIN` / `SC_MIN=[0-9]+` / `SC_FAILED" -ne 0`）
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
arch_need_any_min 'SelfCheckInternal::checkDocs\(log\)' 1 '主片调用了文档页分片（不是把代码搬走就忘接）'
arch_need_any_min 'SelfCheckInternal::checkEngine\(log\)' 1 '主片调用了引擎分片'
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

# ── 批 AO · PLAN §3c 点名的另几处定宽截断：逐处核对后按**实际行为**处理 ──
#
# ⚠ 起因：批 AM 把 PLAN §3c 点名的 4 处留给后续（行号已漂移）⇒ 本批逐处**实测核对**。
#   ⚠ 结论不是「4 处都改」——**4 处的行为各不相同**（一刀切会改错）：
#   ① `ProjectProgressCard`（在 `src/ui/pages/`，**不在** `src/ui/` —— PLAN 路径也漂了）：
#      原来**同时**有「手工掐中间（按字符数 24）」+「`setMaximumWidth(220)`（按像素）」
#      两条截断 ⇒ **互相打架** ⇒ 实测 24 个**中文**字手工掐完仍 268px > 220px
#      ⇒ 照样**硬裁**（半个字）⇒ 缺陷**只在中文名下出现**（纯 ASCII 164px 不超宽）。
#      ⇒ 删掉手工截断，只留**按像素**的 `elidedText(ElideMiddle, …)` + 完整名 tooltip。
#   ② `DashboardPage` 的活跃项目 headline：来自**引擎**（长度不受控）
#      ⇒ 原来 `setMaximumWidth(300)` 是真硬裁 ⇒ 改省略号 + tooltip。
#   ③ `TrayPopupWindow` 的项目名：托盘弹窗宽固定、项目名长度不受控
#      ⇒ 原来 `setFixedWidth(120)` 是真硬裁 ⇒ 改省略号 + tooltip。
#   ④ `SidebarNav` 的**固定视图行**（仪表盘/看板/里程碑）：文本短、**永不溢出**
#      ⇒ 它的 `setMaximumWidth(120)` 是兜底上限，**不用改**；
#      ⚠ 但它的**原注释是错的**（写着「60 字项目名…带省略号」——① 不是项目名；
#        ② `setMaximumWidth` **不会**加省略号）⇒ 已订正（批 AI 教训：说法与实现相反更危险）。
#   ⚠ **不用改的 3 处也留了注释**（`WorkBar` 的 DComboBox / `GeneralPane` 与
#     `MilestonesPage` 的 DLineEdit）：它们分别是「控件自带省略号」与「超宽横向滚动」
#     ⇒ **不是硬裁** ⇒ 加省略号反而是倒退 ⇒ 注明原因，免得下次误改。
#   ⚠ `elidedText(` 与它的参数**跨行**（代码折行了）⇒ grep -E 按行匹配 ⇒ 匹配不到
#   ⇒ 用批 AO 新加的跨行门 `arch_need_ml`（压成一行再匹配）。
arch_need_ml "$SRC/src/ui/pages/ProjectProgressCard.cpp" 'elidedText\([^)]*p\.name, Qt::ElideMiddle' '项目名按**像素**中段省略（不是按字符数切——两条截断会打架，中文名仍被硬裁）'
arch_need "$SRC/src/ui/pages/ProjectProgressCard.cpp" 'setToolTip\(p\.name\)' '被中段省略的完整项目名可从 tooltip 看到'
# ⚠ **手工按字符数截断**不许复活（它与像素限宽打架 ⇒ 中文名溢出成半个字）
arch_forbid "$SRC/src/ui/pages/ProjectProgressCard.cpp" 'shown\.size\(\) > ' '项目名不许再按字符数手工截断（实测 24 个中文字仍 268px > 220px ⇒ 照样硬裁）'
# ⚠⚠ **「限宽 + 拉伸」这个组合不许复活**（批 AO 实测踩出来的布局坑）：
#   名字标签若既 `setMaximumWidth(...)` 又 `addWidget(name, 1)`（拉伸项），
#   Qt 会把**多出来的空间塞给下一个 Preferred 标签** ⇒ 那个 8px 的状态点标签被撑成
#   88px 宽（pixmap 画在它左边）⇒ 视觉上「●」与状态词之间裂开 ~86px 的缝，
#   且整组没贴到卡内右缘（实测 408px 行：name w=220 / dot w=**88** / state x=320）。
#   ⇒ 删掉限宽后 name 吃掉全部余量（w=364 / dot w=**8** / state x=384）⇒ 贴右，
#     与 mac 侧 `DashboardParts.swift:247-258`（`Text` + `Spacer`）一致。
#   ⚠ 视觉层由**仪表盘快照基线**兜底（重放这处改动 ⇒ 仪表盘快照变 ⇒ 视觉 diff 门红），
#     这里这两道门是**源码层**的提前拦截（快照门要跑完整 CI 才看得到）。
arch_forbid "$SRC/src/ui/pages/ProjectProgressCard.cpp" 'name->setMaximumWidth' '项目名标签不许再限宽（限宽 + 拉伸 ⇒ 余量被塞给状态点标签 ⇒ 状态词脱离圆点、整组不贴右）'
arch_need "$SRC/src/ui/pages/ProjectProgressCard.cpp" 'row1->addWidget\(name, 1\)' '项目名标签仍是拉伸项（它吃掉余量 ⇒ 状态点 + 状态词贴到卡内右缘）'
arch_need "$SRC/src/ui/pages/DashboardPage.cpp" 'elidedText\(' '活跃项目 headline 定宽截断用省略号（内容来自引擎、长度不受控）'
arch_need "$SRC/src/ui/pages/DashboardPage.cpp" 'setToolTip\(a\.headline\)' '被省略的完整 headline 可从 tooltip 看到'
arch_need "$SRC/src/tray/TrayPopupWindow.cpp" 'elidedText\(' '托盘弹窗项目名定宽截断用省略号（弹窗宽固定、项目名长度不受控）'
arch_need "$SRC/src/tray/TrayPopupWindow.cpp" 'setToolTip\(row\.name\)' '被省略的完整项目名可从 tooltip 看到'
# ⚠ **过时说法不许复活**（raw：不剥注释 ⇒ 有牙）：「带省略号为预期行为」这句话是错的
#   （`setMaximumWidth` 不加省略号）⇒ 侧栏那行不许再这么写。
arch_forbid_raw "$SRC/src/ui/SidebarNav.cpp" '带省略号为预期行为' '侧栏固定行注释不许再写「带省略号」（setMaximumWidth 不加省略号；且那行不是项目名）'

# ── 批 AP · M3c HiDPI：自绘位图必须按 dpr 放大（否则 125%/150%/200% 下发虚）──
#
# ⚠ **起因**：PLAN §3c 点名了 9 处 1x 自绘，但它那份名单**写在 IconResolver 存在之前**
#   （`IconLoader.cpp` 早已被批 AI 当死代码删掉）⇒ 照 PLAN 做会漏。
#   ⇒ 本批**实测扫全**（grep 所有 `QPixmap` 构造 + 所有 `QPainter` 用法），分成两类：
#   ① **离屏画到 pixmap**（11 处）⇒ 必须走 `platform::dpiPixmap()`：
#      状态点 5（LegendRow / ProjectProgressCard / DashboardPage / ProjectDetailPage /
#      SidebarNav 汇总点）、托盘 3（TrayPopupWindow 大点 + 迷你条 + TrayController 图标）、
#      里程碑五态图标 1、IconResolver 2（qrc 染色 SVG + 占位圆点）。
#   ② **直接画在控件上**（`QPainter p(this)`，8 处：StatusDot / SegmentedBar / FlatButton /
#      Card / ArchCanvasWidget / HeatmapWidget / ColorSampleSheet / TrayPopupWindow 自己的
#      paintEvent）⇒ **本来就对**：控件的画布已是 dpr 分辨率 ⇒ 不许也不需要改。
#      （Canvas2D 的阴影是按**设备像素**画的（`dev->width()` + 继承 transform）⇒ 也是对的。）
#
# ⚠ **为什么这层要有门**：结构事实由**探针**断言（`dpiPixmap=` 那行：缓冲区必须
#   = logical × dpr），效果事实由 **dpr=2 那一跑**断言（边缘过渡层数必须多于 1x）。
#   但探针只能证明**助手**对 ⇒ 11 个**调用点**有没有真的用它，靠下面这些门盯住。
arch_need "$SRC/src/platform/DpiPixmap.cpp" 'setDevicePixelRatio' 'DPI 助手必须设 devicePixelRatio（不设 ⇒ 位图仍按 1x 画 ⇒ 发虚）'
arch_need_ml "$SRC/src/platform/DpiPixmap.cpp" 'QPixmap pm\(logicalSize \* dpr\)' 'DPI 助手的缓冲区必须按 logicalSize × dpr 开（不放大 ⇒ 控件再放大一遍 ⇒ 发虚）'
arch_need "$SRC/src/ui/common/LegendRow.h" 'platform::dpiPixmap\(' '图例小点走 DPI 助手'
arch_need "$SRC/src/ui/pages/ProjectProgressCard.cpp" 'platform::dpiPixmap\(' '项目卡状态点走 DPI 助手'
arch_need "$SRC/src/ui/pages/DashboardPage.cpp" 'platform::dpiPixmap\(' '活跃项目状态点走 DPI 助手'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'platform::dpiPixmap\(' '分支状态点走 DPI 助手'
arch_need "$SRC/src/ui/SidebarNav.cpp" 'platform::dpiPixmap\(' '侧栏汇总大点走 DPI 助手'
arch_need_ml "$SRC/src/tray/TrayPopupWindow.cpp" 'QPixmap pm = platform::dpiPixmap\(' '托盘弹窗**汇总大点**走 DPI 助手（盯**变量名 + 调用**那一行 ⇒ 与迷你条那一行区分得开；批 AV 实测：盯 `platform::dpiPixmap(` 压行后命中 2 次 ⇒ 改一处骗得过门）'
arch_need_ml "$SRC/src/tray/TrayPopupWindow.cpp" 'QPixmap barPm = platform::dpiPixmap\(' '托盘弹窗**迷你条**走 DPI 助手（盯**变量名 + 调用**那一行 ⇒ 与大点那一行区分得开）'
arch_need "$SRC/src/tray/TrayController.cpp" 'platform::dpiPixmap\(' '托盘图标走 DPI 助手'
arch_need "$SRC/src/ui/pages/MilestoneRowWidget.cpp" 'platform::dpiPixmap\(' '里程碑五态图标走 DPI 助手'
arch_need_min "$SRC/src/platform/IconResolver.cpp" 'platform::dpiPixmap\(' 2 '图标兜底通道（qrc 染色 SVG + 占位圆点）**两处**都走 DPI 助手（两处源码相同 ⇒ 行级构造分不开 ⇒ 意图天然是「至少 2 次」；⚠ 这条门不在审计器覆盖内）'
# ⚠ **1x 位图构造不许复活**（这 9 个文件里，自绘位图**只能**由 DPI 助手开）
#   ⚠ 例外：`platform/DpiPixmap.cpp` 自己（它就是开位图的地方）、`main.cpp` 探针里的
#     `legacy` 对照组（**故意**留 1x 当基线）—— 这两处不在这 9 个文件里。
arch_forbid "$SRC/src/ui/common/LegendRow.h" 'QPixmap\s+(pm|barPm)\(' '图例小点不许再开 1x 位图'
arch_forbid "$SRC/src/ui/pages/ProjectProgressCard.cpp" 'QPixmap\s+(pm|barPm)\(' '项目卡状态点不许再开 1x 位图'
arch_forbid "$SRC/src/ui/pages/DashboardPage.cpp" 'QPixmap\s+(pm|barPm)\(' '活跃项目状态点不许再开 1x 位图'
arch_forbid "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'QPixmap\s+(pm|barPm)\(' '分支状态点不许再开 1x 位图'
arch_forbid "$SRC/src/ui/SidebarNav.cpp" 'QPixmap\s+(pm|barPm)\(' '侧栏汇总大点不许再开 1x 位图'
arch_forbid "$SRC/src/tray/TrayPopupWindow.cpp" 'QPixmap\s+(pm|barPm)\(' '托盘弹窗不许再开 1x 位图'
arch_forbid "$SRC/src/tray/TrayController.cpp" 'QPixmap\s+(pm|barPm)\(' '托盘图标不许再开 1x 位图'
arch_forbid "$SRC/src/ui/pages/MilestoneRowWidget.cpp" 'QPixmap\s+(pm|barPm)\(' '里程碑图标不许再开 1x 位图'
arch_forbid "$SRC/src/platform/IconResolver.cpp" 'QPixmap\s+(pm|barPm)\(' '图标兜底通道不许再开 1x 位图'
# ⚠ **探针必须报出 DPI 事实**（不报 ⇒ 缩放倍率不可见 ⇒ HiDPI 无从断言）
#   ⚠ 盯**格式串**（`%g` / `%d`）而不是裸字段名 —— 裸字段名在**注释与提示语**里也出现
#   （负控实测：把探针的字段名改掉，接线门照样绿 ⇒ 门被措辞满足了）。
arch_need "$SRC/src/main.cpp" 'devicePixelRatio=%g' '平台探针报出当前 devicePixelRatio（盯格式串）'
arch_need "$SRC/src/main.cpp" 'dpiEdgeLevels=legacy:%d' '平台探针报出自绘位图的边缘过渡层数（盯格式串）'
# ⚠⚠ **「dpr=2 那一跑」不许被删** —— 删了它，边缘层数那条断言就永远跑在 dpr=1 上
#   （两列必然相同 ⇒ 恒成立 ⇒ 空门）。批 AJ 教训：承诺没有门 = 承诺不存在。
#   ⚠ 盯**命令本身**（`dpi_b_out=…QT_SCALE_FACTOR=2`）而不是裸串 ——
#   裸串在**错误提示语**里也出现（负控实测：把那一跑改成 1x，接线门照样绿）。
arch_need_count "$SRC/scripts/ci-platform-probe.sh" '^dpi_b_out="\$\(QT_SCALE_FACTOR=2 "\$BIN" --platform-probe\)" \|\| dpi_b_rc=\$\?$' 1 'HiDPI 的效果断言必须真在 dpr=2 下跑（不许退化成 dpr=1 的空断言）｜⚠⚠⚨ **批 BX**：退出码必须**在同行**取（`|| dpi_b_rc=$?`）——「下一行再取 `$?`」的形态**中间插一行就断**（`$?` 变成上一条命令的）｜⚠⚠⚨ **批 BS：整行锚定**（盯的是「那**一行**」⇒ QT_SCALE_FACTOR=2 被挪去别处或挪进行尾注释 ⇒ 立刻红；裸盯串时这两种都骗得过门）'
arch_need_count "$SRC/scripts/ci-platform-probe.sh" '^dpi_b_legacy="[^;]*dpiEdgeLevels=legacy:[^;]*\\1/p.\)"$' 1 'HiDPI 门必须断言边缘过渡层数 —— 盯**解析 legacy 那一列**的那行｜⚠⚠⚨ **批 BS：整行锚定**（裸盯串 ⇒ 挪进行尾注释就骗得过门）'
arch_need_count "$SRC/scripts/ci-platform-probe.sh" '^dpi_b_aware="[^;]*dpiEdgeLevels=\.\*aware:[^;]*\\1/p.\)"$' 1 'HiDPI 门必须断言边缘过渡层数 —— 盯**解析 aware 那一列**的那行（两列都要在 ⇒ 少一列就抓不到「dpr 感知更细腻」）｜⚠⚠⚨ **批 BS：整行锚定**'

# ── 批 AQ · mac 侧引擎下载链：写死的 404 URL + 虚构的产物布局（跨目录盯 macos/）──
#
# ⚠ **起因**：mac 侧 `build.sh` 的下载路径有**三个**叠在一起的错，
#   而它们**从未被发现**（因为那条路径从来没成功过 ⇒ 没人见过它成功的样子）：
#   ① URL 写死 `releases/latest/download/moongit-darwin-arm64.tar.gz`
#      —— release 资产名**带版本号**（`moongit-v0.2.1-darwin-arm64.tar.gz`），
#      而 `latest/download` 要求**资产名精确匹配** ⇒ **必然 404**；
#   ② 找「包根的 `moongit-cli`」—— 真实包里**没有**那个文件
#      （包根是**启动器** `moongit`，真二进制在 `bin/moongit-cli`）⇒ 找不到；
#   ③ 只复制那一个文件、**把 `runtime/lib/` 丢掉** ⇒ 装下来的引擎**根本起不来**
#      （缺仓颉运行时）。deepin 侧早已踩过同一族坑，见
#      `deepin/src/logic/EngineDownload.h`。
# ⇒ 修法：`macos/scripts/fetch-engine.sh`（查 API 按**后缀**挑资产 → 整包下载 →
#   整包解包 → 验「启动器 / bin/moongit-cli / runtime/lib」三样齐全）。
#   行为判据：`macos/scripts/engine-fetch-check.sh`（**不依赖 macOS**，Linux 上可跑）。
#
# ⚠ 下面这些是**静态门**：它们进 deepin 的 CI（每次都跑、无网络依赖），
#   行为判据（真下载）需要网络，手工跑 —— 两者互补。
# ⚠ 用 `arch_forbid`（**剥注释**）而不是 `arch_forbid_raw`：
#   注释里**提到**那个旧 URL 是正常的（要解释它为什么坏）⇒ 措辞不该算数，
#   只有**代码里真的用它**才算数。批 AP 的教训换了个方向：门盯的串
#   必须**只被代码满足**（否则门既会被措辞骗过、也会被措辞误伤）。
arch_forbid "$ROOT/macos/build.sh" 'releases/latest/download/moongit-' 'mac build.sh 不许再写死 latest/download 的引擎 URL（资产名带版本号 ⇒ 必然 404）'
arch_need "$ROOT/macos/build.sh" 'fetch-engine\.sh' 'mac build.sh 的下载走 fetch-engine.sh（查 API 挑资产 + 整包落盘）'
arch_forbid "$ROOT/macos/scripts/fetch-engine.sh" 'releases/latest/download' 'fetch-engine.sh 也不许写死 latest/download（同样必然 404）'
arch_need "$ROOT/macos/scripts/fetch-engine.sh" 'grep -o ..browser_download_url' 'fetch-engine.sh 从 API 的资产列表里**取**下载地址（盯那一行 grep —— 盯「browser_download_url」这个串，它在**取 + 洗**两处都出现 ⇒ 改一处骗得过门）'
arch_need "$ROOT/macos/scripts/fetch-engine.sh" 'sed .s/.*"browser_download_url' 'fetch-engine.sh 把取到的 URL **洗**成纯地址（盯那一行 sed）'
arch_need "$ROOT/macos/scripts/fetch-engine.sh" '\[ -x "\$pkg_root/bin/moongit-cli" \]' 'fetch-engine.sh 认得真二进制的真实位置（bin/ 下，不是包根）—— 盯那行**验它可执行**的检查'
arch_need "$ROOT/macos/scripts/fetch-engine.sh" '\[ -d "\$pkg_root/runtime/lib" \]' 'fetch-engine.sh 认得仓颉运行时的真实位置（runtime/lib/）—— 盯那行**验目录存在**的检查'
arch_need "$ROOT/macos/scripts/fetch-engine.sh" '\[ -n "\$\(ls -A "\$pkg_root/runtime/lib" 2>/dev/null\)" \]' 'fetch-engine.sh 还**验 runtime/lib 非空**（目录在但空 ⇒ 引擎照样起不来）'
arch_need "$ROOT/macos/scripts/engine-fetch-check.sh" '\[ -x "\$DEST/bin/moongit-cli" \]' '引擎下载链判据验「三样齐全」（缺一就是装了个跑不起来的引擎）—— 盯那行**验真二进制可执行**的检查'
arch_need "$ROOT/macos/scripts/engine-fetch-check.sh" 'if \[ -d "\$DEST/runtime/lib" \] &&' '引擎下载链判据验仓颉运行时**存在且非空** —— 盯那行判定'
# ⚠ 盯**干活的那一行**（把包里的 dylib 拷进 Frameworks），不是盯「runtime/lib」这个串 ——
#   负控实测：只删掉那句拷贝，`runtime/lib` 仍然出现在**形状判定**那行 ⇒ 门照样绿。
#   （批 AP 的同一条纪律：门必须盯「真正干活的那行」，不能盯一个碰巧出现的串。）
arch_need "$ROOT/macos/build.sh" 'cp .*ENGINE_ROOT/runtime/lib/.*dylib' 'mac build.sh 内嵌引擎时把包自带的运行库一起拷进 Frameworks（缺它 ⇒ 内嵌引擎起不来）'
arch_need "$ROOT/macos/build.sh" 'cp "\$ENGINE_ROOT/bin/moongit-cli"' 'mac build.sh 内嵌的是包里的**真二进制**（内嵌进 bundle 的必须是 Mach-O，rpath 重写与补签才对它有意义）—— 盯**拷贝**那一行，不是盯「判断形状」那一行'

# ── 批 AR · mac 侧「导出后打不开」：回执里的路径抽不出来（跨目录盯 macos/）──
#
# ⚠ **起因**：deepin 侧 `logic/ArchReceipt.cpp` 的注释里**早就写着**这个 mac 缺陷
#   （「mac 的 extractHTMLPath 就栽在这里，导出后「打开」入口始终不出现」），
#   但**一直没修**。批 AR 用**引擎实跑**把形态坐实了：
#   `moongit render arch` 的真实回执是
#     已写入：<绝对路径> · 共 N 个文件，N 个函数（…）
#   —— 路径与文案之间是**全角冒号**（**没有空格**）。
#   ⇒ mac 侧那份同名实现按**空格**切词 ⇒ 切出「已写入：/path/arch.html」这种粘连块
#   ⇒ `hasPrefix("/")` 恒假 ⇒ **抽不出路径** ⇒ 「打开」入口**始终不出现**（死按钮）。
#   ⚠ 而且它是**两份同名复制**（ArchPage + CodeGraphPage）⇒ 改一处漏一处、也测不到。
#
# ⚠ **本机没有 Swift 工具链** ⇒ mac 的 Swift 代码**编不了、也测不了**。
#   ⇒ 这批把可判的部分全做成**跨目录静态门**（每次 deepin CI 都跑），
#     行为侧由 mac 侧 `scripts/client-check.sh` 的纯函数判据承担
#     （本文件已进它的编译清单 + `Tests/ClientCheck/main.swift` 已加四条断言）。
arch_need "$ROOT/macos/Sources/deepDolphin/ArchReceipt.swift" 'enum ArchReceipt' 'mac 侧的回执解析必须是**纯函数**（能进 client-check 的编译清单 ⇒ 才测得到）'
arch_need "$ROOT/macos/Sources/deepDolphin/ArchReceipt.swift" 'u\{FF1A\}' '路径边界必须认**全角冒号**（引擎真实回执就靠它把路径和文案粘在一起；漏了 ⇒ 抽不出路径）'
arch_need "$ROOT/macos/Sources/deepDolphin/ArchReceipt.swift" 'u\{00B7\}' '路径边界必须认**中点**（引擎真实回执里路径后面跟的就是它）'
arch_need "$ROOT/macos/Sources/deepDolphin/ArchReceipt.swift" 'hasPrefix\("/"\)' '只认**绝对路径**（相对路径打不开 ⇒ 宁可不给「打开」入口）'
arch_forbid "$ROOT/macos/Sources/deepDolphin/ArchPage.swift" 'private func extractHTMLPath' 'ArchPage 不许再自带一份回执解析（同名复制会漂移）'
arch_forbid "$ROOT/macos/Sources/deepDolphin/CodeGraphPage.swift" 'private func extractHTMLPath' 'CodeGraphPage 不许再自带一份回执解析（同名复制会漂移）'
arch_need "$ROOT/macos/Sources/deepDolphin/ArchPage.swift" 'ArchReceipt\.htmlPath\(' 'ArchPage 走共享的纯函数'
arch_need "$ROOT/macos/Sources/deepDolphin/CodeGraphPage.swift" 'ArchReceipt\.htmlPath\(' 'CodeGraphPage 走共享的纯函数'
arch_need "$ROOT/macos/scripts/client-check.sh" 'swiftc .*\$ARCHRECEIPT' 'mac 侧判据必须**在 swiftc 那行**编译 ArchReceipt.swift（只声明不编 ⇒ 那四条断言永远绿、永远抓不到东西）'
arch_need "$ROOT/macos/Tests/ClientCheck/main.swift" 'let p = ArchReceipt\.htmlPath\(realArchReceipt\)' 'mac 侧判据必须真的断言「引擎真实回执形态抽得出路径」—— 盯**实跑原文**那条断言'
arch_need "$ROOT/macos/Tests/ClientCheck/main.swift" 'if let p = ArchReceipt\.htmlPath\(text\) \{' 'mac 侧判据必须真的断言「结论行也能抽出路径」—— 盯那条断言'
arch_need "$ROOT/macos/Tests/ClientCheck/main.swift" 'guard let h = ArchReceipt\.htmlPath\(text\)' 'mac 侧判据必须真的断言「相对路径不认」—— 盯那条断言'
# ⚠ deepin 侧那条**实跑夹具**也钉住（它是两侧共同的口径来源）
arch_need "$SRC/src/app/SelfCheckGraph.cpp" 'ArchReceipt::htmlPath\(QStringLiteral\("已写入：' 'deepin 侧自检必须钉住**引擎实跑原文**的回执形态 —— 盯**夹具**那一行（之前盯「已写入：」⇒ 改**说明文字**也会红 ⇒ 盯错了地方）'

# ── 批 AS · mac 侧布尔旗标只认 Bool ⇒ 模型写成字符串时**恒为假**（跨目录盯 macos/）──
#
# ⚠ **起因**：`AgentCore.swift` 里那句注释本来就写着「模型给的布尔/数字经
#   JSONSerialization 可能落成 Bool/Int/Double/String」——
#   而**实现只有 `as? Bool`** ⇒ **说法与实现相反**（批 AI 的教训：
#   说法与实现相反比说法缺失更危险）。
#   ⇒ 只认 Bool 时：模型把旗标写成**字符串**（`"force": "true"`）
#   或非 0/1 的数（`2`）⇒ `as? Bool` 落空 ⇒ 旗标**恒为假**
#   ⇒ 症状：AI 说「强制重跑」，`render arch --force` / `arch gen --force`
#   **静默不生效**（命令照发、旗标没了），界面上还显示「✓ 执行成功」。
#   ⇒ 修法：抽成纯函数 `ToolArgs.flag`（该文件**本就在** agent-check 的编译清单里
#   ⇒ 判据脚手架现成），`AgentCore` 改调它。
arch_forbid "$ROOT/macos/Sources/deepDolphin/AgentCore.swift" 'as\? Bool\) == true' 'AgentCore 不许再只用 `as? Bool` 判旗标（模型写成字符串/非 0/1 的数时恒假 ⇒ --force 静默不生效）'
arch_need "$ROOT/macos/Sources/deepDolphin/AgentCore.swift" 'ToolArgs\.flag\(' 'AgentCore 的旗标解析走共享纯函数'
arch_need "$ROOT/macos/Sources/deepDolphin/ToolArgs.swift" 'static func flag\(' 'ToolArgs 必须提供纯函数版的旗标解析（能进 agent-check 的编译清单 ⇒ 才测得到）'
arch_need "$ROOT/macos/Sources/deepDolphin/ToolArgs.swift" '"true"' '旗标必须认**字符串**形态的 true（模型把布尔写成字符串是真实形状）'
arch_need "$ROOT/macos/scripts/agent-check.sh" 'swiftc .*"\$ARGS"' 'mac 侧判据必须**在 swiftc 那行**编译 ToolArgs.swift（只声明不编 ⇒ 断言永远绿）'
# ⚠ **第四次同一形状**（批 AP 被注释满足 / 批 AQ 在无关的另一行也出现 /
#   批 AR 只声明不编译也算出现 / **批 AS：测试文件里同一个 `ToolArgs.flag(` 出现 8 处**，
#   负控的变异只动其中 1 处 ⇒ 门不红 ⇒ 被负控当场抓到）
#   ⇒ **门盯的串必须只出现在干活的那一行** ⇒ 这里改成盯**每条断言独有的调用构造**
#   （实测每个构造在 macos/ 下都**只命中 1 次**），
#   再加一条「调用点不许被削减」的计数门（掏空任一条断言 ⇒ 少一处调用 ⇒ 红）。
arch_need_min "$ROOT/macos/Tests/AgentCheck/main.swift" 'ToolArgs\.flag\(' 6 'mac 侧判据的旗标断言**调用点不许被削减**（掏空任一条断言 ⇒ 少一处调用 ⇒ 本门红）'
arch_need "$ROOT/macos/Tests/AgentCheck/main.swift" 'where !ToolArgs\.flag\(p, "force"\)' 'mac 侧判据必须真的跑过**字符串形态的真值表**（掏空成恒真 ⇒ 本门红）'
arch_need "$ROOT/macos/Tests/AgentCheck/main.swift" 'where ToolArgs\.flag\(p, "force"\)' 'mac 侧判据必须真的跑过**假值/缺省表**（掏空成恒假 ⇒ 本门红）'
arch_need "$ROOT/macos/Tests/AgentCheck/main.swift" 'ToolArgs\.flag\(\["force": 1\], "force"\)' 'mac 侧判据必须钉「数字 1 为真」'
arch_need "$ROOT/macos/Tests/AgentCheck/main.swift" '!ToolArgs\.flag\(\["force": 2\], "force"\)' 'mac 侧判据必须钉「数字**只有 1 为真**（2 为假 ⇒ 与 deepin 侧同口径）」'

# ── 批 AS · **门自审计**：门盯的串必须**只出现在干活的那一行** ──
#
# ⚠ **第四次同一形状**（批 AP 被注释满足 / 批 AQ 在无关的另一行也出现 /
#   批 AR 只声明不编译也算出现 / **批 AS：测试文件里 8 处同形调用，
#   负控只动其中 1 处 ⇒ 门不红 ⇒ 被负控当场抓到**）
#   ⇒ 接线门判的是「某个串在不在」⇒ **同一串出现 >1 次时，
#     「改掉其中一处」就骗得过门**（别处还顶着呢）。
#   ⇒ 前三次都是**事后人工发现** ⇒ 这里让**机器当场审**：
#   `ci-wiring-audit.py` 逐条数每个 arch_need 门项的正则在目标文件里命中几次，
#   **豁免基线之外**只要还有一条命中 >1 ⇒ 本门红。
# ⚠ 豁免基线 = `scripts/wiring-multi-hit.exempt`（**纯数据、零注释**）：
#   历史 53 条已知隐患**显式入账**（不再藏在暗处）⇒ **新加的门不许落进去**。
#   某条门收紧到唯一构造后 ⇒ 审计器会报「豁免基线里已失效」⇒ 可以清掉。
# ⚠ **有意不审的两种门**（审计器自己说明，别当漏审）：
#   · arch_forbid（判「不该有的东西没了」⇒ 目标串出现 >0 本来就红）；
#   · arch_need_min（判「**至少** N 次」⇒ 命中 >1 本来就是它的语义）。
ARCH_N=$((ARCH_N + 1))
if ! command -v python3 >/dev/null 2>&1; then
    echo "  ✗ 门自审计跑不起来：没有 python3（这条门不许 SKIP —— SKIP 等于没门）" >&2
    ARCH_FAIL=1
else
    AUDIT_OUT="$(mktemp)"
    AUDIT_ERR="$(mktemp)"
    if python3 "$SRC/scripts/ci-wiring-audit.py" --list >"$AUDIT_OUT" 2>"$AUDIT_ERR"; then
        echo "  ✓ 门自审计：豁免基线之外的「串不唯一」隐患 0 条"
    else
        _audit_rc=$?
        # ⚠⚠ **按审计器的退出码说原因**（批 AZ 实测查出来的失准）：
        #   原来这一行**只说一种原因**（「新加的门盯的串不唯一」），
        #   可审计器有 **9 种**失败态（见 ci-wiring-audit.py 的 main()）：
        #     2 = 审计器自己有盲区（有门项没解析到 ⇒ 它们**根本没被审**）
        #     3 = 豁免基线之外有「串不唯一」的隐患
        #     4 = 次数门配准失准（期望次数 ≠ 实际命中数 ⇒ 门没牙或恒红）
        #     5 = 正则写法体检不过，或**有门项命中 0 次**（门永远匹配不到）
        #     6 = **门项行数与基线不符**（批 BH：门项被删了 / 被改成注释了）
        #     7 = **审计器自己有重名常量**（批 BH：后定义覆盖先定义 ⇒ 先那个是死代码）
        #     8 = **盯探针的门项不是整行锚定**（批 BL：判定被掏空但串还在 ⇒ 门假绿）
        #     9 = **审计器引用了未定义的名字**（批 BN：改名漏改调用点 ⇒ 那条路径没人跑
        #         ⇒ 崩了没人发现）或**锚定豁免基线有坏行**（豁免表写坏了 ⇒ 豁免判定失准）
        #   ⇒ 真实原因不是「串不唯一」时，那句话**指错了方向**（排障会被带偏）。
        #   ⚠ 实测（批 AZ 负控）：把新加的 `arch_need_count` 目标串删掉 ⇒
        #     审计器报的是「命中 0 次 ⇒ 门恒红」(rc=4)，而旧消息说的是「串不唯一」⇒ **两回事**。
        case "$_audit_rc" in
            2) _audit_why="审计器自己有盲区（有门项没解析到 ⇒ 它们**根本没被审**）｜⚠ **也可能是门型对拍的判定被掏空**（恒真 ⇒ 恒走这一支 ⇒ 明明没盲区也报盲区）⇒ 这时看 rc=4（次数门配准，指名道姓是哪条门项命中 0）｜⚠⚠⚨ **批 CF**：也可能是**缺 perl**（剥注释工具）⇒ 审计器**根本没审 C++ 侧的门项** ⇒ 同样是盲区（审计器自己会指名道姓地说这一条）｜⚠⚠⚨ **批 CH**：也可能是**源文件读不了**（权限）⇒ 那些门项**根本没被审** ⇒ 同样是盲区（审计器自己会指名道姓说是哪个文件、为什么读不了）｜⚠⚠⚨ **批 CW**：**崩了不再走这一档** ⇒ 崩了 ⇒ **专属码 rc=10**（分诊表里**单独一档**）⇒ 这一档现在**只**表示盲区" ;;
            3) _audit_why="豁免基线之外有「串不唯一」的隐患（改一处骗得过门）" ;;
            4) _audit_why="次数门配准失准（期望次数 ≠ 实际命中数 ⇒ 门没牙或恒红）" ;;
            5) _audit_why="正则写法体检不过，或**有门项命中 0 次**（门永远匹配不到）" ;;
            6) _audit_why="**门项行数与基线不符**（有门项被删了 / 被改成注释了 ⇒ 那些承诺没人守了）" ;;
            7) _audit_why="**审计器自己有重名常量**（后定义覆盖先定义 ⇒ 先那个是死代码 ⇒ 判定可能压根没生效）" ;;
            8) _audit_why="盯探针的门项**不是整行锚定**（判定被掏空但串还在 ⇒ 门假绿；或锚定形态的**自检**不过 ⇒ 判定本身被掏空）" ;;
            9) _audit_why="审计器引用了**未定义的名字**（改名漏改调用点 ⇒ 那条路径没人跑 ⇒ 崩了没人发现）或**锚定豁免基线有坏行**（豁免表写坏了 ⇒ 豁免判定失准 ⇒ 审计器自己失准）" ;;
            10) _audit_why="审计器**崩了**（崩 ⇒ 那些检查**没跑完** ⇒ 那些门项**根本没被审** ⇒ 同样是盲区；⚠⚠⚨ **批 CW**：这是**专属码** ⇒ 不再与 rc=2 的「盲区」混在一档 ⇒ ⚠ **先修审计器**，别去查盲区）" ;;
            *) _audit_why="未知的失败码" ;;
        esac
        echo "  ✗ 门自审计没过（退出码 $_audit_rc）：$_audit_why" >&2
        sed 's/^/      /' "$AUDIT_ERR" >&2
        sed 's/^/      /' "$AUDIT_OUT" >&2
        ARCH_FAIL=1
    fi
    rm -f "$AUDIT_OUT" "$AUDIT_ERR"
fi

# ── 批 AT · 豁免基线清账（第一轮）：把「盯名字」的门改成「盯接线点」──
#
# ⚠ 门自审计（批 AS）报出 **53 条**「同一串在目标文件里命中 >1 次」的历史门
#   ⇒ 它们的形态都是**盯名字不盯接线点** ⇒ 改一处骗得过门。
# ⚠ 仓库里其实**早就有**这个认识（语法高亮那段注释写着「这已是第三回『门盯名字不盯接线点』」）
#   ⇒ 批 AT 把它**逐条**补齐：每条改成盯**唯一**的构造点/接线点。
# ⚠ 改法有两种，**取「改」不取「另加」**：
#   「改」   = 弱门本身改成盯接线点 ⇒ 门项数不变、意图**更强**（存在 ⇒ 必有构造点）、
#              且**豁免基线能缩小**（不再命中 >1）；
#   「另加」 = 弱门留着 + 新增强门 ⇒ 门项 +1、基线**不缩**（弱门仍在暗处）。
# ⚠ 每改一条都要配一条**负控**：证明收紧后的门**仍能抓住**「把那一行改坏」。

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
arch_need_any_count '\bEngineHook::parseStatus\b' 1 '执行层走判定层解析钩子状态' 'src/app/AppModel*.cpp'
arch_need_any_count 'void AppModel::loadHookStatus\(\)' 1 'AppModel 暴露查钩子状态' 'src/app/AppModel*.cpp'
arch_need_any_count 'void AppModel::installHooksAll\(\)' 1 'AppModel 暴露装钩子' 'src/app/AppModel*.cpp'
arch_need_any_count 'void AppModel::uninstallHooksAll\(\)' 1 'AppModel 暴露卸钩子' 'src/app/AppModel*.cpp'
arch_need "$SRC/src/ui/dialogs/panes/AutomationPane.cpp" 'm_model->installHooksAll\b' '自动化页有装钩子入口'
arch_need "$SRC/src/ui/dialogs/panes/AutomationPane.cpp" 'm_model->uninstallHooksAll\b' '自动化页有卸钩子入口'
arch_need "$SRC/src/main.cpp" '--hook-status-parse"' '无头入口可验钩子判定层'
arch_need_any_min '\bEngineHook::parseStatus\b' 6 'SelfCheck 覆盖钩子判定层'
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
arch_need_any_min 'Backend::classify\(' 12 'SelfCheck 覆盖后端分档判定'
arch_need_any_min 'Backend::activationFor\(' 3 'SelfCheck 覆盖激活动作计划'
arch_need_any_min 'Backend::placePopup\(' 9 'SelfCheck 覆盖托盘弹窗落点'
arch_need_any_min 'Backend::reservedInsets\(' 2 'SelfCheck 覆盖任务栏边距'
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
arch_need_any_min 'PanelGeometry::usableArea\(' 9 'SelfCheck 覆盖面板可用区'
arch_need_any_min 'usedPanelGeometry' 3 'SelfCheck 覆盖面板感知落点'

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
# ⚠ 这里报的是**本段**的项数（批 X 段还没跑）⇒ 末尾那行才报**总项数**。
#   批 X 照出：文档里写的「N 项」原先**没法自证** —— 脚本自己报的那个数
#   是中途的计数，批 X 段又加了项却没报总账 ⇒ 「371 项」这种说法不可核。
#   ⇒ 末尾统一报总项数（见文件末尾）。
if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：取数/判定/渲染/接线任一段被摘掉" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 接线完整（取数 → 判定 → 渲染 → 接线，前段 ${ARCH_N} 项）"
fi
ARCH_FAIL=0

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
arch_need "$SRC/src/platform/TraySni.cpp" 'for \(const QString &name : TraySni::requiredProperties\(\)\)' '平台层用判定层的必填属性表 —— 盯**逐个读属性名**那一行'
arch_need "$SRC/src/platform/TraySni.cpp" 'const QStringList pixProps = TraySni::requiredProperties\(\);' '平台层用判定层的必填属性表 —— 盯**取整张表**那一行'
arch_forbid "$SRC/src/platform/TraySni.cpp" 'QStringLiteral\("IconPixmap"\)|QStringLiteral\("AttentionIconPixmap"\)|QStringLiteral\("OverlayIconPixmap"\)' '平台层不硬写 pixmap 属性名（真相源唯一）'
# ⚠ 平台层必须**逐个**暴露这三个属性（宿主读不到就注销）⇒ propertyValue() 里按必填表分发。
arch_need_count_in_fn "$SRC/src/platform/TraySni.cpp" '^[[:space:]]*bool propertyValue\(' 'pixProps\.contains\(prop\)' 1 '平台层按必填表逐个暴露三个 pixmap 属性（宿主读不到就注销）'
# introspect XML 必须**按必填表生成**三个 pixmap 声明（宿主按 XML 找属性，缺了直接不读）。
arch_need_count_in_fn "$SRC/src/platform/TraySni.cpp" '^[[:space:]]*QString introspect\(' 'TraySni::requiredProperties\(\)' 1 '平台层 introspect 按必填表生成三个 pixmap 声明'
# D-Bus 读必须带超时：`QDBusInterface::property()` 没有超时参数 ⇒ 禁用。
arch_need_min "$SRC/src/platform/TraySni.cpp" 'QDBus::Block, 2000' 4 'watcher 读带 2s 超时（不卡 GUI 线程）—— **四处同形** ⇒ 行级构造分不开 ⇒ 意图天然是「至少 4 次」；⚠ 这条门**不在审计器覆盖内**'
arch_forbid "$SRC/src/platform/TraySni.cpp" 'QDBusInterface::property|\.property\(' 'watcher 读不用无超时的 property()'
# 结构体签名推不出来 ⇒ 必须显式注册（否则 D-Bus 侧签名是空的）。
arch_need "$SRC/src/platform/TraySni.cpp" 'registerCustomType\(QMetaType::fromType<Pixmap>\(\),' '自定义结构体显式注册 D-Bus 签名 —— 盯**注册 Pixmap**那一行'
arch_need "$SRC/src/platform/TraySni.cpp" 'registerCustomType\(QMetaType::fromType<QList<Pixmap>>\(\),' '自定义结构体显式注册 D-Bus 签名 —— 盯**注册 Pixmap 列表**那一行'
arch_need "$SRC/src/platform/TraySni.cpp" 'registerCustomType\(QMetaType::fromType<ToolTip>\(\),' '自定义结构体显式注册 D-Bus 签名 —— 盯**注册 ToolTip**那一行'

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
arch_need_any_min 'TraySni::classifyHost\(' 4 'SelfCheck 覆盖 host 变体判定'
arch_need_any_min 'TraySni::encodeArgb32NetworkOrder\(' 4 'SelfCheck 覆盖像素编码'
arch_need_any_min 'TraySni::requiredProperties\(' 1 'SelfCheck 覆盖必填属性表'
arch_need "$SRC/src/main.cpp" 'sniWatcher=' '无头探针报出 SNI watcher 状态'
arch_need "$SRC/src/main.cpp" 'sniHost=' '无头探针报出 host 变体'
arch_need_any_min 'typeToSignature' 2 'SelfCheck 覆盖 D-Bus 签名声明（不声明宿主会按 av 解）'

# ⚠⚠ **字节级判据只能放真机端到端探针**：`--selfcheck` 跑在 QApplication 构造之前
#   ⇒ 没有总线；且 `QDBusArgument` 一旦写入就是**只写**的 ⇒ 同一份数据读不回来
#   ⇒ 放 selfcheck 里只会得到一个「永远红/永远绿」的假判据。
#   ⇒ 探针必须**从总线另一端**（外部进程 gdbus）读 IconPixmap。
arch_need "$SRC/scripts/probe-sni-icon.sh" 'Properties\.Get org\.kde\.StatusNotifierItem IconPixmap' '端到端探针**真的去读 IconPixmap 属性**（字节级判据放真机探针）—— 盯那行 D-Bus 调用，不是盯「IconPixmap」这个词'
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
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 X 段门项全绿（SNI 托盘）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

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
arch_need "$SRC/src/platform/DeepinTray.cpp" 'xcb_get_selection_owner\(conn, atom\)' '用 XGetSelectionOwner 查选区持有者（xprop 查不到选区）—— 盯**真的去查**那一行（之前盯「xcb_get_selection_owner」⇒ 类型名 `xcb_get_selection_owner_reply_t` 里也有 ⇒ 改一处骗得过门）'
arch_need "$SRC/src/platform/DeepinTray.cpp" '_NET_SYSTEM_TRAY_OPCODE' '用 _NET_SYSTEM_TRAY_OPCODE 发 dock 请求'
arch_need "$SRC/src/platform/DeepinTray.cpp" 'dockFieldIndex\(TraySni::DockField::Opcode\)' 'opcode 的下标取自判定层（平台层不许写死数字）'
arch_need "$SRC/src/platform/DeepinTray.cpp" 'dockFieldIndex\(TraySni::DockField::WindowId\)' '窗口 id 的下标取自判定层（平台层不许写死数字）'
arch_forbid "$SRC/src/platform/DeepinTray.cpp" 'data\.l\[0\] = [^0]' 'ClientMessage 的 l[0] 不用（deepin 从 l[1] 读）'
# ⚠⚠ **`values[]` 的顺序必须按 mask 位升序** —— 写反了 ⇒ 32 位 ARGB 窗口
#   「建了却不存在」（GetWindowAttributes 报 BadWindow）⇒ daemon 认不出它。
arch_need "$SRC/src/platform/DeepinTray.cpp" 'XCB_CW_BORDER_PIXEL \| XCB_CW_EVENT_MASK \| XCB_CW_COLORMAP' '建窗的 value_mask 按位升序（values 顺序错 ⇒ 窗口建不出来）'
arch_need "$SRC/src/platform/DeepinTray.cpp" 'xcb_visualid_t visual = advertisedVisual\(g_x11\.conn, owner\);' '用 daemon 广告的 _NET_SYSTEM_TRAY_VISUAL（协议要求）—— 盯**调用**那一行（盯定义的话，调用被摘了门照样绿）'
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
arch_need_min "$SRC/src/tray/TrayController.cpp" 'm_backend == TraySni::Backend::DeepinWindow' 3 'deepin 后端单独一个分支（不与 SNI 并存）—— **三处同形**判断 ⇒ 行级构造分不开 ⇒ 意图天然是「至少 3 次」；⚠ 这条门**不在审计器覆盖内**'

# 判据/探针可见面
arch_need_any_min 'dockFieldIndex' 2 'SelfCheck 覆盖 dock 字段偏移'
arch_need_any_min 'chooseBackend' 5 'SelfCheck 覆盖后端选择'
arch_need_any_min 'dockSelectionName' 1 'SelfCheck 覆盖选区名'
arch_need "$SRC/src/main.cpp" 'deepinTraySelection=' '无头探针报出 deepin 托盘选区状态'
arch_need "$SRC/scripts/probe-deepin-tray.sh" 'Properties\.Get "\$TRAY_SERVICE" TrayIcons' '端到端探针**真的去读 daemon 的 TrayIcons**（判据放在真机探针）—— 盯那行 D-Bus 调用'
arch_need "$SRC/scripts/probe-deepin-tray.sh" 'xprop -id "\$WID" WM_NAME' '端到端探针核 X 侧窗口名（不靠 daemon 侧那张表）—— 盯那行 xprop'
arch_need "$SRC/scripts/probe-deepin-tray.sh" '"\$TRAY_SERVICE\.GetName" "\$WID"' '端到端探针核 daemon 侧 GetName —— 盯那行 D-Bus 调用'

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
arch_need "$SRC/scripts/probe-deepin-tray.sh" '\[ "\$BACKEND" = "deepin-window" \]' 'deepin 探针核对自动选路的结果 —— 盯那行**判定**'
arch_need_any_min 'parseBackendOverride' 6 'SelfCheck 覆盖强制开关的解析'
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
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 Y 段门项全绿（deepin 托盘窗口协议）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

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
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'm_langBox = new QComboBox\(content\);' '文档窗有语言选择器 —— 盯**造下拉框**那一行'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocPages::languageLabel' '语言项显示名来自判定层'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocPages::resolveLanguage' '语言解析走判定层（UI 不自己判值）'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocPages::content\(k, m_language\)' '正文按当前语言取'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocPages::kindTitle\(all\.at\(i\), m_language\)' '类目分段名按当前语言取'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'DocPages::windowTitle' '窗口标题按当前语言取'
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
arch_need "$SRC/src/app/Settings.cpp" 'value\(QStringLiteral\("app\.language"\)\)' '设置层有 app.language 键（与 mac UserDefaults 逐字对齐）—— 盯**读**那一处'
arch_need "$SRC/src/app/Settings.cpp" 'remove\(QStringLiteral\("app\.language"\)\)' '设置层**能删掉** app.language（删不掉 ⇒ 切语言后旧值还在）—— 盯**删**那一处'
arch_need "$SRC/src/app/Settings.cpp" 'setValue\(QStringLiteral\("app\.language"\)' '设置层**能写下** app.language（写不进去 ⇒ 切了语言下次启动又回去）—— 盯**写**那一处'
arch_need "$SRC/src/app/Settings.h" 'appLanguageKey' '设置层暴露语言读写接口'
# 分段按钮要能改档位文字（否则换语言时分段名换不掉）
arch_need "$SRC/src/ui/common/SegmentedButton.h" 'setButtonText' '分段按钮支持改档位文字（语言切换用）'
# 判据覆盖
arch_need_any_min 'DocPages::resolveLanguage' 3 'SelfCheck 覆盖语言解析三态'
arch_need_any_min 'DocPages::languageFromKey' 4 'SelfCheck 覆盖「认不出 ⇒ nullopt」'
arch_need_any_min 'DocPages::languageKey' 5 'SelfCheck 覆盖语言 key 稳定性'
arch_need_any_min 'DocPages::kindTitle' 4 'SelfCheck 覆盖类目显示名按语言取'
# ── 批 AA 补 · 文档语言**行为**探针（接线门是源码扫描，证不了「界面真换了」）──
arch_need "$SRC/src/ui/dialogs/DocsDialog.h" 'QStringList probeValues\(\) const' '文档窗有只读呈现出口（探针要看实际呈现）'
arch_need "$SRC/src/ui/dialogs/DocsDialog.cpp" 'QStringList DocsDialog::probeValues\(\) const' '呈现出口有实现'
arch_need "$SRC/src/ui/dialogs/DocsDialogProbe.h" 'docsLangProbeReport' '探针文件在（机器格式归它，文档窗里不留字面量）'
arch_need "$SRC/src/ui/dialogs/DocsDialogProbe.cpp" 'box->setCurrentIndex\(i\)' '探针走**真实信号路径**（currentIndexChanged）'
arch_need "$SRC/src/ui/common/SegmentedButton.h" 'QString buttonText\(int id\) const' '分段按钮能读回档位名（探针要看分段名换了没有）'
arch_need "$SRC/src/main.cpp" 'return headlessDocsLangProbe\(argc, argv\);' 'main 有文档语言探针 —— 盯**调用**那一行（盯函数名的话，定义还在、调用被摘了，门照样绿）'
arch_need "$SRC/src/main.cpp" 'rawArgs.contains\(QStringLiteral\("--docs-lang-probe"\)\)' '无头分支认得 --docs-lang-probe（不然会落进 GUI 常驻，CI 挂死）'
arch_need "$SRC/src/main.cpp" 'QStandardPaths::setTestModeEnabled\(true\)' '探针隔离设置（切语言会写 app.language ⇒ 不许碰用户真实设置）'
arch_need_count "$SRC/scripts/ci-docs-lang-probe.sh" '^PROBE_OUT="\$\(QT_QPA_PLATFORM=offscreen "\$BIN" --docs-lang-probe\)" \|\| PROBE_RC=\$\?$' 1 '文档语言断言脚本**真的去跑那个探针** —— 盯那行调用（盯「docs-lang-probe」这个词的话，错误消息里也有 ⇒ 改一处骗得过门）｜⚠⚠⚨ **批 BS：整行锚定**（裸盯串 ⇒ 挪进行尾注释就骗得过门）'
arch_need_count "$SRC/scripts/ci-docs-lang-probe.sh" '^if printf .%s. "\$EN_BODY" \| grep -Pq .\[\\x\{4E00\}-\\x\{9FFF\}\].; then$' 1 '断言脚本真查汉字（英文档回落成中文要能抓住）｜⚠⚠⚨ **批 BS：整行锚定**（裸盯串 ⇒ 挪进行尾注释就骗得过门）'
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

# ── 批 AW · 分隔线是**真线**（1 逻辑像素宽），不是用文字冒充 ──
# ⚠ 起因：详情页那两处分隔线是 `new QLabel(QStringLiteral("|"))` —— 用**文字**冒充线。
#   实测（批 AW 探针）：QLabel("|") 的 sizeHint = **4 × 18 逻辑像素**
#   ⇒ 宽 4px（QLabel 带文本边距）而不是 1px、高 18px（字体高）而不是 14px、
#     它是**字形**（dpr=2 时实测占 8×36 物理像素）、颜色还是 QSS 写死的**构建时快照**
#     ⇒ 切主题后不更新。
# ⚠⚠ 实测还否掉了一个想当然的修法：`QFrame::VLine` + `QFrame::Plain`
#   画出来的是 **`QPalette::Text` 色**（实测 #ff000000）**不是** Mid
#   ⇒ 深色主题下是一条**看不见的黑线** ⇒ 只能自绘（颜色取 DS::surfaceBorder() = Mid 口径）。
# ⚠ 对位：mac 侧 `DetailViews.swift` 用 SwiftUI 原生 `Divider().frame(height: 14)`
#   ⇒ 1pt 宽、限高 14 的真线 ⇒ deepin 侧逐条对位。
arch_need "$SRC/src/ui/DesignTokens.h" 'constexpr int divider = 14;' '分隔线高度档（对位 mac `Divider().frame(height: 14)`）—— 单一真相源，不许散写数字'
arch_need "$SRC/src/ui/common/VDivider.h" 'setFixedWidth\(1\);' '分隔线宽 1 **逻辑**像素（文字版 QLabel("|") 实测是 4）'
arch_need "$SRC/src/ui/common/VDivider.h" 'setFixedHeight\(DS::Height::divider\);' '分隔线高度走 DS token（不写死数字）'
arch_need "$SRC/src/ui/common/VDivider.h" 'p\.setBrush\(DS::surfaceBorder\(\)\);' '分隔线颜色走 DS token（写死颜色 ⇒ 切主题不跟随）'
arch_need "$SRC/src/ui/common/VDivider.h" 'QEvent::ThemeChange' '主题变化时重绘（颜色是运行期取的 ⇒ 不重绘就停在旧色）'
arch_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'VDivider \*vDivider\(QWidget \*parent\)' '分隔线**唯一构造点**（盯定义那一行；两处各写一遍 ⇒ 宽/高/色三处口径会分叉）'
arch_need_count "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'vDivider\(' 3 '详情页两处分隔线都走唯一构造点（定义 + 2 处调用 ⇒ 恰好 3 次；改一处即红）'
arch_forbid_tree 'QStringLiteral\("\|"\)' '不许用**文字**当分隔线（QLabel("|") 实测宽 4 高 18 ⇒ 那不是线）'
arch_need "$SRC/src/main.cpp" 'return headlessDividerProbe\(argc, argv\);' 'main 有分隔线探针 —— 盯**调用**那一行（盯函数名的话，定义还在、调用被摘了，门照样绿）'
arch_need "$SRC/src/main.cpp" 'rawArgs.contains\(QStringLiteral\("--divider-probe"\)\)' '无头分支认得 --divider-probe（不然会落进 GUI 常驻，CI 挂死）'
arch_need_count "$SRC/scripts/ci-divider-probe.sh" '^PROBE_OUT="\$\(QT_QPA_PLATFORM=offscreen "\$BIN" --divider-probe\)" \|\| PROBE_RC=\$\?$' 1 '分隔线断言脚本**真的去跑那个探针** —— 盯那行调用（盯「--divider-probe」这个词的话，错误消息里也有 ⇒ 改一处骗得过门）｜⚠⚠⚨ **批 BS：整行锚定**（裸盯串 ⇒ 挪进行尾注释就骗得过门）'
arch_need_count "$SRC/scripts/ci-divider-probe.sh" '^IW="\$\(field inkWidth\)"$' 1 '断言脚本真量墨迹宽（不量就证明不了「1 逻辑像素」这条）—— 盯**取值那一行**（裸盯 `inkWidth` 的话，缺字段的**错误消息**里也有 ⇒ 改一处骗得过门）｜⚠⚠⚨ **批 BS：整行锚定**'
arch_need "$SRC/scripts/ci.sh" 'ci-divider-probe\.sh' 'CI 真跑了这一门（脚本在但不跑 = 没有门）'

# ── 批 AX · M3c「图标名 / 动效」收口：把**实测结论**钉成门（不许退化）──
# ⚠ 起因：M3c 剩「图标名 / 动效」两项 ⇒ 本批先**只读实测**（全树扫），再决定做不做。
# ⚠⚠ **实测结论**（探针扫全 `src/`）：
#   ① **图标名零绕过** —— 全树 `QIcon::fromTheme("…")` **0 处**、`QIcon("…")` **0 处**
#      ⇒ 图标名真的只走 `logic/IconNames` 这一个出处（批 U 做的事没退化）。
#   ② 清单 **27 个**逻辑图标：**零使用 0 个**、清单外使用 **0 个**。
#   ③ **动效全项目只有一处**：`AgentDialog.cpp` 的新消息自动滚动
#      （`new QPropertyAnimation(` 命中 1 处、`QVariantAnimation`/`QAnimationGroup` 全树 0 处）
#      ⇒ 时长走 `DS::MotionStandardMs`、缓动 `QEasingCurve::InOutQuad`。
# ⇒ 下面这些门把上面三条**钉住**（承诺没有门 = 承诺不存在）。
arch_forbid_tree 'QIcon::fromTheme\(\s*(QStringLiteral\()?"' '图标名只许在 `logic/IconNames` 清单里（不许绕过唯一出处直接写主题名 ⇒ 换主题要改 N 处）—— 正则**两种形态都盖**：`fromTheme("x")` 与 `fromTheme(QStringLiteral("x"))`'
arch_forbid_tree 'QIcon\(\s*(QStringLiteral\()?"' '图标名只许在 `logic/IconNames` 清单里（`QIcon("…")` 形态同样绕过；⚠ 正则**两种形态都盖**）'
arch_forbid_tree 'new QPropertyAnimation\(' '全项目只有一处动画（AgentDialog 新消息自动滚动）—— 要加动效先问「为什么不能并进去」' 'src/ui/dialogs/AgentDialog.cpp'
arch_forbid_tree 'setDuration\(\s*[0-9]' '动画时长必须走 DS token（散写数字 = 多个真相源）—— ⚠ **不许用 `\d`**（GNU grep -E 不认 ⇒ 门永远匹配不到 ⇒ 形同虚设；批 AX 实测）'
arch_forbid_tree 'QVariantAnimation|QAnimationGroup' '只用一种动画机制（不许再引入第二种而不统一）'
arch_need "$SRC/src/ui/dialogs/AgentDialog.cpp" 'anim->setDuration\(DS::MotionStandardMs\);' '那唯一一处动画的时长走 DS token'
arch_need "$SRC/src/ui/dialogs/AgentDialog.cpp" 'anim->setEasingCurve\(QEasingCurve::InOutQuad\);' '那唯一一处动画的缓动统一（不各写各的）'
arch_need "$SRC/src/ui/DesignTokens.h" 'constexpr int MotionStandardMs = 200;' '动效时长档 = **200ms**（全项目唯一出处的**唯一取值** —— 散写 200 就是第二个真相源；改档位只改这一处）'

# ⚠⚠ **批 AX 段自己的收尾块**（批 AZ 加段时曾把它顶掉 ⇒ 本批修回）：
#   每段都该有自己的「红了就 exit 1 + 报本段项数」收尾 ⇒ 段被摘掉时能看出是哪一段。
#   ⚠ 这里**不能带末尾的 `exit 0`**（原批 AX 段是最后一段才带）——
#   后面还有批 AZ 段 ⇒ 带了就等于把后面的段跳过。
#   口径与批 X / 批 Y 段一致。
if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 AX 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 AX 段门项全绿（M3c 图标名/动效已达成）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 AZ · CI 的两个**真实检查盲区** + 崩点可诊断性 ─────────────────────
# ⚠⚠⚠ **这一段盯的是 ci.sh 本身** —— 前面的门盯的是「源码里的接线在不在」，
#   而这一段盯的是「**门自己**还活着吗」。
# ⚠ **起因（批 AY 的现象）**：2026-10-20 两次 ci.sh 输出里出现 glibc 段错误回栈，
#   **而 ci.sh 的退出码仍是 0** ⇒ CI 误判通过。
# ⚠⚠⚠ **本批把那个机制定位出来了（实测）**，并分成两个盲区：
#
#   【盲区 1】selfcheck 步的**退出码被 `|| true` 吞掉**
#     原来是 `SELFCHECK_OUT="$("$BIN" --selfcheck || true)"`。
#     ⚠⚠ **要分清两种「吞退出码」**（批 AY 记的「`| tail` 吞退出码」在这里**不成立**）：
#       `ci.sh` 顶部有 `set -euo pipefail` ⇒ 实测（**dash 与 bash 都试过**）
#       `false | tail -2` 会让**整个脚本以 1 退出** ⇒ **管道没有吞退出码**。
#       而 `$( cmd || true )` 里的 `|| true` 是**在命令替换内部** ⇒ 它把 cmd 的
#       退出码变成 0 ⇒ 命令替换整体成功 ⇒ 外层什么也看不出来。
#     ⇒ **崩在汇总行之后**时（stdout 已打出 "N passed, M failed"，随后才段错误）
#       解析照样成功 ⇒ **门放行**。
#     ⇒ **实测复现**：假二进制打印完汇总行再 `kill -SEGV` ⇒ **旧逻辑判绿**。
#     ⚠ 这**正好解释**批 AY 的现象（崩掉的子进程退出码没人看 ⇒ CI 误判通过）。
#
#   【盲区 2】agent-selftest 步**零断言**
#     原来是 `"$BIN" --agent-selftest | tail -2` ⇒ **只打两行输出，一句断言都没有**：
#     agent 链路**整条坏掉**（工具循环断了、模型不回应、进程早退）时，
#     只要进程**退出码是 0**，这一门照样绿 ⇒ **CI 判「agent 链路是好的」而它其实坏了**。
#     ⚠⚠ 实测纠正：这里的洞**不是**「退出码被管道吞掉」（见上），
#       而是「**退出码之外没有别的断言**」——
#       退出码只能区分「0=FINAL / 1=ERROR」（main.cpp:68-72），
#       **区分不了「链路坏了但恰好返回 0」**（main.cpp:191-197：
#        没有 assistant 消息时 finalText 是空串，仍会打印 `[selftest] FINAL: ` 并 return 0）。
#     ⇒ 现在**三件事都要查**：① 退出码 == 0 ② stdout 含 `[selftest] FINAL:`
#       ③ stdout 含 `[selftest-done]`。
#
# ⚠ **下面每条门都盯「干活的那一行」**（批 AP/AQ/AR/AS/AX 连续五次同形状的纪律）：
#   ⇒ 正则一律**只匹配唯一一处**，错误消息里重复出现的词**不算**（靠 `grep -q` 前缀锚定）。
arch_forbid_ml "$SRC/scripts/ci.sh" '--selfcheck[^;|]*\|\| true' 'selfcheck 的退出码**不许被 `|| true` 吞掉**（⚠ `|| true` 在命令替换内部 ⇒ 崩在汇总行**之后**时解析照样成功 ⇒ 门放行；批 AZ 实测复现：旧逻辑判绿）'
arch_forbid_ml "$SRC/scripts/ci.sh" '--agent-selftest[^;|]*\| *tail' 'agent-selftest 的输出**不许再被管道截断**（批 AY 的教训：段错误回栈被 `| tail -2` 截掉 ⇒ 白丢线索；落盘才能排障）'
arch_need_count "$SRC/scripts/ci.sh" '^\( cd "\$CRASH_DIR" && "\$BIN" --selfcheck 2>"\$BUILD/selfcheck\.err" \) >"\$BUILD/selfcheck\.out" \|\| SELFCHECK_RC=\$\?$' 1 'selfcheck 的退出码**有且只有一个**收集点（`|| SELFCHECK_RC=$?`；这是上一条 forbid 的**对位**：只禁 `|| true` 不够 ⇒ 必须有一条「真的收了」的正面证据）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^\( cd "\$CRASH_DIR" && "\$BIN" --agent-selftest \) >"\$BUILD/agent-selftest\.out" 2>"\$BUILD/agent-selftest\.err" \|\| AGENT_RC=\$\?$' 1 'agent-selftest 的退出码**有且只有一个**收集点｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^if \[ "\$SELFCHECK_RC" -ge 128 \]; then$' 1 '**信号退出必须显式判红**（128+n = 被信号 n 杀死；selfcheck 与 agent-selftest 各一处 —— ⚠ 恰好的 2 次：将来加第三个子进程检查时门会红 ⇒ 逼人回来补这条门，而不是默默多一个不判信号的调用点）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^if \[ "\$AGENT_RC" -ge 128 \]; then$' 1 '**信号退出必须显式判红**（128+n = 被信号 n 杀死；selfcheck 与 agent-selftest 各一处 —— ⚠ 恰好的 2 次：将来加第三个子进程检查时门会红 ⇒ 逼人回来补这条门，而不是默默多一个不判信号的调用点）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^    SC_SIG_NAME="\$\(kill -l "\$SC_SIG" 2>/dev/null \|\| echo "信号\$SC_SIG"\)"$' 1 '崩了要说清**是什么信号**（`kill -l` 查信号名；两处各一次）—— 只报「退出码 139」没人知道那是 SEGV 还是别的｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^    AG_SIG_NAME="\$\(kill -l "\$AG_SIG" 2>/dev/null \|\| echo "信号\$AG_SIG"\)"$' 1 '崩了要说清**是什么信号**（`kill -l` 查信号名；两处各一次）—— 只报「退出码 139」没人知道那是 SEGV 还是别的｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^if ! grep -q .\^\\\[selftest\\\] FINAL:. "\$BUILD/agent-selftest\.out"; then$' 1 'agent-selftest 必须断言 **`[selftest] FINAL:` 标记**（盯**那条 grep**：错误消息里也提到 FINAL ⇒ 裸盯词会被顶替）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^if ! grep -q .\^\\\[selftest-done\\\]\$. "\$BUILD/agent-selftest\.out"; then$' 1 'agent-selftest 必须断言**收尾标记 `[selftest-done]`**（盯**那条 grep**：错误消息里也提到该标记 ⇒ 裸盯词会被顶替）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^mkdir -p "\$CRASH_DIR"$' 1 'core 目录必须**先建出来**（core_pattern 是相对名 ⇒ core 落在崩溃进程的 cwd ⇒ 没有专用目录就没有 core 可查）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^ulimit -c 262144 2>/dev/null \|\| true$' 1 'core dump 必须**开着**（不设 `ulimit -c` ⇒ 崩了**压根没有 core** ⇒ 「留 core 供下次查」这句话是空的）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^\( cd "\$CRASH_DIR" && "\$BIN" --selfcheck 2>"\$BUILD/selfcheck\.err" \) >"\$BUILD/selfcheck\.out" \|\| SELFCHECK_RC=\$\?$' 1 'selfcheck 必须在**专用目录**里跑（core 落 cwd ⇒ 不 cd 进 CRASH_DIR ⇒ core 落在仓库目录 ⇒ 弄脏工作区且没人知道去哪儿找）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^BUILD="\$\(cd "\$BUILD" 2>/dev/null && pwd \|\| echo "\$BUILD"\)"$' 1 'BUILD 必须**绝对化**（一旦 cd 进 core 目录，相对路径的 $BIN 就找不到了 ⇒ 自测步直接起不来）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 AZ 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 AZ 段门项全绿（CI 自测步不许吞退出码 / agent 自测三断言 / 崩点可诊断）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BA · CI 的**每一步**都必须有门（批 BA 时 12 步，批 BD 起 14 步，批 BF 起 15 步）──
# ⚠⚠⚠ **起因（实测，不是推演）**：批 AZ 给 ci.sh 的**内部**加了门，
#   但**「ci.sh 一共有哪 12 步」这件事本身没有任何门** ⇒
#   ⇒ **删掉一整步 ⇒ 所有门照样全绿** ⇒ **CI 静默少做一件事**。
#
# ⚠⚠⚠ **实测取证（批 BA）**：写脚本**逐个删掉** ci.sh 的 12 步，每删一步跑一遍
#   接线门 + 审计器 ⇒ 结果是 **12 步里有 6 步删了门照样全绿**：
#     第 3 步 desktop/metainfo 校验、第 7 步 verify 接线扫描、
#     第 8 步 图谱 Canvas 契约清单、第 9 步 **接线门**、第 10 步 引擎契约门、
#     第 12 步 deb 布局验收。
#   ⇒ ⚠ **最刺眼的是第 9 步**：把「接线门」这一步从 ci.sh 里删掉，**门还是绿的**
#     ⇒ 门把自己的存在也丢了，没人管。
#   ⇒ 另外 6 步之所以被抓住，是**别的段落的门恰好**盯到了它们的串（**偶然**，不是「每步都有门」）。
# ⇒ **这正是「承诺没有门 = 承诺不存在」**：CI 清单上写着 12 步，
#   少做一步却没有任何信号。
#
# ⚠ **本段的门盯什么**：每一步的**正文里一个「全文件唯一」的串**，
#   用 `arch_need_count` 钉成**恰好 1 次** ⇒
#   ① 删掉整步 ⇒ 命中数变 0 ⇒ 红；
#   ② 把那个串挪到别的步 ⇒ 命中数仍是 1 ⇒ **不红**（⚠ 已知边界，与全仓其它门同款：
#      本段保证「这一步还在」，不保证「这一步的代码没被挪走」）——
#      要更强的保证得让门**认识步骤边界**（新门型 ⇒ 审计器也要跟着扩），
#      本批不做，**如实记着**。
# ⚠ **串的选择口径**（批 AP/AQ/AR/AS/AX 连续六次同形状的纪律）：
#   必须**只出现在那一步里**（全文件命中数 == 本步内命中数），
#   否则会被**别处顶替**（改一处骗得过门）。
arch_need_count "$SRC/scripts/ci.sh" '^\( cd "\$CRASH_DIR" && "\$BIN" --selfcheck 2>"\$BUILD/selfcheck\.err" \) >"\$BUILD/selfcheck\.out" \|\| SELFCHECK_RC=\$\?$' 1 '第 1 步 selfcheck 的动作还在（删掉这一步 ⇒ CI 少跑一次自测 ⇒ 必须红）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '--color-sample' 1 '第 2 步 截图矩阵（8 张快照 + 状态色样张）的动作还在'
arch_need_count "$SRC/scripts/ci.sh" '^    desktop-file-validate "\$SRC/data/cn\.deepdolphin\.app\.desktop" \|\| _dfv_rc=\$\?$' 1 '第 3 步 desktop/metainfo 校验的动作还在｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）｜⚠⚠⚨ **批 CU：形态已改**（旧形态 `cmd && echo "✓ …"` ⇒ 校验命令的失败被 `&&` 吞掉 ⇒ `set -e` 不触发 ⇒ **CI 假绿**（实测 rc=0 + 「✓ CI 门通过」）⇒ 改成 `|| _dfv_rc=$?` ⇒ 接住退出码 ⇒ 失败即判红）'
arch_need_count "$SRC/scripts/ci.sh" '^if ! sh "\$SRC/scripts/ci-platform-probe\.sh" "\$BIN"; then$' 1 '第 4 步 无头探针（平台探针）的动作还在｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^if ! sh "\$SRC/scripts/ci-d2\.sh" "\$SRC"; then$' 1 '第 5 步 D2 散值门（DS::* 单点真相源）的动作还在｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^\( cd "\$CRASH_DIR" && "\$BIN" --agent-selftest \) >"\$BUILD/agent-selftest\.out" 2>"\$BUILD/agent-selftest\.err" \|\| AGENT_RC=\$\?$' 1 '第 6 步 agent 自测的动作还在｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^wire_need "\$SRC/src/app/AppModel\.cpp" .QStringLiteral\\\("verify"\\\). .AppModel 调引擎 verify 命令.$' 1 '第 7 步 verify 接线扫描的动作还在（盯那条 wire_need 的正则 —— 它是本步唯一的「verify 入口」证据）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^CANVAS_METHODS="setTransform fillRect strokeRect rect beginPath moveTo lineTo arcTo closePath arc bezierCurveTo fill stroke fillText createLinearGradient addColorStop setLineDash setLineDashOffset setShadowBlur setShadowColor setGlobalAlpha setLineWidth setStrokeStyle setFillStyle setFont setTextAlign"$' 1 '第 8 步 图谱 Canvas 契约清单的动作还在（26 个方法的清单在本步唯一定义）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^if sh "\$SRC/scripts/ci-wiring\.sh" "\$SRC"; then$' 1 '第 9 步 **接线门**的动作还在（⚠⚠ 门自己被删了，门也得红 —— 批 BA 实测：本步删掉时**其余门全绿**）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^    DEEPGIT_CLIENT_BIN="\$BIN" sh "\$SRC/scripts/contract-check\.sh" > "\$_cc_log" 2>&1 \|\| _cc_rc=\$\?$' 1 '第 10 步 引擎契约门（真引擎沙箱）的动作还在｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^    sh \"\$SRC/scripts/build-deb\.sh\" \"\$BUILD/deb\" > \"\$BUILD/build-deb\.log\" 2>&1 \|\| _deb_rc=\$\?$' 1 '第 11 步 deb 打包的动作还在（D7 达标的必经：能出包装进 deepin）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）｜⚠⚠⚨ **批 CL：形态已改**（接住退出码 + 分诊 rc=3）：`if sh … ; then` ⇒ `_deb_rc=0` + `sh … || _deb_rc=$?` + `if [ "$_deb_rc" -eq 0 ]; then`⇒ ⚠ 旧形态**接不住**退出码 ⇒ build-deb.sh 报「未验证」(3) 时**落进 else**⇒ 被当成「构建失败」（1）⇒ **码值语义被顶替**（批 CC 纪律）⇒ 现在 3 ⇒ 未验证 ⇒ 计入 `skip` ⇒ 末尾判红｜⚠ **原地替换**（批 BM：不增行）'
arch_forbid "$SRC/scripts/ci.sh" '^    if sh "\$SRC/scripts/build-deb\.sh" "\$BUILD/deb" > "\$BUILD/build-deb\.log" 2>&1; then$' 'CI 第 11 步 deb 打包的**旧形态**（`if sh … ; then`）**绝不许回来**（⚠⚠⚨ 批 CO：⚠ **实测的洞**：这条门在批 CL 改形态时**没被真正替换掉** ⇒ 被**追加**到了新门项行的尾巴上（中间连空格都没有）⇒ shell 把后一条并进了前一条的 label ⇒ **它从来没被执行过** ⇒ 而它盯的形态**早已不存在** ⇒ 它真跑起来**就该是红的** ⇒ ⚠⚠⚨ **CI 一直是假绿** ⇒ ⇒ 现在改成 forbid：**旧形态绝迹**才算数（⚠ forbid 门判「不该有的东西没了」⇒ 命中 >0 ⇒ 红））'
arch_need_count "$SRC/scripts/ci.sh" '^    sh "\$SRC\/scripts\/check-deb-layout.sh" "\$DEB_OUT" > "\$_dl_log" 2>&1 \|\| _dl_rc=\$\?$' 1 '第 12 步 deb 布局验收的动作还在（D7 的**准**验收：装完能不能用）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）｜⚠⚠⚨ **批 CC：形态改成「接住退出码 + 分诊」**'
arch_need_count "$SRC/scripts/ci.sh" '^sh "\$SRC/scripts/probe-agent-tool-surface\.sh" "\$BIN" \|\| ATS_RC=\$\?$' 1 '第 13 步 agent 工具面收敛的动作还在（批 BD 实测：这个探针以前**根本不在 CI 里** ⇒ 它的 9 条断言没人执行）—— ⚠ 盯的是**调用点**那串，不是文件名：文件名在 ci.sh 的注释里也出现过（讲这个洞的来由）⇒ 盯短名会命中 2 次而恒红｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^if ! sh "\$SRC/scripts/ci-orphan-probe\.sh" "\$SRC"; then$' 1 '第 14 步 无游离断言脚本的动作还在（批 BD：这是「CI 自己在漏什么」的那一道）—— ⚠ 同上，盯**调用点**｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^if ! python3 "\$SRC/scripts/ci-tautology-check\.py" "\$SRC"; then$' 1 '第 15 步 判据不许被掏空成恒真的动作还在（批 BF：条数基线门抓不到「条件被掏空」）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '› [0-9]+/16 ' 16 'ci.sh 的步骤打点**恰好 16 个**（多一步/少一步都红；且分母统一是 16 ⇒ 散写分母也红）｜⚠⚠⚨ **批 DG**：assets 侧图标判据接进 CI ⇒ 15 → 16 步'
arch_need_ml "$SRC/scripts/ci.sh" '› 1/16 .*› 2/16 .*› 3/16 .*› 4/16 .*› 5/16 .*› 6/16 .*› 7/16 .*› 8/16 .*› 9/16 .*› 10/16 .*› 11/16 .*› 12/16 .*› 13/16 .*› 14/16 .*› 15/16 .*› 16/16 ' 'ci.sh 的 16 个步骤打点**编号连续**（压行后匹配 ⇒ 跨行也算）⇒ 跳号/重号/乱序都红｜⚠⚠⚨ **批 DG**：15 → 16 步'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BA 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BA 段门项全绿（ci.sh 的 16 步每一步都有门）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BB · 判据条数基线：**必须相等**，不是「不少于」────────────────────
# ⚠⚠⚠ **起因（实测，不是推演）**：批 AJ 立的门是「判据数**不少于** `SC_MIN`」
#   （`if [ "$SC_PASSED" -lt "$SC_MIN" ]`）⇒ ⚠⚠ **余量 = 基线与实际判据数之差，
#   而那个差没人盯**：
#     批 AJ 时基线 393 = 实际 393（严丝合缝）；
#     此后**加了 2 条判据**（393 → 395）而**基线没跟着加** ⇒ 余量变成 **2**
#     ⇒ ⚠⚠ **可以删 2 条判据，门照样绿** ⇒
#     「判据不许被删 ⇒ 有判据被删了 ⇒ 红」这个承诺**当时是假的**。
#   ⚠⚠⚠ **实测复现**（批 BB 负控，修前）：删掉 1 条判据 ⇒ 第 1 步**真实门 rc=0（绿）**；
#     加 1 条判据 ⇒ 也绿（基线与实际已脱钩）。
#   ⚠⚠⚠ **原注释把方向写反了**：原话「忘了加只是门偏**严**，不会偏**松** ⇒ 安全方向」
#     ⇒ **恰恰相反**：忘了加 ⇒ 基线落后 ⇒ **门偏松** ⇒ **正是不安全的那一侧**。
#     （同样的错在台账 E.1s 与 PLAN §10 也各写了一遍 ⇒ 本批一并订正。）
# ⇒ 修法：判定改成**完全相等** ⇒ **余量恒为 0**：
#   加判据忘了同步 ⇒ 红；删判据 ⇒ 红；基线被调小 ⇒ 红。
# ⇒ **下面这两条门盯的正是「这个判定本身」** —— 判定被改回「小于」，余量就又回来了。
arch_need_count "$SRC/scripts/ci.sh" '^if \[ "\$SC_PASSED" -ne "\$SC_MIN" \]; then$' 1 '判据条数基线的判定必须是**完全相等**（`-ne`）—— 改成 `-lt`（不少于）⇒ 余量又回来 ⇒ 可删的判据数 = 基线与实际的差（批 BB 实测：曾有 2 条余量，删 2 条照样绿）｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^SC_MIN=395$' 1 '判据条数基线**有且只有一处**（`SC_MIN=<数字>`）—— 基线散在两处 ⇒ 改一处就废掉另一处 ⇒ 门跟着松｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'
arch_need_count "$SRC/scripts/ci.sh" '^if \[ "\$SC_FAILED" -ne 0 \] \|\| \[ "\$SC_PASSED" -lt 58 \]; then$' 1 '判据**一条都不能失败**（`failed` 必须恒为 0）—— 这条是「牙还在不在」的前提｜⚠⚠⚨ **整行锚定**（批 BN：整行锚定 ⇒ 判定行被**追加内容**（`or True` / 注释尾巴）时门会红；⚠ **这条已进锚定形态检查的适用范围**）'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BB 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BB 段门项全绿（判据条数基线必须完全相等 ⇒ 余量恒为 0）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BC · CI 里跑的**每个断言脚本**，它的断言清单都要有门 ───────────────
# ⚠⚠⚠ **起因**：批 BB 修完 selfcheck 的判据基线后，顺手查了别的脚本 ⇒ 撞出同一族的洞：
#   **CI 里跑的 5 个断言脚本，有 2 个一条门都没有**：
#     · `contract-check.sh`（**120 条真引擎断言**，运行期 120 passed）⇒ **零条门**
#       ⇒ 删掉任意一条断言 ⇒ **没有任何门会红** ⇒ 契约门被悄悄削弱无人知晓；
#     · `check-deb-layout.sh`（deb 布局验收）⇒ 同样零条门。
#   另外 3 个探针脚本**只有个别断言被盯住**（批 AA/AW 盯了具体那几行）⇒
#   **其余断言被删掉也没人管**。
# ⇒ 本段给这 5 个脚本各加一条「**断言清单不许被删**」的条数基线门。
#
# ⚠ **口径说明（每个脚本的可数形态不同，别混用）**：
#   · `contract-check.sh`  用 `check` **调用点**数（93 处）—— ⚠ **不能用「✗ 数」**：
#     它的 `check()` 函数体内只有**一条**报错语句 ⇒ ✗ 数 ≠ 断言数（实测 133 vs 93）。
#   · `check-deb-layout.sh` 用 `ok`/`no` 调用数（14 处）。
#   · 三个探针脚本        用 **报错行数**（每条断言失败时打一条 `✗`）⇒ 数 = 断言数。
#
# ⚠⚠ **已知边界（如实记着）**：条数基线只挡「**删断言**」，
#   挡不住「**把断言掏空成恒真**」（把断言的判定表达式改成恒真 ⇒ 条数不变 ⇒ 门不红）。
#   ⇒ 那要逐条钉住断言的**表达式**，成本远高于收益 ⇒ 本批不做，记为待办。
arch_need_count "$SRC/scripts/contract-check.sh" '^[[:space:]]*check ' 93 '契约门的断言清单**不许被删**（93 处 check 调用 ⇒ 运行期 120 条真引擎断言；⚠ 契约门有随环境变化的 SKIP 分支 ⇒ 运行期条数会变 ⇒ **只能钉静态调用数**）'
arch_need_count "$SRC/scripts/check-deb-layout.sh" '^[[:space:]]*(no|ok) "' 15 'deb 布局验收的断言清单**不许被删**（15 处 ok/no 调用）｜⚠⚠⚨ **批 BX**：「--version 退出码非 0 ⇒ 判失败」多了一条 ok/no 调用（14 → 15）'
arch_need_count "$SRC/scripts/ci-platform-probe.sh" '^[[:space:]]*echo "[ ]*✗' 22 '平台探针的断言清单**不许被删**（22 条报错 ⇒ 每条报错对应一条断言）｜⚠⚠⚨ **批 BS：口径从「含标记的行」收紧成「真报错行」**（行尾注释里的标记不再算数 ⇒ 删一条真报错再在行尾注释里补一个骗不过门）｜⚠ 行尾是自由文本 ⇒ 整行锚定会改窄语义 ⇒ 走豁免表登记'
arch_need_count "$SRC/scripts/ci-docs-lang-probe.sh" '^[[:space:]]*echo "[ ]*✗' 11 '文档语言探针的断言清单**不许被删**（11 条报错）｜⚠⚠⚨ **批 BS：口径从「含标记的行」收紧成「真报错行」**｜⚠ 行尾是自由文本 ⇒ 整行锚定会改窄语义 ⇒ 走豁免表登记'
arch_need_count "$SRC/scripts/ci-divider-probe.sh" '^[[:space:]]*echo "[ ]*✗' 10 '分隔线探针的断言清单**不许被删**（10 条报错；批 AW 只盯了其中 3 条 ⇒ 其余被删掉本来没人管）｜⚠⚠⚨ **批 BS：口径从「含标记的行」收紧成「真报错行」**｜⚠ 行尾是自由文本 ⇒ 整行锚定会改窄语义 ⇒ 走豁免表登记'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BC 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BC 段门项全绿（CI 里跑的 5 个断言脚本，清单都不许被删）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BD · 断言脚本不许游离在 CI 之外 ──────────────────────────────────
# ⚠⚠⚠ **起因（实测，不是推演）**：批 BC 给「CI 里跑的脚本」加了条数基线门，
#   顺手查「CI 里到底跑了哪些脚本」⇒ 撞出同一族的洞，而且是**最后一块**：
#   `scripts/probe-agent-tool-surface.sh`（9 条断言）**根本不在 CI 里**。
#   ⚠⚠⚠ **实测取证（批 BD）**：把这个脚本**整个从仓库删掉** ⇒
#     接线门 rc=0、审计器 rc=0 ⇒ **两个都全绿** ⇒
#     **「仓库里少了一份断言」这件事，没有任何门会说一个字。**
#   ⚠ 对照实测（用来定位洞的位置，不是拍脑袋）：
#     · 删掉**已经接进 CI** 的脚本（ci-docs-lang-probe.sh / ci-divider-probe.sh）
#       ⇒ 门**红**（rc=1）⇒ 洞不在「已接管的」，在「**没接管的**」；
#     · 删掉 ci.sh 里对某个探针的**调用** ⇒ 门**红** ⇒ 调用点本身是有门的。
# ⇒ **修法**（两处，缺一不可）：
#   ① `probe-agent-tool-surface.sh` **接进 CI**（ci.sh 第 13 步）——
#      它的 9 条断言（引擎标的废弃别名不得留在模型可见面/系统提示词里，
#      但**仍要留在必填校验表**里）从此有人执行。
#   ② 新增 `scripts/ci-orphan-probe.sh`（ci.sh 第 14 步）——
#      从**集合**这一层堵：scripts/ 下每个断言脚本，要么在 CI 里**可达**
#      （ci.sh 直接调用，或被 CI 可达的脚本调用），要么在**带理由的白名单**里。
#      ⇒ 「多了一份没人跑的断言」与「少了一份断言」两头都被堵住。
#
# ⚠ **本段守的是「门自己不许被掏空」**（三层）：
#   ① 探针自己的断言清单不许被删（批 BC 口径：数报错行）。
#   ② 探针**判定「什么算断言脚本」的那行**必须在 —— ⚠⚠ 少了它 ⇒ 探针扫到 0 个
#      断言脚本 ⇒ 报「0 个，全部可达」⇒ **空转恒绿**（与批 BC 记的已知边界同形状）。
#   ③ 探针**排除门项行**的规则必须在 —— 少了它 ⇒ 门项字符串（长得像调用）被当成
#      真调用 ⇒ 可达集合被夸大 ⇒ 探针失准。
# ⚠ **白名单不许收纳「已经在 CI 里」的脚本**（逐条钉，期望次数 0）：
#   否则有人可以把一个**已接管的**脚本塞进白名单 ⇒ 它随时能被踢出 CI 而无人知晓。
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^[[:space:]]*echo "[ ]*✗' 11 '无游离门自己的断言清单**不许被删**（⚠ 口径：**11 条断言的报错行**（⚠⚠⚨ **批 CD +1**：新增「有脚本对工具不可读 ⇒ 判失败」那条；⚠⚠⚨ **批 CV +1**：新增「剥注释抽取失败 ⇒ 判失败」那条；⚠⚠⚨ **批 CV 的「剥注释失败 ⇒ 判定不可信」那条在 trap 里**（不是独立行 ⇒ 这条门数不到它 ⇒ 另有门盯它）；「什么算断言脚本」那条判定行**另有一条门**盯着 ⇒ 两边分开数）｜⚠⚠⚨ **批 BS：口径从「含标记的行」收紧成「真报错行」**｜⚠ 行尾是自由文本 ⇒ 整行锚定会改窄语义 ⇒ 走豁免表登记'
arch_need_count "$SRC/scripts/probe-agent-tool-surface.sh" '^[[:space:]]*echo "[ ]*✗' 11 'agent 工具面探针的断言清单**不许被删**（11 条报错）—— ⚠⚠ **这条门是「文件被整个删掉」的唯一防线**：无游离门扫的是**目录里现存的文件** ⇒ 文件没了它就**扫不到**、也就不会报 ⇒ 必须另有一条「盯文件本身」的条数基线门（删文件 ⇒ 门报「文件不存在」⇒ 红）｜⚠⚠⚨ **批 BS：口径从「含标记的行」收紧成「真报错行」**｜⚠ 行尾是自由文本 ⇒ 整行锚定会改窄语义 ⇒ 走豁免表登记'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^[[:space:]]*grep -q .✗ . "\$_f" 2>/dev/null \|\| continue$' 1 '无游离门**判定「什么算断言脚本」的那行**必须在（⚠⚠ 少了它 ⇒ 扫到 0 个 ⇒ 报「全部可达」⇒ **空转恒绿**）｜⚠⚠⚨ **批 BS：整行锚定**（裸盯串 ⇒ 挪进行尾注释就骗得过门）'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^[[:space:]]*strip_comments "\$_cf" \| grep -vE .\^\[\[:space:\]\]\*arch_\[a-z_\]\+\[\[:space:\]\]. 2>/dev/null \\$' 1 '无游离门**排除门项行**的规则必须在（⚠ ⇒ 少了它 ⇒ 门项字符串被当成真调用 ⇒ 可达集合被夸大 ⇒ 探针失准｜⚠⚠⚨ **批 CV：形态已改**（前面接了 `strip_comments` ⇒ **先剥注释再找调用点**；⚠⚠⚨ 实测：不剥 ⇒ 注释里的一行同形文本就能让**游离断言脚本**冒充「在 CI 里」⇒ 本门 **rc=0** ⇒ **假绿** ⇒ 批 BD 的承诺被一行注释破掉）｜⚠⚠⚨ **批 BS：整行锚定**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^(deepin|macos)/[A-Za-z0-9._/-]+\.sh\|[^|]*$' 10 '白名单**条数**基线（恰好 10 条 = deepin 4 + macos 6）—— 增删白名单条目必须同步改这里 ⇒ 改动是显式的、可 review 的（⚠ 期望 == 实际 ⇒ 余量恒为 0，批 BB 口径）｜⚠⚠⚨ **批 BS：整行锚定**（条目里多一个分隔符就红 ⇒ 格式被破坏会被解析错）｜⚠⚠⚨ **批 DE**：条目格式改成 **<平台>/<脚本名>|<理由>** ⇒ 原因：「不可达」是**相对于某个平台的 CI** 才有意义的 ⇒ 不分平台 ⇒ deepin 的白名单能替 mac 开口子（反之亦然）⇒ 后门'
arch_need_count "$SRC/scripts/ci.sh" '(sh|bash|python3) +"?[^"]*/scripts/ci\.sh' 0 '白名单条目 ci.sh **不许被 CI 调用**（它就是 CI 入口本身）—— 期望 0 次：一旦它出现在调用点里 ⇒ 这条白名单就是开后门'
arch_need_count "$SRC/scripts/ci.sh" '(sh|bash|python3) +"?[^"]*/scripts/smoke\.sh' 0 '白名单条目 smoke.sh **不许被 CI 调用**（它是本地冒烟入口，不是 CI 入口）'
arch_need_count "$SRC/scripts/ci.sh" '(sh|bash|python3) +"?[^"]*/scripts/probe-deepin-tray\.sh' 0 '白名单条目 probe-deepin-tray.sh **不许被 CI 调用**（需真机：图形会话 + deepin 托盘 daemon）'
arch_need_count "$SRC/scripts/ci.sh" '(sh|bash|python3) +"?[^"]*/scripts/probe-sni-icon\.sh' 0 '白名单条目 probe-sni-icon.sh **不许被 CI 调用**（需真机：图形会话 + 会话总线）'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BD 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BD 段门项全绿（断言脚本不许游离在 CI 之外；白名单 4 条，每条带理由且都确实不在 CI 里）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BE · per-step 门要认识**步骤边界**（标记串被挪到别处也要红）──────
# ⚠⚠⚠ **起因（实测，不是推演）**：批 BA 立了 12 条 per-step 门（批 BD 扩到 14 条），
#   盯的是「每一步的标记串在**整个 ci.sh** 里恰好出现 1 次」⇒
#   ⚠⚠⚠ **实测：把第 8 步的标记串 `CANVAS_METHODS=` 整行挪到第 12 步**，
#   **命中数仍是 1** ⇒ 跑接线门 ⇒ **rc=0（全绿）** ⇒
#   ⇒ 那道门只能证明「**这个串还在**」，**证明不了「它还在这一步里**」。
#   ⇒ 批 BA 当时把这个边界**如实记着**（「要更强的保证得让门**认识步骤边界**」）——
#     本批就把它补上。
#
# ⚠ **新门型**：`arch_need_count_in_step <文件> <步号> <正则> <期望次数> <说明>`
#   ⇒ 按打点行（`^echo "› N/M `）把文件切段，**在第 N 步的正文里**数那个串。
# ⚠⚠ **新门型 ⇒ 审计器必须跟着扩**（批 AR/AV 的纪律：「审计器自己有盲区 ⇒
#   那些门**根本没被审**」）⇒ `ci-wiring-audit.py` 已加 `arch_need_count_in_step`
#   的解析与**配准校准**；且切段用的 awk 是**从本函数原文抽取**的（零漂移）。
# ⚠ **与已有的文件级门互补，两个都要**：
#   文件级「恰好 1 次」⇒ 抓「被**复制**到别处」；步内「恰好 1 次」⇒ 抓「被**挪**到别处」。
#   ⚠ 二者合起来才是完整的：「这个串**全文件只有一处**」**且**「**那 一处就在这一步里**」。
arch_need_count_in_step "$SRC/scripts/ci.sh" 1 '--selfcheck' 1 '第 1 步 selfcheck 的动作**还在这一步里**（批 BE：文件级门只保证「串还在」，不保证「串没被挪到别的步」）'
arch_need_count_in_step "$SRC/scripts/ci.sh" 2 '--color-sample' 1 '第 2 步 截图矩阵（8 张快照 + 状态色样张）的动作**还在这一步里**'
arch_need_count_in_step "$SRC/scripts/ci.sh" 3 'cn\.deepdolphin\.app\.desktop' 1 '第 3 步 desktop/metainfo 校验的动作**还在这一步里**'
arch_need_count_in_step "$SRC/scripts/ci.sh" 4 'ci-platform-probe\.sh' 1 '第 4 步 无头探针（平台探针）的动作**还在这一步里**'
arch_need_count_in_step "$SRC/scripts/ci.sh" 5 'ci-d2\.sh' 1 '第 5 步 D2 散值门（DS::* 单点真相源）的动作**还在这一步里**'
arch_need_count_in_step "$SRC/scripts/ci.sh" 6 '--agent-selftest' 1 '第 6 步 agent 自测的动作**还在这一步里**'
arch_need_count_in_step "$SRC/scripts/ci.sh" 7 'QStringLiteral\\\("verify"\\\)' 1 '第 7 步 verify 接线扫描的动作**还在这一步里**（盯那条 wire_need 的正则 —— 它是本步唯一的「verify 入口」证据）'
arch_need_count_in_step "$SRC/scripts/ci.sh" 8 'CANVAS_METHODS=' 1 '第 8 步 图谱 Canvas 契约清单的动作**还在这一步里**（26 个方法的清单在本步唯一定义）—— ⚠ 这条正是批 BE 取证时被挪走的那一条'
arch_need_count_in_step "$SRC/scripts/ci.sh" 9 'ci-wiring\.sh' 1 '第 9 步 **接线门**的动作**还在这一步里**（⚠⚠ 门自己被删了，门也得红）'
arch_need_count_in_step "$SRC/scripts/ci.sh" 10 'contract-check\.sh' 1 '第 10 步 引擎契约门（真引擎沙箱）的动作**还在这一步里**'
arch_need_count_in_step "$SRC/scripts/ci.sh" 11 'build-deb\.sh' 1 '第 11 步 deb 打包的动作**还在这一步里**（D7 达标的必经：能出包装进 deepin）'
arch_need_count_in_step "$SRC/scripts/ci.sh" 12 'check-deb-layout\.sh' 1 '第 12 步 deb 布局验收的动作**还在这一步里**（D7 的**准**验收：装完能不能用）'
arch_need_count_in_step "$SRC/scripts/ci.sh" 13 'sh "\$SRC/scripts/probe-agent-tool-surface\.sh"' 1 '第 13 步 agent 工具面收敛的动作**还在这一步里**'
arch_need_count_in_step "$SRC/scripts/ci.sh" 14 'sh "\$SRC/scripts/ci-orphan-probe\.sh"' 1 '第 14 步 无游离断言脚本的动作**还在这一步里**'
arch_need_count_in_step "$SRC/scripts/ci.sh" 16 'python3 "\$SRC/scripts/ci-tautology-check\.py"' 1 '第 16 步 判据不许被掏空成恒真的动作**还在这一步里**（⚠⚠⚨ **批 DG**：assets 图标判据插在它前面 ⇒ 15 → 16 步）'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BE 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BE 段门项全绿（ci.sh 每一步的标记串**不许被挪到别的步**）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BF · 判据不许被「掏空成恒真」（条数基线门抓不到的那一类）────────
# ⚠⚠⚠ **起因（实测，不是推演）**：批 BB/BC 的门盯的是「**判据条数**」
#   （selfcheck 的 `SC_MIN`、各断言脚本的条数基线）⇒
#   ⚠⚠⚠ **实测：把一条判据的条件改成 `true`** ⇒
#     · selfcheck 仍 **395 passed, 0 failed**（条数**没变**）
#     · 批 BB 的「判据数 == SC_MIN」判定**不红**（它只看条数）
#     · 接线门 **rc=0（全绿）**
#   ⇒ 而那条判据**从此永远不会红** ⇒ 判据被悄悄削弱**无人知晓**。
#   ⇒ 这就是批 BC 记下的那条已知边界（「条数基线挡不住把断言掏空成恒真」）。
#
# ⚠ **修法（新增 scripts/ci-tautology-check.py，ci.sh 第 15 步）**：
#   ① **判定层 C++**（`src/app/SelfCheck*.cpp`）：`check(…)` 的**条件**不许是恒真/纯字面量
#      —— 判据 = 条件里**去掉字面量与关键字后至少剩一个被测标识符**
#      ⇒ 抓 `true` / `false` / `1 == 1` / `"a" == "a"`；
#      另禁「捷径」写法 `|| true` / `&& false`（条件里带恒真项 ⇒ 整条判据被短路）。
#   ② **shell 断言脚本**：`if` 的条件不许是 `true` / `false` / `:`。
#   ③ **python 工具脚本**：`if True:` / `if False:` 这类恒真条件。
#
# ⚠⚠ **本段守的是「**门自己不许被掏空**」**（这是本批的另一半价值）：
#   · 探针**自带自检**（每次运行先拿合成样例验一遍自己的判定逻辑 ⇒ 判定被改坏 ⇒ 当场红）
#     ⇒ **门自己证明自己有牙**，比静态门更硬（静态门只能盯「那行代码在不在」）。
#   · 下面这些门钉住自检与四条判定逻辑**都在** ⇒ 有人把它们掏空，门也会红。
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def tautology_reason\(cond\):$' 1 '恒真检查的**统一判定入口**必须在（实扫与自检必须走同一条路径 ⇒ 否则自检测的不是真判定）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+why = tautology_reason\(cond\)$' 2 '实扫必须走**统一判定入口**（不许另写一份判定 ⇒ 两套口径必然漂）｜⚠⚠⚨ **整行锚定**；⚠⚠⚨ **批 DC**：Swift 的 if 条件**也走这个统一入口**（判定只有一份 ⇒ 口径零漂移）⇒ 调用点 1 → **2**（C++ 侧 + Swift 侧）⇒ 期望次数同步 1 → 2'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if not meaningful_idents\(cond\):$' 1 '判定规则 1 必须在（条件里**至少一个被测标识符**）｜⚠⚠⚨ **整行锚定**：盯串的话「`if not meaningful_idents(cond) or True:`」照样命中 ⇒ **判定被掏空而门假绿**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if SHORTCUT\.search\(cond\):$' 1 '判定规则 2 必须在（禁「\|\| true / && false / and False / or True」捷径 ⇒ 条件里带恒真项 ⇒ 整条判据被短路）｜⚠⚠⚨ **批 BJ 升级为整行锚定**：⚠ **盯串会被注释里的同名串顶替**（实测：把真代码换成 `pass  # skip.add(k)` ⇒ 计数仍是 1 ⇒ 门假绿 ⇒ 批 BH 教训的**反面**：注释能替代码 ⇒ 关键判定必须**整行锚定**（含缩进与行尾）'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if SH_CONST\.match\(cond\):$' 1 'shell 侧的恒真条件判定必须在｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+m = PY_CONST_IF\.match\(ln\)$' 2 'python 侧的恒真条件判定必须在（`if True:` / `if False:`）｜⚠ **两处**：.py 顶层 + **heredoc 内嵌 python** ⇒ 同一份判定走两处 ⇒ 改一处不会漏另一处｜⚠ **整行锚定** ⇒ 注释顶不住（批 BJ 实测）'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+st_bad = self_test\(\)$' 1 '探针的**自检**必须在（门自己证明自己有牙）｜⚠⚠⚨ **整行锚定**：盯串的话「`st_bad = self_test() or True`」照样命中 ⇒ 自检被废而门假绿'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if st_bad:$' 1 '自检失败必须**判红**（自检不过还继续跑 ⇒ 等于没有自检）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.cond., [^,]*, True\),$' 7 '自检样例里 **cond 类的「该判为恒真」** 那 7 条不许被掏空（⚠ 只测一边 ⇒ 判反了也能过）｜⚠⚠⚨ **整行锚定**（批 BQ）：中间用**有界**通配（吃不掉逗号 ⇒ 行结构仍被钉住）⇒ 不用无界通配（点星）⇒ 否则整行锚定名存实亡'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.cond., [^,]*, False\),$' 3 '自检样例里 **cond 类的「不该判为恒真」** 那 3 条不许被掏空（⚠ 这 3 条是判据的**反向**护栏 ⇒ 少了它们 ⇒ 探针只会乱报）｜⚠⚠⚨ **整行锚定**（批 BQ）'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.shortcut., [^,]*, True\),$' 10 '自检样例里 **shortcut 类的「该判为捷径」** 那 10 条不许被掏空（批 BJ 起加的脚本侧捷径样例）｜⚠⚠⚨ **整行锚定**（批 BQ）'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.shortcut., [^,]*, False\),$' 4 '自检样例里 **shortcut 类的「不该判为捷径」** 那 4 条不许被掏空（⚠ 反向护栏）｜⚠⚠⚨ **整行锚定**（批 BQ）'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^JUDGEMENT_PREFIX = .SelfCheck.$' 1 '判定层文件名前缀的**定义**必须在（⚠ **整行锚定**：定义与使用是两处不同形态 ⇒ 一条整行正则罩不住 ⇒ 拆成两条）'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if not \(fn\.startswith\(JUDGEMENT_PREFIX\) and fn\.endswith\(.\.cpp.\)\):$' 1 '判定层文件名前缀的**使用点**必须在（⚠ 散在别处 ⇒ 改一处就废掉另一处）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if bad:$' 1 '探针的**违规 ⇒ 判红**判定必须在（没有它 ⇒ 探针只报告不拦 ⇒ 等于没门）｜⚠⚠⚨ **整行锚定**：盯串的话「`if bad or True:`」照样命中 ⇒ **探针的判红被掏空而门假绿**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BF 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BF 段门项全绿（判据不许被掏空成恒真；探针自带自检 ⇒ 门自己证明自己有牙）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BG · 断言函数**实参里**的判据也不许恒真（契约门那 93 条）────────
# ⚠⚠⚠ **起因（实测，不是推演）**：批 BF 把「判据掏空成恒真」管住了
#   （判定层 C++ 的 `check(…)` 条件 + shell 的 `if` 条件 + python 的 `if`）⇒
#   ⚠⚠⚠ **但契约门的判据根本不在 `if` 条件里** —— 它的形态是
#     check <名称> <python表达式（stdin 为 JSON 文本）> [json]
#     check_text <名称> <ERE> <文本>
#   ⇒ **判据就藏在第二个实参里** ⇒ 批 BF 的三类扫描**一条都够不着**。
#   ⚠⚠⚠ **实测取证（修前）**：把其中一条 check 的 python 表达式掏空成 `True`
#     ⇒ 契约门仍 **120 passed, 0 failed**（rc=0）
#     ⇒ 批 BC 的「93 处 check 调用不许被删」**不红**（调用点数没变）
#     ⇒ 接线门**全绿**（rc=0）⇒ 那条断言**从此永远不会红**。
#
# ⚠ **修法**：恒真探针（ci-tautology-check.py）新增第 ④ 类扫描：
#   · `check` 的 python 表达式**必须引用 `d`**（被测 JSON）
#     ⇒ 抓 `True` / `1 == 1` / `'a' == 'a'`（压根没碰被测数据）
#   · `check_text` 的 ERE**必须含至少一个字面字符**
#     ⇒ 抓 `.*` / `^$` / 空串（匹配一切）
#
# ⚠⚠ **本段守的是「**新规则自己不许被掏空**」**：
#   · 实参**解析器**必须在 —— ⚠ 不能用正则抽实参（实测：contract-check.sh:555
#     的描述里含 `==\"OK\"` ⇒ 正则会把描述与表达式粘成一块 ⇒ 判据抽错 ⇒ 门判错）。
#   · **条数交叉校验**必须在 ⇒ ① 解析器漂了（悄悄少看几条）⇒ 当场红；
#     ② 断言被增删 ⇒ 当场红（完全相等口径，批 BB）。
#
# ⚠⚠⚠ **本段在负控里又撞出两个洞（都是「门形同虚设」的经典形态）**：
#   ⚠ **洞 1：盯函数名的门挡不住「改名」**（B10 实测）——
#     `arch_need_count … 'def assertion_arg_is_tautology' 1` 是**子串**匹配
#     ⇒ 把它改成 `def assertion_arg_is_tautology_disabled` ⇒ **命中仍是 1** ⇒ 门照样绿
#     ⇒ **凡是以函数名做判据的门，都必须带左括号**（`def X\(`）⇒ 改名就红。
#     ⚠ 这不是批 BG 独有：批 BF 段的 `def tautology_reason` 同样中招 ⇒ 一并改紧。
#   ⚠ **洞 2：实参解析器把「空实参」吞了 ⇒ 判据错位**（B4 实测）——
#     判据是「**第二个**实参」⇒ 若 `''` 被吞掉 ⇒ `tokens[2]` 变成**第三个**实参
#     ⇒ 判据抽成别的东西 ⇒ **恒真的空 ERE 被判成合法** ⇒ 漏判。
#     ⇒ 解析器必须区分「没开始一个 token」与「token 内容为空」（`started` 标志）
#     ⇒ 且**自检里要有合成样例**证明它（不是靠注释保证）。
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def assertion_arg_is_tautology\(helper, arg\):$' 1 '断言实参的**恒真判定入口**必须在（⚠ **带左括号** ⇒ 改名躲不过）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+got = assertion_arg_is_tautology\(helper, arg\)$' 1 '自检必须走**薄封装**（自检与实扫同一条判定路径）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def assert_arg_reason\(helper, arg\):$' 1 '断言实参的**真正判定函数**必须在（薄封装只是壳 ⇒ 判定逻辑只许有一份）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+why = assert_arg_reason\(helper, arg\)$' 1 '实扫必须走**同一个**判定函数（自检与实扫分家 ⇒ 自检测的不是真判定）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if helper == .check.:$' 1 '`check` 的规则必须在（python 表达式**必须引用 d**）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if helper == .check_text.:$' 1 '`check_text` 的规则必须在（ERE 必须含字面字符）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if not LITERAL_CHAR\.search\(arg\):$' 1 'ERE 的**字面字符**判定必须在（没有字面字符的 ERE 匹配一切）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def scan_shell\(text\):$' 1 'shell **实参解析器**必须在（⚠ 不用正则：描述里含转义引号会把实参抽错）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+_t, st = scan_shell\(chunk\)$' 1 '实参解析器的**调用点 1/3**必须在｜⚠⚠⚨ **整行锚定**：三处调用形态不同 ⇒ 一条整行正则罩不住 ⇒ 拆成三条'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+tokens, _st = scan_shell\(chunk\)$' 1 '实参解析器的**调用点 2/3**必须在｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+toks, _st = scan_shell\(text\)$' 1 '实参解析器的**调用点 3/3**必须在（找调用点 2 + 自检 1 ⇒ 少一处就断了一条路）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if started:$' 2 '实参解析器**必须保留空实参**（⚠ 空实参被吞 ⇒ 判据错位到下一个实参）｜⚠⚠⚨ **整行锚定**：两处同构 ⇒ 一条正则罩住两处 ⇒ 期望次数仍是 2'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def find_assert_calls\(path, helpers\):$' 1 '断言**调用点扫描**必须在（⚠ 带左括号 ⇒ 改名躲不过）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+found = find_assert_calls\(path, helpers\.keys\(\)\)$' 1 '调用点扫描必须被真正调用｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^ASSERT_CALL_BASELINE = \{$' 1 '断言调用**条数基线表**的定义必须在（⚠ **整行锚定**：定义与使用是两处不同形态 ⇒ 拆成两条）'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+for fn, helpers in sorted\(ASSERT_CALL_BASELINE\.items\(\)\):$' 1 '断言调用**条数基线表**的使用必须在（散在别处 ⇒ 改一处就废掉另一处）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+.contract-check\.sh.: \{.check.: 93, .check_text.: 6\},$' 1 '基线里的 **`check` = 93 / `check_text` = 6 必须一起钉死**（⚠ 原来盯两个片段 ⇒ 各盯一处 ⇒ 改一个就废；⚠ 合并成一条**整行锚定** ⇒ 两个数**都**被钉死 ⇒ 比原来**更强**）｜⚠ **两条并一条** ⇒ 门项数 -1'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if got_n != want_n:$' 1 '**条数交叉校验**必须在（解析器漂了 / 断言被增删 ⇒ 当场红）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.assert_arg., \(.check., [^,]*\), True\),$' 2 '自检样例里 **断言实参（check 助手）的「该判为恒真」** 那 2 条不许被掏空｜⚠⚠⚨ **整行锚定**（批 BQ）：中间用**有界**通配 ⇒ 不用无界通配（点星）'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.assert_arg., \(.check., [^,]*\), False\),$' 1 '自检样例里 **断言实参（check 助手）的「不该判为恒真」** 那 1 条不许被掏空（⚠ 反向护栏；⚠ 这一条的实参里**带右括号** ⇒ 字符类要用 `[^,]` 而不是 `[^)]` ⇒ **实测踩到**：用 `[^)]` 命中 0 而不是 1）｜⚠⚠⚨ **整行锚定**（批 BQ）'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.assert_arg., \(.check_text., [^,]*\), True\),$' 3 '自检样例里 **断言实参（check_text 助手）的「该判为恒真」** 那 3 条不许被掏空｜⚠⚠⚨ **整行锚定**（批 BQ）'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.assert_arg., \(.check_text., [^,]*\), False\),$' 1 '自检样例里 **断言实参（check_text 助手）的「不该判为恒真」** 那 1 条不许被掏空（⚠ 反向护栏）｜⚠⚠⚨ **整行锚定**（批 BQ）'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.shell_scan., \([^)]*, \[[^]]*\]\), True\),$' 1 '自检样例里**实参解析器**那条不许被掏空（⚠ 它是解析器的**空实参**护栏 ⇒ 少了它 ⇒ 解析器把空实参吞掉没人知道）｜⚠⚠⚨ **整行锚定**（批 BQ）：中间用**有界**通配（吃不掉右括号与右方括号 ⇒ 行结构仍被钉住）；⚠ **结构顺序实测踩到**：列表在右括号**之前** ⇒ 正则要写成 `\([^)]*, \[[^]]*\]\)` ⇒ 写反了命中 0'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BG 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BG 段门项全绿（断言函数实参里的判据也不许恒真；实参解析器 + 条数交叉校验都在）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BH · 门项总数不许被悄悄删（批 BA 留下的洞）──────────────────────────
#
# ⚠⚠⚠ **起因（实测，不是推演）**：把 ci-wiring.sh 里**任意一条门项**改成注释
#   ⇒ 接线门 **rc=0**、审计器 **rc=0**、**CI 全流程 rc=0** ⇒ **全绿**
#   ⇒ 「**门项被悄悄删**」这件事，**没有任何机制会发现**
#   ⇒ ⚠ 这是批 BA 落的 12 条 per-step 门**盖不住**的洞：批 BA 钉的是
#     「**ci.sh 的每一步**」，**没有人钉「接线门自己的每一条门」**。
#
# ⚠ **修法（两条，互补）**：
#   ① **门项行总数基线**（`scripts/ci-wiring-gates.baseline`）
#      ⇒ 审计器数「文件里实际的门项行数」⇒ 必须 == 基线 ⇒ 删一条 ⇒ 红。
#      ⇒ ⚠ **基线放在独立文件**（不写死在审计器里）⇒ 写死的话审计器既是
#        **执行者**又是**裁判** ⇒ 改审计器就能同时改标准；独立文件 ⇒
#        删基线文件 ⇒ 门与审计器**双双红**。
#      ⇒ ⚠ **「恰好」口径是双向的**：基线改小（实际 > 基线）也红、改大
#        （实际 < 基线）也红 ⇒ 基线成了**锚点**，不是「可以随手改的门槛」。
#   ② **审计器门型覆盖对拍**（「认领数 == 物理行数」）
#      ⇒ 审计器按**自己登记的门型清单**（`GATE_TYPES`）数一遍，再按
#        **不认识门型**的物理口径数一遍 ⇒ 两个数不等 ⇒ **有一种门型没被登记**
#        ⇒ 那些门项**根本没被审**（批 AR 说的「审计器自己有盲区」）⇒ 红。
#      ⇒ ⚠ 这条防的是**将来新增门型时忘了登记**。
#
# ⚠⚠ **本段守的是「新规则自己不许被掏空」**：
#   ⚠ 实测：ci-wiring.sh 里**此前一条门都没有盯审计器源码** ⇒ 改审计器就能
#   同时改标准 ⇒ 下面这些门把新加的判定逻辑**钉住**。
#   ⚠⚠ **两条防线是互补的**：审计器里的「总数核对」抓「**删门项**」；
#   而**把核对逻辑从审计器里删掉** ⇒ 审计器变绿 ⇒ 但下面这些静态门会红。
arch_need_count "$SRC/scripts/ci-wiring-gates.baseline" '^[0-9]+$' 1 '门项行数**基线文件**必须在，且**只有一行、且是纯数字**（⚠ 基线文件里不许写注释 ⇒ 门侧 strip_comments 与审计侧读原文看到的是同一行）'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^GATE_BASELINE = os\.path\.join\(SRC, .scripts., .ci-wiring-gates\.baseline.\)$' 1 '审计器**基线文件路径**的**定义**必须在（⚠ **整行锚定**：定义与使用是两处不同形态 ⇒ 一条整行正则罩不住 ⇒ 拆成两条）｜⚠ **引号位置写 `.`**（正则参数用单引号包裹 ⇒ 不能含字面单引号 ⇒ 截断 ⇒ 门型盲区）'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+path = GATE_BASELINE$' 1 '审计器**基线文件路径**的**使用点**必须在（⚠ 散在别处 ⇒ 改一处就废掉另一处 ⇒ 范围悄悄变了没人知道）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^GATE_CALL_LINE = re\.compile\(r.\^\\s\*arch_\\w\+\\s.\)$' 1 '审计器的**物理行数口径**的**定义**必须在（⚠ **整行锚定**：整条正则原样写出来 ⇒ 口径被改（压行后计数变）立即红）｜⚠ `\s` 是**偶数**个反斜杠 ⇒ 「字面反斜杠 + s」⇒ 合法 ⇒ 不会被正则体检误报'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+physical = sum\(1 for ln in lines if GATE_CALL_LINE\.match\(ln\)\)$' 1 '审计器的**物理行数口径**的**使用点**必须在｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^GATE_TYPES = \[$' 1 '审计器的**门型登记处**的**定义**必须在（⚠ 漏登记一种门型 ⇒ 认领数 != 物理行数 ⇒ 当场红）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+for name, rx in GATE_TYPES:$' 1 '审计器的**门型登记处**的**使用点**必须在｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^FORBID_FAMILY = \{$' 1 'forbid 家族的**逐门型登记**的**定义**必须在（⚠ forbid 门**有意不审**，但行数仍要计入 ⇒ 否则物理行数对不上 ⇒ 假红）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\] \+ sorted\(FORBID_FAMILY\.items\(\)\)$' 1 'forbid 家族的**逐门型登记**的**使用点**必须在｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+if gtotal != gphysical:$' 1 '**门型覆盖对拍**的判定必须**是那一行原样**（⚠ 只盯「串在不在」⇒ 判定被掏空成 `and False` 就躲过了 ⇒ 没人发现）｜⚠⚠⚨ **整行锚定**（⚠ 批 BH 已有一条同口径的门 ⇒ 本条是**冗余但无害**的第二道）'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+elif gphysical != gbase:$' 1 '**门项总数核对**的判定必须**是那一行原样**（⚠ 同上）｜⚠⚠⚨ **整行锚定**（⚠ 同上：批 BH 已有一条同口径的门 ⇒ 冗余但无害）'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+FAILS.append\(6\)$' 1 '审计器的**第 6 种失败态**必须在（门项总数失配 ⇒ 与「盲区(2)/豁免外(3)/次数失准(4)/正则坏(5)」区分开 ⇒ 不然排障会被带偏）（⚠⚠⚨ **批 CQ**：形态从 `return 6` 改成 `FAILS.append(6)`）｜⚠⚠⚨ **整行锚定**'
# ⚠⚠⚠ **「盯串」不够，还要「盯整行」**（批 BH 负控实测撞出来的洞）：
#   ⚠ 把上面那两条判定**掏空但保留判定串**（`elif gphysical != gbase and False:`）
#   ⇒ 判定串还在 ⇒ 上面那些「恰好 1 次」的门**照样绿**
#   ⇒ 而判定**永远不成立** ⇒ 审计器**永远不报**总数失配 ⇒ 「删门项」又没人管了
#   ⇒ ⚠⚠⚠ **恒真探针也抓不到**（实测：python 侧的「`and False` 捷径」不在它的规则里）
#   ⇒ ⇒ **没有任何机制会发现**。
#   ⇒ 修法：**锚定那一行原样**（含缩进与行尾）⇒ 判定被掏空 ⇒ 命中 0 ⇒ 门红。
#   ⚠ 这个手段**不推广**到所有门项（太脆）⇒ 只用于**关键判定**。
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^    if gtotal != gphysical:$' 1 '**门型覆盖对拍**的判定必须**是那一行原样**（⚠ 只盯「串在不在」⇒ 判定被掏空成 `and False` 就躲过了 ⇒ 恒真探针也抓不到 python 侧的这种捷径 ⇒ 没人发现）'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^    elif gphysical != gbase:$' 1 '**门项总数核对**的判定必须**是那一行原样**（⚠ 同上：判定被掏空 ⇒ 审计器永远不报 ⇒ 删门项又没人管）'
# ⚠⚠⚠ **审计器自己有重名常量 ⇒ 那个常量是死代码**（批 BH 自己踩出来的）：
#   本批加「物理门项行」口径时用的常量名**撞了**文件下方已有的同名常量
#   ⇒ 后者覆盖前者 ⇒ 前者成了**死代码** ⇒ **没有任何门会红**（串还在，只是不生效了）
#   ⇒ 这一族（「同名互相顶替」）从批 AS 起反复出现 ⇒ 交给机器盯。
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def check_dup_module_names\(\):$' 1 '审计器的**模块级重名自检**的**定义**必须在（⚠ **带左括号** ⇒ 改名躲不过）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+dups = check_dup_module_names\(\)$' 1 '审计器的**模块级重名自检**的**使用点**必须在（⚠ 只定义不调用 ⇒ 重名常量检查形同虚设）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+FAILS.append\(7\)$' 1 '审计器的**第 7 种失败态**必须在（重名常量 ⇒ 与其它失败态区分开）（⚠⚠⚨ **批 CQ**：形态从 `return 7` 改成 `FAILS.append(7)`）｜⚠⚠⚨ **整行锚定**'


# ── 批 BI · forbid 门族不许「静默变绿」（实测坐实的洞）────────────────────
# ⚠⚠⚠ **为什么要有这一段**（批 BI 实测，不是推演）：
#   forbid 门判的是「不该有的东西没了」⇒ 「没找到」是常态、是绿
#   ⇒ 工具坏了也长成「没找到」的样子 ⇒ 门**静默变绿**。
#   ⚠ 实测：把剥注释的 perl 改成语法错误 ⇒ 被盯文件里**确实有中文**
#     ⇒ 门仍输出「✓」⇒ 接线门 rc=0 ⇒ CI 全绿 ⇒ 这道门形同虚设。
#   ⇒ 修法：6 个 forbid 门全部走**公共三态判定**（命中/没命中/工具坏了）
#     ⇒ 工具坏了 ⇒ 红 ⇒ 门不会静默变绿。
#
# ⚠⚠⚠ **自护门要盯「判定只有一份」**（批 BF/BG 纪律）：
#   若三态映射被复制成两份 ⇒ 两份迟早漂 ⇒ 一份坏了门还是绿。
#   ⚠ **判据要避开自引**（批 BH 教训）：盯的串若就写在门项行里
#     ⇒ 门项自己给自己贡献一次命中 ⇒ 期望值里混着「自己」
#     ⇒ 改一处就要重算 ⇒ 容易改漏。
#   ⇒ 这里用**行首锚定**（`^函数名() {`）⇒ 门项行以 `arch_` 开头 ⇒ 天然不匹配自己。
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^probe_scan_state_of\(\)' 'PROBE_SCAN_STATE=' 3 '三态映射只有一份（三个赋值全在同一个函数里 ⇒ 复制不出第二份判定）'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^probe_scan_state_of\(\) \{ # [^$]*$' 1 '三态映射只允许有一个函数定义（复制出第二份 ⇒ 两份迟早漂 ⇒ 一份坏了门还是绿）｜⚠⚠⚨ **批 BR 整行锚定**：行尾补 `$` ⇒ 只锚行首不够 ⇒ 判定被掏空但串还在 ⇒ 门假绿'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^probe_scan_find\(\) \{ # [^$]*$' 1 '公共查找只允许有一个函数定义（不许复制出第二份）｜⚠⚠⚨ **批 BR 整行锚定**：行尾补 `$` ⇒ 只锚行首不够 ⇒ 判定被掏空但串还在 ⇒ 门假绿'
arch_need_min "$SRC/scripts/ci-wiring.sh" '^ +probe_scan_find ' 7 '公共查找的调用点（四个走 grep 路线的 forbid 门 + 自检三处）'

# ── 批 BJ · 恒真探针要看得见「脚本侧捷径」与「heredoc 内嵌脚本」────────────
# ⚠⚠⚨ **起因（批 BJ 实测，不是推演）**：批 BF 的捷径规则（`|| true` / `&& false`）
#   **只用在判定层 C++** ⇒ 脚本侧**全都漏判**：
#   · shell 的 `if cmd || true; then` / `if cmd && false; then`
#   · python 的 `if x and False:` / `if x or True:`
#   ⇒ 恒真/恒假的条件 ⇒ **断言永不执行**（恒假方向）⇒ 那条判据从此不会红。
# ⚠⚠⚨ **另一半**：heredoc 里常嵌着**别的语言**的脚本（python / awk）⇒
#   ① 里面的 `if` 被**误当** shell 条件（实测 2 处误判）
#   ② 里面的**真判据**（恒真/捷径）现有探针**根本扫不到**（漏判）
#   ⇒ 必须先把 heredoc 体**摘出来**，再用 python / shell 两套规则各扫一遍
#      （python 收尾是 `:`、shell 收尾是 `then` ⇒ 天然不冲突 ⇒ 不用判语言）。
# ⚠⚠⚨ **自护门要盯「判定只有一份」**（批 BF/BG 纪律）：
#   四种场景（判定层 / shell / python / heredoc 内嵌）**全部**走同一个入口
#   ⇒ 不许各自写一遍 ⇒ 复制两份迟早漂 ⇒ 一份坏了门还是绿。
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def shortcut_reason\(cond\):$' 1 '脚本侧捷径的**统一判定入口**必须在（四种场景都走它 ⇒ 判定逻辑只许有一份）｜⚠ **整行锚定**（含缩进与行尾）⇒ 注释顶不住'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+why = shortcut_reason\(strip_literals\(cond\)\)$' 4 '四个实扫点（判定层 / shell / heredoc 内 python / python）都必须走统一入口 ⇒ 少一处就断了一条路｜⚠⚠⚨ **整行锚定**：盯串的话「`why = shortcut_reason(strip_literals(cond)) or None`」照样命中 ⇒ **统一入口被绕开而门假绿**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+got = shortcut_reason\(strip_literals\(inp\)\) is not None$' 1 '**自检**也必须走同一个入口（自检与实扫分家 ⇒ 自检测的不是真判定）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def heredoc_spans\(lines\):$' 1 '**heredoc 感知的实现**必须在（内嵌脚本的判据不许漏判 ⇒ 不摘出来就扫不到）｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def python_if_conds\(text, first_line=1\):$' 1 '**python 条件提取器**必须在（跨行 + heredoc 内嵌都靠它 ⇒ 只按行匹配会漏）｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+skip\.add\(k\)$' 1 'shell 条件扫描**必须跳过 heredoc 体**（否则内嵌 python 的 if 被误当 shell 条件 ⇒ 误判）｜⚠⚠⚨ **整行锚定**：批 BJ 负控实测「把真代码换成 `pass  # skip.add(k)`」⇒ 盯串的话计数仍是 1 ⇒ **门假绿** ⇒ 注释能替代码 ⇒ 关键判定必须整行锚定'

# ── 批 BK · 剥注释必须覆盖 .py（根治「注释顶替真代码」这一整类洞）──────────
# ⚠⚠⚨ **起因（批 BJ 负控实测坐实）**：把真代码 `skip.add(k)` 换成
#   `pass  # skip.add(k)` ⇒ **盯串**的门项命中数仍是 1 ⇒ **门假绿**
#   ⇒ 真代码已经被删了，门却看不出来 ⇒ 「注释能替代码」。
#   ⚠⚠⚨ 这是批 BH「盯串不够，要盯整行」教训的**另一头**
#   （那边是「判定被掏空但串还在」；这边是「代码被删但串还在」）。
# ⚠⚠⚨ **根治办法（不是逐条治标）**：让 `strip_comments` 对 `.py` 也剥 `#`
#   ⇒ **所有**盯 `.py` 的门项一次性不再被注释顶替。
#   ⚠⚠⚨ **两侧必须同步**（批 AS 纪律：审计器必须调**同一条**命令）
#   ⇒ 不一致 ⇒ 审计器的配准校准当场失准 ⇒ 会被抓到（这本身也是一层自护）。
# ⚠⚠⚨ **附带修掉**：python 的 `//` 是整除运算符 ⇒ 原来被当注释剥掉。
arch_need_count "$SRC/scripts/ci-wiring.sh" '^\s+\*\.sh\|\*\.txt\|\*\.py\)$' 1 '门侧的剥注释**必须覆盖 .py**（⇒ 注释里的串顶替不了真代码 ⇒ 这一整类洞根治）｜⚠ **两侧必须同步**（审计器也用同一条命令）⇒ 不一致 ⇒ 配准校准失准 ⇒ 会被抓到'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+if path\.endswith\(.\.sh.\) or path\.endswith\(.\.txt.\) or path\.endswith\(.\.py.\):$' 1 '审计器的剥注释**必须覆盖 .py**（⚠ 两侧口径必须一致 ⇒ 否则同一串在两侧算得不一样 ⇒ 校准失准）｜⚠⚠⚨ **整行锚定**：盯串的话「`or path.endswith(引号位置)` 被换掉」照样命中 ⇒ **口径悄悄变了没人知道**｜⚠ **引号位置写 `.`**（正则参数用单引号包裹 ⇒ 不能含字面单引号）'

# ── 批 BL · 盯「门自己的工具」的门项必须**整行锚定**（根治「判定被掏空但串还在」）──
# ⚠⚠⚨ **起因**：门项盯**串** ⇒ 判定被掏空但**串还在** ⇒ 门照样绿。
#   例：把 `if bad:` 改成 `if bad or True:` ⇒ 串还在 ⇒ 盯串的门**假绿**
#   ⇒ 而 `if bad:` 正是**探针「违规 ⇒ 判红」的那一行** ⇒ 掏空它 = 探针集体失效。
# ⚠⚠⚨ 批 BK 根治了「**注释顶替代码**」（`.py` 也剥 `#`）
#   ⇒ 但「**判定被掏空、串还在**」这一头仍只靠**整行锚定**挡。
# ⚠⚠⚨ **为什么先只收探针文件**：探针是「**门自己的工具**」
#   ⇒ 它被掏空 = 门**集体**失效 ⇒ 风险最高 ⇒ 先收进这一处（范围可控）。
#   ⚠ 全仓逐批推进（已知边界，如实记着）。
# ⚠⚠⚨ **审计器负责判定**（批 AS 纪律：判定逻辑只有一份 ⇒ 实扫与自检都走它）
#   ⇒ 审计器新增第 8 种失败态 = **锚定形态违规 / 锚定形态自检不过**。
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def anchoring_violation\(rx\):$' 1 '锚定形态的**判定函数**必须在（⚠ 判定逻辑只许有一份 ⇒ 实扫与自检都走它 ⇒ 两套口径必然漂）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def anchoring_selftest\(\):$' 1 '锚定形态的**自检**必须在（门自己证明自己有牙 ⇒ 判定被掏空时当场红）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+stbad = anchoring_selftest\(\)$' 1 '锚定形态的**自检必须被调用**（只定义不调用 ⇒ 自检形同虚设 ⇒ 没人会发现判定被掏空）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def check_anchor_scope\(cnt_items, exempt\):$' 1 '锚定形态的**实扫**必须在（探针是门自己的工具 ⇒ 它的门项必须整行锚定）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+anchbad, anchor_need = check_anchor_scope\(cnt, anchor_exempt\)$' 1 '锚定形态的**实扫必须被调用**（定义了不调 ⇒ 没人发现探针门项被改回盯串）｜⚠⚠⚨ **整行锚定**｜⚠⚠⚨ **第二返回值 = 「需要豁免」的集合**（豁免表的唯一合法来源）'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+FAILS.append\(8\)$' 2 '审计器的**第 8 种失败态**必须在（⚠ **两处**：锚定形态**自检**不过 + 实扫出违规 ⇒ 两种失败要分开 ⇒ 不然排障会被带偏）（⚠⚠⚨ **批 CQ**：形态从 `return 8` 改成 `FAILS.append(8)`）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^ANCHOR_SCOPE_SUFFIXES = \(.ci-tautology-check\.py., .ci-wiring-audit\.py., .ci\.sh., .ci-wiring\.sh., .ci-platform-probe\.sh., .ci-docs-lang-probe\.sh., .ci-divider-probe\.sh., .probe-agent-tool-surface\.sh., .ci-orphan-probe\.sh., .check-deb-layout\.sh., .contract-check\.sh., .ci-d2\.sh., .smoke\.sh., .bootstrap-deps\.py., .ci-true-audit\.py., .build-deb\.sh., .ci-unverified-audit\.py.\)$' 1 '审计器的**锚定形态适用范围常量**的**定义**必须在（⚠ **整行锚定**：定义与使用是两处不同形态 ⇒ 拆成两条）｜⚠⚠⚨ **适用范围必须同时含探针与审计器自身**（两者都是「门自己的工具」⇒ 被掏空 = 门集体失效）｜⚠⚠⚨ **批 BN：范围扩到 `ci.sh`**（CI 入口的门项同样是「门自己的工具」）｜⚠⚠⚨ **批 BR：范围再扩到 `ci-wiring.sh`**（**门脚本本体** ⇒ 它的门项就是「判定层不许被掏空」那一整类承诺的载体 ⇒ 载体被掏空 = 承诺集体失效）｜⚠⚠⚨ **批 BS：范围再扩到 5 个探针脚本**（CI 里跑的断言脚本 ⇒ 它们的判定行同样是「门自己的工具」⇒ 被掏空 = 那批承诺集体失效）｜⚠⚠⚨ **批 BY：范围再扩到 2 个计数器型断言脚本**（`check-deb-layout.sh` + `contract-check.sh` ⇒ 它们的**失败计数点**与**末尾判定行**同样是「判定不许被掏空」那一整类承诺的载体）｜⚠⚠⚨ **批 CA：范围再扩到 3 个**（`ci-d2.sh` + `smoke.sh` + `bootstrap-deps.py` ⇒ 它们的**失败上报出口**同样是「失败必须真的报出去」那一整类承诺的载体）｜⚠⚠⚨ **批 CL：范围再扩到 `build-deb.sh`**（⚠ 它是 **CI 第 11 步跑的断言脚本** ⇒ 它的判定行同样是「门自己的工具」⇒ 被掏空 = 那批承诺集体失效 ⇒ 按批 BS 纪律必须纳入）｜⚠⚠⚨ **批 CM：范围再扩到 `ci-unverified-audit.py`**（⚠ 它是 **CI 里跑的盘点脚本** ⇒ 它的判定行同样是「门自己的工具」⇒ 被掏空 = 那批承诺集体失效 ⇒ 按批 BS 纪律必须纳入）'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+if not f\.endswith\(ANCHOR_SCOPE_SUFFIXES\):$' 1 '审计器的**锚定形态适用范围常量**的**使用点**必须在（⚠ 散在别处 ⇒ 改一处就废掉另一处 ⇒ 范围悄悄变了没人知道）｜⚠⚠⚨ **整行锚定**｜⚠⚠⚨ **批 BN：范围判定只此一处**（正向扫描与豁免反向配准共用它算出的「需要豁免」集合 ⇒ 两边口径天然一致 ⇒ 不许各判各的）'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^\s+8\) _audit_why="[^"]*" ;;$' 1 '接线门必须**按审计器的第 8 种失败态说原因**（⚠ 批 AZ 实测：不按退出码说原因 ⇒ 排障会被带偏）｜⚠⚠⚨ **整行锚定**｜⚠⚠⚨ **批 BR 整行锚定**：中间的无界通配（点星）⇒ 行首行尾锚死但中间什么都能吃 ⇒ 名存实亡 ⇒ 改成有界通配'

# ── 批 BN · 「整行锚定」的**豁免机制** + 改名漏改的**静态兜底** ───────────────────
#
# ⚠⚠⚨ **为什么必须有豁免**：批 BN 把 `ci.sh` 纳入「整行锚定」的适用范围
#   ⇒ 实测有 **6 条**门项**不能**整行锚定（锚了会把语义**改窄**）
#   ⇒ 必须有**显式豁免** ⇒ 豁免 = 「**允许弱化的门项**」白名单
#   ⇒ 每一行都要写**理由**、**坏行不豁免**（fail closed）。
# ⚠⚠⚨ **豁免表不许悄悄变长** ⇒ 靠**双向配准**钉死（不是另写一个条数基线）：
#   ① 正向（`check_anchor_scope`）：适用范围内的门项若不锚定 ⇒ **必须**在豁免表里
#   ② 反向（`check_anchor_exempt_reconcile`）：豁免表里每一行 ⇒ **必须**对得上一条现存门项
#   ⇒ 两者合起来 ⇒ **豁免表 ≡ 适用范围内的「非锚定门项」集合**（一一对应）
#   ⇒ 条数是**推导出来的**（⇒ 少一处可以被人偷偷改的地方）。
# ⚠⚠⚨ **改名漏改的静态兜底**（批 BN **实测坐实**的真 bug，不是推演）：
#   批 BM 改名 `check_probe_gate_anchoring` → `check_gate_tool_anchoring` 时
#   **漏改了报告模式（无参）那处调用点** ⇒ 报告模式一跑就 `NameError` 崩掉
#   ⇒ 而 CI **只跑 `--list`** ⇒ 这条路径**根本没人跑** ⇒ 崩了**没人发现**
#   ⇒ 一路带到了已推送的 HEAD ⇒ 现在加 `check_undefined_names()`（symtable 静态抓）。
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^ANCHOR_EXEMPT = os\.path\.join\(SRC, .scripts., .ci-wiring-anchor\.exempt.\)$' 1 '锚定豁免基线的**路径常量**必须在（⚠ **整行锚定**：路径改到别处 ⇒ 豁免表读的是另一个文件 ⇒ 豁免机制**静默换人**）｜⚠⚠⚨ **单一真相源**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def read_anchor_exempt\(\):$' 1 '豁免表的**读取函数**必须在（⚠ 键 = 门型 + 路径 + 正则 ⇒ 三者合起来才唯一 ⇒ 少一个就会**跨门型漏豁免**）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+read_anchor_exempt\(\)$' 1 '豁免表的**读取必须被调用**（定义了不调 ⇒ 豁免表是**摆设** ⇒ 所有人都以为弱化点被管住了）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def is_anchor_exempted\(kind, relpath, rx, exempt\):$' 1 '豁免的**判定函数**必须在（⚠ **判定逻辑只许有一份** ⇒ 实扫与别处不许各判各的 ⇒ 两套口径必然漂）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+if is_anchor_exempted\(key\[0\], key\[1\], key\[2\], exempt\):$' 1 '豁免的**判定必须真的在判定路径上**（⚠ 判定被掏空成「恒真」⇒ **所有**门项都被豁免 ⇒ 门集体失效 ⇒ 比没豁免还糟）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def check_undefined_names\(\):$' 1 '审计器**引用了未定义的名字**的静态检查必须在（批 BN 实测坐实：改名漏改调用点 ⇒ 那条路径没人跑 ⇒ 崩了没人发现 ⇒ 一路带到已推送的 HEAD）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+undef = check_undefined_names\(\)$' 1 '未定义名的静态检查**必须被调用**（定义了不调 ⇒ 这类洞**原样回来** ⇒ 等于没修）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def check_anchor_exempt_reconcile\(need_exempt, exempt\):$' 1 '豁免表的**反向配准**必须在（豁免表 = 弱化点白名单 ⇒ 弱化点必须**有对应物** ⇒ 否则要么门项被删却忘了清豁免（承诺悄悄消失），要么塞了空豁免，要么给已锚定的门项白占一行（豁免表在悄悄变长））｜⚠⚠⚨ **整行锚定**｜⚠⚠⚨ **对标的是「非锚定门项」而不是「任何门项」**（只对标「任何门项」⇒ 给已锚定门项加豁免照样混过去 ⇒ 这道门没牙）'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+dead = check_anchor_exempt_reconcile\(anchor_need, anchor_exempt\)$' 1 '豁免表的**反向配准必须被调用**（定义了不调 ⇒ 反向配准形同虚设 ⇒ 豁免表可以**无限变长**）｜⚠⚠⚨ **整行锚定**｜⚠⚠⚨ **必须用正向扫描算出的「需要豁免」集合**（自己另算一套 ⇒ 两套口径必然漂）'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+FAILS.append\(9\)$' 4 '审计器的**第 9 种失败态**必须在（⚠ **四处**：未定义名 + 豁免坏行 + 豁免文件不在 + 豁免对不上门项 ⇒ 四种失败要分开 ⇒ 不然排障会被带偏）（⚠⚠⚨ **批 CQ**：形态从 `return 9` 改成 `FAILS.append(9)`）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+return \(kind, relpath, rx\.rstrip\(\)\) in exempt$' 1 '豁免**判定的那一行**必须在（⚠ 只盯调用点**盯不住判定体** ⇒ 判定被掏空成「恒真」⇒ **所有**门项都被豁免 ⇒ 门集体失效 ⇒ 比没豁免还糟）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+if \(kind, path, rx\.rstrip\(\)\) not in need_exempt:$' 1 '反向配准的**判定那一行**必须在（⚠ 只盯调用点**盯不住判定体** ⇒ 判定被掏空 ⇒ 豁免表可以**无限变长** ⇒ 「不许悄悄变长」就废了）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^\s+9\) _audit_why="[^"]*" ;;$' 1 '接线门必须**按审计器的第 9 种失败态说原因**（⚠ 批 AZ 实测：不按退出码说原因 ⇒ 排障会被带偏）｜⚠⚠⚨ **整行锚定**｜⚠⚠⚨ **批 BR 整行锚定**：中间的无界通配（点星）⇒ 行首行尾锚死但中间什么都能吃 ⇒ 名存实亡 ⇒ 改成有界通配'
# ── 批 BO · 接线门脚本自己的「失败上报路径」必须有门 ────────────────────────────
#
# ⚠⚠⚨ **为什么要有这一段**（批 BO 实测坐实，不是推演）：
#   `ARCH_FAIL=1` 是「**门型判定失败 → 整道门红**」的**唯一通路**
#   ⇒ 把它改成 `ARCH_FAIL=0` ⇒ **那个门型的所有失败都静默**
#   ⇒ 而审计器**自己重算命中数**（次数配准）⇒ 期望与实际仍然一致 ⇒ **审计器也抓不到**
#   ⇒ ⇒ 这是「**判定被掏空、串还在**」的最严重形态（而且是**批量**的）：
#     改一处 ⇒ 一个门型的全部承诺同时失效。
# ⚠⚠⚨ **实测盘子**（门侧同口径量，**重新数**，不照抄二手数）：
#   全文失败上报 **35** 处（**28** 处在 16 个门型/上报函数体内，**7** 处在顶层）；
#   `arch_` 门型函数 **14** 个（**10** 个直接写上报、**4** 个 forbid 族转发给上报函数）。
# ⚠⚠⚨ **三层钉法**（不用新门型 ⇒ 审计器零改动）：
#   ① **per-函数**（16 条）：每个门型/上报函数体内**到底有几处上报** ⇒ **指名道姓**
#      ⇒ 用现成的 `arch_need_count_in_fn`（它**认识函数体结构** ⇒ 批 BE 纪律）
#      ⇒ ⚠ 转发型门型盯的是「**必须调用上报函数**」⇒ 转发关系被摘掉也红。
#   ② **总数**（1 条）：全文 **35** 处 ⇒ 覆盖**顶层**那 7 处
#      ⇒ ⚠ 顶层块**没有花括号** ⇒ `arch_need_count_in_fn` 提不出「函数体」⇒ 只能靠总数兜。
#   ③ **注册表**（1 条）：`arch_` 门型函数**恰好 14 个** ⇒ 新增门型 ⇒ 必须改基线
#      ⇒ 改的时候就会看到「**新门型也得有失败上报**」⇒ 集合层把新成员挡住。
# ⚠⚠⚨ **判据要避开自引**（批 BI 纪律）：总数与注册表的正则都**行首锚定**
#   ⇒ 门项行自己不会被数进去 ⇒ 期望值里不混着「自己」。

arch_need_count "$SRC/scripts/ci-wiring.sh" '^arch_\w*\(\) \{ # [^$]*$' 15 '`arch_` **门型函数的注册表**（恰好 15 个）—— 新增门型 ⇒ 必须改这条基线 ⇒ 改的时候就会看到「**新门型也得有失败上报**」 ⇒ 集合层把新成员挡住（⚠ **行首锚定**：门项行自己不会被数进去 ⇒ 不自引）｜⚠⚠⚨ **批 BZ：新增了门型 `arch_need_count_pair`（配对门）⇒ 14 → 15**｜⚠⚠⚨ **批 BR 整行锚定**：行尾补 `$` ⇒ 只锚行首不够 ⇒ 判定被掏空但串还在 ⇒ 门假绿'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^\s+ARCH_FAIL=1( ;;)?$' 41 '**全文失败上报的总数**（恰好 39 处）—— ⚠⚠⚨ 它是「门型判定失败 → 整道门红」的**唯一通路** ⇒ 改成别值 ⇒ **那个门型的所有失败都静默** ⇒ 而审计器**自己重算命中数** ⇒ **也抓不到** ⇒ 这条门把「静默失效」变成「必红」（⚠ **行首锚定** ⇒ 门项行不自引）｜⚠⚠⚨ **批 BZ：配对门带 2 处 `ARCH_FAIL=1` ⇒ 35 → 37**｜⚠⚠⚨ **批 CM：加了一处「跑盘点」**（接线门必须真的跑一次未验证出口盘点 ⇒ 盘点与登记册对不上 ⇒ `ARCH_FAIL=1`）⇒ 失败上报处数 **38 → 39**（**原地替换**，批 BM 纪律）｜⚠⚠⚨ **批 CN：两处「没有 perl」改成判红**（`arch_forbid_han` / `arch_forbid_text_dup` ⇒ 以前是「显式 SKIP（不算通过）」⇒ 那是**批 CB / CC 之前的旧口径** ⇒ 只是**碰巧**不可达（顶部 preflight 先 exit 1）⇒ **preflight 被摘就静默放行 ⇒ 假绿**）⇒ 失败上报处数 **39 → 41**（**原地替换**，批 BM 纪律）'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^probe_scan_report\(\)' '^\s+ARCH_FAIL=1' 3 '**probe_scan_report** 的失败上报（函数体内恰好 3 处）—— ⚠ 判定失败必须真的把失败标记打出去 ⇒ 少一处 ⇒ **这个门型的失败全部静默** ⇒ 审计器自己重算命中数 ⇒ **抓不到** ⇒ 这条门让「静默失效」变成「必红」'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^probe_scan_report_many\(\)' '^\s+ARCH_FAIL=1' 2 '**probe_scan_report_many** 的失败上报（函数体内恰好 2 处）—— ⚠ 判定失败必须真的把失败标记打出去 ⇒ 少一处 ⇒ **这个门型的失败全部静默** ⇒ 审计器自己重算命中数 ⇒ **抓不到** ⇒ 这条门让「静默失效」变成「必红」'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_need\(\)' '^\s+ARCH_FAIL=1' 2 '**arch_need** 的失败上报（函数体内恰好 2 处）—— ⚠ 判定失败必须真的把失败标记打出去 ⇒ 少一处 ⇒ **这个门型的失败全部静默** ⇒ 审计器自己重算命中数 ⇒ **抓不到** ⇒ 这条门让「静默失效」变成「必红」'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_need_ml\(\)' '^\s+ARCH_FAIL=1' 2 '**arch_need_ml** 的失败上报（函数体内恰好 2 处）—— ⚠ 判定失败必须真的把失败标记打出去 ⇒ 少一处 ⇒ **这个门型的失败全部静默** ⇒ 审计器自己重算命中数 ⇒ **抓不到** ⇒ 这条门让「静默失效」变成「必红」'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_need_any_count\(\)' '^\s+ARCH_FAIL=1' 1 '**arch_need_any_count** 的失败上报（函数体内恰好 1 处）—— ⚠ 判定失败必须真的把失败标记打出去 ⇒ 少一处 ⇒ **这个门型的失败全部静默** ⇒ 审计器自己重算命中数 ⇒ **抓不到** ⇒ 这条门让「静默失效」变成「必红」'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_need_any_min\(\)' '^\s+ARCH_FAIL=1' 1 '**arch_need_any_min** 的失败上报（函数体内恰好 1 处）—— ⚠ 判定失败必须真的把失败标记打出去 ⇒ 少一处 ⇒ **这个门型的失败全部静默** ⇒ 审计器自己重算命中数 ⇒ **抓不到** ⇒ 这条门让「静默失效」变成「必红」'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_need_count\(\)' '^\s+ARCH_FAIL=1' 2 '**arch_need_count** 的失败上报（函数体内恰好 2 处）—— ⚠ 判定失败必须真的把失败标记打出去 ⇒ 少一处 ⇒ **这个门型的失败全部静默** ⇒ 审计器自己重算命中数 ⇒ **抓不到** ⇒ 这条门让「静默失效」变成「必红」'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_need_min\(\)' '^\s+ARCH_FAIL=1' 2 '**arch_need_min** 的失败上报（函数体内恰好 2 处）—— ⚠ 判定失败必须真的把失败标记打出去 ⇒ 少一处 ⇒ **这个门型的失败全部静默** ⇒ 审计器自己重算命中数 ⇒ **抓不到** ⇒ 这条门让「静默失效」变成「必红」'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_need_count_in_fn\(\)' '^\s+ARCH_FAIL=1' 3 '**arch_need_count_in_fn** 的失败上报（函数体内恰好 3 处）—— ⚠ 判定失败必须真的把失败标记打出去 ⇒ 少一处 ⇒ **这个门型的失败全部静默** ⇒ 审计器自己重算命中数 ⇒ **抓不到** ⇒ 这条门让「静默失效」变成「必红」'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_need_count_in_step\(\)' '^\s+ARCH_FAIL=1' 2 '**arch_need_count_in_step** 的失败上报（函数体内恰好 2 处）—— ⚠ 判定失败必须真的把失败标记打出去 ⇒ 少一处 ⇒ **这个门型的失败全部静默** ⇒ 审计器自己重算命中数 ⇒ **抓不到** ⇒ 这条门让「静默失效」变成「必红」'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_forbid_han\(\)' '^\s+ARCH_FAIL=1' 3 '**arch_forbid_han** 的失败上报（函数体内恰好 2 处）—— ⚠ 判定失败必须真的把失败标记打出去 ⇒ 少一处 ⇒ **这个门型的失败全部静默** ⇒ 审计器自己重算命中数 ⇒ **抓不到** ⇒ 这条门让「静默失效」变成「必红」｜⚠⚠⚨ **批 CN：那支「没有 perl」改成判红**（原先只打印 SKIP ⇒ 不算失败 ⇒ **静默放行**）⇒ 函数体内失败上报 **2 → 3**（**原地替换**，批 BM 纪律）'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_forbid_text_dup\(\)' '^\s+ARCH_FAIL=1' 7 '**arch_forbid_text_dup** 的失败上报（函数体内恰好 6 处）—— ⚠ 判定失败必须真的把失败标记打出去 ⇒ 少一处 ⇒ **这个门型的失败全部静默** ⇒ 审计器自己重算命中数 ⇒ **抓不到** ⇒ 这条门让「静默失效」变成「必红」｜⚠⚠⚨ **批 CN：那支「没有 perl」改成判红**（原先只打印 SKIP ⇒ 不算失败 ⇒ **静默放行**）⇒ 函数体内失败上报 **6 → 7**（**原地替换**，批 BM 纪律）'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_forbid\(\)' '^\s+probe_scan_report ' 1 '**arch_forbid** 必须**转发给上报函数**（函数体内恰好 1 次调用 `probe_scan_report`）—— ⚠ forbid 族的失败**不自己上报** ⇒ 转发关系被摘掉 ⇒ **这个门型的失败全部静默** ⇒ 而它自己不报错 ⇒ 谁都看不出来'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_forbid_ml\(\)' '^\s+probe_scan_report ' 1 '**arch_forbid_ml** 必须**转发给上报函数**（函数体内恰好 1 次调用 `probe_scan_report`）—— ⚠ forbid 族的失败**不自己上报** ⇒ 转发关系被摘掉 ⇒ **这个门型的失败全部静默** ⇒ 而它自己不报错 ⇒ 谁都看不出来'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_forbid_raw\(\)' '^\s+probe_scan_report ' 1 '**arch_forbid_raw** 必须**转发给上报函数**（函数体内恰好 1 次调用 `probe_scan_report`）—— ⚠ forbid 族的失败**不自己上报** ⇒ 转发关系被摘掉 ⇒ **这个门型的失败全部静默** ⇒ 而它自己不报错 ⇒ 谁都看不出来'
arch_need_count_in_fn "$SRC/scripts/ci-wiring.sh" '^arch_forbid_tree\(\)' '^\s+probe_scan_report_many ' 1 '**arch_forbid_tree** 必须**转发给上报函数**（函数体内恰好 1 次调用 `probe_scan_report_many`）—— ⚠ forbid 族的失败**不自己上报** ⇒ 转发关系被摘掉 ⇒ **这个门型的失败全部静默** ⇒ 而它自己不报错 ⇒ 谁都看不出来'


# ── 批 BP · 恒真探针自己的「扫描范围」不许被改窄 ─────────────────────────────
#
# ⚠⚠⚨ **为什么要有这一段**（批 BP **实测坐实**，不是推演）：
#   恒真探针（`ci-tautology-check.py`）是「**判据不许被掏空成恒真**」那一整类洞的
#   **唯一执行者** ⇒ 它的**扫描范围**就是那一整类洞的**覆盖面**。
#   ⇒ 实测：把「扫 `.sh` 脚本」那一行改掉 ⇒ **所有 shell 脚本的 if 条件都不再被查**
#     ⇒ 而探针**自己没有条数基线** ⇒ 少扫了它也照样输出「✓」并 **rc=0**
#     ⇒ ⇒ 探针**静默变成半个空门** ⇒ 批 BJ 建立的「脚本侧捷径」那一整类洞**失守**
#     ⇒ 而 CI **只跑这一个入口** ⇒ 没人会发现。
# ⚠⚠⚨ **修法（两层）**：
#   ① **范围行逐条钉住**（4 条 + 判定层那 2 条已在批 BJ 段）⇒ 改范围常量 ⇒ 必红
#   ② **扫到的文件数必须有基线**（`scripts/ci-tautology-scope.baseline`）
#      ⇒ ⚠ **恰好**（批 BB 口径：「不少于」天生带余量 ⇒ 少一个还绿 ⇒ 没牙）
#      ⇒ ⚠ **fail closed**：基线读不到 / 坏行 ⇒ 照红（不许「读不到就当没有基线」）
#      ⇒ ⚠ **基线是自锚的**（批 BH 纪律的关键差别）：期望值写在**独立文件**里，
#        实际值来自**文件系统** ⇒ 改基线单独就红 ⇒ 裁判改不了标准。
# ⚠⚠⚨ **判据要避开自引**（批 BI 纪律）：正则参数**行首锚定** ⇒ 门项行自己不会被数进去。
# ⚠⚠⚨ **引号位置写 `.`**（批 BL 既有约定）：门项正则**不能含字面单引号**
#   ⇒ 代码里 `fn.endswith('.sh')` 的引号只能写 `.`（实测 GNU grep 3.11 的 `-E`
#   不认 `[\x27]`、不认 `\047`）⇒ ⚠ 整行锚定已把这个弱点大幅削弱。

arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+appdir = os\.path\.join\(root, .src., .app.\)$' 1 '恒真探针的**判定层目录**必须在（⚠ **整行锚定**：改目录 ⇒ 扫不到判定文件 ⇒ 那一整类判据**不再被查恒真** ⇒ 探针静默变成半个空门）｜⚠⚠⚨ **批 BP**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+scripts = os\.path\.join\(root, .scripts.\)$' 1 '恒真探针的**脚本目录**必须在（⚠ **整行锚定**：改目录 ⇒ shell/python 脚本的 if 条件**不再被查恒真** ⇒ 批 BJ 那一整类洞失守）｜⚠⚠⚨ **批 BP**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if not fn\.endswith\(.\.sh.\):$' 1 '恒真探针的 **shell 脚本范围**必须在（⚠ **整行锚定**；⚠ 引号位置只能写 `.` ⇒ 正则参数不许含字面单引号）—— 改扩展名 ⇒ 所有 .sh 的 if 条件**不再被查恒真** ⇒ **静默**（改前实测：探针照样输出「✓」并 rc=0）｜⚠⚠⚨ **批 BP**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if not fn\.endswith\(.\.py.\):$' 1 '恒真探针的 **python 脚本范围**必须在（⚠ **整行锚定**；⚠ 引号位置只能写 `.`）—— 改扩展名 ⇒ 所有 .py 的 if 条件**不再被查恒真** ⇒ **静默**｜⚠⚠⚨ **批 BP**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^SCOPE_BASELINE = .ci-tautology-scope\.baseline.$' 1 '恒真探针的**扫描范围基线文件**路径常量必须在（⚠ **整行锚定**：基线放**独立文件** ⇒ 裁判改不了标准；⚠ **单一出处**）｜⚠⚠⚨ **批 BP**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def read_scope_baseline\(scripts\):$' 1 '扫描范围基线的**读取函数**必须在（⚠ 少一行 / 坏行 ⇒ 必须**返回 None** ⇒ fail closed ⇒ 不许「读不到就当没有基线」）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+scope_expect = read_scope_baseline\(scripts\)$' 1 '扫描范围基线**必须被读取**（定义了不读 ⇒ 基线是摆设 ⇒ 范围随便改 ⇒ 探针静默失守）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if scope_expect is None:$' 1 '基线**读不到**必须**fail closed**（照红）—— 不许「读不到就当没有基线」⇒ 否则删掉基线文件 ⇒ 范围检查整个消失 ⇒ 探针静默失守｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if got_scope\[key\] != want:$' 1 '**扫到的文件数**必须与基线**完全相等**（⚠ **恰好** ⇒ 少一个就红；「不少于」天生带余量 ⇒ 少一个还绿 ⇒ 没牙 —— 批 BB 口径）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+want = scope_expect\[key\]$' 1 '基线里那个口径的**期望值**必须真的取出来用（⚠ 取错了 ⇒ 比的是别的 ⇒ 范围检查名存实亡）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-tautology-scope.baseline" '^[a-z_]+ [0-9]+$' 7 '扫描范围基线文件**恰好 7 行带口径名**（每行 `<口径名> <数字>`：判定层 / shell / macos_shell / assets_shell / linux_shell / python / **swift** 各一行）—— ⚠ 行数变了 ⇒ 口径错位 ⇒ 范围检查名存实亡 ⇒ **基线自己也要被守**（批 BH 纪律）｜⚠⚠⚨ **批 CZ**：加了 mac 侧那一行 ⇒ 3 → 4｜⚠⚠⚨ **批 DB**：再加 assets / linux 两行 ⇒ 4 → 6；⚠⚠⚨ **批 DC**：基线改成**带口径名**的格式（每行 `<口径> <数字>`）⇒ 6 行 → 7 行（加 Swift 那一行）⇒ ⚠ 原先是**纯数字**、靠**行序**对应口径 ⇒ ⚠ 两个口径的数字**相同**时（python 5 / swift 5）门就**钉不住是哪个** ⇒ 「每个口径记两遍」立不住 ⇒ 改成带名字 ⇒ 每个口径能**单独**钉住'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if not os\.path\.isdir\(d\):$' 1 '恒真探针的**扫描目录不存在**必须**明确报错**（不许崩成 traceback ⇒ 崩掉的退出码也是 1 ⇒ CI 照样红，但**看不出是哪一步坏了** ⇒ 排障会被带偏 —— 批 AZ 纪律）｜⚠⚠⚨ **批 BP**｜⚠⚠⚨ **整行锚定**'
if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BH/BI 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BH 段门项全绿（门项总数不许被悄悄删；审计器门型覆盖对拍也在）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0
echo "✓ 批 BI 段门项全绿（forbid 门族不许静默变绿；工具坏了 ⇒ 红，不是绿）；门项合计 ${ARCH_N} 项（含前段）"
echo "✓ 批 BJ 段门项全绿（恒真探针看得见脚本侧捷径与 heredoc 内嵌脚本）；门项合计 ${ARCH_N} 项（含前段）"
echo "✓ 批 BK 段门项全绿（剥注释覆盖 .py ⇒ 注释顶替不了真代码）；门项合计 ${ARCH_N} 项（含前段）"
echo "✓ 批 BL 段门项全绿（盯门自己的工具的门项必须整行锚定；判定被掏空但串还在 ⇒ 门假绿）；门项合计 ${ARCH_N} 项（含前段）"
echo "✓ 批 BN 段门项全绿（整行锚定的豁免机制：双向配准 ⇒ 豁免表 ≡ 非锚定门项集合；改名漏改有静态兜底）；门项合计 ${ARCH_N} 项（含前段）"
echo "✓ 批 BO 段门项全绿（接线门脚本自己的失败上报路径：per-函数 + 总数 + 注册表 ⇒ 少了上报 = 必红）；门项合计 ${ARCH_N} 项（含前段）"
echo "✓ 批 BP 段门项全绿（恒真探针自己的扫描范围：范围行逐条钉住 + 文件数基线恰好相等 ⇒ 范围被改窄 = 必红）；门项合计 ${ARCH_N} 项（含前段）"

# ── 批 BQ · 「整行锚定」不许名存实亡（中间不许无界通配）─────────────────────
#
# ⚠⚠⚨ **起因（批 BP 实测坐实，不是推演）**：
#   批 BL/BM/BN 一路用**整行锚定**挡「**判定被掏空、串还在**」
#   ⇒ 但整行锚定只看「行首 `^`」+「行尾 `$`」
#   ⇒ 中间放一个**点星**（无界通配）⇒ 行首行尾锚死、**中间什么都能吃**
#   ⇒ ⇒ 判定被掏空、串还在 ⇒ 门照样绿 ⇒ 「整行锚定」**名存实亡**。
#   实测：探针的样例表门项就是这种写法 ⇒ 样例表内容随便改都照样命中
#   ⇒ 那道门是**假的**（批 BL 遗留的「锚定 ≠ 内容」那条边界，本批收掉一半）。
# ⚠⚠⚨ **修法（三层）**：
#   ① **审计器加一条判定** `has_unbounded_wildcard()`：只认**未转义**的点星
#      （点号前**偶数**个反斜杠 ⇒ 是通配；**奇数**个 ⇒ 被转义 ⇒ 是字面点）
#      ⇒ 适用范围仍是「门自己的工具」（探针 / 审计器 / ci.sh）
#      ⇒ 违规 ⇒ 审计器第 8 种失败态（rc=8）。
#   ② **自检必须含正反两面**（批 BF 纪律）：含点星的**必判违规** /
#      有界通配的**必判合规** / 转义点星的**必判合规** ⇒ 判定被掏空时当场红。
#   ③ **把那 2 条「名存实亡」的门项改成精确形式**（本批同批改）：
#      按「类别 + 期望」拆成 **9 条**（cond 6+3 / shortcut 8+4 /
#      assert_arg 2+1+2+1 / shell_scan 1）⇒ 中间用**有界**通配
#      ⇒ 吃不掉结构分隔符 ⇒ 行结构仍被钉住 ⇒ 整行锚定**名副其实**。
# ⚠⚠⚨ **中间为什么用「有界」通配**（实测踩到，记下来）：
#   正则参数用**单引号**包裹 ⇒ 正则里**不能有字面单引号**（批 BL 既有约束）
#   ⇒ 字符类里写不了 `[^\']` ⇒ 只能挑**不含引号**的结构分隔符：
#   逗号 / 右括号 / 右方括号 ⇒ `[^,]` / `[^)]` / `[^]]`。
#   ⚠⚠ **踩到的坑**：右括号类罩不住 `('check', "d.get('x')==1")`
#     ⇒ 那个实参里**带右括号** ⇒ 实测命中 **0**（不是 1）⇒ 改用逗号类才罩住。
#   ⚠⚠ **另一个坑**：`('shell_scan', (<文本>, [<列表>]), True)` 的**结构顺序**
#     是「列表在右括号**之前**」⇒ 正则必须写成 `\([^)]*, \[[^]]*\]\)`
#     ⇒ 写反了实测命中 **0**。
# ⚠⚠⚨ **本段 5 条门项守的是「新规则自己不许被掏空」**：
#   规则被掏空 ⇒ 「整行锚定」继续名存实亡 ⇒ 而**没人会发现**
#   （审计器自己绿 ⇒ 它的报告没人怀疑）⇒ 所以规则本身也要有门。
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def has_unbounded_wildcard\(mid\):$' 1 '无界通配的**判定函数**必须在（⚠ 判定逻辑只许有一份 ⇒ 实扫与自检都走它 ⇒ 两套口径必然漂）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+if nb % 2 == 0:$' 1 '无界通配判定的**转义计数行**必须在（⚠ 点号前**偶数**个反斜杠 ⇒ 这个点号是通配元字符；**奇数**个 ⇒ 被转义 ⇒ 是字面点）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+return True$' 1 '无界通配判定的**「判违规」返回**必须在（⚠ 全文件恰好 1 处 ⇒ 判定被掏空成 `return False` 就红）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+if has_unbounded_wildcard\(rx\[1:-1\]\):$' 1 '无界通配判定**必须真的在判定路径上**（⚠ 只定义不调用 ⇒ 规则形同虚设 ⇒ 整行锚定继续名存实亡）｜⚠⚠⚨ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+\(r.[^,]*, (True|False)\),$' 9 '锚定形态**自检的样例条数**必须是 9（⚠ 4 条原有 + 3 条批 BQ 新增：含点星的必判违规 / 有界通配的必判合规 / 转义点星的必判合规 + **2 条批 BS 新增：末尾 \$ 必判违规 / 转义反斜杠 + 行尾锚点必判合规**）⇒ 样例被删 ⇒ 自检失去证明力 ⇒ 门红'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BQ 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BQ 段门项全绿（整行锚定不许名存实亡：中间不许无界通配 ⇒ 规则自己有门）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BS · CI 里跑的断言脚本（探针们）纳入「整行锚定」适用范围 ─────────────────────
#
# ⚠⚠⚨ **本批先把洞摆出来，再修**（全部实测坐实，不是推演）：
#   ① **7 条「盯探针判定行」的门项原来是裸 `arch_need`（盯串）**
#      ⇒ 判定被掏空但串还在 ⇒ 门假绿。实测能骗过门的变异：
#        · 把 `QT_SCALE_FACTOR=2` 挪进行尾注释
#          ⇒ 「HiDPI 的效果断言」退化成 dpr=1 的空断言（**正是那条门自己声称要防的**）；
#        · 把 `--docs-lang-probe` / `--divider-probe` / `field inkWidth` / `grep -Pq`
#          挪进行尾注释 ⇒ 断言脚本「不再真的跑那个探针」也没人管；
#        · 把 `dpiEdgeLevels=legacy:` / `dpiEdgeLevels=.*aware:` 挪进行尾注释
#          ⇒ HiDPI 边缘层数断言瞎了（少一列就抓不到「dpr 感知更细腻」）。
#      ⇒ 现在改成**整行锚定的 `arch_need_count`（恰好 1 处）** ⇒ 上面每种变异都会红。
#   ② **5 条「断言清单条数门」的口径从「含标记的行」收紧成「真报错行」**
#      （`^[[:space:]]*echo "[ ]*✗`）⇒ **行尾注释里的标记不再算数**
#      ⇒ 「删一条真报错 + 在行尾注释里补一个标记」骗不过门了。
#   ③ **适用范围扩到 5 个探针脚本**（`ANCHOR_SCOPE_SUFFIXES`）
#      ⇒ 以后谁给这些脚本加「盯串」门项 ⇒ 审计器当场红（rc=8）。
#   ④ **孤儿探针自己的 3 条判定行门项**改成整行锚定。
#
# ⚠⚠⚨ **为什么「条数门」要显式豁免**（不是漏网、不是忘了）：
#   那些门项数的是**报错文案行** ⇒ 行尾是**自由文本**
#   ⇒ 整行锚定等于把每条报错文案逐字写进正则 ⇒ **语义被改窄**
#   ⇒ ⇒ **显式登记在豁免表里**（批 BN 的豁免机制：正向不豁免就红 + 反向豁免对不上就红）。
#
# ⚠⚠⚨ **本段 2 条门项守的是「批 BS 自己新加的判定不许被掏空」**：
#   批 BS 给审计器加了一条**按反斜杠奇偶数**判「末尾 $ 有没有被转义」的规则
#   ⇒ 规则被掏空 ⇒ 合法的整行锚定门项被误判成违规 ⇒ **逼人把门项写弱**（假红）。
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+if nb % 2 == 1:$' 1 '「末尾 \$ 有没有被转义」的**判定行**必须在（⚠ 末尾 \$ 前**奇数**个反斜杠 ⇒ 这个 \$ 被转义（字面美元号）⇒ 不算行尾锚点；**偶数**个 ⇒ 它是行尾锚点）｜⚠⚠⚨ **整行锚定**｜⚠⚠⚨ **批 BS：原判据按「末两字符是 \$\」⇒ 把 `\\\$` 误判成被转义 ⇒ 假红 ⇒ 逼人把门项写弱**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+while j >= 0 and rx\[j\] == .\\\\.:$' 1 '「末尾 \$ 有没有被转义」的**反斜杠计数行**必须在（⚠ 数末尾 \$ 前面连续有几个反斜杠 ⇒ 奇偶决定它是不是被转义）｜⚠⚠⚨ **整行锚定**｜⚠⚠⚨ **批 BS：源行里是两个反斜杠（源码字面量 `\\\\`）⇒ 正则里要写四个**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BS 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BS 段门项全绿（探针脚本纳入整行锚定适用范围：判定行不许被掏空）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BT · 探针脚本的「失败上报」不许被摘掉（否则断言空转 ⇒ CI 假绿）──────
#
# ⚠⚠⚨ **实测坐实的洞（行为级，不是推演）**：
#   把 `ci-platform-probe.sh` **最后一条** `✗ ` 报错后面的 `exit 1` 摘掉
#   ⇒ 喂一个「只让最后一条断言失败」的假探针
#   ⇒ **脚本 exit 0**、并且照样打印「✓ 平台探针通过」
#   ⇒ ⇒ **CI 假绿**（断言失败了，CI 报通过）
#   ⇒ 而**现有门全绿**（`✗ ` 条数门数的是 20 条报错行 ⇒ 一条没少 ⇒ 绿）
#   ⇒ ⇒ 「**探针的失败必须真的让 CI 失败**」这个承诺**从来没有门**。
#
# ⚠⚠⚨ **为什么「报错行条数」那几条门看不见它**：
#   它们数的是**报错文案行** ⇒ 报错行**还在** ⇒ 绿
#   ⇒ 而「失败上报」（`exit N` / `return 1` / `fail=1`）被摘掉 ⇒ 断言变空转
#   ⇒ ⇒ 两个门数的是**不同的东西** ⇒ 缺一个就少一道防线。
#
# ⚠⚠⚨ **本段 5 条门项数的是「失败上报语句」的条数**：
#   摘掉任何一条（或把它改成 `exit 0` / `fail=0`）⇒ 条数变少 ⇒ **必红**。
#   ⚠ 正则**整行锚定** ⇒ 审计器（批 BL/BM/BN/BR/BS 的适用范围）会查它。
arch_need_count "$SRC/scripts/ci-platform-probe.sh" '^[[:space:]]*(exit [1-9]|return 1|fail=1)$' 24 '探针脚本的**失败上报语句条数**必须恰好是 24（⚠ **摘掉任何一条失败上报（或把它改成 `exit 0` / `fail=0`）⇒ 那条断言就变空转 ⇒ 脚本仍 exit 0 ⇒ CI 假绿**）｜⚠⚠⚨ **批 BT**｜⚠ 口径：这条门数的是**整行的失败上报语句**（`exit N` / `return 1` / `fail=1`）⇒ 辅助函数的内层/外层报错、awk 程序内部的 `exit 1` 都会**多出来**⇒ **不是 1:1 配对**，只钉住**总数** ⇒ 目的：**不许把任何一条失败上报摘掉或改成 0**'
arch_need_count "$SRC/scripts/ci-docs-lang-probe.sh" '^[[:space:]]*(exit [1-9]|return 1|fail=1)$' 11 '探针脚本的**失败上报语句条数**必须恰好是 11（⚠ **摘掉任何一条失败上报（或把它改成 `exit 0` / `fail=0`）⇒ 那条断言就变空转 ⇒ 脚本仍 exit 0 ⇒ CI 假绿**）｜⚠⚠⚨ **批 BT**｜⚠ 口径：数**整行的失败上报语句**（`exit N` / `return 1` / `fail=1`）⇒ **不是与报错行 1:1 配对**，只钉**总数** ⇒ 目的：**不许把任何一条失败上报摘掉或改成 0**'
arch_need_count "$SRC/scripts/ci-divider-probe.sh" '^[[:space:]]*(exit [1-9]|return 1|fail=1)$' 10 '探针脚本的**失败上报语句条数**必须恰好是 10（⚠ **摘掉任何一条失败上报（或把它改成 `exit 0` / `fail=0`）⇒ 那条断言就变空转 ⇒ 脚本仍 exit 0 ⇒ CI 假绿**）｜⚠⚠⚨ **批 BT**｜⚠ 口径：数**整行的失败上报语句**（`exit N` / `return 1` / `fail=1`）⇒ **不是与报错行 1:1 配对**，只钉**总数** ⇒ 目的：**不许把任何一条失败上报摘掉或改成 0**'
arch_need_count "$SRC/scripts/probe-agent-tool-surface.sh" '^[[:space:]]*(exit [1-9]|return 1|fail=1)$' 13 '探针脚本的**失败上报语句条数**必须恰好是 13（⚠ **摘掉任何一条失败上报（或把它改成 `exit 0` / `fail=0`）⇒ 那条断言就变空转 ⇒ 脚本仍 exit 0 ⇒ CI 假绿**）｜⚠⚠⚨ **批 BT**｜⚠ 口径：数**整行的失败上报语句**（`exit N` / `return 1` / `fail=1`）⇒ 这个脚本用 `fail=1` 累加 + 末尾统一 `exit 1`，还有 2 条 `exit 3`（**SKIP**，也算失败）⇒ **不是与报错行 1:1 配对**，只钉**总数** ⇒ 目的：**不许把任何一条失败上报摘掉或改成 0**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^[[:space:]]*(exit [1-9]|return 1|fail=1)$' 10 '探针脚本的**失败上报语句条数**必须恰好是 10（⚠ **摘掉任何一条失败上报（或把它改成 `exit 0` / `fail=0`）⇒ 那条断言就变空转 ⇒ 脚本仍 exit 0 ⇒ CI 假绿**）｜⚠⚠⚨ **批 BT**｜⚠⚠⚨ **批 CV +1**：新增「剥注释抽取失败 ⇒ `exit 1`」那条（⚠ trap 里那句 `exit $_cv_rc` **不是整行** ⇒ 这条门数不到它）｜⚠ 口径：数**整行的失败上报语句**（`exit N` / `return 1` / `fail=1`）⇒ 这个脚本用 `fail=1` 累加 + 末尾统一 `exit 1`⇒ **不是与报错行 1:1 配对**，只钉**总数** ⇒ 目的：**不许把任何一条失败上报摘掉或改成 0**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BT 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BT 段门项全绿（探针的失败上报不许被摘掉：断言空转 ⇒ CI 假绿）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BU · helper 型断言脚本：「失败上报」与「断言清单」都要有门 ──────────────
#
# ⚠⚠⚨ **实测坐实的洞**：`build-deb.sh` / `probe-deepin-tray.sh` /
#   `probe-sni-icon.sh` 用**助手**统一报错（`die()` / `fail()`）
#   ⇒ `✗ ` 标记**只在助手体内** ⇒：
#     · 「`✗ ` 条数门」对它们**形同虚设**（数出来只有 1 ⇒ 助手在 ⇒ 绿）
#       ⇒ 删掉任意一条断言调用，门照样绿；
#     · 批 BC 承诺的「**清单不许被删**」对它们**从来没兑现过**；
#     · 助手里的 `exit 1` 被摘掉 ⇒ 所有断言变空转（同批 BT 的洞）。
#
# ⚠⚠⚨ **修法（两层）**：
#   ① **助手定义行必须整行锚定** ⇒ 助手被掏空（`exit 1` 没了）⇒ 红；
#   ② **助手调用点数必须恰好 N** ⇒ 删掉任意一条断言调用 ⇒ 红。
#
# ⚠⚠⚨ **口径为什么不能行首锚定**（实测）：助手调用常写在行中
#   （`[ -f "$BIN" ] || die "..."`）⇒ 只用 `^` 会**少数**（实测 20 → 5）
#   ⇒ 计数必须按**调用点**计（不限行首）⇒ ⚠ 强度弱于行首锚定
#   ⇒ **如实记为已知边界**（行尾注释理论上能冒充）。
arch_need_count "$SRC/scripts/build-deb.sh" '^die\(\) \{ echo "✗ build-deb: \$\*" >&2; exit 1; \}$' 1 '**helper 型脚本的失败助手定义行**必须原样存在（⚠ **整行锚定**）⇒ 助手里的 `exit 1` 被摘掉 ⇒ 所有断言**变空转**（脚本仍 exit 0 ⇒ CI 假绿）⇒ 必红｜⚠⚠⚨ **批 BU**｜die 助手定义行'
arch_need_count "$SRC/scripts/probe-deepin-tray.sh" '^fail\(\) \{ echo "✗ \$1" >&2; exit 1; \}$' 1 '**helper 型脚本的失败助手定义行**必须原样存在（⚠ **整行锚定**）⇒ 助手里的 `exit 1` 被摘掉 ⇒ 所有断言**变空转**（脚本仍 exit 0 ⇒ CI 假绿）⇒ 必红｜⚠⚠⚨ **批 BU**｜fail 助手定义行'
arch_need_count "$SRC/scripts/probe-sni-icon.sh" '^fail\(\) \{ echo "✗ \$1" >&2; exit 1; \}$' 1 '**helper 型脚本的失败助手定义行**必须原样存在（⚠ **整行锚定**）⇒ 助手里的 `exit 1` 被摘掉 ⇒ 所有断言**变空转**（脚本仍 exit 0 ⇒ CI 假绿）⇒ 必红｜⚠⚠⚨ **批 BU**｜fail 助手定义行'
arch_need_count "$SRC/scripts/build-deb.sh" '\b(die|fail) "' 23 '**helper 型脚本的断言清单不许被删** —— 助手调用点必须恰好 23 处（⚠⚠⚨ **批 CD +3**：新增 3 个**诊断增强**的 die ——① 解包失败 ② readelf 失败 ③ ldd 失败：它们不是新断言，而是**把「工具失败」从静默变成响亮失败**）（⚠ 口径：数的是**调用点**（`die "` / `fail "`），**不是 `✗ ` 标记数** —— 后者在 helper 型脚本里只有 **1**（在助手体内）⇒ 用它当清单门**形同虚设**：删掉任意一条断言调用，门照样绿）｜⚠⚠⚨ **批 BU**｜⚠ **强度弱于行首锚定**（调用点常写在行中 ⇒ 没法行首锚定）⇒ 行尾注释理论上能冒充 ⇒ **如实记为已知边界**｜⚠ 期望 == 实际 ⇒ 余量恒为 0（批 BB 口径）'
arch_need_count "$SRC/scripts/probe-deepin-tray.sh" '\b(die|fail) "' 7 '**helper 型脚本的断言清单不许被删** —— 助手调用点必须恰好 7 处（⚠ 口径：数的是**调用点**（`die "` / `fail "`），**不是 `✗ ` 标记数** —— 后者在 helper 型脚本里只有 **1**（在助手体内）⇒ 用它当清单门**形同虚设**：删掉任意一条断言调用，门照样绿）｜⚠⚠⚨ **批 BU**｜⚠ **强度弱于行首锚定**（调用点常写在行中 ⇒ 没法行首锚定）⇒ 行尾注释理论上能冒充 ⇒ **如实记为已知边界**｜⚠ 期望 == 实际 ⇒ 余量恒为 0（批 BB 口径）'
arch_need_count "$SRC/scripts/probe-sni-icon.sh" '\b(die|fail) "' 10 '**helper 型脚本的断言清单不许被删** —— 助手调用点必须恰好 10 处（⚠ 口径：数的是**调用点**（`die "` / `fail "`），**不是 `✗ ` 标记数** —— 后者在 helper 型脚本里只有 **1**（在助手体内）⇒ 用它当清单门**形同虚设**：删掉任意一条断言调用，门照样绿）｜⚠⚠⚨ **批 BU**｜⚠ **强度弱于行首锚定**（调用点常写在行中 ⇒ 没法行首锚定）⇒ 行尾注释理论上能冒充 ⇒ **如实记为已知边界**｜⚠ 期望 == 实际 ⇒ 余量恒为 0（批 BB 口径）'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BU 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BU 段门项全绿（helper 型断言脚本：失败助手定义行 + 断言清单都要有门）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BV · 无头路径的收尾：「退出时 QApplication 必须还活着」——CI 偶发段错误的真身 ──
#
# ⚠⚠⚨ **取证坐实的洞（core 解析 + 反汇编，不是推演）**：
#   CI 偶发段错误（退出码 139）的 core 解析结果：
#     · 崩溃线程 = **`QDBusConnection` 线程**（探针进程正好 3 个线程：
#       deepDolphin / QDBusConnection / DConfigGlobalTh，与 core 里的 3 个 NT_PRSTATUS
#       一一对应；崩溃那个线程的栈上有 `QEventLoop::exec` ⇒ 是个跑事件循环的线程）；
#     · 崩点 rip = libQt6Core 的 `QCoreApplication::notifyInternal2`，
#       故障指令 `mov (%rdi),%rax`，**rdi = 0**；
#     · 反汇编逐条对上：
#         `159d91 lea ...,%rbp`      （rbp = &QCoreApplication::self）
#         `159d98 cmpq $0x0,0x0(%rbp)`（**第一次读 self：非空 ⇒ 通过**）
#         `159dc3 call QInternal::activateCallbacks`（**这里主线程把 self 置空**）
#         `159de1 mov 0x0(%rbp),%rdi`  （**第二次读 self：已是 NULL**）
#         `159dec mov (%rdi),%rax`     （**崩：解引用 NULL**）
#     · 而 `QCoreApplication::~QCoreApplication()` 里 `15beee: movq $0x0,(%rax)`
#       写的**正是** `QCoreApplication::self` ⇒ **析构 QApplication 会把 self 置空**。
#   ⇒ 根因：**主线程析构 QApplication 的同时，后台线程正在派发事件** ⇒ 空指针解引用。
#   ⇒ 而探针的收尾**正好**在 app 作用域之外（`::_exit` 写在 `}` 之后）⇒ 竞态窗口就在那里。
#
# ⚠⚠⚨ **修法（两层）**：
#   ① **产品侧**：所有无头路径统一走 `probeExit()` —— 它在**退出那一刻**报
#      `appAlive=<0|1>` 再 `_exit` ⇒ **退出时 QApplication 还活着**（app 永不析构）。
#   ② **CI 侧**：三个探针脚本**各断言** `appAlive=1` ⇒ 那个竞态**从「偶发」变成「必红」**
#      （退出点一旦被挪出 app 作用域 ⇒ 事实变 0 ⇒ 门立刻红）。
#
# ⚠⚠⚨ **为什么事实必须由 `probeExit` 在退出点求值**：
#   若把 `appAlive` 的求值挪到别处 ⇒ 它就不再反映「退出时 app 还在不在」
#   ⇒ 断言变成空门（判定被搬走但串还在 —— 批 BQ/BL 反复治的那一类洞）。
arch_need_count "$SRC/scripts/ci-platform-probe.sh" '^if \[ "\$APP_ALIVE" != "1" \]; then$' 2 '平台探针的**两跳**都必须断言「退出时 QApplication 还活着」（事实行 appAlive）｜⚠⚠⚨ **批 BV**｜⚠ **整行锚定**（批 BS：整行锚定 ⇒ 判定行被追加内容/挪走时门会红）｜⚠ 少一趟（dpr=2 那趟）⇒ 那个竞态在缩放档位下就没人管了'
arch_need_count "$SRC/scripts/ci-docs-lang-probe.sh" '^if \[ "\$APP_ALIVE" != "1" \]; then$' 1 '文档语言探针必须断言「退出时 QApplication 还活着」（事实行 appAlive）｜⚠⚠⚨ **批 BV**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-divider-probe.sh" '^if \[ "\$APP_ALIVE" != "1" \]; then$' 1 '分隔线探针必须断言「退出时 QApplication 还活着」（事实行 appAlive）｜⚠⚠⚨ **批 BV**｜⚠ **整行锚定**'
arch_need_count "$SRC/src/main.cpp" 'appAlive=%d' 1 '「退出时 QApplication 还活着」这个**事实**不许被删（它是批 BV 那条竞态的**唯一可见面**）｜⚠⚠⚨ **批 BV**｜⚠ 口径：`strip_comments` 剥注释 ⇒ 注释里写一遍不算数（批 BK 纪律）'
arch_need_count "$SRC/src/main.cpp" '::_exit\(rc\);' 1 '`_exit` **只许出现在 `probeExit` 里**（1 处）｜⚠⚠⚨ **批 BV**｜⚠ 散落的 `_exit` 就是「退出点被挪到别处」的入口 ⇒ 一律收口到 probeExit（那儿才有 appAlive 事实）'
arch_need_count "$SRC/src/main.cpp" 'probeExit\(' 11 '无头路径的收尾**必须走 `probeExit`**（11 = 1 处定义 + 10 个调用点：快照 / 色样张 / 平台探针 / 文档语言探针 ×2 / 分隔线探针 ×2 / 工具面探针 ×3）｜⚠⚠⚨ **批 BV**｜⚠ 走别的出口 = 没有 appAlive 事实 = 那个竞态没人看得见'
arch_forbid "$SRC/scripts/ci-platform-probe.sh" '2>/dev/null' '平台探针的**stderr 不许被扔掉**（探针崩了时 CrashHandler 的栈回溯（崩点）全在 stderr 里 ⇒ 扔掉 = CI 只剩一句「退出码 139」，**没人知道崩在哪**）｜⚠⚠⚨ **批 BV**｜⚠ 口径：`strip_comments` 剥注释 ⇒ 注释里提一嘴不算'
arch_forbid "$SRC/scripts/ci-docs-lang-probe.sh" '2>/dev/null' '文档语言探针的**stderr 不许被扔掉**（崩点会因此看不见）｜⚠⚠⚨ **批 BV**｜⚠ 口径：`strip_comments` 剥注释 ⇒ 注释里提一嘴不算'
arch_forbid "$SRC/scripts/ci-divider-probe.sh" '2>/dev/null' '分隔线探针的**stderr 不许被扔掉**（崩点会因此看不见）｜⚠⚠⚨ **批 BV**｜⚠ 口径：`strip_comments` 剥注释 ⇒ 注释里提一嘴不算'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BV 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BV 段门项全绿（无头路径的收尾：退出时 QApplication 必须还活着 + 崩点不许被吞）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BW · 「探针崩了」不许被当成「未验证」（SKIP） ─────────────────────
#
# ⚠⚠⚨ **起因（批 BV 留下的已知边界）**：批 BV 把「崩点不许被吞」做进了三个探针脚本
#   ⇒ 但 `probe-agent-tool-surface.sh` 当时**没收** ⇒ 顺手查了一遍，发现**更糟**：
#   它的探针调用**根本没接退出码**：
#       OUT="$(... --agent-tool-surface 2>/dev/null)"
#       if [ -z "$OUT" ]; then echo "SKIP: 引擎未找到…"; exit 3; fi
#   ⇒ **只看 stdout 空不空** ⇒ 于是：
#     · 探针**崩了**（139）⇒ stdout 空 ⇒ 报「SKIP: 引擎未找到」⇒ exit 3
#     · 探针**报成功但没输出**⇒ stdout 空 ⇒ 同样 SKIP
#   ⇒ ci.sh 第 13 步看到 exit 3 ⇒ 打印「‣ SKIP …未验证」⇒ **CI 整体照样绿**
#   ⇒ ⇒ 「**崩了**」被伪装成「**环境不具备**」⇒ 崩点彻底看不见。
#
# ⚠⚠⚨ **修法（三层）**：
#   ① **产品侧**：「引擎未找到」用**专属退出码 3**（= 未验证），
#      其它失败用 1 ⇒ 「未验证」与「失败」在**退出码**这一层就分开了；
#   ② **CI 侧**：脚本**接住退出码**并分诊（3 = SKIP / 其它非 0 = **失败**），
#      且 stderr **落盘并在失败时原样吐出** ⇒ 崩点（CrashHandler 的栈回溯）看得见；
#   ③ **顺带**：工具面探针的收尾也收口到 `probeExit`（批 BV 的口径）⇒
#      「所有无头路径统一走 probeExit」这句话**这才真的成立**。
#
# ⚠⚠⚨ **实测（行为级，假探针）**：
#   ① 假探针 `kill -SEGV $$`（退出码 139）⇒ 脚本 **exit 1（失败）**且把 stderr 吐出来
#      ⇒ **以前是 exit 3（SKIP）⇒ CI 假绿**；
#   ② 假探针 `exit 3`（引擎未找到）⇒ 脚本 **exit 3（SKIP）** ⇒ 语义**没变**；
#   ③ 假探针 `exit 0` 但无输出 ⇒ 脚本 **exit 1**（假绿被抓住）。
arch_need_count "$SRC/scripts/probe-agent-tool-surface.sh" '^OUT="\$\(QT_QPA_PLATFORM=offscreen "\$BIN" --agent-tool-surface 2>"\$ERR_FILE"\)" \|\| PROBE_RC=\$\?$' 1 '工具面探针的**退出码必须被接住**（`|| PROBE_RC=$?`）且 stderr **落盘**（不许扔掉）｜⚠⚠⚨ **批 BW**｜⚠ **整行锚定**（批 BS：整行锚定 ⇒ 判定行被追加内容/挪走时门会红）｜⚠ 不接退出码 ⇒ 探针崩了（139）与「引擎没找到」被当成同一件事 ⇒ 崩了 ⇒ SKIP ⇒ **CI 假绿**'
arch_need_count "$SRC/scripts/probe-agent-tool-surface.sh" '^if \[ "\$PROBE_RC" -eq 3 \]; then$' 1 '「**未验证**」（引擎缺席）必须单列成 SKIP 这一支｜⚠⚠⚨ **批 BW**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/probe-agent-tool-surface.sh" '^if \[ "\$PROBE_RC" -ne 0 \]; then$' 1 '**其它非 0 退出码必须判「失败」**（不许混进 SKIP 那一支）｜⚠⚠⚨ **批 BW**｜⚠ **整行锚定**｜⚠ 这一支才是「崩了」的归宿'
arch_need_count "$SRC/scripts/probe-agent-tool-surface.sh" '^[[:space:]]*echo "✗ 工具面探针退出码 0 [^"]*" >&2$' 1 '探针**退出码 0 却什么都没报** ⇒ 必须判**失败**（否则这一门会被当成 SKIP 放过去 ⇒ 假绿）｜⚠⚠⚨ **批 BW**｜⚠ **整行锚定**'
arch_need_count "$SRC/src/main.cpp" 'probeExit\(3\);' 1 '「引擎未找到」必须用**专属的『未验证』退出码 3**（与「失败（1）」分开）｜⚠⚠⚨ **批 BW**｜⚠ 口径：`strip_comments` 剥注释 ⇒ 注释里写一遍不算数'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BW 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BW 段门项全绿（探针崩了不许被当成 SKIP：退出码分诊 + 崩点落地）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BX · 「崩了」必须被判成「崩了」：退出码不许被吞、stderr 不许顶替 stdout ──
#
# ⚠⚠⚨ **起因**：批 BW 标了「其余断言脚本还没逐个查」⇒ 本批**逐个盘点**了
#   `scripts/` 下全部 16 个断言脚本对「我们自己的二进制 / 探针脚本」的调用
#   ⇒ 盘出两处**具体**的洞（不是印象，是逐行看的）：
#
# ⚠⚠⚨ **洞 ①（行为级·假绿）**：`check-deb-layout.sh` ⑧「空环境下能跑 --version」
#   原来是：
#       VOUT="$(env -i "$BIN" --version 2>&1 | head -3)"
#       if printf '%s' "$VOUT" | grep -q .; then ok "能跑起来"; else no "…"; fi
#   ⇒ **退出码完全没查** + **stderr 被 `2>&1` 合并进 stdout** + 判据只是「有输出」
#   ⇒ **实测**：造一个「先往 stderr 打一行警告、再 `kill -SEGV` 崩掉」的假二进制
#   ⇒ 这一门判 **✓ 可执行在空环境下能跑起来** ⇒ **假绿**。
#
# ⚠⚠⚨ **洞 ②（形态级·诊断失真）**：`ci-platform-probe.sh` 的 dpr=2 那跳用
#   「**下一行**再取 `$?`」的形态 ⇒ `$?` 只对**紧邻的上一条**命令有效
#   ⇒ 中间插一行 ⇒ 退出码被换成别人的 ⇒ 崩溃被伪装成「探针没输出」⇒ 诊断失真。
#
# ⚠⚠⚨ **修法**：
#   ① `check-deb-layout.sh` ⑧：**查退出码**（非 0 ⇒ 判失败）+ **stderr 不混进 stdout**
#      （stdout 单独取，stderr 原样透出 ⇒ 崩点看得见）；
#   ② `ci-platform-probe.sh`：**退出码改成同行取**（`|| VAR=$?`）⇒ 形态固定，
#      插一行也断不了（批 BV 已在另外三跳用同一形态）。
arch_need_count "$SRC/scripts/check-deb-layout.sh" '^[[:space:]]*VOUT="\$\(env -i "\$BIN" --version\)" \|\| VRC=\$\?$' 1 'deb 布局验收的「空环境下能跑 --version」**必须查退出码**，且 **stderr 不许混进 stdout**｜⚠⚠⚨ **批 BX**｜⚠ **整行锚定**（这一条同时排除掉 `2>&1` 那种写法）｜⚠⚠⚨ **实测的洞**：以前 `2>&1` + 只判「有输出」⇒ 一个「先打警告再段错误」的二进制也能过这一门（判 ✓ 能跑起来）⇒ **假绿**'
arch_need_count "$SRC/scripts/check-deb-layout.sh" '^[[:space:]]*if \[ "\$VRC" -ne 0 \]; then$' 1 '「--version 退出码非 0」必须**判失败**（崩了也走这一支 ⇒ 不许再落回「有输出就算过」）｜⚠⚠⚨ **批 BX**｜⚠ **整行锚定**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BX 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BX 段门项全绿（崩了必须被判成崩了：退出码不许被吞、stderr 不许顶替 stdout）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BY · 「失败计数不许被掏空」：计数器型断言脚本的 fail 计数必须真的有门 ──
#
# ⚠⚠⚨ **起因（实测盘点，不是印象）**：批 BT/BU 把「失败上报」的门型收进了
#   `exit N` 形态的脚本 ⇒ **计数器型**（`fail=$((fail+1))` + 末尾 `[ "$fail" -eq 0 ]`）
#   的脚本**从来没被收过**。
#   ⇒ 本批**逐个盘点了 `scripts/` 下全部脚本**的失败上报形态 ⇒
#       **全仓只有 2 个脚本是计数器型**：
#         · `check-deb-layout.sh`（1 处计数：唯一的 `no()` 助手）
#         · `contract-check.sh`（39 处计数：2 个助手 + 37 处行内）
#       其余脚本全是 `exit N` 形态（批 BT/BU 已收）⇒ **本批一次收干净**。
#
# ⚠⚠⚨ **洞（行为级·假绿）**：计数器型脚本的失败判定链是三环：
#       ① 报错（`echo "  ✗ …"`）⇒ ② 计数（`fail=$((fail+1))`）
#       ⇒ ③ 末尾判定（`[ "$fail" -eq 0 ]` 决定退出码）
#   ⇒ **中间那一环被摘掉**（`fail=$((fail+1))` 被删 / 改成 `fail=$((fail+2))` /
#   换成别的写法 / 判定之前被 `fail=0` **复位**）⇒
#       **报错照打**（stderr 里明明写着「✗」）但**永远不计数**
#   ⇒ 末尾判定恒真 ⇒ 脚本 exit 0 ⇒ **CI 假绿**。
#   ⚠⚠⚨ 「**复位**」这一条尤其阴：计数**一条不少** ⇒ 任何「数计数点」的门都抓不到
#   ⇒ 必须另有一条「**写 fail 的行数**」的门（见本段第 4 / 7 条）。
#
# ⚠⚠⚨ **修法（本批只动判据层 ⇒ 零产品代码改动）**：
#   ① 两个计数器型脚本的**失败计数点 / 成功计数点 / 末尾判定行**逐条**整行锚定**；
#   ② 计数点按**形态**分组钉住（助手行 / 独立成行 / 带 >&2 的自由文案 /
#      `|| { …; }` 形态）⇒ 「删一处 + 补一处同形态」也躲不过（**总数不变也红**）；
#   ③ 加「**写 fail 的行数**」门 ⇒ 「判定前把计数器复位」也红；
#   ④ 两个脚本**纳入审计器的「整行锚定」适用范围** ⇒ 将来这些门被写弱
#      （从整行锚定改回盯串）审计器就会红（收掉批 BX 遗留的已知边界）。
#
# ⚠⚠⚨ **口径如实记录（不是缺陷，是取舍）**：
#   · 「写 fail 的行数」是**行数**口径 ⇒ 一行里写两次 `fail=` 只算 1 行
#     ⇒ 但「增量行数」那条门数的是**行数**、形态分组门数的是**行数** ⇒ 三者口径一致；
#   · 计数点**总数**（39）这一条是**不许增不许减**的基线 ⇒ 将来合法新增一条断言
#     ⇒ 必须同步更新期望值（与本仓其它条数基线门同规矩，批 BB 口径）。
arch_need_count "$SRC/scripts/check-deb-layout.sh" '^no\(\) \{ echo "  ✗ \$1" >&2; fail=\$\(\(fail\+1\)\); \}$' 1 'deb 布局验收的**失败计数点本体**必须**整行锚定**（`no()` 助手的定义行 ⇒ 摘掉 `fail=$((fail+1))` ⇒ 报错照打但永远不计数 ⇒ 末尾判定恒真 ⇒ 假绿）｜⚠⚠⚨ **批 BY**｜⚠ **整行锚定**｜⚠ 口径：全仓 `check-deb-layout.sh` 只有这 1 处失败计数点'
arch_need_count "$SRC/scripts/check-deb-layout.sh" '^ok\(\) \{ echo "  ✓ \$1"; pass=\$\(\(pass\+1\)\); \}$' 1 'deb 布局验收的**成功计数点本体**也必须**整行锚定**（与失败计数点对称 ⇒ 成功/失败两侧都不许被掏空）｜⚠⚠⚨ **批 BY**｜⚠ **整行锚定**｜⚠ 口径：全仓 `check-deb-layout.sh` 只有这 1 处成功计数点'
arch_need_count "$SRC/scripts/check-deb-layout.sh" '^\[ "\$fail" -eq 0 \]$' 1 'deb 布局验收的**末尾判定行**必须**整行锚定**（这一行决定退出码 ⇒ 改成判 `pass` / 判 `-le` / 换成别的变量 ⇒ 脚本 exit 0 ⇒ 假绿）｜⚠⚠⚨ **批 BY**｜⚠ **整行锚定**｜⚠ 口径：`check-deb-layout.sh` 全文只有这 1 处这样的末尾判定'
arch_need_count "$SRC/scripts/check-deb-layout.sh" '^[^#]*\bfail=[^#]*$' 2 'deb 布局验收里**写 `fail` 变量的行恰好 2 行**（1 处初始化 + 1 处计数）⇒ 「判定前把计数器 `fail=0` **复位**」会多出第 3 行 ⇒ 必红（⚠ **复位这一类洞任何「数计数点」的门都抓不到** —— 计数一条不少，只是被清零了）｜⚠⚠⚨ **批 BY**｜⚠ **整行锚定**｜⚠ 口径：行数（不是出现次数）⇒ 一行里写两次 `fail=` 只算 1 行'
arch_need_count "$SRC/scripts/check-deb-layout.sh" '^[^#]*fail=\$\(\(fail\+1\)\)(; \})?$' 1 'deb 布局验收的**失败计数增量行恰好 1 行** ⇒ 删掉 / 改写 / 新增任何一处计数点都红（⚠ 这条与「写 fail 的行数」**互补**：前者盯**增量**的写法，后者盯**写**的总面）｜⚠⚠⚨ **批 BY**｜⚠ **整行锚定**｜⚠ 口径：行数；允许行尾是 `; }`（`no()` 定义行就是这个形态）'
arch_need_count "$SRC/scripts/contract-check.sh" '^[[:space:]]+echo "  ✗ \$name"; fail=\$\(\(fail\+1\)\)$' 2 '契约门**两个断言助手**（`check()` / `check_text()`）的**失败计数行**必须**整行锚定**且**恰好 2 行** ⇒ 93 处 `check` 调用与全部 `check_text` 调用的失败都靠这一行计数 ⇒ 摘掉 ⇒ 报错照打但永远不计数 ⇒ 末尾判定恒真 ⇒ 假绿｜⚠⚠⚨ **批 BY**｜⚠ **整行锚定**｜⚠ 口径：两个助手各 1 行 ⇒ 恰好 2'
arch_need_count "$SRC/scripts/contract-check.sh" '^[[:space:]]+fail=\$\(\(fail\+1\)\)$' 31 '契约门**独立成行**的失败计数点恰好 31 行 ⇒ 这 31 处都是「报错在上一行、计数在下一行」的形态 ⇒ 逐行钉住形态（⚠ 与「总数」那条**互补**：删一处 + 补一处同形态 ⇒ 总数不变，但**这条会红**）｜⚠⚠⚨ **批 BY**｜⚠ **整行锚定**｜⚠ 口径：31 = 39 处计数点里「独立成行」的那部分'
arch_need_count "$SRC/scripts/contract-check.sh" '^[[:space:]]+echo "  ✗ [^"]*" >&2; fail=\$\(\(fail\+1\)\)$' 4 '契约门**报错与计数同行**（`echo "  ✗ …" >&2; fail=$((fail+1))`）的失败计数点恰好 4 行 ⇒ 这一形态（自由文案 + >&2）逐行钉住 ⇒ 摘掉计数只留报错 ⇒ 假绿｜⚠⚠⚨ **批 BY**｜⚠ **整行锚定**｜⚠ 口径：报错文案是自由文本 ⇒ 用 `[^"]*` 有界通配钉住结构（不把文案逐字写进正则）'
arch_need_count "$SRC/scripts/contract-check.sh" '^[[:space:]]*\|\| \{ echo "  ✗ [^"]*"; fail=\$\(\(fail\+1\)\); \}$' 2 '契约门**短路形态**（`|| { echo "  ✗ …"; fail=$((fail+1)); }`）的失败计数点恰好 2 行 ⇒ 这一形态逐行钉住 ⇒ 摘掉计数 ⇒ 假绿｜⚠⚠⚨ **批 BY**｜⚠ **整行锚定**｜⚠ 口径：报错文案是自由文本 ⇒ 用 `[^"]*` 有界通配钉住结构'
arch_need_count "$SRC/scripts/contract-check.sh" '^[^#]*fail=\$\(\(fail\+1\)\)(; \})?$' 39 '契约门的**失败计数增量行恰好 39 行** ⇒ 删一处 / 改写一处 / 新增一处（任何形态）都红（⚠ **恰好 = 不许增不许减**：将来合法新增一条失败路径必须同步更新期望值）｜⚠⚠⚨ **批 BY**｜⚠ **整行锚定**｜⚠ 口径：39 = 2（两个助手）+ 31（独立成行）+ 4（同行 >&2）+ 2（`|| { }`）'
arch_need_count "$SRC/scripts/contract-check.sh" '^\[ "\$fail" -eq 0 \]$' 1 '契约门的**末尾判定行**必须**整行锚定**（这一行决定退出码 ⇒ 改成判 `pass` / 判 `-le` ⇒ 120 条断言挂了脚本也 exit 0 ⇒ 假绿）｜⚠⚠⚨ **批 BY**｜⚠ **整行锚定**｜⚠ 口径：`contract-check.sh` 全文只有这 1 处这样的末尾判定'
arch_need_count "$SRC/scripts/contract-check.sh" '^[^#]*\bfail=[^#]*$' 40 '契约门里**写 `fail` 变量的行恰好 40 行**（1 处初始化 + 39 处计数）⇒ 「判定前把计数器 `fail=0` **复位**」会多出第 41 行 ⇒ 必红（⚠ **复位这一类洞任何「数计数点」的门都抓不到** —— 计数一条不少，只是被清零了）｜⚠⚠⚨ **批 BY**｜⚠ **整行锚定**｜⚠ 口径：行数（不是出现次数）'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BY 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BY 段门项全绿（失败计数不许被掏空：计数点/判定行逐条整行锚定 + 写 fail 的行数基线 ⇒ 摘计数 / 复位计数都必红）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 BZ · 「新增失败路径必须带计数」：报错行数 == 计数行数（配对门）──
#
# ⚠⚠⚨ **起因（批 BY 明确记下的洞，不是推演）**：批 BY 给计数器型脚本的
#   「失败计数点 / 末尾判定行」都落了整行锚定的门，**但有一类洞它抓不到**：
#
# ⚠⚠⚨ **洞**：批 BY 的门保证「**已有的**计数点不被摘、不被复位」，
#   ⇒ 但**新增**一条失败路径时，如果新代码只写了
#       echo "  ✗ …" >&2        ← 报错（照打）
#       （忘了 fail=$((fail+1))） ← 计数（漏了）
#   ⇒ 末尾判定 `[ "$fail" -eq 0 ]` **看不到**这条失败
#   ⇒ 脚本 exit 0 ⇒ **CI 假绿**。
#
# ⚠⚠⚨ **为什么两条独立的「恰好 N 次」门抓不到它**：
#   「报错行数 == 39」与「计数行数 == 39」是**两个互不知情**的门
#   ⇒ 新增一条**不带计数**的报错行 ⇒ 报错门红（40 ≠ 39）、计数门绿（39 == 39）
#   ⇒ 人把**报错门**的期望值改成 40 ⇒ 两门都绿
#   ⇒ 但那条新报错**永远不计数** ⇒ **假绿**。
#   ⇒ 必须有**一条**门**同时**盯住两个数 ⇒ 它们的**差恒为 0**。
#
# ⚠⚠⚨ **本批做法**：新增**门型** `arch_need_count_pair`（批 AR/AV 纪律：
#   **新门型必须进审计覆盖** ⇒ 解析 + 门型对拍登记 + 期望校准，三处都做）。
#
# ⚠⚠⚨ **口径**：
#   · 数的是**行数**（`grep -cE`）⇒ 一行里写两次只算 1 行；
#   · 报错行用 `echo "  ✗`（**两格缩进**）⇒ `exit N` 形态的报错行
#     （`echo "✗ …"`，无缩进）**自然被排除** ⇒ 只盯**计数器型**的失败路径；
#   · 期望值是**不许增不许减**的基线（批 BB 口径）。
arch_need_count_pair "$SRC/scripts/check-deb-layout.sh" 'echo "  ✗' 'fail=\$\(\(fail\+1\)\)' 1 'deb 布局验收的**报错行数必须等于失败计数行数**（且都恰好 1）｜⚠⚠⚨ **批 CS**：审计器侧**逐段**核对 ⇒ 每段**恰好 1 处**计数 ⇒ 「总数相等但逐条不对」也红⇒ 「新增一条**只报错不计数**的失败路径」⇒ 报错行 +1 而计数行不变 ⇒ **差 ≠ 0** ⇒ 必红（末尾判定恒真 ⇒ 假绿）｜⚠⚠⚨ **批 BZ**｜⚠ 口径：**行数**（不是出现次数）｜⚠ 缩进差异把 `exit N` 形态的报错行（`echo "✗ …"`，无两格缩进）**自然排除**在外 ⇒ 只盯**计数器型**的失败路径'
arch_need_count_pair "$SRC/scripts/contract-check.sh" 'echo "  ✗' 'fail=\$\(\(fail\+1\)\)' 39 '契约门的**报错行数必须等于失败计数行数**（且都恰好 39）｜⚠⚠⚨ **批 CS**：审计器侧**逐段**核对 ⇒ 每段**恰好 1 处**计数 ⇒ 「总数相等但逐条不对」也红⇒ 「新增一条**只报错不计数**的失败路径」⇒ 报错行 +1 而计数行不变 ⇒ **差 ≠ 0** ⇒ 必红（末尾判定恒真 ⇒ 假绿）｜⚠⚠⚨ **批 BZ**｜⚠ 口径：**行数**｜⚠ 缩进差异把 `exit N` 形态的报错行（`echo "✗ …"`，无两格缩进）**自然排除**在外 ⇒ 只盯**计数器型**的失败路径'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 BZ 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 BZ 段门项全绿（新增失败路径必须带计数：报错行数 == 计数行数 ⇒ 差恒为 0）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CA · 「失败上报出口」不许被摘掉：判据层与 CI 自己的出口都要有门 ──
#
# ⚠⚠⚨ **起因（实测盘点，不是印象）**：批 BT 收了 5 个探针脚本、批 BU 收了 3 个
#   helper 型脚本、批 BY/BZ 收了 2 个计数器型脚本 ⇒ **但「失败上报出口」这个
#   承诺本身**（脚本失败时**必须真的报出去**，不许被摘掉、不许 fall through 到 0）
#   **从来没在「判据层与 CI 自己身上**收过。
#
# ⚠⚠⚨ **洞 ①（行为级·假绿·旗舰）**：`ci-wiring-audit.py` 的**退出码契约**没人守
#   ⇒ 它是**判据层的裁判** ⇒ 它的每个失败出口都是「某一类判据失配 ⇒ 必须红」的
#   唯一通路。
#   ⇒ 实测：把 `return 4`（「次数门没配准 ⇒ rc=4」）**整行摘掉**
#   ⇒ 再让某条次数门的期望值失准 ⇒ 审计器**不再报 4**
#   ⇒ 而是 fall through 到 `return 3 if outside else 0` ⇒ `outside` 为空
#   ⇒ **rc=0** ⇒ **审计器对失准的门项报「全绿」** ⇒ **假绿坐实**。
#
# ⚠⚠⚨ **洞 ②（行为级·假绿·实测）**：`ci-d2.sh` 的**最终判定**那一行
#   `if [ "$FAIL" != "0" ]; then exit 1; fi`
#   ⇒ 摘掉那个 `exit 1` ⇒ 脚本**明明已经检出失败**（打印了「✗ 豁免路径不存在」）
#   ⇒ 却照样打印「✓ D2 命中 0/0（存量已清零，DS 单一真相源）」并 **exit 0**
#   ⇒ **假绿坐实**（一个**失败的门自己说「✓」**）。
#
# ⚠⚠⚨ **洞 ③（形态级）**：`ci.sh` 的失败**已经被 `if` 分支消化**了
#   （`set -e` 救不了：失败命令的退出码被 `if` 的条件消费掉了）
#   ⇒ 只剩那些**显式 `exit 1`** 兜底
#   ⇒ 摘掉一个 ⇒ 那一步的失败**不再中止 CI** ⇒ CI 继续往下跑 ⇒ 假绿。
#
# ⚠⚠⚨ **修法（本批只动判据层 ⇒ 零产品代码改动）**：
#   ① 每个脚本的**失败出口**逐个钉住（整行锚定）—— ⚠⚠⚨ **批 CC 已把「非 0 的总数」改成「按码值分桶」**（改一个码值 ⇒ 旧桶 -1 + 新桶 +1 ⇒ 两条都红）；
#   ② 审计器额外钉「成功出口条数」⇒ 与「失败出口条数」**合看**：
#      任何一个失败出口被改成 `return 0` ⇒ 失败出口掉 1、成功出口涨 1
#      ⇒ **两条都红**；
#   ③ 三个 `.py` 的**入口行**（`sys.exit(main())`）单独钉住
#      ⇒ 入口被摘 ⇒ `main()` 的返回值被丢弃 ⇒ **rc 恒 0** ⇒ 工具永远绿；
#   ④ `ci-d2.sh` / `smoke.sh` / `bootstrap-deps.py` **纳入**审计器的
#      「整行锚定」适用范围 ⇒ 将来这些门被写弱审计器就会红
#      （这 3 个文件在范围内**没有**非锚定门项 ⇒ **豁免表不变**）。
#
# ⚠⚠⚨ **口径（如实记着）**：
#   · 「失败出口」= **整行**的 `exit <非0数字>` / `return <非0数字>`
#     ⇒ **行内**形态（如 `|| { …; exit 1; }` / `|| exit 1`）**数不到**
#     ⇒ `smoke.sh` 的两处行内失败上报**单钉**（否则它们没门）；
#   · 「失败出口被改成**另一个非 0 码**」⇒ 出口数不变 ⇒ 这两条门**抓不到**
#     ⇒ 抓得到的是**诊断不失真**（另一条门盯具体码值）或**下一批**。
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s*return 2$' 4 '审计器的 **rc=2**（盲区 / 豁免基线不在）**前置早退**出口必须恰好 4 处（⚠⚠⚨ **批 CQ**：硬门模式改成「**收集失败态、一次报全**」⇒ 这 4 处**仍然是早退**（源文件读不了 / git diff 拿不到 / 跨文件命中数算不出来 ⇒ **后面不可信** ⇒ 必须早退）⇒ 另 3 处（盲区 / 豁免基线不在 / 审计器自己有盲区）已改成 `FAILS.append(2)` ⇒ **见下一条**）｜⚠⚠⚨ **批 CA 原地替换 + 批 CC 分桶**｜⚠ **整行锚定**｜⚠⚠⚨ **批 CQ**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s*return FAILS\[0\] if FAILS else \(3 if outside else 0\)$' 1 '审计器的**「统一出口」**（`return FAILS[0] if FAILS else (3 if outside else 0)`）必须恰好 1 处（⚠⚠⚨ **批 CQ**：改成「**收集失败态、一次报全**」⇒ 这里取**最先失败**的那个 rc（⇒ **码值语义不变** ⇒ 门侧按 rc 分诊的文案表零改动）⇒ 差别只在「**其余失败也一并报出来**」；⚠ rc=3（豁免之外）仍只从这一行出）｜⚠⚠⚨ **批 CA**｜⚠ **整行锚定**｜⚠⚠⚨ **批 CQ**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s*return 0$' 3 '审计器的**成功出口**（`return 0`）必须恰好 3 处｜⚠⚠⚨ **批 CA**｜⚠ **整行锚定**｜⚠ **与失败出口合看**：失败出口现在分**两个家族** —— ① `return N`（**前置**早退 4 处 + 统一出口 1 处 = 5 处）② `FAILS.append(N)`（**收集**，15 处）⇒ 两族合看**失败出口共 20 处**（⚠ 批 CQ 改后实测：15 处顺序早退里 11 处改成收集 ⇒ 16 → 5）⇒ 任何一个失败出口被改成 `return 0` ⇒ 成功出口涨 1 ⇒ **这条门红**｜⚠⚠⚨ **批 CQ**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^    sys\.exit\(main\(\)\)$' 1 '审计器的**入口**必须把 `main()` 的返回值交给 `sys.exit`（否则返回值被丢弃 ⇒ rc 恒 0 ⇒ 审计器**永远绿**）｜⚠⚠⚨ **批 CA**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci.sh" '^[[:space:]]*exit [1-9]$' 38 'CI 入口的**失败上报**（整行的 `exit N`）必须恰好 38 处｜⚠⚠⚨ **批 CA**｜⚠ **整行锚定**｜⚠⚠⚨ `ci.sh` 的失败**已经被 `if` 分支消化**（`set -e` 救不了：失败命令的退出码被 `if` 的条件消费掉了）⇒ 只剩这些显式 `exit 1` 兜底 ⇒ 摘掉一个 ⇒ 那一步的失败**不再中止 CI** ⇒ 假绿｜⚠⚠⚨ **批 CU**：第 3 步两处校验的失败出口**新增 2 处**（接住退出码 ⇒ 失败即判红）⇒ 34 → 36'
arch_need_count "$SRC/scripts/ci-d2.sh" '^[[:space:]]*exit [1-9]$' 6 'D2 散值门的**失败上报**（整行的 `exit N`）必须恰好 6 处｜⚠⚠⚨ **批 CA**｜⚠ **整行锚定**｜⚠⚠⚨ **实测的洞**：摘掉最终判定那一行 ⇒ 脚本明明已检出「✗ 豁免路径不存在」却照样打印「✓ D2 命中 0/0」并 **exit 0** ⇒ **假绿坐实**'
arch_need_count "$SRC/scripts/smoke.sh" '^\[ -x "\$BIN" \] \|\| \{ echo "✗ [^"]*"; exit 1; \}$' 1 '冒烟脚本「产物缺失」那一支的失败上报（**行内**形态 `|| { …; exit 1; }`）必须**整行锚定**｜⚠⚠⚨ **批 CA**｜⚠ 这一条是**行内**形态 ⇒ 不会被「整行的 `exit N`」那条门数到 ⇒ 必须单钉'
arch_need_count "$SRC/scripts/smoke.sh" '^[[:space:]]*exit [1-9]$' 3 '冒烟脚本**整行**的失败上报（`exit N`）必须恰好 3 处（selfcheck 失败 / **契约门未验证 ⇒ 原样传出**（8 缩进）/ **引擎缺席 ⇒ 未验证**（4 缩进））｜⚠⚠⚨ **批 CA**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/smoke.sh" '^[[:space:]]*bash "\$SRC/scripts/contract-check\.sh" \|\| _cc_rc=\$\?$' 1 '冒烟脚本调用契约门那一行**必须接住退出码**（`|| _cc_rc=$?`）⇒ ⚠⚠⚨ 以前是 `|| exit 1` ⇒ 契约门报「未验证」(**3**) 时**被压成 1（失败）**⇒ ⚠⚠⚨ **退出码的码值语义被顶替**（批 CC 纪律）⇒ 调用方**分不出**「根本没验过」与「验了但没过」（⚠⚠⚨ 批 CL）｜⚠ **整行锚定**（形态变了 ⇒ **原地替换**、不增行，批 BM）'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s*return [1-9]$' 3 '恒真探针的**失败退出码出口**（整行的 `return <非0数字>`）必须恰好 3 处｜⚠⚠⚨ **批 CA**｜⚠ **整行锚定**｜⚠ 摘掉一个 ⇒ 对应失败路径 fall through ⇒ 可能落到 `return 0` ⇒ 探针恒绿'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    sys\.exit\(main\(\)\)$' 1 '恒真探针的**入口**必须把 `main()` 的返回值交给 `sys.exit`（否则返回值被丢弃 ⇒ rc 恒 0 ⇒ 探针**永远绿**）｜⚠⚠⚨ **批 CA**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/bootstrap-deps.py" '^\s*return [1-9]$' 1 '依赖引导脚本的**失败退出码出口**必须恰好 1 处｜⚠⚠⚨ **批 CA**｜⚠ **整行锚定**｜⚠ 它**不在 CI 里**（手动引导用）⇒ 但「失败出口被摘 ⇒ 静默成功」是同一类洞 ⇒ 一并收'
arch_need_count "$SRC/scripts/bootstrap-deps.py" '^    sys\.exit\(main\(\)\)$' 1 '依赖引导脚本的**入口**必须把 `main()` 的返回值交给 `sys.exit`（否则返回值被丢弃 ⇒ rc 恒 0 ⇒ 引导脚本**永远报成功**）｜⚠⚠⚨ **批 CA**｜⚠ **整行锚定**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CA 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CA 段门项全绿（失败上报出口不许被摘掉：判据层与 CI 自己的出口都有门）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CB · 「未验证」不许被当成「通过」：契约门的 SKIP 必须用专属退出码 3 ──
#
# ⚠⚠⚨ **起因（实测盘点，不是印象）**：批 CA 把「失败上报出口」逐个钉住了
#   ⇒ 盘出**唯一**一处「用 `exit 0` 表示**未验证**」的地方：
#   `contract-check.sh` 的两个 SKIP 分支。
#   ⚠⚠⚨ **批 BW 早就在探针侧立了这条口径**（0=通过 / 1=失败 / **3=SKIP**），
#   而且它的注释**早就写着**「与第 10 步契约门**同款口径**」
#   ⇒ 但契约门脚本一直用的是 `exit 0` ⇒ **注释与实际行为不一致**（批 BB 纪律：
#   说明必须与实际行为一致）⇒ 本批把脚本侧对齐。
#
# ⚠⚠⚨ **洞（行为级·假绿）**：`ci.sh` 第 10 步原来是
#       if cmd; then …「✓ 引擎契约门通过」… else … exit 1; fi
#   ⇒ 脚本 exit 0（**未验证**）也走「**通过**」那一支
#   ⇒ ⚠⚠⚨ **实测**：缺 python3 时**120 条契约断言一条都没跑**，
#     CI 却打印「**✓ 引擎契约门通过**」⇒ **假绿**。
#   ⇒ 根因链有两环：① 脚本用 exit 0 表示未验证；② CI 不分诊退出码。
#   ⇒ **两环都要修**，只修一环仍然是假绿。
#
# ⚠⚠⚨ **修法（照批 BW 的房style）**：
#   ① **脚本侧**：两个 SKIP 分支 `exit 0` → **专属未验证码 3**；
#   ② **CI 侧**：第 10 步**接住退出码**并分诊
#      （**0 = 通过 / 3 = 未验证(SKIP) / 其它非 0 = 失败**）
#      ⇒ SKIP 支**如实打印「本组未验证，不算通过」**（与第 13 步同款口径）。
#
# ⚠⚠⚨ **口径（如实记着）**：
#   · 引擎缺席那一支在 CI 里**走不到**（ci.sh 的外层守卫先判过引擎在不在）
#     ⇒ 收它是为了「脚本**单独**跑时也诚实」+ 与第 13 步口径一致；
#   · CI 里**实际可达**的是「缺 python3」那一支 ⇒ 门项两条都收（不许只收一条）。
arch_need_count "$SRC/scripts/contract-check.sh" '^    exit 3$' 2 '契约门**引擎缺席**那一支的「未验证」必须用**专属退出码 3**（不是 `exit 0`）｜⚠⚠⚨ **批 CI**：+1 = 末尾「有未验证 ⇒ exit 3」（**失败优先**）｜⚠⚠⚨ **批 CB**｜⚠ **整行锚定**｜⚠⚠⚨ 以前是 `exit 0` ⇒ 与「通过」在**退出码**这一层分不开 ⇒ 调用方无从分辨｜⚠ 口径：只数**独立成行**的 `exit 3`（「缺 python3」那一支是**行内**形态 ⇒ 另有一条门）'
arch_need_count "$SRC/scripts/contract-check.sh" '^command -v python3 >/dev/null \|\| \{ echo "SKIP contract-check：[^"]*"; exit 3; \}$' 1 '契约门**缺 python3**那一支的「未验证」必须用**专属退出码 3**｜⚠⚠⚨ **批 CB**｜⚠ **整行锚定**｜⚠⚠⚨ **实测的洞**：这一支是 CI 里**实际可达**的那个 ⇒ 摘掉/改成 `exit 0` ⇒ **120 条契约断言一条没跑**却报「✓ 引擎契约门通过」⇒ **假绿**｜⚠ 口径：报错文案是自由文本 ⇒ 用 `[^"]*` 有界通配钉住结构'
arch_need_count "$SRC/scripts/ci.sh" '^    _cc_rc=0$' 1 'CI 第 10 步必须**初始化**契约门的退出码变量（`set -u` 下未初始化 ⇒ 读它就炸）｜⚠⚠⚨ **批 CB**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci.sh" '^    if \[ "\$_cc_rc" -eq 0 \]; then$' 1 'CI 第 10 步必须**分诊**「退出码 0 = 通过」这一支｜⚠⚠⚨ **批 CB**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci.sh" '^    elif \[ "\$_cc_rc" -eq 3 \]; then$' 1 'CI 第 10 步必须**分诊**「退出码 3 = 未验证(SKIP)」这一支（⚠ 少了它 ⇒ exit 3 会落进「失败」⇒ 未验证被当成失败；⚠ 更糟的是少了它而脚本还用 exit 0 ⇒ 未验证被当成**通过**）｜⚠⚠⚨ **批 CB**｜⚠ **整行锚定**｜⚠ 与第 13 步（agent 工具面门，批 BW）**同款口径**'
arch_need_count "$SRC/scripts/ci.sh" '^        echo "✗ 引擎契约门\*\*未验证\*\*[^\"]*" >&2$' 1 'CI 第 10 步的契约门**未验证**支必须**判红**（⚠⚠⚨ **批 CI**：⚠⚠⚨ 以前只打印「不算通过」⇒ CI 继续 ⇒ 最后照样打「✓ CI 门通过」⇒ **核心门根本没验，却说 CI 通过** ⇒ 假绿（批 CB 的已知边界，本批收口））｜⚠ **整行锚定**｜⚠⚠⚨ **批 CI**'
arch_need_count "$SRC/scripts/ci.sh" '^        echo "✗ 引擎契约门失败（退出码 \$_cc_rc）" >&2$' 1 'CI 第 10 步的失败支必须**报出退出码**（诊断不失真：只知道「失败」不知道「哪一类失败」）｜⚠⚠⚨ **批 CB**｜⚠ **整行锚定**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CB 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CB 段门项全绿（未验证不许被当成通过：契约门 SKIP ⇒ 专属码 3 + CI 侧分诊）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0
# ── 批 CC · 「失败出口的码值」是判据的一部分：不许被悄悄改 ──────────────────
#
# ⚠⚠⚨ **起因（实测盘点，不是印象）**：批 CA 把「失败上报出口」逐个钉住了
#   ⇒ 但它钉的是**总数**（`return [1-9]` == 16）⇒ 而**退出码是判据的一部分**
#   （每个码值承载一类语义）⇒ 改一个码值**总数不变** ⇒ 批 CA 的门**全绿**
#   ⇒ 诊断被带偏。⇒ 批 CA 段自己就写着这条已知边界 ⇒ **本批就是那个「下一批」**。
#
# ⚠⚠⚨ **洞 ①（行为级·假绿·旗舰）**：`check-deb-layout.sh` 的 SKIP 分支
#   （没有 dpkg-deb ⇒ 本门**未验证**）用的是 `exit 3`
#   ⇒ ⚠⚠⚨ **实测**：把它改成 `exit 0` ⇒ 脚本 **rc=0** 而输出**仍写着**
#     「SKIP: 没有 dpkg-deb（本门**未验证**，不算通过）」⇒
#     CI 第 12 步打印「**✓ deb 布局验收通过**」⇒ **假绿坐实**
#   ⇒ ⚠⚠⚨ 而**现有门全绿**（`exit 3` **一条门都没有** ⇒ 没人看得见）。
#
# ⚠⚠⚨ **洞 ②（行为级·误判）**：`ci.sh` 第 12 步**不分诊**退出码
#   （`elif sh …; then … else … exit 1; fi`）⇒
#   ① 脚本 exit 3（**正确的未验证**）⇒ CI 判「✗ 失败」并 exit 1
#      ⇒ **未验证被当成失败**；
#   ② 脚本 exit 0（**未验证**）⇒ CI 打印「✓ 通过」⇒ **假绿**。
#   ⇒ 与批 CB 修的第 10 步（契约门）**同款洞** ⇒ 本批同款修。
#
# ⚠⚠⚨ **洞 ③（行为级·诊断被带偏）**：审计器的失败码**每个都有语义**
#   （2=盲区 / 3=豁免之外有隐患 / **4=次数门没配准** / 5=正则坏 / 6=总数失配
#   / 7=重名 / 8=锚定形态 / 9=未定义名）
#   ⇒ ⚠⚠⚨ **实测**：把 `return 4` 改成 `return 3` ⇒ 次数门失准时审计器报
#     **rc=3** ⇒ **撞上「豁免之外有隐患」的码** ⇒
#     **按 rc 分派的自动化处理会走错分支** ⇒ 排障被带偏。
#
# ⚠ **修法（本批只动判据层与 CI 脚本 ⇒ 零产品代码改动）**：
#   ① **按码值分桶**逐个钉住（不再是「非 0 的总数」）⇒ 改一个码值
#     ⇒ **旧桶 -1 + 新桶 +1** ⇒ **两条都红**；
#   ② `ci.sh` 第 12 步**接住退出码**并分诊（0/3/其它）
#     ⇒ 与第 10 步、第 13 步**同款口径**；
#   ③ 批 CA 的 `return [1-9]` **宽门原地替换**成第一条分桶门
#     （其余 6 条在本段）⇒ 7 条分桶门**完全蕴含**那条宽门
#     （5+1+2+1+1+2+4 = 16）⇒ 删宽门不降低保护。
#
# ⚠ **口径**：
#   · 「用法错」= **2**（4 个探针 + check-deb-layout.sh + 恒真探针）
#     ⇒ 改成 1 ⇒ **用法错被当成断言失败** ⇒ 诊断失真；
#   · 「未验证」= **3**（check-deb-layout.sh + agent 工具面探针）
#     ⇒ 改成 0 ⇒ **未验证被当成通过** ⇒ 假绿（洞 ①）；
#   · 审计器的 9 个码**各有语义** ⇒ 逐个钉死。
arch_need_count "$SRC/scripts/check-deb-layout.sh" '^[[:space:]]*exit 1$' 1 'deb 布局验收的**真实失败**出口（`exit 1`）必须恰好 1 处｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**｜⚠ 与「用法错(2)」「未验证(3)」**分桶**钉住 ⇒ 改任何一个码值 ⇒ 另一个桶也红 ⇒ **码值语义不许被顶替**'
arch_need_count "$SRC/scripts/check-deb-layout.sh" '^[[:space:]]*exit 2$' 1 'deb 布局验收的**用法错**出口（`exit 2`）必须恰好 1 处（`✗ 用法：$0 <deb 路径>`）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**｜⚠ 改成 1 ⇒ **用法错被当成真实失败** ⇒ 诊断失真'
arch_need_count "$SRC/scripts/check-deb-layout.sh" '^[[:space:]]*exit 3$' 1 'deb 布局验收的**未验证**出口（`exit 3`）必须恰好 1 处（⚠⚠⚨ **实测的洞**：改成 `exit 0` ⇒ **rc=0** 而输出仍写着「SKIP …未验证」⇒ CI 打印「✓ 通过」⇒ **假绿坐实**，且**现有门全绿**）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s*FAILS.append\(4\)$' 1 '审计器的 **rc=4**（**次数门没配准**）失败态必须恰好 1 处（⚠⚠⚨ **批 CQ**：形态从 `return 4` 改成 `FAILS.append(4)` ⇒ **收集**而不是早退⇒ rc 仍取最先失败的那个 ⇒ **码值语义不变**）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s*FAILS.append\(5\)$' 2 '审计器的 **rc=5**（正则写法坏 / 门项命中 0 次）失败态必须恰好 2 处（⚠⚠⚨ **批 CQ**：形态从 `return 5` 改成 `FAILS.append(5)`）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s*FAILS.append\(6\)$' 1 '审计器的 **rc=6**（门项总数失配）失败态必须恰好 1 处（⚠⚠⚨ **批 CQ**：形态从 `return 6` 改成 `FAILS.append(6)`）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s*FAILS.append\(7\)$' 1 '审计器的 **rc=7**（门型重名）失败态必须恰好 1 处（⚠⚠⚨ **批 CQ**：形态从 `return 7` 改成 `FAILS.append(7)`）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s*FAILS.append\(8\)$' 2 '审计器的 **rc=8**（锚定形态违规）失败态必须恰好 2 处（⚠⚠⚨ **批 CQ**：形态从 `return 8` 改成 `FAILS.append(8)`）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s*FAILS.append\(9\)$' 4 '审计器的 **rc=9**（未定义名 / 豁免基线坏行 / 反向配准对不上）失败态必须恰好 4 处（⚠⚠⚨ **批 CQ**：形态从 `return 9` 改成 `FAILS.append(9)`）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci.sh" '^    _dl_rc=0$' 1 'CI 第 12 步必须**初始化** deb 布局验收的退出码变量（`set -u` 下未初始化 ⇒ 读它就炸）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci.sh" '^    sh "\$SRC\/scripts\/check-deb-layout\.sh" "\$DEB_OUT" > "\$_dl_log" 2>&1 \|\| _dl_rc=\$\?$' 1 'CI 第 12 步必须**接住** deb 布局验收的退出码（`|| _dl_rc=$?`）且 stderr **落盘**｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**｜⚠⚠⚨ 写成 `if cmd; then` ⇒ exit 0（未验证）也走「通过」那一支 ⇒ **假绿**'
arch_need_count "$SRC/scripts/ci.sh" '^    if \[ "\$_dl_rc" -eq 0 \]; then$' 1 'CI 第 12 步必须**分诊**「退出码 0 = 通过」这一支｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci.sh" '^    elif \[ "\$_dl_rc" -eq 3 \]; then$' 1 'CI 第 12 步必须**分诊**「退出码 3 = 未验证(SKIP)」这一支（⚠ 少了它 ⇒ exit 3 落进「失败」⇒ **未验证被当成失败**）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci.sh" '^        echo "‣ SKIP deb 布局验收：本组\*\*未验证\*\*[^"]*" >&2$' 1 'CI 第 12 步的 SKIP 支必须**如实打印「未验证、不算通过」**｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**｜⚠ 少了这句 ⇒ 日志里只剩一句「✓ 通过」或一句「✗ 失败」⇒ 读日志的人**分不出这一组到底验没验**'
arch_need_count "$SRC/scripts/ci.sh" '^        echo "✗ deb 布局验收失败（退出码 \$_dl_rc）" >&2$' 1 'CI 第 12 步的失败支必须**报出退出码**（诊断不失真：只知道「失败」不知道「哪一类失败」）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-platform-probe.sh" '^[[:space:]]*exit 2$' 1 '平台探针的**用法错**出口（`exit 2`）必须恰好 1 处（`✗ 用法：$0 <deepDolphin 二进制>`）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**｜⚠ 改成 1 ⇒ **用法错被当成断言失败** ⇒ 诊断失真'
arch_need_count "$SRC/scripts/ci-docs-lang-probe.sh" '^[[:space:]]*exit 2$' 1 '文档语言探针的**用法错**出口（`exit 2`）必须恰好 1 处｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**｜⚠ 改成 1 ⇒ **用法错被当成断言失败** ⇒ 诊断失真'
arch_need_count "$SRC/scripts/ci-divider-probe.sh" '^[[:space:]]*exit 2$' 1 '分隔线探针的**用法错**出口（`exit 2`）必须恰好 1 处｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**｜⚠ 改成 1 ⇒ **用法错被当成断言失败** ⇒ 诊断失真'
arch_need_count "$SRC/scripts/probe-agent-tool-surface.sh" '^[[:space:]]*exit 2$' 1 'agent 工具面探针的**用法错**出口（`exit 2`）必须恰好 1 处｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**｜⚠ 改成 1 ⇒ **用法错被当成断言失败** ⇒ 诊断失真'
arch_need_count "$SRC/scripts/probe-agent-tool-surface.sh" '^[[:space:]]*exit 3$' 2 'agent 工具面探针的**未验证**出口（`exit 3`）必须恰好 2 处（⚠ 批 BW 立的 0/1/**3** 口径：3 = SKIP ⇒ **不算通过**）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**｜⚠ 改成 0 ⇒ **未验证被当成通过** ⇒ 假绿'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s*return 2$' 1 '恒真探针的**用法错**出口（`return 2`）必须恰好 1 处（`用法：ci-tautology-check.py <源码根目录>`）｜⚠⚠⚨ **批 CC**｜⚠ **整行锚定**｜⚠ 改成 1 ⇒ **用法错被当成检查失败** ⇒ 诊断失真'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CC 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CC 段门项全绿（失败出口的码值语义不许被顶替：未验证/用法错/审计器各码分桶钉住）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0
# ── 批 CD · 「工具读不了」不许被当成「没问题」 ────────────────────────────
#
# ⚠⚠⚨ **起因（实测盘点，不是印象）**：批 AZ 早就记下过「真正吞退出码的是
#   **命令替换内部的 `|| true`**」⇒ 但本批**逐个盘点**了 `scripts/` 下
#   **外部工具的调用站点**（419 处）⇒ 按「工具失败会落到**哪一支**」分类：
#   · 「危险方向」（工具崩了走「通过」那一支）⇒ **0 处**（如实记着）；
#   · 「命令替换内 `|| true`」⇒ 多处，但**输入是字符串**的（grep 读的是管道
#     ⇒ 崩不了）⇒ 无害；
#   · ⚠⚠⚨ **输入是文件**的那几处 ⇒ **工具读不了 ⇒ 静默跳过 ⇒ 假绿**。
#
# ⚠⚠⚨ **洞 ①（行为级·假绿·旗舰）**：`ci-d2.sh` 的散值门
#   ⇒ 造一个**含散值**的源文件，让它对 grep **不可读**（chmod 000 ⇒ grep rc=2）
#   ⇒ `grep -rlE … 2>/dev/null` **静默跳过**它 ⇒ 命中数变 0
#   ⇒ 脚本打印「**✓ D2 命中 0/0（存量已清零，DS 单一真相源）**」并 **exit 0**
#   ⇒ ⚠⚠⚨ **门自己说「✓」⇒ 假绿坐实** ⇒ 而**接线门全绿** ⇒ 没人看得见。
#
# ⚠⚠⚨ **洞 ②（行为级·假绿）**：`ci-orphan-probe.sh` 的「什么算断言脚本」判定
#   ⇒ `grep -q '✗ ' "$_f" 2>/dev/null || continue`
#   ⇒ grep **崩了**（rc=2）与「没找到」（rc=1）**混为一谈**
#   ⇒ 游离断言脚本**被静默跳过** ⇒ 脚本打印「**✓ 无游离断言脚本**」并 exit 0
#   ⇒ **漏检坐实**。
#
# ⚠ **修法（只动判据层 ⇒ 零产品代码改动）**：
#   在**扫描之前**先验**可读性** ⇒ 读不了 ⇒ 判失败
#   ⇒ **不许让工具静默跳过 ⇒ 不许把「没判定」当成「没问题」**
#   （⚠ 与批 CB/CC 同款口径：**未验证不许被当成通过**）。
#   ⚠ 选「扫描前验可读性」而不是「逐个接 grep 的 rc」的理由：
#     ① **一次挡住整类**（同一批文件的所有 grep 调用都受益）；
#     ② 被扫集合与被验集合**完全一致**（不漏一个文件）；
#     ③ 失败信息**指名道姓**是哪个文件读不了（排障不用猜）。
#   ⚠ `ci-orphan-probe.sh` 的 `calls_of()` 里也有 `2>/dev/null`
#     ⇒ 但它的失败方向是「REACH 集合变小 ⇒ **误报**（不是假绿）」⇒ 安全方向
#     ⇒ 如实记着，**不改**。
arch_need_count "$SRC/scripts/ci-d2.sh" '^_d2_unread="\$\(find "\$SRC\/src" -type f ! -readable -print 2>\/dev\/null\)" \|\| _d2_find_rc=\$\?$' 1 'D2 散值门**必须在扫描前验可读性**（⚠⚠⚨ **实测的洞**：某个含散值的源文件对 grep 不可读 ⇒ `grep -rl … 2>/dev/null` **静默跳过**它 ⇒ 命中数变 0 ⇒ 门打印「**✓ D2 命中 0/0**」并 exit 0 ⇒ **门自己说「✓」⇒ 假绿坐实**）（⚠ **这一条同时保证「find 的退出码被接住」**：`|| _d2_find_rc=$?` 与检查在同一行 ⇒ 整行锚定 ⇒ 摘掉退出码接住也红）｜⚠⚠⚨ **批 CD**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-d2.sh" '^    FAIL=1    # ⚠⚠⚨ 批 CD：不可读 ⇒ 判失败（末尾的 exit 1 在「✓ 命中 0\/0」之前 ⇒ 那个 ✓ 永远打不出来）$' 1 'D2 散值门在**有源文件不可读**时**必须判失败**（`FAIL=1`）⇒ 末尾的 `exit 1` 在「✓ 命中 0/0」**之前** ⇒ 那个「✓」永远打不出来｜⚠⚠⚨ **批 CD**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^        \[ -r "\$_f" \] \|\| _orphan_unread="\$_orphan_unread \$\(basename "\$_f"\)"$' 1 '无游离门**必须在扫描前验可读性**（⚠⚠⚨ **实测的洞**：游离断言脚本对 grep 不可读 ⇒ `grep -q … || continue` **静默跳过**它 ⇒ 门打印「**✓ 无游离断言脚本**」并 exit 0 ⇒ **漏检 ⇒ 假绿坐实**）｜⚠⚠⚨ **批 CD**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^        fail=1    # ⚠⚠⚨ 批 CD：不可读 ⇒ 判失败（末尾统一 exit 1 ⇒ 「✓ 无游离断言脚本」永远打不出来）$' 1 '无游离门在**有脚本不可读**时**必须判失败**（`fail=1`）⇒ 末尾统一 `exit 1` ⇒ 「✓ 无游离断言脚本」永远打不出来｜⚠⚠⚨ **批 CD**｜⚠ **整行锚定**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CD 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CD 段门项全绿（工具读不了不许被当成没问题：扫描前先验可读性）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0
# ── 批 CE · 「外部工具的失败」不许被当成「检查通过」 ────────────────────────
#
# ⚠⚠⚨ **起因（实测盘点，不是印象）**：批 CD 盘过「外部工具的调用站点」
#   （419 处）⇒ 结论是「**危险方向 0 处**」⇒ ⚠⚠⚨ **但那个口径有盲区**：
#   它只找**字面形态** `if 外部工具; then <不通过>; else <通过>; fi`
#   ⇒ **漏了两种形态**：
#   ① **工具输出 → 变量 → 判定**（`N=$( 工具 | grep -c )` ⇒ `[ "$N" = "0" ] || die`）；
#   ② **无 else 分支**的 `if 工具; then <失败支>; fi`
#      ⇒ 工具失败 ⇒ 条件为假 ⇒ **什么都不做 ⇒ 隐式通过**。
#   ⇒ 本批用**更宽的口径**重盘（两种形态都盘）⇒ 盘出 **3 处真洞**
#   （另 4 处输入是字符串 ⇒ grep 崩不了 ⇒ 无害）。
#
# ⚠⚠⚨ **洞 ①（行为级·假绿·旗舰·D7 核心验收）**：`build-deb.sh` 的 ldd 缺库检查
#   `_nf="$(env -u LD_LIBRARY_PATH ldd … 2>&1 | grep -c 'not found' || true)"`
#   ⇒ ldd **失败**（二进制不存在 / 不可读 / 工具崩了 ⇒ 报 "cannot open"）
#   ⇒ 计数 **0** ⇒ 「无缺失库」⇒ **判通过** ⇒ **假绿**
#   ⇒ ⚠⚠⚨ **实测**（stub 一个失败的 ldd）：旧形态 **rc=0 走到末尾**。
#   ⇒ ⚠⚠⚨ 假绿的代价：**发出一个装不起来的 deb**（CI 第 11 步照样报「✓」）。
#
# ⚠⚠⚨ **洞 ②（行为级·假绿）**：`build-deb.sh` 的 readelf RPATH 检查
#   `if readelf -d … | grep -qiE "rpath|runpath"; then die; fi`
#   ⇒ **无 else** ⇒ readelf 失败 ⇒ 不进 then ⇒ **静默判「没带 RPATH」⇒ 假绿**
#   ⇒ ⚠⚠⚨ **实测**（stub 一个失败的 readelf）：旧形态 **rc=0 走到末尾**。
#
# ⚠⚠⚨ **洞 ③（行为级·假绿·判据层自身）**：`ci-wiring.sh` 的图标收口检查
#   （`strip_comments "$f" | grep -qE 'QIcon::fromTheme'` ⇒ then 分支是失败支、
#   **无 else**）⇒ 文件对工具不可读 ⇒ 条件为假 ⇒ **裸图标漏检** ⇒ 假绿。
#
# ⚠ **修法（只动判据层与构建脚本 ⇒ 零产品代码改动）**：
#   ① **接住工具的退出码** ⇒ 非 0 ⇒ **判失败**（工具失败 = 没验过）
#      ⇒ 与批 CB/CC/CD **同款口径**：**未验证不许被当成通过**；
#   ② **拆开管道**（工具输出先落进变量，再加工）
#      ⇒ 否则管道里**拿不到**工具自己的退出码（管道退出码是最后一条的）；
#   ③ `dpkg-deb -x` 的失败**改成响亮 die**（以前靠 `set -e` 静默中止
#      ⇒ 没有 die 消息 ⇒ 看着像「跑到一半没了」⇒ **诊断失真**）。
arch_need_count "$SRC/scripts/build-deb.sh" '^    die "ldd 读不了解包后的二进制（退出码 \$_ldd_rc）⇒ \*\*D7 缺库检查未验证\*\*，不算通过（\$_ldd_out）"$' 1 'deb 构建的 **ldd 缺库检查**（D7 核心验收）**必须在 ldd 失败时判失败**（⚠⚠⚨ **实测的洞**：ldd 失败（二进制读不了 / 工具崩了）⇒ 旧形态计数 0 ⇒ 判「无缺失库」⇒ **rc=0 假绿** ⇒ **发出装不起来的 deb**）｜⚠⚠⚨ **批 CE**｜⚠ **整行锚定**｜⚠ 与批 CB/CC/CD 同款口径：**未验证不许被当成通过**'
arch_need_count "$SRC/scripts/build-deb.sh" '^    die "readelf 读不了包内二进制（退出码 \$_re_rc）⇒ \*\*RPATH 检查未验证\*\*，不算通过（\$_re_out）"$' 1 'deb 构建的 **readelf RPATH 检查**必须在 readelf 失败时判失败（⚠⚠⚨ **实测的洞**：旧形态是 `if readelf … | grep -qiE …; then die; fi`（**无 else**）⇒ readelf 失败 ⇒ 不进 then ⇒ 静默判「没带 RPATH」⇒ **rc=0 假绿**）｜⚠⚠⚨ **批 CE**｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/build-deb.sh" '^dpkg-deb -x "\$DEB_PATH" "\$TMP\/unpack" \|\| die "解包失败：\$DEB_PATH（产物自检的前提就没有 ⇒ 后面全是空转）"$' 1 'deb 构建的**解包失败必须响亮 die**（⚠ 以前靠 `set -e` 静默中止 ⇒ 没有 die 消息 ⇒ 看着像「跑到一半没了」⇒ **诊断失真**）｜⚠⚠⚨ **批 CE**｜⚠ **整行锚定**'

arch_need_count "$SRC/scripts/ci-wiring.sh" '^    if \[ ! -r "\$f" \]; then$' 1 '接线门的**图标收口检查必须先验可读性**（⚠⚠⚨ **实测的洞**：某个 `src/ui/*.cpp` 对 grep **不可读** ⇒ `strip_comments … | grep -qE` **无输出** ⇒ **裸 QIcon::fromTheme 漏检** ⇒ 门照样绿 ⇒ **判据层自身的假绿**）｜⚠⚠⚨ **批 CE**｜⚠ **整行锚定**｜⚠ 与批 CB/CC/CD 同款口径：**未验证不许被当成通过**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CE 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CE 段门项全绿（外部工具的失败不许被当成「检查通过」：接住退出码 + 工具失败即判失败）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CF · 「判据层自己的剥注释」不许有三份实现、三种口径 ────────────────────────
#
# ⚠⚠⚨ **起因（实测盘点 + 对照实验，不是推演）**：
#   剥注释函数 `strip_comments` 在仓里有 **3 份 shell 实现 + 1 份 python 实现**：
#     · `ci-wiring.sh` = `s{(?<!:)(//)(?!:).*$}{}` + `.sh/.txt/.py` 走 sed 剥 `#` ⇒ **最全**
#     · `ci-d2.sh`     = 同款 perl 正则，但**缺 `.py` 分支** ⇒ `.py` 不剥 `#`
#     · `ci.sh`        = `s{//(?!:).*$}{}` —— **旧口径**（**没有** `(?<!:)`）
#     · 审计器（python）= 同款 perl 正则 + `.py` 分支（批 BK 已同步）
#   ⇒ 批 AS 的承诺是「**同一条命令、不复刻** ⇒ 两套口径必然漂**」
#   ⇒ 而**两个 shell 脚本根本没遵守**（它们自己复刻了，还各自漂了）
#   ⇒ ⚠⚠⚨ **实测（对照实验）**：
#     ① 同一份源码、同一个门项 ⇒ `ci.sh` 口径命中 **0**、
#        `ci-wiring.sh` 口径命中 **1** ⇒ **相反结论**；
#     ② 仓里已有 **12** 个真实源文件在两套口径下输出**不同**
#        （`https://…` 被 sed 兜底整段剥掉，perl 口径不会）⇒ **现在就能咬人**。
#   ⇒ 后果：ci.sh 的 verify 接线门**误报红**（假红，批 BS：假红逼人把承诺改弱）；
#     换个构造就是**漏检**（假绿）。
#
# ⚠⚠⚨ **洞 ②（静默降级 + 诊断失真）**：三份实现都有 perl→sed 的**静默兜底**。
#   ⇒ perl 缺席 ⇒ **口径变成第四种**；实测（造一个不含 perl 的 PATH）：
#     · 审计器**未捕获异常崩掉**（`FileNotFoundError: 'perl'`）⇒ 退出码 1
#       ⇒ 门报「**未知的失败码**」⇒ 真实原因（缺 perl）**没有任何消息提到**；
#     · 接线门红了，但红因是「取数/判定/渲染/接线任一段被摘掉」
#       —— ⚠⚠⚨ **与真实原因毫无关系** ⇒ 排障被带偏（批 CE 纪律：诊断不许失真）。
#
# ⚠ **修法（只动判据层 ⇒ 零产品代码改动）**：
#   ① **口径单一真相源**：`ci.sh` / `ci-d2.sh` **不再自己定义**
#      ⇒ 改为**从 `ci-wiring.sh` 原文抽取**（批 AV 纪律：抽取而非复刻）
#      ⇒ 一次挡住整类（口径永远一致，改一处就跟着变）；
#   ② **静默降级 ⇒ 响亮失败**：三个脚本顶层**前置检查 perl 在不在**
#      ⇒ 缺 ⇒ **响亮失败**（未验证不许被当成通过；批 CB/CC/CD/CE 同款口径）；
#      判据层的 `strip_comments` 默认分支**去掉 sed 兜底** ⇒ 工具失败**报出来**；
#   ③ **审计器前置检查**：缺 perl ⇒ 指名道姓 + 退出码 2
#      （2 = 审计器有盲区或缺文件 ⇒ C++ 侧的门项**根本没被审** ⇒ 正是盲区）。
arch_forbid "$SRC/scripts/ci.sh" 'perl -pe' 'ci.sh **不许自己实现剥注释**（⚠⚠⚨ **批 CF**：以前这里**自己定义**了一份，而且是**旧口径**（`s{//(?!:).*$}{}`，**没有** `(?<!:)`）⇒ `https://…` 会被整段剥掉 ⇒ **同一个门项，两处口径结论相反** —— 实测：同一份源码、同一个门项 ⇒ ci.sh 口径命中 **0**、ci-wiring.sh 口径命中 **1**；仓里已有 **12** 个真实源文件在两套口径下输出**不同** ⇒ 现在就能咬人，不是假想 ⇒ 假红（批 BS：假红逼人把承诺改弱）或漏检）｜⚠ **口径必须单一真相源**（批 AS：同一条命令、不复刻）｜⚠⚠⚨ **批 CF**'
arch_forbid "$SRC/scripts/ci-d2.sh" 'perl -pe' 'ci-d2.sh **不许自己实现剥注释**（⚠⚠⚨ **批 CF**：以前这里**自己定义**了一份（口径对，但**缺 `.py` 分支** ⇒ `.py` 不剥 `#` ⇒ 批 BK 的洞「注释里的串顶替真代码」在这里仍在））｜⚠ **口径必须单一真相源**（批 AS：同一条命令、不复刻）｜⚠⚠⚨ **批 CF**'
arch_need_count "$SRC/scripts/ci.sh" '^if ! eval "\$\(sed -n .\/\^strip_comments\(\) \{\/,\/\^\}\/p. "\$SRC\/scripts\/ci-wiring\.sh"\)" \|\| ! strip_comments "\$SRC\/scripts\/ci-wiring\.sh" >\/dev\/null 2>&1; then$' 1 'ci.sh 的剥注释函数必须**从 ci-wiring.sh 原文抽取**（⚠⚠⚨ **批 CF**：口径必须单一真相源 —— 批 AV 纪律「抽取而非复刻」⇒ 改一处就跟着变 ⇒ 不会漂）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CF**'
arch_need_count "$SRC/scripts/ci-d2.sh" '^if ! eval "\$\(sed -n .\/\^strip_comments\(\) \{\/,\/\^\}\/p. "\$SRC\/scripts\/ci-wiring\.sh"\)" \|\| ! strip_comments "\$SRC\/scripts\/ci-wiring\.sh" >\/dev\/null 2>&1; then$' 1 'ci-d2.sh 的剥注释函数必须**从 ci-wiring.sh 原文抽取**（⚠⚠⚨ **批 CF**：口径必须单一真相源 —— 批 AV 纪律「抽取而非复刻」）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CF**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^command -v perl >\/dev\/null 2>&1 \|\| \{$' 1 '判据层的剥注释**前提是 perl 在** ⇒ 缺它必须**响亮失败**（⚠⚠⚨ **批 CF**：以前会**静默降级**换口径 ⇒ 门与审计器不再同口径 ⇒ 判定不可信且无人知晓 ⇒ 假红或假绿都可能）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CF**｜⚠ 与批 CB/CC/CD/CE 同款口径：**未验证不许被当成通过**'
arch_need_count "$SRC/scripts/ci.sh" '^command -v perl >\/dev\/null 2>&1 \|\| \{$' 1 'CI 入口的剥注释**前提是 perl 在** ⇒ 缺它必须**响亮失败**（⚠⚠⚨ **批 CF**：以前静默降级 ⇒ 红因指错方向 ⇒ 排障被带偏）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CF**'
arch_need_count "$SRC/scripts/ci-d2.sh" '^command -v perl >\/dev\/null 2>&1 \|\| \{$' 1 '散值门的剥注释**前提是 perl 在** ⇒ 缺它必须**响亮失败**（⚠⚠⚨ **批 CF**：以前静默降级 ⇒ 命中数变 0 ⇒ 而本门**照样打印「✓ D2 命中 0/0」** ⇒ **假绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CF**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^        perl -pe .s\{\(\?<!:\)\(\/\/\)\(\?!:\)\.\*\$\}\{\}. "\$1"$' 1 '判据层的剥注释**必须直接走 perl**（⚠⚠⚨ **批 CG**：形态改成「`perl …` + **接住退出码**」（原来裹在 `if ! perl …; then` 里 ⇒ 拿不到**原始**退出码 ⇒ 分不清「工具坏了」与「消费者提前收工（SIGPIPE=141）」）⇒ **失败要接住**（写标记 ⇒ 末尾统一判红）⇒ perl 缺席/崩了都不会被当成「没有命中」｜⚠ **整行锚定** ⇒ 一旦有人把兜底或失败处理加回来 ⇒ 这一行变形 ⇒ 门立刻红｜⚠⚠⚨ **批 CG + 批 CP**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def require_perl\(\):$' 1 '审计器的**剥注释工具前提检查**的**定义**必须在（⚠⚠⚨ **批 CF**：以前 perl 缺席时审计器**未捕获异常崩掉** ⇒ 退出码 1 ⇒ 门报「**未知的失败码**」⇒ 真实原因没人知道）｜⚠ **带左括号** ⇒ 改名躲不过｜⚠ **整行锚定**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^    _rp = require_perl\(\)$' 1 '审计器的**剥注释工具前提检查**必须**真的被调用**（只定义不调 ⇒ 形同虚设 ⇒ 崩了没人发现）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CF**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CF 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CF 段门项全绿（判据层自己的剥注释只有一份实现、一种口径；剥注释工具不许静默降级）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CG · 「剥注释失败」不许被当成「没找到」 ────────────────────────────────
#
# ⚠⚠⚨ **起因（实测对照实验，不是推演）**：
#   批 CE 只在**图标收口那一个扫描点**加了「文件不可读 ⇒ 判失败」
#   ⇒ 其余调用点（forbid / need / count / any …）**都没有这层保护**。
#   ⇒ ⚠⚠⚨ **对照实验（同一个文件、同一份内容，只改权限）**：
#     · 文件**可读** ⇒ `✗ raise 不再散落在界面代码里：… —— src/…/zzAzCgProbe.cpp`
#       ⇒ 门**红**（违例被抓到）；
#     · 文件**不可读**（chmod 000）⇒ 那一行**整个消失** ⇒ 该 forbid 门**静默变绿**。
#   ⇒ ⚠⚠⚨ **彻底假绿**：探针放 `src/logic/`（不在批 CE 那一处的保护范围内）
#     ⇒ **接线门 rc=0 全绿**、✗ 行数 0 ⇒ 违例**完全没被看见**。
#   ⇒ 根因：管道里**拿不到** strip_comments 的退出码（管道退出码 = 最右命令的）
#     ⇒ 而「输出为空」与「工具失败」在下游**长得一模一样**。
#
# ⚠ **修法（只动判据层 ⇒ 零产品代码改动）**：
#   ① 剥注释**失败 ⇒ 写标记文件**（跨子 shell ⇒ 必须用文件，变量传不出去）
#      ⇒ 正常路径**零开销**（只在失败时写）；
#   ② 三个脚本**末尾统一检查标记** ⇒ 有 ⇒ **判红 + 指名道姓**列出失败的文件；
#      ⇒ 且放在「✓ 全绿」**之前** ⇒ 那个「✓」永远打不出来。
#   ⇒ ⚠⚠⚨ 一次挡住**整类**（批 CD 纪律：一次挡住整类，别逐点治标）：
#      forbid / need / count / any … **全部**剥注释调用点都受益。
#   ⚠ 为什么**不用落盘重写**（批 BI 已实测否决）：管道 → 落盘慢 20 倍
#      （30ms vs 1.5ms）⇒ 2511 次调用 ⇒ 84 秒 ⇒ CI 不可接受。
#   ⚠ 为什么**不用懒探测**（批 BI 已有）：它只验「工具活着」，
#      **盖不住「这一次调用」失败**（文件不可读时工具是活的）。
arch_need_count "$SRC/scripts/ci-wiring.sh" '^        printf .%s\\n. "\$1" >> "\$STRIP_FAIL_FILE"$' 1 '剥注释**失败必须写标记**（⚠⚠⚨ **批 CG**：工具失败 = 没验过 ⇒ 不许被当成「没有命中」—— 管道里**拿不到** strip_comments 的退出码 ⇒ 失败时**写标记文件**（跨子 shell ⇒ 必须用文件，变量传不出去）⇒ 正常路径**零开销**）｜⚠ **恰好 1 处**（**可读性先验**那一支 ⇒ 少一处就红）｜⚠ **整行锚定**（⚠ 同内容不同缩进是常态 ⇒ 必须按缩进拆成两条门，**一条正则罩不住多缩进**）｜⚠⚠⚨ **批 CG**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^            printf .%s\\n. "\$1" >> "\$STRIP_FAIL_FILE"$' 2 '剥注释**失败必须写标记**（⚠⚠⚨ **批 CG**：工具失败 = 没验过 ⇒ 不许被当成「没有命中」⇒ 失败时**写标记文件** ⇒ 末尾统一判红）｜⚠ **恰好 2 处**（sed 支与 perl 支**各一处** ⇒ 少一处就红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CG**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^STRIP_FAIL_FILE="\$\{TMPDIR:-\/tmp\}\/deepdolphin-strip-fail\.\$\$"$' 1 '判据层的**剥注释失败标记文件**的定义必须在（⚠⚠⚨ **批 CG**：标记是跨子 shell 传状态的唯一手段 —— 变量传不出子 shell ⇒ 只能落文件）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CG**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^if \[ -s "\$STRIP_FAIL_FILE" \]; then$' 1 '判据层**必须检查剥注释失败标记**（⚠⚠⚨ **批 CH**：诊断**搬进 trap**了⇒ 退出时**必打** ⇒ 这一行只负责 exit 1⇒ ⚠⚠⚨ **实测的洞**：段落 `ARCH_FAIL` **提前 exit** 时末尾检查根本跑不到⇒ 诊断打不出来 ⇒ 门侧只报「出现 0 次（期望 N 次）」⇒ **真话被藏了**⇒ 现在：无论从哪退出，诊断都会打出来并点名那个文件）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci.sh" '^STRIP_FAIL_FILE="\$\{TMPDIR:-\/tmp\}\/deepdolphin-strip-fail\.\$\$"$' 1 'CI 入口的**剥注释失败标记文件**的定义必须在（⚠⚠⚨ **批 CG**：ci.sh 抽出来的 strip_comments 失败时要写它 ⇒ 变量不在就写不进去 ⇒ 失败被静默吞掉）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CG**'
arch_need_count "$SRC/scripts/ci.sh" '^if \[ -s "\$STRIP_FAIL_FILE" \]; then$' 1 'CI 入口**必须检查剥注释失败标记**（⚠⚠⚨ **批 CH**：诊断**搬进 trap**了⇒ 退出时**必打** ⇒ 这一行只负责 exit 1⇒ 「✓ CI 门通过」永远打不出来）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-d2.sh" '^STRIP_FAIL_FILE="\$\{TMPDIR:-\/tmp\}\/deepdolphin-strip-fail\.\$\$"$' 1 '散值门的**剥注释失败标记文件**的定义必须在（⚠⚠⚨ **批 CG**：ci-d2.sh 抽出来的 strip_comments 失败时要写它 ⇒ 变量不在就写不进去 ⇒ 失败被静默吞掉）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CG**'
arch_need_count "$SRC/scripts/ci-d2.sh" '^if \[ -s "\$STRIP_FAIL_FILE" \]; then$' 1 '散值门**必须检查剥注释失败标记**（⚠⚠⚨ **批 CH**：诊断**搬进 trap**了⇒ 退出时**必打** ⇒ 这一行只负责 exit 1⇒ 「✓ D2 命中 0/0」永远打不出来）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CG 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CG 段门项全绿（剥注释失败不许被当成「没找到」：失败留标记 + 末尾统一判红）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CH · 「盘点方法本身」也要被门守：审计器自己读不了不许当成「没问题」 ──────
#
# ⚠⚠⚨ **起因（实测坐实，不是推演）**：
#   ⚠⚠⚨ 批 CG 收了 **shell 侧三处**的「剥注释失败」
#   ⇒ 但**判据层自己**还有**第四份**剥注释实现 = **审计器**（python 侧）
#   ⇒ 它把「源文件读不了」当成「**这个文件里没有**」⇒ 实测三个洞：
#   ① **诊断失真**：被盯的源文件不可读 ⇒ 报「**门永远匹配不到（形同虚设）**」
#      ⇒ ⚠⚠⚨ **完全不提「不可读 / 权限」**（实测 grep 计数 = 0）
#      ⇒ 真实原因是权限，报告说的是「门写错了」⇒ 排障被带偏；
#   ② **崩在栈里**：审计器自己依赖的文件（门脚本 / 豁免基线 / 门项总数基线）
#      不可读 ⇒ 未捕获 `PermissionError` ⇒ 退出码 **1**
#      ⇒ 门侧报「**未知的失败码**」⇒ 真实原因没有任何一条消息提到
#      （⚠ 批 CF 修过「缺 perl」的同一形状，**没管「文件读不了」**）；
#   ③ ⚠⚠⚨ **假绿的机制缺口**：审计器用「命中数 == 期望数」判绿
#      ⇒ 而「读不了」产生的命中数恰好是 **0**
#      ⇒ **凡是期望 0 次的门**，被盯文件读不了时 ⇒ 命中 0 == 期望 0
#      ⇒ 校准说「0 条失准」⇒ **审计器判绿** ⇒ 而那个文件**根本没被审**。
#      ⚠ **当前仓里**每个被期望-0 门盯着的文件**同时**被别的门盯着
#      ⇒ 端到端实测 rc=5（红，但**红因指错**）⇒ **假绿尚未落地**；
#      ⇒ 但**机制缺口是真的** ⇒ 必须先挡住。
#
# ⚠ **修法（只动判据层 ⇒ 零产品代码改动）**：
#   ① **统一读入口** `read_source()`：读不了 ⇒ 抛 `UnreadableSource`
#      ⇒ 所有读源文件的地方都走它 ⇒ 一次挡住整类（批 CD 纪律）；
#   ② **先验可读性**（`os.access` 用真实 uid ⇒ 与 shell 的 `-r` 同口径
#      ⇒ **两侧口径一致**）；
#   ③ **接住工具的退出码**（批 CG 纪律：工具失败 ≠ 没找到）；
#   ④ **顶层兜底** ⇒ 指名道姓 + **rc=2**（盲区：那些门项**根本没被审**）
#      ⇒ 与「缺 perl」同款 ⇒ 门侧的 rc=2 分派消息**同步补一句**
#      （批 BB：说明必须与实际行为一致）。
#   ⑤ ⚠⚠⚨ **门侧也漏了**（负控 A6.1 逮到）：段落 `ARCH_FAIL` **提前 exit** 时
#      末尾的标记检查**根本跑不到** ⇒ 「剥注释失败」诊断**打不出来**
#      ⇒ 门侧只报「出现 0 次（期望 N 次）」⇒ **真话被藏了**
#      ⇒ 修法：诊断搬进**退出 trap** ⇒ 无论从哪退出都会打出来并点名那个文件
#      ⇒ 末尾的显式检查只负责 exit 1（诊断不再重复打）。
#   ⇒ ⚠⚠⚨ **审计器就是判定层自己的「盘点方法」**
#   ⇒ 它不可靠 ⇒ 盘点结论就不可靠
#   ⇒ 这正是「**盘点方法本身也要被门守**」的第一块砖。
arch_forbid "$SRC/scripts/ci-wiring-audit.py" 'open\([^)]*\)\.read\(\)' '审计器**不许再直接用 open 读源文件**（⚠⚠⚨ **批 CH**：读不了 ⇒ 必须**指名道姓地失败** ⇒ 统一走 `read_source` ⇒ 一次挡住整类；⚠ 这个门盯的是**写法** ⇒ 将来新增的读文件点自动被约束）｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^class UnreadableSource\(Exception\):$' 1 '审计器的**「源文件读不了」异常类**必须在（⚠⚠⚨ **批 CH**：⚠⚠⚨ 实测：python 侧把「读不了」当成「这个文件里没有」⇒ 报成「**门永远匹配不到**」⇒ 完全不提权限 ⇒ 排障被带偏）｜⚠ **带左括号** ⇒ 改名躲不过｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def read_source\(path\):$' 1 '审计器的**统一读入口**必须在（⚠⚠⚨ **批 CH**：所有读源文件的地方都走它⇒ 读不了 ⇒ 抛异常 ⇒ 顶层兜底 ⇒ rc=2 ⇒ **一次挡住整类**）｜⚠ **带左括号** ⇒ 改名躲不过｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^    if not os\.access\(path, os\.R_OK\):$' 1 '审计器的剥注释**必须先验可读性**（⚠⚠⚨ **批 CH**：⚠⚠⚨ 实测：perl 打不开文件时**退出码仍是 0** ⇒ 靠退出码抓不住「读不了」⇒ 必须先验；⚠ `os.access` 用**真实 uid** ⇒ 与 shell 的 `-r` 同口径⇒ **两侧口径一致**，不会一边绿一边红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^    if _tool_rc != 0:$' 1 '审计器的剥注释**必须接住工具的退出码**（⚠⚠⚨ **批 CH**：批 CG 纪律：工具失败 ≠ 没找到 ⇒ 退出码非 0 ⇒ 抛 ⇒ 不许把空输出当成「没有」）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^        raise UnreadableSource\(path, .读不了（%s）. % e\)$' 1 '审计器的**读不了必须抛**（⚠⚠⚨ **批 CH**：统一读入口的 OSError ⇒ 抛⇒ 顶层兜底 ⇒ 指名道姓 + rc=2 ⇒ 不许静默当空）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^        raise UnreadableSource\(path, .对工具不可读（权限）.\)$' 1 '审计器的**「对工具不可读」必须抛**（⚠⚠⚨ **批 CH**：先验可读性命中 ⇒ 抛⇒ 顶层兜底 ⇒ rc=2）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^        raise UnreadableSource\(path, .剥注释工具退出码 %d. % _tool_rc\)$' 1 '审计器的**「工具退出码非 0」必须抛**（⚠⚠⚨ **批 CH**：工具失败 ≠ 没找到）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^    except UnreadableSource as e:$' 1 '审计器的**顶层必须兜住「源文件读不了」**（⚠⚠⚨ **批 CH**：⚠⚠⚨ 实测：以前是**未捕获异常** ⇒ 退出码 1 ⇒ 门侧报「**未知的失败码**」⇒ 真实原因（权限）没有任何一条消息提到 ⇒ 排障被带偏；⇒ 现在：指名道姓 + **rc=2**（盲区：那些门项**根本没被审**））｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def main\(\):$' 1 '审计器的**顶层入口**必须在（⚠ **批 BN**：改名漏改调用点 ⇒ NameError ⇒ 崩在栈里 ⇒ 退出码 1 ⇒「未知的失败码」；⚠ 现在顶层入口负责兜底「源文件读不了」⇒ 入口被摘 ⇒ 兜底也没了）｜⚠ **带左括号** ⇒ 改名躲不过｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^\s+2\) _audit_why="[^"]*源文件读不了[^"]*" ;;$' 1 '接线门**按 rc=2 说原因**时必须**点名「源文件读不了」这一类**（⚠⚠⚨ **批 CH**：审计器读不了源文件 ⇒ 那些门项**根本没被审** ⇒ 盲区⇒ 与「缺 perl」同用 rc=2 ⇒ 门侧**必须把这一种也说清楚**⇒ 否则排障被带偏（批 BB：说明必须与实际行为一致））｜⚠ **整行锚定**（⚠ 用**有界通配**（字符类里不含双重引号）⇒ 不锁死整条文案⇒ 只锁「必须提到这一类」⇒ 改措辞不会假红）｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^trap ._ch_rc=\$\?; if \[ -s "\$STRIP_FAIL_FILE" \]; then echo [^;]*剥注释失败[^;]*; _ch_rc=1; fi; rm -f [^;]*; exit \$_ch_rc. EXIT$' 1 '判据层的**退出 trap 必须带剥注释失败的诊断**（⚠⚠⚨ **批 CH**：⚠⚠⚨ 实测的洞：段落 `ARCH_FAIL` **提前 exit** 时末尾的检查根本跑不到 ⇒ 诊断打不出来⇒ 门侧只报「出现 0 次（期望 N 次）」⇒ **真话被藏了**⇒ 诊断搬进 trap ⇒ 无论从哪退出都会打出来并点名那个文件）｜⚠ **整行锚定**（⚠ 措辞自由 ⇒ 改文案不会假红；⚠ 但**必须提到「剥注释失败」**）｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci.sh" '^trap ._ch_rc=\$\?; if \[ -s "\$STRIP_FAIL_FILE" \]; then echo [^;]*剥注释失败[^;]*; _ch_rc=1; fi; rm -f [^;]*; exit \$_ch_rc. EXIT$' 1 'CI 入口的**退出 trap 必须带剥注释失败的诊断**（⚠⚠⚨ **批 CH**：诊断在退出时必打 ⇒ 「✓ CI 门通过」永远打不出来）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'
arch_need_count "$SRC/scripts/ci-d2.sh" '^trap ._ch_rc=\$\?; if \[ -s "\$STRIP_FAIL_FILE" \]; then echo [^;]*剥注释失败[^;]*; _ch_rc=1; fi; rm -f [^;]*; exit \$_ch_rc. EXIT$' 1 '散值门的**退出 trap 必须带剥注释失败的诊断**（⚠⚠⚨ **批 CH**：诊断在退出时必打 ⇒ 「✓ D2 命中 0/0」永远打不出来）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CH**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CH 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CH 段门项全绿（审计器自己读不了源文件 ⇒ 指名道姓 + rc=2，不许当成「没问题」）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CI · 「未验证」不许被当成「通过」（从契约门内部到 CI 出口，全链路） ──────
#
# ⚠⚠⚨ **起因（实测坐实，不是推演）**：
#   批 CB 给契约门留了**专属退出码 3**（未验证）⇒ CI 侧也分诊了 0/3/其它
#   ⇒ 但 ⚠⚠⚨ **内层的 SKIP 根本没上报**：
#   契约门里 **14 处内层 SKIP**（客户端二进制缺席 / 打桩服务器没起来 /
#   GitHub API 不可达 / 没有 curl …）**只打印、不计数**
#   ⇒ 末尾判 `fail` ⇒ **exit 0**
#   ⇒ ⚠⚠⚨ 实测：客户端缺席时跑出「85 passed, **1 failed**, 9 unverified」
#      ⇒ 那 **9 组**既没算失败、也没算未验证 ⇒ 只要别的都过 ⇒ **exit 0**
#   ⇒ 而每条 SKIP 消息里都写着「本项**未验证**，不算通过」
#   ⇒ ⚠⚠⚨ **说法比门宽**（批 AA 教训）
#   ⇒ 且 CI 第 10 步收到 rc=3 只**打印**「不算通过」⇒ CI 继续
#      ⇒ 最后照样打「✓ CI 门通过」⇒ **假绿**（批 CB 的已知边界）
#
# ⚠⚠⚨ **洞 ②（取数失败落进「判通过」那一支 · 实测坐实）**：
#   `E2E_OUT` 取数失败 ⇒ `E2E_N=""` ⇒ `[ "" -eq 0 ]` 在 dash 里
#   报「Illegal number」并返回 **2** ⇒ `if` 判假 ⇒ 落到 elif
#   ⇒ `[ 0 -ne 0 ]` 假 ⇒ **else ⇒ 判通过**
#   ⇒ **取数失败被当成「没有问题」** ⇒ 假绿
#
# ⚠ **修法（只动判据层 ⇒ 零产品代码改动）**：
#   ① 契约门加**未验证计数器** `skip`；每个内层 SKIP ⇒ `skip=$((skip+1))`；
#   ② 末尾：`if [ "$skip" -ne 0 ] && [ "$fail" -eq 0 ]; then … exit 3; fi`
#      ⇒ ⚠ **失败优先**（真有失败 ⇒ 仍报 1 ⇒ 未验证不掩盖失败）
#      ⇒ ⚠ 该写法**不含 `fail=`** ⇒ 「写 fail 变量的行数」那条门不受影响；
#      ⇒ ⚠ 末尾判定行 `[ "$fail" -eq 0 ]` **原样保留** ⇒ 那条门也不受影响；
#   ③ 取数失败 ⇒ 先判空（`-z`）⇒ 走「没取到可比对的符号」那一支（判红）；
#   ④ CI 第 10 步：**rc=3 ⇒ 判红**；**引擎缺席 ⇒ 判红**
#      ⇒ 收掉批 CB 的已知边界：「SKIP 后 CI 仍绿」
#      ⇒ ⚠ 批 CB 已给契约门留了专属码 3 ⇒ 这一层能分清「未验证」与「失败」
arch_need_count "$SRC/scripts/contract-check.sh" '^pass=0; fail=0; skip=0$' 1 '契约门**必须有「未验证」计数器**（⚠⚠⚨ **批 CI**：⚠⚠⚨ 实测的洞：**14 处内层 SKIP**（客户端二进制缺席 / 打桩服务器没起来 / GitHub API 不可达 / 没有 curl …）**只打印、不计数** ⇒ 末尾判 `fail` ⇒ exit 0 ⇒ 「这些组**根本没验**」被当成「**通过**」⇒ 而每条消息里都写着「本项**未验证**，不算通过」⇒ **说法比门宽**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CI**'
arch_need_count "$SRC/scripts/contract-check.sh" '^    skip=\$\(\(skip\+1\)\)$' 4 '契约门**每个内层 SKIP 都必须计入未验证**（4 缩进那批，**恰好 4 处**）（⚠⚠⚨ **批 CI**：少一处 ⇒ 那一组未验证**又不计数** ⇒ 假绿）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CI**'
arch_need_count "$SRC/scripts/contract-check.sh" '^        skip=\$\(\(skip\+1\)\)$' 7 '契约门**每个内层 SKIP 都必须计入未验证**（8 缩进那批，**恰好 7 处**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CI**'
arch_need_count "$SRC/scripts/contract-check.sh" '^            skip=\$\(\(skip\+1\)\)$' 3 '契约门**每个内层 SKIP 都必须计入未验证**（12 缩进那批，**恰好 3 处**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CI**'
arch_need_count "$SRC/scripts/contract-check.sh" '^if \[ "\$skip" -ne 0 \] && \[ "\$fail" -eq 0 \]; then$' 1 '契约门**末尾必须按「未验证」判**（⚠⚠⚨ **批 CI**：有未验证 ⇒ **专属退出码 3**（批 CB 口径）⇒ 不许说通过；⚠ **失败优先**：真有失败 ⇒ 仍报 1）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CI**'
arch_need_count "$SRC/scripts/contract-check.sh" '^    if \[ -z "\$E2E_N" \] \|\| \[ "\$E2E_N" -eq 0 \]; then$' 1 '契约门**取数失败不许落进「判通过」那一支**（⚠⚠⚨ **批 CI**：⚠⚠⚨ 实测的洞：`E2E_OUT` 取数失败 ⇒ `E2E_N=""` ⇒ `[ "" -eq 0 ]` 在 dash 里报「Illegal number」并返回 **2** ⇒ `if` 判假 ⇒ 落到 elif ⇒ **else ⇒ 判通过**⇒ **取数失败被当成「没有问题」⇒ 假绿** ⇒ 修法：先判空）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CI**'
arch_need_count "$SRC/scripts/ci.sh" '^    echo "✗ 引擎契约门\*\*未验证\*\*：未找到 moongit\/deepgit（可设 DEEPGIT_BIN 指定）" >&2$' 1 'CI 第 10 步的**引擎缺席**支必须**判红**（⚠⚠⚨ **批 CI**：以前只打印「不算通过」⇒ CI 继续 ⇒ 最后照样打「✓ CI 门通过」⇒ **核心门根本没验，却说 CI 通过** ⇒ 假绿）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CI**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CI 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CI 段门项全绿（未验证不许被当成通过：契约门内层 SKIP 计数 + 末尾 exit 3 + CI 判红）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CJ · 「一次性盘点的数字」不许被当成事实 ──────────────────────────
#
# ⚠⚠⚨ **起因（实测坐实，不是推演）**：
#   批 CG / 批 CE / 批 CI 的结论都引用过「`scripts/` 下命令替换内带 `|| true`
#   的站点 **N** 处」这个数字 ⇒ 那个数字来自**一次性盘点脚本**（还放在 /tmp 里）
#   ⇒ **仓内没有任何东西能重算出它** ⇒ 数字不可复核；
#   ⇒ ⚠⚠⚨ **三个盘点器给出三个数**：
#      **24**（批 CI 原写；原盘点器**跨行合并把注释并进块**⇒ 跨度配对错乱
#             ⇒ 3 处**假阳性**）/ **26**（逐行 + **不剥注释**⇒ 多算注释里的）
#      / **21**（**真值**：剥注释 + 正确的 shell 词法 + 嵌套括号）
#   ⇒ **一次性盘点的数字不许被当成事实** ⇒ 本批把盘点搬进**仓内常驻脚本**
#     （`scripts/ci-true-audit.py`）⇒ 数字由**机器**算、**逐处**登记
#     （`scripts/ci-true-audit.baseline`）⇒ 每处还要写清**为什么可以留**。
#
# ⚠⚠⚨ **洞（真洞 · 逐处才发现 · 实测坐实）**：
#   `ci.sh` 的**分层纪律门**（判定层零 QWidget 头）原先是
#   `grep -rlE … "$SRC/src/logic" "$SRC/src/models" 2>/dev/null || true`
#   ⇒ 源文件对 grep **不可读** ⇒ grep **静默跳过** ⇒ `GW_HITS` 仍为空
#   ⇒ **分层纪律门放行** ⇒ **假绿**；
#   ⇒ ⚠⚠⚨ 同一个洞**在 `ci-d2.sh` 里已经被批 CD 堵上**（`find … ! -readable` 预检）
#     ⇒ **同一个洞堵一半比不堵更坏**（以为有门 ⇒ 实际没有）
#   ⇒ 修法（照批 CD 同款口径）：**扫描之前先验可读性** ⇒ 读不了 ⇒ 判失败。
#
# ⚠ **判定方向是双向红**（批 BH 纪律：恰好口径双向红）：
#   「实测有、登记册没有」⇒ 红（新增未登记）
#   「登记册有、实测没有」⇒ 红（登记册腐化 ⇒ 修好后请删那一行）
#
# ⚠⚠⚨ **门项正则一律由现抽实际行生成**（批 BS 纪律：绝不手写）
#
arch_need_count "$SRC/scripts/ci-true-audit.py" '^TRUE_AUDIT_EXPECTED_ROWS = 21$' 1 '登记册的**条数基线常量**必须在（⚠⚠⚨ 批 CJ：⚠ **整份清单被删/被改** ⇒ 盘点结果没人对 ⇒ 「一次性盘点的数字」又变成没人守的数字）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci-true-audit.py" '^    if len\(base\) != TRUE_AUDIT_EXPECTED_ROWS:$' 1 '登记册**条数必须恰好等于基线**（⚠⚠⚨ 批 CJ：批 BC 纪律「清单不许被删」+ 批 BB 纪律「恰好」⇒ 少一条就红 ⇒ 整份登记册被截短也红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci-true-audit.py" '^        if len\(parts\) != 6:$' 1 '登记册**每行必须恰好 6 段**（⚠⚠⚨ 批 CJ：⚠ 分隔符用 **TAB**（理由里要写 `|| true` ⇒ 用竖线分隔会把行劈开）⇒ 段数对不上 ⇒ 登记册**永远读不出来**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci-true-audit.py" '^        if not parts\[5\]\.strip\(\):$' 1 '登记册**每行必须写清理由**（⚠⚠⚨ 批 CJ：批 BN 纪律「逐条理由」⇒ 没有理由的登记 = 一条没人负责的例外）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci-true-audit.py" '^    missing = list\(\(cb - cg\)\.elements\(\)\)$' 1 '盘点必须判「**登记册有、实测没有**」这一侧（⚠⚠⚨ 批 CJ：⚠ **登记册腐化**方向 ⇒ 修好一处却忘了删登记册那行 ⇒ 白名单烂在仓里 ⇒ 下一个 `|| true` 直接被放过）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci-true-audit.py" '^    extra = list\(\(cg - cb\)\.elements\(\)\)$' 1 '盘点必须判「**实测有、登记册没有**」这一侧（⚠⚠⚨ 批 CJ：⚠ **新增未登记**方向 ⇒ 有人新加一处 `|| true` 却没登记 ⇒ 没人知道它吞了什么退出码）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci-true-audit.py" '^    selftest_strip_parity\(shs\)$' 1 '盘点脚本必须**跑抽取自检**（⚠⚠⚨ 批 CJ：批 CF 教训「**复用实现的方式本身要有自检**」⇒ 剥注释口径一旦漂移 ⇒ 盘点结果与门侧口径不同 ⇒ 数字又不可信）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci-true-audit.py" '^        return 1$' 1 '盘点脚本的**失败上报出口**（整行的 `return 1`）必须恰好 1 处｜⚠⚠⚨ **批 CA**｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci-true-audit.py" '^    sys\.exit\(main\(\)\)$' 1 '盘点脚本的**入口**必须把 `main()` 的返回值交给 `sys.exit`（否则返回值被丢弃 ⇒ rc 恒 0 ⇒ 盘点脚本**永远绿**）｜⚠⚠⚨ **批 CA**｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci-true-audit.py" '^    text = AUDIT\.strip_comments\(path\)$' 1 '盘点脚本**必须复用判据层自己的剥注释**（⚠⚠⚨ 批 CJ：批 CF 纪律「绝不复刻」⇒ 自己实现一份 ⇒ 两套口径 ⇒ 数字又不可信）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^if ! python3 "\$SRC/scripts/ci-true-audit\.py"; then$' 1 '接线门**必须真的跑一次盘点**（⚠⚠⚨ 批 CJ：⚠ 盘点脚本不被 CI 调用 ⇒ 它就是「又多了一份没人跑的断言」⇒ 批 BD 同款洞）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci.sh" '^_gw_unread="\$\(find "\$SRC/src/logic" "\$SRC/src/models" -type f ! -readable -print 2>/dev/null\)" \|\| _gw_find_rc=\$\?$' 1 '分层纪律门**必须在扫描前验可读性**（⚠⚠⚨ 批 CJ：⚠⚠⚨ **实测的洞**：源文件对 grep 不可读 ⇒ grep **静默跳过** ⇒ 分层纪律门**放行** ⇒ 假绿；⚠ 与批 CD 在 ci-d2.sh 里的洞**同款** ⇒ 那边堵了这边没堵 ⇒ **堵一半比不堵更坏**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci.sh" '^if \[ "\$_gw_find_rc" -ne 0 \] \|\| \[ -n "\$_gw_unread" \]; then$' 1 '分层纪律门在**有源文件不可读**时**必须判失败**（⚠⚠⚨ 批 CJ：⚠ **未验证不许被当成通过** ⇒ 判红而不是「当作没有违规」）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_need_count "$SRC/scripts/ci.sh" '^    CANVAS_FAIL=1    # ⚠⚠⚨ 批 CJ：不可读 ⇒ 判失败（末尾统一 exit 1 ⇒ 「✓ 图谱 Canvas 契约门通过」永远打不出来）$' 1 '分层纪律门在**有源文件不可读**时**必须真的置失败位**（⚠⚠⚨ 批 CJ：⚠ 判失败位被摘掉 ⇒ 末尾的 `exit 1` 不触发 ⇒ 门照样打「✓」）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CJ**'
arch_forbid "$SRC/scripts/ci-true-audit.py" 'sed -e' '盘点脚本**不许自己实现剥注释**（⚠⚠⚨ 批 CJ：⚠ 自己写一份 `sed -e` ⇒ 与判据层口径漂移 ⇒ 盘点数字又不可信 ⇒ **单一真相源**被绕过）｜⚠⚠⚨ **批 CJ**｜⚠ **期望 0 次** ⇒ 语义是「不许出现在任何位置」⇒ **显式豁免**（批 BN）'

# ⚠ 盘点脚本**必须真的被跑一次**（批 BD：多一份没人跑的断言 = 少一份断言）
if ! python3 "$SRC/scripts/ci-true-audit.py"; then
    ARCH_FAIL=1
fi

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CJ 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CJ 段门项全绿（一次性盘点的数字不许被当成事实：仓内常驻盘点 + 逐处带理由的登记册）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CK · 「未验证」不许被当成「通过」（**CI 自己这一层**） ────────────────
#
# ⚠⚠⚨ **起因（实测盘点 + 对照实验，不是推演）**：
#   盘点 `scripts/` 下所有「跳过/未验证」出口 ⇒ ⚠⚠⚨ **ci.sh 自己就有 6 处**
#   「**只打印、不计数**」：
#   ① `desktop-file-validate` 缺席（desktop 合法性**没验**）
#   ② `appstream-util` 缺席（metainfo 合法性**没验**）
#   ③ 没有 `dpkg-deb` ⇒ **deb 构建没跑**（⚠⚠⚨ **D7 达标的必经**）
#   ④ 没有 deb 产物 ⇒ **deb 布局验收没跑**（⚠ **D7 的准验收**）
#   ⑤ deb 布局验收**脚本自己报 SKIP**（rc=3）⇒ ⚠⚠⚨ **与批 CI 修过的第 10 步完全同款**
#   ⑥ agent 工具面门报 SKIP（rc=3）⇒ 同款
#   ⇒ 全部「只打印、不算失败」⇒ **CI 继续跑** ⇒ 最后照样打
#     「**✓ CI 门通过**」⇒ ⚠⚠⚨ **未验的组被当成「通过」** ⇒ **假绿**。
#   ⇒ ⚠⚠⚨ 旧立场写死在 ci.sh 第 12 步的注释里：「不算通过，但**不判失败**」
#     ⇒ 那个立场**已被本批收掉**（批 BB：说明必须与实际行为一致）。
#
# ⚠ **修法**（只动判据层 ⇒ 零产品代码改动）：
#   ① ci.sh 加**未验证计数器** `skip`；6 处跳过各 `skip=$((skip+1))`；
#   ② 末尾：`if [ "$skip" -ne 0 ]; then … exit 3; fi`
#      ⇒ **专属退出码 3**（与契约门、agent 工具面门同款口径，批 CB/CI）
#      ⇒ ⚠ **失败优先**：ci.sh 是 `set -e` 逐步执行 ⇒ 真失败**当场** exit 1
#        ⇒ 能走到末尾说明**没有真失败** ⇒ 这里只判「未验证」；
#   ③ 判定块必须**紧挨着**「✓ CI 门通过」**之前**
#      ⇒ 顺序反了 ⇒ 「✓」先打出来 ⇒ 未验的组**已经被说成通过**了。
#
# ⚠⚠⚨ **门项正则一律由现抽实际行生成**（批 BS 纪律：绝不手写）
#
arch_need_count "$SRC/scripts/ci.sh" '^skip=0$' 1 'CI 入口**必须有「未验证」计数器**（⚠⚠⚨ 批 CK：⚠⚠⚨ 实测的洞：ci.sh 自己就有 **6 处**「跳过/未验证」出口**只打印、不计数** ⇒ CI 继续 ⇒ 最后照样打「**✓ CI 门通过**」⇒ **未验的组被当成「通过」**⇒ 假绿）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CK**'
arch_need_count "$SRC/scripts/ci.sh" '^    skip=\$\(\(skip\+1\)\)$' 6 'CI 入口的**未验证计数点**（4 缩进那批，**恰好 6 处**）必须逐个计数（⚠⚠⚨ 批 CK：少一处 ⇒ 那一组未验证**又不计数** ⇒ 假绿；⚠ 4 缩进 = desktop-file-validate 缺席 / appstream-util 缺席 / 没有 dpkg-deb（**D7 必经**）/ 没有 deb 产物（**D7 准验收**）/ agent 工具面门报 SKIP / **Pillow 缺席（批 DG：assets 图标判据未验证）**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CK**'
arch_need_count "$SRC/scripts/ci.sh" '^        skip=\$\(\(skip\+1\)\)$' 2 'CI 入口的**未验证计数点**（8 缩进那批，**恰好 2 处**）必须计数（⚠⚠⚨ 批 CK：① deb 布局验收**脚本自己报 SKIP**（rc=3）那一支 ⇒ ⚠⚠⚨ 与批 CI 修过的第 10 步**完全同款** ⇒ 以前只打印「不算通过」⇒ CI 继续 ⇒ 假绿；⚠⚠⚨ 批 CL：② deb 构建**脚本自己报 SKIP**（rc=3）那一支 ⇒ 同款 ⇒ 以前 build-deb.sh 那边**只打印**⇒ exit 0 ⇒ CI 照样打「✓ deb 构建通过」⇒ **说法比门宽**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CK**'
arch_need_count "$SRC/scripts/ci.sh" '^if \[ "\$skip" -ne 0 \]; then$' 1 'CI 入口**末尾必须按「未验证」判**（⚠⚠⚨ 批 CK：有任何一组没验 ⇒ **专属退出码 3**⇒ 判红 ⇒ 不许说通过；⚠ **失败优先**：ci.sh 是 `set -e` 逐步执行 ⇒ 真失败**当场** exit 1 ⇒ 能走到这里说明没有真失败）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CK**'
arch_need_count "$SRC/scripts/ci.sh" '^    exit 3$' 1 'CI 入口的「未验证」必须用**专属退出码 3**（⚠⚠⚨ 批 CK：与契约门、agent 工具面门**同款口径**，批 CB/CI）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CK**'
arch_need_ml "$SRC/scripts/ci.sh" 'SKIP: desktop-file-validate 未安装（装 desktop-file-validate 包后此门生效）"[[:space:]]+skip=\$\(\(skip\+1\)\)' 'desktop-file-validate 缺席那一处**必须紧跟计数**（⚠⚠⚨ 批 CK：⚠ 少了计数 ⇒ 「desktop 合法性没验」被当成「通过」）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CK**'
arch_need_ml "$SRC/scripts/ci.sh" 'SKIP: appstream-util 未安装（README 决策 69 的硬门随工具到位生效）"[[:space:]]+skip=\$\(\(skip\+1\)\)' 'appstream-util 缺席那一处**必须紧跟计数**（⚠⚠⚨ 批 CK：⚠ 少了计数 ⇒ 「metainfo 合法性没验」被当成「通过」）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CK**'
arch_need_ml "$SRC/scripts/ci.sh" '‣ SKIP deb 构建：没有 dpkg-deb"[[:space:]]+skip=\$\(\(skip\+1\)\)' '没有 dpkg-deb 那一处**必须紧跟计数**（⚠⚠⚨ 批 CK：⚠⚠⚨ **deb 构建是 D7 达标的必经**⇒ 没构建 ⇒ 后面的「deb 布局验收」也跟着没有产物 ⇒ **两组都没验** ⇒ 假绿）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CK**'
arch_need_ml "$SRC/scripts/ci.sh" '‣ SKIP deb 布局验收：没有 deb 产物（本组\*\*未验证\*\*，不算通过）"[[:space:]]+skip=\$\(\(skip\+1\)\)' '没有 deb 产物那一处**必须紧跟计数**（⚠⚠⚨ 批 CK：⚠ **deb 布局验收是 D7 的准验收**⇒ 没验 ⇒ 假绿）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CK**'
arch_need_ml "$SRC/scripts/ci.sh" '‣ SKIP deb 布局验收：本组\*\*未验证\*\*（脚本自己报了 SKIP）——不算通过" >&2[[:space:]]+skip=\$\(\(skip\+1\)\)' 'deb 布局验收**脚本自己报 SKIP**（rc=3）那一支**必须紧跟计数**（⚠⚠⚨ 批 CK：⚠⚠⚨ 与批 CI 修过的第 10 步**完全同款**）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CK**'
arch_need_ml "$SRC/scripts/ci.sh" '‣ SKIP agent 工具面门：引擎缺席或版本太老（无 deprecated 标记）"[[:space:]]+skip=\$\(\(skip\+1\)\)' 'agent 工具面门报 SKIP（rc=3）那一处**必须紧跟计数**（⚠⚠⚨ 批 CK：⚠⚠⚨ 与批 CI 修过的第 10 步**完全同款**）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CK**'
arch_need_ml "$SRC/scripts/ci.sh" 'exit 3[[:space:]]+fi[[:space:]]+echo "✓ CI 门通过：快照与 git 基线逐字节一致（无未提交的视觉改动）' '「未验证 ⇒ 判红」那块**必须紧挨着**「✓ CI 门通过」**之前**（⚠⚠⚨ 批 CK：⚠⚠⚨ 顺序反了 ⇒ 「✓ CI 门通过」先打出来 ⇒ 未验的组**已经被说成通过**了 ⇒ 假绿）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CK**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CK 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CK 段门项全绿（未验证不许被当成通过：CI 自己的 6 处跳过必须计数 + 末尾 exit 3）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CL · 「未验证」不许被当成「通过」（**子脚本层**：打包脚本 / 冒烟脚本） ──
#
# ⚠⚠⚨ **起因（实测盘点 + 逐处人工判，不是推演）**：
#   盘点判据层所有脚本的「跳过 / 未验证」出口 ⇒ 68 处带「未验证」字样的打印行
#   ⇒ ⚠⚠⚨ 逐处判（批 CJ 纪律：危险方向靠人工判）⇒ **3 处真洞**：
#   ① `build-deb.sh` 的第 2h 步「apt 查不到候选版本」⇒ **只打印、不计数**
#   ② `build-deb.sh` 的第 2h 步「没有 apt-cache」⇒ **只打印、不计数**
#   ③ `smoke.sh` 的「引擎缺席」⇒ **只打印** ⇒ 脚本 exit 0 ⇒ 冒烟说「全绿」
#   ⇒ 全部「只打印」⇒ 脚本 **exit 0** ⇒ CI 第 11 步照样打
#     「**✓ deb 构建通过（依赖清单自洽 + …）**」⇒ ⚠⚠⚨ **说法比门宽**（批 AA）
#
# ⚠⚠⚨ **另有一处码值语义被顶替（批 CC 纪律）**：
#   `smoke.sh` 以前是 `bash contract-check.sh || exit 1`
#   ⇒ 契约门报「未验证」(**3**) 时**被压成 1（失败）**
#   ⇒ 调用方**分不出**「根本没验过」与「验了但没过」⇒ 本批一并收口
#
# ⚠⚠⚨ **为什么 build-deb.sh 不用 die**：die 调用点有门钉住**恰好 23 处**（批 BU）
#   ⇒ 加 die 会动那条清单门 ⇒ 这里用**独立计数器** ⇒ 互不干扰。
#
# ⚠⚠⚨ **门项正则一律由现抽实际行生成**（批 BS 纪律：绝不手写）
#
arch_need_count "$SRC/scripts/build-deb.sh" '^skip=0$' 1 '打包脚本**必须有「未验证」计数器** `skip`（⚠⚠⚨ 批 CL：⚠⚠⚨ 实测的洞：build-deb.sh 第 2h 步有 **2 处**「未验证」只**打印**（apt 查不到候选版本 / 没有 apt-cache）⇒ 脚本**继续跑完** ⇒ 末尾照样打「**✓ 已生成**」⇒ **exit 0** ⇒ CI 第 11 步打印「**✓ deb 构建通过**」⇒ ⚠⚠⚨ **说法比门宽**（批 AA 教训））｜⚠ **整行锚定**｜⚠⚠⚨ **批 CL**'
arch_need_count "$SRC/scripts/build-deb.sh" '^        skip=\$\(\(skip\+1\)\)$' 1 '打包脚本的**未验证计数点**（8 缩进那批，**恰好 1 处**）必须计数（⚠⚠⚨ 批 CL：那是「apt 查不到候选版本」那一支 ⇒ 少一处 ⇒ 那一项**不再被判红**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CL**'
arch_need_count "$SRC/scripts/build-deb.sh" '^    skip=\$\(\(skip\+1\)\)$' 1 '打包脚本的**未验证计数点**（4 缩进那批，**恰好 1 处**）必须计数（⚠⚠⚨ 批 CL：那是「没有 apt-cache」那一支 ⇒ 少一处 ⇒ 那一项**不再被判红**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CL**'
arch_need_count "$SRC/scripts/build-deb.sh" '^if \[ "\$skip" -ne 0 \]; then$' 1 '打包脚本**末尾必须按「未验证」判**（⚠⚠⚨ 批 CL：⚠ 退出码 **3** = 未验证（SKIP）⇒ 与契约门、agent 工具面门、CI 第 10/11/12/13 步**同款口径**，批 CB / CI / CK ⇒ 调用方能把它与「通过（0）」和「失败（其它非 0）」分开）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CL**'
arch_need_count "$SRC/scripts/build-deb.sh" '^    exit 3$' 1 '打包脚本的「未验证」必须用**专属退出码 3**（⚠⚠⚨ 批 CL：⚠ 不用 `die` —— die 调用点有门钉住**恰好 23 处**（批 BU）⇒ 加 die 会动那条清单门 ⇒ 这里用**独立计数器** ⇒ 互不干扰）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CL**'
arch_need_ml "$SRC/scripts/build-deb.sh" '‣ SKIP：apt 查不到候选版本（本机可能没配源 / 离线）—— 这一项\*\*未验证\*\*，不算通过"[[:space:]]+skip=\$\(\(skip\+1\)\)' '打包脚本「apt 查不到候选版本」那一处**必须紧跟计数**（⚠⚠⚨ 批 CL：⚠ 这一支是**有意不误红**的（无法区分「包真不存在」与「本机没配源/离线」，批 AE 的设计）⇒ 所以**不能**判失败 ⇒ 但也**不能**只打印 ⇒ 必须**计数** ⇒ 末尾专属码 3）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CL**'
arch_need_ml "$SRC/scripts/build-deb.sh" '‣ SKIP：没有 apt-cache —— 这一项\*\*未验证\*\*，不算通过"[[:space:]]+skip=\$\(\(skip\+1\)\)' '打包脚本「没有 apt-cache」那一处**必须紧跟计数**（⚠⚠⚨ 批 CL：同款：不能误红 ⇒ 但必须计数 ⇒ 末尾专属码 3）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CL**'
arch_need_ml "$SRC/scripts/build-deb.sh" 'exit 3[[:space:]]+fi[[:space:]]+echo "✓ 已生成 \$DEB_PATH' '打包脚本的「未验证 ⇒ 判红」那块**必须紧挨着**「**✓ 已生成**」**之前**（⚠⚠⚨ 批 CL：⚠ 顺序反了 ⇒ 「✓ 已生成」先打出来 ⇒ 这一项**已经被说成通过**了 ⇒ 假绿；⚠ 与批 CK 的「必须紧挨着「✓ CI 门通过」之前」**同款口径**）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CL**'
arch_need_count "$SRC/scripts/smoke.sh" '^    exit 3$' 1 '冒烟脚本「**引擎缺席 ⇒ 未验证**」必须用**专属退出码 3**（⚠⚠⚨ 批 CL：⚠⚠⚨ 实测的洞：以前这一支**只打印** ⇒ 脚本 exit 0 ⇒ 冒烟脚本说「全绿」⇒ **未验证被当成通过** ⇒ 与契约门本体的口径**不一致**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CL**'
arch_need_count "$SRC/scripts/smoke.sh" '^        exit 3$' 1 '冒烟脚本「**契约门未验证 ⇒ 原样传出**」必须用**专属退出码 3**（⚠⚠⚨ 批 CL：⚠⚠⚨ 以前是 `bash contract-check.sh || exit 1` ⇒ 契约门报「未验证」(**3**) 时**被压成 1（失败）** ⇒ ⚠⚠⚨ **退出码的码值语义被顶替**（批 CC 纪律）⇒ 调用方**分不出**「根本没验过」与「验了但没过」）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CL**'
arch_need_ml "$SRC/scripts/smoke.sh" 'SKIP contract-check：moongit/deepgit 均不在（引擎未安装），本轮冒烟不算全绿——如实记录"[[:space:]]+exit 3' '冒烟脚本「引擎缺席 ⇒ 只打印」那一处**必须紧跟** `exit 3`（⚠⚠⚨ 批 CL：⚠ 少了退出码 ⇒ 脚本 exit 0 ⇒ 假绿）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CL**'
arch_need_ml "$SRC/scripts/smoke.sh" 'bash "\$SRC/scripts/contract-check\.sh" \|\| _cc_rc=\$\?[[:space:]]+if \[ "\$_cc_rc" -eq 3 \]; then' '冒烟脚本调用契约门那一行**必须接住退出码**并**紧跟** rc=3 分诊（⚠⚠⚨ 批 CL：⚠⚠⚨ `|| exit 1` ⇒ **码值语义被顶替**（批 CC）⇒ 现在 `|| _cc_rc=$?` ⇒ 3 原样传出 ⇒ 其它非 0 ⇒ exit 1）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CL**'
arch_need_ml "$SRC/scripts/ci.sh" '‣ SKIP deb 构建：本组\*\*未验证\*\*（脚本自己报了 SKIP）——不算通过" >&2[[:space:]]+skip=\$\(\(skip\+1\)\)' 'ci.sh「deb 构建脚本自报 SKIP」那一处**必须紧跟计数**（⚠⚠⚨ 批 CL：⚠⚠⚨ build-deb.sh 现在用**专属码 3** 报「未验证」 ⇒ CI 第 11 步**分诊** rc=3 ⇒ **计入 skip** ⇒ 末尾判红 ⇒ 与第 10 步（契约门，批 CB/CI）、第 12 步（deb 布局验收，批 CC）**同款口径**）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CL**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CL 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CL 段门项全绿（未验证不许被当成通过：打包脚本 / 冒烟脚本的未验证出口必须计数 + 专属码 3）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CM · 「未验证出口」的盘点搬进仓内常驻脚本 + 逐组带理由的登记册 ──
#
# ⚠⚠⚨ **起因（批 CL 实测坐实，不是推演）**：
#   批 CK / 批 CL 的结论都引用「判据层有 **N 处**『未验证 / 跳过』提示」
#   ⇒ 那个数字来自**一次性盘点脚本**（放在 /tmp 里）
#   ⇒ ⚠⚠⚨ **仓内没有任何东西能重算出它** ⇒ 数字不可复核；
#   ⇒ 且实测：批 CL 的**修复本身**又新增了带「未验证」字样的提示消息
#   ⇒ 「**修一次，数字就涨**」⇒ 「N 处未验证出口」这个说法**本身就不可靠**。
#
# ⚠⚠⚨ **口径（机器可判 · 写死在盘点脚本里 · 门项整行锚定那些定义行）**：
#   · 站点 = **打印行**（echo/printf/print）且含未验证关键词，且不在排除表里；
#   · 排除表**四类**（每类都有实测依据）：成功消息（✓）/ 步骤标题（›）/
#     辅助提示（引号内首个非空白是 ⇒）/ 成功汇总行（含 `passed,`）；
#   · 分类两类：`失败上报`（含 ✗ ⇒ 已判红）/ `跳过提示`（其余 ⇒ 只打印）。
#
# ⚠⚠⚨ **登记册按 (文件, 分类) 聚合计数，不按行登记**（刻意的取舍）：
#   · 按行登记 ⇒ 身份含行号或文案 ⇒ **改一句文案就漂** ⇒ **假红**
#     ⇒ 批 BS 纪律：**假红比假绿更坏**；
#   · 记**处数** ⇒ 改文案不漂、中间插入不漂，**只有数量变了才红**
#     ⇒ 而数量变了**正是**要人看一眼的时候；
#   · ⚠⚠⚨ **代价（如实记）**：**组级理由** ⇒ 「这一组里某一处没判红」
#     **机器看不出来** ⇒ ⚠ 这是本批**最弱的一环**（批 CJ 同款纪律）。
#
# ⚠⚠⚨ **口径数的是「提示行」，不是「逻辑出口数」**
#   ⇒ 一处逻辑出口可能占 1~2 行 ⇒ 处数**大于**出口数 ⇒ 刻意为之。
#
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^UNVERIFIED_EXPECTED_ROWS = 21$' 1 '盘点脚本**必须有「登记册条数基线」常量**（⚠ 批 BC：清单不许被删 ⇒ **恰好**）｜⚠⚠⚨ **批 CX**：登记册加了「未验证逻辑出口」那一类 ⇒ 条数基线 15 → 21（⚠ **同一个数字记三处**的机制照旧）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**｜⚠⚠⚨ **批 CQ：登记册 14 → 15 行**（批 CQ 给审计器新增了两处「未验证/跳过」提示 ⇒ **必须显式登记** ⇒ 批 CM 的双向红）'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^BASELINE = os\.path\.join\(SCRIPTS, "ci-unverified-audit\.baseline"\)$' 1 '盘点脚本的**登记册路径常量**必须在（⚠ 路径写错 ⇒ 读不到登记册 ⇒ 盘点无处对照 ⇒ **未验证不许被当成通过**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^UNVERIFIED_KEYWORDS = r"SKIP\|未验证\|不算通过\|跳过\|无法验证\|not verified"$' 1 '盘点脚本的**未验证关键词定义行**必须在（⚠⚠⚨ 批 CM：⚠ 这是**口径** ⇒ 改宽了 ⇒ 把普通提示也算成「未验证出口」⇒ 登记册全线失准 ⇒ 改窄了 ⇒ 新洞看不见 ⇒ **口径必须被门钉住**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^UNVERIFIED_EXCLUDE_OK = "✓"$' 1 '盘点脚本的**排除表·成功消息**那一行必须在（⚠⚠⚨ 批 CM：⚠ 实测的误报 —— 「✓ 批 CL 段门项全绿（未验证不许被当成通过…）」是**成功汇总** ⇒ 不排除 ⇒ **修一次数字就涨** ⇒ 数字不可信）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^UNVERIFIED_EXCLUDE_TITLE = "›"$' 1 '盘点脚本的**排除表·步骤标题**那一行必须在（⚠ 步骤打点「› N/15 …」不是出口）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^UNVERIFIED_EXCLUDE_HINT = "⇒"$' 1 '盘点脚本的**排除表·辅助提示**那一行必须在（⚠ 紧跟在失败上报后面的「⇒ …」说明行本身**不构成**出口）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^UNVERIFIED_EXCLUDE_SUMMARY = "passed,"$' 1 '盘点脚本的**排除表·成功汇总行**那一行必须在（⚠ 「──── N passed, N failed, N unverified ────」是**成功汇总** ⇒ 不是出口）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^UNVERIFIED_PRINT_RE = r"\^\\s\*\(echo\|printf\|print\)\\b"$' 1 '盘点脚本的**打印行判定正则**必须在（⚠⚠⚨ 批 CM：⚠ 必须同时认 shell 的 `echo`/`printf` **与** python 的 `print` ⇒ 否则 python 侧判据脚本的「未验证」提示**完全不在盘点范围内** ⇒ **盲区**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^UNVERIFIED_HINT_RE = r"\^\\s\*\(\?:echo\|printf\)\\s\+\\"\?\\s\*⇒"$' 1 '盘点脚本的**辅助提示判定正则**必须在（⚠⚠⚨ 批 CM 实测踩过：⚠ 必须按**「引号内首个非空白字符」**判 ⇒ 按「整行以 ⇒ 开头」判 ⇒ 实际行是 `echo "  ⇒ …"` ⇒ 开头是 `echo` ⇒ **排除规则静默失效** ⇒ 多算了 3 行）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^        if len\(parts\) != 4:$' 1 '登记册**每行必须恰好 4 段**（文件|分类|处数|理由）⇒ 段数不对 ⇒ 读不出来 ⇒ 登记册永远对不上 ⇒ **假红**｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^        if not n\.strip\(\)\.isdigit\(\) or int\(n\) <= 0:$' 1 '登记册的**处数必须是正整数**（0 处 ⇒ 登记腐化 ⇒ 该删那一行）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^        if not why\.strip\(\):$' 1 '登记册**每行必须写清理由**（⚠⚠⚨ 机器只校验「非空」⇒ 「理由写得对不对」**机器判不了** ⇒ **危险方向靠人工**（批 CJ 同款纪律））｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^    if len\(rows\) != UNVERIFIED_EXPECTED_ROWS:$' 1 '登记册**条数必须恰好等于基线常量**（⚠ 批 BC：清单不许被删）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^    if missing:$' 1 '盘点必须判「**实测有、登记册没有**」（新增未登记 ⇒ **红** ⇒ 必须显式登记 + 写理由）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^    if dead:$' 1 '盘点必须判「**登记册有、实测没有**」（登记册腐化 ⇒ **红** ⇒ 修好后请删那一行）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^    if drifted:$' 1 '盘点必须判「**处数对不上**」（同一 (文件, 分类) 的处数变了 ⇒ **红** ⇒ 新增了一处「未验证」提示 ⇒ 要人看一眼）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^    HELPER\.selftest_strip_parity\(files\)$' 1 '盘点脚本**必须跑抽取自检**（批 CF/CH 教训：「复用实现的方式本身要有自检」⇒ 剥注释口径漂移当场红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^        return 1$' 1 '盘点脚本的**失败上报出口**（`return 1`）必须恰好 1 处（批 CA 口径：失败必须真的报出去 ⇒ 少一处 ⇒ 这个脚本的失败**静默**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^    sys\.exit\(main\(\)\)$' 1 '盘点脚本的**入口**必须把 `main()` 的返回值交给 `sys.exit`（否则返回值被丢弃 ⇒ rc 恒 0 ⇒ 盘点**永远绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^if ! python3 "\$SRC/scripts/ci-unverified-audit\.py"; then$' 1 '接线门**必须真的跑一次盘点**（⚠ 批 BD 纪律：「多了一份没人跑的断言」与「少了一份断言」是同一个洞的两头 ⇒ 从**集合**这一层堵）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CM**'
arch_forbid "$SRC/scripts/ci-unverified-audit.py" '^[[:space:]]*def strip_comments' '盘点脚本**不许自己实现剥注释**（⚠⚠⚨ 批 CF 纪律：口径单一真相源 ⇒ 必须**复用**判据层自己的实现（这里复用 `ci-true-audit.py` → `ci-wiring-audit.py`）⇒ 自己写一份 ⇒ 两边口径可能不同 ⇒ 盘点结果不可信）｜⚠⚠⚨ **批 CM**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CM 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CM 段门项全绿（未验证出口的盘点搬进仓内常驻脚本 + 逐组带理由的登记册）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CN · 「没有 perl ⇒ 这道门没跑」必须**判红**（不许回退成 SKIP 口径）──
#
# ⚠⚠⚨ **起因（批 CM 登记册里明写「建议下一批收」，不是推演）**：
#   `ci-wiring.sh` 有两处「没有 perl ⇒ **显式 SKIP（不算通过）**」
#   ⇒ 那是**批 CB / CC 之前的旧口径**（工具坏了 ⇒ 只打印 ⇒ 继续 ⇒ 绿）；
#   ⇒ ⚠ 以前它们只是**碰巧**不可达（脚本顶部 preflight「没有 perl ⇒ exit 1」先兜住）；
#   ⇒ ⇒ **顶部 preflight 一旦被摘掉**（或 perl 中途消失）
#     ⇒ 这两处就**静默放行 ⇒ 假绿**。
#
# ⚠⚠⚨ **本批做两件事**：
#   ① 那两处改成**判红**（`ARCH_FAIL=1` + `return 1`）⇒ 口径与批 CB/CC/BI 统一；
#   ② ⚠ **给顶部 preflight 本身加门** ⇒ 它是那两处的唯一活路
#     ⇒ 它不许被摘掉（⚠ **实测：它此前没有任何门** ⇒ 摘掉它没人发现）。
#
# ⚠ 门项正则**现抽**（批 BS）：preflight 的第 1 / 3 / 4 行照抄实际行，
#   第 2 行只钉结构（`echo "✗ 没有 perl…" >&2`）⇒ 改文案不假红、删行必红。
#
arch_need_ml "$SRC/scripts/ci-wiring.sh" 'command -v perl >/dev/null 2>&1 \|\| \{[[:space:]]+echo "✗ 没有 perl[^"]*" >&2[[:space:]]+exit 1[[:space:]]+\}' '判据层**顶部**的「没有 perl ⇒ 判失败」preflight **整块不许被摘掉**（⚠⚠⚨ 批 CN：⚠ **实测：它此前没有任何门** ⇒ 它是 `arch_forbid_han` / `arch_forbid_text_dup` 那两处「没有 perl ⇒ 判红」的**唯一活路** ⇒ **摘掉它 ⇒ 那两处就静默放行 ⇒ 假绿** ⇒ 现在它自己也被门盯住）｜⚠ **跨行锚定**（⚠ 压行后匹配 ⇒ 跨行形态不变）｜⚠⚠⚨ **批 CN**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CN 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CN 段门项全绿（没有 perl ⇒ 这道门没跑 ⇒ 必须判红；顶部 preflight 也不许被摘）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CO · 门项行的「实参数个数」必须与门型签名对得上（不许一行藏两条门）──
#
# ⚠⚠⚨ **起因（实测，不是推演）**：
#   `ci-wiring.sh` 里有**一行**把**两条门粘在一起**
#   （前一条的说明文字后面**直接**接了后一条 ⇒ 中间连空格都没有）
#   ⇒ shell 解析时后一条被**并进前一条的 label**
#   ⇒ ⚠⚠⚨ **后一条从来没被执行过**
#   ⇒ 而它盯的形态**早已不存在**（批 CL 改掉了）⇒ 它真跑起来**就该是红的**
#   ⇒ ⚠⚠⚨ **CI 一直是假绿** ⇒ 且批 CL 的负控**定位串命中 2 条**却只跑了其中一条。
#
# ⚠⚠⚨ **结构性兜底**：审计器新增「门项行的**实参数个数**必须与门型签名对得上」
#   ⇒ 实参数个数对不上 ⇒ 那行**藏着东西** ⇒ 报（rc=2「盲区」那一支）。
#   ⇒ ⚠ 门型签名**现抽** `ci-wiring.sh` 的函数定义（批 AV 纪律：不复刻）
#     ⇒ 定长门型必须**恰好**相等；可选参（`${N:-…}`）/ 变参（`shift`）允许多传。
#
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def check_gate_arity\(\):$' 1 '审计器的**「门项行实参数个数」检查函数**必须在（⚠⚠⚨ 批 CO：⚠ **实测的洞**：`ci-wiring.sh` 里有一行把**两条门粘在一起** ⇒ 后一条被并进前一条的 label ⇒ **它从来没被执行过** ⇒ 而它盯的形态早已不存在 ⇒ 它真跑起来就该是红的 ⇒ **CI 一直是假绿** ⇒ ⇒ 这个检查是**结构性**的兜底）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CO**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^    arity_bad = check_gate_arity\(\)$' 1 '审计器的**「门项行实参数个数」检查必须真的被调用**（⚠ 只定义不调用 ⇒ 等于没有 ⇒ 删掉调用点 ⇒ 这条门红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CO**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CO 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CO 段门项全绿（门项行的实参数个数必须与门型签名对得上；不许一行藏两条门）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CP · 判据层「先红遮后红」不许再遮 ───────────────────────────────────
# ⚠⚠⚨ **实测的洞（批 CP 的起因，不是推演）**：段级 trailer 原来长这样：
#     if [ "$ARCH_FAIL" -ne 0 ]; then
#         echo "✗ 接线门失败：批 X 段有门项红（上面带 ✗ 的行）" >&2
#         exit 1              ← ⚠⚠⚨ **提前退出**
#     fi
#   ⇒ `ARCH_FAIL` 是**全局**的 ⇒ **任何一段红了，后面每一段的 trailer 都会 exit**
#     ⇒ ⚠⚠⚨ **实测：540/1017 条门项根本没跑**（只跑了 477 条）
#     ⇒ 排障被迫「改一个 ⇒ 跑一次 ⇒ 再改一个」⇒ 一次只看得见一个洞。
#   ⇒ 现在：段级 trailer **只记红不退出**（`ARCH_ANY_FAIL=1`）⇒ 全部门项都跑完
#     ⇒ 末尾**统一**判红（退出码语义**不变**：红 = 1）⇒ 一次看得见**全部**洞。
#   ⇒ ⚠ 段级 `ARCH_FAIL` 现在是**段内作用域**（每段末清零）⇒ 段归属不失真。
#   ⇒ ⚠ 盘点脚本那一处 `exit 1`（批 CM 加的）**同款** ⇒ 也收了
#     ⇒ 盘点**自己成段**（诊断不许失真：它的红不许落到「接线门」段头上）。
#   ⇒ ⚠ 顶部自检也**自己成段**（同款：它的红不许混进后面任何一段的归属里）。
arch_need_count "$SRC/scripts/ci-wiring.sh" '^ARCH_ANY_FAIL=0$' 1 '判据层的**全局红过标志**的声明必须在（⚠⚠⚨ **批 CP**：段级 trailer 不再提前 exit ⇒ 末尾统一按它判红 ⇒ 它被摘 ⇒ **红也不报了** ⇒ **假绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CP**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^\s+if \[ "\$_strip_rc" -ne 0 \] && \[ "\$_strip_rc" -ne 141 \]; then$' 2 '剥注释的**失败判定必须容忍 141**（SIGPIPE = 消费者**提前收工**）—— ⚠⚠⚨ **批 CP 实测的洞**：以前把 141 也当成「工具坏了」⇒ 记标记 ⇒ 末尾判红 ⇒ ⚠⚠⚨ **假红**（批 BS 纪律：假红比假绿更坏 ⇒ 逼人把承诺改弱）⇒ ⚠⚠⚨ **引爆点**：`arch_need_count_in_fn` 的 awk 读完函数体就 `exit` ⇒ sed 还在写 ⇒ 被 SIGPIPE 打断 ⇒ ⇒ **门项文件越大越容易触发**（时间炸弹）｜⚠ **整行锚定**｜⚠ 恰好 2 处（sed 支 + perl 支各一处）｜⚠⚠⚨ **批 CP**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^\s+ARCH_ANY_FAIL=1$' 57 '每个段级 trailer **都要记全局红过**（恰好 57 处）—— ⚠⚠⚨ **批 CP**：少一处 ⇒ 那个段的失败**被吞掉** ⇒ 末尾统一判红时看不见 ⇒ **假绿**（⚠ 与「段末清零」那条**配对**：清零 57 处 ⇒ 记红也必须 57 处 ⇒ 差恒为 0；⚠⚠⚨ **批 CR**：批 CR 段新增 1 处 ⇒ 41 → 42；⚠⚠⚨ **批 CS**：批 CS 段新增 1 处 ⇒ 42 → 43；⚠⚠⚨ **批 CT**：批 CT 段新增 1 处 ⇒ 43 → 44；⚠⚠⚨ **批 CU**：批 CU 段新增 1 处 ⇒ 44 → 45；⚠⚠⚨ **批 CV**：批 CV 段新增 1 处 ⇒ 45 → 46；⚠⚠⚨ **批 CW**：批 CW 段新增 1 处 ⇒ 46 → 47；⚠⚠⚨ **批 CX**：批 CX 段新增 1 处 ⇒ 47 → 48；⚠⚠⚨ **批 CY**：批 CY 段新增 1 处 ⇒ 48 → 49；⚠⚠⚨ **批 CZ**：批 CZ 段新增 1 处 ⇒ 49 → 50；⚠⚠⚨ **批 DA**：批 DA 段新增 1 处 ⇒ 50 → 51；⚠⚠⚨ **批 DB**：批 DB 段新增 1 处 ⇒ 51 → 52；⚠⚠⚨ **批 DC**：批 DC 段新增 1 处 ⇒ 52 → 53；⚠⚠⚨ **批 DD**：批 DD 段新增 1 处 ⇒ 53 → 54；⚠⚠⚨ **批 DE**：批 DE 段新增 1 处 ⇒ 54 → 55；⚠⚠⚨ **批 DF**：批 DF 段新增 1 处 ⇒ 55 → 56）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CP**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^ARCH_FAIL=0$' 58 '判据层失败位的**声明 + 每段末清零**（恰好 58 处 = 1 处声明 + 57 处段末清零；⚠⚠⚨ **批 CR**：批 CR 段新增 1 处 ⇒ 42 → 43；⚠⚠⚨ **批 CS**：批 CS 段新增 1 处 ⇒ 43 → 44；⚠⚠⚨ **批 CT**：批 CT 段新增 1 处 ⇒ 44 → 45；⚠⚠⚨ **批 CU**：批 CU 段新增 1 处 ⇒ 45 → 46；⚠⚠⚨ **批 CV**：批 CV 段新增 1 处 ⇒ 46 → 47；⚠⚠⚨ **批 CW**：批 CW 段新增 1 处 ⇒ 47 → 48；⚠⚠⚨ **批 CX**：批 CX 段新增 1 处 ⇒ 48 → 49；⚠⚠⚨ **批 CY**：批 CY 段新增 1 处 ⇒ 49 → 50；⚠⚠⚨ **批 CZ**：批 CZ 段新增 1 处 ⇒ 50 → 51；⚠⚠⚨ **批 DA**：批 DA 段新增 1 处 ⇒ 51 → 52；⚠⚠⚨ **批 DB**：批 DB 段新增 1 处 ⇒ 52 → 53；⚠⚠⚨ **批 DC**：批 DC 段新增 1 处 ⇒ 53 → 54；⚠⚠⚨ **批 DD**：批 DD 段新增 1 处 ⇒ 54 → 55；⚠⚠⚨ **批 DE**：批 DE 段新增 1 处 ⇒ 55 → 56；⚠⚠⚨ **批 DF**：批 DF 段新增 1 处 ⇒ 56 → 57）—— ⚠⚠⚨ **批 CP**：少一处段末清零 ⇒ 那个段的失败**污染后面所有段** ⇒ 段归属失真（诊断被带偏）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CP**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^if \[ "\$ARCH_ANY_FAIL" -ne 0 \]; then$' 1 '判据层**末尾必须统一按全局红过判红**（恰好 1 处）—— ⚠⚠⚨ **批 CP**：段级 trailer 不再提前 exit ⇒ 全部门项都跑完 ⇒ 末尾这一句是**唯一的「红 ⇒ 退出」通路** ⇒ 摘掉 ⇒ 明明有红却 **exit 0** ⇒ **假绿**｜⚠ **整行锚定**｜⚠⚠⚨ **批 CP**'
arch_forbid_ml "$SRC/scripts/ci-wiring.sh" 'if \[ "\$ARCH_FAIL" -ne 0 \]; then[^;]*>&2[[:space:]]+exit 1' '段级 trailer **不许再提前 exit**（⚠⚠⚨ **批 CP**：提前 exit ⇒ 一处红遮住后面所有门项 ⇒ 实测 **540/1017 条门项根本没跑** ⇒ 排障只能「改一个 ⇒ 跑一次 ⇒ 再改一个」）｜⚠ **跨行锚定**（压行后匹配 ⇒ 跨行形态也盯得住）｜⚠ 口径：锚在 trailer **自己的** `>&2` 之后 ⇒ **不会**误伤门项说明文字里的散文「exit 1」（⚠ 压行后散文与代码同处一行 ⇒ 宽正则会假红）｜⚠⚠⚨ **批 CP**'
arch_need_count "$SRC/scripts/ci-wiring.sh" '^\s+exit 1$' 3 '判据层**整行的 `exit 1`**必须恰好 3 处（⚠⚠⚨ **批 CP**：那 3 处 = ① 顶部 preflight「没有 perl ⇒ 判失败」② 末尾「剥注释失败」检查 ③ 末尾「统一按全局红过判红」）—— ⚠⚠⚨ **段级 trailer 里一处都不许有** （有 ⇒ 一处红就提前退出 ⇒ **后面 540 条门项根本没跑**）⇒ 多一处 ⇒ 有人把提前 exit 又塞回去了 ⇒ 必红｜⚠ **整行锚定**｜⚠⚠⚨ **批 CP**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CP 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CP 段门项全绿（一处红不许再遮住后面的门项：全跑完 + 末尾统一判红）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CQ · 审计器侧「先红遮后红」不许再遮（一次报全）─────────────────────
# ⚠⚠⚨ **起因（实测坐实，不是推演）**：`ci-wiring-audit.py --list` 的硬门模式里
#   是 **15 个顺序 `return N` 早退** ⇒ 同时存在两处问题时，**先红的那个 rc 遮住后面的**
#   （实测：rc=6「条数与基线不符」**遮住** rc=4「次数门没配准」⇒ 后者**完全不在输出里**）
#   ⇒ ⇒ 排障被迫「改一个 ⇒ 跑一次 ⇒ 再改一个」⇒ 一次只看得见一个洞。
# ⚠⚠⚨ **修法**：每一处失败**记进收集器**（`FAILS.append(N)`）⇒ **不再顺序早退**
#   ⇒ 末尾**一次报全**；⇒ ⚠ **rc 仍取最先失败的那个**（`FAILS[0]`）
#   ⇒ ⇒ **码值语义不变** ⇒ 门侧按 rc 分诊的文案表**零改动**。
# ⚠ **4 处仍然是早退**（源文件读不了 / git diff 拿不到 / 跨文件命中数算不出来
#   / 统一出口）⇒ 那时**后面确实不可信** ⇒ 早退是**语义正确**的，不是遮蔽。
# ⚠ **依赖失败的检查**（豁免基线坏了 / 锚定自检不过 ⇒ 整行锚定那两项不可信）
#   ⇒ **明确跳过并说明**（不跑 = 「没验」⇒ 必须说出来）⇒ 不许默默不跑。
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^FAILS = \[\]$' 1 '审计器的**失败态收集器**的声明必须在（⚠⚠⚨ **批 CQ**：硬门模式改成「**收集失败态、一次报全**」⇒ 它是那 15 处失败态的**唯一落点** ⇒ 摘掉 ⇒ 审计器自己 NameError ⇒ 崩 ⇒ 门红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CQ**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s*FAILS.append\(2\)$' 4 '审计器的 **rc=2**（盲区 / 豁免基线不在 / 审计器崩了）**收集处**必须恰好 4 处（⚠⚠⚨ **批 CQ**：① 门型盲区 ② 豁免基线不在 ③ 审计器自己有盲区 ④ 审计器崩了（兜底）⇒ 四种失败要分开 ⇒ 不然排障会被带偏）｜⚠⚠⚨ **批 CQ**｜⚠ **整行锚定**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CQ 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CQ 段门项全绿（审计器不许再「先红遮后红」：失败态收集 + 一次报全）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CR · 门项条数记三遍：改一边必红（不许拿「改基线」当删门项的掩护）────
# ⚠⚠⚨ **起因（实测坐实，不是推演）**：把 `ci-wiring.sh` 里**一条门项行删掉**
#   **且** 把 `ci-wiring-gates.baseline` 的数字 -1
#   ⇒ 审计器 rc=0、接线门 rc=0、✗ 行数 **0** ⇒ ⚠⚠⚨ **全绿**
#   ⇒ ⇒ **一条承诺就这么悄悄消失了**（而「改基线」是**每批都要做的惯常动作**
#   ⇒ ⇒ 惯常动作正好是最好的掩护 ⇒ 必须专门堵）。
# ⚠⚠⚨ **修法**：同一件事**记三遍** ——
#   ① `scripts/ci-wiring-gates.baseline`（基线文件里的数字）
#   ② `ci-wiring-audit.py` 里的**常量**（审计器自己核对 ① 与 ② ⇒ 不一致就红）
#   ③ **下面这两条门**：③ 钉住 ② 的值、④ 钉住 ② 的**判定行**（整行锚定）
#   ⇒ 改任意一边 ⇒ 另外两边对不上 ⇒ **红**
# ⚠ **不宣称完全堵死**（四处协同编辑仍能躲过）⇒ 但成本从 2 处升到 4 处、跨 2 个文件
#   ⇒ **极显眼** ⇒ 评审必看见 ⇒ 惯常动作不再是掩护。
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^GATE_LINES_EXPECTED = 1180$' 1 '门项条数必须被**审计器源码里的常量**交叉钉住（⚠⚠⚨ **批 CR**：实测坐实 —— 删一条门项 **且** 把基线文件 -1 ⇒ 旧行为**全绿**（审计器 rc=0、接线门 rc=0、✗ 0 行）⇒ 承诺**悄悄消失** ⇒ 现在同一件事记三遍：基线文件 / 审计器常量 / **本门里的这个数字** ⇒ 改任意一边 ⇒ 另外两边对不上 ⇒ **红**）｜⚠⚠⚨ **批 CY**：批 CY 段新增 6 条 ⇒ 1044 → 1050（**三处同改**）；⚠⚠⚨ **批 CZ**：批 CZ 段新增 6 条 ⇒ 1050 → 1056（**三处同改**）；⚠⚠⚨ **批 DA**：批 DA 段新增 18 条 ⇒ 1056 → 1074（**三处同改**）；⚠⚠⚨ **批 DB**：批 DB 段新增 13 条 ⇒ 1074 → 1087（**三处同改**）；⚠⚠⚨ **批 DC**：批 DC 段新增 20 条 ⇒ 1087 → 1107（**三处同改**）；⚠⚠⚨ **批 DD**：批 DD 段新增 15 条 ⇒ 1107 → 1122（**三处同改**）｜⚠ **整行锚定**；⚠⚠⚨ **批 DE**：批 DE 段新增 31 条 ⇒ 1122 → 1153（**三处同改**）；⚠⚠⚨ **批 DF**：批 DF 段新增 14 条 ⇒ 1153 → 1167（**三处同改**）；⚠⚠⚨ **批 DG**：批 DG 段新增 13 条 ⇒ 1167 → 1180（**三处同改**）｜⚠⚠⚨ **批 CR**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+if gbase is not None and gbase != GATE_LINES_EXPECTED:$' 1 '基线与常量的**交叉核对判定行**必须**是那一行原样**（⚠⚠⚨ **批 CR**：⚠ 只盯「串在不在」⇒ 判定被掏空成 `and False:` 就躲过了 ⇒ 没人发现 ⇒ **交叉核对形同虚设** ⇒ 那批承诺也就没人守了）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CR**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CR 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CR 段门项全绿（门项条数记三遍：改一边必红）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CS · 配对门不许只比「总数」：必须**逐段**配对 ─────────────────────
# ⚠⚠⚨ **起因（实测坐实，不是推演）**：`arch_need_count_pair` 只保证
#   「**报错行数 == 计数行数** == 期望」⇒ **总数相等**
#   ⇒ 实测：把某处的计数行**挪到别的一段** ⇒ 报错 39 / 计数 39（**总数不变**）
#   ⇒ ⇒ **审计器 rc=0、接线门 rc=0、✗ 行数 0** ⇒ ⚠⚠⚨ **全绿**
#   ⇒ ⇒ 那一处报错**不再被计数** ⇒ 末尾判定恒真 ⇒ **CI 假绿**
#   ⇒ ⇒ 本批：审计器侧**逐段**核对 ⇒ 每段（从这处报错到下一处报错之前）
#     必须**恰好 1 处**计数行 ⇒ 「总数相等但逐条不对」也红。
# ⚠ **零新门型**（判据层的门型注册表不变 ⇒ 审计器的门型对拍不受影响）——
#   逐段核对加在**已有的配对校准**里 ⇒ 门侧那两条配对门的**语义**变强了
#   ⇒ ⇒ 它们的**说明文字必须同步改**（批 BA/BB 纪律：说明文字必须与实际行为一致）。
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^def pair_segment_bad\(path, ra, rb\):$' 1 '配对门的**逐段配对**检查函数**必须存在**（⚠⚠⚨ **批 CS**：⚠ 实测坐实 —— 把某处的计数行**挪到别的一段** ⇒ 报错数/计数数**总数不变** ⇒ 老门**全绿** ⇒ ⇒ 那一处报错**不再被计数** ⇒ 末尾判定恒真 ⇒ **CI 假绿** ⇒ ⇒ 必须有**逐段**核对：每段（从这处报错到下一处报错之前）**恰好 1 处**计数）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CS**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+seg = pair_segment_bad\(f, ra, rb\)$' 1 '配对门的**逐段配对**检查**必须真的被调用**（定义了不调 ⇒ 形同虚设 ⇒ 没人发现「总数相等但逐条不对」⇒ **CI 假绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CS**'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+if seg_n != 1:$' 1 '逐段配对的**判定行**必须**是那一行原样**（⚠⚠⚨ **批 CS**：⚠ 只盯「串在不在」⇒ 判定被掏空成 `and False:` 就躲过了 ⇒ 没人发现 ⇒ **逐段配对形同虚设**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CS**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CS 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CS 段门项全绿（配对门逐段配对：总数相等不够，逐条也得对）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CT · 崩了 ⇒ rc 强制 2（不许被更早的失败态顶替）────────────────────
# ⚠⚠⚨ **起因（实测坐实，不是推演）**：先造一处别的失败（基线改错 ⇒ rc=6）
#   **且**让审计器随后崩 ⇒ 旧行为 **rc=6**
#   ⇒ ⇒ 输出里**两条消息都在**（批 CQ 的一次报全 ✓）
#   ⇒ ⇒ 但 **rc**（CI 的**分诊依据**）指向「门项行数与基线不符」
#   ⇒ ⇒ 而真实原因是**审计器崩了** ⇒ ⚠⚠⚨ **排障被带偏**
#   ⇒ ⇒ 本批：崩了 ⇒ rc **强制 2**（盲区家族：那些检查没跑完）
# ⚠ **rc=2 的分诊文案也补了一句**（说明文字必须与实际行为一致）
#   ⇒ 不然分诊表里 rc=2 那一档**不包含**「崩了」⇒ 照样被带偏。
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^CRASH_RC = 10$' 1 '崩了的退出码必须被**钉死**（⚠⚠⚨ **批 CT**：崩了 ⇒ 那些检查**没跑完** ⇒ 与「源文件读不了」同款 ⇒ 用**专属码 rc=10**（不再与「盲区 rc=2」混一档）；⚠⚠⚨ 实测：先造 rc=6 **且**让审计器崩 ⇒ 旧行为 **rc=6** ⇒ 「崩了」被顶替 ⇒ **CI 的分诊依据指向别的原因** ⇒ 排障被带偏 ⇒ 崩了时**强制**这个码）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CT**｜⚠⚠⚨ **批 CW**：码值从 2 改成 **10（专属码）** ⇒ 崩了与「盲区」**完全分离** ⇒ 分诊表里**单独一档** ⇒ 不会再被当成「盲区」去查'
arch_need_count "$SRC/scripts/ci-wiring-audit.py" '^\s+return CRASH_RC$' 1 '崩了的出口必须走**这个常量**（⚠⚠⚨ **批 CT**：⚠ 改回 `return FAILS[0] if FAILS else 2` ⇒ 又会被更早的失败态顶替 ⇒ 洞回来；⇒ 单独一个常量还能让门**指名道姓**地盯住崩了的那一处）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CT**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CT 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CT 段门项全绿（崩了 ⇒ rc 强制 2：分诊依据不被顶替）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CU · 「校验失败」不许被 `&&` 吞掉（ci.sh 第 3 步 ⇒ 假绿）────────────
# ⚠⚠⚨ **起因（实测坐实，不是推演）**：把 desktop 文件的 `Type` 写成非法值
#   ⇒ `desktop-file-validate` **判红**（rc=1、错误打在 stdout）
#   ⇒ 但旧版 ci.sh **rc=0**、末尾照样打「✓ CI 门通过」、**15 步全部跑完**
#   ⇒ ⇒ ⚠⚠⚨ **假绿**（desktop 非法 ⇒ 图标进不了启动器 / 点不起来）
# ⚠ **根因**：`set -euo pipefail` 对 `&&` 列表里**非末位**命令的失败
#   **不触发退出**（bash / dash 实测：`false && echo OK` ⇒ 继续往下跑、rc=0）
#   ⇒ ⇒ 「校验命令的成败」被挂在 `&&` 后面 ⇒ **失败不影响 CI 的结论**。
# ⚠ **为什么没有第二道门兜底**：`desktop-file-validate` / `appstream-util`
#   **全仓只在 ci.sh 那一处被调用**（grep 全仓确认）⇒ 那个 `&&` 就是**唯一**
#   的那道门 ⇒ 它形同虚设 ⇒ 本批必须**行为修**（接住退出码）+ **形态门**。
# ⚠⚠⚨ **本段的门盯什么**（三条，各管一头）：
#   ① 两处校验**必须接住退出码**（`|| _xxx_rc=$?`）——
#      ⚠ 不接 ⇒ `_xxx_rc` 恒为 0 ⇒ **失败分支永远进不去** ⇒ 洞回来；
#   ② 两处**失败分支必须报错 + `exit 1`**（跨行锚定）——
#      ⚠ 接住了退出码但不判红 ⇒ 失败照样往下跑 ⇒ 还是假绿；
#   ③ **形态 forbid**：ci.sh 里不许再出现「`&&` 挂着的 echo」——
#      ⚠ 这一条**一次挡住整类**（批 CD 纪律：一次挡住整类，别逐点治标）。
arch_need_ml "$SRC/scripts/ci.sh" '_dfv_rc=0[[:space:]]+desktop-file-validate "\$SRC/data/cn\.deepdolphin\.app\.desktop" \|\| _dfv_rc=\$\?[[:space:]]+if \[ "\$_dfv_rc" -ne 0 \]; then[[:space:]]+echo "✗ desktop 文件不合法（desktop-file-validate 退出码 \$_dfv_rc）" >&2[[:space:]]+exit 1[[:space:]]+fi' 'CI 第 3 步的 desktop 校验必须**接住退出码并判红**（⚠⚠⚨ **批 CU**：⚠ 实测坐实 —— 旧形态把校验命令挂在 `&&` 后面 ⇒ `set -e` 对 `&&` 列表里**非末位**的失败**不触发退出**（bash/dash 实测：`false && echo OK` ⇒ 继续、rc=0）⇒ ⇒ desktop 非法 ⇒ ci.sh **rc=0**、照样打「✓ CI 门通过」⇒ **假绿** ⇒ ⇒ 本门把「初始化 → 接退出码 → 失败分支报错 → `exit 1`」**整块钉住** ⇒ 少一环（不接退出码 / 不判红 / 报错被删 / `exit 1` 被摘）⇒ **红**）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CU**'
arch_need_ml "$SRC/scripts/ci.sh" '_asu_rc=0[[:space:]]+appstream-util validate-relax --nonet "\$SRC/data/metainfo/cn\.deepdolphin\.app\.metainfo\.xml" \|\| _asu_rc=\$\?[[:space:]]+if \[ "\$_asu_rc" -ne 0 \]; then[[:space:]]+echo "✗ metainfo 不合法（appstream-util 退出码 \$_asu_rc）" >&2[[:space:]]+exit 1[[:space:]]+fi' 'CI 第 3 步的 metainfo 校验必须**接住退出码并判红**（⚠⚠⚨ **批 CU**：⚠ 与 desktop 那一处**同款洞** —— `appstream-util` **全仓只在 ci.sh 这一处被调用** ⇒ 那道 `&&` 就是唯一的那道门 ⇒ 它形同虚设 ⇒ ⇒ 本门把「初始化 → 接退出码 → 失败分支报错 → `exit 1`」**整块钉住**）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 CU**'
arch_forbid "$SRC/scripts/ci.sh" '&&[[:space:]]*echo' 'CI 里不许再出现「`&&` 挂着的 echo」这种形态（⚠⚠⚨ **批 CU**：⚠ `set -euo pipefail` 对 `&&` 列表里**非末位**命令的失败**不触发退出**（bash/dash 实测：`false && echo OK` ⇒ 继续往下跑、rc=0）⇒ ⇒ 挂在 `&&` 后面的**校验命令的失败不影响 CI 的结论** ⇒ 实测：desktop 非法 ⇒ ci.sh **rc=0** + 「✓ CI 门通过」⇒ **假绿** ⇒ ⇒ 本条**一次挡住整类**（不是逐点治标）：任何「用 `&&` 把成败挂在成功提示上」的写法都不许回来｜⚠ forbid 门判「不该有的东西没了」⇒ 命中 >0 ⇒ 红）'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CU 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CU 段门项全绿（校验失败不许被 && 吞掉：接住退出码 + 失败即判红 + 形态禁绝）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CV · 「可达」判定不许被**注释**顶替（孤儿探针 ⇒ 假绿）──────────────
# ⚠⚠⚨ **起因（实测坐实，不是推演）**：批 BD 立的「断言脚本不许游离在 CI 之外」
#   门，靠 `calls_of()` 在**原始文本**里找调用点 ⇒ ⚠⚠⚨ **不剥注释**
#   ⇒ ⇒ **实测**：造一个**没有任何真调用点**的断言脚本 ⇒ 门判红 ✓；
#     **只**在 ci.sh 里加一行**注释**（`# sh "$SRC/scripts/<那个脚本>.sh"`）
#     ⇒ 门改判「全部可达」⇒ **rc=0** ⇒ ⚠⚠⚨ **假绿坐实**
#     ⇒ ⇒ 批 BD 的承诺（「少了一份断言 ⇒ 必须红」）**可被一行注释破掉**。
# ⚠ **为什么这一处特别刺眼**：这道门是**专门为「承诺不许悄悄消失」而建**的
#   ⇒ 它自己形同虚设 ⇒ 比没有门更坏（给人虚假的安全感）。
# ⚠ **修法**（只动判据层脚本 ⇒ 零产品代码改动）：
#   ① `calls_of()` **先剥注释**再找调用点 ⇒ **抽取** ci-wiring.sh 的
#      `strip_comments`（批 CF / AV 纪律：判据层只有**一份**剥注释实现 ⇒ 零漂移）；
#   ② 抽取失败 ⇒ **指名道姓地失败**（不许静默降级成「不剥注释」）；
#   ③ **剥注释失败**（工具失败 ≠ 没找到）⇒ 判红（不许当成「没有游离脚本」）。
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^if ! eval "\$\(sed -n .\/\^strip_comments\(\) \{\/,\/\^\}\/p. "\$SRC\/scripts\/ci-wiring\.sh"\)" \|\| ! strip_comments "\$SRC\/scripts\/ci-wiring\.sh" >\/dev\/null 2>&1; then$' 1 '孤儿探针的**剥注释必须从 ci-wiring.sh 抽取**（⚠⚠⚨ **批 CV**：⚠ 不剥注释 ⇒ 注释里的一行同形文本就能让**游离断言脚本**冒充「在 CI 里」⇒ 本门 rc=0 ⇒ **假绿**（实测坐实）⇒ ⇒ 这条门钉住「**抽取**」这个动作 ⇒ 抽取被摘掉 ⇒ 门红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CV**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^    echo "✗ 剥注释函数抽取失败或不可用（ci-wiring\.sh 的函数体里有独占的 \} 行 ⇒ 抽出来是残缺的）" >&2$' 1 '孤儿探针**抽取失败必须指名道姓地失败**（⚠⚠⚨ **批 CV**：⚠ 静默降级成「不剥注释」⇒ 等于把本批收掉的洞原样放回去 ⇒ **假绿** ⇒ ⇒ 这条门钉住那句诊断 ⇒ 它被删 ⇒ 门红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CV**'
arch_forbid "$SRC/scripts/ci-orphan-probe.sh" 's/\^\[\[:space:\]\]\*#|perl -pe' '孤儿探针**不许自己实现剥注释**（⚠⚠⚨ **批 CV**：⚠⚠⚨ **复刻** ⇒ 判据层就有**两份**剥注释口径 ⇒ 迟早漂移 ⇒ 同一个判定两边结论相反 ⇒ 没人发现 ⇒ 批 CF / AV 纪律：**抽取而非复刻** ⇒ 这条 forbid 门把「自己实现」的两支实现（sed 那一支 / perl 那一支）**一起禁掉** ⇒ 只许用 ci-wiring.sh 那一份）｜⚠ forbid 门判「不该有的东西没了」⇒ 命中 >0 ⇒ 红'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^trap ._cv_rc=\$\?; rm -f "\$WL_FILE"; if \[ -s "\$STRIP_FAIL_FILE" \]; then echo "✗ 剥注释失败[^;]*; _cv_rc=1; fi; rm -f "\$STRIP_FAIL_FILE"; exit \$_cv_rc. EXIT$' 1 '孤儿探针**必须把「剥注释失败」当成失败**（⚠⚠⚨ **批 CV**：⚠ 工具失败 ≠ 没找到 ⇒ 剥注释失败 ⇒ 可达性判定**不可信** ⇒ 必须判红（不许当成「没有游离脚本」）⇒ 这条门盯住 trap 里那一段 ⇒ 它被摘掉 ⇒ 门红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CV**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CV 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CV 段门项全绿（「可达」判定不许被注释顶替：先剥注释 + 抽取失败即判红 + 不许复刻剥注释）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CW · 崩了 ⇒ **专属码 rc=10**（不再与「盲区 rc=2」混一档）────────────
# ⚠⚠⚨ **起因（批 CT 留下的已知边界，不是推演）**：批 CT 让「崩了」不再被更早的
#   失败态顶替 ⇒ 但当时把崩了归进 **rc=2（盲区）** ⇒ ⇒ **rc=2 有两种成因**
#   （「真有盲区」/「审计器自己崩了」）⇒ 分诊那一档**说不出到底是哪一种**
#   ⇒ ⇒ 人看到 rc=2 ⇒ 先去查盲区 ⇒ 若盲区清单看不出问题 ⇒ **就不会想到是崩了**
#   ⇒ ⇒ ⚠⚠⚨ **排障还是会被带偏**（只是比批 CT 之前好一点）。
#   ⇒ ⇒ 本批：**专属码 rc=10** ⇒ 与 rc=2 **完全分离** ⇒ 分诊表里**单独一档**
#     ⇒ 「崩了」再也**混不进去** ⇒ 分诊依据就是 rc 本身。
# ⚠ **rc 语义只加不改**：rc=2/3/4/5/6/7/8/9 的含义**一个字都没动**
#   ⇒ 门侧分诊表的既有各档**零改动** ⇒ 只**多**一档。
# ⚠ **别的一律不动**：审计器里 `FAILS.append(2)` **照旧**（崩 ⇒ 那些检查没跑完
#   ⇒ **性质**仍是盲区）⇒ 报告里的「性质」分桶不变 ⇒ 只改**分诊用的 rc**。
arch_need_count "$SRC/scripts/ci-wiring.sh" '^\s+10\) _audit_why="[^"]*审计器\*\*崩了\*\*[^"]*" ;;$' 1 '接线门必须**按审计器的第 10 种失败态说原因**（⚠⚠⚨ **批 CW**：⚠ 崩了 ⇒ **专属码 rc=10** ⇒ 这一档必须**单独认领** ⇒ 少了它 ⇒ case 落到 `*)` ⇒ 报「未知的失败码」⇒ **排障被带偏**（真实原因是「审计器崩了」））｜⚠ **整行锚定**｜⚠⚠⚨ **批 CW**'
arch_forbid "$SRC/scripts/ci-wiring.sh" '2\) _audit_why="[^"]*审计器崩了' 'rc=2 的分诊文案**不许再提「崩了」**（⚠⚠⚨ **批 CW**：⚠ 崩了 ⇒ **专属码 rc=10** ⇒ rc=2 这一档**只**表示盲区 ⇒ 若文案里仍混着「崩了」⇒ 人会以为 rc=2 可能是崩 ⇒ **分诊依据又被带偏**）｜⚠ forbid 门判「不该有的东西没了」⇒ 命中 >0 ⇒ 红'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CW 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CW 段门项全绿（崩了 ⇒ 专属码 rc=10：与「盲区 rc=2」完全分离）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CX · 「未验证的逻辑出口」也要进登记册（盘点口径不只数提示行）──────
# ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：盘点脚本原来**只数**
#   「带未验证关键词的**打印行**」⇒ ⇒ 一处 `exit 3`（未验证的**逻辑出口**）
#   若**没带提示** ⇒ 登记册**看不见它** ⇒ 「未验证出口必须明示」这条纪律
#   **没有牙** ⇒ 实测：加一处**没提示**的 `exit 3` ⇒ 盘点照样绿 ⇒ **假绿**
# ⇒ 本批：盘点口径**多算一类**「未验证逻辑出口」⇒ 登记册**逐文件**登记它的处数
#   ⇒ ⇒ 新增一处出口（**带不带提示都一样**）⇒ 处数对不上 ⇒ **必红**
# ⇒ ⚠ 为什么「逐文件登记处数」而不是「逐处登记」（批 CM 遗留① 已否决）：
#   逐处化会因为**同款文案**导致集合比对塌陷 ⇒ 假红；此处登记的是**条数**
#   （按文件聚合）⇒ 不碰文案 ⇒ **不撞那个否决理由**。
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^UNVERIFIED_EXIT_RE = re\.compile\(r"\^\\s\*exit\\s\+3\(\\s\|\$\)"\)$' 1 '盘点口径必须**把「未验证的逻辑出口」算进来**（⚠⚠⚨ **批 CX**：⚠ 原来只数「带未验证关键词的**打印行**」⇒ 一处 `exit 3` 若**没带提示** ⇒ 登记册看不见 ⇒ 「未验证出口必须明示」这条纪律**没有牙** ⇒ 实测：加一处**没提示**的 `exit 3` ⇒ 盘点照样绿 ⇒ **假绿** ⇒ ⇒ 这条门钉住「口径里有这一类」⇒ 它被删 ⇒ 门红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CX**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^        if UNVERIFIED_EXIT_RE\.match\(ln\):$' 1 '盘点必须**真的按这一类计站点**（⚠⚠⚨ **批 CX**：⚠ 口径常量在、但扫描时不判 ⇒ 等于没这一类 ⇒ 登记册照旧看不见逻辑出口 ⇒ **假绿**回来 ⇒ ⇒ 这条门钉住「扫描时命中即计入」⇒ 它被摘 ⇒ 门红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CX**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CX 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CX 段门项全绿（未验证的逻辑出口也进登记册：口径多一类 + 扫描真判）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0


# ── 批 CY · 「未验证出口登记册」的覆盖面不许只覆盖一半（范围 + 键唯一）──────
# ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：
#   盘点脚本的扫描范围**写死**在 `SCRIPTS = HERE`（= `deepin/scripts/`）
#   ⇒ ⇒ `macos/scripts/` 里那 **12 个判据脚本**的未验证出口**完全不在册**
#     ⇒ ⚠ 而判据层**早已有门项盯着 `macos/scripts/*.sh`**（批 AJ 起）
#       ⇒ ⇒ 「未验证出口必须登记」这条纪律的覆盖面**比门项覆盖面窄**
#   ⇒ 实测：在 mac 侧判据脚本里加一处**没提示**的专属码 3 出口
#     ⇒ **HEAD 版盘点 rc=0**（假绿）⇒ **本批版 rc=1**
# ⚠⚠⚨ **第二个洞（扩范围时必踩）**：两个目录里**都有** `contract-check.sh`
#   ⇒ 若登记册仍用**裸文件名**做键 ⇒ 两个文件的处数**合并**
#     ⇒ **一处新增 + 一处减少 = 净 0** ⇒ 登记册照样相等 ⇒ **假绿**
#   ⇒ ⇒ 键必须是**相对仓库根的路径**（唯一）⇒ 本批把 21 行的文件列全改成路径
# ⚠⚠⚨ **第三个洞（登记册自身撞车）**：同一 (文件, 分类) 出现两行
#   ⇒ 字典里**静默塌陷** ⇒ 行数对了、组数少了 ⇒ 「条数基线」名不副实
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^UNVERIFIED_SCOPE = \("deepin/scripts", "macos/scripts"\)$' 1 '盘点范围**必须同时含两个判据脚本目录**（⚠⚠⚨ **批 CY**：⚠ 原来只扫 `deepin/scripts/` ⇒ `macos/scripts/` 的未验证出口**完全不在册** ⇒ 实测：在 mac 侧判据脚本里加一处**没提示**的专属码 3 出口 ⇒ 盘点照样绿 ⇒ **假绿** ⇒ 而判据层**早已有门项盯着 `macos/scripts/*.sh`** ⇒ 「未验证出口必须登记」这条纪律的覆盖面**比门项覆盖面窄** ⇒ 范围被改窄 ⇒ 这道门红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CY**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^    for scope in UNVERIFIED_SCOPE:$' 1 '盘点**必须真的遍历**那个范围常量（⚠⚠⚨ **批 CY**：⚠ 常量在、但扫描时不遍历 ⇒ 等于没扩范围 ⇒ mac 侧照样隐形 ⇒ **假绿**回来 ⇒ 批 CX 同款教训：「口径常量在、但扫描时不判」）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CY**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^        if not os\.path\.isdir\(base\):$' 1 '盘点范围里的目录**不存在**时必须**当场判红**（⚠⚠⚨ **批 CY**：⚠ `os.walk` 对不存在的目录**不报错**、直接产出空 ⇒ 范围被悄悄掏空 ⇒ 盘点等于没跑 ⇒ **假绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CY**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^        key = os\.path\.relpath\(path, REPO_ROOT\)$' 1 '登记册的**键必须用相对仓库根的路径**（⚠⚠⚨ **批 CY**：⚠ 两个目录里**都有** `contract-check.sh` ⇒ 若用裸文件名做键 ⇒ 两个文件的处数**合并** ⇒ **一处新增 + 一处减少 = 净 0** ⇒ 登记册照样相等 ⇒ **假绿** ⇒ 这是扩范围时**必踩**的坑）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CY**'
arch_need_count "$SRC/scripts/ci-unverified-audit.py" '^    if len\(base\) != len\(rows\):$' 1 '登记册的 **(文件, 分类) 键不许重复**（⚠⚠⚨ **批 CY**：⚠ 重复行在字典里**静默塌陷**（后一条盖前一条）⇒ 行数对了、组数少了 ⇒ 「登记册条数基线」**名不副实** ⇒ 且两行处数若相同 ⇒ **全绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CY**'
arch_need_min "$SRC/scripts/ci-unverified-audit.baseline" '^[A-Za-z0-9._-]+/[A-Za-z0-9._/-]+' 21 '登记册**每一行的文件列都必须带目录**（⚠⚠⚨ **批 CY**：⚠ 键要是裸文件名 ⇒ 与脚本侧**同名**文件撞车 ⇒ 跨目录处数互相抵消 ⇒ **假绿** ⇒ ⇒ 这条门要求 **21 行全部**带目录（配合登记册条数基线 21 ⇒ **一条都不许是裸名**））｜⚠ **下限由审计器校准**（`check_min_gates` 校准下限 == 实际命中数 ⇒ 下限写小了 ⇒ 门没牙）｜⚠⚠⚨ **批 CY**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CY 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CY 段门项全绿（未验证出口登记册的覆盖面不许只盖一半：范围含两个判据脚本目录 + 键唯一 + 登记册不许重复）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 CZ · 「判定不许被掏空成恒真」在 mac 侧**没有牙**（范围只盖一边）──────
# ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：
#   恒真探针（批 BG/BJ 立的「判据不许被掏空成恒真」）的 shell 扫描范围
#   **只有 `deepin/scripts/`**（`os.listdir(scripts)` ⇒ 单目录、顶层）
#   ⇒ ⇒ `macos/scripts/` 里那 **12 个判据脚本**上的 if 条件**从来没被查过**
#     ⇒ 而 mac 侧 `build.sh` **确实会跑**它们（contract-check / agent-check / …）
#       ⇒ 它们就是 mac 平台的判定层 ⇒ 恒真条件 ⇒ **mac 构建的判定静默通过**
#   ⇒ 实测坐实：在 mac 侧判据脚本里加一处恒真条件
#     ⇒ ⚠⚠⚨ **HEAD 版探针 rc=0**（假绿）⇒ **本批版 rc=1**
# ⚠⚠⚨ **顺带收掉的第二个洞**：`render-harness/run.sh` 在**子目录**里
#   ⇒ `os.listdir`（顶层）**够不着** ⇒ 它上面的 4 处 if 条件也不被查
#   ⇒ ⇒ 改成**递归**收集（⚠ deepin 侧**没有**子目录 .sh ⇒ 计数不变 ⇒ 两平台口径对称）
# ⚠⚠⚨ **口径不许漂**：两个平台**走同一个循环、同一个判定函数**
#   ⇒ 抽成 `scan_shell_file()`（⚠ 这样「四个实扫点」那条门**不用改**）
#   ⇒ ⚠ **递归**要递归**两个**目录（不许只递归 mac 侧 ⇒ 口径分叉）
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    repo_root = os\.path\.dirname\(os\.path\.abspath\(root\)\)$' 1 '恒真探针的 **mac 侧判据脚本目录**必须在（⚠⚠⚨ **批 CZ**：⚠ 判据脚本**散落在两个平台** ⇒ 范围不许只盖一边 ⇒ mac 侧那 12 个脚本上的「判定不许被掏空成恒真」本来**没有牙** ⇒ ⚠ 目录必须从**仓库根**算（root 的上一级）⇒ ⚠ 且要用**绝对路径**（root 可能是相对路径 `.` ⇒ `dirname(.)` 是空串 ⇒ 目录会找错 ⇒ 诊断失真）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CZ**｜⚠⚠⚨ **批 DB**：范围扩成**四个目录** ⇒ 「仓库根」这条被提到前面单独一行（`repo_root`）⇒ 本门跟着它走'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    sh_scope = \(\(.shell., scripts, .scripts.\), \(.macos_shell., mac_dir, .macos.\), \(.assets_shell., assets_dir, .assets.\), \(.linux_shell., linux_scripts, .linux/scripts.\)\)$' 1 '恒真探针的 **shell 侧范围必须同时含两个平台**（⚠⚠⚨ **批 CZ**：⚠ 只列一个目录 ⇒ mac 侧整批判据**不再被查恒真** ⇒ 探针静默变成半个空门 ⇒ ⚠ 两个目录写在**同一行** ⇒ 改一边就看得出来）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CZ**｜⚠⚠⚨ **批 DB**：扩成**四个口径**（deepin / macos / assets / linux）⇒ 仍写在**同一行** ⇒ 改一边就看得出来'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def scan_shell_file\(path, label\):$' 1 '恒真探针的 **shell 侧判定必须是共用函数**（⚠⚠⚨ **批 CZ**：⚠ 两个平台各写一遍判定 ⇒ **口径必然漂**（批 BF/BG 纪律：判定逻辑只许有一份）⇒ 一边改了另一边没改 ⇒ 两边的结论不一致 ⇒ 没人发现）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CZ**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^                _ni, _nb = scan_shell_file\(path, _rel \+ .\/. \+ os\.path\.relpath\(path, _d\)\)$' 1 '两个平台**必须真的走那个共用函数**（⚠⚠⚨ **批 CZ**：⚠ 定义了不调 ⇒ 等于没抽 ⇒ 两边各写一遍 ⇒ 口径漂 ⇒ 批 CX 同款教训：「常量在、但扫描时不判」⇒ **假绿**回来）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CZ**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^SCOPE_KEYS = \(.judgement., .shell., .macos_shell., .assets_shell., .linux_shell., .python., .swift.\)$' 1 '恒真探针的 **扫描范围口径序**必须在（⚠⚠⚨ **批 CZ**：⚠ 行序 = 口径序 ⇒ 少一行 / 多一行 ⇒ 基线读不出对应关系 ⇒ **fail closed** ⇒ 少一个平台就红 ⇒ 这条门钉住「**口径清单（名字 + 顺序）**」这件事本身）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CZ**｜⚠⚠⚨ **批 DB**：口径 4 → **6**（判定层 / deepin / macos / assets / linux / python）⇒ **行序 = 口径序** ⇒ 基线那 6 行的含义被这条门钉死；⚠⚠⚨ **批 DC**：口径 6 → **7**（加 Swift）⇒ **行序 = 口径序** ⇒ 基线那 7 行的含义被这条门钉死'
arch_need_count "$SRC/scripts/ci-tautology-scope.baseline" '^macos_shell 13$' 1 '扫描范围基线里 **mac 侧的判据脚本数必须恰好是 13**（⚠⚠⚨ **批 CZ**：⚠ 这一行是「mac 侧那批判据**还在被查**」的唯一数字依据 ⇒ 被改小 ⇒ 范围被悄悄改窄 ⇒ **没人发现** ⇒ ⇒ 这个数字**记两遍**（基线文件 + 本门）⇒ 改任意一边 ⇒ 另一边对不上 ⇒ **红**）｜⚠⚠⚨ **批 CZ**macos/scripts/`（12）扩成 **`macos/` 整棵树**（13 ⇒ **含 build.sh**）⇒ 12 → 13）｜⚠ **整行锚定**｜⚠⚠⚨ **批 CZ**｜⚠⚠⚨ **批 DB**；⚠⚠⚨ **批 DC**：改成**带口径名**（`macos_shell 13`）⇒ 每个口径能被**单独**钉住'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 CZ 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 CZ 段门项全绿（恒真探针的范围不许只盖一边：两个平台的判据脚本目录都在范围内 + 走同一个判定函数）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 DA · 「恒真」判定不许把 shell 的**惯用无限循环**当成判据被掏空 ──────
# ⚠⚠⚨ **起因（实测坐实，不是推演）**：
#   恒真探针把 shell 条件的「恒真/恒假」判定**一刀切**地套在**所有**条件上
#   ⇒ `while :; do` / `while true; do`（**shell 的惯用无限循环**）
#     被报成「if 的条件是恒真/恒假」⇒ **CI 假红**
#   ⇒ 实测坐实：在**探针范围内**的判据脚本里加一处 `while :; do`
#     ⇒ ⚠⚠⚨ **HEAD 版探针 rc=1**（假红）⇒ **本批版 rc=0**
#   ⇒ ⚠⚠⚨ **假红比假绿更坏**（批 BS 纪律）：假绿是承诺悄悄消失；
#     假红是**逼人把承诺改弱**（把 `while :; do` 改成怪写法来求绿）
#   ⇒ ⚠ 全仓唯一的 `while :; do` 现在在 `macos/build.sh:236`（**不在**探针范围内）
#     ⇒ 假红目前是**潜在**的 ⇒ 但只要有人往范围内脚本里写这个极常见惯用法
#       就会**当场假红** ⇒ 属于「迟早会踩」的坑 ⇒ 本批先收口。
# ⚠⚠⚨ **修法（判定逻辑只许有一份 ⇒ 口径不许漂）**：
#   ① `shell_if_conds()` 返回值带上**种类**（`if` / `while`）⇒ 判定处知道该不该判
#   ② 恒真/恒假判定**只对 `if`/`elif`** 生效 ⇒ `while` / `until` 放过
#   ③ 判定抽成 `shell_tautology_reason()` ⇒ **自检与实扫同一条路径**（批 BF 纪律）
#   ④ 扫描拆出 `scan_shell_text()`（**文本入口**）⇒ 自检能拿合成样例走**同一条**扫描
#      ⇒ 「while 不判 / if 判」这条区分由**探针自己**证明有牙（不是只靠门钉形态）
# ⚠ **已知边界（如实记着）**：`until true`（体永不执行）也被放过（本批不判）
#   ⇒ 「while / until 的体永不执行 ⇒ 断言永不跑」这条（批 BJ ③）仍靠**人读**兜着。
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def shell_tautology_reason\(kind, cond\):$' 1 '恒真探针的 **shell 侧恒真判定入口**必须在（⚠ **带左括号** ⇒ 改名躲不过；⚠⚠⚨ **批 DA**：判定抽成函数 ⇒ **自检与实扫走同一条路径**（批 BF 纪律）⇒ 自检才有意义 ⇒ 不许在实扫处另写一份）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+if kind != .if.:$' 1 '恒真/恒假判定**只对 `if`/`elif`** 生效（⚠⚠⚨ **批 DA**：⚠ `while :; do` / `while true; do` 是 **shell 的惯用无限循环** ⇒ 把它判成「判据被掏空成恒真」= **假红** ⇒ ⚠⚠⚨ **假红比假绿更坏**（批 BS：假红逼人把承诺改弱））｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+why = shell_tautology_reason\(kind, cond\)$' 1 '实扫**必须走那个统一判定入口**（⚠⚠⚨ **批 DA**：⚠ 不走 ⇒ 自检测的不是真判定 ⇒ 假的保证；⚠ 不许另写一份判定 ⇒ 两套口径必然漂 ⇒ 一边改了另一边没改 ⇒ 没人发现）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+got = shell_tautology_reason\(_k, _c\) is not None$' 1 '**自检**也必须走同一个判定函数（⚠ 自检与实扫分家 ⇒ 自检测的不是真判定 ⇒ 假的保证 —— 批 BF 纪律）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+kw = .if.$' 1 '条件提取必须认出 `if` 关键字（⚠⚠⚨ **批 DA**：种类由关键字推出 ⇒ 关键字漏了 ⇒ **那一类条件根本不被提取** ⇒ 那批判据**不再被查恒真** ⇒ 探针静默变成半个空门）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+kw = .elif.$' 1 '条件提取必须认出 `elif` 关键字（⚠ `elif` 的条件同样是条件 ⇒ 同样会退化 —— 批 BJ ②；⚠⚠⚨ **批 DA**：漏了 ⇒ `elif` 的恒真条件不再被查）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+kw = .while.$' 1 '条件提取必须认出 `while` 关键字（⚠⚠⚨ **批 DA**：⚠ `while` 的条件**仍要被提取**（批 BJ ③：体永不执行 ⇒ 断言永不跑）⇒ 只是**不判恒真**；⚠ 漏了 ⇒ `while` 的条件整个没人看）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+kw = .until.$' 1 '条件提取必须认出 `until` 关键字（⚠⚠⚨ **批 DA**：⚠ `until` 与 `while` 同族 ⇒ 同样**不判恒真**；⚠ 漏了 ⇒ `until` 的条件整个没人看）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+kind = .if. if kw in \(.if., .elif.\) else .while.$' 1 '**种类映射**必须在（⚠⚠⚨ **批 DA**：⚠ `if`/`elif` ⇒ `if` 家族（恒真要判）；`while`/`until` ⇒ `while` 家族（惯用无限循环 ⇒ 不判）⇒ ⚠ **映射写反 ⇒ 假红**（`while` 被判恒真）或**假绿**（`if` 被放过））｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+out\.append\(\(got\[0\], got\[1\], kind\)\)$' 1 '提取时**必须把种类一起带出来**（⚠⚠⚨ **批 DA**：⚠ 只回 (行号, 条件) ⇒ 判定处拿不到种类 ⇒ 要么全判（**假红**）要么全放过（**假绿**））｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+for line, cond, kind in shell_if_conds\(text\):$' 1 '实扫**必须解包出种类**（⚠⚠⚨ **批 DA**：⚠ 解包成两个 ⇒ 种类被丢掉 ⇒ 判定处永远拿不到 ⇒ 恒真判定静默失效）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def scan_shell_text\(text, label\):$' 1 '恒真探针的 **shell 侧扫描函数（文本入口）**必须在（⚠⚠⚨ **批 DA**：⚠ 入参是**文本** ⇒ 自检能拿合成样例走**同一条**扫描路径 ⇒ 「while 不判 / if 判」这条区分由**探针自己**证明有牙（不是只靠门钉形态））｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+return scan_shell_text\(text, label\)$' 1 '文件入口**必须真的交给那个扫描函数**（⚠⚠⚨ **批 DA**：⚠ 定义了不调 ⇒ 等于没抽 ⇒ 判据层与自检分家 ⇒ 假的保证 —— 批 CX 同款教训：「常量在、但扫描时不判」⇒ **假绿**回来）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.shell_e2e., \(.if [^,]*., 1\), True\),$' 2 '自检样例里 **`if` 家族该判红的** 那 2 条不许被掏空（⚠⚠⚨ **批 DA**：⚠ 只测「不该判的」⇒ 把恒真判定整个关掉也能过 ⇒ 只测一边 ⇒ 判反了也能过 —— 批 BF 纪律）｜⚠ **整行锚定**（批 BQ：中间用**有界**通配 `[^,]*` ⇒ 吃不掉逗号 ⇒ 行结构仍被钉住）｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.shell_e2e., \(.while [^,]*., 0\), True\),$' 2 '自检样例里 **`while` 家族不该判红的** 那 2 条不许被掏空（⚠⚠⚨ **批 DA**：⚠ 这是**反向护栏** ⇒ 少了它 ⇒ 假红回来没人发现 ⇒ 探针自己证明不了有牙）｜⚠ **整行锚定**（批 BQ）｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.shell_taut., \(.if., [^,]*\), True\),$' 1 '自检样例里 **判定级「该判为恒真」** 那 1 条不许被掏空（⚠ `if false` ⇒ 体永不执行 ⇒ 真掏空 ⇒ 必须判红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.shell_taut., \(.if., [^,]*\), False\),$' 1 '自检样例里 **判定级「不该判为恒真」** 那 1 条不许被掏空（⚠ 反向护栏 ⇒ 少了它 ⇒ 探针只会乱报）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.shell_taut., \(.until., [^,]*\), False\),$' 1 '自检样例里 **`until` 家族不该判为恒真** 那 1 条不许被掏空（⚠ `until` 与 `while` 同族 ⇒ 同样放过；⚠ 少一条 ⇒ `until` 的假红没人发现）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DA**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 DA 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 DA 段门项全绿（恒真判定只对 if/elif 生效：while/until 的惯用无限循环不再被当成判据被掏空；自检自己证明有牙）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 DB · 恒真探针的 shell 范围不许只盖「两个平台的判据脚本目录」───────
# ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：
#   恒真探针（批 BF 立的）的 shell 范围 = **两个平台的判据脚本目录**
#   ⇒ `macos/build.sh`、`assets/icon/check-icon.sh`、`linux/scripts/*.sh`
#     这 **11 个仓内自有 .sh**（**101 处 if 条件**）**从来没被查过**
#   ⇒ ⚠⚠⚨ 而 `macos/build.sh` **被 4 条门项盯着**（批 AJ 起：引擎 URL /
#     fetch-engine.sh / runtime lib 拷贝 / bin 拷贝）
#     ⇒ ⇒ **门项覆盖面比探针覆盖面宽** ⇒ **同一族洞**（批 CY 的题）
#   ⇒ 实测坐实：在 `macos/build.sh` 里加一处恒真条件
#     ⇒ ⚠⚠⚨ **HEAD 版探针 rc=0**（假绿）⇒ **本批版 rc=1**
# ⚠⚠⚨ **前置依赖（批 DA 收了它，本批才敢扩）**：
#   用**批 DA 之前**的口径量候选范围 ⇒ **160 处 if 条件、1 处会被判红**
#   ⇒ `macos/build.sh:236` 的 `while :; do`（**惯用无限循环**）
#     ⇒ ⚠⚠⚨ **不先修假红就扩范围 ⇒ 当场假红**（批 BS：假红逼人把承诺改弱）
#   ⇒ 用**批 DA 之后**的口径量同一范围 ⇒ **0 处判红** ⇒ **扩范围是净收益**
# ⚠⚠⚨ **口径不许漂**：四个范围目录**走同一个循环、同一个判定函数**
#   ⇒ 四个口径**写在同一行**（`sh_scope`）⇒ 改一边就看得出来
# ⚠ **显式目录清单，不靠排除表** ⇒ `linux/vendor`（第三方）**不进范围**
# ⚠ **每个基线数字都记两遍**（基线文件 + 门）⇒ 改一边必红
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    mac_dir = os\.path\.join\(repo_root, .macos.\)$' 1 '恒真探针的 **mac 侧整棵树目录**必须在（⚠⚠⚨ **批 DB**：⚠ 原范围只有 `macos/scripts/` ⇒ **`macos/build.sh` 不在范围** ⇒ 而它**被 4 条门项盯着**（批 AJ 起：引擎 URL / fetch-engine.sh / runtime lib / bin 拷贝）⇒ **门项覆盖面比探针覆盖面宽** ⇒ 同一族洞（批 CY 的题）⇒ 它的 38 处 if 条件**从来没被查过**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    assets_dir = os\.path\.join\(repo_root, .assets.\)$' 1 '恒真探针的 **assets 目录**必须在（⚠⚠⚨ **批 DB**：⚠ `assets/icon/check-icon.sh` 是**图标校验脚本**（判据脚本）⇒ 它的 10 处 if 条件不该没人查）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    linux_scripts = os\.path\.join\(repo_root, .linux., .scripts.\)$' 1 '恒真探针的 **linux 侧脚本目录**必须在（⚠⚠⚨ **批 DB**：⚠ `linux/scripts/` 里 9 个脚本（含 `ai-e2e.sh` / `ci-local.sh` 这类**判据脚本**）的 53 处 if 条件不该没人查；⚠ **只列 `scripts` 子目录** ⇒ `linux/vendor`（第三方）**不进范围** ⇒ 用**显式目录清单**，不靠排除表）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    for d in \(appdir, scripts, mac_dir, assets_dir, linux_scripts, swift_dir\):$' 1 '**六个扫描目录**必须在**存在性检查**里（判定层 / deepin 判据脚本 / macos 整棵树 / assets / linux/scripts / **Swift 判据**）（⚠⚠⚨ **批 DB**：⚠ 目录不存在却**默默跳过** ⇒ 范围被悄悄改窄 ⇒ 没人发现 ⇒ **假绿**；⇒ 少一个目录 ⇒ 那一整片 .sh **不再被查**而门照样绿）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**；⚠⚠⚨ **批 DC**：**五个**范围目录都要在存在性检查里（加 `swift_dir`）⇒ 目录不存在却**默默跳过** ⇒ 范围被悄悄改窄 ⇒ **假绿**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    for _key, _d, _rel in sh_scope:$' 1 '范围常量**必须真的被遍历**（⚠⚠⚨ **批 DB**：⚠⚠⚨ 批 CX 同款教训：「常量在、但扫描时不判」⇒ **假绿**回来；⚠ 改成只遍历第一项 ⇒ 三个新口径**一个都不扫**而门照样绿 ⇒ 范围被悄悄改窄）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    n_sh_files = \{.shell.: 0, .macos_shell.: 0, .assets_shell.: 0, .linux_shell.: 0\}$' 1 '**四个 shell 口径的计数**必须都在（⚠⚠⚨ **批 DB**：⚠ 少一个键 ⇒ 那个口径**永远数不到文件** ⇒ 与基线**恒不相等** ⇒ 探针恒红；⚠ 更坏：把那个键删掉 + 基线同步改 ⇒ **范围收窄没人发现**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+.assets_shell.: n_sh_files\[.assets_shell.\],$' 1 '扫到的 **assets 口径**必须进对拍字典（⚠⚠⚨ **批 DB**：⚠ 漏了 ⇒ `got_scope` 里没这个键 ⇒ 范围检查**漏掉一整片**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+.linux_shell.: n_sh_files\[.linux_shell.\],$' 1 '扫到的 **linux 口径**必须进对拍字典（⚠⚠⚨ **批 DB**：⚠ 漏了 ⇒ `got_scope` 里没这个键 ⇒ 范围检查**漏掉一整片**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**'
arch_need_count "$SRC/scripts/ci-tautology-scope.baseline" '^judgement 4$' 1 '范围基线里 **判定层的文件数必须恰好是 4**（⚠⚠⚨ **批 DB**：⚠ 这个数字**记两遍**（基线文件 + 本门）⇒ 改任意一边 ⇒ 另一边对不上 ⇒ **红**；⚠ 原先只有基线文件记着 ⇒ 改范围 + 改基线 ⇒ **协同编辑**就收窄了范围而没人发现）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**；⚠⚠⚨ **批 DC**：改成**带口径名**（`judgement 4`）⇒ 每个口径能被**单独**钉住'
arch_need_count "$SRC/scripts/ci-tautology-scope.baseline" '^shell 18$' 1 '范围基线里 **deepin 侧判据脚本数必须恰好是 18**（⚠⚠⚨ **批 DB**：⚠ 这个数字**记两遍**（基线文件 + 本门）⇒ 改任意一边 ⇒ 另一边对不上 ⇒ **红**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**；⚠⚠⚨ **批 DC**：改成**带口径名**（`shell 18`）⇒ 每个口径能被**单独**钉住'
arch_need_count "$SRC/scripts/ci-tautology-scope.baseline" '^assets_shell 1$' 1 '范围基线里 **assets 侧的 .sh 数必须恰好是 1**（⚠⚠⚨ **批 DB**：⚠ 这个数字**记两遍**（基线文件 + 本门）⇒ 改任意一边 ⇒ 另一边对不上 ⇒ **红**；⚠ 改小 ⇒ **范围被悄悄改窄**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**；⚠⚠⚨ **批 DC**：改成**带口径名**（`assets_shell 1`）⇒ 每个口径能被**单独**钉住'
arch_need_count "$SRC/scripts/ci-tautology-scope.baseline" '^linux_shell 9$' 1 '范围基线里 **linux 侧的 .sh 数必须恰好是 9**（⚠⚠⚨ **批 DB**：⚠ 这个数字**记两遍**（基线文件 + 本门）⇒ 改任意一边 ⇒ 另一边对不上 ⇒ **红**；⚠ 改小 ⇒ **范围被悄悄改窄**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**；⚠⚠⚨ **批 DC**：改成**带口径名**（`linux_shell 9`）⇒ 每个口径能被**单独**钉住'
arch_need_count "$SRC/scripts/ci-tautology-scope.baseline" '^python 5$' 1 '范围基线里 **python 工具脚本数必须恰好是 5**（⚠⚠⚨ **批 DB**：⚠ 这个数字**记两遍**（基线文件 + 本门）⇒ 改任意边 ⇒ 另一边对不上 ⇒ **红**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DB**；⚠⚠⚨ **批 DC**：改成**带口径名**（`python 5`）⇒ ⚠ **顺带解掉一个撞车**：纯数字格式下 `^5$` 同时罩住 python 与 Swift 两个口径 ⇒ 钉不住是哪个 ⇒ 现在带名字就不撞了'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 DB 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 DB 段门项全绿（恒真探针的 shell 范围不许只盖两个平台的判据脚本目录：仓内自有 .sh 的四个口径都在范围内 + 每个基线数字都记两遍）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 DC · Swift 判据也不许被掏空（恒真探针的第三种语言）──────────────
# ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：
#   mac 侧的判据脚本是 **Swift**（`macos/Tests/*/main.swift`：5 个文件）
#   ⇒ 断言形态 = `check("标签") { …guard… else { throw fail("…") }… }`
#   ⇒ 判据就藏在**闭包体**里 ⇒ C++ 侧那条「`check(…)` 的第三个实参」口径**够不着**
#   ⇒ ⚠⚠⚨ **恒真探针里没有 Swift** ⇒ 那 **469 条断言一条都没被查过**
#   ⇒ 而 mac 构建**确实会跑**它们（`macos/build.sh` → `macos/scripts/*-check.sh`）
#     ⇒ 它们就是 **mac 平台的判定层** ⇒ 掏空了也没人知道（**假绿**）
#   ⇒ 实测坐实：在 `macos/Tests/ClientCheck/main.swift` 里把一条断言掏空
#     ⇒ ⚠⚠⚨ **HEAD 版探针 rc=0**（假绿）⇒ **本批版 rc=1**
# ⚠⚠⚨ **Swift 侧的两种掏空形态**：
#   ① **断言闭包里没有失败路径**（`throw` / `try` / `fatalError` / …）
#      ⇒ 这条断言**永远不会失败** ⇒ 等价于 C++ 侧的 `check(log, "…", true)`
#   ② **`if` 条件恒真/恒假**（`if true` / `if false`）或**带捷径**（`|| true`）
#      ⇒ 体总执行 / 永不执行 ⇒ 里面的判据形同虚设
# ⚠⚠⚨ **先量后改（扩范围之前必须先知道会不会立刻假红）**：
#   用本批口径量全部 469 条断言 ⇒ **0 条**闭包缺失败路径 ⇒ **不会立刻假红**
#   ⇒ 144 处 if 条件里 **0 处**恒真/恒假、**0 处**带捷径 ⇒ 同样是净收益
#   ⇒ ⚠⚠⚨ 顺带量出一个**抽取器假红**：仓里的 `"""` 多行字符串把引号状态机带偏
#     ⇒ 闭包体被抽错 ⇒ 误报「没有失败路径」⇒ **假红** ⇒ 本批把 `"""` 单独一档
# ⚠⚠⚨ **顺带收掉的第二个洞**：范围基线原是**纯数字**、靠**行序**对应口径
#   ⇒ ⚠ 两个口径的文件数**相同**时（python 5 / swift 5）门就**钉不住是哪个**
#   ⇒ 「每个口径都记两遍」（批 DB）这条纪律**立不住**
#   ⇒ 本批把基线改成**带口径名**（每行 `<口径> <数字>`）⇒ 每个口径能**单独**钉住
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    swift_dir = os\.path\.join\(repo_root, .macos., .Tests.\)$' 1 '恒真探针的 **Swift 判据目录**必须在（⚠⚠⚨ **批 DC**：⚠ mac 侧的判据脚本是 **Swift**（`macos/Tests/*/main.swift`：5 个文件、**469 条断言**）⇒ 它们的断言形态是 `check("标签") { …guard… else { throw … } }` ⇒ 判据藏在**闭包体**里 ⇒ C++ 侧那条「第三个实参」口径**够不着** ⇒ ⚠⚠⚨ **那 469 条断言从来没被查过恒真** ⇒ 而 mac 构建**确实会跑**它们 ⇒ 它们就是 **mac 平台的判定层**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^SWIFT_FAIL_RE = re\.compile\($' 1 'Swift 的**失败路径关键字表**必须在（⚠⚠⚨ **批 DC**：⚠ 闭包里**没有任何失败路径** ⇒ 这条断言**永远不会失败** ⇒ 等价于 C++ 侧的 `check(log, "…", true)` ⇒ 掏空；⚠⚠⚨ **`try?` 不算**（它把错误**吞掉** ⇒ 不会失败 ⇒ 实测仓里有 15 处 `try?` ⇒ 粗口径会把「吞错误」误当成「会失败」⇒ **假绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    r.\\bthrow\\b\|\\btry\\b[(][?][!]\\[?][)]\|\\bfatalError\\b\|\\bprecondition\\b\|\\bassert\\b.\)$' 1 'Swift 断言的**失败路径关键字表**必须保持原样（⚠⚠⚨ **批 DC**：⚠ **删掉任何一个关键字** ⇒ 「闭包必须有失败路径」这条承诺**悄悄变弱**（⚠ 实测：删 `fatalError` / `try` / `assert` / `precondition` ⇒ 命中数 1 → 0 ⇒ 门红）；⚠ **去掉 `(?!\?)` 排除** ⇒ `try?`（把错误吞掉）被当成失败路径 ⇒ 假绿；⚠ `try?` **不算**失败路径（批 DC 规矩））｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def strip_swift\(text, blank_strings=False\):$' 1 'Swift 的**注释/字符串剥离器**必须在（⚠⚠⚨ **批 DC**：⚠ **状态机而不是正则**（源码里有 `"https://…"` ⇒ 正则分不清 `//` 是注释还是 URL 的一部分）；⚠ **`"""` 多行字符串**单独一档（⚠⚠⚨ 实测踩到：当成普通字符串 ⇒ 引号状态机跑偏 ⇒ 闭包体被抽错 ⇒ **假红**）；⚠ `blank_strings=True` ⇒ 关键字**只从代码里认** ⇒ 否则说明文字里的 `try` 就能冒充失败路径）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def _swift_balance\(text, i, open_ch, close_ch\):$' 1 'Swift 的**括号/花括号配平器**必须在（⚠ **不用正则猜**闭包边界 ⇒ 闭包里有嵌套闭包与字符串字面量 ⇒ 正则会抽错）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def swift_check_closures\(text\):$' 1 'Swift 的**断言闭包提取器**必须在（⚠⚠⚨ **批 DC**：⚠ 不提取 ⇒ 那 469 条断言**一条都查不到**；⚠ `check` 必须**在行首** ⇒ `func check(…)` 那条**定义**不会被当成调用（⚠ 实测：5 个文件各 1 条定义 ⇒ 不排除就会多算 5 条））｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def swift_if_conds\(text\):$' 1 'Swift 的**if 条件提取器**必须在（⚠⚠⚨ **批 DC**：⚠ 不提取 ⇒ Swift 侧的 `if true` / `if false` **没人查**；⚠ 含 `else if`（它也是条件））｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def swift_assert_reason\(body\):$' 1 'Swift 断言的**掏空判定入口**必须在（⚠ **带左括号** ⇒ 改名躲不过；⚠ **返回原因而不是布尔** ⇒ 调用方不再自己算一遍 ⇒ 两份判定迟早漂）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    if SWIFT_FAIL_RE\.search\(code\):$' 1 'Swift 断言的**判定本体**必须在（⚠⚠⚨ **批 DC**：⚠ 闭包里**有**失败路径 ⇒ 这条断言**可能会失败** ⇒ 不判红；⚠ 判定被掏空 ⇒ 掏空的断言混过去 ⇒ **假绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def scan_swift_text\(text, label\):$' 1 'Swift 的**扫描函数（文本入口）**必须在（⚠ **入参是文本** ⇒ 自检能拿合成样例走**同一条**扫描路径 ⇒ 「Swift 侧也有牙」由**探针自己**证明）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def scan_swift_file\(path, label\):$' 1 'Swift 的**扫描函数（文件入口）**必须在（⚠ 薄封装 ⇒ 判定逻辑只有那一份 ⇒ 口径零漂移）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^            _na, _ni, _nb = scan_swift_file\($' 1 'Swift 侧**必须真的走那个扫描函数**（⚠⚠⚨ **批 DC**：⚠ 定义了不调 ⇒ 等于没抽 ⇒ 469 条断言**仍然没人查** ⇒ **假绿** —— 批 CX 同款教训：「常量在、但扫描时不判」）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^            n_swift_files \+= 1$' 1 'Swift 的**文件计数**必须在（⚠⚠⚨ **批 DC**：⚠ 少计 ⇒ 与基线**恒不相等** ⇒ 探针恒红；⚠ 更坏：把计数摘掉 + 基线同步改 ⇒ **范围收窄没人发现**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^                     .python.: n_py_files, .swift.: n_swift_files\}$' 1 '扫到的 **Swift 口径**必须进对拍字典（⚠⚠⚨ **批 DC**：⚠ 漏了 ⇒ 范围检查**漏掉一整片** ⇒ Swift 侧被悄悄移出范围而没人发现）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-scope.baseline" '^swift 5$' 1 '范围基线里 **Swift 判据文件数必须恰好是 5**（⚠⚠⚨ **批 DC**：⚠ 这个数字**记两遍**（基线文件 + 本门）⇒ 改任意一边 ⇒ 另一边对不上 ⇒ **红**；⚠ 改小 ⇒ **Swift 侧被悄悄移出范围**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^        if len\(parts\) != 2 or parts\[0\] != key or not parts\[1\]\.isdigit\(\):$' 1 '基线解析**必须 fail closed**（⚠⚠⚨ **批 DC**：⚠ 坏行 / 口径名写错 / 顺序乱了 ⇒ **返回 None** ⇒ 探针当场红 ⇒ 不许「读不到就当没有基线」；⚠⚠⚨ 基线改成**带口径名**的格式 ⇒ ⚠ 名字对不上**必须**红 ⇒ 否则「口径名与 `SCOPE_KEYS` 不一致」会**静默**对错行）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.swift_taut., [^,]+, False\),$' 1 '自检样例里 **Swift 侧「不该判红」** 那 1 条不许被掏空（⚠⚠⚨ **批 DC**：⚠ 这是**反向护栏** ⇒ 少了它 ⇒ 探针只会乱报）｜⚠ **整行锚定**（批 BQ：中间用**有界**通配 `[^,]+`）｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.swift_taut., [^,]+, True\),$' 1 '自检样例里 **Swift 侧「该判红」** 那 1 条不许被掏空（⚠⚠⚨ **批 DC**：⚠ 只测一边 ⇒ 把判定整个关掉也能过）｜⚠ **整行锚定**（批 BQ）｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.swift_e2e., \(.check\(.x.\) \{[^,]*\}\\n., [^,]*\), True\),$' 2 '自检样例里 **Swift 侧端到端（断言那两档）**那 2 条不许被掏空（⚠⚠⚨ **批 DC**：⚠ 断言掏空 / 正常断言 两档 ⇒ ⚠ **只测一边 ⇒ 判反了也能过**）｜⚠ **整行锚定**（批 BQ：中间用**有界**通配 `[^,]*` ⇒ 吃不掉逗号 ⇒ 行结构仍被钉住）｜⚠⚠⚨ **批 DC**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.swift_e2e., \(.if true \{[^,]*\}\\n., [^,]*\), True\),$' 1 '自检样例里 **Swift 侧 `if true` 那一档**不许被掏空（⚠⚠⚨ **批 DC**：⚠ Swift 侧的 `if` 条件恒真 ⇒ 体总执行 ⇒ 里面的判据形同虚设 ⇒ **必须判红**；⚠ 少了它 ⇒ 只测断言那两档 ⇒ `if` 侧的口径没人盯）｜⚠ **整行锚定**（批 BQ：中间用**有界**通配 `[^,]*`）｜⚠⚠⚨ **批 DC**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 DC 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 DC 段门项全绿（Swift 判据也不许被掏空：469 条断言的闭包必须有失败路径 + if 条件不许恒真/带捷径；范围基线改成带口径名 ⇒ 每个口径能单独钉住）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 DD · 判据层的「判定口径表」不许被悄悄改弱 ─────────────────────
# ⚠⚠⚨ **起因（实测坐实 + 完整枚举，不是推演）**：
#   恒真探针（批 BF 立的）里有一批「**判定口径表**」——
#     KEYWORDS（哪些词不算标识符）/ SHORTCUT（哪些写法算捷径）/
#     SH_CONST（shell 恒真字面量）/ PY_CONST_IF（python 恒真条件）/
#     LITERAL_CHAR（ERE 里哪些字符算字面量）/ SWIFT_FAIL_RE（Swift 失败路径）
#   ⚠ **它们的内容被削弱 ⇒ 没有任何东西会红**：
#     实测把每张表的**每一个分支**逐个删掉（78 个分支）⇒
#     **接线门 / 探针 / 审计器三样全绿** ⇒ 没人发现 ⇒
#     「恒真/纯字面量」「捷径」「ERE 匹配一切」「没有失败路径」这些
#     判定**悄悄变弱** ⇒ 承诺悄悄消失。
#   ⇒ 修法两腿（互不依赖 ⇒ 改一处必红）：
#     ① **内容级门**：每一行整行锚定 ⇒ 改一行 ⇒ 那条门红；
#     ② **补自检**（在探针里 ⇒ 批 DA·定）：每一档都有自检样例
#        ⇒ 改口径 ⇒ 探针自检红 ⇒ 探针自己证明有牙。
# ⚠ **正则一律从真实行现抽**（批 CX 纪律）⇒ 不手抄 ⇒ 零漂移。
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^KEYWORDS = \{$' 1 '「不算标识符」的关键字表**必须**是集合字面量（⚠ 改成别的形态 ⇒ 表的内容 不再是「抽掉它们之后不剩标识符」⇒ 判定口径漂）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    .true., .false., .nullptr., .NULL., .this., .sizeof., .static_cast.,$' 1 '「不算标识符」的关键字表**第 1 行**必须原样（⚠⚠⚨ **批 DD**：实测 —— 删掉任何一个关键字 ⇒ 接线门/探针/审计器**三样全绿** ⇒ 没人发现 ⇒ 「恒真/纯字面量」这条判定**悄悄变弱** ⇒ ⇒ 这一行逐字钉住）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    .const_cast., .reinterpret_cast., .dynamic_cast., .new., .delete.,$' 1 '「不算标识符」的关键字表**第 2 行**必须原样（⚠⚠⚨ **批 DD**：见第 1 行那条）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    .not., .and., .or., .int., .bool., .char., .double., .float., .void.,$' 1 '「不算标识符」的关键字表**第 3 行**必须原样（⚠⚠⚨ **批 DD**：见第 1 行那条）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    .unsigned., .signed., .long., .short., .auto., .return.,$' 1 '「不算标识符」的关键字表**第 4 行**必须原样（⚠⚠⚨ **批 DD**：见第 1 行那条）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^SHORTCUT = re\.compile\($' 1 '「捷径」的判定表**必须**是编译好的正则（⚠ 改成别的形态 ⇒ 捷径判定口径漂）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    r.\\\|\\\|\\s\*true\\b\|\\\|\\\|\\s\*false\\b\|&&\\s\*false\\b\|&&\\s\*true\\b.$' 1 '「捷径」判定表（`|| true` / `|| false` / `&& false` / `&& true` 四种退化方向）**第 1 行**必须原样（⚠⚠⚨ **批 DD**：实测 —— 删掉其中任何一档 ⇒ **三样全绿** ⇒ 没人发现 ⇒ 捷径判定**悄悄变弱**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    r.\|\\bor\\s\+true\\b\|\\bor\\s\+True\\b\|\\bor\\s\+False\\b.$' 1 '「捷径」判定表（`or true` / `or True` / `or False` 三档）**第 2 行**必须原样（⚠⚠⚨ **批 DD**：见第 1 行那条）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    r.\|\\band\\s\+false\\b\|\\band\\s\+False\\b\|\\band\\s\+True\\b.\)$' 1 '「捷径」判定表（`and false` / `and False` / `and True` 三档）**第 3 行**必须原样（⚠⚠⚨ **批 DD**：见第 1 行那条）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^SH_CONST = re\.compile\(r.\^\\s\*\(true\|false\|:\)\\s\*\$.\)$' 1 'shell 侧恒真字面量表（`true` / `false` / `:`）**必须原样**（⚠⚠⚨ **批 DD**：实测删掉任一档 ⇒ **三样全绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^PY_CONST_IF = re\.compile\(r.\^\\s\*if\\s\+\(True\|False\|1\|0\)\\s\*:.\)$' 1 'python 侧恒真条件表（`True` / `False` / `1` / `0`）**必须原样**（⚠⚠⚨ **批 DD**：实测删掉**任意一档** ⇒ **三样全绿** ⇒ python 侧的恒真条件**没人查了**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^LITERAL_CHAR = re\.compile\(r.\[\^\\\^\\\$\\\.\\\*\\\+\\\?\\\(\\\)\\\[\\\]\\\{\\\}\\\|\\\\\].\)$' 1 'ERE 的「字面字符」集合（哪些字符算字面量）**必须原样**（⚠⚠⚨ **批 DD**：实测删掉其中任何一档 ⇒ **三样全绿** ⇒ 「ERE 匹配一切 ⇒ 恒真」这条判定**悄悄变弱**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^        elif kind == .py_const_if.:$' 1 '自检**必须真的有** `py_const_if` 那一档（⚠⚠⚨ **批 DD**：⚠ 分支被改名/删掉 ⇒ python 侧那 5 个样例**走不到那条判定** ⇒ 自检测的不是真判定 ⇒ **假绿** —— 批 CX 同款教训：「常量在、但扫描时不判」）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.py_const_if., [^,]*, True\),$' 4 '自检样例里 **python 侧恒真条件的 4 档**（`if True:` / `if False:` / `if 1:` / `if 0:`）不许被掏空（⚠⚠⚨ **批 DD**：⚠ 实测 —— 删掉 PY_CONST_IF 里**任意一档** ⇒ 接线门/探针/审计器**三样全绿** ⇒ python 侧的恒真条件**没人查**）｜⚠ **整行锚定**（批 BQ：中间用**有界**通配 `[^,]*`）｜⚠⚠⚨ **批 DD**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^\s+\(.py_const_if., [^,]*, False\),$' 1 '自检样例里 **python 侧「不该判红」** 那 1 条不许被掏空（⚠⚠⚨ **批 DD**：⚠ 这是**反向护栏** ⇒ 少了它 ⇒ 探针只会乱报）｜⚠ **整行锚定**（批 BQ）｜⚠⚠⚨ **批 DD**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 DD 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 DD 段门项全绿（判定口径表不许被悄悄改弱：关键字表 / 捷径表 / shell 恒真字面量 / python 恒真条件 / ERE 字面字符，五张表逐行钉住 + python 侧恒真条件补了自检））；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0

# ── 批 DE · mac 侧判据脚本不许游离 / 失败计数不许被摘掉 ───────────────────
# ⚠⚠⚨ **起因（实测坐实，不是推演）**：
#   ① **失败计数被摘掉 ⇒ 假绿**：
#      `assets/icon/check-icon.sh` 的失败助手是**报错与计数同行**
#      （`bad() { echo "  ✗ $1"; fail=$((fail + 1)); }`）
#      ⇒ 摘掉 `fail=$((fail + 1))` ⇒ 末尾 `[[ $fail -eq 0 ]]` 恒真 ⇒ **恒 exit 0**
#      ⇒ 而它**从来没进过批 BZ 的配对门**（那两道门只罩 `check-deb-layout.sh`
#      与 `contract-check.sh`）⇒ **没有任何门会红** ⇒ 承诺悄悄消失。
#      同款形态还有 **mac 侧 4 个 nc8x 负控脚本**（计数点写作 `fail=$((fail + 1))`，
#      **带空格** ⇒ 与 `contract-check.sh` 的 `fail=$((fail+1))` 不是同一条正则）：
#      nc88 / nc89 / nc90 / nc91 ⇒ 摘掉计数点 ⇒ 末尾判定恒真 ⇒ 负控**恒绿** ⇒ 假绿。
#   ② **mac 侧判据脚本可以整组游离**：
#      孤儿探针（批 BD）的范围**只有 `deepin/scripts/`** ⇒ `macos/scripts/` 里那
#      **12 个判据脚本**从来没被查过 ⇒ 有人把 `macos/build.sh` 里对某个判据脚本的
#      **调用**摘掉 ⇒ **没有任何门会说一个字** ⇒ 承诺悄悄消失。
#      ⚠ 实测坐实：`nc88…nc91` 这 **4 个负控脚本全仓无人调用**
#      （`macos/build.sh` 不调、文档只在 `macos/README.md` 顺带提过）
#      ⇒ 这 4 组「判据坏了会红」的负控**从来没跑过**。
#
# ⚠⚠⚨ **关键口径坑（实测；直接扩范围会假红）**：
#   mac 构建的调用形态是**裸可执行**（`if "$DIR/scripts/xxx.sh"; then`），
#   **不是** `sh x.sh` ⇒ 孤儿探针现口径（要求解释器前缀）**认不出**
#   ⇒ ⇒ 直接把 mac 侧扫进来 ⇒ 12 个脚本**全成「游离」⇒ 假红**。
#   ⇒ 本批给 mac 侧**一份自己的调用点口径**（`CALL_RE_MACOS`），两份口径都**整行钉住**。
#   ⚠⚠⚨ **而且 mac 那份还必须排除「可执行性守卫」**
#     （`if [ -x "$DIR/scripts/xxx.sh" ]; then`）—— 守卫**不是调用**
#     ⇒ 若把它算成调用 ⇒ 有人把真调用删掉、只留守卫 ⇒ 探针仍判「可达」⇒ **假绿**
#     ⇒ 那正是本批要堵的洞 ⇒ 口径：**路径后紧跟 `;` / `)` / 行末**才算「把它当命令执行」。
#     ⚠ **实测**：摘掉 `build.sh` 里 `if "$DIR/scripts/contract-check.sh"; then`
#       那一行（**保留** `[ -x … ]` 守卫）⇒ 探针 **rc=1**（指名道姓报出
#       `contract-check.sh` 游离）⇒ 本批承诺成立。
#
# ⚠⚠⚨ **两腿互不依赖**（批 DD·定）：改一边必红。
#   腿 1 = **失败计数不许被摘掉**（配对门从 2 个脚本扩到 **7 个**）
#   腿 2 = **mac 侧判据脚本不许游离**（孤儿探针从 1 个平台扩到 **2 个**）
#
# ⚠ **腿 1 · 配对门扩到 7 个脚本**（报错行数 == 计数行数 == 期望；审计器侧还**逐段**核对）
arch_need_count_pair "$ROOT/assets/icon/check-icon.sh" 'echo "  ✗' 'fail=\$\(\(fail \+ 1\)\)' 1 '图标一致性验收的**报错行数必须等于失败计数行数**（且都恰好 1）｜⚠⚠⚨ **批 DE**：⚠⚠⚨ **实测的洞** —— 它的失败助手是**报错与计数同行**（`bad() { echo "  ✗ $1"; fail=$((fail + 1)); }`）⇒ 摘掉计数点 ⇒ 末尾 `[[ $fail -eq 0 ]]` **恒真** ⇒ **恒 exit 0** ⇒ 假绿｜⚠ 口径：**行数**（不是出现次数）｜⚠ 缩进差异把末尾汇总行 `echo "✗ $fail 处不一致"`（**无两格缩进**）**自然排除**在外 ⇒ 只盯**计数器型**的失败路径｜⚠ 本脚本**目前不在任何 CI 里**（只有 `assets/icon/README.md` 教人手跑）⇒ 本门守的是「**将来接进 CI 时它必须是真的**」'
arch_need_count_pair "$ROOT/macos/scripts/nc88-agent-bulk-check.sh" 'printf .  ✗ %-34s (期望红|红了)' 'fail=\$\(\(fail \+ 1\)\)' 2 '**nc88 负控组**的**报错行数必须等于失败计数行数**（且都恰好 2）｜⚠⚠⚨ **批 DE**：⚠ 实测 —— 这 4 个 nc8x 脚本**全仓无人调用** ⇒ 它们「判据坏了会红」的负控**从来没跑过**；⚠ 计数点被摘 ⇒ 末尾判定恒真 ⇒ 负控**恒绿** ⇒ 假绿｜⚠ 报错正则**排除** `exit 2` 那类「负控没生效」的报错行（那些**刻意不计数**，否则配对必假红）｜⚠ 口径：**行数**'
arch_need_count_pair "$ROOT/macos/scripts/nc89-one-screen-one-answer-check.sh" 'printf .  ✗ %-38s (期望红|红了)' 'fail=\$\(\(fail \+ 1\)\)' 2 '**nc89 负控组**的**报错行数必须等于失败计数行数**（且都恰好 2）｜⚠⚠⚨ **批 DE**：⚠ 实测 —— 这 4 个 nc8x 脚本**全仓无人调用** ⇒ 它们「判据坏了会红」的负控**从来没跑过**；⚠ 计数点被摘 ⇒ 末尾判定恒真 ⇒ 负控**恒绿** ⇒ 假绿｜⚠ 报错正则**排除** `exit 2` 那类「负控没生效」的报错行（那些**刻意不计数**，否则配对必假红）｜⚠ 口径：**行数**'
arch_need_count_pair "$ROOT/macos/scripts/nc90-settings-tabs-check.sh" 'printf .  ✗ %-36s (期望红|红了)' 'fail=\$\(\(fail \+ 1\)\)' 2 '**nc90 负控组**的**报错行数必须等于失败计数行数**（且都恰好 2）｜⚠⚠⚨ **批 DE**：⚠ 实测 —— 这 4 个 nc8x 脚本**全仓无人调用** ⇒ 它们「判据坏了会红」的负控**从来没跑过**；⚠ 计数点被摘 ⇒ 末尾判定恒真 ⇒ 负控**恒绿** ⇒ 假绿｜⚠ 报错正则**排除** `exit 2` 那类「负控没生效」的报错行（那些**刻意不计数**，否则配对必假红）；⚠⚠⚨ **注意**：`expect_gone` 那条 `printf .  ✗ %-36s 变体没删掉…` **也带 `%-36s`** ⇒ 报错正则**必须**再钉住「期望红|红了」两档，否则会把那条 `exit 2` 的报错行数进来 ⇒ 期望值变成 3 ⇒ **假红**｜⚠ 口径：**行数**'
arch_need_count_pair "$ROOT/macos/scripts/nc91-settings-scroll-check.sh" 'printf .  ✗ %-36s (期望红|红了)' 'fail=\$\(\(fail \+ 1\)\)' 2 '**nc91 负控组**的**报错行数必须等于失败计数行数**（且都恰好 2）｜⚠⚠⚨ **批 DE**：⚠ 实测 —— 这 4 个 nc8x 脚本**全仓无人调用** ⇒ 它们「判据坏了会红」的负控**从来没跑过**；⚠ 计数点被摘 ⇒ 末尾判定恒真 ⇒ 负控**恒绿** ⇒ 假绿｜⚠ 报错正则**排除** `exit 2` 那类「负控没生效」的报错行（那些**刻意不计数**，否则配对必假红）｜⚠ 口径：**行数**'
#
# ⚠ **腿 2 · 孤儿探针扩到两个平台**（范围 / 入口 / 调用点口径 / 白名单，逐条整行钉住）
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^DEEPIN_SCOPE="\$SRC/scripts"$' 1 '孤儿探针的 **deepin 侧范围目录**必须在（⚠⚠⚨ **批 DE**：⚠ 范围被静默收窄 ⇒ 那一整片判据脚本**没人查**而门全绿 ⇒ **假绿**；⚠ 深度侧范围不许被改成别的目录）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^DEEPIN_ENTRY="\$SRC/scripts/ci\.sh"$' 1 '孤儿探针的 **deepin 侧 CI 入口**必须是 `ci.sh`（⚠⚠⚨ **批 DE**：⚠ 入口算错 ⇒ 可达集合算在别的文件上 ⇒ 一整片脚本**全成游离**或**全成可达** ⇒ 门失准）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^MACOS_SCOPE="\$ROOT/macos/scripts"$' 1 '孤儿探针的 **mac 侧范围目录**必须在（⚠⚠⚨ **批 DE**：⚠⚠⚨ **实测的洞** —— 批 BD 的范围**只有 `deepin/scripts/`** ⇒ `macos/scripts/` 里那 **12 个判据脚本**从来没被查过 ⇒ 有人把 `macos/build.sh` 里对某个判据脚本的**调用**摘掉 ⇒ **没有任何门会说一个字** ⇒ 承诺悄悄消失；⚠ 范围被静默收窄 ⇒ 那一整片没人查而门全绿）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^MACOS_ENTRY="\$ROOT/macos/build\.sh"$' 1 '孤儿探针的 **mac 侧 CI 入口**必须是 `macos/build.sh`（⚠⚠⚨ **批 DE**：⚠ 入口算错 ⇒ 可达集合算在别的文件上 ⇒ 一整片脚本**全成游离**或**全成可达** ⇒ 门失准；⚠ mac 侧入口必须从**仓库根**算 ⇒ 不能写成相对路径）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^_CALL_PATH=.\[\^"\]\*/scripts/\[A-Za-z0-9\._/-\]\+\\\.\(sh\|py\).$' 1 '孤儿探针的**脚本路径片段**必须原样（⚠⚠⚨ **批 DE**：⚠ 两个平台**共用这一份** ⇒ 路径口径零漂移；⚠ 片段被改窄（漏掉子目录形态）⇒ 子目录里的判据脚本**认不出来** ⇒ 漏检 ⇒ 假绿）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^CALL_RE_DEEPIN="\(sh\|bash\|python3\?\)\[\[:space:\]\]\+\\"\?\$\{_CALL_PATH\}"$' 1 '孤儿探针的 **deepin 侧调用点口径**必须原样（⚠⚠⚨ **批 DE**：⚠ **解释器前缀**（`sh` / `bash` / `python3`）是 deepin 侧调用点的标志 ⇒ 删掉前缀 ⇒ 调用点认不出 ⇒ 一整片脚本**全成游离** ⇒ 假红；⚠ 口径被改宽 ⇒ 「提到过路径」被当成「调用过」⇒ 假绿）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^CALL_RE_MACOS="\(sh\|bash\|python3\?\)\[\[:space:\]\]\+\\"\?\$\{_CALL_PATH\}\|\\"\$\{_CALL_PATH\}\\"\(\[\^\]\]\*\)\$"$' 1 '孤儿探针的 **mac 侧调用点口径**必须原样（⚠⚠⚨ **批 DE**：⚠⚠⚨ **实测坐实** —— mac 构建的调用形态是**裸可执行**（`if "$DIR/scripts/x.sh"; then`）⇒ 用 deepin 那份口径**一个都认不出** ⇒ 直接扩范围会**假红**；⚠⚠⚨ **而且必须排除「可执行性守卫」**（`if [ -x "$DIR/scripts/x.sh" ]; then`）—— 守卫**不是调用** ⇒ 若把它算成调用 ⇒ 有人把真调用删掉、只留守卫 ⇒ 探针仍判「可达」⇒ **假绿** ⇒ 口径：**引号路径之后到行尾不得出现 `]`** ⇒ `[ … ]` 守卫天然排除，而 `"…x.sh"; then` / `"…x.sh" || true` / `"…x.sh" 参数` **都算调用**｜⚠⚠⚨ **负控实测（批 DE C7）**：口径要求路径后**紧跟** `;` / `)` / 行末时认不出 `"…x.sh" || true` ⇒ 漏检 ⇒ 本批放宽）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^PLATFORMS="deepin macos assets"$' 1 '孤儿探针的**平台清单**必须恰好是三个（⚠⚠⚨ **批 DE**：⚠ 少一个 ⇒ 那一个平台**整片不被查**而门全绿 ⇒ 假绿；⚠ 多一个不认识的平台 ⇒ 那个平台**直接被判红**（fail closed）⇒ 不会静默漏检；⚠⚠⚨ **批 DG**：加 **assets** ⇒ 两个 → 三个）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^        deepin\) _scope="\$DEEPIN_SCOPE"; _entry="\$DEEPIN_ENTRY"; _re="\$CALL_RE_DEEPIN" ;;$' 1 '孤儿探针的 **deepin 平台分支**必须真的走 deepin 那份范围/入口/口径（⚠⚠⚨ **批 DE**：⚠⚠⚨ **批 CX 同款教训**：「常量在、但扫描时不判」⇒ 定义了不用 ⇒ 等于没定义；⚠ 分支被改成走 mac 那份口径 ⇒ deepin 侧**认不出调用点** ⇒ 全成游离 ⇒ 假红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^        macos\)  _scope="\$MACOS_SCOPE";  _entry="\$MACOS_ENTRY";  _re="\$CALL_RE_MACOS" ;;$' 1 '孤儿探针的 **mac 平台分支**必须真的走 mac 那份范围/入口/口径（⚠⚠⚨ **批 DE**：⚠⚠⚨ **批 CX 同款教训**：「常量在、但扫描时不判」；⚠ 分支被改成走 deepin 那份口径 ⇒ mac 侧**认不出裸可执行调用** ⇒ 12 个脚本**全成游离** ⇒ 假红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^    for _f in \$\(find "\$_scope" -type f \\\( -name .\*\.sh. -o -name .\*\.py. \\\) 2>/dev/null \| LC_ALL=C sort\); do$' 2 '孤儿探针的**范围扫描必须递归**（恰好 **2 处**：可读性预检 + 断言脚本识别，两处**同一句**）｜⚠⚠⚨ **批 DE**：⚠ 只扫顶层 ⇒ `macos/scripts/render-harness/run.sh`（**子目录**里）不被查 ⇒ 漏检；⚠ 少一处 ⇒ 两个扫描点**口径不一致**（一处递归一处不递归）⇒ 判定失真；⚠ 递归下钻被摘 ⇒ 计数从 2 变 1 ⇒ **红**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^    if \[ ! -d "\$_scope" \]; then$' 1 '孤儿探针必须**先验范围目录存在**（⚠⚠⚨ **批 DE**：⚠ 目录不存在 ⇒ **fail closed**（判红）而不是「这一平台没有判据脚本」⇒ 否则整个平台被**静默移出范围**而门全绿 ⇒ 假绿）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^    if \[ ! -f "\$_entry" \]; then$' 1 '孤儿探针必须**先验 CI 入口存在**（⚠⚠⚨ **批 DE**：⚠ 入口不存在 ⇒ **fail closed**（判红）而不是「可达集合为空」⇒ 否则整片脚本被误报成游离、或因空集合而全成可达）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^        deepin/\*\|macos/\*\|assets/\*\) ;;$' 1 '白名单条目的**平台前缀**必须只认这三个（⚠⚠⚨ **批 DE**：⚠ 白名单里出现不认识的前缀 ⇒ 那个条目**永远不会被任何平台检查到** ⇒ 形同虚设 ⇒ 后门；⚠ 本门守的是「前缀集合」，具体条目另有门逐条钉；⚠⚠⚨ **批 DG**：加 **assets** ⇒ 两个 → 三个）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^if \[ "\$n_wl_total" -ne "\$n_wl" \]; then$' 1 '孤儿探针必须**核对「被检查的白名单条数 == 白名单总条数」**（⚠⚠⚨ **批 DE**：⚠ 不核对 ⇒ 某个平台的条目**没被任何平台检查** ⇒ 那条白名单形同虚设 ⇒ 后门，而门全绿）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DE**'
#
# ⚠ **白名单逐条钉住：mac 侧那 6 条「不许被 build.sh 调用」**
#   ⇒ 白名单是**例外登记**，不是垃圾桶（批 BD 纪律）
#   ⇒ 一旦某个条目**进了 build.sh** ⇒ 它不该留在白名单 ⇒ 门必须红
arch_need_count "$ROOT/macos/build.sh" '"[^"]*/scripts/engine-fetch-check\.sh"' 0 '白名单条目 **engine-fetch-check.sh** **不许被 mac 构建调用**（它就是**引擎下载链判据**）—— 期望 0 次：一旦它出现在 build.sh 里 ⇒ 这条白名单就是开后门（随时可以被踢出 CI 而无人知晓）｜⚠⚠⚨ **批 DE**'
arch_need_count "$ROOT/macos/build.sh" '"[^"]*/scripts/nc88-agent-bulk-check\.sh"' 0 '白名单条目 **nc88-agent-bulk-check.sh** **不许被 mac 构建调用**（它是 **nc8x 负控组**之一）—— 期望 0 次：一旦它出现在 build.sh 里 ⇒ 这条白名单就是开后门｜⚠⚠⚨ **批 DE**'
arch_need_count "$ROOT/macos/build.sh" '"[^"]*/scripts/nc89-one-screen-one-answer-check\.sh"' 0 '白名单条目 **nc89-one-screen-one-answer-check.sh** **不许被 mac 构建调用**（它是 **nc8x 负控组**之一）—— 期望 0 次：一旦它出现在 build.sh 里 ⇒ 这条白名单就是开后门｜⚠⚠⚨ **批 DE**'
arch_need_count "$ROOT/macos/build.sh" '"[^"]*/scripts/nc90-settings-tabs-check\.sh"' 0 '白名单条目 **nc90-settings-tabs-check.sh** **不许被 mac 构建调用**（它是 **nc8x 负控组**之一）—— 期望 0 次：一旦它出现在 build.sh 里 ⇒ 这条白名单就是开后门｜⚠⚠⚨ **批 DE**'
arch_need_count "$ROOT/macos/build.sh" '"[^"]*/scripts/nc91-settings-scroll-check\.sh"' 0 '白名单条目 **nc91-settings-scroll-check.sh** **不许被 mac 构建调用**（它是 **nc8x 负控组**之一）—— 期望 0 次：一旦它出现在 build.sh 里 ⇒ 这条白名单就是开后门｜⚠⚠⚨ **批 DE**'
arch_need_count "$ROOT/macos/build.sh" '"[^"]*/scripts/render-harness/run\.sh"' 0 '白名单条目 **render-harness/run.sh** **不许被 mac 构建调用**（它是**离屏渲染 harness**，产出快照不是判据）—— 期望 0 次：一旦它出现在 build.sh 里 ⇒ 这条白名单就是开后门｜⚠⚠⚨ **批 DE**'
#
# ⚠⚠⚨ **配对门的互补腿 · 失败路径清单门**（负控实测坐实 ⇒ 不是推演）
#   ⚠ 配对门盯的是「**计入 fail 的那一类**」的报错行（紧口径 `期望红|红了`）
#     ⇒ **新增一条别措辞的失败路径**时，紧口径**看不见** ⇒ 配对门仍绿
#     ⇒ ⚠⚠⚨ **负控实测**：在 nc89 里新增一条「只报错不计数、且措辞不同」的失败路径
#       ⇒ 配对门 **rc=0（全绿）** ⇒ ⇒ 必须另有一条**宽口径清单门**盯住**总数**
#   ⇒ 两腿互补：**摘掉计数点** ⇒ 配对门红；**新增失败路径** ⇒ 清单门红。
arch_need_count "$ROOT/assets/icon/check-icon.sh" '\bbad "' 11 '图标一致性验收的**失败路径清单**不许被增删（恰好 11 处 `bad "…"` 调用点）｜⚠⚠⚨ **批 DE**：⚠ 这是配对门的**互补腿** —— 配对门盯「报错行 ↔ 计数点」的**配对**，但**新增一条失败路径**（多一处 `bad "…"`）而**不动**计数点时，配对门仍绿（报错行数与计数行数**都**没变）⇒ 必须另有一条**清单门**盯住**调用点总数**｜⚠ 口径：**调用点**（`bad "`），**不是** `✗ ` 标记数（后者在 helper 型脚本里只有 1 ⇒ 形同虚设，批 BU 同款教训）｜⚠ 期望 == 实际 ⇒ 余量恒为 0（批 BB 口径）'
arch_need_count "$ROOT/macos/scripts/nc88-agent-bulk-check.sh" 'printf .  ✗' 3 '**nc88 负控组**的**失败路径清单**不许被增删（恰好 3 处报错行）｜⚠⚠⚨ **批 DE**：⚠ 这是配对门的**互补腿** —— 配对门盯的是「**计入 fail 的那一类**」（紧口径 `期望红|红了`）⇒ **新增一条别措辞的失败路径**时紧口径**看不见** ⇒ 必须另有一条**宽口径清单门**盯住总数｜⚠ 口径：**报错行**（`printf .  ✗`）｜⚠ 期望 == 实际 ⇒ 余量恒为 0（批 BB 口径）'
arch_need_count "$ROOT/macos/scripts/nc89-one-screen-one-answer-check.sh" 'printf .  ✗' 3 '**nc89 负控组**的**失败路径清单**不许被增删（恰好 3 处报错行）｜⚠⚠⚨ **批 DE**：⚠ 这是配对门的**互补腿** —— ⚠⚠⚨ **负控实测坐实**：新增一条「只报错不计数、且措辞不同」的失败路径 ⇒ 配对门**绿** ⇒ 靠这条清单门抓住｜⚠ 口径：**报错行**（`printf .  ✗`）｜⚠ 期望 == 实际 ⇒ 余量恒为 0（批 BB 口径）'
arch_need_count "$ROOT/macos/scripts/nc90-settings-tabs-check.sh" 'printf .  ✗' 6 '**nc90 负控组**的**失败路径清单**不许被增删（恰好 6 处报错行）｜⚠⚠⚨ **批 DE**：⚠ 这是配对门的**互补腿** ｜⚠ 口径：**报错行**（`printf .  ✗`）｜⚠⚠⚨ **注意**：这 6 处里有 **3 处是 `exit 2` 那类「负控没生效」**（**刻意不计数**）⇒ 配对门**必须**用紧口径把它们排除（否则必假红）⇒ ⇒ **两条腿缺一不可**｜⚠ 期望 == 实际 ⇒ 余量恒为 0（批 BB 口径）'
arch_need_count "$ROOT/macos/scripts/nc91-settings-scroll-check.sh" 'printf .  ✗' 4 '**nc91 负控组**的**失败路径清单**不许被增删（恰好 4 处报错行）｜⚠⚠⚨ **批 DE**：⚠ 这是配对门的**互补腿** ｜⚠ 口径：**报错行**（`printf .  ✗`）｜⚠⚠⚨ **注意**：这 4 处里有 **2 处是 `exit 2` 那类「负控没生效」**（**刻意不计数**）⇒ 配对门**必须**用紧口径把它们排除（否则必假红）⇒ ⇒ **两条腿缺一不可**｜⚠ 期望 == 实际 ⇒ 余量恒为 0（批 BB 口径）'
#
if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 DE 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 DE 段门项全绿（mac 侧判据脚本不许游离：孤儿探针扩到两个平台 + 裸可执行调用口径 + 排除可执行性守卫；失败计数不许被摘掉：配对门扩到 7 个脚本）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0
# ── 批 DF · 恒真探针的「条件抽取器」不许被掏空 ────────────────────────
# ⚠⚠⚨ **起因（实测坐实 + 对照实验，不是推演）**：
#   恒真探针里有**两个「条件抽取器」**——它们决定「哪些条件会被拿去判恒真」：
#     · `extract_check_conds`（**C++ 判定层**）⇒ 抽出 `check(...)` 的**第三个实参**
#       ⇒ 决定「判定层 396 条判据」这条承诺还成不成立；
#     · `_shell_cond_at`（**shell 侧**）⇒ 抽出每个 `if` 的条件文本
#       ⇒ 决定「shell 881 个条件」这条承诺还成不成立。
#
# ⚠⚠⚨ **实测坐实的洞**：这两个抽取器**都是零门**；
#   且 `extract_check_conds` **连自检都覆盖不到** ——
#   自检的 `cond` 那一档喂的是**裸条件串** ⇒ **压根不经过抽取器**。
#   ⇒ 实测把 `len(args) >= 3` 改成 `>= 99`：
#     **判定层 396 条判据 ⇒ 0 条**（探针照样打印「✓ 判据非恒真」）
#     ⇒ 而**接线门 rc=0 / 探针 rc=0 / 审计器 rc=0** ⇒ ⚠⚠⚨ **三样全绿**
#     ⇒ ⇒ 「判定层每条判据的条件都含被测标识符」这条承诺**彻底消失**，
#        而**没有任何门会说一个字**。
#   ⇒ 第二个变异（`args[2]` ⇒ `args[0]`）同样三样全绿 ⇒ 抽到的变成**第一个实参**
#     ⇒ 条件变成一个**恒真的标识符** ⇒ 承诺变空 ⇒ **假绿坐实**。
#
# ⚠ **修法（两腿，互不依赖 ⇒ 改一边必红）**：
#   ① **内容级门**：两个抽取器的**关键行**逐条整行钉住（含**调用点** ——
#      批 CX 同款教训：「常量在、但扫描时不判」⇒ 定义了不用 ⇒ 等于没定义）；
#   ② **补自检**：新增自检档 `cpp_e2e` ⇒ 样例**必须经过 `extract_check_conds`**
#      ⇒ 抽取器被掏空 ⇒ **自检当场红**（⚠ 原先的 `cond` 档喂裸条件串 ⇒ 覆盖不到）。
# ⚠⚠⚨ **已知边界（如实记着）**：真实语料上的**抽取覆盖率**（判定层 396 条）
#   **没有基线钉住** ⇒ 实测「`check(` 出现 397 次 vs 抽出 396 条」⇒ 差的 1 处是
#   **注释里**的提及 ⇒ 严格交叉校验会**假红** ⇒ 本批**不做**判据数基线；
#   ⇒ 抽取器本身由「内容门 + 合成自检」保证（合成自检不依赖真实语料 ⇒ 零维护成本）。

arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def extract_check_conds\(text\):$' 1 '恒真探针的 **C++ 侧条件抽取器**必须在（⚠⚠⚨ **批 DF**：⚠ 它是**零门 + 零自检**的 ⇒ 实测把 `len(args) >= 3` 改成 `>= 99` ⇒ 判定层 **396 条判据一条都抽不出来**（报「判定层 0 条判据」）⇒ 而**接线门 / 探针 / 审计器三样全绿** ⇒ **假绿坐实**；⚠ **带左括号** ⇒ 改名躲不过）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    for m in re\.finditer\(r.\\bcheck\\s\*\\\(., text\):$' 1 '抽取器的**抽取起点**必须原样（⚠⚠⚨ **批 DF**：⚠ 它认的是 `check(` 这个**调用点**；⚠ 改成别的名字 ⇒ 判定层的判据**一条都抽不出来** ⇒ 396 条判据**不被查**而门全绿 ⇒ **假绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^        if len\(args\) >= 3:$' 1 '抽取器**必须认「第三个实参」**（⚠⚠⚨ **批 DF**：⚠ 判据层 `check(log, "标签", 条件)` 的**条件是第三个实参**；⚠⚠⚨ **实测**：改成 `>= 99` ⇒ 判定层 **396 条 ⇒ 0 条** ⇒ **接线门 / 探针 / 审计器三样全绿** ⇒ **假绿坐实** ⇒ 本门逐字钉住）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^            out\.append\(\(line, args\[2\]\.strip\(\)\)\)$' 1 '抽取器**必须取第三个实参**（⚠⚠⚨ **批 DF**：⚠⚠⚨ **实测**：改成 `args[0]` ⇒ 抽到的变成**第一个实参**（`log` 之类）⇒ 判据条件变成一个**恒真的标识符** ⇒ 「条件含被测标识符」这条**承诺变空**而**三样全绿** ⇒ **假绿坐实** ⇒ 本门逐字钉住）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^        for line, cond in extract_check_conds\(text\):$' 1 '**实扫必须真的走那个抽取器**（⚠⚠⚨ **批 DF**：⚠⚠⚨ **批 CX 同款教训**：「常量在、但扫描时不判」⇒ 定义了不用 ⇒ 等于没定义 ⇒ 396 条判据**不被查**而门全绿 ⇒ **假绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^def _shell_cond_at\(lines, i, kwlen\):$' 1 '恒真探针的 **shell 侧条件抽取器**必须在（⚠⚠⚨ **批 DF**：⚠ 它也是**零门**；⚠ shell 侧 881 个条件全靠它抽出来 ⇒ 它被掏空 ⇒ 那一整片**不被查**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^        cond \+= . . \+ lines\[j\]\.strip\(\)$' 1 'shell 侧抽取器的**跨行拼接**必须在（⚠⚠⚨ **批 DF**：⚠ shell 的 `if` 条件**可以跨行** ⇒ 只取首行 ⇒ 条件被**截断** ⇒ 判定失真 ⇒ **漏判** ⇒ 承诺悄悄变弱）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^        got = _shell_cond_at\(lines, i, len\(kw\) \+ 1\)$' 1 '**shell 实扫必须真的走那个抽取器**（⚠⚠⚨ **批 DF**：⚠⚠⚨ **批 CX 同款教训**：「常量在、但扫描时不判」⇒ 定义了不用 ⇒ 等于没定义）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^        elif kind == .cpp_e2e.:$' 1 '自检**必须真的有** `cpp_e2e` 那一档（⚠⚠⚨ **批 DF**：⚠ 分支被改名/删掉 ⇒ 那 3 条样例**走不到那条判定** ⇒ 自检测的不是真判定 ⇒ **假绿** —— 批 CX 同款教训：「常量在、但扫描时不判」）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^            conds = extract_check_conds\(text\)$' 1 '**自检必须真的经过 `extract_check_conds`**（⚠⚠⚨ **批 DF**：⚠⚠⚨ 这就是**原来那个洞** —— `cond` 那一档喂的是**裸条件串** ⇒ **压根不经过抽取器** ⇒ 抽取器被掏空时自检**照样绿**；⚠ 这一档**必须过抽取器** ⇒ 抽取器坏了 ⇒ 自检红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^            got_bad = sum\(1 for _ln, _c in conds if tautology_reason\(_c\) is not None\)$' 1 '自检必须**走真判定**（⚠⚠⚨ **批 DF**：⚠ 自检自己另写一份判定 ⇒ 测的不是真判定 ⇒ **假的保证** —— 批 BF 纪律：「自检与实扫必须走同一条判定路径」）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    \(.cpp_e2e., \(.check\(log, "标签", true\);\\n., 1\), True\),$' 1 '自检样例里 **C++ 侧「该判红」那一档**不许被掏空（⚠⚠⚨ **批 DF**：⚠ 少了它 ⇒ 抽取器坏掉时**没人发现** ⇒ 396 条判据**不被查**而门全绿 ⇒ **假绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    \(.cpp_e2e., \(.check\(log, "标签", ok && count == 3\);\\n., 0\), True\),$' 1 '自检样例里 **C++ 侧「不该判红」那一档**不许被掏空（⚠⚠⚨ **批 DF**：⚠ 这是**反向护栏** ⇒ 少了它 ⇒ 抽取器乱判也能过）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'
arch_need_count "$SRC/scripts/ci-tautology-check.py" '^    \(.cpp_e2e., \(.check\(log, "标签1", true\);\\ncheck\(log, "标签2", false\);\\n., 2\), True\),$' 1 '自检样例里 **C++ 侧「多条判据」那一档**不许被掏空（⚠⚠⚨ **批 DF**：⚠ 只测单条 ⇒ 「只抽第一条」的抽取器也能过 ⇒ **漏判** ⇒ 承诺悄悄变弱）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DF**'

if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 DF 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 DF 段门项全绿（恒真探针的条件抽取器不许被掏空：C++ 侧 extract_check_conds + shell 侧 _shell_cond_at 的关键行逐条钉住 + C++ 侧补 cpp_e2e 自检档）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0
# ── 批 DG · assets 侧判据脚本不许游离（图标那一套真的进 CI） ──────────────
# ⚠⚠⚨ **起因（实测坐实，不是推演）**：
#   `assets/icon/` 下有**两个判据脚本** ——
#     ① `check-icon.sh`（「所有平台用同一套 icon」这条约束的验收）
#     ② `make-icons.py --check`（产物与母版一致性的**只校验**模式）
#   ⇒ ⚠⚠⚨ **实测坐实**：这两个脚本**不在任何 CI 里**
#     ⇒ 它们的断言**从来没人执行** ⇒ 有人改了图标体系、忘了重跑产物
#     ⇒ **没有任何门会说一个字** ⇒ 承诺悄悄消失。
#   ⇒ ⚠ **与 mac 侧那 6 条白名单不同款**：那两个脚本**本机不可验**
#     （需 macOS + Swift 工具链）⇒ 只能「只登记」；
#     而这两个**本机可跑可验**（Pillow 在、产物入库）⇒ **真的接进 CI**
#     ⇒ 批 DE 遗留的「assets 侧判据脚本游离」**正面收掉**。
#   ⇒ 腿 1：`ci.sh` 新增第 15 步（图标判据）⇒ **步数 15 → 16**
#     （⚠ 步数门、连续门、每步必有门、in_step 全部同步改）；
#   ⇒ 腿 2：孤儿探针扩到**第三个平台 assets**（范围/入口/调用口径/路径前缀
#     **各一份**）⇒ assets 侧以后新增判据脚本却忘了接进 CI ⇒ **会被抓到**。
# ⚠⚠⚨ **工具缺席 ⇒ 未验证（专属码 3）**：图标判据要 Pillow
#   ⇒ 缺席 ⇒ `ci.sh` 显式 SKIP ⇒ 计入 `skip` ⇒ 末尾 `exit 3`
#   ⇒ **未验证不许被当成通过**（批 CB/CC 纪律）⇒ 不许拿「工具没装」
#   冒充「图标不一致」。

arch_need_count "$SRC/scripts/ci.sh" '^    bash "\$SRC/\.\./assets/icon/check-icon\.sh" \|\| _ic2_rc=\$\?$' 1 '第 15 步 assets 图标一致性验收的**动作还在**（⚠⚠⚨ **批 DG**：⚠ 这个脚本以前**不在任何 CI 里** ⇒ 它的断言**从来没人执行** ⇒ 「三个平台同一套 icon」这句承诺**没人守** ⇒ 接进 CI 后必须钉住调用点，⚠ **整行锚定**（批 BN）｜⚠⚠⚨ **批 DG**'

arch_need_count "$SRC/scripts/ci.sh" '^    python3 "\$SRC/\.\./assets/icon/make-icons\.py" --check \|\| _ic_rc=\$\?$' 1 '第 15 步 assets 图标**产物与母版一致性校验**的动作还在（⚠⚠⚨ **批 DG**：⚠ `make-icons.py --check` 是**只校验不写文件**的判据模式 ⇒ 它以前也**不在任何 CI 里** ⇒ 产物与母版分家时**没有任何门会说一个字** ⇒ 现在接进 CI，⚠ **整行锚定**｜⚠⚠⚨ **批 DG**'

arch_need_count "$SRC/scripts/ci.sh" '^if python3 -c .from PIL import Image. >/dev/null 2>&1; then$' 1 '第 15 步**必须先探工具**再跑图标判据（⚠⚠⚨ **批 DG**：⚠⚠⚨ 少了这一探 ⇒ Pillow 缺席时 `check-icon.sh` 会把「PIL-缺」当成「母版不合法」⇒ **把「工具没装」说成「图标不一致」**⇒ **码值语义被顶替**（批 CC 纪律）⇒ 现在缺席 ⇒ SKIP ⇒ 计入 `skip` ⇒ 末尾专属码 3｜⚠ **整行锚定**｜⚠⚠⚨ **批 DG**'

arch_need_count "$SRC/scripts/ci.sh" '^    echo "SKIP: Pillow 未安装（图标判据未验证：母版包围盒那节需要 PIL）"$' 1 '第 15 步的**未验证提示**必须在（⚠⚠⚨ **批 DG**：⚠ 少了它 ⇒ 日志里只剩一句「✓ 通过」⇒ 读日志的人**分不出这一组到底验没验**（批 CC 同款口径）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DG**'

arch_need_ml "$SRC/scripts/ci.sh" 'SKIP: Pillow 未安装[^"]*"[[:space:]]+skip=' 'Pillow 缺席那一处**必须紧跟计数**（⚠⚠⚨ **批 DG**：⚠ 少了计数 ⇒ 「图标判据没验」被当成「通过」⇒ **未验证不许被当成通过**（批 CK 同款口径）｜⚠ **跨行锚定**｜⚠⚠⚨ **批 DG**'

arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^ASSETS_SCOPE="\$ROOT/assets"$' 1 '孤儿探针的 **assets 侧范围目录**必须在（⚠⚠⚨ **批 DG**：⚠ 范围被静默收窄 ⇒ `assets/icon/` 下那两个判据脚本**没人查**而门全绿 ⇒ **假绿**；⚠ 范围不许被改成别的目录）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DG**'

arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^ASSETS_ENTRY="\$SRC/scripts/ci\.sh"$' 1 '孤儿探针的 **assets 侧 CI 入口**必须是 `ci.sh`（⚠⚠⚨ **批 DG**：⚠ assets 侧**没有自己的 CI** ⇒ 它的判据脚本只能由 deepin CI 驱动 ⇒ 入口算错 ⇒ 可达集合算在别的文件上 ⇒ 两个脚本**全成游离**或**全成可达** ⇒ 门失准）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DG**'

arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^_CALL_PATH_ASSETS=.\[\^"\]\*/assets/\[A-Za-z0-9\._/-\]\+\\\.\(sh\|py\).$' 1 '孤儿探针的 **assets 侧路径片段**必须原样（⚠⚠⚨ **批 DG**：⚠ 它**不共用** `_CALL_PATH`（那份只认 `/scripts/` 下）⇒ 共用口径 ⇒ assets 的路径**一个都认不出** ⇒ 可达集合为空 ⇒ 两个脚本全成「游离」⇒ **假红**；⚠ 片段被改窄 ⇒ 漏检 ⇒ **假绿**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DG**'

arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^CALL_RE_ASSETS="\(sh\|bash\|python3\?\)\[\[:space:\]\]\+\\"\?\$\{_CALL_PATH_ASSETS\}"$' 1 '孤儿探针的 **assets 侧调用点口径**必须真的用 assets 那份路径片段（⚠⚠⚨ **批 DG**：⚠ 改成 `_CALL_PATH` ⇒ 认不出 assets 路径 ⇒ 两个脚本全成「游离」⇒ **假红**；⚠ 这条与「assets 侧路径片段」那一条**配对** ⇒ 改一边必红）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DG**'

arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^_STRIP_ASSETS=.\.\*/assets/.$' 1 '孤儿探针的 **assets 侧路径前缀**必须原样（⚠⚠⚨ **批 DG**：⚠ 它决定「抽出来的名字能不能对上 scope 下的相对路径」⇒ 错了 ⇒ 白名单「指向不存在的脚本」⇒ **假红**；⚠ 改成 `.*/scripts/` ⇒ 名字剥不掉前缀 ⇒ 对不上 ⇒ 失准）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DG**'

arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^    _strip="\$_STRIP_DEEPIN"$' 1 '孤儿探针的**路径前缀默认值**必须在（⚠⚠⚨ **批 DG**：⚠ deepin/macos 两个平台**共用** `scripts/` 前缀 ⇒ 抽出来的名字要能对上 scope 下的相对路径；⚠ 少了这一行 ⇒ `$_strip` 为空 ⇒ 剥不掉前缀 ⇒ 两个平台的名字全带目录 ⇒ 白名单与可达判定**双双失准**）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DG**'

arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^        assets\) _scope="\$ASSETS_SCOPE"; _entry="\$ASSETS_ENTRY"; _re="\$CALL_RE_ASSETS"; _strip="\$_STRIP_ASSETS" ;;$' 1 '孤儿探针的 **assets 平台分支**必须真的走 assets 那份范围/入口/口径/前缀（⚠⚠⚨ **批 DG**：⚠ 少这一支 ⇒ 平台清单里有 assets 但**没有分支** ⇒ fail closed 判红；⚠ 走错分支 ⇒ 那一整片脚本**全成游离**或**全成可达** ⇒ 门失准）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DG**'

arch_need_count "$SRC/scripts/ci-orphan-probe.sh" '^echo "✓ 无游离断言脚本：三个平台共 \$n_assert_total 个断言脚本全部在 CI 里可达（白名单 \$n_wl 条，每条带理由）"$' 1 '孤儿探针的**汇总文案**必须说「三个平台」（⚠⚠⚨ **批 DG**：⚠ 文案说两个 ⇒ 读日志的人以为**只查了两个平台** ⇒ 承诺的覆盖面**被说窄了** ⇒ 与实际行为不一致（批 BA/BB 纪律）｜⚠ **整行锚定**｜⚠⚠⚨ **批 DG**'


if [ "$ARCH_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：批 DG 段有门项红（上面带 ✗ 的行）" >&2
    ARCH_ANY_FAIL=1
else
    echo "✓ 批 DG 段门项全绿（assets 侧图标判据接进 CI + 孤儿探针扩到第三平台 assets）；门项合计 ${ARCH_N} 项（含前段）"
fi
ARCH_FAIL=0







# ⚠⚠⚨ 批 CG · **剥注释失败**必须被看见（工具失败 ≠ 没找到）。
#   ⇒ 放在「✓ 全绿」**之前** ⇒ 那个「✓」永远打不出来
#     （批 CE 的教训：诊断失真最贵；⚠⚠⚨ 实测：剥注释失败时
#       forbid 门会判「没找到」⇒ **静默变绿** ⇒ 违例被漏检）。
#   ⇒ ⚠⚠⚨ 覆盖**全部**剥注释调用点（forbid / need / count / any …）
#     ⇒ 一次挡住整类（批 CD 纪律：一次挡住整类，别逐点治标）。
if [ -s "$STRIP_FAIL_FILE" ]; then
    # ⚠⚠⚨ 批 CH：诊断**搬进 trap**了（退出时必打）⇒ 这里只负责 exit 1
    #   ⇒ 否则「段落 ARCH_FAIL 提前 exit」会把末尾的诊断吃掉 ⇒ 红因指错（⚠⚠⚨ 批 CP：段级 trailer 已不再提前 exit ⇒ 这条隐患已收）
    exit 1
fi
# ⚠⚠⚨ 批 CP · **末尾统一判红**（段级 trailer 不再提前 exit ⇒ 全部门项都跑完）
#   ⇒ 退出码语义**不变**（红 = 1）⇒ 但诊断是**全的**（一处红不再遮住后面所有问题）
if [ "$ARCH_ANY_FAIL" -ne 0 ]; then
    echo "✗ 接线门失败：有门项红（上面带 ✗ 的行）" >&2
    exit 1
fi
exit 0
