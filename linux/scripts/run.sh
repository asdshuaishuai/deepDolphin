#!/usr/bin/env bash
# run.sh —— 跑起来 deepDolphin Linux 客户端。
#
# 为什么不用 `cjpm run`：`cjpm run` 会自己配好运行时路径，所以**看起来**没问题；
# 一旦直接执行 target/release/bin/main 就会
#   dyld: Library not loaded: @rpath/libcangjie-runtime.dylib
# 而「`cjpm run` 能跑」与「产物能跑」是两件事 ——
# 打成包分发时走的正是后者。所以这里显式把运行时路径摆出来。
#
# 为什么不把 rpath 写进 cjpm.toml 的 link-option：那样得把 $HOME 硬编进构建配置，
# 换台机器就断。脚本里算一次更干净。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${CANGJIE_HOME:-}" ]]; then
  CANGJIE_HOME="$HOME/.local/share/cangjie/current"
fi
if [[ ! -f "$CANGJIE_HOME/envsetup.sh" ]]; then
  echo "找不到仓颉 SDK：$CANGJIE_HOME" >&2
  echo "装 1.0.5 LTS 后重试，或先 export CANGJIE_HOME=..." >&2
  exit 1
fi
# 仓颉的 envsetup.sh 会直接读这两个变量，而 `set -u` 会让未定义时报错退出。
# 先给空值再 source，别指望 `set -u` 兼容外部脚本。
export DYLD_LIBRARY_PATH="${DYLD_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
# shellcheck disable=SC1091
source "$CANGJIE_HOME/envsetup.sh"

# macOS 的极简 SDK。
#
# 必须在 source envsetup.sh **之后**无条件覆盖：envsetup 会把 SDKROOT 指向
# 完整的 /Applications/Xcode.app/…/MacOSX.sdk，而那套 SDK 在这台机器上
# 链接不过（libSystem.tbd 解析出 "unknown architecture"，随后
# __stack_chk_fail / __dyld_get_image_header 等基础符号全部未定义）。
# 极简 SDK 是本项目既定的解法，与 moonGit 的构建口径一致。
if [[ -d "$HOME/.local/share/sdks/MacOSX.minimal/latest" ]]; then
  export SDKROOT="$HOME/.local/share/sdks/MacOSX.minimal/latest"
fi

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) CJO="darwin_aarch64_cjnative" ;;
  *)     CJO="$(ls "$CANGJIE_HOME/runtime/lib" | grep -m1 "^darwin_")" ;;
esac

export DYLD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/$CJO:$CANGJIE_HOME/tools/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
export LD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/$CJO:$CANGJIE_HOME/tools/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ⚠️ 上面所有 `$VAR` 紧跟中文时都必须写成 `${VAR}`：
# bash 在 UTF-8 locale 下会把多字节字符的**首字节**当成变量名的合法延续，
# 于是 `$DEEPGIT_BIN（仓库内）` 变成对 `DEEPGIT_BIN<首字节>` 的展开，
# 在 `set -u` 下直接以「unbound variable」退出。报错信息里那个乱码字符就是它。
cd "$HERE"
cjpm build

# 引擎定位顺序：DEEPGIT_BIN → 仓内 release → PATH 上的 moongit / deepgit。
# 开发时直接指向仓内构建，省得先跑一遍 install.sh。
if [[ -z "${DEEPGIT_BIN:-}" ]]; then
  REPO_BIN="$HERE/../../moonGit/target/release/bin/main"
  if [[ -x "$REPO_BIN" ]]; then
    export DEEPGIT_BIN="$REPO_BIN"
    echo "› 引擎：${DEEPGIT_BIN}（仓内构建）"
  else
    echo "› 引擎：走 PATH 查找 moongit / deepgit"
  fi
else
  echo "› 引擎：${DEEPGIT_BIN}"
fi

# --profile 透传：CUI 的帧耗时统计，排查「窗口空着」这类问题用得上
# （本机 screencapture 抓不到 CUI 的 Metal 窗口，profile 是可靠的读数路径）。
exec ./target/release/bin/main "$@"
