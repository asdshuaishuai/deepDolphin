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
mkdir -p "$FIX"
git -C "$FIX" init -q -b main . 2>/dev/null
printf '# atlas\n\nUSER-SENTINEL 用户手写内容不许动\n' > "$FIX/README.md"
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

echo "──── contract-check: $pass passed, $fail failed ────"
[ "$fail" -eq 0 ]
