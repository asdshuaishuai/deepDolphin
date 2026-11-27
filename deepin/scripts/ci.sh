#!/usr/bin/env bash
# ci.sh — deepin 客户端本地 CI 门（DDE-INTEGRATION-PLAN.md §4.1/§4.3）。
#
# ⚠ **这份清单必须与下面的步骤打点一一对应**（批 BA：12 步逐个钉了门；
#   批 BD 起扩到 14 步，批 BF 起 15 步，⚠⚠⚨ **批 DG 起 16 步**
#   —— 批 DG 把 assets 侧两个判据脚本接进 CI）⇒ 改步骤就改这份清单，也改门。
# 1. --selfcheck：断言「0 failed 且 ≥58 passed」（例数只增不减）
# 2. 截图矩阵（亮/暗 × 4 页）→ docs/snapshots，落盘后人工 diff 基线
# 3. desktop / metainfo 校验：desktop-file-validate / appstream-util 缺工具显式 SKIP
#    （SKIP 不算失败——工具随 deepin 打包环境到位，硬门随之生效）
# 4. 无头探针三件套：ci-platform-probe.sh（--platform-probe 正式断言：exit 0 且输出含
#    backend= 行）+ ci-docs-lang-probe.sh（四语言切换真跑）+ ci-divider-probe.sh（分隔线真渲染）
# 5. D2 grep 门：DS::*（DesignTokens）之外出现色值/px 字号即缺陷 —— 独立成
#    scripts/ci-d2.sh（可单独跑，负控能精确打）。批 N 已把 M3-3 登记的 4 处存量
#    全收进 token，上限降到 0（只减不增）
# 6. --agent-selftest（恒走 mock 渠道）：退出码 + FINAL 标记 + 收尾标记三断言
# 7. verify 接线源扫描门：引擎 verify 的判定层与接线点必须都在（判定不许藏回视图）
# 8. 图谱 Canvas 契约门：Canvas2D 覆盖契约清单 26 个方法 + logic/models 零 QWidget 头
#  9. 架构图接线门：取数（graph arch --format scene）→ 判定（视口/命中/回执）→
#     渲染（SceneRender → Canvas2D）→ 接线（详情页入口 → 面板 → 架构图窗 → 画布）四段都在；
#     生成/导出必须走 Text 契约（回执型命令，stdout 是人话不是 JSON）
# 10. 引擎契约门：scripts/contract-check.sh（真引擎沙箱；引擎缺席显式 SKIP 且不算通过）
# 11. deb 打包：scripts/build-deb.sh（依赖清单双向校验 + 产物零环境变量下无缺失库）
# 12. deb 布局验收：scripts/check-deb-layout.sh（装完能不能用：service/desktop/图标/metainfo）
# 13. agent 工具面收敛：scripts/probe-agent-tool-surface.sh（引擎标的废弃别名不得留在
#     模型可见面/系统提示词里，但仍留在必填校验表里；引擎缺席/太老 ⇒ 显式 SKIP）
# 14. 无游离断言脚本：scripts/ci-orphan-probe.sh（scripts/ 下每个断言脚本都必须在 CI
#     里可达，否则进**带理由的白名单** ⇒ 「少了一份断言」不可能再悄无声息）
# 15. assets 侧图标判据：assets/icon/make-icons.py --check（产物与母版一致）
#     + assets/icon/check-icon.sh（三个平台同一套 icon）—— ⚠⚠⚨ 批 DG：这两个脚本
#     以前**不在任何 CI 里** ⇒ 它们的断言从来没人执行 ⇒ 现在接进 CI；
#     ⚠ 需 Pillow：缺席 ⇒ 显式 SKIP（**未验证不许被当成通过**）
# 16. 判据不许被掏空成恒真：scripts/ci-tautology-check.py（判定层的判据条件必须含被测
#     标识符；shell 断言脚本的 if 条件不许恒真/恒假 ⇒ 判据**条数不变但条件被掏空**也抓得住）
#
# 用法：scripts/ci.sh [build目录]（默认 build/）
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-$SRC/build}"
# ⚠ **绝对化**：批 AZ 起 selfcheck/agent-selftest 要 `cd` 进 core 目录再跑
#   （core_pattern 是相对名 ⇒ core 落在进程 cwd ⇒ cwd 必须是专用目录）。
#   ⇒ 若 BUILD 是相对路径（用户传 `scripts/ci.sh build`），cd 之后 $BIN 就找不到了。
#   ⇒ 这里先绝对化（`cd` 到不存在的目录会失败 ⇒ 用 `|| true` 兜住，保留原值）。
BUILD="$(cd "$BUILD" 2>/dev/null && pwd || echo "$BUILD")"
BIN="$BUILD/deepDolphin"
# ⚠⚠⚨ 批 DW：`BIN` **export** 出去 ⇒ 双跑覆盖面门（`ci-shell-parity.sh`）拿的是**同一个**二进制
#   ⇒ **单一真相源** ⇒ 两个地方各算一遍 ⇒ 算出不同路径 ⇒ 又一个新洞
#   ⇒ 登记册里参数列 = `bin` 的条目就靠它（没它 ⇒ 那几条双跑不了 ⇒ 门 fail closed）
export BIN
# ⚠⚠⚨ 批 CK · 「未验证」不许被当成「通过」——**CI 自己这层**。
#   ⇒ 盘点 `scripts/` 下所有「跳过/未验证」出口 ⇒ ci.sh 自己就有 **6 处**
#     「只打印、不计数」⇒ CI 继续 ⇒ 最后照样打「✓ CI 门通过」
#     ⇒ ⚠⚠⚨ **未验的组被当成「通过」** ⇒ 假绿。
#   ⇒ 其中 ④⑤ 两处是 **D7 达标的必经**（deb 构建 / deb 布局验收）。
#   ⇒ 口径与第 10 步（契约门，批 CI）**同款**：未验证 ⇒ 专属退出码 3 ⇒ 判红。
skip=0

# ⚠⚠⚨ 批 CF · 剥注释口径的**前提**是 perl 在（默认分支靠它剥 C++ 的 `//` 注释）。
#   ⇒ 以前 perl 缺席时**静默降级**到 sed 兜底 ⇒ **口径变了** ⇒ 同一个门项两边结论可能相反
#     ⇒ 而**没有任何一条消息说「perl 缺失」** ⇒ 排障方向被带偏。
#   ⇒ 现在：缺 perl ⇒ **响亮失败**（未验证不许被当成通过；批 CB/CC/CD/CE 同款口径）。
# ⚠ 抽取的前提：单一真相源文件必须在（抽不到 ⇒ 函数未定义 ⇒ 调用时报
#   "command not found" ⇒ 退出码 127 ⇒ 在 `|| true` 里被吞 ⇒ **静默失效**）。
# ⚠⚠⚨ 批 CG · **剥注释失败**必须被看见（工具失败 ≠ 没找到）。
#   ⇒ 标记文件（跨子 shell ⇒ 必须用文件，变量传不出去）
#   ⇒ 抽取过来的 strip_comments 失败时写它；脚本末尾统一检查 ⇒ 有 ⇒ 判红。
STRIP_FAIL_FILE="${TMPDIR:-/tmp}/deepdolphin-strip-fail.$$"
trap '_ch_rc=$?; if [ -s "$STRIP_FAIL_FILE" ]; then echo "✗ 剥注释失败（工具失败 ≠ 没找到）——这些文件的匹配结果**不可信**：$(sort -u "$STRIP_FAIL_FILE" | tr "\n" " ")" >&2; _ch_rc=1; fi; rm -f "$STRIP_FAIL_FILE"; exit $_ch_rc' EXIT
[ -f "$SRC/scripts/ci-wiring.sh" ] || {
    echo "✗ 找不到 $SRC/scripts/ci-wiring.sh（剥注释口径的单一真相源 ⇒ 抽不到就等于没有门）" >&2
    exit 1
}
command -v perl >/dev/null 2>&1 || {
    echo "✗ 没有 perl（剥注释工具）⇒ 判据口径无法确定 ⇒ **未验证不许被当成通过**" >&2
    exit 1
}

# 运行库环境提前到步骤 1 之前：selfcheck 也要加载 sysroot 的 Qt6/DTK6——原先导出
# 在步骤 2，无 sysroot rpath 的环境下步骤 1 的二进制根本起不来。用"无条件前置 +
# 保留旧值"而非 ${VAR:-默认}：预置了 LD_LIBRARY_PATH 的环境（如容器运行时自带
# /opt/... 路径）会原样沿用旧值，sysroot 永远进不去。
export LD_LIBRARY_PATH="$HOME/.local/dd-sysroot/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$HOME/.local/dd-sysroot/usr/lib/x86_64-linux-gnu/qt6/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

# ── 崩点可诊断（批 AZ）────────────────────────────────────────────────────
# ⚠ **为什么要有**：批 AY 记过一次「ci.sh 输出里出现段错误回栈、而 ci.sh 退出码仍是 0」。
#   那次**根因没定位**（2 次都未复现）⇒ 唯一能推进的是「**下次复现时要能查**」。
#   ⇒ 这里把三样东西备好：
#   ① **完整输出落盘**（selfcheck.err / agent-selftest.out|err）—— 批 AY 的栈
#      被 `| tail -2` 截断 ⇒ 白丢线索 ⇒ 这条不许再犯。
#   ② **core dump 开着**（`ulimit -c`）—— 本机**没有 gdb**，但 `strings core`
#      还能看出是哪个库/哪个符号 ⇒ 比一句「Segmentation fault」有用得多。
#      ⚠ 实测：`core_pattern` 是相对名 `core`（core_uses_pid=1 ⇒ 文件名带 pid）
#        ⇒ core 落在**崩溃进程的 cwd** ⇒ 必须在**专用目录**里跑，别落进仓库根。
#      ⚠ 实测单位：`ulimit -c` 在 bash 下是 1024 字节/单位、dash 下是 512 字节/单位
#        ⇒ 这里给的值在两种 shell 下分别是 256MB / 128MB 上限（都够用，且不会撑爆磁盘）。
#   ③ **崩了要说清「崩在哪一步」**（信号名 + 退出码 + core 路径 + stderr 全文）。
#
# ⚠ **core 目录不进 git**：`build/` 已被 .gitignore 忽略 ⇒ core 落这儿不会脏工作区。
CRASH_DIR="$BUILD/crash"
mkdir -p "$CRASH_DIR"
# 256MB（bash）/ 128MB（dash）上限：够抓栈，又不会把磁盘写满。
ulimit -c 262144 2>/dev/null || true
# 打印最近一次 core 的路径（崩了才用得上；没有就什么都不打）。
# ⚠⚠ **末尾必须 `|| true`**（批 AZ 实测踩到的坑）：
#   「没有 core 时 `ls` 退出码非 0」在 `set -euo pipefail` 下会**反噬**：
#   `ls | head -1` 的管道码 = ls 的非 0 ⇒ 命令替换 `_core="$(latest_core)"`
#   拿到的退出码非 0 ⇒ **赋值语句本身失败** ⇒ `set -e` 直接把脚本带走
#   （实测 dash/bash 都是 rc=2，**后面那句诊断根本打不出来**）。
#   ⇒ 这里必须显式兜住，让「没有 core」是一个**正常分支**而不是脚本终止。
# ⚠ 实测命名：`core_pattern` 是相对名 `core`、`core_uses_pid=1`
#   ⇒ 实际落盘文件名是 **`core.<pid>`**（实测 `core.1565590`）⇒ glob 用 `core.*` 正好。
latest_core() {
    ls -t "$CRASH_DIR"/core.* 2>/dev/null | head -1 || true
}

SC_MIN=395
echo "› 1/16 selfcheck（断言 0 failed 且 ≥58 passed 且判据数 == $SC_MIN 条不许被删）"
# ⚠⚠⚠ **不许用 `|| true` 吞掉 selfcheck 的退出码**（批 AZ 实测出来的真洞）：
#   原来这行是 `SELFCHECK_OUT="$("$BIN" --selfcheck || true)"` ⇒ **退出码被丢弃**。
#   ⚠⚠ **要分清两种「吞退出码」**（批 AY 的「`| tail` 吞退出码」在这里**不成立**）：
#     `ci.sh` 顶部有 `set -euo pipefail` ⇒ 实测（dash 与 bash 都试过）
#     `false | tail -2` 会让**整个脚本以 1 退出** ⇒ **管道没有吞退出码**。
#     而 `$( cmd || true )` 里的 `|| true` 是**在命令替换内部** ⇒ 它把 `cmd` 的
#     退出码变成 0 ⇒ **命令替换整体成功** ⇒ 外层什么也看不出来。
#   ⇒ **崩在汇总行之后**时（stdout 已完整打出 "N passed, M failed"，随后才段错误）
#     解析照样成功 ⇒ **门放行**（实测：假二进制打印完汇总行再 `kill -SEGV` ⇒ 门判绿）。
#   ⚠ 这**正好解释**批 AY 记的那次现象：「ci.sh 输出里出现段错误回栈、而 ci.sh 退出码仍是 0」
#     —— 崩掉的子进程退出码没人看 ⇒ CI 误判通过（那次的栈在 libQt6Core）。
#   ⇒ 现在：**退出码单独收**；信号退出（139=SIGSEGV / 134=SIGABRT / 141=SIGPIPE）
#     **显式判红**，并把 stderr（CrashHandler 打的回栈）**原样打出来**。
# ⚠ stderr 必须**落盘**再打：CrashHandler 的回栈只有十几行，全打出来才知道崩在哪。
#   （批 AY 的教训：栈被 `| tail -2` 截断 ⇒ 白丢线索 ⇒ 下次复现查不了。）
SELFCHECK_RC=0
# ⚠ 在 CRASH_DIR 里跑：core_pattern 是相对名 ⇒ core 落在**进程的 cwd**
#   ⇒ cwd 必须是专用目录（崩了才有 core 可查），不能是仓库根（会脏工作区）。
#   ⚠ 实测：selfcheck **不依赖 cwd**（在 /tmp 跑与在仓库跑，395/0 一致）。
( cd "$CRASH_DIR" && "$BIN" --selfcheck 2>"$BUILD/selfcheck.err" ) >"$BUILD/selfcheck.out" || SELFCHECK_RC=$?
if [ "$SELFCHECK_RC" -ge 128 ]; then
    # 128+n ⇒ 被信号 n 杀死（bash/dash 惯例）。这一类**必须判红**，不能当「输出解析不了」糊过去。
    SC_SIG=$((SELFCHECK_RC - 128))
    SC_SIG_NAME="$(kill -l "$SC_SIG" 2>/dev/null || echo "信号$SC_SIG")"
    echo "✗ selfcheck 被信号杀死（$SC_SIG_NAME / 退出码 $SELFCHECK_RC）—— 崩了，不是判据不达标" >&2
    if [ -s "$BUILD/selfcheck.err" ]; then
        echo "  ---- selfcheck stderr（含 CrashHandler 回栈）----" >&2
        sed 's/^/    /' "$BUILD/selfcheck.err" >&2
    fi
    _core="$(latest_core)"
    if [ -n "$_core" ]; then
        echo "  ⇒ core dump：$_core（本机无 gdb ⇒ 可用 strings 看符号）" >&2
    fi
    exit 1
fi
SELFCHECK_OUT="$(cat "$BUILD/selfcheck.out")"
printf '%s\n' "$SELFCHECK_OUT" | tail -1
SC_PASSED="$(printf '%s\n' "$SELFCHECK_OUT" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '[0-9]+' || true)"
SC_FAILED="$(printf '%s\n' "$SELFCHECK_OUT" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '[0-9]+' || true)"
if [ -z "$SC_PASSED" ] || [ -z "$SC_FAILED" ]; then
    echo "✗ selfcheck 输出无法解析（期待尾行 selfcheck: N passed, M failed——崩溃/早退？）" >&2
    if [ -s "$BUILD/selfcheck.err" ]; then
        echo "  ---- selfcheck stderr ----" >&2
        sed 's/^/    /' "$BUILD/selfcheck.err" >&2
    fi
    exit 1
fi
if [ "$SC_FAILED" -ne 0 ] || [ "$SC_PASSED" -lt 58 ]; then
    echo "✗ selfcheck 未达标：${SC_PASSED} passed / ${SC_FAILED} failed（要求 0 failed 且 ≥58 passed）" >&2
    exit 1
fi
# ⚠⚠ **判据只许增不许减**（批 AJ）：以前只断言「≥58 passed」——
#   58 是 2024 年的老数字 ⇒ **删掉 300 条判据照样全绿**。
#   ⇒ 判据是「契约的牙齿」，删一条就少一颗牙，而门看不见。
# ⚠ 口径 = **判据条数**（passed 数）。抓不到「删一条又加一条」那种换名操作（少见）。
# ⚠ **基线写死在本脚本里**（与上面「≥58」同一做法）⇒ 改基线 = 改脚本 = 评审看得见。
#   刻意**不**用单独的基线文件：那个文件会被顺手改小 ⇒ 门跟着一起松 ⇒ 等于没门。
#
# ⚠⚠⚠⚠ **判定必须是「完全相等」，不是「不少于」**（批 BB 实测出来的）：
#   原来这里是 `-lt "$SC_MIN"`（**只要不少于基线就算过**）⇒
#   ⚠⚠ **余量 = 基线与实际判据数之差**，而那个差**没人盯**：
#     批 AJ 时基线 393 = 实际 393 ⇒ 严丝合缝；
#     此后**加了 2 条判据**（393 → 395）而**基线没跟着加** ⇒ 余量变成 **2**
#     ⇒ ⚠⚠ **可以删 2 条判据，门照样绿** ⇒
#     「判据不许被删 ⇒ 有判据被删了 ⇒ 红」这个承诺**当时是假的**。
#   ⚠⚠⚠ **实测复现**（批 BB 负控）：删掉 1 条判据 ⇒ 第 1 步**真实门 rc=0（绿）**。
#   ⚠⚠⚠ **更糟的是：原注释把方向写反了** —— 原话是
#     「加判据时同步把 SC_MIN 加一（忘了加只是门偏**严**，不会偏**松** ⇒ 安全方向）」
#     ⇒ **恰恰相反**：忘了加 ⇒ 基线落后于实际 ⇒ **门偏松** ⇒ **正是不安全的那一侧**。
#     ⇒ 同样的错在**台账 E.1s** 与 **PLAN §10** 里也各写了一遍 ⇒ 本批一并订正。
#
# ⇒ 现在改成**必须相等** ⇒ **余量恒为 0**：
#   · 加了判据忘了同步基线 ⇒ **红**（逼人同步 ⇒ 余量攒不出来）
#   · 删了判据 ⇒ **红**
#   · 基线被调小 ⇒ **红**（基线 ≠ 实际）
# ⚠ 代价（明写在这儿，别当成 surprise）：**每次加判据要同步改 SC_MIN**。
#   这正是「承诺要有牙」的成本 —— 批 AJ 当年也是这个成本，只是它写反了方向。
if [ "$SC_PASSED" -ne "$SC_MIN" ]; then
    echo "✗ selfcheck 判据数 ${SC_PASSED} ≠ 基线 ${SC_MIN} ⇒ 判据数与基线必须**完全相等**" >&2
    echo "  （判据是契约的牙齿：删一条就少一颗牙，而门本该看见）" >&2
    echo "  · 加了判据 ⇒ 请把 scripts/ci.sh 的 SC_MIN 改成 ${SC_PASSED}" >&2
    echo "  · 确实要删判据 ⇒ 请一并调小 SC_MIN 并在提交信息里写明理由（改基线 = 改脚本 = 评审看得见）" >&2
    exit 1
fi
echo "✓ selfcheck ${SC_PASSED} passed, ${SC_FAILED} failed"

echo "› 2/16 截图矩阵（离屏）"
# ⚠ 这一步**强制** offscreen，不继承环境里的 QT_QPA_PLATFORM。
#   理由（决策 86）：基线是离屏拍的；若宿主已设 QT_QPA_PLATFORM=dxcb;xcb，
#   快照会带 DTK 原生窗口装饰与 chameleon 样式 —— 同一份代码拍出另一张脸，
#   视觉 diff 门被环境牵着走。离屏才是「同机位」的可复现前提。
#   注意：第 4 步的平台探针**要**真实 backend，故那里不强制 offscreen。
mkdir -p "$SRC/docs/snapshots"
# ⚠⚠ **本批（批 AN）改的关键一处**：基线必须来自 **git 里已提交的版本**，
#   不能是「本次跑出来的产物」。
#   原来这里直接拍进 `docs/snapshots/*.png`（**覆盖**基线），
#   后面两道门再拿「刚覆盖完的基线」跟新拍的一张比 ⇒ **自己跟自己比** ⇒ 恒绿。
#   ⚠ 后果：基线漂了（今天拍 A、昨天拍 B）这道门也抓不到 ——
#   因为它比的是「本次产物 vs 本次产物」。实测（批 AN）同机并发能拍出 4 种字节，
#   而旧门一道都没红 ⇒ 「基线必须逐字节可重现」这句承诺**当时是假的**。
#   ⇒ 现在：**先取 git 里的基线**（`git show HEAD:...`）到临时目录，
#   所有比对都用它；本次产物另存到临时目录，两者比。
#   ⚠ 「本次产物 vs git 基线」不一致时**报错退出**（视觉改动必须有人看过并提交），
#     而不是默默把新图写回工作区让人自己看 diff。
BASE_DIR="$(mktemp -d)"
SHOT_DIR="$(mktemp -d)"
base_available=1
for theme in light dark; do
    for sec in dashboard board milestones setupguide; do
        rel="docs/snapshots/${theme}-${sec}.png"
        if git -C "$SRC" cat-file -e "HEAD:deepin/$rel" 2>/dev/null; then
            git -C "$SRC" show "HEAD:deepin/$rel" > "$BASE_DIR/${theme}-${sec}.png"
        else
            base_available=0
        fi
    done
    rel="docs/snapshots/${theme}-colors.png"
    if git -C "$SRC" cat-file -e "HEAD:deepin/$rel" 2>/dev/null; then
        git -C "$SRC" show "HEAD:deepin/$rel" > "$BASE_DIR/${theme}-colors.png"
    else
        base_available=0
    fi
done
if [ "$base_available" -eq 0 ]; then
    echo "✗ 取不到 git 里的基线（首次提交前跑 ci.sh 会这样）" >&2
    echo "  ⇒ 先提交一次快照基线，再跑 CI；本次产物留在 $SHOT_DIR" >&2
    rm -rf "$BASE_DIR"
    exit 1
fi
for theme in light dark; do
    # ⚠ setupguide = **引擎缺失首屏**（批 AH）：那个界面在正常启动时根本不出现
    #   （引擎在 ⇒ 落仪表盘）⇒ 以前 docs/snapshots/*-setupguide.png 是**死基线**
    #   （拍不出、没人比）——死基线比没基线更隐蔽：它让人以为「首屏有视觉保障」。
    for sec in dashboard board milestones setupguide; do
        # ⚠⚠ **不要用 `| tail -1`**：管道的退出码是 **tail 的** ⇒ 快照进程失败
        #   （退出码非 0）会被**静默吞掉** ⇒ 拍出来是半张图也不报。
        #   ⇒ 改用「先存输出再取最后一行」，并**检查真实退出码**。
        if ! QT_QPA_PLATFORM=offscreen DEEPDOLPHIN_THEME="$theme" "$BIN" --snapshot \
                "$SHOT_DIR/${theme}-${sec}.png" --section "$sec" \
                >"$SHOT_DIR/out.txt" 2>"$SHOT_DIR/err.txt"; then
            echo "✗ 快照失败：${theme}-${sec}" >&2
            grep -v "setHighDpiScaleFactorRoundingPolicy\|can not find qm files\|DGuiApplicationHelper:\|This plugin does not support\|DPlatformWindowInterface" \
                "$SHOT_DIR/err.txt" | sed 's/^/    /' >&2
            rm -rf "$BASE_DIR" "$SHOT_DIR"
            exit 1
        fi
        tail -1 "$SHOT_DIR/out.txt"
    done
    # 状态色样张（批 R）：把**每一档状态色**都画出来，改色 ⇒ 色卡 diff 红。
    #   （批 T 之前，面板快照拍的是空态 ⇒ 状态点一个都没画进去，对状态色是**空门**；
    #     批 T 起用夹具后面板快照已有真实内容，但这张色卡仍留着 ——
    #     它是**逐档**的，面板快照只覆盖夹具里恰好出现的那几档。）
    #   ⚠ 同上：色卡也不许用管道接 tail（失败会被吞）
    if ! QT_QPA_PLATFORM=offscreen DEEPDOLPHIN_THEME="$theme" "$BIN" --color-sample \
            "$SHOT_DIR/${theme}-colors.png" >"$SHOT_DIR/out.txt" 2>"$SHOT_DIR/err.txt"; then
        echo "✗ 色卡失败：${theme}-colors" >&2
        grep -v "setHighDpiScaleFactorRoundingPolicy\|can not find qm files\|DGuiApplicationHelper:\|This plugin does not support\|DPlatformWindowInterface" \
            "$SHOT_DIR/err.txt" | sed 's/^/    /' >&2
        rm -rf "$BASE_DIR" "$SHOT_DIR"
        exit 1
    fi
    tail -1 "$SHOT_DIR/out.txt"
done
# ⚠ 本次产物 vs **git 基线**：不一致 = 界面改了 ⇒ 必须有人看过并提交。
#   （原来这一步不存在：产物直接覆盖了基线 ⇒ 永远「一致」⇒ 视觉 diff 门是空门。）
visual_changed=0
for f in "$SHOT_DIR"/*.png; do
    name=$(basename "$f")
    if ! cmp -s "$BASE_DIR/$name" "$f"; then
        echo "✗ 视觉变了：$name 与 git 基线不同（请人工确认后提交基线）" >&2
        visual_changed=1
    fi
done
if [ "$visual_changed" -ne 0 ]; then
    echo "✗ 视觉改动未提交 —— 基线必须与代码同版本，否则 diff 门是空门" >&2
    echo "  本次产物在 $SHOT_DIR（确认无误后 cp 过去再提交）" >&2
    rm -rf "$BASE_DIR"
    exit 1
fi
echo "✓ 8 张快照与 git 基线逐字节一致（无未提交的视觉改动）"

# ⚠ **重拍比字节**（批 T）—— 基线必须**逐字节可重现**。
#   为什么这道门是硬的：基线一旦带墙钟（侧栏「上次刷新 HH:mm」是本地时区渲染），
#   CI **每次**都出 diff ⇒ 人就学会忽略 diff ⇒ 基线退化成空门（比没门更糟）。
#   这道门盯的是**行为**（同一份代码两次拍出同一张图），不是「我改的这两个文件看着对」——
#   将来谁往渲染路径里塞了墙钟，它就红。
#   夹具 + 固定刷新时刻 + 快照进程固定 TZ=UTC（见 main.cpp）⇒ 6 张面板快照逐字节恒定。
#
# ⚠ **再拍一份「换了时区的」**：这一拍专门抓「渲染跟着宿主时区走」。
#   应用内部固定 TZ=UTC ⇒ 外层 TZ 传什么都一样 ⇒ 字节必须相同。
#   哪天有人把 main.cpp 里那句 qputenv("TZ","UTC") 删了 ⇒ 宿主时区渗进来
#   ⇒ 这两张立刻不同 ⇒ 门红（而只靠接线门盯那一行是不够的：门要能**行为**地抓住）。
# ⚠ 对比的必须是**两个互相不同**的时区（UTC 与 America/New_York）——
#   若拿「宿主时区」当其中一个，宿主恰好就是那个时区时（实测本机就是 Asia/Shanghai）
#   ⇒ 两张必然相同 ⇒ 门永远绿 ⇒ 又一个空门（负控实测，第十五次「同名/同形互相顶替」）。
REPRO_DIR="$(mktemp -d)"
repro_fail=0
# ⚠⚠ **失败时必须留下原因**（批 AN 实测踩出来的盲点）：
#   原来这里是 `>/dev/null 2>&1` ⇒ 快照进程失败时**退出码非 0 但什么也看不见**。
#   ⇒ 「✗ 重拍失败：xxx」这句话本身不含原因 ⇒ 下一次再遇到只能从头猜
#   （批 AN 查那个偶发失败查了很久，就是因为这个）。
#   ⇒ 现在把 stderr 收进临时文件，失败时**原样打出来**。
repro_shoot() { # repro_shoot <主题> <区块> <输出路径> <TZ>
    TZ="$4" QT_QPA_PLATFORM=offscreen DEEPDOLPHIN_THEME="$1" "$BIN" --snapshot \
        "$3" --section "$2" >/dev/null 2>"$REPRO_DIR/stderr.txt"
    rc=$?
    if [ "$rc" -ne 0 ] && [ -s "$REPRO_DIR/stderr.txt" ]; then
        # ⚠ 只留**有诊断价值**的行（DTK 的环境告警每次都有 ⇒ 全打等于噪声）
        grep -v "setHighDpiScaleFactorRoundingPolicy\|can not find qm files\|DGuiApplicationHelper:\|This plugin does not support\|DPlatformWindowInterface" \
            "$REPRO_DIR/stderr.txt" | sed 's/^/    /' >&2
    fi
    return $rc
}
for theme in light dark; do
    for sec in dashboard board milestones setupguide; do
        again="$REPRO_DIR/${theme}-${sec}.png"
        if ! repro_shoot "$theme" "$sec" "$again" "UTC"; then
            echo "✗ 重拍失败：${theme}-${sec}" >&2
            repro_fail=1
            continue
        fi
        if ! cmp -s "$BASE_DIR/${theme}-${sec}.png" "$again"; then
            echo "✗ 快照不可重现：${theme}-${sec}.png 两次拍出不同字节（基线会天天漂）" >&2
            repro_fail=1
        fi
        # 换**另一个**时区再拍一张：字节必须一模一样
        other="$REPRO_DIR/${theme}-${sec}-tz.png"
        if ! repro_shoot "$theme" "$sec" "$other" "America/New_York"; then
            echo "✗ 换时区重拍失败：${theme}-${sec}" >&2
            repro_fail=1
            continue
        fi
        if ! cmp -s "$again" "$other"; then
            echo "✗ 快照跟着宿主时区走：${theme}-${sec}.png 换 TZ 后字节不同（基线不可跨机重现）" >&2
            repro_fail=1
        fi
    done
done
rm -rf "$REPRO_DIR"
if [ "$repro_fail" -ne 0 ]; then
    echo "✗ 基线不可重现 —— 基线带墙钟就等于没有基线" >&2
    exit 1
fi
echo "✓ 8 张快照两次重拍逐字节一致，且换宿主时区后仍一致（基线可重现）"

# ⚠ **跨运行复拍**（批 AN）：上一段只在**单次运行内**比两次 ⇒ 抓不到「有时拍出
#   另一种字节」的漂移。实测那正是真发生过的：同一份代码在并发下会拍出 4 种字节
#   （根因 = DTK `DShadowLine` 的 SVG 渐变带渲染不确定）。
#   ⇒ 这里在**新进程**里再拍一轮，与已提交的基线比 —— 跨运行漂移才抓得到。
#   ⚠ 门数刻意保持小：8 段 × 2 主题 = 16 次进程启动，约 20s。
CROSS_DIR="$(mktemp -d)"
cross_fail=0
for theme in light dark; do
    for sec in dashboard board milestones setupguide; do
        shot="$CROSS_DIR/${theme}-${sec}.png"
        # ⚠ 同上：失败时把 stderr 打出来（否则只知道「失败了」，不知道「为什么」）
        if ! TZ=UTC QT_QPA_PLATFORM=offscreen DEEPDOLPHIN_THEME="$theme" "$BIN" --snapshot \
                "$shot" --section "$sec" >/dev/null 2>"$CROSS_DIR/stderr.txt"; then
            echo "✗ 跨运行复拍失败：${theme}-${sec}" >&2
            grep -v "setHighDpiScaleFactorRoundingPolicy\|can not find qm files\|DGuiApplicationHelper:\|This plugin does not support\|DPlatformWindowInterface" \
                "$CROSS_DIR/stderr.txt" | sed 's/^/    /' >&2
            cross_fail=1
            continue
        fi
        if ! cmp -s "$BASE_DIR/${theme}-${sec}.png" "$shot"; then
            echo "✗ 快照跨运行不可重现：${theme}-${sec}.png 新进程拍出的字节与基线不同" >&2
            cross_fail=1
        fi
    done
done
rm -rf "$CROSS_DIR"
if [ "$cross_fail" -ne 0 ]; then
    echo "✗ 基线跨运行会漂 —— 漂了就是「没有基线」（改了界面它不红）" >&2
    exit 1
fi
echo "✓ 8 张快照跨运行（新进程）复拍仍与基线逐字节一致"

# ⚠ 临时目录收尾（批 AN）：$BASE_DIR 是 git 基线、$SHOT_DIR 是本次产物。
#   两者在上面的门里都用过了 ⇒ 这里清掉。
#   ⚠ 失败路径（exit 1）会提前退出 ⇒ 临时目录留在 /tmp，由系统回收，不污染仓库。
rm -rf "$BASE_DIR" "$SHOT_DIR"

echo "› 3/16 desktop / metainfo 校验（缺工具显式 SKIP）"
# ⚠⚠⚨ 批 CU · **校验失败不许被 `&&` 吞掉**（实测坐实的洞 ⇒ 台账 E.2bd）
#   ⚠⚠⚨ 实测（旧形态）：把 desktop 的 `Type` 写成非法值 ⇒ desktop-file-validate
#     **判红**（rc=1、错误打在 stdout）⇒ 但旧版 ci.sh **rc=0**、末尾照样打
#     「✓ CI 门通过」、**15 步全部跑完** ⇒ ⚠⚠⚨ **假绿**
#     （desktop 非法 ⇒ 图标进不了启动器 / 点不起来 ⇒ 这道门本该拦住）
#   ⇒ 根因：`set -euo pipefail` 对 `&&` 列表里**非末位**命令的失败
#     **不触发退出**（bash / dash 实测：`false && echo OK` ⇒ 继续往下跑、rc=0）
#     ⇒ 「校验命令的成败」被挂在 `&&` 后面 ⇒ **失败不影响 CI 的结论**。
#   ⇒ 而 desktop-file-validate / appstream-util **全仓只在 ci.sh 这一处被调用**
#     ⇒ 没有第二道门兜底 ⇒ 那个 `&&` 就是**唯一**的那道门 ⇒ 它形同虚设。
#   ⇒ 现在：**接住退出码** ⇒ 非 0 ⇒ 判红（与第 10/11/12/13 步同款口径）。
if command -v desktop-file-validate >/dev/null 2>&1; then
    _dfv_rc=0
    desktop-file-validate "$SRC/data/cn.deepdolphin.app.desktop" || _dfv_rc=$?
    if [ "$_dfv_rc" -ne 0 ]; then
        echo "✗ desktop 文件不合法（desktop-file-validate 退出码 $_dfv_rc）" >&2
        exit 1
    fi
    echo "✓ desktop 合法"
else
    echo "SKIP: desktop-file-validate 未安装（装 desktop-file-validate 包后此门生效）"
    skip=$((skip+1))
fi
if command -v appstream-util >/dev/null 2>&1; then
    _asu_rc=0
    appstream-util validate-relax --nonet "$SRC/data/metainfo/cn.deepdolphin.app.metainfo.xml" || _asu_rc=$?
    if [ "$_asu_rc" -ne 0 ]; then
        echo "✗ metainfo 不合法（appstream-util 退出码 $_asu_rc）" >&2
        exit 1
    fi
    echo "✓ metainfo 合法"
else
    echo "SKIP: appstream-util 未安装（README 决策 69 的硬门随工具到位生效）"
    skip=$((skip+1))
fi

echo "› 4/16 无头探针（平台探针 + 固定文档页四语言探针 + 分隔线探针）"
# 探针断言独立成 scripts/ci-platform-probe.sh：可单独跑，负控也能精确打它。
if ! sh "$SRC/scripts/ci-platform-probe.sh" "$BIN"; then
    echo "✗ 平台探针门失败" >&2
    exit 1
fi
# ⚠ 文档语言探针（批 AA）：**真跑**一遍四语言切换，看文档窗的实际呈现有没有跟着换。
#   接线门是**源码扫描** —— 它能证明「代码里写了 setButtonText」，但证明不了
#   「换语言后按钮真的变了」⇒ 这一门补的是**行为**证据。
if ! sh "$SRC/scripts/ci-docs-lang-probe.sh" "$BIN"; then
    echo "✗ 文档语言探针门失败（换语言后界面没跟着换）" >&2
    exit 1
fi
# ⚠ 分隔线探针（批 AW）：**真渲染**一次分隔线，量墨迹。
#   详情页**不在快照矩阵里** ⇒ 快照抓不到它 ⇒ 这一门是它唯一的**行为**证据。
#   静态门守「页面用的是真线组件」，这一门守「组件真的是 1 逻辑像素宽的线」。
if ! sh "$SRC/scripts/ci-divider-probe.sh" "$BIN"; then
    echo "✗ 分隔线探针门失败（分隔线不是 1 逻辑像素的真线）" >&2
    exit 1
fi

# ⚠⚠⚨ 批 CF · **剥注释口径的单一真相源**（批 AV 纪律：抽取而非复刻）。
#   ⇒ 以前这里**自己定义**了一份，而且是**旧口径**（`s{//(?!:).*$}{}`，**没有** `(?<!:)`）
#   ⇒ `https://…` 会被整段剥掉 ⇒ **同一个门项，两处口径结论相反**：
#     实测：同一份源码、同一个门项 ⇒ ci.sh 口径命中 **0**、ci-wiring.sh 口径命中 **1**
#     ⇒ 仓里已有 **12** 个真实源文件在两套口径下输出不同 ⇒ 现在就能咬人，不是假想。
#   ⇒ 现在：**从 ci-wiring.sh 原文抽取** ⇒ 口径永远一致（改一处就跟着变）。
# ⚠ **抽的是函数原文**（`sed -n '/^strip_comments() {/,/^}/p'`）⇒ 不复刻、不手抄。
# ⚠⚠⚨ **抽取可能截断**：`sed -n '/^strip_comments() {/,/^}/p'` 会在**第一个**独占
#   `}` 行处结束 ⇒ 函数体里若有这样的行 ⇒ 抽出来是**残缺函数** ⇒ 行为错乱。
#   ⇒ 所以：抽取失败或抽出来不可用 ⇒ **指名道姓地失败**（不许静默用半个函数）。
if ! eval "$(sed -n '/^strip_comments() {/,/^}/p' "$SRC/scripts/ci-wiring.sh")" || ! strip_comments "$SRC/scripts/ci-wiring.sh" >/dev/null 2>&1; then
    echo "✗ 剥注释函数抽取失败或不可用（ci-wiring.sh 的函数体里有独占的 } 行 ⇒ 抽出来是残缺的）" >&2
    exit 1
fi

echo "› 5/16 D2 grep 门（DS::* 单点真相源；散值上限 0，存量已清零）"
# 散值门独立成 scripts/ci-d2.sh：可单独跑，负控也能精确打它。
if ! sh "$SRC/scripts/ci-d2.sh" "$SRC"; then
    echo "✗ 设计系统散值门失败：src/ 下出现色值/硬编码 px 字号" >&2
    exit 1
fi

echo "› 6/16 agent 自测（mock 渠道）"
# ⚠⚠⚠ **这一门原来没有断言**（批 AZ 实测查出来的第二个真洞）：
#   原来是 `"$BIN" --agent-selftest | tail -2` ⇒ **只打两行输出，零断言**：
#   · agent 链路**整条坏掉**（工具循环断了、模型不回应、进程早退）时，
#     只要进程**退出码是 0**，这一门照样绿 ⇒ **CI 判「agent 链路是好的」而它其实坏了**。
#   · ⚠⚠ **实测纠正了一个想当然的判断**（批 AY 的「管道吞退出码」在这条上**不成立**）：
#     `ci.sh` 顶部有 `set -euo pipefail` ⇒ 实测（dash 与 bash 都试过）
#     `false | tail -2` 会让**整个脚本以 1 退出** ⇒ **退出码没有被管道吞掉**。
#     ⇒ 所以这儿的洞**不是**「退出码被吞」，而是**「退出码之外没有别的断言」**：
#       退出码只能区分「0=FINAL / 1=ERROR」（main.cpp:68-72），
#       **区分不了「链路坏了但恰好返回 0」**（如 main.cpp:191-197：
#        没有 assistant 消息时 finalText 是空串，仍会打印 `[selftest] FINAL: ` 并 return 0）。
#   ⇒ 现在**三件事都要查**（契约见 src/main.cpp:68-72）：
#     ① 退出码 == 0（0 = FINAL；1 = ERROR，main.cpp 里显式 return 1）
#     ② stdout 里有 `[selftest] FINAL:`（真的走完了工具循环 ⇒ 不是早退）
#     ③ stdout 里有 `[selftest-done]`（收尾标记 ⇒ 进程跑到了最后一步）
#   ⚠ 输出**落盘**再查：既保住完整输出供排障，也避免 `| tail` 把诊断信息截掉
#     （批 AY 的教训：栈被截断 ⇒ 白丢线索）。
AGENT_RC=0
# ⚠ 同样在 CRASH_DIR 里跑：core_pattern 是相对名 ⇒ core 落在**进程的 cwd**
#   ⇒ 不 cd 的话，agent-selftest 崩了会把 `core.<pid>` 落在**仓库目录**里。
( cd "$CRASH_DIR" && "$BIN" --agent-selftest ) >"$BUILD/agent-selftest.out" 2>"$BUILD/agent-selftest.err" || AGENT_RC=$?
if [ "$AGENT_RC" -ge 128 ]; then
    AG_SIG=$((AGENT_RC - 128))
    AG_SIG_NAME="$(kill -l "$AG_SIG" 2>/dev/null || echo "信号$AG_SIG")"
    echo "✗ agent 自测被信号杀死（$AG_SIG_NAME / 退出码 $AGENT_RC）" >&2
    if [ -s "$BUILD/agent-selftest.err" ]; then
        echo "  ---- agent-selftest stderr ----" >&2
        sed 's/^/    /' "$BUILD/agent-selftest.err" >&2
    fi
    exit 1
fi
if [ "$AGENT_RC" -ne 0 ]; then
    echo "✗ agent 自测退出码 $AGENT_RC（要求 0；1 = ERROR，见 main.cpp:68-72）" >&2
    if [ -s "$BUILD/agent-selftest.out" ]; then
        echo "  ---- agent-selftest stdout ----" >&2
        sed 's/^/    /' "$BUILD/agent-selftest.out" >&2
    fi
    exit 1
fi
if ! grep -q '^\[selftest\] FINAL:' "$BUILD/agent-selftest.out"; then
    echo "✗ agent 自测没有 FINAL 标记（工具循环没走完/早退）—— 期望 stdout 含 '[selftest] FINAL:'" >&2
    sed 's/^/    /' "$BUILD/agent-selftest.out" >&2
    exit 1
fi
if ! grep -q '^\[selftest-done\]$' "$BUILD/agent-selftest.out"; then
    echo "✗ agent 自测没有收尾标记 '[selftest-done]'（进程没跑到最后一步）" >&2
    sed 's/^/    /' "$BUILD/agent-selftest.out" >&2
    exit 1
fi
tail -2 "$BUILD/agent-selftest.out"

echo "› 7/16 verify 接线在（源扫描：判定不许藏回视图，撤入口 ≠ 撤能力）"
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

echo "› 8/16 图谱 Canvas 契约清单齐（章程 §3.5：方法清单就是移植验收清单）"
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
# ⚠⚠⚨ **批 CJ · 真洞（实测坐实）**：
#   原来这行是 `grep -rlE … "$SRC/src/logic" "$SRC/src/models" 2>/dev/null || true`
#   ⇒ ⚠⚠⚨ **文件对 grep 不可读**（chmod 000）⇒ grep **静默跳过**它
#   ⇒ 若那个文件里**有** QWidget 头 ⇒ `GW_HITS` 仍是空 ⇒ **分层纪律门放行**
#   ⇒ **假绿**（⚠ 与批 CD 在 `ci-d2.sh` 里收的洞**同款**：
#     那边**已经**加了 `find … ! -readable` 预检 ⇒ **这边没加**
#     ⇒ ⚠⚠⚨ **同一个洞堵一半比不堵更坏**（以为有门 ⇒ 实际没有））。
#   ⇒ 修法（照批 CD 同款口径）：**扫描之前先验可读性** ⇒ 读不了 ⇒ 判失败。
#   ⚠ `|| true` **保留**（无匹配 ⇒ grep 退 1 ⇒ `set -e` 会中止 ⇒ 必须吞）
#   ⇒ 但**先验了可读性** ⇒ 这处 `|| true` 只吞「无匹配」，不吞「读不了」。
#   ⚠ **不用 `|| true` 包 find**（那会新增一处 `|| true` 站点 ⇒ 登记册要跟着动）
#   ⇒ 照 `ci-d2.sh` 同款写法：`|| _gw_find_rc=$?`。
GW_UNREADABLE=""
_gw_find_rc=0
_gw_unread="$(find "$SRC/src/logic" "$SRC/src/models" -type f ! -readable -print 2>/dev/null)" || _gw_find_rc=$?
if [ "$_gw_find_rc" -ne 0 ] || [ -n "$_gw_unread" ]; then
    echo "✗ logic/ 或 models/ 里有源文件对工具不可读（find 退出码 $_gw_find_rc）：$_gw_unread ⇒ grep 会静默跳过它们 ⇒ 分层纪律门会误判「干净」⇒ **未验证不许被当成通过**" >&2
    CANVAS_FAIL=1    # ⚠⚠⚨ 批 CJ：不可读 ⇒ 判失败（末尾统一 exit 1 ⇒ 「✓ 图谱 Canvas 契约门通过」永远打不出来）
fi
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
for f in src/logic/GraphToken.cpp src/logic/SceneRender.cpp src/models/GraphScene.cpp src/platform/Canvas2D.cpp src/platform/DpiPixmap.cpp; do
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

echo "› 9/16 接线门（源扫描：判定层与接线点必须都在，撤入口 ≠ 撤能力）"
# 接线门独立成 scripts/ci-wiring.sh：可单独跑，负控也能精确打它。
# ⚠⚠⚨ 批 DU · **双跑**：接线门在 `sh` 与 `bash` 下各跑一遍 ⇒ **输出与退出码必须一致**
#   ⇒ 判据层的**结论不许随执行 shell 变**（批 DT 立的承诺 ⇒ 这里给它装上牙齿）。
#   ⇒ ⚠ **双跑是通用的**：任何新的分叉（不论什么构造）都会被它抓住
#     ⇒ 而批 DT 的规则只管「门型函数体内的 echo」⇒ 口径之外的靠这道门兜住。
#   ⇒ ⚠ **不新增步骤**（⚠ 新增步骤会牵动 16 个步骤标记 + 一条 arch_need_ml 门）
#     ⇒ 改成在**第 9 步内部**双跑 ⇒ 步骤数不变 ⇒ 那些门不受影响。
#   ⇒ ⚠ **无自引用**：双跑逻辑在 `ci.sh`（入口）⇒ `ci-wiring.sh` 不跑 `ci.sh`。
#   ⇒ ⚠ 退出码**接住**（批 CQ 纪律：不用管道读退出码）；差异**落文件**再读（不用 | head）。
#   ⇒ ⚠ 只在**接线门绿时**才跑第二遍 ⇒ 红了就照旧报错退出（省时间）。
# ⚠⚠⚨ 批 DU · 双跑的两份日志必须落在 **TMPDIR**，不许落 `$BUILD`（CI 的工作目录）
#   ⇒ 理由（**前瞻性加固**，与批 DU 首次端到端那次「未能复现的分叉」无因果关系）：
#     双跑的第二遍会比第一遍**多看到第一遍的产物** ⇒ 若产物落在**会被扫描的目录**里
#     ⇒ 第二遍的输入就与第一遍不同 ⇒ 双跑门会**自己制造分叉** ⇒ 假红（批 DL：假红比假绿更坏）。
#   ⇒ 现在落 `${TMPDIR:-/tmp}`（与 `STRIP_FAIL_FILE` 同款惯例）⇒ 两遍读到的输入严格一致。
#   ⇒ ⚠ 可观测性不丢：第一遍的输出仍然 `cat` 出来（下面），diff 也照样落盘。
#   ⇒ ⚠ 带 `$$`（PID）⇒ 并发跑 CI 时两份日志不会互相覆盖。
_W_DASH_LOG="${TMPDIR:-/tmp}/deepdolphin-wiring-dash.$$.log"
_W_BASH_LOG="${TMPDIR:-/tmp}/deepdolphin-wiring-bash.$$.log"
_W_DIFF_LOG="${TMPDIR:-/tmp}/deepdolphin-wiring-shell-diff.$$.log"
_w_dash_rc=0
sh "$SRC/scripts/ci-wiring.sh" "$SRC" > "$_W_DASH_LOG" 2>&1 || _w_dash_rc=$?
cat "$_W_DASH_LOG"
if [ "$_w_dash_rc" -ne 0 ]; then
    echo "✗ 接线门失败：取数/判定/渲染/接线任一段被摘掉" >&2
    exit 1
fi
_w_bash_rc=0
bash "$SRC/scripts/ci-wiring.sh" "$SRC" > "$_W_BASH_LOG" 2>&1 || _w_bash_rc=$?
if [ "$_w_bash_rc" -ne "$_w_dash_rc" ]; then
    echo "✗ ⚠⚠⚨ 接线门在 sh 与 bash 下**退出码不同**（sh=$_w_dash_rc / bash=$_w_bash_rc）⇒ 判据层的**结论随执行 shell 变** ⇒ 不可信（批 DT）" >&2
    exit 1
fi
if ! cmp -s "$_W_DASH_LOG" "$_W_BASH_LOG"; then
    echo "✗ ⚠⚠⚨ 接线门在 sh 与 bash 下**输出不同** ⇒ 诊断文案**随执行 shell 变** ⇒ 负控的文案命中判定不可信（批 DT）" >&2
    _w_diff_rc=0
    diff "$_W_DASH_LOG" "$_W_BASH_LOG" > "$_W_DIFF_LOG" 2>&1 || _w_diff_rc=$?
    echo "   差异已写 $_W_DIFF_LOG（diff 退出码 $_w_diff_rc）前 20 行：" >&2
    head -20 "$_W_DIFF_LOG" >&2
    exit 1
fi
echo "✓ 接线门在 sh 与 bash 下**输出与退出码一致**（判据层的结论不随执行 shell 变）"

# ⚠⚠⚨ 批 DV · **双跑覆盖面门**：接线门只是**一个**判据脚本 ⇒
#   别的判据脚本（`ci-d2.sh` / `ci-orphan-probe.sh` …）的**结论同样可能随执行 shell 变**
#   ⇒ 而**没有任何一道门**会发现 ⇒ ⇒ 本门按**仓内常驻登记册**
#   （`scripts/ci-shell-parity.baseline`）逐个双跑 ⇒ 覆盖面不许被悄悄改窄
#   （批 DQ 立过的教训：「一条本该被登记的承诺，在三个目录上从未生效」）。
#   ⇒ ⚠ **不新增步骤**（新增步骤会牵动 16 个步骤标记 + 一条 arch_need_ml 门）⇒ 并在第 9 步里。
#   ⇒ ⚠ **无自引用**：本门只跑登记册里标 `parity` 的条目 ⇒ 不跑自己（自引用会递归）。
#   ⇒ ⚠ 登记册里标 `ci.sh` 的条目（接线门）由上面的批 DU 双跑负责 ⇒ 「入口共用 ≠ 口径共用」。
# ⚠⚠⚨ 批 EA · **双跑覆盖面门自己进双跑**（登记册里最后一条**可动的**豁免消失）
#   ⇒ 「谁守双跑覆盖面」的最后一道闭环 ⇒ **守覆盖面那道门自己**也被双跑
#   ⇒ ⚠ **「自引用 ⇒ 递归」只在 `parity` 位置成立**：本门只跑登记册里标 `parity` 的条目
#     ⇒ 自己那行是 `ci.sh` 位置 ⇒ **被跳过** ⇒ ⇒ **不递归**
#   ⇒ ⚠ **两份日志都落 TMPDIR**（批 DU 纪律）：第二遍会多看到第一遍的产物 ⇒ 假红
#   ⇒ ⚠ **无自引用**：本门不跑 `ci.sh`
#   ⇒ 退出码**接住**（批 CQ 纪律：不用管道读退出码）；差异**落文件**再读
_P_SH_LOG="${TMPDIR:-/tmp}/deepdolphin-paritygate-sh.$$.log"
_P_BASH_LOG="${TMPDIR:-/tmp}/deepdolphin-paritygate-bash.$$.log"
_P_DIFF_LOG="${TMPDIR:-/tmp}/deepdolphin-paritygate-shell-diff.$$.log"
_p_sh_rc=0
sh "$SRC/scripts/ci-shell-parity.sh" "$SRC" > "$_P_SH_LOG" 2>&1 || _p_sh_rc=$?
# ⚠ 可观测性不丢：第一遍的输出照样打出来（和批 DU 的接线门双跑同款）
cat "$_P_SH_LOG"
if [ "$_p_sh_rc" -ne 0 ]; then
    echo "✗ 双跑覆盖面门失败（某个判据脚本在 sh 与 bash 下**结论不一致** ⇒ 判据层的结论随执行 shell 变 ⇒ 不可信）" >&2
    exit 1
fi
_p_bash_rc=0
bash "$SRC/scripts/ci-shell-parity.sh" "$SRC" > "$_P_BASH_LOG" 2>&1 || _p_bash_rc=$?
if [ "$_p_bash_rc" -ne "$_p_sh_rc" ]; then
    echo "✗ ⚠⚠⚨ 双跑覆盖面门在 sh 与 bash 下**退出码不同**（sh=$_p_sh_rc / bash=$_p_bash_rc）⇒ **守覆盖面**的那道门自己随 shell 变 ⇒ 不可信（批 DT）" >&2
    exit 1
fi
if ! cmp -s "$_P_SH_LOG" "$_P_BASH_LOG"; then
    echo "✗ ⚠⚠⚨ 双跑覆盖面门在 sh 与 bash 下**输出不同** ⇒ 覆盖面报告**随执行 shell 变** ⇒ 读者看到的覆盖面口径不可信（批 DT）" >&2
    _p_diff_rc=0
    diff "$_P_SH_LOG" "$_P_BASH_LOG" > "$_P_DIFF_LOG" 2>&1 || _p_diff_rc=$?
    echo "   差异已写 $_P_DIFF_LOG（diff 退出码 $_p_diff_rc）前 20 行：" >&2
    head -20 "$_P_DIFF_LOG" >&2
    exit 1
fi
echo "✓ 双跑覆盖面门在 sh 与 bash 下**输出与退出码一致**（守覆盖面那道门自己也不随执行 shell 变）"

echo "› 10/16 引擎契约门（真引擎沙箱；**未验证 ⇒ 计入末尾**，不许说通过）"
# contract-check.sh 之前是**游离脚本** —— CI 从来没跑过它，契约漂移不会被拦。
# 接进 CI 后：引擎在 → 真跑（32 条）；引擎不在 → 脚本自己 SKIP 并如实说明
# 「本组未验证」（不是静默通过）。
# ⚠⚠⚨ 批 CI：**未验证 ⇒ 判红**（收掉批 CB 的已知边界：SKIP 后 CI 仍绿）
#   ⇒ 契约门脚本返回专属码 3（未验证）/ 其它非 0（失败）⇒ 本层分诊
#   ⇒ ⚠ **失败优先**：契约门自己有真失败时它返回 1 ⇒ 走「失败」那一支。
if [ -n "${DEEPGIT_BIN:-}" ] || command -v moongit >/dev/null || command -v deepgit >/dev/null; then
    # ⚠ 别写成 `if cmd | tail -3` —— 那样 if 判的是 tail 的退出码（永远 0），
    #   契约挂了门也是绿的。必须拿脚本自己的退出码。
    _cc_log="$BUILD/contract-check.log"
    # ⚠⚠⚨ 批 CB：**接住退出码**并分诊（0=通过 / 3=未验证(SKIP) / 其它非 0=失败）。
    #   ⚠ 以前是 `if cmd; then … else … exit 1; fi` ⇒ 脚本 exit 0（**未验证**）也走
    #   「通过」那一支 ⇒ ⚠⚠⚨ 实测：缺 python3 时**120 条契约断言一条都没跑**，
    #   CI 却打印「✓ 引擎契约门通过」⇒ **假绿**。
    #   ⚠ 别写成 `if ! cmd; then $?`：`!` 会把退出码**取反** ⇒ 分不清 SKIP 与失败。
    #   ⚠ 分诊口径与第 13 步（agent 工具面门，批 BW）**同款**：3 = 未验证，不算通过。
    _cc_rc=0
    DEEPGIT_CLIENT_BIN="$BIN" sh "$SRC/scripts/contract-check.sh" > "$_cc_log" 2>&1 || _cc_rc=$?
    if [ "$_cc_rc" -eq 0 ]; then
        tail -3 "$_cc_log"
        echo "✓ 引擎契约门通过"
    elif [ "$_cc_rc" -eq 3 ]; then
        tail -3 "$_cc_log"
        # ⚠⚠⚨ 批 CI：**未验证不许被当成通过** ⇒ 这里**必须判红**
        #   ⇒ 以前只打印「不算通过」⇒ CI 继续跑 ⇒ 最后照样打「✓ CI 门通过」
        #   ⇒ **核心门根本没验，却说 CI 通过** ⇒ 假绿（批 CB 的已知边界，本批收口）
        # ⚠⚠⚨ 批 EC · **「未验证」的处置口径必须统一** —— 这里**不许当场 exit 1**
        #   ⇒ ① 同一个「未验证」rc 语义**分两档**（此处 1 vs 末尾 3）⇒ 分诊表说错方向
        #   ⇒ ② **提前中止** ⇒ 第 11～16 步**根本没跑** ⇒ 那些未验证/失败
        #     **永远不会被报出来**（批 CQ「一次报全」在 CI 层被破坏）
        #   ⇒ 现在：与其它 8 处**同款** ⇒ 计数（skip++）⇒ 继续跑 ⇒ 末尾统一 `exit 3`
        #   ⇒ ⚠ **真失败那一支仍然当场 exit 1**（失败优先 —— 末尾注释说的就是它）
        echo "‣ SKIP 引擎契约门：本组**未验证**（脚本自己报了 SKIP）——不算通过" >&2
        skip=$((skip+1))
        echo "  ⇒ 把环境补齐后重跑（逐条看上面的「‣ SKIP」）" >&2
    else
        tail -20 "$_cc_log" >&2
        echo "✗ 引擎契约门失败（退出码 $_cc_rc）" >&2
        exit 1
    fi
else
    # ⚠⚠⚨ 批 CI：**未验证不许被当成通过** ⇒ 引擎缺席 ⇒ 契约门整组没验 ⇒ 判红
    #   ⇒ 以前只打印「不算通过」⇒ CI 继续 ⇒ 最后照样打「✓ CI 门通过」⇒ 假绿
    # ⚠⚠⚨ 批 EC · **与上面那一支同款口径** ⇒ 计数（skip++）⇒ 继续跑
    #   ⇒ 末尾统一 `exit 3` ⇒ 同一个「未验证」**只有一个 rc** ⇒ 不再分两档
    echo "‣ SKIP 引擎契约门**未验证**：未找到 moongit/deepgit（可设 DEEPGIT_BIN 指定）——不算通过" >&2
    skip=$((skip+1))
    echo "  ⇒ **未验证不许被当成通过**（批 CB 口径：契约门用专属退出码 3）" >&2
fi

echo "› 11/16 deb 打包（D7 达标的必经：能出包装进 deepin，且装后零环境变量）"
# PLAN §「CI 流程」明确列了「⑥ deb 构建」—— 这一门以前根本不存在，
# 于是「能不能出包装进 deepin」从没被验证过。
# build-deb.sh 自带**依赖清单双向校验**（清单 ↔ 二进制实际 DT_NEEDED）：
# 漏声明（装上跑不起来）/ 多声明（包名不存在装不上）/ 包名抄错，一律构建失败。
if command -v dpkg-deb >/dev/null 2>&1; then
    # ⚠⚠⚨ 批 CL · **接住退出码并分诊**（0=通过 / 3=未验证(SKIP) / 其它非 0=失败）。
    #   ⇒ build-deb.sh 的第 2h 步（依赖包在 apt 仓库里能不能装到）有两处
    #     「未验证」：apt 查不到候选版本 / 没有 apt-cache
    #   ⇒ 以前那边**只打印、不计数** ⇒ 脚本 exit 0 ⇒ 这里**照样打「✓ deb 构建通过」**
    #     ⇒ ⚠⚠⚨ **说法比门宽**（批 AA 教训）⇒ 批 CL 已让 build-deb.sh 自己
    #     **专属码 3** ⇒ 现在这里**分诊**：3 ⇒ 未验证 ⇒ **计入 skip** ⇒ 末尾判红。
    #   ⚠ 与第 10 步（契约门，批 CB/CI）、第 12 步（deb 布局验收，批 CC）**同款口径**。
    _deb_rc=0
    sh "$SRC/scripts/build-deb.sh" "$BUILD/deb" > "$BUILD/build-deb.log" 2>&1 || _deb_rc=$?
    if [ "$_deb_rc" -eq 0 ]; then
        tail -3 "$BUILD/build-deb.log"
        # ⚠ 解包后「零环境变量下无缺失库」的校验**在 build-deb.sh 里**（产物自检归打包脚本，
        #   别在这里再写一份 —— 两处定义会漂）。
        echo "✓ deb 构建通过（依赖清单自洽 + 产物零环境变量下无缺失库）"
    elif [ "$_deb_rc" -eq 3 ]; then
        tail -3 "$BUILD/build-deb.log" >&2
        echo "‣ SKIP deb 构建：本组**未验证**（脚本自己报了 SKIP）——不算通过" >&2
        skip=$((skip+1))
    else
        tail -20 "$BUILD/build-deb.log" >&2
        echo "✗ deb 构建失败" >&2
        exit 1
    fi
else
    echo "‣ SKIP deb 构建：没有 dpkg-deb"
    skip=$((skip+1))
    echo "‣ 本组**未验证**，不算通过"
fi

echo "› 12/16 deb 布局验收（D7 的**准**验收：装完能不能用）"
# ⚠ D7 的最终验收是「干净 deepin 25 容器里 dpkg -i + 启动」—— 本机**没有容器
#   运行时**（无 docker/podman）⇒ 那一段做不了。
#   ⇒ 这里做「不依赖容器的那一半」：把 deb **解包**到临时目录（不装进系统），
#     按**包内真实布局**逐项查「装完之后点图标能不能起来」。
# ⚠ 这一门**抓到过真 bug**：D-Bus service 文件原来写 `Exec=deepDolphin --dbus-service`
#   —— ① 裸名（dbus 激活**不做 PATH 搜索**，实测裸名 `true` 也 Spawn.ExecFailed）
#   ② `--dbus-service` 这个 flag **客户端根本不认识**（全项目 grep 无此 flag）
#   ⇒ 两处合起来 = **从启动器点图标激活失败、应用起不来**。
DEB_OUT="$(ls -t "$BUILD"/deb/*.deb 2>/dev/null | head -1)"
if [ -z "$DEB_OUT" ]; then
    echo "‣ SKIP deb 布局验收：没有 deb 产物（本组**未验证**，不算通过）"
    skip=$((skip+1))
else
    # ⚠⚠⚨ 批 CC：**接住退出码**并分诊（0=通过 / 3=未验证(SKIP) / 其它非 0=失败）。
    #   ⚠ 以前是 `elif sh …; then … else … exit 1; fi` ⇒ 脚本 exit 0（**未验证**）
    #     也走「通过」那一支 ⇒ ⚠⚠⚨ 实测：把 check-deb-layout.sh 的 SKIP 支
    #     `exit 3` 改成 `exit 0` ⇒ **rc=0** 而输出仍写着「SKIP …未验证」
    #     ⇒ CI 第 12 步打印「✓ deb 布局验收通过」⇒ **假绿坐实**
    #     ⇒ 且**现有门全绿**（`exit 3` 一条门都没有 ⇒ 没人看得见）。
    #   ⚠ 分诊口径与第 10 步（契约门，批 CB）、第 13 步（agent 工具面门，批 BW）
    #     **同款**：3 = 未验证（SKIP）。
    #   ⚠⚠⚨ **批 CK**：旧立场是「不算通过，但**不判失败**」⇒ **已被收掉**
    #     ⇒ 那个立场会让 CI 继续跑 ⇒ 最后照样打「**✓ CI 门通过**」
    #     ⇒ **未验的组被当成「通过」** ⇒ 假绿。
    #     ⇒ 现在：**未验证 ⇒ 计入 `skip` ⇒ 末尾判红**（退出码 3）。
    _dl_log="${TMPDIR:-/tmp}/deepdolphin-deb-layout-sh.$$.log"
    _dl_rc=0
    sh "$SRC/scripts/check-deb-layout.sh" "$DEB_OUT" > "$_dl_log" 2>&1 || _dl_rc=$?
    # ⚠⚠⚨ 批 DZ · **双跑**：判据层的**结论不许随执行 shell 变**（批 DT 立的承诺）
    #   ⇒ 这一门以前是 EXEMPT（deb 产物第 11 步才就位 ⇒ 双跑点在它之前 ⇒ 依赖没到位）
    #   ⇒ 现在双跑点就在**本步内部**（deb 产物已经在）⇒ 覆盖面扩到这一门
    #   ⇒ `sh` 一遍（CI 真正用的就是 dash）+ `bash` 一遍
    #   ⇒ **退出码必须一致** + **输出必须逐字节一致**（stdout 与 stderr 合流后比）
    #   ⇒ ⚠ **两份日志都落 TMPDIR**（批 DU 纪律）：不许落 CI 工作目录
    #     ⇒ 否则第二遍会多看到第一遍的产物 ⇒ 双跑**自己制造分叉** ⇒ 假红
    #   ⇒ ⚠ **无自引用**：本门只跑 check-deb-layout.sh
    _dl_bash_log="${TMPDIR:-/tmp}/deepdolphin-deb-layout-bash.$$.log"
    _dl_bash_rc=0
    bash "$SRC/scripts/check-deb-layout.sh" "$DEB_OUT" > "$_dl_bash_log" 2>&1 || _dl_bash_rc=$?
    if [ "$_dl_rc" -ne "$_dl_bash_rc" ]; then
        echo "✗ ⚠⚠⚨ deb 布局验收在 sh 与 bash 下**退出码不同**（sh=$_dl_rc / bash=$_dl_bash_rc）⇒ 判据层的**结论随执行 shell 变** ⇒ 不可信（批 DT）" >&2
        exit 1
    fi
    if ! cmp -s "$_dl_log" "$_dl_bash_log"; then
        echo "✗ ⚠⚠⚨ deb 布局验收在 sh 与 bash 下**输出不同** ⇒ 诊断文案**随执行 shell 变** ⇒ 不可信（批 DT）" >&2
        _dl_diff_log="${TMPDIR:-/tmp}/deepdolphin-deb-layout-shell-diff.$$.log"
        _dl_diff_rc=0
        diff "$_dl_log" "$_dl_bash_log" > "$_dl_diff_log" 2>&1 || _dl_diff_rc=$?
        echo "   差异已写 $_dl_diff_log（diff 退出码 $_dl_diff_rc）前 20 行：" >&2
        head -20 "$_dl_diff_log" >&2
        exit 1
    fi
    # ⚠⚠⚨ **退出码必须被报出来**（批 DW 纪律）：「两版一致」不许掩盖「这一组跑通没跑通」
    echo "✓ deb 布局验收在 sh 与 bash 下**输出与退出码一致**（退出码 $_dl_rc ⇒ 判据层的结论不随执行 shell 变）"
    if [ "$_dl_rc" -eq 0 ]; then
        tail -3 "$_dl_log"
        echo "✓ deb 布局验收通过（装完能不能用：service/desktop/图标/metainfo/空环境启动）"
    elif [ "$_dl_rc" -eq 3 ]; then
        tail -3 "$_dl_log" >&2
        echo "‣ SKIP deb 布局验收：本组**未验证**（脚本自己报了 SKIP）——不算通过" >&2
        skip=$((skip+1))
    else
        tail -20 "$_dl_log" >&2
        echo "✗ deb 布局验收失败（退出码 $_dl_rc）" >&2
        exit 1
    fi
fi

echo "› 13/16 agent 工具面收敛（旧名别名必须从模型可见面剔掉，但仍可执行）"
# ⚠⚠⚠ **这个探针以前根本不在 CI 里**（批 BD 实测查出来的）：
#   ① 它有 9 条断言（引擎标的废弃别名不得出现在模型可见面/系统提示词里，
#      但**仍要留在必填校验表**里 —— 收敛的是「推荐谁」，不是「还能不能用」）；
#   ② 而 `probe-agent-tool-surface.sh` **整个从仓库删掉，接线门与审计器都全绿**
#      （实测 rc=0 / rc=0）⇒ 一份断言可以悄悄消失而无人知晓。
#   ⇒ 现在它接进 CI（批 BD）；第 14 步再从「集合」这一层把同类问题堵上。
#
# ⚠ 退出码语义（探针自己定的，别猜）：0=通过 / 1=失败 / 2=用法错 /
#   **3=SKIP**（引擎缺席，或引擎 < 0.2.0 没有 deprecated 标记 ⇒ 本门**未验证**，
#   **不算通过** —— 与第 10 步契约门同款口径）。
# ⚠⚠ **别写成 `if ! cmd; then $?`**：`!` 会把退出码**取反** ⇒ then 分支里的 `$?`
#   恒为 0 ⇒ 分不清「SKIP」和「失败」。必须先原样收下退出码。
ATS_RC=0
sh "$SRC/scripts/probe-agent-tool-surface.sh" "$BIN" || ATS_RC=$?
if [ "$ATS_RC" -eq 3 ]; then
    echo "‣ SKIP agent 工具面门：引擎缺席或版本太老（无 deprecated 标记）"
    skip=$((skip+1))
    echo "‣ 本组**未验证**，不算通过"
elif [ "$ATS_RC" -ne 0 ]; then
    echo "✗ agent 工具面门失败（退出码 $ATS_RC；1=断言红，2=用法错）" >&2
    exit 1
fi

echo "› 14/16 无游离断言脚本（每个断言脚本都必须在 CI 里可达）"
# ⚠ 这一步查的是「**CI 自己在漏什么**」：
#   批 BD 实测：`probe-agent-tool-surface.sh`（9 条断言）整个从仓库删掉，
#   接线门与审计器**都全绿** ⇒ 「少了一份断言」这件事**没有任何门会说一个字**。
#   ⇒ 新增 scripts/ci-orphan-probe.sh：scripts/ 下每个断言脚本要么在 CI 里可达
#     （ci.sh 直接调用，或被 CI 可达的脚本调用），要么在**带理由的白名单**里。
if ! sh "$SRC/scripts/ci-orphan-probe.sh" "$SRC"; then
    echo "✗ 有断言脚本游离在 CI 之外（CI 从来不跑它 ⇒ 它的断言没人执行）" >&2
    exit 1
fi

echo "› 15/16 assets 侧图标判据（产物与母版一致 + 三个平台同一套 icon）"
# ⚠⚠⚨ **批 DG · 起因（实测坐实，不是推演）**：assets 侧有两个**判据脚本**
#   （`assets/icon/check-icon.sh` ＝ 图标一致性验收；`assets/icon/make-icons.py --check`
#   ＝ 产物与母版一致性校验）⇒ ⚠ **它们不在任何 CI 里** ⇒ 它们的断言
#   **从来没人执行** ⇒ 「所有平台用同一套 icon」这句承诺**没人守**
#   ⇒ 有人改了图标体系、忘了重跑产物 ⇒ **没有任何门会说一个字**。
#   ⇒ 与 mac 侧那 6 条白名单**不同款**：这两个脚本**本机可跑可验**
#   （Pillow 在、产物入库）⇒ 所以本批是**真的接进 CI**，不是「只登记」。
# ⚠⚠⚨ **工具缺席 ⇒ 未验证（专属码 3），不许当成真失败**（批 CB/CC 纪律）：
#   这两个脚本都要 Pillow ⇒ 缺席时 `check-icon.sh` 的母版包围盒那节
#   会把「PIL-缺」当成「母版不合法」⇒ **把「工具没装」说成「图标不一致」**
#   ⇒ **码值语义被顶替** ⇒ ⇒ 先探工具：缺席 ⇒ `skip++` ⇒ 末尾 `exit 3`。
if python3 -c 'from PIL import Image' >/dev/null 2>&1; then
    _ic_rc=0
    python3 "$SRC/../assets/icon/make-icons.py" --check || _ic_rc=$?
    if [ "$_ic_rc" -ne 0 ]; then
        echo "✗ 图标产物与母版不一致（make-icons.py --check 退出码 $_ic_rc）" >&2
        exit 1
    fi
    _ic2_rc=0
    bash "$SRC/../assets/icon/check-icon.sh" || _ic2_rc=$?
    if [ "$_ic2_rc" -ne 0 ]; then
        echo "✗ 图标一致性验收失败（check-icon.sh 退出码 $_ic2_rc）" >&2
        exit 1
    fi
    echo "✓ 图标判据全绿（产物与母版一致 + 三个平台同一套 icon）"
else
    echo "SKIP: Pillow 未安装（图标判据未验证：母版包围盒那节需要 PIL）"
    skip=$((skip+1))
fi

echo "› 16/16 判据不许被掏空成恒真（判定层条件的静态分析）"
# ⚠⚠⚠ **起因（实测，不是推演）**：批 BB/BC 的门盯的是「**判据条数**」
#   （selfcheck 的 `SC_MIN`、各断言脚本的条数基线）⇒
#   ⚠⚠⚠ **实测：把一条判据的条件改成 `true`** ⇒
#     · selfcheck 仍 **395 passed, 0 failed**（条数**没变**）
#     · 批 BB 的「判据数 == SC_MIN」判定**不红**（它只看条数）
#     · 接线门 **rc=0（全绿）**
#   ⇒ 而那条判据**从此永远不会红** ⇒ 判据被悄悄削弱**无人知晓**。
#   ⇒ 新增 scripts/ci-tautology-check.py：判定层的判据条件**不许是恒真/纯字面量**，
#     shell 断言脚本的 `if` 条件**不许是恒真/恒假**。
# ⚠ 该探针**自带自检**：每次运行先拿合成样例验一遍自己的判定逻辑
#   ⇒ 判定逻辑被掏空 ⇒ 探针当场报「自检失败」⇒ 红（门自己证明自己有牙）。
if ! python3 "$SRC/scripts/ci-tautology-check.py" "$SRC"; then
    echo "✗ 判据里有恒真/纯字面量条件（判据被掏空 ⇒ 它的断言永远不会红）" >&2
    exit 1
fi

# ⚠⚠⚨ 批 CG · **剥注释失败**必须被看见（工具失败 ≠ 没找到）。
#   ⇒ 放在「✓ 全绿」**之前** ⇒ 那个「✓」永远打不出来
#     （批 CE 的教训：诊断失真最贵；⚠⚠⚨ 实测：剥注释失败时
#       forbid 门会判「没找到」⇒ **静默变绿** ⇒ 违例被漏检）。
#   ⇒ ⚠⚠⚨ 覆盖**全部**剥注释调用点（forbid / need / count / any …）
#     ⇒ 一次挡住整类（批 CD 纪律：一次挡住整类，别逐点治标）。
if [ -s "$STRIP_FAIL_FILE" ]; then
    # ⚠⚠⚨ 批 CH：诊断**搬进 trap**了（退出时必打）⇒ 这里只负责 exit 1
    #   ⇒ 否则「段落 ARCH_FAIL 提前 exit」会把末尾的诊断吃掉 ⇒ 红因指错
    exit 1
fi


# ⚠⚠⚨ 批 CK · 「未验证」不许被当成「通过」（**CI 自己这层**）。
#   ⇒ 有任何一组**没验**（工具缺席 / 产物缺失 / 子脚本报 SKIP）⇒ 判红。
#   ⇒ ⚠ **失败优先**：ci.sh 是 `set -e` 逐步执行 ⇒ 真失败**当场** exit 1
#     ⇒ 能走到这里说明**没有真失败** ⇒ 这里只判「未验证」。
#   ⇒ ⚠ 退出码 **3** = 未验证（与契约门、agent 工具面门同款口径，批 CB/CI）。
if [ "$skip" -ne 0 ]; then
    echo "✗ 有 $skip 组**未验证**（SKIP）⇒ **未验证不许被当成通过**" >&2
    echo "  ⇒ 逐条看上面带「SKIP」的行；把环境补齐后重跑" >&2
    exit 3
fi

echo "✓ CI 门通过：快照与 git 基线逐字节一致（无未提交的视觉改动）"
