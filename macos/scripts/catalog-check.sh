#!/bin/bash
# catalog-check.sh — models.dev 目录层（ModelsDev.swift）的检查。
#
# 【为什么不能靠 ContractCheck 兜住】
# ContractCheck 管的是**跨进程契约**（引擎输出 ↔ 客户端模型）。
# 这里管的是纯客户端内部两个 P0，性质不同：
#   · P0-1 打包版 AI 永久不可用：`parse()` 持 NSLock 后调 `parseInto()` 再取
#     同一把**非递归**锁 ⇒ 永久自死锁。触发条件是「无缓存 + bundle 有资源」，
#     所以 `swift run` 开发期**完全测不出来**。
#   · P0-2 快照是扁平键（context/cost_in/cost_out），解析器读嵌套
#     （limit{}/cost{}）⇒ 225 个 provider 的上下文窗口与成本全为 nil。
#
# 【关键点】编译的是 Sources/deepGit/ModelsDev.swift 本体，不是副本 ——
# 副本会与源文件漂移，测了等于没测。
#
# 【跑法】scripts/catalog-check.sh

set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$PKG_DIR/Sources/deepGit/ModelsDev.swift"
# ModelsDev.popularProviders 的默认上限来自这里，编译时必须一起带上
PICKER="$PKG_DIR/Sources/deepGit/ProviderPickerSlice.swift"
CHECKER="$PKG_DIR/Tests/CatalogCheck/main.swift"
SNAPSHOT="$PKG_DIR/Resources/models-dev.json"

if [[ ! -f "$SNAPSHOT" ]]; then
  echo "✗ 找不到 $SNAPSHOT —— 这个检查需要真实快照（打包时被读的那份）。" >&2
  exit 2
fi

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/dg-catalog-XXXXXX")"
cleanup() {
  if command -v mavis-trash >/dev/null 2>&1; then
    mavis-trash -- "$SANDBOX" >/dev/null 2>&1
  else
    rm -rf "$SANDBOX"
  fi
}
trap cleanup EXIT

SDK="$(xcrun --show-sdk-path --sdk macosx 2>/dev/null)"
BIN="$SANDBOX/catalog-check"
echo "编译目录检查（ModelsDev.swift + ProviderPickerSlice.swift 本体 + 检查程序）…"
if ! swiftc -O -sdk "$SDK" "$CATALOG" "$PICKER" "$CHECKER" -o "$BIN" 2>"$SANDBOX/compile.log"; then
  echo "✗ 编译失败：" >&2
  sed 's/^/  /' "$SANDBOX/compile.log" >&2
  exit 1
fi

echo ""
"$BIN"
RC=$?

if [[ $RC -ne 0 ]]; then
  echo ""
  echo "目录检查未通过。常见成因："
  echo "  · 又把解析与加锁混进同一个函数 —— 那会自死锁（P0-1）"
  echo "  · 快照形状变了（扁平 context/cost_in ↔ 嵌套 limit{}/cost{}）而解析器没跟上（P0-2）"
  echo "  · provider 选择器又变回「标题报总家数、列表只列前 N 家」—— 159 家选不到（#209）"
fi
exit $RC
