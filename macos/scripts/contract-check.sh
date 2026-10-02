#!/bin/bash
# contract-check.sh — 客户端 ↔ 引擎契约检查。
#
# 【为什么要有它】
# P0-1 是这样漏到线上的：`AIClient.status(name:)` 按裸 ProjectStatus 解码，
# 而引擎 CLI 恒返回 envelope —— 100% 必现的解码失败，详情面板每次打开都崩。
# 那种缺陷人工审计和代码评审都挡不住（两边各自「看起来」都合理）。
# 能挡住它的只有一件事：**拿引擎的真实输出喂客户端的真实模型**。
#
# 【关键点】编译的是 Sources/deepDolphin/Models.swift 本体，不是测试里的副本 ——
# 副本会与源文件漂移，测了等于没测。
#
# 【跑法】scripts/contract-check.sh
# 需要：swiftc（Xcode CLT）、一个可执行的 deepgit 引擎二进制。

set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS="$PKG_DIR/Sources/deepDolphin/Models.swift"
# Models.swift 的 commitTypeLine 走这个零依赖纯函数，编译时必须一起带上
# （漏了就是「符号找不到」，与模型写错症状相似但原因完全不同）。
CTCOMP="$PKG_DIR/Sources/deepDolphin/CommitTypeComposition.swift"
MSCARD="$PKG_DIR/Sources/deepDolphin/MilestoneCard.swift"
UPOUT="$PKG_DIR/Sources/deepDolphin/UpdateOutcome.swift"
CHECKER="$PKG_DIR/Tests/ContractCheck/main.swift"

# ---- 定位引擎二进制 -------------------------------------------------------
# ⚠️ 路径必须数对层数：PKG_DIR 是 <repo>/deepDolphin/macos，
#    引擎在 <repo>/moonGit —— 要上溯**两**层。层数错了会落到不存在的目录，
#    然后静默回退到 ~/.local/bin/moongit（过期安装版），
#    于是契约检查会拿旧引擎的输出对新模型，报出一堆假失败 ——
#    症状与「模型写错了」几乎一样，极难分辨。
#    本项目已因此栽过两次：一次层数错（journal 顶层被报成「不是 object」——
#    旧引擎返回裸数组、projects 缺 listed、错误桩缺 commitCount），
#    一次是引擎仓改名 moonGit/ → moonGit/。
find_engine() {
  if [[ -n "${DEEPGIT_BIN:-}" && -x "$DEEPGIT_BIN" ]]; then echo "$DEEPGIT_BIN"; return; fi
  local repo_engine="$PKG_DIR/../../moonGit/target/release/bin/main"
  if [[ -x "$repo_engine" ]]; then echo "$repo_engine"; return; fi
  # 退而求其次：已安装的。本地开发时应总是命中上面那条。
  for p in "$HOME/.local/bin/moongit" "$HOME/.local/bin/deepgit" \
           /usr/local/bin/moongit /opt/homebrew/bin/moongit; do
    [[ -x "$p" ]] && { echo "$p"; return; }
  done
  echo ""
}

ENGINE="$(find_engine)"
if [[ -z "$ENGINE" ]]; then
  echo "✗ 找不到 deepgit 引擎二进制。" >&2
  echo "  请先构建：cd moonGit && cjpm build" >&2
  echo "  或设置 DEEPGIT_BIN=/path/to/deepgit" >&2
  exit 2
fi
# 用的是不是仓内那个？回退到已安装版要提醒 —— 它可能是过期的，
# 那样报出来的失败反映的是引擎版本而不是模型对错。
case "$ENGINE" in
  *"/moonGit/target/"*) ;;
  *) echo "⚠ 用的是已安装的引擎（${ENGINE}），不是仓内 release。" >&2
     echo "  已安装版可能过期，失败未必是模型的问题。建议先 cd moonGit && cjpm build" >&2 ;;
esac
echo "引擎：$ENGINE"

# ---- 沙箱 -----------------------------------------------------------------
# 必须放在被测 git 仓库之外，且 DEEPGIT_HOME 独立 —— 绝不能碰用户真实数据。
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/dg-contract-XXXXXX")"
HOME_DIR="$SANDBOX/home"
REPO_OK="$SANDBOX/ok"
REPO_BAD="$SANDBOX/bad"
REPO_DOOMED="$SANDBOX/doomed"
FIXTURES="$SANDBOX/fixtures"
mkdir -p "$HOME_DIR" "$FIXTURES"

cleanup() {
  if command -v mavis-trash >/dev/null 2>&1; then
    mavis-trash -- "$SANDBOX" >/dev/null 2>&1
  else
    rm -rf "$SANDBOX"
  fi
}
trap cleanup EXIT

# mavis-trash 本身会往 stdout 打 "moved to trash"，混进检查输出里像故障。
# 这里包一层静默封装。
remove_path() {
  if command -v mavis-trash >/dev/null 2>&1; then
    mavis-trash -- "$1" >/dev/null 2>&1
  else
    rm -rf "$1"
  fi
}

export DEEPGIT_HOME="$HOME_DIR"
export NO_COLOR=1

mkgit() {  # mkgit <dir> <ncommits>
  mkdir -p "$1"
  (
    cd "$1" || exit 1
    git init -q -b main >/dev/null 2>&1
    git config user.name t >/dev/null 2>&1
    git config user.email t@t >/dev/null 2>&1
    for i in $(seq 1 "${2:-1}"); do
      echo "c$i" > "f$i.txt"
      git add . >/dev/null 2>&1
      git commit -q -m "c$i" >/dev/null 2>&1
    done
  )
}

# ---- 造场景 ---------------------------------------------------------------
mkgit "$REPO_OK" 3
mkgit "$REPO_DOOMED" 2

# 坏项目：路径存在时正常，删掉后采集必失败（错误桩）
mkgit "$REPO_BAD" 1

# 依赖清单样本：Phase 3 给 ProjectStatus 加了 `manifests`，
# 而**没有**依赖清单的仓库恒发 `manifests: []` —— 空数组解不出元素类型，
# 于是「它是字符串数组还是对象数组」这条判据永远是空跑。
# `overall` 就是这么栽的：照想象写成 {summary, notes}，而错误桩发的是 {}。
# 造一个真的带 package.json 的仓库，这条才跑得到。
printf '{\n  "name": "ok",\n  "version": "1.0.0"\n}\n' > "$REPO_OK/package.json"

# 提交类型条数上界样本（缺陷 #206）：
# 15 个提交、15 种不同类型（含 4 种旧分类法遗留名）⇒ 引擎会把它们聚成
# 12 类（11 个已知 + other 桶），也就是 commitTypes 的**条数**上界。
# 客户端色板容量必须容得下这个数，否则分段条上会把两类涂成同一个颜色。
REPO_TYPES="$SANDBOX/types"
mkdir -p "$REPO_TYPES"
(
  cd "$REPO_TYPES" || exit 1
  git init -q -b main >/dev/null 2>&1
  git config user.name t >/dev/null 2>&1
  git config user.email t@t >/dev/null 2>&1
  for t in feat fix perf refactor docs test build ci style chore revert wip temp misc zzz; do
    echo "$t" > "$t.txt"
    git add . >/dev/null 2>&1
    git commit -q -m "$t: n" >/dev/null 2>&1
  done
)

# 降级项目：路径存在但**不是 git 仓库** ⇒ milestoneProgress 判 gitReadable=false。
# 它存在的唯一理由是钉死一条不变量：**里程碑条目的键集不得随数据变化**。
# 本脚本抓出来的真实缺陷就是这个 —— unverifiedReason 只在 git 读不出来时发，
# 于是健康态 CLI 17 键 / 降级态 CLI 18 键 / 降级态 dashboard 17 键，
# 消费方看「有没有这个键」就知道出了故障，却没有任何文档说明这层耦合。
REPO_PLAIN="$SANDBOX/plain"
mkdir -p "$REPO_PLAIN"

# 待记录徽章的样本仓库（见下面 collect status_pending 处的说明）
REPO_PENDING="$SANDBOX/pending"
mkdir -p "$REPO_PENDING"
(
  cd "$REPO_PENDING" || exit 1
  git init -q -b main >/dev/null 2>&1
  git config user.name t >/dev/null 2>&1
  git config user.email t@t >/dev/null 2>&1
  echo base > p.txt
  git add . >/dev/null 2>&1
  git commit -q -m "feat: 基线" >/dev/null 2>&1
)

# 陈旧样本仓库（`status_all` fixture 里用来验时间窗真的在筛）
#
# ⚠️ 造它是因为判据「时间窗真的改变项目集合」曾经在数据上**空转**：
# 那时 status fixture 只含 `ok`（一个当天提交的项目），于是
# 「近 7 天」和「全量」收下同样多的项目 —— 而判据里写着
# 「沙箱里项目可能全都新鲜，那就分不出来」并主动 return 通过。
# 更糟的是这些仓库都没有远端，`branches` 追踪数组**恒为空**，
# 于是旧实现（拿 `primaryBranch?.staleDays` 判定）对每个项目都走
# 「没有分支记录 → 保留」，控件在任何数据下都是死的，而判据全绿。
#
# 所以这个仓库要同时满足两个条件，缺一个这条判据就又是空话：
#   1. 最后提交在 40 天前        → 窗口必须把它分出去
#   2. 没有远端、branches 为空   → 复现真形状（追踪数组拿不到）
STALE_DATE="$(date -v-47d '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -d '47 days ago' '+%Y-%m-%dT%H:%M:%S%z')"
REPO_STALE="$SANDBOX/stale"
mkdir -p "$REPO_STALE"
(
  cd "$REPO_STALE" || exit 1
  git init -q -b main >/dev/null 2>&1
  git config user.name t >/dev/null 2>&1
  git config user.email t@t >/dev/null 2>&1
  echo old > o.txt
  git add . >/dev/null 2>&1
  # ⚠️ 必须同时改 AUTHOR 与 COMMITTER：引擎读的 `lastCommitAt` 取自提交者时间，
  # 只改一个的话 log 里显示 47 天前而 JSON 里仍是今天（判据反而会绿）。
  GIT_AUTHOR_DATE="$STALE_DATE" GIT_COMMITTER_DATE="$STALE_DATE" \
    git commit -q -m "chore: 很久以前的提交" >/dev/null 2>&1
)

"$ENGINE" add "$REPO_OK" --name ok >/dev/null 2>&1
"$ENGINE" add "$REPO_BAD" --name bad >/dev/null 2>&1
"$ENGINE" add "$REPO_PLAIN" --name plain >/dev/null 2>&1
"$ENGINE" add "$REPO_TYPES" --name types >/dev/null 2>&1
"$ENGINE" add "$REPO_STALE" --name stale >/dev/null 2>&1

# ── 有远端的样本仓库（2026-10-02 新增）────────────────────────────────
# 上面几个仓库**都没有远端**，于是 `branches` 追踪数组**恒为空** ——
# 后果是「客户端的『可合入分支』判据 == 引擎的 `work.mergeCandidates`」
# 这条交叉验证会 0 == 0 空转着变绿，而客户端当时的判据恰恰是错的。
#
# ⚠️ 空转是这类判据最常见的死法：断言写对了，数据让它失去意义。
#    所以这里要造出**旧判据判错、新判据判对**的那一份数据：
#      远端 + 一个领先 main 的非默认分支 + 已经跑过 update
#    ⇒ aheadOfDefault = 1（领先）
#    ⇒ pendingCommits = 0（刚跑过 update，快照已归零）
#    ⇒ isDefault = false / merged = false
#    引擎 `work.mergeCandidates` = 1；
#    而旧判据 `pendingCommits > 0 && !isDefault` 判出 0 —— 差 1，判据真的会红。
REPO_REMOTE="$SANDBOX/remote.git"
REPO_MERGE="$SANDBOX/mergeable"
git init -q --bare "$REPO_REMOTE" >/dev/null 2>&1
git clone -q "$REPO_REMOTE" "$REPO_MERGE" >/dev/null 2>&1
(
  cd "$REPO_MERGE" || exit 1
  git config user.name t >/dev/null 2>&1
  git config user.email t@t >/dev/null 2>&1
  git checkout -q -b main >/dev/null 2>&1
  echo base > a.txt
  git add . >/dev/null 2>&1
  git commit -q -m "feat: 基线" >/dev/null 2>&1
  git push -q -u origin main >/dev/null 2>&1

  # 分支一：**已合入**（从 main 拉出 → 合回 main）。
  # 它的作用是让 `merged` 键在样本里**真的出现过 true** ——
  # 契约里「这个键解得出来吗」原本是空跑的：沙箱所有分支 merged 全是 false，
  # 于是「let merged: Bool = false（永不解码）」这个写法也能蒙对。
  #
  # ⚠️ 必须**从 main 拉出**。第一版把它从 feature/ahead 拉出，
  #    合回 main 时把 ahead 的提交也带上了 → ahead 变成 0 且 merged 变成 true，
  #    整个样本退化。第二版改成「不推 main」想造 merged && ahead 同时成立，
  #    实测 aheadOfDefault 也是比本地默认分支算的，ahead 仍是 0 ——
  #    引擎的 merged 与 aheadOfDefault 在真实数据里互斥，造不出来。
  #    这条局限写进了 ContractCheck 第 17 组的注释里，不假装它是更强的保证。
  git checkout -q -b feature/done
  echo done > b.txt
  git add . >/dev/null 2>&1
  git commit -q -m "feat: 已合入的改动" >/dev/null 2>&1
  git push -q -u origin feature/done >/dev/null 2>&1
  git checkout -q main >/dev/null 2>&1
  git merge -q --no-ff feature/done -m "merge: feature/done" >/dev/null 2>&1
  git push -q origin main >/dev/null 2>&1

  # 分支二：**待合入**（从 main 拉出，不合并），然后切回 main。
  # 留在 feature 上会让它成为当前分支、形态与真 app 不同；
  # 切回 main 才对应「我站在主干上、手下有活没合」。
  git checkout -q -b feature/ahead
  echo more >> a.txt
  git add . >/dev/null 2>&1
  git commit -q -m "feat: 待合入的改动" >/dev/null 2>&1
  git push -q -u origin feature/ahead >/dev/null 2>&1
  git checkout -q main >/dev/null 2>&1
)
"$ENGINE" add "$REPO_MERGE" --name mergeable >/dev/null 2>&1
# ⚠️ 必须跑 update：pendingCommits 只在「跑过 update」之后才归零。
#    不跑的话待合入那条分支 pendingCommits > 0，旧判据也判对 —— 交叉验证又空转了。
"$ENGINE" update mergeable --quiet >/dev/null 2>&1

# ⚠️ 必须先给仓库补一个提交再跑第二次 update：连续两次 update 之间
# 什么都不变的话，引擎会判定「无变化」（它有「去时间戳后内容等价则不刷新」的设计），
# 于是这份 fixture 里**根本没有「改动 + 备份」那一档**。
# 第一版就这么写的，结果两条断言报「样本里没有改动过的既有文档」。
# 顺带一提：无变化那一档本身也是个真实形状（客户端必须照实说「没有变化」）。
(
  cd "$REPO_OK" || exit 1
  echo "trigger-doc-change" > trigger.txt
  git add . >/dev/null 2>&1
  git -c user.name=t -c user.email=t@t commit -q -m "feat: trigger doc change" >/dev/null 2>&1
)
# ⚠️ 这里**不要**再显式跑一次 update：fixture 是用 `collect update_one` 采集的，
# 而 collect 自己就要跑一次 `update ok`。多跑一次，内容在采集前就被写掉了，
# 于是采到的是第三次 update —— 引擎判「无变化」，样本里根本没有备份那一档
# （第一版就这么栽的，报错是「样本里没有改动过的既有文档」）。
"$ENGINE" milestone add ok "正常里程碑" --date 2027-06-01 >/dev/null 2>&1
"$ENGINE" milestone add plain "降级里程碑" >/dev/null 2>&1

# 让 ok 项目有一条 tag 绑定但 tag 不存在的里程碑，便于断言 tagName
"$ENGINE" milestone add ok "带tag里程碑" --tag v9.9-不存在 >/dev/null 2>&1

# 里程碑凑到 8 条（缺陷 #207）：仪表盘卡片只画 5 条，而标题按 counts 全量说话。
# 8 > 5 是**故意的** —— 少于 5 条时那处 prefix 是空操作，测它等于没测。
for i in 1 2 3 4 5 6; do
  "$ENGINE" milestone add ok "补足里程碑 $i" >/dev/null 2>&1
done

# ⚠️ 再跑一次 update（缺陷 #210）：第一次是**新建**文档（created=true、
# backup="" —— 本来就没有旧版本可备份），只有第二次改动才会留下真实的备份路径。
# 两种形状都要收：新键恒发，空串与真路径各是一份真实数据。
"$ENGINE" update ok --quiet >/dev/null 2>&1

collect() {  # collect <fixture名> <引擎参数...>
  local name="$1"; shift
  "$ENGINE" "$@" > "$FIXTURES/$name.json" 2>/dev/null || true
  if [[ ! -s "$FIXTURES/$name.json" ]]; then
    echo "  ⚠ fixture '$name' 为空（引擎命令失败：$*）" >&2
  fi
}

# ⚠️ 顺序要紧：这些 fixture 必须在删路径**之前**收。
# git 那条尤其敏感 —— 路径失效后引擎返回 ok=false，测的就不是正常形状了。
collect status        status ok --json --quiet
# 全量项目清单：时间窗类判据必须用它，不能用上面那份只含 `ok` 的。
# 单项目 fixture 里「新旧对比」根本不存在，判据只能空转。
collect status_all    status --json --quiet
# 待记录徽章的数据源样本（#213）：
# pendingCommits 以前**恒为 0** —— status 读的是进度库里存的快照，
# 而那个快照在 update 算完后立刻归零（flow/update.cj:591），
# 于是顶栏那个徽章永远不亮。引擎改成实时算之后需要一个**非 0** 的样本
# 才能证明这件事真的发生了；只在刚跑完 update 的项目上验，
# 验到的永远是 0，等于什么都没验。
"$ENGINE" add "$REPO_PENDING" --name pending >/dev/null 2>&1
"$ENGINE" update pending --quiet >/dev/null 2>&1
# 关键：**不再**跑 update，只提交
for i in 1 2 3; do
  echo "pending $i" >> "$REPO_PENDING/p.txt"
  ( cd "$REPO_PENDING" && git add -A && git commit -q -m "feat: 未记录的提交 $i" )
done
collect status_pending status pending --json --quiet

# 非 git 项目的单独 fixture。
# 「status」那份只含 ok（一个 git 项目），于是 warnings 的断言拿不到
# 「非 git」这个真正要紧的样本 —— 写「遍历所有项目，非 git 就断言」的检查
# 会一路空转着变绿。必须**点名**能拿到那个样本。
collect status_plain status plain --json --quiet
collect status_types status types --json --quiet
collect milestones    milestone list --json
collect docs          docs ok --json
collect dashboard     dashboard --json
collect journal       journal ok --json
collect update_one    update ok --json --quiet
collect update_all    update --json --quiet
# 工具清单：客户端的 executeTool 是一份**手写 switch**，
# 与引擎这里的声明是同一份清单的两处副本。两份一旦漂移，
# 表现是「模型调了一个客户端不会执行的工具」——
# 而那在界面上只显示一句「未知工具：X」，很容易被当成模型乱调。
collect tools         tools --json
collect git           git status ok --json
collect milestones_deg milestone list --json
collect dashboard_deg  dashboard --json

# ---- MCP 出口（第三套：stdio JSON-RPC，给 AI 工具循环用）-------------------
# ⚠️ MCP 的形状与 CLI **刻意不同**，别当成 bug 去"统一"：
#   get_project_status → 裸 ProjectStatus（单项目语义，无需剥 envelope，省 token）
#   list_milestones    → {counts, items}（counts 里 9 个披露字段一个不缺）
# 这两条由检查程序第 10 组钉住：改形状会立刻红。
#
# ⚠️⚠️ 必须在删路径**之前**收（这是本脚本第二次栽在这上面）：
# MCP 的 get_project_status 要真读 git 仓库，路径一旦失效它返回的是
# 「路径不存在或卷未挂载：…」那段错误文案而不是 JSON ——
# 症状是「ProjectStatus 解码失败：Data was corrupted / Unexpected character 'è'」，
# 与「模型写错了」几乎无法分辨。同 CLI 那批 fixture。
collect_mcp() {  # collect_mcp <fixture名> <工具名> <参数JSON>
  local name="$1" tool="$2" args="$3"
  printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":%s}}' \
    "$tool" "$args" | "$ENGINE" mcp > "$FIXTURES/$name.json" 2>/dev/null || true
}

# ---- MCP 的工具注册表（tools/list）：第三份副本 ---------------------------
# ⚠️ 缺陷 #192：CLI `tools --json`（10 个）与 MCP `tools/list`（15 个）
# **几乎完全不相交**，重叠只有 6 个。这两份从来没被钉在一起过，
# 所以漂移是静默的。这里把 tools/list 也收下来，交给检查程序比对。
printf '%s\n%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | "$ENGINE" mcp 2>/dev/null | tail -1 > "$FIXTURES/mcp_tools_list.json" || true

collect_mcp mcp_status     get_project_status '{"name":"ok"}'
collect_mcp mcp_milestones list_milestones    '{}'
collect_mcp mcp_dashboard  get_dashboard      '{}'

# --- 场景 2：采集失败项目（-1 三态）---
# 删掉 bad 项目的路径，但保留它在注册表里
remove_path "$REPO_BAD"
collect status_error  status bad --json --quiet

# --- 场景 3：全部项目采集失败（P0-2 的前提）---
# ok / bad / plain 三个项目路径都失效 ⇒ 引擎 exit 1 + stderr 空 + stdout 有 JSON
#
# ⚠️ plain 也必须删：它是「路径存在但不是 git 仓库」，引擎仍能列出一条记录，
#    于是只要它还活着就不是「全失败」，exit 会变成 0，第 9 组的前提悄悄消失。
#    （本脚本已因此踩过一次：加了 plain 之后这里印出 exit=0。）
remove_path "$REPO_PLAIN"
remove_path "$REPO_OK"
# ⚠️⚠️ REPO_TYPES 必须**在收完 status_types 之后**跟着一起删。
# 第一版特意留着它不删（怕拿到错误桩），结果第 9 组「全部项目采集失败」的前提
# 直接塌了：还有一个项目活着 ⇒ `status` 退出 0 ⇒ 那组全部断言失去意义
# （实测报 exit=0）。顺序错了两次：先是没删，这次是删的时机不对。
# 正确形状是：先 collect 真实样本（拿到正常形状），再删（让全失败场景成立）。
remove_path "$REPO_TYPES"
# ⚠️ 同理：待记录徽章那个样本仓库也必须删。
# 它是本轮新增的（#213），收完 status_pending 之后忘了删 ——
# 于是第 9 组的前提又塌了：还有一个项目活着 ⇒ `status` 退出 0。
# **凡是往注册表里加项目的场景，都要在这一段跟着删一次。**
remove_path "$REPO_PENDING"
# 同上：陈旧样本仓库（本轮为验时间窗新增）也得删。
# 忘了删的后果一模一样：还有一个项目活着 ⇒ 第 9 组前提塌成 exit=0。
# 这已经是第三次栽在这一段，所以下面把「加项目」和「删项目」写死成对称的两段。
remove_path "$REPO_STALE"
# 第四次：有远端的 mergeable 样本仓库（本轮为验 mergeCandidates 交叉验证新增）。
# 形状与上面两处完全相同：注册了、路径活着 ⇒ 第 9 组 exit 回到 0。
# 规律不变 —— **这一段每加一行 remove_path，下一个加项目的人就会漏掉它**。
remove_path "$REPO_MERGE"
collect status_allfail status --json --quiet
"$ENGINE" status --json --quiet >/dev/null 2>&1
ALLFAIL_RC=$?
ALLFAIL_ERR_BYTES=$("$ENGINE" status --json --quiet 2>&1 >/dev/null | wc -c | tr -d ' ')
# 退出码一并交给检查程序断言：P0-2 修的是「非 0 退出时 stdout 仍带 payload」，
# 一旦 exit 悄悄变回 0，这条断言就整个失去意义（payload 照样能解，什么都测不到）。
echo "$ALLFAIL_RC" > "$FIXTURES/status_allfail.rc"
echo "  （全失败场景：exit=$ALLFAIL_RC, stderr=${ALLFAIL_ERR_BYTES}B）"

# ---- 编译契约检查 ---------------------------------------------------------
SDK="$(xcrun --show-sdk-path --sdk macosx 2>/dev/null)"
BIN="$SANDBOX/contract-check"
echo "编译契约检查（Models.swift + 三个纯函数本体 + 检查程序）…"
if ! swiftc -O -sdk "$SDK" "$MODELS" "$CTCOMP" "$MSCARD" "$UPOUT" "$CHECKER" -o "$BIN" 2>"$SANDBOX/compile.log"; then
  echo "✗ 编译失败：" >&2
  sed 's/^/  /' "$SANDBOX/compile.log" >&2
  exit 1
fi

# ---- 跑 -------------------------------------------------------------------
echo ""
DG_FIXTURES="$FIXTURES" "$BIN"
RC=$?

if [[ $RC -ne 0 ]]; then
  echo ""
  echo "契约检查未通过。常见成因："
  echo "  · 引擎改了 JSON 键名 —— 同步改 Sources/deepDolphin/Models.swift（AGENTS.md 有约定）"
  echo "  · 引擎新增了必填字段 —— 补进对应 struct"
  echo "  · 沙箱没造成功 —— 上面的 ⚠ 会提示"
fi
exit $RC
