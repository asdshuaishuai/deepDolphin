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
printf 'int main(void) { return 0; }\n' > "$FIX/src/main.c"
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

echo "──── contract-check: $pass passed, $fail failed ────"
[ "$fail" -eq 0 ]