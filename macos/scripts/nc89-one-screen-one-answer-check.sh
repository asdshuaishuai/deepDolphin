#!/bin/bash
# NC89 —— 【W】「一屏之内不许出现两个答案」判据组的负控。
#
# 【为什么这组特别需要负控】
# 这一组的三条判据都是**新写的**，而且都是「钉结构」而不是「钉数值」。
# 钉结构的判据有个特有死法：它可能只是把**当前恰好长这样**的写法记下来了，
# 于是把代码改回缺陷版本时它照样绿 —— 绿得像在保护，其实什么也没保护。
# 只有把缺陷版本真的构造出来跑一遍，才知道它咬不咬得住。
#
# 每个变体只改一处、只回滚一处，且**必须红在它声称的那条判据上** ——
# 「红了」不够，「红的原因与它声称的判据一致」才算数。
# 所以每个变体都带 expect（期望命中的判据名）。
set -u
cd "$(dirname "$0")/.." || exit 1
unset SDKROOT

MODELS=Sources/deepDolphin/Models.swift
SCOPE=Sources/deepDolphin/DashboardScope.swift
VIEWS=Sources/deepDolphin/DetailViews.swift
BAR=Sources/deepDolphin/WorkBar.swift
PANEL=Sources/deepDolphin/PanelView.swift
APP=Sources/deepDolphin/DeepGitApp.swift
SRCDIR=Sources/deepDolphin
# ⚠️ 备份清单必须**列全所有被 mutate 的文件**。
#   漏一个 = 那个文件的还原靠不上，脚本中途非零退出时改坏的源码就留在工作区里。
#   （本脚本第一版就是漏了 PanelView：变体 9 改它，而清单里没有它。）
FILES="Models.swift DashboardScope.swift DetailViews.swift WorkBar.swift PanelView.swift DeepGitApp.swift"

pass=0
fail=0

# 备份与还原。用 mktemp -d：连跑两次不会互相踩。
tmp=$(mktemp -d)
for f in $FILES; do cp "$SRCDIR/$f" "$tmp/$f"; done
restore() {
  [ -d "$tmp" ] || return 0
  for f in $FILES; do [ -f "$tmp/$f" ] && cp "$tmp/$f" "$SRCDIR/$f"; done
  return 0
}
# ⚠️ **任何退出路径都必须还原**，包括 mutate 检测到「没生效」时的 exit 2。
#   只在变体末尾写 restore 是不够的：中途非零退出就把改坏的源码留在工作区里，
#   而那份源码**看起来是正常的实现**，很可能就这样被提交出去。
trap restore EXIT INT TERM

# mutate <文件> <perl 表达式>
#
# ⚠️ **就地校验这个文件真的被改动了**，改不动就当场退出。
#   局部哈希比对是唯一可靠的判据：拿全局快照比会被「负控运行期间我自己改了
#   另一个源文件」污染，于是把一个**根本没生效**的变体报成「判据是摆设」——
#   而最自然的反应（去改判据）恰好是错的方向。
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

# run <期望命中的判据名> <变体名> [判据套件]
#
# ⚠️ **套件必须按判据的实际位置选**。
#   第一版所有变体都跑 client-check，于是变体 1（isMergeCandidate 退回 pendingCommits）
#   「期望红，实际绿」—— 而 client-check 绿**不代表判据失效**：
#   `isMergeCandidate` 的函数体与「客户端 == 引擎」那条交叉验证在 **contract-check** 里
#   （那条要拿引擎真实输出当证据，天然属于契约检查）。
#   把它误报成「判据是摆设」之后，最自然的反应（去 client-check 里补一条重复的）
#   恰好是错的方向：正确的做法是让负控去跑**那条判据真正所在**的套件。
run() {
  local expect="$1" name="$2" suite="${3:-client}"
  local script marker out
  case "$suite" in
    contract) script=./scripts/contract-check.sh; marker="契约检查未通过" ;;
    *)        script=./scripts/client-check.sh;  marker="客户端检查未通过" ;;
  esac
  out=$("$script" 2>&1)
  if ! printf '%s' "$out" | grep -q "$marker"; then
    printf '  ✗ %-38s 期望红（%s），实际绿 —— 这条判据现在是个摆设\n' "$name" "$suite"
    fail=$((fail + 1))
  elif ! printf '%s' "$out" | grep -qF "$expect"; then
    printf '  ✗ %-38s 红了，但红的原因不是它声称的判据\n     期望命中：%s\n     实际：%s\n' \
      "$name" "$expect" "$(printf '%s' "$out" | grep -A1 '·' | tail -1 | cut -c1-110)"
    fail=$((fail + 1))
  else
    printf '  ✓ %-38s 按预期红在「%s」(%s)\n' "$name" "$expect" "$suite"
    pass=$((pass + 1))
  fi
}

echo "NC89 —— 【W】「一屏之内不许出现两个答案」判据组负控"
echo ""

# ═══ 缺陷 1 的四个变体：needsAction / isMergeCandidate ═══
# 全部对应真 app 现场：侧栏「看板 0」而仪表盘「待处理 6」。

# ── 变体 1：isMergeCandidate 退回 pendingCommits ──
# 这是**引擎已经修掉的那个错**（dashboard.cj:200-208 + 回归测试
# testDashboardMergeCandidatesUsesAheadOfDefaultNotPending）。客户端把它又犯了一遍。
# 判据在 contract-check：那里既有「三条条件逐字对齐」那条源码级断言，
# 也有「客户端 == 引擎 work.mergeCandidates」那条**拿真实数据**的交叉验证。
mutate "$MODELS" 's/        aheadOfDefault > 0 && !isDefault && !merged/        pendingCommits > 0 \&\& !isDefault/s'
run "合并候选的条数" "变体1 判据退回 pendingCommits" contract
restore

# ── 变体 2：漏掉 !merged 这一条 ──
# 单独拿掉一个排除条件：已合入的分支会被重新报成「可合入」。
# ⚠️ 这条**只能**由源码级断言抓住：引擎的 merged 与 aheadOfDefault 在真实数据里
#    互斥（merged ⇒ 不领先），造不出「两条同时成立」的样本 ——
#    局限写在 contract-check 第 17 组的注释里。
mutate "$MODELS" 's/aheadOfDefault > 0 && !isDefault && !merged/aheadOfDefault > 0 \&\& !isDefault/s'
run "isMergeCandidate 的三条条件" "变体2 漏掉 !merged" contract
restore

# ── 变体 3：merged 写成 let + 初值 ──
# 合成 init(from:) 会跳过「带初值的不可变存储属性」⇒ merged 永远是 false。
# 这一变体不改变任何判定结果，**只有那条按写法钉的判据会红** ——
# 正好用来验证「按写法覆盖整族」那条判据不是摆设（不变量 105 的整族）。
#
# ⚠️ 判据在 **client-check** 而不是 contract-check：
#    `let merged: Bool = false` 会让 Swift 的**成员初始化器直接丢掉 `merged` 参数**，
#    于是契约检查里任何显式传 `merged:` 的测试代码**编译失败**，
#    脚本在编译阶段就退出、判据根本没机会运行 ——
#    负控会据此误报「这条判据是摆设」（第一版就踩了，见不变量 118）。
#    client-check 只做源码 lint、不编译，正好是这条判据该待的地方。
mutate "$MODELS" 's/^    let merged: Bool$/    let merged: Bool = false/m'
run "let + 初值" "变体3 merged 写成 let + 初值" client
restore

# ── 变体 4：needsAction 绕过 isMergeCandidate 自己判 ──
# 抄第二份判法。抄的时候很容易顺手抄成引擎**原来那个错版本**。
mutate "$MODELS" 's/            \|\| branches\.contains \{ \$0\.isMergeCandidate \}/            || branches.contains { \$0.aheadOfDefault > 0 \&\& !\$0.isDefault }/s'
run "needsAction" "变体4 needsAction 自己另判一份"
restore

# ═══ 缺陷 2 的两个变体：项目总数 listed / total ═══

# ── 变体 5：主数字用 total（仅采集成功） ──
mutate "$SCOPE" 's/DashKPI\(kind: \.projects, title: "项目总数", value: listed,/DashKPI(kind: .projects, title: "项目总数", value: d.projects.total,/s'
run "必须用 listed" "变体5 项目总数退回 total"
restore

# ── 变体 6：把失败数悄悄吞掉 ──
# 改用 listed 是对的，但必须同时披露「其中几个读不出来」。
# 只改一半（数字对了、披露没了）同样是把坏掉的项目藏起来。
mutate "$SCOPE" 's/        if failed > 0 \{ projectsCaption \+= " · 采集失败 \\\(failed\) 个" \}\n//s'
run "必须用 listed" "变体6 采集失败数从界面上消失"
restore

# ═══ 缺陷 3 的三个变体：待处理必须是项目数 ═══

# ── 变体 7：退回三种单位相加 ──
# dirty 是项目数、mergeCandidates 是**分支数**、第三项是布尔。加起来没有意义。
mutate "$SCOPE" 's/        let attentionProjects = projects\.filter \{ \$0\.needsAction \}/        let attentionProjects = projects.filter { \$0.userDirtyCount > 0 || \$0.untrackedCount > 0 || \$0.stashCount > 0 }\n        _ = d.projects.dirty + d.work.mergeCandidates + (d.work.untrackedFiles > 0 ? 1 : 0)/s'
run "必须是项目数" "变体7 待处理退回混合单位"
restore

# ── 变体 8：主数字换成分支数 ──
mutate "$SCOPE" 's/DashKPI\(kind: \.attention, title: "待处理", value: attentionProjects\.count,/DashKPI(kind: .attention, title: "待处理", value: mergeBranchCount,/s'
run "必须是项目数" "变体8 待处理主数字换成分支数"
restore

# ── 变体 9：侧栏徽标与 KPI 分叉 ──
# 让侧栏改成数「项目总数」：徽标是装饰，每个视图行都长一个样。
mutate "$PANEL" 's/model\.projects\.filter \{ \$0\.boardColumn == \.attention \}/model.projects.filter { $0.liveness == .recent }/s'
run "同一个算法" "变体9 侧栏徽标与 KPI 分叉"
restore

# ── 变体 9b：liveness 内部把 needsAction 短路掉（本条判据漏过一次的地方） ──
# ⚠️ 这是**真 app 抓到、而当时的判据全绿**的那一处：
#    侧栏「看板 1」vs 仪表盘「待处理 3」。
#    当时 W3 钉的「链条完整」（boardColumn → liveness → needsAction 三段都在）
#    是**成立**的，而两个数照样不同 —— 因为 `engineStale` 排在 `needsAction`
#    前面，「又停滞又有活要干」的项目在 liveness 内部就被 return 掉了。
#    ⇒ 教训：**「同一个谓词」不保证「同一个结果」**，中间任何一层都可能短路。
#      判据钉到**判定顺序**上，而不是只钉「这几行存在」。
# 两步：把 needsAction 那行删掉，再插到 engineStale 后面。
mutate "$MODELS" 's/        if needsAction \{ return \.needsAction \}\n//'
mutate "$MODELS" 's/(        if primaryBranch\?\.status == "stale" \{ return \.engineStale \}\n)/$1        if needsAction { return .needsAction }\n/'
run "同一个算法" "变体9b liveness 内部短路掉 needsAction"
restore

# ═══ 缺陷 4（页头第四处）的两个变体 ═══

# ── 变体 10：页头摘要退回自己算（第四处分叉） ──
# ⚠️ 第一版这个变体是**无效变体**：把 `summaryLine` 改成
# `projects.filter { $0.needsAction }.count` —— 算出来的数**和原来一样**，
# 那不是缺陷，判据绿是对的。是变体设计错了，不是判据坏了。
#   ⇒ 纪律：变体必须还原**真实发生过的那个错**，
#     「能找到一个让判据红的改法」不等于「那是个缺陷变体」（不变量 118）。
# 真实发生的错：页头独立算 `d.projects.total` 与混合单位的「待处理」，
# 与下面的 KPI 卡（listed + 项目数）分叉。
mutate "$VIEWS" 's/Text\(DashKPIBuilder\.summaryLine\(kpis\)\)/Text("共 \\(d.projects.total) 个项目 · \\(risky) 项待处理")/s'
run "不许自己再算一遍" "变体10 页头摘要退回自己算"
restore

# ── 变体 11：kpis 被算两次（页头与卡片可能拿的不是同一份） ──
mutate "$VIEWS" 's/Text\(DashKPIBuilder\.summaryLine\(kpis\)\)/Text(DashKPIBuilder.summaryLine(DashKPIBuilder.kpis(d, projects: model.projects)))/s'
run "不许自己再算一遍" "变体11 页头与卡片各算一份 kpis"
restore

# ═══ 缺陷 5/6（详情页重排）的三个变体 ═══

# ── 变体 12：git 操作按钮排又回到页面中下部 ──
mutate "$VIEWS" 's/                    if p\.isGit \{ gitOpButtons\(p\) \}\n//s'
run "必须在页头" "变体12 页头没有 git 操作按钮排"
restore

# ── 变体 13：按钮排列两遍 ──
# 同一个动作在一页里出现两次 —— 本项目反复修过的缺陷族。
# 两处的可用性判定（busyProject）会分叉，而那只有真点一次才发现。
mutate "$VIEWS" 's/(                if p\.isGit \{ gitOpButtons\(p\) \})/$1\n                if p.isGit { gitOpButtons(p) }/s'
run "只有一个构造点" "变体13 git 操作按钮排列两遍"
restore

# ── 变体 14：把一对全量按钮放回顶栏 ──
# 用户 2026-10-02 明确要求撤掉：「仪表盘本来就有浅更新和深更新 全部，
# 所以没必要再多两个」。这个变体验证「不许在一屏里出现两次」那条钉得住。
mutate "$BAR" 's/            pipeline/            AgentBulkButtons()\n            pipeline/s'
run "不许在一屏里出现两次" "变体14 顶栏又摆一对全量按钮"
restore

# ── 变体 15：窗口标题又散成字面量（识别静默失效） ──
# `NSApp.windows[i].title` 取的是**导航标题**。
# 变体把导航标题改成另一个字面量 ⇒ 场景标题与实际显示的标题不再同源，
# 而判据只钉「两处走同一个常量」，抓不到「常量被换成一个没人对过的值」——
# 真正咬住它的是**唯一出处**那条：任何一处写裸字面量都会红。
mutate "$PANEL" 's/navigationTitle\(PanelWindow\.title\)/navigationTitle("deepGit 主面板")/'
run "只能有一个出处" "变体15 导航标题又写字面量"
restore

# ── 变体 16：「叫醒面板」又有了第二份实现 ──
# 原来 AppDelegate 与 DockMenuTarget 各抄了一份逐字相同的实现。
# 变体往 Dock target 里塞回一份内联实现（锚点用 `@objc func openPanel()` ——
# `@objc` 只在这一个方法上，是最稳定的区分点，不吃整段多行构造）。
mutate "$APP" 's/(@objc func openPanel\(\) \{\n        MainActor\.assumeIsolated \{ )PanelWindow\.bringToFront\(\)( \})/$1NSApp.activate(ignoringOtherApps: true)\n            if let p = NSApp.windows.first(where: { $0.title == "deepGit" }) { p.makeKeyAndOrderFront(nil) }\n        }\n        PanelWindow.bringToFront()$2/s'
run "只能有一份实现" "变体16 Dock 菜单内联了第二份实现"
restore

echo ""
if [ "$fail" -eq 0 ]; then
  echo "✅ NC89 全部按预期红：$pass/$pass"
  exit 0
fi
echo "❌ NC89 有变体没红对：$pass 通过 / $fail 失败"
exit 1
