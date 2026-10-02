#!/bin/bash
# markdown-check.sh — MarkdownView 块级解析（MarkdownParser.swift）的检查。
#
# 覆盖：
#   1. 解析正确性 —— 解析器从 MarkdownView.swift 抽到独立文件时，
#      最容易丢的就是行内记号剥离与标题层级判定。
#   2. **不重复解析** —— 原来 `blocks` 是 computed property，
#      body 每次求值都全量重解析一遍，200KB 文档是每帧主线程工作。
#      抽成纯函数 + 4 条记忆化后才可测。
#
# 编译的是 Sources/deepDolphin/MarkdownParser.swift 本体（不是副本）——
# 副本会与源文件漂移，测了等于没测。
# 也正因为它不 import SwiftUI，才可能被单独编译测试。
#
# 【跑法】scripts/markdown-check.sh

set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARSER="$PKG_DIR/Sources/deepDolphin/MarkdownParser.swift"
CHECKER="$PKG_DIR/Tests/MarkdownCheck/main.swift"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/dg-md-XXXXXX")"
cleanup() {
  if command -v mavis-trash >/dev/null 2>&1; then
    mavis-trash -- "$SANDBOX" >/dev/null 2>&1
  else
    rm -rf "$SANDBOX"
  fi
}
trap cleanup EXIT

SDK="$(xcrun --show-sdk-path --sdk macosx 2>/dev/null)"
BIN="$SANDBOX/markdown-check"
echo "编译 markdown 检查（MarkdownParser.swift 本体 + 检查程序）…"
if ! swiftc -O -sdk "$SDK" "$PARSER" "$CHECKER" -o "$BIN" 2>"$SANDBOX/compile.log"; then
  echo "✗ 编译失败：" >&2
  sed 's/^/  /' "$SANDBOX/compile.log" >&2
  exit 1
fi

echo ""
"$BIN"
RC=$?

if [[ $RC -ne 0 ]]; then
  echo ""
  echo "markdown 检查未通过。常见成因："
  echo "  · blocks 又变回 computed property —— body 每次求值都重解析（每帧主线程工作）"
  echo "  · 行内记号剥离或标题层级判定在搬文件时丢了"
fi
exit $RC
