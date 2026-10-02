#!/bin/bash
# NC91 —— 设置面板「滚动归属 + 尺寸下限」判据组的负控。
#
# 【为什么这组特别需要负控】
# 这两条判据是在**真 app 上量出来的**缺陷上写出来的：
# sheet 776×689 比窗口 940×672 还高，页脚按钮落在 y=809、窗口底边在 772 ——
# 保存按钮被顶到窗口框外、压在桌面上；同时 AI 页滚轮纹丝不动。
# 「记下当前写法」式的判据在这里最危险：缺陷版本和修复版本长得极像
# （都有一层 ScrollView、都有 minHeight），不实测根本分不出谁是谁。
#
# 每个变体只改一处、只回滚一处，且**必须红在它声称的那条判据上** ——
# 「红了」不够，「红的原因与它声称的判据一致」才算数。
set -u
cd "$(dirname "$0")/.." || exit 1
unset SDKROOT

SETTINGS=Sources/deepDolphin/AISettingsView.swift
SRCDIR=Sources/deepDolphin
FILES="AISettingsView.swift"

pass=0
fail=0

tmp=$(mktemp -d)
for f in $FILES; do cp "$SRCDIR/$f" "$tmp/$f"; done
restore() {
  [ -d "$tmp" ] || return 0
  for f in $FILES; do [ -f "$tmp/$f" ] && cp "$tmp/$f" "$SRCDIR/$f"; done
  return 0
}
trap restore EXIT INT TERM

# mutate <文件> <perl 表达式> [改完后必须出现的锚点]
# 局部哈希比对是唯一可靠的判据：拿全局快照比会被「负控运行期间我自己改了
# 另一个源文件」污染，于是把一个**根本没生效**的变体报成「判据是摆设」。
# 哈希变了也**不等于**改成了想要的样子，所以第三个参数是必需的：
# 指名改完必须出现的那段文本。
mutate() {
  local file="$1" expr="$2" expect="${3-}"
  local before after
  before=$(shasum "$file" | cut -d' ' -f1)
  perl -0pi -e "$expr" "$file"
  after=$(shasum "$file" | cut -d' ' -f1)
  if [ "$before" = "$after" ]; then
    printf '  ✗ 变体**没有改动 %s** —— 正则锚点失配，负控没生效（判据无辜）\n' "$(basename "$file")"
    exit 2
  fi
  if [ -n "$expect" ] && ! grep -qF "$expect" "$file"; then
    printf '  ✗ 变体改动了 %s，但没改成预期形状（缺：%s）—— 负控没生效（判据无辜）\n' \
      "$(basename "$file")" "$expect"
    exit 2
  fi
}

run() {
  local expect="$1" name="$2"
  local out
  out=$(./scripts/client-check.sh 2>&1)
  if ! printf '%s' "$out" | grep -q "客户端检查未通过"; then
    printf '  ✗ %-36s 期望红，实际绿 —— 这条判据现在是个摆设\n' "$name"
    fail=$((fail + 1))
  elif ! printf '%s' "$out" | grep -qF "$expect"; then
    printf '  ✗ %-36s 红了，但红的原因不是它声称的判据\n     期望命中：%s\n     实际：%s\n' \
      "$name" "$expect" "$(printf '%s' "$out" | grep -A1 '✗' | tail -1 | cut -c1-140)"
    fail=$((fail + 1))
  else
    printf '  ✓ %-36s 按预期红在「%s」\n' "$name" "$expect"
    pass=$((pass + 1))
  fi
}

echo "NC91 —— 设置面板滚动归属 + 尺寸下限判据组负控"
echo ""

# ── 变体 1：把 AI 页重新套回外层 ScrollView（**本轮修的就是它**） ──
# Form 报的是整份内容高度 ⇒ 外层判定「装得下」不滚，sheet 被撑到比窗口还高。
mutate "$SETTINGS" \
  's/(        case \.ai:\n)(.*\n)(            AISettingsPane\(draft: \$draft\)\n)/$1$2            ScrollView {\n                AISettingsPane(draft: \$draft)\n            }\n/' \
  'ScrollView {
                AISettingsPane(draft:'
run "每一页各自声明滚动归属" "变体1 AI 页又被套回 ScrollView"
restore

# ── 变体 2：通用页把自己的 ScrollView 删了 ──
# 那一页内容比窗口高，删掉之后窗口一小就够不着。
mutate "$SETTINGS" 's/            ScrollView \{\n                LoginItemCard\(\)\n                    \.padding\(DSSpacing\.lg\)\n                    \.frame\(maxWidth: \.infinity, alignment: \.leading\)\n            \}/            LoginItemCard()\n                .padding(DSSpacing.lg)/'
run "每一页各自声明滚动归属" "变体2 通用页没有滚动容器"
restore

# ── 变体 3：自动化页把自己的 ScrollView 删了 ──
mutate "$SETTINGS" 's/            ScrollView \{\n                ScheduleCard\(\)\n                    \.padding\(DSSpacing\.lg\)\n                    \.frame\(maxWidth: \.infinity, alignment: \.leading\)\n            \}/            ScheduleCard()\n                .padding(DSSpacing.lg)/'
run "每一页各自声明滚动归属" "变体3 自动化页没有滚动容器"
restore

# ── 变体 4：AI 页的滚动容器被换成普通 VStack ──
# 外层已经不许套 ScrollView 了，内侧再没有 Form ⇒ 这一页彻底不能滚。
mutate "$SETTINGS" 's/        Form \{/        VStack {/' 'VStack {'
run "每一页各自声明滚动归属" "变体4 AI 页失去自己的滚动容器"
restore

# ── 变体 5：minHeight 写回 640（比窗口装得下的还高） ──
# 窗口最小 940×672，去掉工具栏约剩 620；640 会把页脚顶出窗口框。
mutate "$SETTINGS" 's/minHeight: 400/minHeight: 640/' 'minHeight: 640'
run "尺寸下限必须留在窗口装得下的范围内" "变体5 面板高度回到 640"
restore

# ── 变体 6：minHeight 压到 200（矮到页签栏和页脚挤在一起） ──
mutate "$SETTINGS" 's/minHeight: 400/minHeight: 200/' 'minHeight: 200'
run "尺寸下限必须留在窗口装得下的范围内" "变体6 面板压到 200 高"
restore

# ── 变体 7：删掉最小尺寸约束（sheet 按内容收缩，能被压成 0×0） ──
mutate "$SETTINGS" 's/\.frame\(minWidth: 480, minHeight: 400\)//'
run "尺寸下限必须留在窗口装得下的范围内" "变体7 删掉最小尺寸约束"
restore

echo ""
if [ "$fail" -eq 0 ]; then
  echo "✅ NC91 全部按预期红：$pass/$pass"
  exit 0
fi
echo "❌ NC91 有变体没红对：$pass 通过 / $fail 失败"
exit 1
