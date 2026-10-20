#!/usr/bin/env bash
# probe-agent-tool-surface.sh — agent 工具面**收敛**的正式断言（批 AB）。
#
# 【断言什么】引擎给 `tools --json` 里的旧名别名带 `deprecated: true`（引擎 0.2.0
#   起）⇒ 客户端**不再把它们推荐给模型**：
#   ① 6 个旧名别名**不在**模型可见面（model=）里；
#   ② 6 个旧名别名**仍在**必填校验表（validated=）里 —— 它们**仍可执行**
#      （契约门第 12 组要求「客户端能执行的工具集 == 引擎声明的工具集」，
#      收敛的是「推荐谁」，不是「还能不能用」）；
#   ③ 系统提示词里的清单**也不含**那些别名（提示词与工具表**同一口径** ——
#      不然模型会去调一个「提示词里有、工具表里没有」的名字）；
#   ④ 新面的工具（index_query / confidence_gen / arch_gen …）**在**模型可见面里。
#
# ⚠ **引擎缺席或版本太老 ⇒ 显式 SKIP，且不算通过**
#   （引擎 < 0.2.0 没有 deprecated 标记 ⇒ 本门无从验证；不能因此红，也不能因此绿）。
#
# 用法：scripts/probe-agent-tool-surface.sh <deepDolphin 二进制>
set -uo pipefail
BIN="${1:-}"
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    echo "✗ 用法：$0 <deepDolphin 二进制>" >&2
    exit 2
fi

ALIASES="codegraph_overview codegraph_tree codegraph_symbol codegraph_impact codegraph_arch codegraph_confidence"
NEWFACE="index_query index_overview index_gen confidence_gen confidence_query arch_gen render"

OUT="$(QT_QPA_PLATFORM=offscreen "$BIN" --agent-tool-surface 2>/dev/null)"
if [ -z "$OUT" ]; then
    echo "SKIP: 引擎未找到（工具面探针需要真引擎）—— 本门**未验证**，不算通过"
    exit 3
fi

MODEL="$(printf '%s\n' "$OUT" | sed -n 's/^model=//p')"
VALIDATED="$(printf '%s\n' "$OUT" | sed -n 's/^validated=//p')"
PROMPT="$(printf '%s\n' "$OUT" | sed -n 's/^prompt=//p')"
ENGINE_DEPRECATED="$(printf '%s\n' "$OUT" | sed -n 's/^engine_deprecated=//p')"

if [ -z "$MODEL" ] || [ -z "$VALIDATED" ]; then
    echo "✗ 探针没报出工具面（model/validated 为空）" >&2
    exit 1
fi

# ⚠ 引擎太老 ⇒ 原始清单里没有 deprecated 标记 ⇒ 没法验证「收敛」⇒ 显式 SKIP。
#   ⚠ 必须看**原始**清单的标记数（探针报 engine_deprecated=）：客户端给模型的
#     清单**已经收敛**（别名被剔掉了），在那里找标记永远找不到 ⇒ 会误判 SKIP。
if [ "${ENGINE_DEPRECATED:-0}" -lt 1 ] 2>/dev/null; then
    echo "SKIP: 引擎的 tools --json 里没有 deprecated 标记（引擎 < 0.2.0）—— 本门**未验证**，不算通过"
    exit 3
fi

fail=0
for a in $ALIASES; do
    if printf '%s\n' "$MODEL" | tr ',' '\n' | grep -qx "$a"; then
        echo "  ✗ 旧名别名仍在模型可见面里：$a" >&2
        fail=1
    fi
    if ! printf '%s\n' "$VALIDATED" | tr ',' '\n' | grep -qx "$a"; then
        echo "  ✗ 旧名别名不在必填校验表里（收敛把「还能不能用」也收掉了）：$a" >&2
        fail=1
    fi
    if printf '%s\n' "$PROMPT" | grep -q "\"$a\""; then
        echo "  ✗ 系统提示词的清单里还列着旧名别名：$a" >&2
        fail=1
    fi
done
for n in $NEWFACE; do
    if ! printf '%s\n' "$MODEL" | tr ',' '\n' | grep -qx "$n"; then
        echo "  ✗ 新面工具不在模型可见面里：$n" >&2
        fail=1
    fi
done

if [ "$fail" -ne 0 ]; then
    echo "✗ agent 工具面收敛断言失败" >&2
    exit 1
fi

n_model="$(printf '%s\n' "$MODEL" | tr ',' '\n' | grep -c .)"
n_validated="$(printf '%s\n' "$VALIDATED" | tr ',' '\n' | grep -c .)"
echo "✓ agent 工具面收敛：模型可见 $n_model 个（旧名别名已剔除），可执行/可校验 $n_validated 个（别名仍在，可继续调用）"
