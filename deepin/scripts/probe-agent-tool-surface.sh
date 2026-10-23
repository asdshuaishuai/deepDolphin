#!/usr/bin/env bash
# probe-agent-tool-surface.sh — agent 工具面**收敛**的正式断言（批 AB）。
#
# 【断言什么】引擎给 `tools --json` 里的旧名别名带 `deprecated: true`（引擎 0.2.0
#   起）⇒ 客户端**不再把它们推荐给模型**：
#   ① 被标记的旧名别名**不在**模型可见面（model=）里；
#   ② 它们**仍在**必填校验表（validated=）里 —— 它们**仍可执行**
#      （契约门第 12 组要求「客户端能执行的工具集 == 引擎声明的工具集」，
#      收敛的是「推荐谁」，不是「还能不能用」）；
#   ③ 系统提示词里的清单**也不含**那些别名（提示词与工具表**同一口径** ——
#      不然模型会去调「提示词里有、工具表里没有」的名字）；
#   ④ 新面的工具（index_query / confidence_gen / arch_gen …）**在**模型可见面里；
#   ⑤ **数量自洽**：校验表个数 − 模型面个数 == 被标记的别名个数
#      ⇒ 只剔了一部分、或多剔了非别名工具，都会被抓住（逐个名字的断言抓不到前者）。
#
# ⚠⚠ **别名名单必须来自引擎**（探针的 engine_deprecated_names= 行），
#   **不许在本脚本里硬编码** ——
#   硬编码的后果：引擎新增别名时这道门**漏检**（新的别名还在模型面里，门却绿）；
#   引擎取消某个别名的标记时**假红**（名单过期）。
#   （批 AB 初版就是硬编码 6 个名字 ⇒ 引擎新增别名即漏检，已改。）
#   ⚠ 注意：并非所有 `codegraph_*` 都是废弃别名 —— 例如
#   `codegraph_patch_confidence` / `codegraph_patch_merge` 是**新功能**（引擎没标废弃），
#   它们**应该**留在模型可见面里 ⇒ 「按前缀一刀切」是错的判据。
#
# ⚠ **引擎缺席或版本太老 ⇒ 显式 SKIP，且不算通过**
#   （引擎 < 0.2.0 没有 deprecated 标记 ⇒ 本门无从验证；不能因此红，也不能因此绿）。
#
# 用法：scripts/probe-agent-tool-surface.sh <deepDolphin 二进制>
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

# 新面的锚点工具（这几个**必须**在模型可见面里 —— 它们是「旧名别名的继任者」）。
NEWFACE="index_query index_overview index_gen confidence_gen confidence_query arch_gen render"

# ⚠⚠⚨ 批 BW：**必须看探针的退出码**。
#   以前这里只看「stdout 空不空」⇒ **探针崩了（139）和「引擎没找到」被当成同一件事**
#   ⇒ 崩了 ⇒ 报 SKIP（exit 3）⇒ ci.sh 打印「‣ SKIP …未验证」⇒ **CI 整体照样绿**
#   ⇒ ⇒ 「崩了」被伪装成「环境不具备」⇒ 崩点彻底看不见。
#   ⇒ 现在按退出码分诊：**3 = 未验证（引擎缺席）** / **其它非 0 = 失败**。
#   ⚠ stderr **不扔掉**（落盘，失败时原样吐出）⇒ 崩点（CrashHandler 的栈回溯）看得见。
ERR_FILE="$(mktemp 2>/dev/null || echo /tmp/az-ats-stderr.$$)"
trap 'rm -f "$ERR_FILE"' EXIT
PROBE_RC=0
OUT="$(QT_QPA_PLATFORM=offscreen "$BIN" --agent-tool-surface 2>"$ERR_FILE")" || PROBE_RC=$?
if [ "$PROBE_RC" -eq 3 ]; then
    echo "SKIP: 引擎未找到（工具面探针需要真引擎）—— 本门**未验证**，不算通过"
    cat "$ERR_FILE" >&2
    exit 3
fi
if [ "$PROBE_RC" -ne 0 ]; then
    echo "✗ 工具面探针退出码 $PROBE_RC（要求 0；3=引擎未找到已单列为 SKIP）—— 这是**失败**，不是「未验证」" >&2
    echo "--- 探针 stderr（崩点在这里）---" >&2
    cat "$ERR_FILE" >&2
    exit 1
fi
if [ -z "$OUT" ]; then
    echo "✗ 工具面探针退出码 0 却什么都没报（假绿：这一门会被当成 SKIP 放过去）" >&2
    cat "$ERR_FILE" >&2
    exit 1
fi

MODEL="$(printf '%s\n' "$OUT" | sed -n 's/^model=//p')"
VALIDATED="$(printf '%s\n' "$OUT" | sed -n 's/^validated=//p')"
PROMPT="$(printf '%s\n' "$OUT" | sed -n 's/^prompt=//p')"
ENGINE_DEPRECATED="$(printf '%s\n' "$OUT" | sed -n 's/^engine_deprecated=//p')"
DEPRECATED_NAMES="$(printf '%s\n' "$OUT" | sed -n 's/^engine_deprecated_names=//p')"

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
if [ -z "$DEPRECATED_NAMES" ]; then
    echo "✗ 探针报 engine_deprecated=${ENGINE_DEPRECATED} 却没给出别名名字（判据没法断言谁）" >&2
    exit 1
fi
# ⚠⚠⚨ 批 DJ · **抽取值必须格式合法**（治本第二步 ⇒ 让探针脚本**自己**有牙）。
#   ⚠⚠⚨ **批 DI 实测坐实的洞**：原来**只有非空检查** ⇒
#     把抽取口径 `s/^validated=//p` 改成 `s/^valid//p` ⇒ 抽到 `ated=…`
#     ⇒ **非空检查照样通过** ⇒ 「每个废弃别名都要在校验表里」那条断言
#     ⇒ ⚠⚠⚨ **逐条比的都是错值** ⇒ 别名重新出现在模型可见面**也不会被发现**。
#   ⇒ 现在补**格式校验**：`validated` 只能是「标识符,标识符,…」
#     （**排除 `=`** ⇒ `ated=…` 这种前缀残留一律被抓）。
#   ⚠ **位置**：必须在「引擎太老 ⇒ SKIP」那一支**之后**
#     ⇒ 引擎太老时探针可能压根不报 `validated=` ⇒ 那条路径必须原样放行。
if ! printf '%s' "$VALIDATED" | grep -Eq '^[A-Za-z0-9_-]+(,[A-Za-z0-9_-]+)*$'; then
    echo "✗ 工具面探针的 validated= 不是「标识符,标识符,…」（得到 '$VALIDATED'）⇒ 判定失效：逐条比的都是错值" >&2
    exit 1
fi

fail=0
# ⚠ 别名名单是**逗号分隔**的一行 ⇒ 先把逗号换成空格再按词循环
#   （直接 `for a in $DEPRECATED_NAMES` 会把整串当成一个词 ⇒ 断言必然假红）。
for a in $(printf '%s\n' "$DEPRECATED_NAMES" | tr ',' ' '); do
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

# ⑤ 数量自洽：收敛掉的**恰好**是那些被标记的别名，一个不多一个不少。
n_model="$(printf '%s\n' "$MODEL" | tr ',' '\n' | grep -c .)"
n_validated="$(printf '%s\n' "$VALIDATED" | tr ',' '\n' | grep -c .)"
n_dep="$(printf '%s\n' "$DEPRECATED_NAMES" | tr ',' '\n' | grep -c .)"
if [ "$((n_validated - n_model))" -ne "$n_dep" ]; then
    echo "  ✗ 数量不自洽：校验表 $n_validated − 模型面 $n_model = $((n_validated - n_model))，" \
         "但引擎标了 $n_dep 个废弃别名 ⇒ 收敛掉的不**恰好**是那些别名" >&2
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "✗ agent 工具面收敛断言失败" >&2
    exit 1
fi

echo "✓ agent 工具面收敛：模型可见 $n_model 个（引擎标的 $n_dep 个旧名别名已剔除），" \
     "可执行/可校验 $n_validated 个（别名仍在，可继续调用）"
