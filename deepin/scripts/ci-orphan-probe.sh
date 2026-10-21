#!/usr/bin/env bash
# ci-orphan-probe.sh — 「断言脚本不许游离在 CI 之外」（批 BD）。
#
# 【为什么要有它 —— 实测取证，不是推演】
#   批 BD 实测：把 `scripts/probe-agent-tool-surface.sh`（9 条断言）**整个删掉**，
#   跑接线门 + 审计器 ⇒ **两个都 rc=0（全绿）**。
#   ⇒ 也就是说：仓库里**少了一份断言**（agent 工具面的收敛不再被验），
#     而**没有任何门会说一个字**。
#   ⚠ 对照实测（同一批，用来定位洞的位置）：
#     · 删掉**已经接进 CI** 的脚本（ci-docs-lang-probe.sh / ci-divider-probe.sh）
#       ⇒ 门**红**（rc=1）⇒ 洞不在「已接管的」，而在「**没接管的**」。
#     · 删掉 ci.sh 里对某个探针的**调用** ⇒ 门**红** ⇒ 调用点本身是有门的。
#   ⇒ 所以要补的是**最后一块**：**没人接管的断言脚本**，不许悄悄存在。
#
# 【本门断言三件事】
#   ① 每个断言脚本都必须在 CI 里**可达**（ci.sh 直接调用，或被 CI 可达的脚本调用）。
#   ② 例外必须**显式登记在白名单**里，且每条都带**非空理由**。
#   ③ 白名单里的脚本必须**确实不可达** ⇒ 不许把「已经在 CI 里的脚本」偷偷塞进
#      白名单来逃避门（那样它随时可以被踢出 CI 而无人知晓）。
#
# 【口径（实测，不是猜）】
#   · 「断言脚本」= scripts/ 下**含报错标记行**的文件（每条断言失败时打一条报错）。
#     实测：build.sh / build-system.sh / dev-run.sh / setup-deps.sh / bootstrap-deps.py
#     都**没有**报错行 ⇒ 它们是构建/依赖脚本，不做断言 ⇒ 不归本门管。
#   · 「可达」按**调用点**判定（`sh "$SRC/scripts/xxx.sh"` 这种真调用），
#     **不是**「文件名字符串出现过」——
#     ⚠ 实测 ci.sh 里 `scripts/ci.sh` 出现 3 次，全是注释/用法说明；
#       用「出现过」会把 ci.sh 误判成「自己调用了自己」。
#   · ⚠ **门项行不算调用点**：ci-wiring.sh 里
#       `arch_need "$SRC/scripts/ci.sh" 'sh "\$SRC/scripts/ci-d2\.sh"' …`
#     这类**门项字符串**长得像调用 ⇒ 判定时必须排除 `arch_*` 开头的行
#     （否则「门项里提到的脚本」会被当成「真被调用」⇒ 门被架空）。
#
# 【用法】sh scripts/ci-orphan-probe.sh <源码根目录>
#   退出码 0 = 通过；非 0 = 失败（stderr 里有原因）。
set -uo pipefail
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPTS="$SRC/scripts"

# ⚠⚠⚨ 批 CV · **「可达」判定之前必须先剥注释**（实测坐实的洞 ⇒ 台账 E.2be）
#   ⚠⚠⚨ **实测**：造一个**没有任何真调用点**的断言脚本（游离）⇒ 本门判红 ✓；
#     **只**在 ci.sh 里加一行**注释**（`# sh "$SRC/scripts/<那个脚本>.sh"`）
#     ⇒ 本门改判「全部可达」⇒ **rc=0** ⇒ ⚠⚠⚨ **假绿坐实**
#     ⇒ ⇒ 批 BD 的承诺（「少了一份断言 ⇒ 必须红」）**可被一行注释破掉**。
#   ⇒ **抽取**而非复刻（批 CF / AV 纪律：判据层只有**一份**剥注释实现）
#     ⇒ 与 ci.sh / ci-d2.sh **同款现成写法**（那两处已经这么抽）。
#   ⇒ ⚠ 抽取失败 ⇒ **指名道姓地失败**（不许静默降级成「不剥注释」
#     ⇒ 那等于把本批收掉的洞原样放回去 ⇒ 假绿）。
STRIP_FAIL_FILE="${TMPDIR:-/tmp}/deepdolphin-strip-fail.$$"

# ── 白名单：允许「不在 CI 里」的断言脚本 ─────────────────────────────────
# ⚠ 白名单是**例外登记**，不是垃圾桶：每条必须写清「为什么它进不了 CI」。
# ⚠ 白名单**条数**由 ci-wiring.sh 的「批 BD 段」钉死（完全相等 ⇒ 余量恒为 0，
#   批 BB 口径）⇒ 增删条目必须同步改基线 ⇒ 改动是显式的、可 review 的。
WHITELIST="\
ci.sh|它就是 CI 入口本身（CI 不需要调用自己）
smoke.sh|本地冒烟入口：做「配置+构建」，再跑 selfcheck 与契约门；它的检查项是 ci.sh 的子集（CI 入口是 ci.sh，额外多跑快照/探针/deb）
probe-deepin-tray.sh|需真机：要有图形会话（DISPLAY/WAYLAND_DISPLAY）且要有 deepin 托盘 daemon，CI/CI 容器里都没有
probe-sni-icon.sh|需真机：要有图形会话与会话总线（用 gdbus 从总线另一端读 IconPixmap）"

fail=0
WL_FILE="$(mktemp)"
# ⚠⚠⚨ 批 CG 同款口径：**剥注释失败**必须被看见（工具失败 ≠ 没找到）
#   ⇒ 判据层那条「剥注释失败 ⇒ 未验证」的口径，在这里同样适用
#   ⇒ 剥注释失败 ⇒ 可达性判定**不可信** ⇒ 必须判红（不许当成「没有游离脚本」）。
trap '_cv_rc=$?; rm -f "$WL_FILE"; if [ -s "$STRIP_FAIL_FILE" ]; then echo "✗ 剥注释失败（工具失败 ≠ 没找到）—— 孤儿探针的可达性判定**不可信**：$(sort -u "$STRIP_FAIL_FILE" | tr "\n" " ")" >&2; _cv_rc=1; fi; rm -f "$STRIP_FAIL_FILE"; exit $_cv_rc' EXIT
printf '%s\n' "$WHITELIST" | sed '/^$/d' > "$WL_FILE"

if [ ! -f "$SCRIPTS/ci.sh" ]; then
    echo "✗ 找不到 CI 入口：$SCRIPTS/ci.sh" >&2
    exit 1
fi

# ⚠⚠⚨ 批 CV · **抽取**判据层那**唯一一份**剥注释实现（剥注释口径**只有一份**）。
#   ⇒ 抽取失败 ⇒ **指名道姓地失败**（不许静默降级成「不剥注释」
#     ⇒ 那等于把批 CV 收掉的洞原样放回去 ⇒ 假绿）。
if ! eval "$(sed -n '/^strip_comments() {/,/^}/p' "$SRC/scripts/ci-wiring.sh")" || ! strip_comments "$SRC/scripts/ci-wiring.sh" >/dev/null 2>&1; then
    echo "✗ 剥注释函数抽取失败或不可用（ci-wiring.sh 的函数体里有独占的 } 行 ⇒ 抽出来是残缺的）" >&2
    exit 1
fi

# ── 1. 算「CI 可达集合」（从 ci.sh 出发的**传递闭包**）────────────────────
# ⚠ 为什么是传递闭包而不是「只看 ci.sh 直接调用」：
#   ci-wiring.sh 自己会调 `python3 "$SRC/scripts/ci-wiring-audit.py"` ——
#   审计器是**断言工具**（它判门项有没有命中 0 次），它确实在 CI 链路里，
#   但它不是被 ci.sh 直接调的 ⇒ 只看直接调用会把它误判成「游离」。
calls_of() {
    _cf="$SCRIPTS/$1"
    [ -f "$_cf" ] || return 0
    # ⚠ 排除门项行（见文件头「门项行不算调用点」）
    # ⚠⚠⚨ 批 CV：**先剥注释**再找调用点（否则注释里的一行同形文本就能冒充真调用
    #   ⇒ 游离断言脚本被当成「在 CI 里」⇒ 本门假绿 ⇒ 实测坐实 ⇒ 台账 E.2be）
    #   ⚠ 剥注释口径**只有一份**（抽取 ci-wiring.sh 的 strip_comments ⇒ 零漂移）。
    strip_comments "$_cf" | grep -vE '^[[:space:]]*arch_[a-z_]+[[:space:]]' 2>/dev/null \
        | grep -oE '(sh|bash|python3?)[[:space:]]+"?[^"]*/scripts/[A-Za-z0-9._-]+\.(sh|py)' 2>/dev/null \
        | sed 's|.*/||' | sort -u || true
}

REACH=""
_frontier="ci.sh"
while [ -n "$_frontier" ]; do
    _next=""
    for _s in $_frontier; do
        for _t in $(calls_of "$_s"); do
            case " $REACH " in
                *" $_t "*) ;;
                *) REACH="$REACH $_t"; _next="$_next $_t" ;;
            esac
        done
    done
    _frontier="$_next"
done

# ── 2. 白名单自身要合法 ─────────────────────────────────────────────────
while IFS='|' read -r _name _reason; do
    [ -n "$_name" ] || continue
    if [ -z "$_reason" ]; then
        echo "  ✗ 白名单条目没写理由：$_name（例外必须说清「为什么它进不了 CI」）" >&2
        fail=1
        continue
    fi
    if [ ! -f "$SCRIPTS/$_name" ]; then
        echo "  ✗ 白名单条目指向不存在的脚本：$_name" >&2
        fail=1
        continue
    fi
    case " $REACH " in
        *" $_name "*)
            echo "  ✗ 白名单条目已失效：$_name 现在**在 CI 里**（可达）⇒ 它不该留在白名单" \
                 "（留着等于给它开后门：随时可以被踢出 CI 而无人知晓）" >&2
            fail=1
            ;;
    esac
done < "$WL_FILE"

# ⚠⚠⚨ 批 CD：**工具读不了文件 ⇒ grep 会静默跳过它** ⇒ 漏检 ⇒ 假绿。
#   ⇒ ⚠⚠⚨ **实测的洞**：造一个**游离断言脚本**（`scripts/zzAzCdFake.sh`），
#     让它对 grep **不可读**（chmod 000 ⇒ grep rc=2）
#     ⇒ `grep -q '✗ ' "$_f" 2>/dev/null || continue` 把它**静默跳过**
#     ⇒ 本脚本打印「**✓ 无游离断言脚本**」并 **exit 0**
#     ⇒ **游离断言脚本漏检 ⇒ 假绿坐实**（而接线门全绿 ⇒ 没人看得见）。
#   ⇒ 所以在扫之前**先验可读性**：读不了 ⇒ 必须红，**不许当成「不是断言脚本」**
#     （⚠ 与批 CB/CC 同款口径：**未验证不许被当成通过**）。
_orphan_unread=""
for _f in "$SCRIPTS"/*.sh "$SCRIPTS"/*.py; do
    [ -f "$_f" ] || continue
    [ -r "$_f" ] || _orphan_unread="$_orphan_unread $(basename "$_f")"
done
if [ -n "$_orphan_unread" ]; then
    echo "✗ 有脚本对工具不可读：$_orphan_unread ⇒ grep 会静默跳过它们 ⇒ 本门会漏检 ⇒ **未验证不许当成通过**" >&2
    fail=1    # ⚠⚠⚨ 批 CD：不可读 ⇒ 判失败（末尾统一 exit 1 ⇒ 「✓ 无游离断言脚本」永远打不出来）
fi

# ── 3. 每个断言脚本都必须在 CI 里可达（否则进白名单）────────────────────
n_assert=0
n_orphan=0
for _f in "$SCRIPTS"/*.sh "$SCRIPTS"/*.py; do
    [ -f "$_f" ] || continue
    grep -q '✗ ' "$_f" 2>/dev/null || continue
    n_assert=$((n_assert + 1))
    _name="$(basename "$_f")"
    case " $REACH " in
        *" $_name "*) continue ;;
    esac
    if cut -d'|' -f1 "$WL_FILE" | grep -qxF "$_name"; then
        continue
    fi
    echo "  ✗ 断言脚本游离在 CI 之外：$_name" \
         "（CI 从来不跑它 ⇒ 它的断言没人执行；把它整个删掉也没人知道）" >&2
    n_orphan=$((n_orphan + 1))
    fail=1
done

n_wl="$(wc -l < "$WL_FILE" | tr -d ' ')"
if [ "$fail" -ne 0 ]; then
    echo "✗ 无游离断言脚本门失败（游离 $n_orphan 个）" >&2
    exit 1
fi
echo "✓ 无游离断言脚本：scripts/ 下 $n_assert 个断言脚本全部在 CI 里可达（白名单 $n_wl 条，每条带理由）"
exit 0
