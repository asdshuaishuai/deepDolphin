#!/usr/bin/env bash
# contract-check.sh — 真实引擎输出 → 契约断言（PLAN §2.8 / CHARTER §3）。
#
# 在隔离沙箱（DEEPGIT_HOME=$TMP，绝不碰 ~/.deepgit）里造一个已知形状的 fixture
# 仓库（main + 领先 1 提交的 feature 分支），逐命令跑 `moongit <命令> --json`，
# 用 python3 断言客户端模型层依赖的键名与口径：
#   1. status 恒等式      {projects, summary, language}，listed == len(projects)
#   2. status 项目键       id/currentBranch/branches/dirty/… 存在
#   3. dashboard 口径      work.mergeCandidates == 1（领先分支恰好 1 条）
#   4. milestone 对账      list.readCount == len(list.milestones)
#   5. milestone 动作载荷  done → {applied, status}（无 message 键，AppModel 已对齐）
#   6. scan 差值           重扫已注册目录：found ≥ 1 且 added == 0
#   7. update 载荷         {count, results, succeeded, failed}，succeeded == 1
#   8. 文档托管承诺        托管标记写入、用户哨兵行逐字节保留、docs --json 可回读
#   9. verify 四态契约     六键齐全；刚 update 完 verified=true；删文档 → missing=1
#                          且 verified=false、note 带备份路径（缺失 ≠ 通过）
#  10. graph scene 契约   moongit-graph-scene v1：五键齐全、v==1、themes 两套、
#                          edgesDropped/warnings 恒发、chips[].count 是数字、
#                          shape 类型只五种、hits 带 id/x/y/w
#  11. 架构图回执契约     arch gen / render arch 是**回执型命令**（stdout 是人话，
#                          不是 JSON）：回执非空、给出 arch.json / .html 落盘路径；
#                          arch gen --format json 另给一份机器可读载荷
#  12. agent 工具清单对位 引擎 `tools --json` 声明集 ⇄ 客户端能执行清单
#                          （客户端 `deepDolphin --agent-tool-names`）：必须严格相等。
#                          漂移的症状很隐蔽：模型调了个客户端不会执行的工具，
#                          界面上只显示「未知工具：X」，很容易被当成模型乱调
#
# 引擎缺席：SKIP 且不算通过（如实报告，不伪造契约验证）。
set -uo pipefail

BIN="${DEEPGIT_BIN:-}"
if [ -z "$BIN" ]; then
    BIN="$(command -v moongit || command -v deepgit || true)"
fi
if [ -z "$BIN" ]; then
    echo "SKIP contract-check：未找到 moongit/deepgit（可设 DEEPGIT_BIN 指定）"
    exit 0
fi
command -v python3 >/dev/null || { echo "SKIP contract-check：需要 python3 做 JSON 断言"; exit 0; }

# 客户端二进制（第 12 组要拿它的工具清单）。找不到 → 该组显式 SKIP，
# **不算通过**（否则「清单没对过」会被当成「对过了」）。
CLIENT_BIN="${DEEPGIT_CLIENT_BIN:-}"
if [ -z "$CLIENT_BIN" ]; then
    CLIENT_BIN="$(cd "$(dirname "$0")/.." && pwd)/build/deepDolphin"
fi

echo "› 引擎：$BIN"
"$BIN" version >/dev/null || { echo "✗ 引擎探活失败"; exit 1; }

SANDBOX="$(mktemp -d /tmp/dd-contract.XXXXXX)"
export DEEPGIT_HOME="$SANDBOX/home"
FIX="$SANDBOX/fixture/atlas"
mkdir -p "$FIX/src"
git -C "$FIX" init -q -b main . 2>/dev/null
printf '# atlas\n\nUSER-SENTINEL 用户手写内容不许动\n' > "$FIX/README.md"
# ⚠ 夹具必须带**源码**：没有源码的项目，arch 视图是空的（0 shapes / 0 hits /
#   包围盒退化）—— scene 那组断言会整组空转，看着全绿其实什么都没验到。
# ⚠ main.c 里那个**跨文件调用**（compute 在 util.c）是第 14 组的原料：
#   没有跨文件函数边，热力图的「跨作用域边界卡」就没有真实数据可验，
#   那组断言会整组空转（看着全绿，其实什么都没验到）。
printf 'int compute(int n);\nint main(void) {\n    return compute(21);\n}\n' > "$FIX/src/main.c"
printf 'int compute(int n) {\n    return n * 2;\n}\n' > "$FIX/src/util.c"
git -C "$FIX" add . 2>/dev/null
GIT_AUTHOR_DATE='2026-10-03T09:00:00' GIT_COMMITTER_DATE='2026-10-03T09:00:00' \
    git -C "$FIX" commit -qm 'feat: 初始提交' 2>/dev/null
git -C "$FIX" checkout -qb feature/search 2>/dev/null
printf 'x' > "$FIX/search.c"
git -C "$FIX" add . 2>/dev/null
GIT_AUTHOR_DATE='2026-10-03T10:00:00' GIT_COMMITTER_DATE='2026-10-03T10:00:00' \
    git -C "$FIX" commit -qm 'feat(search): 搜索实现' 2>/dev/null
git -C "$FIX" checkout -q main 2>/dev/null

pass=0; fail=0
check() { # check <名称> <python表达式（stdin 为 JSON 文本）> [json]
    local name="$1" expr="$2" json="${3:-}"
    if printf '%s' "$json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
sys.exit(0 if ($expr) else 1)
" 2>/dev/null; then
        echo "  ✓ $name"; pass=$((pass+1))
    else
        echo "  ✗ $name"; fail=$((fail+1))
    fi
}

# 文本断言器：给**回执型命令**用（arch gen / render arch 的 stdout 是人话，
# 不是 JSON —— 拿 JSON 解析器去收它们会把成功报成失败，这正是客户端
# EngineCli 分 Json/Text 两套输出契约的起因）。
check_text() { # check_text <名称> <ERE> <文本>
    local name="$1" ere="$2" text="${3:-}"
    if printf '%s' "$text" | grep -qE "$ere"; then
        echo "  ✓ $name"; pass=$((pass+1))
    else
        echo "  ✗ $name"; fail=$((fail+1))
    fi
}

trap 'rm -rf "$SANDBOX"' EXIT
echo "› 沙箱：$SANDBOX（DEEPGIT_HOME 隔离，退出即清）"

# 1+2. add → status 恒等式与项目键
"$BIN" add "$FIX" --json >/dev/null 2>&1
STATUS="$("$BIN" status --json 2>/dev/null)"
check "status 恒等式：envelope={projects,summary,language} 且 listedProjects==len(projects)" \
    "sorted(d.keys())==['language','projects','summary'] and d['summary'].get('listedProjects')==len(d['projects'])" "$STATUS"
check "status 项目键：id/currentBranch/branches/dirty/commitCount 存在" \
    "d['projects'] and all(k in d['projects'][0] for k in ('id','currentBranch','branches','dirty','commitCount'))" "$STATUS"

# 7+8. update 载荷与文档托管承诺（必须在 dashboard 前：分支事实由成功 update 记入进度库）
# update 有两种合法形状：单项目直返逐仓载荷 {ok, docs, journalEntry…}；
# 多项目聚合信封 {count, results, succeeded, failed}。两种都要认。
UPD="$("$BIN" update --json 2>/dev/null)"
check "update 载荷：单项目逐仓（ok+docs）或聚合信封（succeeded==1）" \
    "(d.get('ok') is True and isinstance(d.get('docs'), list)) or (all(k in d for k in ('count','results','succeeded','failed')) and d.get('succeeded')==1)" "$UPD"
grep -q 'deepgit:begin' "$FIX/README.md" \
    && { echo "  ✓ 文档托管：README 出现托管标记"; pass=$((pass+1)); } \
    || { echo "  ✗ 文档托管：README 无托管标记"; fail=$((fail+1)); }
grep -q 'USER-SENTINEL 用户手写内容不许动' "$FIX/README.md" \
    && { echo "  ✓ 文档托管：用户哨兵行逐字节保留"; pass=$((pass+1)); } \
    || { echo "  ✗ 文档托管：用户内容被改动！"; fail=$((fail+1)); }
DOCS="$("$BIN" docs atlas --json 2>/dev/null)"
check "docs 回读：README 内容含哨兵行" \
    "'USER-SENTINEL' in json.dumps(d, ensure_ascii=False)" "$DOCS"

# 3. dashboard：成功 update 后，领先分支恰好 1 条可合入
DASH="$("$BIN" dashboard --json 2>/dev/null)"
check "dashboard：work.mergeCandidates==1（fixture 领先分支数）" \
    "d.get('work',{}).get('mergeCandidates')==1" "$DASH"

# 4+5. milestone：对账与动作载荷
"$BIN" milestone add atlas 'v1.0' --desc 契约检查 --json >/dev/null 2>&1
MLIST="$("$BIN" milestone list --json 2>/dev/null)"
check "milestone 对账：readCount==len(milestones)" \
    "d.get('readCount')==len(d.get('milestones',[]))" "$MLIST"
MDONE="$("$BIN" milestone done atlas v1.0 --json 2>/dev/null)"
check "milestone done 载荷：applied 为真且带 status（无 message 键依赖）" \
    "d.get('applied') is True and isinstance(d.get('status'), str) and 'message' not in d" "$MDONE"

# 6. scan 差值：重扫已注册目录，不再重复注册
SCAN="$("$BIN" scan "$(dirname "$FIX")" --depth 2 --json 2>/dev/null)"
check "scan 差值：found ≥ 1 且 added == 0（已注册不重报）" \
    "len(d.get('candidates',[]))>=1 and d.get('added',0)==0" "$SCAN"

# 9. verify 契约（引擎新能力，客户端 DocumentIntegrity 消费）：四态口径必须逐字对齐。
#    放在最后：第 9 条要删 README 才能造出 missing 档。
VERIFY="$("$BIN" verify atlas --json 2>/dev/null)"
check "verify 载荷：六键齐全（checked/failures/undetermined/missing/verified/documents）" \
    "all(k in d for k in ('checked','failures','undetermined','missing','verified','documents'))" "$VERIFY"
check "verify 刚 update 完：verified 为真且零失败零缺失" \
    "d.get('verified') is True and d.get('failures')==0 and d.get('undetermined')==0 and d.get('missing')==0" "$VERIFY"
check "verify 文档条目：project/doc/ok 三键在" \
    "d.get('documents') and all(k in d['documents'][0] for k in ('project','doc','ok'))" "$VERIFY"

# 缺失档：删掉受管文档 → missing==1 且 verified==false，且 note 带**可操作的备份路径**
mv "$FIX/README.md" "$FIX/README.md.hidden"
VERIFY_MISSING="$("$BIN" verify atlas --json 2>/dev/null)"
mv "$FIX/README.md.hidden" "$FIX/README.md"
check "verify 缺失档：missing==1 且 verified 为假（缺失 ≠ 通过）" \
    "d.get('missing')==1 and d.get('verified') is False" "$VERIFY_MISSING"
check "verify 缺失档：note 带备份路径（用户下一步要的东西不许被吞）" \
    "'备份' in json.dumps(d, ensure_ascii=False) and 'backups' in json.dumps(d, ensure_ascii=False)" "$VERIFY_MISSING"

# 10. graph arch --format scene 契约（moongit-graph-scene v1）：客户端 GraphScene 模型层
#     消费的键名与口径，逐字对真引擎输出。
SCENE="$("$BIN" graph arch atlas --format scene 2>/dev/null)"
check "scene 顶层：v/gen/themes/views/panels 五键齐全" \
    "all(k in d for k in ('v','gen','themes','views','panels'))" "$SCENE"
check "scene 版本：v==1 且 gen=='moongit-graph'（契约版本不认识就明说，不静默兼容）" \
    "d.get('v')==1 and d.get('gen')=='moongit-graph'" "$SCENE"
check "scene 主题：dark/light 两套，且含 cols/fills/langs 与 simple token" \
    "all(t in d.get('themes',{}) for t in ('dark','light')) and all(k in d['themes']['dark'] for k in ('text','muted','bg0','cols','fills','langs'))" "$SCENE"
check "scene 视图：含 arch，且每个 view 都发 edgesDropped（恒发，0 也发）" \
    "'arch' in d.get('views',{}) and all('edgesDropped' in v for v in d['views'].values())" "$SCENE"
check "scene 告警：meta.warnings 四字段恒发（空也发）" \
    "all(k in d.get('meta',{}).get('warnings',{}) for k in ('violations','cycleEdges','violationPairs','cycleModules'))" "$SCENE"
check "scene 分层：chips 是数组（空也发）且每个 count 是**数字**字段（布局读它，不许从 label 抠数字）" \
    "isinstance(d.get('meta',{}).get('chips'), list) and all(isinstance(c.get('count'), int) for c in d['meta']['chips'])" "$SCENE"
check "scene 形状：t 只在已知的五种里（frame/rrect/rect/text/edge）" \
    "all(s.get('t') in ('frame','rrect','rect','text','edge') for v in d.get('views',{}).values() for s in v.get('shapes',[]))" "$SCENE"
check "scene 命中区：hits 带 id/x/y/w（下钻靠它）" \
    "all(all(k in h for k in ('id','x','y','w')) for v in d.get('views',{}).values() for h in v.get('hits',[]))" "$SCENE"
# 包围盒（bounds）：客户端的视口自适应**只**靠它。缺了 → 包围盒恒 0 →
# fit 退化成恒等视口 → 图不缩放、贴在左上角（且客户端看不出来）。
check "scene 包围盒：每个 view 都发 bounds{x0,y0,x1,y1}（自适应视口全靠它）" \
    "all(all(k in v.get('bounds',{}) for k in ('x0','y0','x1','y1')) for v in d.get('views',{}).values())" "$SCENE"
check "scene 视图非空：夹具带源码 → arch 有 shapes 且有 hits（否则整组断言空转）" \
    "d.get('views',{}).get('arch',{}).get('shapes') and d.get('views',{}).get('arch',{}).get('hits')" "$SCENE"
check "scene 包围盒：有 shape 的 view 包围盒非退化（x1>x0 且 y1>y0，否则图无处可放）" \
    "all((not v.get('shapes')) or (v['bounds']['x1'] > v['bounds']['x0'] and v['bounds']['y1'] > v['bounds']['y0']) for v in d.get('views',{}).values())" "$SCENE"

# 11. 架构图生成/导出契约（**回执型命令**：stdout 是人话回执，不是 JSON）。
#     客户端 AppModel::genArch/exportArch 走 EngineCli 的 Text 契约消费它们。
ARCH_GEN="$("$BIN" arch gen atlas 2>/dev/null)"
check_text "arch gen 回执：非空且说清生成了（Text 契约：非空即算成功）" \
    '架构已生成' "$ARCH_GEN"
check_text "arch gen 回执：给出 arch.json 落盘路径（经引擎写，客户端不碰项目文件）" \
    'arch\.json' "$ARCH_GEN"

ARCH_GEN_JSON="$("$BIN" arch gen atlas --format json 2>/dev/null)"
check "arch gen --format json：载荷是合法 JSON 且含 modules 数组（模块分层数据）" \
    "isinstance(d.get('modules'), list)" "$ARCH_GEN_JSON"

RENDER="$("$BIN" render arch atlas 2>/dev/null)"
check_text "render arch 回执：非空且给出 .html 落盘路径（引擎层交付物）" \
    '\.html' "$RENDER"

# 12. agent 工具清单对位（引擎 tools --json ⇄ 客户端能执行清单）。
#     漂移的表现：模型调了一个客户端不会执行的工具，界面上只显示一句
#     「未知工具：X」—— 很容易被当成模型乱调，而真因是两份清单已经不一致。
#     引擎加工具时必须同步客户端，否则这条会红。
if [ ! -x "$CLIENT_BIN" ]; then
    echo "  ‣ SKIP 第 12 组：找不到客户端二进制 $CLIENT_BIN（可设 DEEPGIT_CLIENT_BIN 指定）"
    echo "    ‣ 本组**未验证**，不算通过"
else
    ENGINE_TOOLS_JSON="$("$BIN" tools --json 2>/dev/null)"
    CLIENT_TOOLS="$("$CLIENT_BIN" --agent-tool-names 2>/dev/null)"
    ENGINE_TOOLS="$(printf '%s' "$ENGINE_TOOLS_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('\n'.join(sorted(t.get('name','') for t in d.get('tools',[]) if t.get('name'))))
" 2>/dev/null | grep -v '^$' | sort)"
    CLIENT_SORTED="$(printf '%s\n' "$CLIENT_TOOLS" | grep -v '^$' | sort)"
    # 前提：两边都抓到了东西（抓不到就是本组空转，必须先修抓取）
    if [ -z "$ENGINE_TOOLS" ] || [ -z "$CLIENT_SORTED" ]; then
        echo "  ✗ 第 12 组前提：引擎或客户端的清单没抓到（引擎 $(printf '%s\n' "$ENGINE_TOOLS" | grep -c . ) 个 / 客户端 $(printf '%s\n' "$CLIENT_SORTED" | grep -c . ) 个）" >&2
        fail=$((fail+1))
    else
        echo "  ✓ 第 12 组前提：引擎 $(printf '%s\n' "$ENGINE_TOOLS" | grep -c . ) 个 / 客户端 $(printf '%s\n' "$CLIENT_SORTED" | grep -c . ) 个（两边都抓到了，不是空转）"
        pass=$((pass+1))
        # 差集用临时文件比对（不用进程替换：脚本以 sh/dash 跑，POSIX 没有 <(...)）
        _e="$SANDBOX/tools-engine.txt"
        _c="$SANDBOX/tools-client.txt"
        printf '%s\n' "$ENGINE_TOOLS" > "$_e"
        printf '%s\n' "$CLIENT_SORTED" > "$_c"
        ONLY_ENGINE="$(comm -23 "$_e" "$_c")"
        ONLY_CLIENT="$(comm -13 "$_e" "$_c")"
        if [ -z "$ONLY_ENGINE" ] && [ -z "$ONLY_CLIENT" ]; then
            echo "  ✓ agent 工具清单：客户端能执行的工具集 == 引擎声明的工具集（一份清单不许抄两份）"
            pass=$((pass+1))
        else
            echo "  ✗ agent 工具清单：两份清单漂移了。" >&2
            [ -n "$ONLY_ENGINE" ] && echo "      引擎有、客户端不会执行：$(echo "$ONLY_ENGINE" | tr '\n' ' ')" >&2
            [ -n "$ONLY_CLIENT" ] && echo "      客户端会执行、引擎没声明：$(echo "$ONLY_CLIENT" | tr '\n' ' ')" >&2
            fail=$((fail+1))
        fi
    fi
fi

# 13. 代码图谱三源契约（graph tree / confidence / functions）。
#     客户端的树骨架、疑点归属、调用关系全靠这三份合成。
#     ⚠ 最要紧的是**符号 id 构造式**：tree 的 symbols 不带 id，客户端按
#       `f:<路径>:<行号>:<名字>` 造一个；这个构造式必须与引擎 functions 侧的
#       id 同形 —— 不同形就永远对不上「调用方/被调方」，且症状极隐蔽
#       （树能画、关系页签永远空）。
TREE_JSON="$("$BIN" graph tree atlas --depth 8 --json 2>/dev/null)"
CONF_JSON="$("$BIN" graph confidence atlas --json 2>/dev/null)"
FNS_JSON="$("$BIN" graph functions atlas --json 2>/dev/null)"

check "代码图谱 tree：root/files 齐全，且 files[].symbols[] 带 name/line/kind" \
    "isinstance(d.get('root'), str) and isinstance(d.get('files'), list) and all(all(k in s for k in ('name','line','kind')) for f in d.get('files',[]) for s in f.get('symbols',[]))" \
    "$TREE_JSON"
check "代码图谱 tree：symbols **不带 id**（客户端按构造式造；引擎若开始发 id，两边要对上）" \
    "all('id' not in s for f in d.get('files',[]) for s in f.get('symbols',[]))" \
    "$TREE_JSON"
check "代码图谱 tree：truncated/skipped/oversizeSkipped 恒发（截断披露不能缺键）" \
    "all(k in d for k in ('truncated','skipped','oversizeSkipped'))" \
    "$TREE_JSON"
check "代码图谱 confidence：score/astNote/dimensions/findings 齐全" \
    "isinstance(d.get('score'), int) and 'astNote' in d and isinstance(d.get('dimensions'), list) and isinstance(d.get('findings'), list)" \
    "$CONF_JSON"
check "代码图谱 confidence：findings[] 带 kind/file/line/weight（归属键的来源）" \
    "all(all(k in f for k in ('kind','file','line','weight')) for f in d.get('findings',[]))" \
    "$CONF_JSON"
check "代码图谱 functions：functions/functionEdges/codeSnippets 齐全" \
    "isinstance(d.get('functions'), list) and isinstance(d.get('functionEdges'), list) and isinstance(d.get('codeSnippets'), dict)" \
    "$FNS_JSON"
# 符号 id 构造式必须与引擎同形（f:<路径>:<行号>:<名字>）
check "代码图谱 functions：符号 id 与客户端构造式同形 f:路径:行号:名字（关系页签全靠它对上）" \
    "all(f['id'] == 'f:' + f['file'] + ':' + str(f['line']) + ':' + f['name'] for f in d.get('functions',[]))" \
    "$FNS_JSON"
# ⚠ 上一条验的是**引擎侧**的形状；客户端的构造函数也得真的与之同形 ——
#   否则树能画、关系页签永远空（症状极隐蔽）。这里**端到端**比：
#   拿引擎给的一个真实符号，问客户端二进制「同样三个输入你会造出什么 id」。
if [ ! -x "$CLIENT_BIN" ]; then
    echo "  ‣ SKIP 符号 id 端到端比对：找不到客户端二进制 $CLIENT_BIN"
    echo "    ‣ 本条**未验证**，不算通过"
else
    # 用 python 做比对（别在 sh 里切 tab：dash 的 read 不认 $'\t'）
    E2E_OUT="$(printf '%s' "$FNS_JSON" | python3 -c "
import json, subprocess, sys
client = sys.argv[1]
d = json.load(sys.stdin)
fns = d.get('functions', [])[:3]
if not fns:
    print('EMPTY'); sys.exit(0)
bad = []
for f in fns:
    out = subprocess.run([client, '--code-graph-symbol-id', f.get('file',''),
                          str(f.get('line',0)), f.get('name','')],
                         capture_output=True, text=True).stdout.strip()
    if out != f.get('id',''):
        bad.append((f.get('file'), f.get('line'), f.get('name'), out, f.get('id')))
for b in bad:
    print('MISMATCH\t' + '\t'.join(str(x) for x in b))
print('COUNT\t%d' % len(fns))
" "$CLIENT_BIN" 2>/dev/null)"
    E2E_N="$(printf '%s\n' "$E2E_OUT" | grep '^COUNT' | head -1 | cut -f2 | tr -d '[:space:]')"
    E2E_BAD="$(printf '%s\n' "$E2E_OUT" | grep -c '^MISMATCH' || true)"
    if [ "$E2E_N" -eq 0 ]; then
        echo "  ✗ 符号 id 端到端：没取到可比对的符号（断言空转，必须先修取数）" >&2
        fail=$((fail+1))
    elif [ "$E2E_BAD" -ne 0 ]; then
        echo "  ✗ 符号 id 端到端：客户端造的 id 与引擎给的不一致 ——" >&2
        printf '%s\n' "$E2E_OUT" | grep '^MISMATCH' | cut -f2- | while read -r line; do
            echo "      $line" >&2
        done
        fail=$((fail+1))
    else
        echo "  ✓ 符号 id 端到端：客户端对 ${E2E_N} 个真实符号造出的 id 与引擎完全一致"
        pass=$((pass+1))
    fi
fi

# 14. 三源**符号对齐**（热力图「跨作用域边界卡」的前提）。
#     客户端用 graph tree 的 (路径,名字,行号) 造符号 id，用 graph functions 的
#     引擎 id 认调用边。两边对不上（哪怕只差一个行号）→「调用方在不在作用域内」
#     就判错，跨作用域引用会**静默消失**：热力图少画几张卡，用户看不出是契约漂移
#     还是数据就这样 —— 这类症状最难查，所以要在契约层钉死。
#     另附一条前提：夹具里确有**跨文件**函数边，否则这组是空转。
ALIGN_JSON="$(printf '%s' "$TREE_JSON" | python3 -c "
import json, sys
t = json.load(sys.stdin)
f = json.loads(sys.argv[1])
print(json.dumps({'tree': t, 'fns': f}, ensure_ascii=False))
" "$FNS_JSON" 2>/dev/null)"
if [ -z "$ALIGN_JSON" ]; then
    echo "  ✗ 第 14 组前提：两份 JSON 合不到一起（tree/functions 没取到）" >&2
    fail=$((fail+1))
else
    check "代码图谱符号对齐：tree 与 functions 的符号集合逐条一致（差集为空）" \
        "len(d['tree'].get('files',[]))>0 and len(d['fns'].get('functions',[]))>0 and \
{(fl.get('path'), s.get('name'), s.get('line')) for fl in d['tree'].get('files',[]) for s in fl.get('symbols',[])} == \
{(x.get('file'), x.get('name'), x.get('line')) for x in d['fns'].get('functions',[])}" \
        "$ALIGN_JSON"
    check "代码图谱跨文件调用边：夹具造得出跨文件 functionEdge（热力图边界卡的原料）" \
        "any(e.get('from','').split(':')[1:2] != e.get('to','').split(':')[1:2] for e in d['fns'].get('functionEdges',[]))" \
        "$ALIGN_JSON"
fi

# 15. 补丁体检契约（引擎 graph patchconf 三层）。
#     客户端的三层判定全靠这三个载荷的形状 —— 形状一漂，界面就会把
#     「算不出的信号（null）」显示成 0 分、把「拿不准的项」整段吞掉。
#     夹具是**独立项目**：改动必须留在工作区（不提交），又不能污染主夹具
#     （主夹具的 tree/arch 断言依赖它的原始内容）。
#     改动内容特意调一个**仓库里不存在**的函数 → 造出真实的「拿不准的项」，
#     否则 uncertain 恒空，那组断言就整组空转（看着全绿，其实什么都没验到）。
PFIX="$SANDBOX/fixture/atlaspatch"
mkdir -p "$PFIX/src"
git -C "$PFIX" init -q -b main . 2>/dev/null
printf 'int compute(int n) {\n    return n * 2;\n}\n' > "$PFIX/src/util.c"
git -C "$PFIX" add . 2>/dev/null
GIT_AUTHOR_DATE='2026-10-03T09:00:00' GIT_COMMITTER_DATE='2026-10-03T09:00:00' \
    git -C "$PFIX" commit -qm 'feat: 初始提交' 2>/dev/null
# ↓ 未提交改动（留在工作区，不提交）
printf 'int compute(int n) {\n    return n * 2;\n}\n\nint helper(int a) {\n    return mystery_call(a) + 1;\n}\n' \
    > "$PFIX/src/util.c"
git -C "$PFIX" diff HEAD > "$SANDBOX/patch.diff" 2>/dev/null
"$BIN" add "$PFIX" --json >/dev/null 2>&1
PATCH_JSON="$("$BIN" graph patchconf atlaspatch --patch "$SANDBOX/patch.diff" --json 2>/dev/null)"
if [ -z "$PATCH_JSON" ]; then
    echo "  ✗ 第 15 组前提：引擎没吐出补丁体检载荷（patchconf 缺席或项目没注册）" >&2
    fail=$((fail+1))
else
    check "补丁体检 Layer1：schema 是 moongit-patch-confidence/1" \
        "d.get('schema') == 'moongit-patch-confidence/1'" \
        "$PATCH_JSON"
    check "补丁体检 Layer1：总分在 0..1 之间且是数字" \
        "isinstance(d.get('overall'), (int, float)) and not isinstance(d.get('overall'), bool) and 0.0 <= d['overall'] <= 1.0" \
        "$PATCH_JSON"
    check "补丁体检 Layer1：signals 的值要么是数字要么是 null（null = 分母为 0，算不出）" \
        "isinstance(d.get('signals'), dict) and all(v is None or (isinstance(v, (int, float)) and not isinstance(v, bool)) for v in d['signals'].values())" \
        "$PATCH_JSON"
    check "补丁体检 Layer1：signals 含 S1..S10 全部键（少了就是契约漂了）" \
        "set(['S%d' % i for i in range(1, 11)]) <= set(d.get('signals', {}).keys())" \
        "$PATCH_JSON"
    check "补丁体检 Layer1：entities 每项带 id/kind/confidence/file/line" \
        "isinstance(d.get('entities'), list) and all(set(['id','kind','confidence','file','line']) <= set(e.keys()) for e in d['entities'])" \
        "$PATCH_JSON"
    check "补丁体检 Layer1：uncertain 每项带 id/issue/detail 与 context_ref{file,line}" \
        "isinstance(d.get('uncertain'), list) and all(set(['id','issue','detail']) <= set(u.keys()) and isinstance(u.get('context_ref'), dict) and set(['file','line']) <= set(u['context_ref'].keys()) for u in d['uncertain'])" \
        "$PATCH_JSON"
    check "补丁体检 Layer1：夹具造得出真实的「拿不准的项」（不确定项恒空就是空转）" \
        "len(d.get('uncertain', [])) > 0" \
        "$PATCH_JSON"
    check "补丁体检 Layer1：diagnostics 带 total_entities/patch_files/added_lines/null_signals" \
        "isinstance(d.get('diagnostics'), dict) and set(['total_entities','patch_files','added_lines','null_signals']) <= set(d['diagnostics'].keys())" \
        "$PATCH_JSON"

    # Layer 3 合并：拿 Layer 1 的载荷 + 一份裁决 → 终稿
    printf '%s' "$PATCH_JSON" > "$SANDBOX/algorithm.json"
    python3 - "$SANDBOX/algorithm.json" "$SANDBOX/agent.json" <<'PY'
import json, sys
alg = json.load(open(sys.argv[1]))
items = [{"id": u.get("id", ""), "verdict": "unresolved", "value": "",
          "confidence": 0.05, "reason": "契约门：人工裁决未解析",
          "evidence_refs": []} for u in alg.get("uncertain", [])]
json.dump({"task": "layer2_review", "items": items}, open(sys.argv[2], "w"))
PY
    MERGED_JSON="$("$BIN" graph patchconf --merge "$SANDBOX/algorithm.json" "$SANDBOX/agent.json" --json 2>/dev/null)"
    if [ -z "$MERGED_JSON" ]; then
        echo "  ✗ 第 15 组前提：引擎没吐出合并终稿（--merge 缺席）" >&2
        fail=$((fail+1))
    else
        check "补丁体检 Layer3：schema 是 moongit-patch-confidence-merged/1" \
            "d.get('schema') == 'moongit-patch-confidence-merged/1'" \
            "$MERGED_JSON"
        check "补丁体检 Layer3：alerts 每项带 level/type/detail" \
            "isinstance(d.get('alerts'), list) and all(set(['level','type','detail']) <= set(a.keys()) for a in d['alerts'])" \
            "$MERGED_JSON"
        check "补丁体检 Layer3：sources 带 algorithm/agent 两个来源标志" \
            "isinstance(d.get('sources'), dict) and set(['algorithm','agent']) <= set(d['sources'].keys())" \
            "$MERGED_JSON"
        check "补丁体检 Layer3：复核数在 diagnostics.reviewed_by_agent（顶层 reviewed 没有这个键）" \
            "isinstance(d.get('diagnostics'), dict) and 'reviewed_by_agent' in d['diagnostics']" \
            "$MERGED_JSON"
    fi
fi

echo "──── contract-check: $pass passed, $fail failed ────"
[ "$fail" -eq 0 ]