#!/usr/bin/env bash
# ci-docs-lang-probe.sh — 固定文档页四语言探针的**正式断言**（批 AA）。
#
# 【为什么要有这一门】接线门是**源码扫描**：它能证明「代码里写了
#   `setButtonText` / `DocPages::content(k, m_language)`」，但**证明不了**
#   「用户点了语言之后，界面真的换了」—— 扫描看得见调用，看不见结果。
#   这一门**真跑**一遍切换，报出文档窗的**实际呈现**再逐条核对。
#
# 【断言什么】
#   ① 探针 exit 0，且恰好报出四种语言（zh-CN / en / zh-TW / ja，顺序固定）
#   ② 每种语言的呈现**五个字段齐全**（title / close / segments / body / hint）
#   ③ 四种语言的 title / close / segments / body **两两不同**
#      （相同 = 换语言没生效，或某个语言回落成了另一个）
#   ④ 英文那一档**不含汉字**（回落成中文的直接信号）
#   ⑤ 呈现里**不许出现字面量 "%1"**（提示函数留模板给调用方填 ⇒ 用户会看见 %1）
#
# 用法：scripts/ci-docs-lang-probe.sh <deepDolphin 二进制>
set -uo pipefail
BIN="${1:-}"
# ⚠⚠⚨ 批 DX：**`-f` 也要查**（实测）：`-x` 对**目录**也返回 true ⇒ 目录能冒充二进制
#   ⇒ 探针要等到 exec 时才炸 ⇒ 而两个 shell 的**报错文案不同**（dash: Permission denied
#   / bash: 是一个目录）⇒ 双跑门会**误诊**成「输出不同」
#   ⇒ ⇒ 必须在**喂之前**就挡住（fail closed）⇒ 这一组**根本没验过**，不许当成通过
if [ -z "$BIN" ] || [ ! -f "$BIN" ] || [ ! -x "$BIN" ]; then
    echo "✗ 用法：$0 <deepDolphin 二进制>" >&2
    exit 2
fi

PROBE_RC=0
# ⚠ 批 BV：**不許**把 stderr 扔掉（`2>/dev/null`）—— 探针崩了时 CrashHandler 的
#   栈回溯（崩点）全在 stderr 里 ⇒ 扔掉 = CI 只剩一句「退出码 139」，没人知道崩在哪。
#   （DTK 那几行噪声照旧会进 CI 日志；断言只看 stdout，不受影响。）
PROBE_OUT="$(QT_QPA_PLATFORM=offscreen "$BIN" --docs-lang-probe)" || PROBE_RC=$?
printf '%s\n' "$PROBE_OUT"
if [ "$PROBE_RC" -ne 0 ]; then
    echo "✗ docs-lang-probe 退出码 $PROBE_RC（要求 0）" >&2
    exit 1
fi
# ⚠ 批 BV：退出时 QApplication 必须**还活着**（事实行 appAlive）。
#   为 0 ⇒ 退出点在 app 作用域之外 ⇒ 析构 QApplication 会把静态 QCoreApplication::self
#   置空 ⇒ 后台线程派发事件时空指针解引用 ⇒ **SIGSEGV**（批 BV 取证坐实）。
APP_ALIVE="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^appAlive=//p')"
if [ "$APP_ALIVE" != "1" ]; then
    echo "✗ docs-lang-probe 报 appAlive=${APP_ALIVE:-缺失}（要求 1：退出时 QApplication 必须还活着）" >&2
    exit 1
fi

field() { # field <键> —— 取该键的**全部**取值（每行一个）
    printf '%s\n' "$PROBE_OUT" | sed -n "s/^$1=//p"
}

count_lines() { printf '%s' "$1" | grep -c . || true; }

LANGS="$(field lang)"
N_LANG="$(count_lines "$LANGS")"
if [ "$N_LANG" != "4" ]; then
    echo "✗ docs-lang-probe 报了 $N_LANG 种语言（要求 4：zh-CN / en / zh-TW / ja）" >&2
    exit 1
fi
EXPECTED="$(printf 'zh-CN\nen\nzh-TW\nja')"
if [ "$LANGS" != "$EXPECTED" ]; then
    echo "✗ 语言顺序不对（得到：$(printf '%s' "$LANGS" | tr '\n' ' ')）" >&2
    exit 1
fi

# ② 五个字段齐全
for k in title close segments body hint; do
    n="$(count_lines "$(field "$k")")"
    if [ "$n" != "4" ]; then
        echo "✗ docs-lang-probe 的 $k= 出现 $n 次（要求 4：每种语言一条）" >&2
        exit 1
    fi
done

# ③ 四种语言两两不同（两两不同 ⇔ 去重后仍是 4 个）
for k in title close segments body; do
    vals="$(field "$k")"
    uniq_n="$(printf '%s\n' "$vals" | sort -u | grep -c . || true)"
    if [ "$uniq_n" != "4" ]; then
        echo "✗ $k 四种语言只有 $uniq_n 个不同取值（换语言没生效 / 某语言回落成了另一个）" >&2
        printf '%s\n' "$vals" | sed 's/^/    /' >&2
        exit 1
    fi
done

# 分段必须是四档（四个类目）
n_seg="$(field segments | head -1 | awk -F'|' '{print NF}')"
if [ "$n_seg" != "4" ]; then
    echo "✗ segments= 不是四档（得到 $n_seg 段）" >&2
    exit 1
fi

# ④ 英文那一档不含汉字（回落成中文的直接信号）
EN_BODY="$(printf '%s\n' "$PROBE_OUT" | awk '/^lang=en$/{f=1;next} /^lang=/{f=0} f && /^body=/{print;exit}')"
if [ -z "$EN_BODY" ]; then
    echo "✗ docs-lang-probe 的英文档没有 body= 行" >&2
    exit 1
fi
if printf '%s' "$EN_BODY" | grep -Pq '[\x{4E00}-\x{9FFF}]'; then
    echo "✗ 英文档的正文里出现汉字（英文正文回落成中文了）" >&2
    exit 1
fi

# ⑤ 不许出现字面量 "%1"（提示函数留模板给调用方填 ⇒ 用户会看见 %1）
if printf '%s\n' "$PROBE_OUT" | grep -q '%1'; then
    echo "✗ 呈现里出现字面量 %1（提示函数把模板漏给用户了）" >&2
    exit 1
fi

echo "✓ 文档语言探针通过（四种语言真跑一遍：标题/关闭/分段/正文/底部说明都跟着换，英文档无汉字，无 %1 模板残留）"
