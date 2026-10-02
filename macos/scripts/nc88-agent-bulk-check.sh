#!/bin/bash
# NC88 —— 「一键全量」判据组的负控。
#
# 【为什么要单独跑一遍】判据绿只说明「现在没坏」，不说明「坏了它会红」。
# 尤其这一组：它们全是对**新写的实现**加的约束，最容易出现的不是判据失效，
# 而是判据写成了一个当前恰好为真的形状（永远绿），自己还不知道。
#
# 每个变体只改一处、只回滚一处，且**必须红在它声称的那条判据上** ——
# 「红了」不够，「红的原因与它声称的判据一致」才算数。
# 所以下面每个变体都带 expect（期望命中的判据名）与 notExpect（不该被误伤的那条）。
set -u
cd "$(dirname "$0")/.." || exit 1
unset SDKROOT

SRC=Sources/deepDolphin/AgentBulkUpdate.swift
VIEW=Sources/deepDolphin/AgentBulkView.swift
MODEL=Sources/deepDolphin/Model.swift
BAR=Sources/deepDolphin/WorkBar.swift
SRCDIR=Sources/deepDolphin

pass=0
fail=0

# 备份与还原。用 mktemp -d 而不是固定名：连跑两次不会互相踩。
tmp=$(mktemp -d)
cp "$SRC" "$tmp/AgentBulkUpdate.swift"
cp "$VIEW" "$tmp/AgentBulkView.swift"
cp "$MODEL" "$tmp/Model.swift"
cp "$BAR" "$tmp/WorkBar.swift"
restore() {
  # 快照可能已经被清掉了（正常收尾时会先 rm）。扑空就安静跳过 ——
  # 否则退出时会刷一串 cp 报错，把「15/15 全红」这条结论淹掉。
  [ -d "$tmp" ] || return 0
  for f in AgentBulkUpdate.swift AgentBulkView.swift Model.swift WorkBar.swift; do
    [ -f "$tmp/$f" ] && cp "$tmp/$f" "$SRCDIR/$f"
  done
  return 0
}
# ⚠️ **任何退出路径都必须还原**，包括 mutate 检测到「没生效」时的 exit 2。
#   只在每个变体末尾写 `restore` 是不够的：中途非零退出就把改坏的源码留在
#   工作区里，而那份源码**看起来是正常的实现**，很可能就这样被提交出去。
#   本轮真的踩到过：变体 6 的锚点失配 → exit 2 → `busyAll = true` 被删掉后
#   留在工作区，下一轮判据红了 —— 报的是「实现有缺陷」，其实是我留下的垃圾。
trap restore EXIT INT TERM

# mutate <文件> <perl 表达式>
#
# ⚠️ **就地校验这个文件真的被改动了**，改不动就当场退出。
#   第一版是拿「全量快照 vs 当前」比对四个文件，结果有两种误判：
#     · 正则失配 ⇒ 文件没变 ⇒ 快照比对本该抓到；
#     · 可我在负控运行期间**自己**改了另一个源文件 ⇒ 快照失配 ⇒
#       守卫以为「有改动」，于是一个**根本没生效**的变体被报成
#       「判据是摆设」—— 而最自然的反应（去改判据）恰好是错的方向。
#   局部哈希比对不受其它文件变动影响，这是唯一可靠的判据。
mutate() {
  local file="$1"; shift
  local before after
  before=$(shasum "$file" | cut -d' ' -f1)
  perl -0pi -e "$1" "$file"
  after=$(shasum "$file" | cut -d' ' -f1)
  if [ "$before" = "$after" ]; then
    printf '  ✗ 变体**没有改动 %s** —— 正则锚点失配，负控没生效（判据无辜）\n' "$(basename "$file")"
    exit 2
  fi
}

# run <期望命中的判据名> <变体名>
run() {
  local expect="$1" name="$2"
  local out
  out=$(./scripts/client-check.sh 2>&1)
  if ! printf '%s' "$out" | grep -q "客户端检查未通过"; then
    printf '  ✗ %-34s 期望红，实际绿 —— 这条判据现在是个摆设\n' "$name"
    fail=$((fail + 1))
  elif ! printf '%s' "$out" | grep -qF "$expect"; then
    printf '  ✗ %-34s 红了，但红的原因不是它声称的判据\n     期望命中：%s\n     实际：%s\n' \
      "$name" "$expect" "$(printf '%s' "$out" | grep -A1 '·' | tail -1 | cut -c1-110)"
    fail=$((fail + 1))
  else
    printf '  ✓ %-34s 按预期红在「%s」\n' "$name" "$expect"
    pass=$((pass + 1))
  fi
}

echo "NC88 —— 「一键全量」判据组负控"
echo ""

# ── 变体 1：把执行退回裸的批量 CLI ──
# 这是本组最要防的那个：功能照样「能跑」，界面照样出结果，
# 但「基于 AI agent 执行」已经名存实亡，而没有任何一层会红。
mutate "$SRC" 's/let \(ok, text\) = await AgentCore\.executeTool\(\n\s*tool,\n\s*params: \["name": p\.name\],\n\s*parametersJSONByName: required\n\s*\)/let (ok, text) = (true, "")\n            _ = await EngineCLI.shared.updateAll(deep: deep)/s'
run "必须逐个走 agent 工具通道" "变体1 执行退回裸 updateAll"
restore

# ── 变体 2：遍历里截断 ──
mutate "$SRC" 's/for p in projects \{/for p in projects.prefix(1) {/s'
run "覆盖必须遍历全部已注册项目" "变体2 全量只跑第一个仓库"
restore

# ── 变体 3：遍历里按状态过滤 ──
mutate "$SRC" 's/for p in projects \{/for p in projects.filter({ \$0.error == nil }) {/s'
run "覆盖必须遍历全部已注册项目" "变体3 过滤掉读不出来的仓库"
restore

# ── 变体 4：失败即中断整批 ──
# ⚠️ 锚点只取 `outcomes.append(Outcome(` 这一行、不吃后面的参数 ——
#   第一版把整段多行构造都写进正则里，于是排版一改（拆成多行）正则就失配，
#   变体「没生效」而被误读成「判据是摆设」。负控的锚点要选**最稳定的那个**。
mutate "$SRC" 's/(            outcomes\.append\(Outcome\()/            guard ok else { return Report(deep: deep, outcomes: outcomes, attempted: projects.count, aiText: "", aiNote: "中断") }\n$1/s'
run "一个仓库失败不许中断整批" "变体4 第一个失败就 return"
restore

# ── 变体 5：传空项目名 ──
mutate "$SRC" 's/params: \["name": p\.name\]/params: ["name": ""]/s'
run "必须显式传项目名" "变体5 传空 name（= 全群改写）"
restore

# ── 变体 6：锁放到第一个 await 之后 ──
# 两步：把 `busyAll = true` 从「发起时」挪到「冻结名单之后」。
# （第一版照着更早一版的 Model.swift 写锚点，而那时锁还在 Task 里面 ——
#  锁挪到 Task 外之后这三行全部失配，负控没生效。现在锚点只认
#  `busyAll = true` 那一行本身，与它在函数里的位置无关。）
#
# ⚠️ 2026-10-02：`startAgentBulk` 随按钮一起撤掉，执行体搬进 `updateAll`，
#    冻结那行也从 `self.projects` 改成 `projects`（同层无需 self）。
#    锚点跟着实际写法走 —— 负控的锚点失配时**判据是无辜的**，
#    该改的是锚点，不是判据。
mutate "$MODEL" 's/        busyAll = true\n//'
mutate "$MODEL" 's/(        let targets = projects\n)/$1        self.busyAll = true\n/'
run "共用同一把锁" "变体6 锁放到第一个 await 之后"
restore

# ── 变体 7：全量的那条链断一环（死功能） ──
# ⚠️ 原来是「按钮做出来但不挂」—— 按钮已按用户要求撤掉，
#    于是同一份担心换了个问法：**撤掉按钮之后，能力还接得上吗？**
#    判据相应改成「全量入口不许在一屏里出现两次」，
#    它同时钉「只有一处入口」与「这一处真能走通到 updateAll」。
#    这里断掉双轨 → requestBulkUpdate 那一环。
mutate "$MODEL" 's/            requestBulkUpdate\(deep: deep\)/            startUpdate(deep: deep)/s'
run "不许在一屏里出现两次" "变体7 双轨到全量的链断一环"
restore

# ── 变体 8：视图里另写一份工具名字面量 ──
# 只做一件事：在视图里塞一个工具名字面量，看「唯一出处」那条判据是否还咬得住。
# （第一版这里先试着用正则改写 title 那行，正则里的嵌套引号转义炸了、
#  报了一行 Perl 错才走兜底 —— 变体要的是「确定地改一处」，
#  正则改不出确定性就不是负控，是碰运气。）
# ⚠️ 2026-10-02：锚点原来挂在 `model.startAgentBulk` 上，
#    而那个方法连同按钮一起撤掉了 ⇒ 变体失配、exit 2。
#    换成挂**结构体声明**这一行 —— 它在文件重写后依然存在，且最稳定。
mutate "$VIEW" 's/(struct AgentBulkResultSheet: View \{)/let _literalToolName = "run_shallow_update"\n$1/s'
run "工具名不许在客户端另写一份字面量" "变体8 视图里写字面量工具名"
restore

# ── 变体 9：必填清单各抄一份 ──
mutate "$SRC" 's/        let required = await AgentCore\.requiredParamsByTool\(\)/        let required = ["run_shallow_update": "{\\"type\\":\\"object\\",\\"required\\":[]}"]/s'
run "共用同一份" "变体9 必填清单自造一份（校验失效）"
restore

# ── 变体 10：AI 失败静默 ──
mutate "$SRC" 's/            let msg = EngineError\.userMessage\(for: error\)\n            return \("", "未生成 AI 简报：\\\(msg\)\\n\\n更新本身已经执行完毕，结果以上表为准。"\)/            \/\/ 静默吞掉：更新已经跑完，简报没出来就算了/s'
run "AI 那一层没跑成时必须说出口" "变体10 AI 失败静默吞掉"
restore

# ── 变体 11：空 catch ──
mutate "$SRC" 's/            let msg = EngineError\.userMessage\(for: error\)\n            return \("", "未生成 AI 简报：\\\(msg\)\\n\\n更新本身已经执行完毕，结果以上表为准。"\)/            \/\/ 什么也不做/s'
run "AI 那一层没跑成时必须说出口" "变体11 catch 是空的"
restore

# ── 变体 12：把引擎原始 JSON 灌回界面（真 app 截图抓到的那条） ──
mutate "$SRC" 's/detail: ok \? describe\(text, fallback: p\.name\) : text/detail: text/s'
run "不许直接灌引擎原始 JSON" "变体12 说明退回原始 JSON"
restore

# ── 变体 13：明细改回 markdown 表格（窄面板会被撑爆） ──
# 锚点取 `let items = outcomes.map { o in` —— 明细排版的唯一入口。
# （第一版去匹配那行 list item 的字面内容，而它是带引号的 Swift 字符串字面量，
#  正则里那个前导引号怎么转都对不齐 ⇒ 变体没生效。）
mutate "$SRC" 's/(            let items = outcomes\.map \{ o in\n)/$1                let table = "| 仓库 | 结果 | 说明 |"; _ = table\n/s'
run "不许直接灌引擎原始 JSON" "变体13 明细改回 markdown 表格"
restore

# ── 变体 14：先冻结名单、后刷新（= 截图抓到的那条） ──
# 把 refreshAll 从「冻结之前」挪到「冻结之后」。
# 只有两条 mutate：先删掉冻结前那次刷新，再在冻结后补一次。
# ⚠️ 这里原本还有第三条 `s/(…refreshAll…\n            onDone\(report\))/$1/s` ——
#    那是**替换成自身**的空操作，文件一个字节都不变。局部守卫当场拦下了它
#    （这正是守卫存在的意义：空操作伪装成一次成功的改动）。
mutate "$MODEL" 's/        await refreshAll\(\)\n        let targets = projects\n/        let targets = projects\n/s'
mutate "$MODEL" 's/(        let targets = projects\n)/$1        await refreshAll()\n/s'
run "先刷新注册表再冻结名单" "变体14 冻结陈旧名单（静默漏仓库）"
restore

# ── 变体 15：标题取点击时的旧数（面板自相矛盾） ──
# 锚点只取 `attempted) 个仓库` 这一小段。
# （第一版把整行 `title = "全量\(deep ? "深度" : "浅")更新 · \(r.attempted) 个仓库"`
#  写进正则 —— 里面既有嵌套的 Swift 字符串引号又有未转义的括号，
#  perl 直接报 Unmatched ( in regex 而**什么也没改**。）
# 2026-10-02：绑定名从 `r` 改成 `report`（sheet 的入参），锚点同步。
mutate "$VIEW" 's/attempted\) 个仓库/model.projects.count) 个仓库/s'
run "先刷新注册表再冻结名单" "变体15 标题用点击时的旧数"
restore

# ── 变体 16：汇总换个词说（数字对、措辞分叉） ──
# 真 app 抓到：上一行「成功 3 个，失败 3 个」，下一行写「3/6 完成」。
# 同一个量两套措辞 ⇒ 用户以为分母不同。
# 变体只把汇总那行改回旧措辞，**上面那两个变量一个都不动** ——
# 所以任何只钉「数字对不对」的判据都咬不住它，必须钉措辞。
#
# ⚠️ 锚点只取 `## 逐仓库结果（\(tally)）` 这一行。
#    第一版想把整段汇总计算（`let failed = …` 起三行、带 `? :` 和
#    嵌套中文引号）一起替换，perl 直接报 `Unmatched ) in regex`、
#    **一个字节都没改** —— 而变体被如实报成「锚点失配、判据无辜」。
#    这正是本项目写过的规矩：锚点要选最稳定的那处，不吃多行构造、
#    不吃带嵌套引号的 Swift 字符串字面量。
mutate "$SRC" 's/## 逐仓库结果（\\\(tally\)）/## 逐仓库结果（\\\(succeeded)\/\\\(outcomes.count) 完成）/'
run "换个词再说一遍" "变体16 汇总退回「N/M 完成」"
restore

echo ""
rm -rf "$tmp"
if [ "$fail" -eq 0 ]; then
  echo "✅ NC88 全部按预期红：$pass/$pass"
  exit 0
fi
echo "❌ NC88 有变体没红对：$pass 通过 / $fail 失败"
exit 1
