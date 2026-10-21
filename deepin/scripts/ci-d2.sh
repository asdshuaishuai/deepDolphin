#!/usr/bin/env bash
# ci-d2.sh — 设计系统散值门（DS::* 单点真相源），可单独跑。
#
# 【门意】`src/` 下出现**色值字面量**、**硬编码 px 字号** → 缺陷。
#   字号/色值只准从 DesignTokens 取。
#
# 【为什么单独成脚本】
#   ① 改字号/色值时能秒级验（不用跑完整个 ci.sh —— 截图矩阵最慢）；
#   ② **负控**能精确打这一门：把某处改回硬编码 → 这一门必须红
#      （门内嵌在 ci.sh 里时，负控得跑整条 CI 才看得到红）。
#
# 【为什么先剥注释】注释里提到 API 名（如 setPixelSize）**不是散值** ——
#   把它算进命中只会逼人改措辞而不是改代码。门 7（verify 接线门）
#   早就是剥注释的；两门共用同一份 strip_comments。
#
# 【为什么检测形式要全】⚠ **同一个值换个写法就溜过去 = 门是假的**。
#   只盯 `#RRGGBB` 的话，`QColor(0x10, 0xB9, 0x81)`、`rgb(255,0,204)`、
#   `QColor(89, 240, 184)` 全都合法 —— 而它们**就是同一批色值**。
#   本门因此覆盖：6/8 位 hex、3 位 hex、QColor 三元组（十进制/十六进制）、
#   rgb() 字面量、rgba() 带裸 alpha、setPixelSize/setPointSizeF 的数字参数、
#   QSS 里的 font-size 字面量、以及「含 font-size 的文件里的裸数字 .arg(N)」
#   （QSS 占位符喂字号那条路 —— 写 `font-size: %1px` + `.arg(11)` 一样是散值）。
#
# 【豁免怎么管】豁免**必须逐条登记**（路径|keep|fix|理由），不是「碰巧躲过」。
#   模式：
#     keep —— 永久豁免（契约层/令牌定义处/判据夹具），命中数不限；
#     fix  —— **待收敛**豁免（真·第二份真相源，已立项），命中数归零时**门必须红**：
#             「这一条已经收敛了，把它从清单里删掉」—— 白名单不许腐化。
#   登记的路径若不存在 → 门红（路径写错 = 门形同虚设）。
#
# 用法：scripts/ci-d2.sh [源码根目录]（默认脚本所在目录的上一级）
set -uo pipefail
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

# 剥注释再匹配：注释里出现的字样不算散值（否则加一行注释就能骗过门）。
strip_comments() {
    if command -v perl >/dev/null 2>&1; then
        # ⚠ `(?<!:)` 排除 `://` —— 否则字符串里的 URL（https://…）
        #   会被当成行注释整段剥掉，门就看不见它了（负控实测）。
        perl -pe 's{(?<!:)(//)(?!:).*$}{}' "$1"
    else
        sed -e 's|//[^/].*$||' "$1"
    fi
}

if [ ! -d "$SRC/src" ]; then
    echo "✗ 源码目录不存在：$SRC/src（脚本位置/参数错了——门失效比门失败更糟）" >&2
    exit 1
fi

# ── 显式豁免清单 ──
# 格式：src/相对路径|keep|fix|理由
# ⚠ 路径写错 / 文件不存在 → 门红（宁可吵，也不能让豁免静默失效）。
D2_EXEMPT='src/ui/DesignTokens.h|keep|令牌定义处：色值/字号的唯一出处
src/ui/DesignTokens.cpp|keep|令牌定义处：色值/字号的唯一出处
src/app/SelfCheck.cpp|keep|判据夹具：必须写期望字面量（否则「期望值随手改」无从发现）
src/app/SelfCheckDocs.cpp|keep|判据夹具（批 AJ 拆分出的分片）：必须写期望字面量（否则「期望值随手改」无从发现）
src/app/SelfCheckEngine.cpp|keep|判据夹具（批 AJ 拆分出的分片）：必须写期望字面量（否则「期望值随手改」无从发现）
src/app/SelfCheckGraph.cpp|keep|判据夹具（批 AK 拆分出的分片）：必须写期望字面量（否则「期望值随手改」无从发现）
src/platform/Canvas2D.cpp|keep|Canvas 契约层：12px 是契约层内部兜底，不是设计令牌
src/logic/SemColors.h|keep|固定色唯一出处（判定层纯色：语义色 + 固定色，DS::semColor 也转发它）
src/logic/GraphToken.cpp|keep|引擎契约色透传 + 洋红兜底（契约色不是 DS 令牌）
src/logic/HeatLayout.cpp|keep|契约热色（与 HTML 交付物逐字同色，不随主题改写）
src/logic/CommitTypeComposition.cpp|keep|12 色提交类型**序列色**（序号→颜色的映射，刻意与状态语义色区分 —— 与 mac 的 DSColor.sequence 同款）'

# ⚠ `setPixelSize` 要**带数字参数**才算散值 —— 只写 API 名的话，
#   `setPixelSize(DS::FontPx::code)`（已收口进 token）也会被拦，那拦的是
#   「不许调这个 API」而不是「不许有散值」，与门的意图不符。
D2_PATTERN='#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{3}\b|setPixelSize\([0-9]|setPointSizeF?\([0-9]|font-size: *[0-9]+px|rgb\([0-9]|rgba\([^)]*,\s*[0-9.]+\s*\)|QColor\(\s*[0-9]'

# 文件级规则：含 font-size: 的文件里不得有**裸数字** .arg(N) ——
#   QSS 占位符喂字号的那条路（font-size: %1px + .arg(11)）同样是散值。
D2_ARG_PATTERN='\.arg\([0-9]+'

EXEMPT_HITS="$(mktemp)"
trap 'rm -f "$EXEMPT_HITS"' EXIT

exempt_field() { # exempt_field <src/相对路径> <字段号 2=模式 3=理由>
    printf '%s\n' "$D2_EXEMPT" | awk -F'|' -v p="$1" -v n="$2" '$1==p {print $n; exit}'
}

D2_HITS=""
D2_COUNT=0
FAIL=0

# ⚠⚠⚨ 批 CD：**工具读不了文件 ⇒ 后面所有 grep 都会静默跳过它** ⇒ 假绿。
#   ⇒ ⚠⚠⚨ **实测的洞**：造一个**含散值**的源文件（`src/zzAzCdProbe.cpp`），
#     让它对 grep **不可读**（chmod 000 ⇒ grep rc=2）
#     ⇒ `grep -rlE … 2>/dev/null` 把它**静默跳过** ⇒ 命中数变 0
#     ⇒ 本脚本打印「**✓ D2 命中 0/0（存量已清零，DS 单一真相源）**」并 **exit 0**
#     ⇒ **门自己说「✓」⇒ 假绿坐实**（而接线门全绿 ⇒ 没人看得见）。
#   ⇒ 所以在扫之前**先验可读性**：读不了 ⇒ 必须红，**不许当成「没有散值」**
#     （⚠ 与批 CB/CC 同款口径：**未验证不许被当成通过**）。
D2_UNREADABLE=""
_d2_find_rc=0
_d2_unread="$(find "$SRC/src" -type f ! -readable -print 2>/dev/null)" || _d2_find_rc=$?
if [ "$_d2_find_rc" -ne 0 ] || [ -n "$_d2_unread" ]; then
    echo "✗ 有源文件对工具不可读（find 退出码 $_d2_find_rc）：$_d2_unread ⇒ grep 会静默跳过它们 ⇒ 本门会误判「已清零」⇒ **未验证不许当成通过**" >&2
    FAIL=1    # ⚠⚠⚨ 批 CD：不可读 ⇒ 判失败（末尾的 exit 1 在「✓ 命中 0/0」之前 ⇒ 那个 ✓ 永远打不出来）
fi

# ── 规则 1：文件内散值（剥注释后）──
for _f in $(grep -rlE "$D2_PATTERN" "$SRC/src" 2>/dev/null | sort); do
    _rel="${_f#$SRC/}"
    _hits="$(strip_comments "$_f" | grep -nE "$D2_PATTERN" | sed "s|^|${_f}:|" || true)"
    [ -z "$_hits" ] && continue
    _n="$(printf '%s\n' "$_hits" | grep -c . || true)"
    if [ -n "$(exempt_field "$_rel" 2)" ]; then
        echo "$_rel $_n" >> "$EXEMPT_HITS"
    else
        D2_HITS="${D2_HITS}${_hits}
"
        D2_COUNT=$((D2_COUNT + _n))
    fi
done

# ── 规则 2：含 font-size: 的文件里的裸数字 .arg(N) ──
for _f in $(grep -rlE 'font-size:' "$SRC/src" 2>/dev/null | sort); do
    _rel="${_f#$SRC/}"
    _hits="$(strip_comments "$_f" | grep -nE "$D2_ARG_PATTERN" | sed "s|^|${_f}:|" || true)"
    [ -z "$_hits" ] && continue
    _n="$(printf '%s\n' "$_hits" | grep -c . || true)"
    if [ -n "$(exempt_field "$_rel" 2)" ]; then
        echo "$_rel $_n" >> "$EXEMPT_HITS"
    else
        D2_HITS="${D2_HITS}${_hits}
"
        D2_COUNT=$((D2_COUNT + _n))
    fi
done

# ── 豁免清单自检：路径必须存在；fix 项命中数必须 > 0（归零 = 该删了）──
while IFS='|' read -r _p _m _r; do
    [ -z "$_p" ] && continue
    if [ ! -f "$SRC/$_p" ]; then
        echo "  ✗ 豁免路径不存在：$_p —— 路径写错 = 门形同虚设" >&2
        FAIL=1
        continue
    fi
    if [ "$_m" != "fix" ]; then
        continue
    fi
    _n="$(grep -c "^$_p " "$EXEMPT_HITS" 2>/dev/null || true)"
    _n="${_n:-0}"
    if [ "$_n" = "0" ]; then
        echo "  ✗ 豁免已失效：$_p（$_r）—— 该条已收敛，请从清单里删掉（白名单不许腐化）" >&2
        FAIL=1
    fi
done <<EOF
$D2_EXEMPT
EOF

# 上限 **0**（批 N 把 M3-3 登记的 4 处存量全收进 DS token 了 —— 存量只减不增，
#   清零后上限就是 0：此后任何一处新散值都当场红）。
if [ "$D2_COUNT" -gt 0 ]; then
    echo "✗ D2 命中 ${D2_COUNT} 处（上限 0，存量已清零），命中清单：" >&2
    printf '%s\n' "$D2_HITS" >&2
    FAIL=1
fi

if [ "$FAIL" != "0" ]; then
    exit 1
fi
echo "✓ D2 命中 ${D2_COUNT}/0（存量已清零，DS 单一真相源）"
