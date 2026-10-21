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
    # ⚠⚠⚨ 批 CB：未验证 ⇒ **专属退出码 3**（不是 0）⇒ 调用方能把它与「通过」分开。
    #   ⚠ 批 BW 早就在探针侧立了这条口径（0=通过 / 1=失败 / 3=SKIP），
    #     而且它的注释**早就写着**「与第 10 步契约门同款口径」
    #     ⇒ 但本脚本一直用的是 `exit 0` ⇒ **注释与实际行为不一致** ⇒ 本批对齐。
    #   ⚠ 以前 exit 0 ⇒ ci.sh 判「✓ 引擎契约门通过」⇒ **一条断言都没跑却说通过**。
    exit 3
fi
command -v python3 >/dev/null || { echo "SKIP contract-check：需要 python3 做 JSON 断言"; exit 3; }

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

# 16. 语法高亮的语言集合 ⇄ 引擎 detectLang 的产物。
#     引擎的 `graph/extract.cj:detectLang` 恰好产出九种语言；客户端的语法高亮
#     必须覆盖**同样这九种** —— 少一种，那种语言的源码就是一片纯色，而
#     「一片纯色」在界面上看不出是缺能力还是代码本来就长这样。
#     用**独立项目**（langfix）跑：往主夹具里加 9 个不同扩展名的文件会改掉
#     主夹具的 tree/arch 断言前提。
LANGFIX="$SANDBOX/fixture/langfix"
mkdir -p "$LANGFIX"
git -C "$LANGFIX" init -q -b main . 2>/dev/null
printf 'func greet() {}\n' > "$LANGFIX/a.swift"
printf 'func main() {}\n' > "$LANGFIX/a.cj"
printf 'export const x = 1;\n' > "$LANGFIX/a.ts"
printf 'def f():\n    return 1\n' > "$LANGFIX/a.py"
printf 'package main\nfunc main() {}\n' > "$LANGFIX/a.go"
printf 'fn main() {}\n' > "$LANGFIX/a.rs"
printf 'class A {}\n' > "$LANGFIX/a.java"
printf 'fun main() {}\n' > "$LANGFIX/a.kt"
printf 'int main(void) { return 0; }\n' > "$LANGFIX/a.c"
git -C "$LANGFIX" add . 2>/dev/null
GIT_AUTHOR_DATE='2026-10-03T09:00:00' GIT_COMMITTER_DATE='2026-10-03T09:00:00' \
    git -C "$LANGFIX" commit -qm 'feat: 九种语言' 2>/dev/null
"$BIN" add "$LANGFIX" --json >/dev/null 2>&1
LANG_TREE="$("$BIN" graph tree langfix --depth 8 --json 2>/dev/null)"
CLIENT_LANGS="$("$CLIENT_BIN" --syntax-languages 2>/dev/null)"
if [ -z "$LANG_TREE" ] || [ -z "$CLIENT_LANGS" ]; then
    echo "  ✗ 第 16 组前提：没取到引擎语言清单或客户端语言清单" >&2
    fail=$((fail+1))
else
    LANG_JSON="$(printf '%s\n%s' "$LANG_TREE" "$CLIENT_LANGS" | python3 -c "
import json, sys
raw = sys.stdin.read()
dec = json.JSONDecoder()
t, idx = dec.raw_decode(raw.lstrip())
rest = raw.lstrip()[idx:].strip()
print(json.dumps({'tree': t, 'client': [x for x in rest.splitlines() if x.strip()]}, ensure_ascii=False))
" 2>/dev/null)"
    check "语法高亮语言集合：客户端清单与引擎 detectLang 的产物**逐条相等**" \
        "sorted({f.get('lang') for f in d['tree'].get('files',[]) if f.get('lang')}) == sorted(set(d['client']))" \
        "$LANG_JSON"
    check "语法高亮语言集合：九种语言一个不少（少一种 = 那种语言的源码是纯色）" \
        "len(set(d['client'])) == 9" \
        "$LANG_JSON"
fi

# 17. 图谱三件套（引擎 graph overview / symbol / impact）。
#     关键一条：**引擎的 symbol / impact 只认「符号名」** —— 传符号 id
#     （f:路径:行号:名字）进去，引擎返回空结果。那空结果看着像「这个符号没有
#     影响面」，其实是有影响面的（客户端明明持有 id，却传错了形态）。
#     这条陷阱钉在契约层，客户端那侧也有对应判据（logic/GraphInsight 的
#     symbolNameFromId）。
OV_JSON="$("$BIN" graph overview atlas --json 2>/dev/null)"
SYM_JSON="$("$BIN" graph symbol atlas compute --json 2>/dev/null)"
IMP_JSON="$("$BIN" graph impact atlas compute --json 2>/dev/null)"
# 传**符号 id**（而不是名字）→ 引擎给空结果
IMP_BY_ID_JSON="$("$BIN" graph impact atlas 'f:src/util.c:1:compute' --json 2>/dev/null)"
# 符号不存在 → 引擎返回空 defs 且**退出码 0**（不是错误）
SYM_MISS_JSON="$("$BIN" graph symbol atlas nosuchsym --json 2>/dev/null)"
SYM_MISS_RC=0
"$BIN" graph symbol atlas nosuchsym --json >/dev/null 2>&1 || SYM_MISS_RC=$?
if [ -z "$OV_JSON" ] || [ -z "$SYM_JSON" ] || [ -z "$IMP_JSON" ]; then
    echo "  ✗ 第 17 组前提：引擎没吐出三件套的载荷" >&2
    fail=$((fail+1))
else
    check "图谱 overview：root/files/symbols/topFiles/byLang/byKind 齐全" \
        "all(k in d for k in ['root','files','symbols','topFiles','byLang','byKind'])" \
        "$OV_JSON"
    check "图谱 overview：截断披露键恒发（truncated/skipped/oversizeSkipped/unreadableDirs）" \
        "all(k in d for k in ['truncated','skipped','oversizeSkipped','unreadableDirs','unreadableDirsTruncated'])" \
        "$OV_JSON"
    check "图谱 symbol：defs 与 referencedBy 键在，且 defs 每项带 file/line/kind" \
        "all(k in d for k in ['name','defs','referencedBy']) and all(set(['file','line','kind']) <= set(x.keys()) for x in d['defs'])" \
        "$SYM_JSON"
    check "图谱 impact：impactedSymbols/refFiles/granularity/两个 capped 键在" \
        "all(k in d for k in ['name','defs','refFiles','impactedSymbols','granularity','refFilesCapped','impactedCapped'])" \
        "$IMP_JSON"
    check "图谱 impact：受影响符号每项带 file/symbol/kind" \
        "all(set(['file','symbol','kind']) <= set(x.keys()) for x in d.get('impactedSymbols',[]))" \
        "$IMP_JSON"
    check "图谱 impact：**传符号名才有结果**（引擎只认名字）" \
        "len(d.get('impactedSymbols',[])) > 0" \
        "$IMP_JSON"
    check "图谱 impact：传符号 id 返回**空结果**（客户端必须先取名字，否则看着像「无影响面」）" \
        "len(d.get('impactedSymbols',[])) == 0 and len(d.get('defs',[])) == 0" \
        "$IMP_BY_ID_JSON"
    check "图谱 symbol：符号不存在时返回空 defs 且**退出码 0**（是「没找到」不是错误）" \
        "d.get('defs') == [] and d.get('name') == 'nosuchsym'" \
        "$SYM_MISS_JSON"
    if [ "$SYM_MISS_RC" -eq 0 ]; then
        echo "  ✓ 图谱 symbol：符号不存在的退出码是 0（不是错误退出）"; pass=$((pass+1))
    else
        echo "  ✗ 图谱 symbol：符号不存在的退出码是 $SYM_MISS_RC（应为 0）" >&2; fail=$((fail+1))
    fi
fi

# 18. 引擎自检（doctor）与进度报告（report）。
#     两处最容易「错得毫无声响」：
#     ① **doctor 发现问题时退出码是 1**（引擎自己注释写了「自检命令必须能失败」），
#        但 stdout 仍是**合法 JSON**。客户端若把非零退出当「命令崩了」，
#        用户看到的是「引擎调用失败」而不是「环境有 N 个问题」—— 自检工具
#        最该说清的事反而没说。这条用**真场景**（注册路径失效）造出来验。
#     ② **report 是回执型命令**：stdout 是人话（「报告已生成：<路径>（N 个项目）」），
#        不是 JSON。拿 JSON 解析器去收会把成功报成失败。
#     另附端到端：把真载荷/真回执喂给**客户端二进制**，逐条对判定结果 ——
#     自造夹具验的是另一回事（引擎形状变了、客户端没跟上，自造夹具照样全绿）。
DOCFIX="$SANDBOX/fixture/docfix"
mkdir -p "$DOCFIX/src"
git -C "$DOCFIX" init -q -b main . 2>/dev/null
printf 'int main(void) {\n    return 0;\n}\n' > "$DOCFIX/src/main.c"
git -C "$DOCFIX" add . 2>/dev/null
GIT_AUTHOR_DATE='2026-10-03T09:00:00' GIT_COMMITTER_DATE='2026-10-03T09:00:00' \
    git -C "$DOCFIX" commit -qm 'feat: 初始提交' 2>/dev/null
"$BIN" add "$DOCFIX" --json >/dev/null 2>&1

DOCTOR_JSON="$("$BIN" doctor --json 2>/dev/null)"
DOCTOR_RC=0
"$BIN" doctor --json >/dev/null 2>&1 || DOCTOR_RC=$?
if [ -z "$DOCTOR_JSON" ]; then
    echo "  ✗ 第 18 组前提：引擎没吐出 doctor 载荷" >&2
    fail=$((fail+1))
else
    check "引擎自检：载荷含 checks/problems，checks 每项带 check/result/detail" \
        "isinstance(d.get('checks'), list) and isinstance(d.get('problems'), int) and \
all(set(['check','result','detail']) <= set(c.keys()) for c in d['checks'])" \
        "$DOCTOR_JSON"
    check "引擎自检：result 是**自由文本**（有 OK 以外的值，客户端不许按 ==\"OK\" 判健康）" \
        "any(c.get('result') != 'OK' for c in d.get('checks', []))" \
        "$DOCTOR_JSON"
    check "引擎自检：临时残留**不计入** problems（客户端不许自己数「非 OK 的项」）" \
        "d.get('problems') == 0" \
        "$DOCTOR_JSON"

    # ⚠ 端到端：把真载荷喂给客户端二进制，看它判成哪一档。
    if [ ! -x "$CLIENT_BIN" ]; then
        echo "  ‣ SKIP 第 18 组端到端：找不到客户端二进制 $CLIENT_BIN"
        echo "    ‣ 本条**未验证**，不算通过"
    else
        DOCTOR_VERDICT="$(printf '%s' "$DOCTOR_JSON" | "$CLIENT_BIN" --doctor-parse 2>/dev/null)"
        check "引擎自检端到端：客户端对真载荷判成 ok 档、问题数与引擎一致" \
            "d.get('ok') is True and d.get('tone') == 'ok' and d.get('problems') == 0 and d.get('checks') > 0" \
            "$DOCTOR_VERDICT"
    fi
fi

# report：回执型命令（stdout 是人话），落盘 .md。
# ⚠ 放在「删掉 docfix」**之前**：注册路径没了，report 可能整条跑不通，
#   那时红的是 report 不是 doctor，两条断言会互相掩盖。
# ⚠ 引擎的 report 把回执写在 **stderr**（arch gen / render arch 才在 stdout，
#   实测 2026-10-19）。这里两路都收，客户端侧则按「stdout 优先、空则 stderr」
#   取回执（EngineCli::receiptText）—— 只认 stdout 的客户端会把成功说成失败。
"$BIN" report >"$SANDBOX/report.out" 2>"$SANDBOX/report.err"
REPORT_OUT="$(cat "$SANDBOX/report.out")"
REPORT_ERR="$(cat "$SANDBOX/report.err")"
REPORT_TXT="$REPORT_OUT
$REPORT_ERR"
if [ -z "$REPORT_TXT" ]; then
    echo "  ✗ 第 18 组前提：引擎没吐出 report 回执" >&2
    fail=$((fail+1))
else
    check_text "进度报告回执：给出 .md 落盘路径（Text 契约：回执型命令不是 JSON）" \
        '\.md' "$REPORT_TXT"
    REPORT_JSON="$(python3 -c "
import json, sys
out = open(sys.argv[1], encoding='utf-8', errors='replace').read()
err = open(sys.argv[2], encoding='utf-8', errors='replace').read()
print(json.dumps({'out': out, 'err': err}, ensure_ascii=False))
" "$SANDBOX/report.out" "$SANDBOX/report.err" 2>/dev/null)"
    check "进度报告回执：引擎把回执写在 **stderr**（客户端只认 stdout 会把成功说成失败）" \
        "not d['out'].strip() and '.md' in d['err']" "$REPORT_JSON"
    # 端到端：客户端从真回执里抽路径（剥 ANSI 后），且该文件**真的存在**。
    if [ ! -x "$CLIENT_BIN" ]; then
        echo "  ‣ SKIP 第 18 组报告路径端到端：找不到客户端二进制 $CLIENT_BIN"
        echo "    ‣ 本条**未验证**，不算通过"
    else
        REPORT_PATH="$(printf '%s' "$REPORT_TXT" | "$CLIENT_BIN" --receipt-file-path .md 2>/dev/null)"
        if [ -z "$REPORT_PATH" ]; then
            echo "  ✗ 进度报告端到端：客户端从真回执里抽不出 .md 路径（「打开报告」入口永远是坏的）" >&2
            fail=$((fail+1))
        elif [ -f "$REPORT_PATH" ]; then
            echo "  ✓ 进度报告端到端：客户端抽出的路径存在且是绝对路径（$REPORT_PATH）"
            pass=$((pass+1))
        else
            echo "  ✗ 进度报告端到端：客户端抽出的路径不存在（$REPORT_PATH）" >&2
            fail=$((fail+1))
        fi
    fi
fi

# 真问题档：把注册路径删掉 → 引擎报「1 个失效」，problems>0，**退出码 1**。
# 夹具独立（docfix）：删的是它自己的目录，不动主夹具 atlas。
rm -rf "$DOCFIX"
DOCTOR_BAD_JSON="$("$BIN" doctor --json 2>/dev/null)"
DOCTOR_BAD_RC=0
"$BIN" doctor --json >/dev/null 2>&1 || DOCTOR_BAD_RC=$?
if [ -z "$DOCTOR_BAD_JSON" ]; then
    echo "  ✗ 第 18 组前提：引擎没吐出有问题时的 doctor 载荷" >&2
    fail=$((fail+1))
else
    check "引擎自检：注册路径失效 → problems>0（引擎口径的问题数确实动了）" \
        "d.get('problems', 0) > 0" \
        "$DOCTOR_BAD_JSON"
    if [ "$DOCTOR_BAD_RC" -ne 0 ]; then
        echo "  ✓ 引擎自检：有问题时**退出码非 0**（自检必须能失败，否则脚本/CI 判断不了环境可用性）"
        pass=$((pass+1))
    else
        echo "  ✗ 引擎自检：有问题时退出码是 0（自检必须能失败）" >&2; fail=$((fail+1))
    fi
    # ⚠ 退出码非 0 但 stdout 仍是**合法 JSON** —— 客户端必须读载荷，不按退出码判成败。
    if printf '%s' "$DOCTOR_BAD_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
sys.exit(0 if isinstance(d, dict) and 'checks' in d else 1)
" 2>/dev/null; then
        echo "  ✓ 引擎自检：有问题时 stdout 仍是**合法 JSON**（客户端按退出码判成败会把「环境有问题」说成「命令崩了」）"
        pass=$((pass+1))
    else
        echo "  ✗ 引擎自检：有问题时 stdout 不是合法 JSON（客户端读不到载荷）" >&2; fail=$((fail+1))
    fi
    if [ ! -x "$CLIENT_BIN" ]; then
        echo "  ‣ SKIP 第 18 组端到端（问题档）：找不到客户端二进制 $CLIENT_BIN"
        echo "    ‣ 本条**未验证**，不算通过"
    else
        DOCTOR_BAD_VERDICT="$(printf '%s' "$DOCTOR_BAD_JSON" | "$CLIENT_BIN" --doctor-parse 2>/dev/null)"
        check "引擎自检端到端：有问题时客户端仍判为**有效报告**、档是 problem（不是 unreadable）" \
            "d.get('ok') is True and d.get('tone') == 'problem' and d.get('problems', 0) > 0" \
            "$DOCTOR_BAD_VERDICT"
    fi
fi

# 19. 引擎配置（config list / get / set）。
#     三处最容易「错得毫无声响」：
#     ① **`backupKeep: 0` 是合法值**（明确不保留备份），客户端若拿 0 当「引擎没发」
#        的哨兵，界面会把「明确不要备份」说成「不知道留几份」—— 意思完全相反。
#     ② **引擎的 `ai` 恒为空对象**（引擎自报「AI 由客户端层负责，引擎保持 AI 无关」）。
#        客户端若从引擎 config 读 AI 设置，就与客户端自己的 AI 设置形成**两个真相源**。
#     ③ **可写键只有四个**（language / update.backupKeep / update.maxShallowBranches /
#        roots）—— 界面给的键必须是引擎认的那些，给错键必然失败。
#     另注：`config set` 的回执走 **stderr**（与 `report` 同款），Text 契约要两路兜底。
CFG_JSON="$("$BIN" config list --json 2>/dev/null)"
if [ -z "$CFG_JSON" ]; then
    echo "  ✗ 第 19 组前提：引擎没吐出 config 载荷" >&2
    fail=$((fail+1))
else
    check "引擎配置：顶层键齐全（version/language/roots/ai/update）" \
        "all(k in d for k in ['version','language','roots','ai','update'])" \
        "$CFG_JSON"
    check "引擎配置：update 四键齐全（docs/agentDocCandidates/backupKeep/maxShallowBranches）" \
        "all(k in d.get('update',{}) for k in ['docs','agentDocCandidates','backupKeep','maxShallowBranches'])" \
        "$CFG_JSON"
    check "引擎配置：backupKeep / maxShallowBranches 是**数字**（客户端要按数字校验）" \
        "isinstance(d.get('update',{}).get('backupKeep'), int) and isinstance(d.get('update',{}).get('maxShallowBranches'), int)" \
        "$CFG_JSON"
    check "引擎配置：roots 与 docs 是数组（空也发）" \
        "isinstance(d.get('roots'), list) and isinstance(d.get('update',{}).get('docs'), list)" \
        "$CFG_JSON"
    check "引擎配置：引擎的 **ai 恒为空对象**（引擎 AI 无关；客户端不许从引擎读 AI 设置）" \
        "d.get('ai') == {}" \
        "$CFG_JSON"

    # config get：stdout 是 **JSON 值**（不是人话）—— 走 Json 契约
    CFG_GET="$("$BIN" config get language 2>/dev/null)"
    check "引擎配置：config get 返回 JSON 值（不是人话；走 Json 契约）" \
        "isinstance(d, str) and d != ''" \
        "$CFG_GET"

    # ⚠ config set 的回执在 **stderr**（实测 2026-10-19，与 report 同款）
    "$BIN" config set update.backupKeep 30 >"$SANDBOX/cfg.out" 2>"$SANDBOX/cfg.err"
    CFG_SET_OUT="$(cat "$SANDBOX/cfg.out")"
    CFG_SET_ERR="$(cat "$SANDBOX/cfg.err")"
    CFG_SET_JSON="$(python3 -c "
import json, sys
out = open(sys.argv[1], encoding='utf-8', errors='replace').read()
err = open(sys.argv[2], encoding='utf-8', errors='replace').read()
print(json.dumps({'out': out, 'err': err}, ensure_ascii=False))
" "$SANDBOX/cfg.out" "$SANDBOX/cfg.err" 2>/dev/null)"
    check "引擎配置：config set 的回执写在 **stderr**（Text 契约要两路兜底，只认 stdout 会把成功说成失败）" \
        "not d['out'].strip() and 'backupKeep' in d['err']" \
        "$CFG_SET_JSON"
    # 坏值必须被引擎拒（客户端界面靠这个说清「哪个值不对」）
    CFG_BAD="$("$BIN" config set update.backupKeep abc 2>&1)"
    check_text "引擎配置：config set 拒绝非整数值（客户端本地也拦一道，但引擎是最终裁判）" \
        '整数' "$CFG_BAD"
    # 未知键必须被引擎拒并列出可用键（客户端的键集要与之一致）
    CFG_UNKNOWN="$("$BIN" config set nosuchkey 1 2>&1)"
    check_text "引擎配置：config set 拒绝未知键并列出可用键（客户端键集须与之一致）" \
        '未知配置键' "$CFG_UNKNOWN"

    # 端到端：客户端解析真载荷
    if [ ! -x "$CLIENT_BIN" ]; then
        echo "  ‣ SKIP 第 19 组端到端：找不到客户端二进制 $CLIENT_BIN"
        echo "    ‣ 本条**未验证**，不算通过"
    else
        CFG_VERDICT="$(printf '%s' "$CFG_JSON" | "$CLIENT_BIN" --engine-config-parse 2>/dev/null)"
        check "引擎配置端到端：客户端对真载荷解析出同一组值（版本/语言/文档数/两个数字）" \
            "d.get('ok') is True and d.get('version') == 1 and d.get('language') == 'zh' and d.get('docs') > 0 and d.get('backupKeep') > 0 and d.get('maxShallowBranches') > 0" \
            "$CFG_VERDICT"
        # 回执净化端到端：真回执（带色码）喂客户端，出来的是干净的一句话
        CFG_PLAIN="$(printf '%s' "$CFG_SET_ERR" | "$CLIENT_BIN" --receipt-plain 2>/dev/null)"
        if [ -z "$CFG_PLAIN" ]; then
            echo "  ✗ 引擎配置端到端：客户端把真回执净化后空了（界面会什么都不显示）" >&2
            fail=$((fail+1))
        elif printf '%s' "$CFG_PLAIN" | grep -q 'backupKeep'; then
            echo "  ✓ 引擎配置端到端：客户端把真回执净化成干净的一句话（无 ANSI 残留）"
            pass=$((pass+1))
        else
            echo "  ✗ 引擎配置端到端：客户端净化后的回执内容不对：$CFG_PLAIN" >&2
            fail=$((fail+1))
        fi
    fi
fi

# 20. 持久化代码索引的状态（index overview / index update）。
#     ① **「已最新」≠「已更新」**：源文件没动时引擎回 fresh: true 且**不发 rebuilt 键**，
#        这次什么都没重建 —— 界面若说成「更新好了」就是骗人。
#     ② **`rebuilt` 是条件键**（fresh 时没有）—— 按 false 读会把「这次没重建」
#        说成「从来没重建过」（后者是历史事实）。
#     ③ 增量更新后 `indexJson` 落盘路径**必须真的存在**（否则「打开索引」是坏入口）。
IDXFIX="$SANDBOX/fixture/idxfix"
mkdir -p "$IDXFIX/src"
git -C "$IDXFIX" init -q -b main . 2>/dev/null
printf 'int compute(int n) {\n    return n * 2;\n}\nint main(void) { return compute(1); }\n' > "$IDXFIX/src/util.c"
git -C "$IDXFIX" add . 2>/dev/null
GIT_AUTHOR_DATE='2026-10-03T09:00:00' GIT_COMMITTER_DATE='2026-10-03T09:00:00' \
    git -C "$IDXFIX" commit -qm 'feat: 初始提交' 2>/dev/null
"$BIN" add "$IDXFIX" --json >/dev/null 2>&1
"$BIN" index gen idxfix --stats >/dev/null 2>&1

IDX_OVERVIEW="$("$BIN" index overview idxfix --json 2>/dev/null)"
if [ -z "$IDX_OVERVIEW" ]; then
    echo "  ✗ 第 20 组前提：引擎没吐出 index overview 载荷" >&2
    fail=$((fail+1))
else
    check "索引状态：概览键齐全（project/updateCount/generatedAt/selfHealed/nodes/edges/files/byKind/probe）" \
        "all(k in d for k in ['project','updateCount','generatedAt','selfHealed','nodes','edges','files','byKind','probe'])" \
        "$IDX_OVERVIEW"
    check "索引状态：nodes/edges/files 是**数字**（0 是合法值：空索引）" \
        "all(isinstance(d.get(k), int) for k in ['nodes','edges','files'])" \
        "$IDX_OVERVIEW"
    check "索引状态：探针三字段齐全（files/bytes/maxMtime）" \
        "all(k in d.get('probe',{}) for k in ['files','bytes','maxMtime'])" \
        "$IDX_OVERVIEW"
fi

# 已最新：fresh: true，且**引擎不发 rebuilt 键**
IDX_FRESH="$("$BIN" index update idxfix --json 2>/dev/null)"
if [ -z "$IDX_FRESH" ]; then
    echo "  ✗ 第 20 组前提：引擎没吐出 index update 载荷" >&2
    fail=$((fail+1))
else
    check "索引更新：源文件没动时 fresh 为真" \
        "d.get('fresh') is True" \
        "$IDX_FRESH"
    check "索引更新：**fresh 时引擎不发 rebuilt 键**（条件键，不是恒发的 false）" \
        "'rebuilt' not in d" \
        "$IDX_FRESH"
fi

# 改了文件 → fresh: false + rebuilt: true + indexJson 落盘路径
printf 'int compute(int n) {\n    return n * 3;\n}\nint extra(void) { return 7; }\nint main(void) { return compute(1); }\n' > "$IDXFIX/src/util.c"
IDX_REBUILT="$("$BIN" index update idxfix --json 2>/dev/null)"
if [ -z "$IDX_REBUILT" ]; then
    echo "  ✗ 第 20 组前提：引擎没吐出重建后的 index update 载荷" >&2
    fail=$((fail+1))
else
    check "索引更新：源文件变了 → fresh 假 / rebuilt 真" \
        "d.get('fresh') is False and d.get('rebuilt') is True" \
        "$IDX_REBUILT"
    check "索引更新：代数递增（updateCount ≥ 1）" \
        "d.get('updateCount', 0) >= 1" \
        "$IDX_REBUILT"
    if [ -n "$IDX_REBUILT" ]; then
        IDX_JSON_PATH="$(printf '%s' "$IDX_REBUILT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('indexJson', ''))
" 2>/dev/null)"
        if [ -z "$IDX_JSON_PATH" ]; then
            echo "  ✗ 索引更新：重建后没给 indexJson 落盘路径" >&2; fail=$((fail+1))
        elif [ -f "$IDX_JSON_PATH" ]; then
            echo "  ✓ 索引更新：重建后的 indexJson 落盘路径真实存在"
            pass=$((pass+1))
        else
            echo "  ✗ 索引更新：重建后的 indexJson 落盘路径不存在（$IDX_JSON_PATH）" >&2
            fail=$((fail+1))
        fi
    fi
    # 端到端：客户端解析真概览
    if [ ! -x "$CLIENT_BIN" ]; then
        echo "  ‣ SKIP 第 20 组端到端：找不到客户端二进制 $CLIENT_BIN"
        echo "    ‣ 本条**未验证**，不算通过"
    else
        IDX_VERDICT="$(printf '%s' "$IDX_OVERVIEW" | "$CLIENT_BIN" --index-status-parse 2>/dev/null)"
        check "索引状态端到端：客户端对真概览解析出同一组值（代数/节点/边/文件/探针）" \
            "d.get('ok') is True and d.get('project') == 'idxfix' and d.get('updateCount') >= 0 and d.get('nodes') >= 0 and d.get('edges') >= 0 and d.get('files') >= 0 and d.get('probeFiles') >= 0" \
            "$IDX_VERDICT"
    fi
fi

# ── 第 21 组：引擎获取链（GitHub Releases 下载安装）──
# ⚠ 这组**不依赖引擎**（引擎在不在都该验）：验的是「引擎没装时用户唯一的出路」。
#   ① 本地端到端：file:// 打桩跑完整链（查发布信息→下载→校验→解压→落盘→探活）
#   ② 校验和不匹配 → **拒绝安装**（不落盘）
#   ③ 真 GitHub API：latest release 载荷能被判定层读懂（网络不通 → 显式 SKIP，不算通过）
if [ ! -x "$CLIENT_BIN" ]; then
    echo "  ‣ SKIP 第 21 组：找不到客户端二进制 $CLIENT_BIN"
    echo "    ‣ 本组**未验证**，不算通过"
else
    ENG_TMP="$(mktemp -d)"
    mkdir -p "$ENG_TMP/pkg/bin" "$ENG_TMP/pkg/runtime/lib"
    # ⚠ 夹具必须用**真实发布包的布局**（引擎 `scripts/package-release.sh` 的产物）：
    #   根部 = 启动器 `moongit`，真二进制在 `bin/moongit-cli`，仓颉运行库在
    #   `runtime/lib/`；启动器按**自身所在目录**去找后两样。
    #   ⚠ 原来这里只放了一个 `moongit-cli`（**虚构布局**）—— 夹具与生产者分叉，
    #     测过的路径真实资产根本走不到（真实包里根部没有 moongit-cli）。
    printf '#!/bin/sh\ncase "$1" in\n  version) echo "moongit 0.0.0-contract";;\n  *) echo "unknown";;\nesac\n' > "$ENG_TMP/pkg/bin/moongit-cli"
    chmod +x "$ENG_TMP/pkg/bin/moongit-cli"
    printf '#!/bin/sh\nROOT="$(dirname "$0")"\nexport LD_LIBRARY_PATH="$ROOT/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\nexec "$ROOT/bin/moongit-cli" "$@"\n' > "$ENG_TMP/pkg/moongit"
    chmod +x "$ENG_TMP/pkg/moongit"
    : > "$ENG_TMP/pkg/runtime/lib/.keep"
    tar czf "$ENG_TMP/engine.tar.gz" -C "$ENG_TMP/pkg" moongit bin runtime
    ENG_SHA="$(sha256sum "$ENG_TMP/engine.tar.gz" | cut -d' ' -f1)"
    ENG_SZ="$(wc -c < "$ENG_TMP/engine.tar.gz" | tr -d ' ')"
    cat > "$ENG_TMP/release.json" <<EOF
{"tag_name":"v0.0.0-contract","assets":[{"name":"moongit-v0.0.0-contract-linux-x64.tar.gz","browser_download_url":"file://$ENG_TMP/engine.tar.gz","digest":"sha256:$ENG_SHA","size":$ENG_SZ}]}
EOF
    ENG_OUT="$("$CLIENT_BIN" --engine-download "file://$ENG_TMP/release.json" --engine-download-dest "$ENG_TMP/dest" 2>/dev/null)"
    check "引擎获取：端到端跑通（下载→校验→解压→落盘→探活）" \
        "d.get('ok') is True and d.get('stage') == 'ok' and d.get('verified') is True and d.get('tag') == 'v0.0.0-contract'" \
        "$ENG_OUT"
    if [ -x "$ENG_TMP/dest/moongit" ]; then
        echo "  ✓ 引擎获取：落盘的引擎可执行且改名成 moongit"
        pass=$((pass+1))
    else
        echo "  ✗ 引擎获取：落盘的引擎不存在或不可执行（$ENG_TMP/dest/moongit）" >&2
        fail=$((fail+1))
    fi
    # ⚠ 整包落盘：真二进制与运行库**必须一起**跟过来 ——
    #   只拷启动器的话，装下来的引擎 exec 不到二进制 / 加载不到运行库 ⇒ 跑不起来。
    if [ -x "$ENG_TMP/dest/bin/moongit-cli" ] && [ -d "$ENG_TMP/dest/runtime/lib" ]; then
        echo "  ✓ 引擎获取：整包落盘（bin/ 与 runtime/ 跟着启动器一起过来了）"
        pass=$((pass+1))
    else
        echo "  ✗ 引擎获取：整包没落全（缺 bin/ 或 runtime/lib ⇒ 装下来的引擎跑不起来）" >&2
        fail=$((fail+1))
    fi
    # 校验和不匹配 → 必须拒绝，且**不落盘**（落了就是半个坏引擎在跑）
    sed 's/sha256:[0-9a-f]*/sha256:0000000000000000000000000000000000000000000000000000000000000000/' \
        "$ENG_TMP/release.json" > "$ENG_TMP/bad-digest.json"
    ENG_BAD="$("$CLIENT_BIN" --engine-download "file://$ENG_TMP/bad-digest.json" --engine-download-dest "$ENG_TMP/dest-bad" 2>/dev/null)"
    check "引擎获取：校验和不匹配 → 拒绝安装（stage=digestMismatch）" \
        "d.get('ok') is False and d.get('stage') == 'digestMismatch'" \
        "$ENG_BAD"
    if [ -e "$ENG_TMP/dest-bad/moongit" ]; then
        echo "  ✗ 引擎获取：校验和不匹配却落了盘（坏引擎会被当好的用）" >&2
        fail=$((fail+1))
    else
        echo "  ✓ 引擎获取：校验和不匹配时没有落盘"
        pass=$((pass+1))
    fi

    # ⚠⚠ **装坏包不许毁掉原来能用的引擎**（批 AF 修的真 bug）。
    #   原实现是「先删旧引擎 → 再解包 → 最后才探活」⇒ 装到跑不起来的包时，
    #   **原来能用的引擎被顶替成坏的**（实测：old 0.9.9 → boom），且没有备份、
    #   无法回滚 ⇒ 用户从「能用」掉到「有个跑不起来的引擎」。
    #   ⚠ v0.2.0 那个坏包（runtime/lib/ 是空的）上这是**真实发生过**的。
    #   现在的形状：解包 → **旁路目录** → 探活 → **通过了才切换**。
    #   ⇒ 失败路径压根不碰目标目录 ⇒ 旧引擎原封不动。
    ENG_OLD="$ENG_TMP/old"
    mkdir -p "$ENG_OLD/bin" "$ENG_OLD/runtime/lib"
    printf '#!/bin/sh\ncase "$1" in\n  version) echo "old 1.0.0";;\n  *) exit 0;;\nesac\n' > "$ENG_OLD/bin/moongit-cli"
    chmod +x "$ENG_OLD/bin/moongit-cli"
    printf '#!/bin/sh\nROOT="$(dirname "$0")"\nexport LD_LIBRARY_PATH="$ROOT/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\nexec "$ROOT/bin/moongit-cli" "$@"\n' > "$ENG_OLD/moongit"
    chmod +x "$ENG_OLD/moongit"
    : > "$ENG_OLD/runtime/lib/.keep"

    # 造一个**探活失败**的包（version 退出码非 0）
    mkdir -p "$ENG_TMP/badpkg/bin" "$ENG_TMP/badpkg/runtime/lib"
    printf '#!/bin/sh\ncase "$1" in\n  version) echo "boom" >&2; exit 3;;\n  *) exit 0;;\nesac\n' > "$ENG_TMP/badpkg/bin/moongit-cli"
    chmod +x "$ENG_TMP/badpkg/bin/moongit-cli"
    printf '#!/bin/sh\nROOT="$(dirname "$0")"\nexport LD_LIBRARY_PATH="$ROOT/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\nexec "$ROOT/bin/moongit-cli" "$@"\n' > "$ENG_TMP/badpkg/moongit"
    chmod +x "$ENG_TMP/badpkg/moongit"
    : > "$ENG_TMP/badpkg/runtime/lib/.keep"
    tar czf "$ENG_TMP/bad.tar.gz" -C "$ENG_TMP/badpkg" moongit bin runtime
    BAD_SHA="$(sha256sum "$ENG_TMP/bad.tar.gz" | cut -d' ' -f1)"
    BAD_SZ="$(wc -c < "$ENG_TMP/bad.tar.gz" | tr -d ' ')"
    cat > "$ENG_TMP/bad.json" <<EOF
{"tag_name":"v9.9.9-bad","assets":[{"name":"moongit-v9.9.9-bad-linux-x64.tar.gz","browser_download_url":"file://$ENG_TMP/bad.tar.gz","digest":"sha256:$BAD_SHA","size":$BAD_SZ}]}
EOF

    # ── 场景 A：已装 1.0.0，装一个探活失败的包 ⇒ 旧引擎必须**原样保留** ──
    ENG_KEEP="$ENG_TMP/dest-keep"
    cp -a "$ENG_OLD" "$ENG_KEEP"
    ENG_KEEPOUT="$("$CLIENT_BIN" --engine-download "file://$ENG_TMP/bad.json" --engine-download-dest "$ENG_KEEP" 2>/dev/null)"
    check "引擎获取：装坏包 ⇒ **旧引擎原样保留**（不许被顶替成坏的）" \
        "d.get('ok') is False and d.get('stage') == 'probeFailed' and d.get('keptPrevious') is True" \
        "$ENG_KEEPOUT"
    if [ -x "$ENG_KEEP/moongit" ] && [ "$("$ENG_KEEP/moongit" version 2>/dev/null)" = "old 1.0.0" ]; then
        echo "  ✓ 引擎获取：装坏包后旧引擎还在，且还是原来那个能跑的版本"
        pass=$((pass+1))
    else
        echo "  ✗ 引擎获取：装坏包把旧引擎毁掉/顶替了（现在输出：$("$ENG_KEEP/moongit" version 2>&1)）" >&2
        fail=$((fail+1))
    fi
    # 失败路径不许在目标目录旁边留下旁路/备份残留（残留会污染下一次的安装）
    if [ -e "$ENG_TMP/dest-keep.staging" ] || [ -e "$ENG_TMP/dest-keep.backup" ]; then
        echo "  ✗ 引擎获取：装坏包后留下旁路/备份残留（下次安装会踩到）" >&2
        fail=$((fail+1))
    else
        echo "  ✓ 引擎获取：装坏包后没有留下旁路/备份残留"
        pass=$((pass+1))
    fi

    # ── 场景 B：下载到的比已装的旧 ⇒ **拒绝降级**（不把能用的换成不能用的）──
    #   夹具包版本 = 0.0.0（release.json 那个），已装 = 1.0.0 ⇒ 0.0.0 < 1.0.0。
    ENG_DOWN="$ENG_TMP/dest-down"
    cp -a "$ENG_OLD" "$ENG_DOWN"
    ENG_DOWNOUT="$("$CLIENT_BIN" --engine-download "file://$ENG_TMP/release.json" --engine-download-dest "$ENG_DOWN" 2>/dev/null)"
    check "引擎获取：下载到的比已装的旧 ⇒ **拒绝降级**（已装的不动）" \
        "d.get('ok') is False and d.get('stage') == 'versionDowngrade' and d.get('keptPrevious') is True" \
        "$ENG_DOWNOUT"
    if [ "$("$ENG_DOWN/moongit" version 2>/dev/null)" = "old 1.0.0" ]; then
        echo "  ✓ 引擎获取：拒绝降级后旧引擎原样还在"
        pass=$((pass+1))
    else
        echo "  ✗ 引擎获取：拒绝降级却动了旧引擎" >&2
        fail=$((fail+1))
    fi

    # ── 场景 C：版本确实更高 ⇒ 升级成功（这才允许切过去）──
    mkdir -p "$ENG_TMP/newpkg/bin" "$ENG_TMP/newpkg/runtime/lib"
    printf '#!/bin/sh\ncase "$1" in\n  version) echo "moongit 2.0.0-contract";;\n  *) exit 0;;\nesac\n' > "$ENG_TMP/newpkg/bin/moongit-cli"
    chmod +x "$ENG_TMP/newpkg/bin/moongit-cli"
    printf '#!/bin/sh\nROOT="$(dirname "$0")"\nexport LD_LIBRARY_PATH="$ROOT/runtime/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\nexec "$ROOT/bin/moongit-cli" "$@"\n' > "$ENG_TMP/newpkg/moongit"
    chmod +x "$ENG_TMP/newpkg/moongit"
    : > "$ENG_TMP/newpkg/runtime/lib/.keep"
    tar czf "$ENG_TMP/new.tar.gz" -C "$ENG_TMP/newpkg" moongit bin runtime
    NEW_SHA="$(sha256sum "$ENG_TMP/new.tar.gz" | cut -d' ' -f1)"
    NEW_SZ="$(wc -c < "$ENG_TMP/new.tar.gz" | tr -d ' ')"
    cat > "$ENG_TMP/new.json" <<EOF
{"tag_name":"v2.0.0-contract","assets":[{"name":"moongit-v2.0.0-contract-linux-x64.tar.gz","browser_download_url":"file://$ENG_TMP/new.tar.gz","digest":"sha256:$NEW_SHA","size":$NEW_SZ}]}
EOF
    ENG_UP="$ENG_TMP/dest-up"
    cp -a "$ENG_OLD" "$ENG_UP"
    ENG_UPOUT="$("$CLIENT_BIN" --engine-download "file://$ENG_TMP/new.json" --engine-download-dest "$ENG_UP" 2>/dev/null)"
    check "引擎获取：版本确实更高 ⇒ 升级成功（切到新版本）" \
        "d.get('ok') is True and d.get('stage') == 'ok' and d.get('installedVersion') == '2.0.0'" \
        "$ENG_UPOUT"
    if [ "$("$ENG_UP/moongit" version 2>/dev/null)" = "moongit 2.0.0-contract" ]; then
        echo "  ✓ 引擎获取：升级后跑的是新版本"
        pass=$((pass+1))
    else
        echo "  ✗ 引擎获取：升级后还是旧版本（现在输出：$("$ENG_UP/moongit" version 2>&1)）" >&2
        fail=$((fail+1))
    fi
    # ⚠ **网络瞬断 ⇒ 客户端要重试**（行为门）。
    #   依据：2026-10-20 实测，本机第一次下载引擎 release 直接「下载中断：Connection closed」，
    #   稍后重试同一个 URL 1.17 秒下完 ⇒ 一次抖动不该让用户手动再点一次。
    #   打桩：本地 HTTP 服务器，**前 N 次请求直接断开连接**（不发响应 ⇒ 客户端看到
    #   RemoteHostClosedError），第 N+1 次才正常返回。
    #   ⚠ release.json 由服务器**自己生成**（端口是运行时才定的 ⇒ 预置的 JSON 里写不对 URL）。
    if command -v python3 >/dev/null 2>&1; then
        cat > "$ENG_TMP/fuzzy_server.py" <<'PYEOF'
import hashlib, http.server, json, os, socket, socketserver, sys

ROOT = sys.argv[1]
PORTFILE = sys.argv[2]
FAILS = int(sys.argv[3])
state = {"n": 0}


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, name, ctype):
        body = open(os.path.join(ROOT, name), "rb").read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/engine.tar.gz":
            state["n"] += 1
            if state["n"] <= FAILS:
                # 直接断开：不发任何响应 ⇒ 客户端看到「Connection closed」
                self.close_connection = True
                try:
                    self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                self.connection.close()
                return
            self._send("engine.tar.gz", "application/gzip")
        elif self.path == "/release.json":
            tar = open(os.path.join(ROOT, "engine.tar.gz"), "rb").read()
            payload = {
                "tag_name": "v0.0.0-retry",
                "assets": [{
                    "name": "moongit-v0.0.0-retry-linux-x64.tar.gz",
                    "browser_download_url": "http://127.0.0.1:%d/engine.tar.gz" % PORT,
                    "digest": "sha256:" + hashlib.sha256(tar).hexdigest(),
                    "size": len(tar),
                }],
            }
            body = json.dumps(payload).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()

    def log_message(self, *args):
        pass


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", 0), H) as httpd:
    PORT = httpd.server_address[1]
    with open(PORTFILE, "w") as f:
        f.write(str(PORT))
    httpd.serve_forever()
PYEOF
        # ── 场景 1：断连 2 次（少于重试上限）⇒ 必须重试成功 ──
        python3 "$ENG_TMP/fuzzy_server.py" "$ENG_TMP" "$ENG_TMP/port" 2 >/dev/null 2>&1 &
        SRV_PID=$!
        i=0
        while [ ! -s "$ENG_TMP/port" ] && [ "$i" -lt 60 ]; do sleep 0.1; i=$((i+1)); done
        PORT="$(cat "$ENG_TMP/port" 2>/dev/null || true)"
        if [ -n "$PORT" ]; then
            ENG_RETRY="$("$CLIENT_BIN" --engine-download "http://127.0.0.1:$PORT/release.json" --engine-download-dest "$ENG_TMP/dest-retry" 2>/dev/null)"
            check "引擎获取：网络瞬断（连断 2 次）⇒ 重试后**仍装成功**（不是一次失败就放弃）" \
                "d.get('ok') is True and d.get('stage') == 'ok' and d.get('verified') is True" \
                "$ENG_RETRY"
            if [ -x "$ENG_TMP/dest-retry/moongit" ]; then
                echo "  ✓ 引擎获取：重试后落盘的引擎可执行"
                pass=$((pass+1))
            else
                echo "  ✗ 引擎获取：重试后落盘的引擎不存在或不可执行" >&2
                fail=$((fail+1))
            fi
        else
            echo "  ‣ SKIP 第 21 组之重试场景：打桩服务器没起来（本项**未验证**，不算通过）"
        fi
        kill "$SRV_PID" 2>/dev/null
        wait "$SRV_PID" 2>/dev/null
        rm -f "$ENG_TMP/port"

        # ── 场景 2：断连次数超过上限 ⇒ 必须**最终失败**（不是无限重试）──
        python3 "$ENG_TMP/fuzzy_server.py" "$ENG_TMP" "$ENG_TMP/port2" 9 >/dev/null 2>&1 &
        SRV_PID2=$!
        i=0
        while [ ! -s "$ENG_TMP/port2" ] && [ "$i" -lt 60 ]; do sleep 0.1; i=$((i+1)); done
        PORT2="$(cat "$ENG_TMP/port2" 2>/dev/null || true)"
        if [ -n "$PORT2" ]; then
            ENG_DEAD="$("$CLIENT_BIN" --engine-download "http://127.0.0.1:$PORT2/release.json" --engine-download-dest "$ENG_TMP/dest-dead" 2>/dev/null)"
            check "引擎获取：一直断连 ⇒ 到上限后**最终失败**（不是无限重试）" \
                "d.get('ok') is False and d.get('stage') == 'downloadFailed'" \
                "$ENG_DEAD"
        else
            echo "  ‣ SKIP 第 21 组之重试上限场景：打桩服务器没起来（本项**未验证**，不算通过）"
        fi
        kill "$SRV_PID2" 2>/dev/null
        wait "$SRV_PID2" 2>/dev/null
    else
        echo "  ‣ SKIP 第 21 组之重试场景：没有 python3（本项**未验证**，不算通过）"
    fi

    # 本平台没有资产 → 必须说清「有什么」，而不是笼统失败
    cat > "$ENG_TMP/darwin-only.json" <<EOF
{"tag_name":"v0.1.0","assets":[{"name":"moongit-v0.1.0-darwin-arm64.tar.gz","browser_download_url":"file://$ENG_TMP/engine.tar.gz","digest":"sha256:$ENG_SHA","size":$ENG_SZ}]}
EOF
    ENG_NOASSET="$("$CLIENT_BIN" --engine-download "file://$ENG_TMP/darwin-only.json" --engine-download-dest "$ENG_TMP/dest-na" 2>/dev/null)"
    check "引擎获取：本平台没资产 → 说清是哪一种（stage=noPlatformAsset）" \
        "d.get('ok') is False and d.get('stage') == 'noPlatformAsset' and 'darwin' in d.get('message','')" \
        "$ENG_NOASSET"
    # 真 GitHub API：latest release 载荷能被判定层读懂
    if command -v curl >/dev/null 2>&1; then
        ENG_API="$(curl -fsSL --max-time 25 https://api.github.com/repos/asdshuaishuai/moongit/releases/latest 2>/dev/null)"
        if [ -z "$ENG_API" ]; then
            echo "  ‣ SKIP 第 21 组真 API 那条：GitHub API 不可达（网络问题）"
            echo "    ‣ 本条**未验证**，不算通过"
        else
            ENG_PARSED="$(printf '%s' "$ENG_API" | "$CLIENT_BIN" --engine-release-parse 2>/dev/null)"
            check "引擎获取：真 GitHub API 的 latest release 能被判定层读懂（tag + 资产清单）" \
                "d.get('parsed') is True and d.get('tag') != '' and len(d.get('available', [])) > 0" \
                "$ENG_PARSED"
            # 若本次 release 恰好有 Linux 资产 → 它的下载地址与校验和必须合法
            check "引擎获取：真 API 的资产条目字段合法（有则 url 是 https、digest 非空）" \
                "d.get('hasAsset') is False or (d.get('assetUrl','').startswith('https://') and d.get('hasDigest') is True)" \
                "$ENG_PARSED"
        fi
    else
        echo "  ‣ SKIP 第 21 组真 API 那条：没有 curl"
        echo "    ‣ 本条**未验证**，不算通过"
    fi
    rm -rf "$ENG_TMP"
fi

# ── 第 22 组：引擎钩子（post-commit / post-merge 托管块）──
# ⚠ 这组验的是**两件安全的事**（客户端敢提供「装/卸」按钮的前提）：
#   ① 装上后，用户**原有的钩子内容不被覆盖**（托管块在前，用户内容追加在后）；
#   ② 卸载时**只删托管块**，用户自己的逻辑原样留着。
#   这两条一旦不成立，客户端的「卸载」按钮就是**删用户数据**。
if [ ! -x "$CLIENT_BIN" ]; then
    echo "  ‣ SKIP 第 22 组：找不到客户端二进制 $CLIENT_BIN"
    echo "    ‣ 本组**未验证**，不算通过"
else
    HOOK_REPO="$SANDBOX/hooked"
    mkdir -p "$HOOK_REPO/src"
    git -C "$HOOK_REPO" init -q -b main . 2>/dev/null
    printf 'int main(void){return 0;}\n' > "$HOOK_REPO/src/main.c"
    git -C "$HOOK_REPO" add . 2>/dev/null
    GIT_AUTHOR_DATE='2026-10-03T09:00:00' GIT_COMMITTER_DATE='2026-10-03T09:00:00' \
        git -C "$HOOK_REPO" commit -qm 'feat: 初始提交' 2>/dev/null
    "$BIN" add "$HOOK_REPO" --name hooked >/dev/null 2>&1
    # 用户自己的钩子逻辑（必须在装/卸全程存活）
    printf '#!/bin/sh\n# 用户自己的逻辑\ntrue\n' > "$HOOK_REPO/.git/hooks/post-commit"
    chmod +x "$HOOK_REPO/.git/hooks/post-commit"
    "$BIN" hook install hooked >/dev/null 2>&1
    HOOK_STATUS_JSON="$("$BIN" hook status hooked --json 2>/dev/null)"
    check "引擎钩子：装上后 post-commit / post-merge 都报已安装（installed 数组前两位）" \
        "d.get('project') == 'hooked' and len(d.get('installed', [])) >= 2 and d.get('installed')[0] is True and d.get('installed')[1] is True" \
        "$HOOK_STATUS_JSON"
    check "引擎钩子：状态载荷带钩子日志路径" \
        "d.get('log', '') != ''" \
        "$HOOK_STATUS_JSON"
    # 客户端判定层对**真载荷**的解读
    HOOK_VERDICT="$(printf '%s' "$HOOK_STATUS_JSON" | "$CLIENT_BIN" --hook-status-parse 2>/dev/null)"
    check "引擎钩子端到端：客户端把真载荷读成「两个都装了」" \
        "d.get('parsed') is True and d.get('installedPresent') is True and d.get('postCommit') is True and d.get('postMerge') is True and d.get('count') == 2" \
        "$HOOK_VERDICT"
    # ⚠ 安全断言 ①：用户原有的钩子内容**没被覆盖**
    if grep -q "用户自己的逻辑" "$HOOK_REPO/.git/hooks/post-commit" 2>/dev/null; then
        echo "  ✓ 引擎钩子：装上后用户原有的钩子逻辑仍在（托管块追加而非覆盖）"
        pass=$((pass+1))
    else
        echo "  ✗ 引擎钩子：装上后用户原有的钩子逻辑被覆盖了" >&2
        fail=$((fail+1))
    fi
    "$BIN" hook uninstall hooked >/dev/null 2>&1
    HOOK_STATUS_JSON2="$("$BIN" hook status hooked --json 2>/dev/null)"
    check "引擎钩子：卸载后两个钩子都报未安装" \
        "len(d.get('installed', [])) >= 2 and d.get('installed')[0] is False and d.get('installed')[1] is False" \
        "$HOOK_STATUS_JSON2"
    # ⚠ 安全断言 ②：卸载**只删托管块**，用户逻辑原样留着
    if grep -q "用户自己的逻辑" "$HOOK_REPO/.git/hooks/post-commit" 2>/dev/null; then
        echo "  ✓ 引擎钩子：卸载后用户原有的钩子逻辑仍在（只删托管块）"
        pass=$((pass+1))
    else
        echo "  ✗ 引擎钩子：卸载把用户自己的钩子逻辑也删了" >&2
        fail=$((fail+1))
    fi
fi

echo "──── contract-check: $pass passed, $fail failed ────"
[ "$fail" -eq 0 ]