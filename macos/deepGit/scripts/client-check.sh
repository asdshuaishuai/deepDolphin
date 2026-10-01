#!/bin/bash
# client-check.sh — 客户端判定层的检查（ClientDecisions.swift + PathInput.swift）。
#
# 覆盖三个已修缺陷：
#   P1-10 开机自启开关失败后不回滚 ⇒ 开关说自己知道是假的话
#   P1-12 刷新进行中时把用户请求静默丢弃 ⇒ 点刷新像没反应
#   ScanSheet 手打绝对路径 / 首尾空格直接失败且报错误导 ⇒ 判定抽到 PathInput
#
# 编译的是 Sources/deepGit/*.swift 本体（不是副本）：
# 副本会与源文件漂移，测了等于没测。
# 之所以能单独编译它们，正是因为那些判定被抽成了零依赖的纯函数 ——
# 内联在视图/生命周期代码里时，运行时根本抓不到它们。
#
# 【跑法】scripts/client-check.sh

set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DECISIONS="$PKG_DIR/Sources/deepGit/ClientDecisions.swift"
PATHINPUT="$PKG_DIR/Sources/deepGit/PathInput.swift"
STOPDEC="$PKG_DIR/Sources/deepGit/StopDecision.swift"
LANGCOV="$PKG_DIR/Sources/deepGit/LanguageCoverage.swift"
CCSCOPE="$PKG_DIR/Sources/deepGit/CommitCountScope.swift"
CTXENV="$PKG_DIR/Sources/deepGit/ContextEnvelope.swift"
ENGFAIL="$PKG_DIR/Sources/deepGit/EngineFailure.swift"
SCANCOV="$PKG_DIR/Sources/deepGit/ScanCoverage.swift"
CTCOMP="$PKG_DIR/Sources/deepGit/CommitTypeComposition.swift"
UPOUT="$PKG_DIR/Sources/deepGit/UpdateOutcome.swift"
MSCARD="$PKG_DIR/Sources/deepGit/MilestoneCard.swift"
DSTOK="$PKG_DIR/Sources/deepGit/DesignTokens.swift"
DSTRG="$PKG_DIR/Sources/deepGit/DestructiveGuard.swift"
A11Y="$PKG_DIR/Sources/deepGit/A11yLabel.swift"
SCL="$PKG_DIR/Sources/deepGit/ShortcutMap.swift"
ROUTE="$PKG_DIR/Sources/deepGit/Route.swift"
ROUTER="$PKG_DIR/Sources/deepGit/Router.swift"
SCOPE="$PKG_DIR/Sources/deepGit/Scope.swift"
LDST="$PKG_DIR/Sources/deepGit/LoadState.swift"
CHECKER="$PKG_DIR/Tests/ClientCheck/main.swift"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/dg-client-XXXXXX")"
cleanup() {
  if command -v mavis-trash >/dev/null 2>&1; then
    mavis-trash -- "$SANDBOX" >/dev/null 2>&1
  else
    rm -rf "$SANDBOX"
  fi
}
trap cleanup EXIT

# ── 编译**之前**的前置检查 ─────────────────────────────────────────────
# 为什么必须在 swiftc 之前：文件名打错 / 某个纯函数文件被摘出编译清单时，
# swiftc 会先报 "error opening input file" 或 "cannot find 'X' in scope"，
# 检查器**根本没编出来** ⇒ 写在 Swift 里的同类断言永远绿、永远抓不到东西。
# 这里先查，才能给出可读的原因，并让负控真能抓到。
PRECHECK_FAIL=0
PRECHECK_N=0

# (1) 声明的每个源文件都必须真实存在
while IFS= read -r f; do
  [ -n "$f" ] || continue
  PRECHECK_N=$((PRECHECK_N+1))
  if [ ! -f "$PKG_DIR/Sources/deepGit/$f" ]; then
    echo "✗ 编译清单声明了 ${f}，但磁盘上没有这个文件" >&2
    PRECHECK_FAIL=$((PRECHECK_FAIL+1))
  fi
done <<EOF
$(sed -n 's/^[A-Z_][A-Z_0-9]*="\$PKG_DIR\/Sources\/deepGit\/\([^"]*\)"$/\1/p' "$0")
EOF

# (2) 清单里的每个文件都必须零 SwiftUI/AppKit 依赖
for f in $(sed -n 's/^[A-Z_][A-Z_0-9]*="\$PKG_DIR\/Sources\/deepGit\/\([^"]*\)"$/\1/p' "$0"); do
  [ -f "$PKG_DIR/Sources/deepGit/$f" ] || continue
  if grep -qE '^import (SwiftUI|AppKit)' "$PKG_DIR/Sources/deepGit/$f"; then
    echo "✗ $f 进了编译清单但依赖 SwiftUI/AppKit ⇒ 命令行检查器编不过" >&2
    PRECHECK_FAIL=$((PRECHECK_FAIL+1))
  fi
done

if [ "$PRECHECK_N" -lt 6 ]; then
  echo "✗ 编译清单只解析出 $PRECHECK_N 个源文件，前置检查本身可能失效" >&2
  PRECHECK_FAIL=$((PRECHECK_FAIL+1))
fi
if [ "$PRECHECK_FAIL" -ne 0 ]; then
  echo "客户端检查未通过：编译前置检查 $PRECHECK_FAIL 项失败（编译尚未开始）" >&2
  exit 1
fi

SDK="$(xcrun --show-sdk-path --sdk macosx 2>/dev/null)"
BIN="$SANDBOX/client-check"
echo "编译客户端检查（ClientDecisions + PathInput + StopDecision + LanguageCoverage + CommitCountScope + ContextEnvelope + EngineFailure + ScanCoverage + CommitTypeComposition + MilestoneCard + UpdateOutcome + DesignTokens + DestructiveGuard + A11yLabel + ShortcutMap 本体 + 检查程序）…"
if ! swiftc -O -sdk "$SDK" "$DECISIONS" "$PATHINPUT" "$STOPDEC" "$LANGCOV" "$CCSCOPE" "$CTXENV" "$ENGFAIL" "$SCANCOV" "$CTCOMP" "$MSCARD" "$UPOUT" "$DSTOK" "$DSTRG" "$A11Y" "$SCL" "$ROUTE" "$ROUTER" "$SCOPE" "$LDST" "$CHECKER" -o "$BIN" 2>"$SANDBOX/compile.log"; then
  echo "✗ 编译失败：" >&2
  sed 's/^/  /' "$SANDBOX/compile.log" >&2
  exit 1
fi

echo ""
"$BIN"
RC=$?

if [[ $RC -ne 0 ]]; then
  echo ""
  echo "客户端检查未通过。常见成因："
  echo "  · 开关又回到「只信用户意图」—— 失败后不回滚（P1-10）"
  echo '  · 刷新闸门又回到 if isLoading { return } —— 用户请求被静默丢弃（P1-12）'
  echo "  · 路径判定回到「直接发原始字符串」—— 首尾空格/相对路径会让引擎报一句看不懂的错"
  echo "  · 停止更新回到「只取消 Swift Task」—— 那是假停止（引擎进程照跑到超时）"
  echo "  · 引擎失败回到「丢掉 payload」—— 用户只看到「引擎退出码 1」（#193）"
  echo "  · 扫描结果回到「found==0 就是没有」—— 没扫完也被说成没有仓库（#197）"
  echo "  · 注意：检查里的源码 lint 会先剥注释再匹配，所以不会把自己写的说明当缺陷"
fi
exit $RC
