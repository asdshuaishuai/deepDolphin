#!/bin/bash
# NC90 —— 设置分页签判据组的负控。
#
# 【为什么这组特别需要负控】
# 这一组是**纯新写**的判据，钉的是「三个页签各接一张卡」与
# 「页脚不许有死控件」两条。两者都是**结构性**断言 ——
# 它们特别容易退化成「把当前恰好长这样���写法记下来」，
# 于是把代码改回缺陷版本时照样绿，而绿得像在保护。
#
# 每个变体只改一处、只回滚一处，且**必须红在它声称的那条判据上** ——
# 「红了」不够，「红的原因与它声称的判据一致」才算数。
set -u
cd "$(dirname "$0")/.." || exit 1
unset SDKROOT

SETTINGS=Sources/deepGit/AISettingsView.swift
SRCDIR=Sources/deepGit
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
#
# ⚠️ 哈希变了**不等于**改成了想要的样子。替换串里漏写转义的 `$` 就是一个：
#    perl 把它当自己的变量吃成空串，源文件根本编译不过，但 client-check
#    是按文本查的，照样绿 ⇒ 报成「判据是摆设」，把结论带歪。
#    所以第三个参数是必需的：**指名改完必须出现的那段文本**。
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

echo "NC90 —— 设置分页签判据组负控"
echo ""

# ── 变体 1：漏接一个页签（点得过去、里面是空的） ──
mutate "$SETTINGS" 's/                case \.automation: ScheduleCard\(\)\n//'
run "必须双向对齐" "变体1 自动化页没接内容"
restore

# ── 变体 2：页签栏漏一个分类 ──
# 页签少一个 = 有一块设置**从界面上消失了**，用户再也找不到它。
mutate "$SETTINGS" 's/    case general, automation, ai/    case general, automation/'
run "必须双向对齐" "变体2 页签栏漏掉 AI"
restore

# ── 变体 3：页脚对所有页都摆「保存」（死控件） ──
# 通用/自动化是**即时写入**的，那里没有未保存的改动可保存。
mutate "$SETTINGS" 's/                if tab == \.ai \{\n                    Button\("保存"\) \{ save\(\) \}/                if true {\n                    Button("保存") { save() }/'
run "不许出现死控件" "变体3 保存按钮常显"
restore

# ── 变体 4：「保存」不按有没有改动禁用 ──
# 打开设置什么都不改也能点保存 = 一个点下去什么都不会发生的按钮。
mutate "$SETTINGS" 's/                        \.disabled\(!aiDirty\)\n//'
run "不许出现死控件" "变体4 保存不按 dirty 禁用"
restore

# ── 变体 5：关闭按钮在即时写入的页上也写「取消」 ──
# 「取消」承诺能撤销，可那两页根本没有未保存的东西可撤销。
mutate "$SETTINGS" 's/Button\(tab == \.ai \? "取消" : "关闭"\)/Button("取消")/'
run "不许出现死控件" "变体5 关闭按钮恒叫「取消」"
restore

# ── 变体 6：保存失败后不送回 AI 页 ──
# 失败可能发生在用户已经切走之后；不送回去，他停在一页无关的 tab 上
# 看着一条与自己无关的报错。
mutate "$SETTINGS" 's/            tab = \.ai\n//'
run "不许出现死控件" "变体6 保存失败不回 AI 页"
restore

# ── 变体 7：同一个页签分支写两遍 ──
# 写两遍就是渲染两次 —— 本项目反复修过的缺陷族（按钮排两遍、侧栏行两遍）。
mutate "$SETTINGS" 's/(                case \.general:    LoginItemCard\(\))/$1\n                LoginItemCard()/'
run "必须双向对齐" "变体7 通用页渲染两张卡"
restore

# ── 变体 8：AI 页自持一份草稿（编辑的那份与保存的那份分叉） ──
# 分页签之后保存动作在页脚，页脚拿的是父层那份；AI 页要是再养一份，
# 就会出现「界面上改的是这一份、存下去的是那一份」，而且哪里出错都不报错。
mutate "$SETTINGS" 's/    \@Binding var draft: AIConfig/    \@Binding var draft: AIConfig\n    \@State private var ownDraft = AIConfig()/' 'ownDraft = AIConfig()'
run "一处真身" "变体8 AI 页自持第二份草稿"
restore

# ── 变体 9：草稿接进来了，却没接基准（保存按钮永远灰着） ──
mutate "$SETTINGS" 's/    \@State private var original = AIConfig\(\)\n//' 'private var aiDirty: Bool { draft != original }'
run "一处真身" "变体9 宿主编排里丢了基准"
restore

echo ""
if [ "$fail" -eq 0 ]; then
  echo "✅ NC90 全部按预期红：$pass/$pass"
  exit 0
fi
echo "❌ NC90 有变体没红对：$pass 通过 / $fail 失败"
exit 1
