#!/bin/bash
# agent-check.sh — agent 判定层的检查。
#
# 覆盖两个缺陷：
#   P0-4 工具调用轮次上限时直接 throw，把**本轮已生成的 result.text 丢掉**
#   P0-5 agent 每次从零起步（`var convo = [ChatMessage.user(question)]`），
#         所谓"对话"其实是一串互不相干的一次性提问
#
# 编译的是 Sources/deepDolphin/*.swift 本体（不是副本）——
# 副本会与源文件漂移，测了等于没测。
# 也正因为它们无任何依赖，判定才能被单独抽出来测：
# 内联在 for 循环/视图里时，那几档永远抓不到。
#
# 【跑法】scripts/agent-check.sh

set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTCOME="$PKG_DIR/Sources/deepDolphin/AgentOutcome.swift"
MSG="$PKG_DIR/Sources/deepDolphin/ChatMessage.swift"
CONVO="$PKG_DIR/Sources/deepDolphin/AgentConversation.swift"
AIERR="$PKG_DIR/Sources/deepDolphin/AIErrorMessage.swift"
ARGS="$PKG_DIR/Sources/deepDolphin/ToolArgs.swift"
CHECKER="$PKG_DIR/Tests/AgentCheck/main.swift"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/dg-agent-XXXXXX")"
cleanup() {
  if command -v mavis-trash >/dev/null 2>&1; then
    mavis-trash -- "$SANDBOX" >/dev/null 2>&1
  else
    rm -rf "$SANDBOX"
  fi
}
trap cleanup EXIT

SDK="$(xcrun --show-sdk-path --sdk macosx 2>/dev/null)"
BIN="$SANDBOX/agent-check"
echo "编译 agent 检查（AgentOutcome + ChatMessage + AgentConversation + AIErrorMessage + ToolArgs 本体 + 检查程序）…"
if ! swiftc -O -sdk "$SDK" "$OUTCOME" "$MSG" "$CONVO" "$AIERR" "$ARGS" "$CHECKER" -o "$BIN" 2>"$SANDBOX/compile.log"; then
  echo "✗ 编译失败：" >&2
  sed 's/^/  /' "$SANDBOX/compile.log" >&2
  exit 1
fi

echo ""
"$BIN"
RC=$?

if [[ $RC -ne 0 ]]; then
  echo ""
  echo "agent 检查未通过。常见成因："
  echo "  · 轮次上限时又回到「直接抛错」—— 那会把已生成的答案丢掉（P0-4）"
  echo "  · 交出半截答案却没标注「已达上限」—— 用户会当成完整结论"
  echo "  · 对话历史被清零/裁掉太多 —— 追问会答非所问（P0-5）"
  echo "  · 发送按钮的禁用原因说不清 —— 用户只能猜为什么灰着"
  echo "  · AI 网络错误退回 Cocoa 英文原文 —— 中文界面里出现 Could not connect to the server."
fi
exit $RC
