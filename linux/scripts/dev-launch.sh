#!/usr/bin/env bash
# 跳过构建直接启动（仅本机开发用；正式入口是 scripts/run.sh）。
#
# 为什么要单独一个脚本：`run.sh` 每次都 `cjpm build`，一次两分钟，
# 而反复调界面布局时改一行就要等两分钟。加上 `timeout` 更不能用 run.sh
# （build 阶段就把时间用光了）。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export CANGJIE_HOME="${CANGJIE_HOME:-$HOME/.local/share/cangjie/current}"
export DYLD_LIBRARY_PATH="${DYLD_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
# shellcheck disable=SC1091
source "$CANGJIE_HOME/envsetup.sh"

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

# SDL3 动态库：仓内 vendor 里那份，与构建时链的是同一个。
export DYLD_LIBRARY_PATH="$HERE/vendor/CangjieSDL/.sdl3:$DYLD_LIBRARY_PATH"

if [[ -z "${DEEPGIT_BIN:-}" ]]; then
  REPO_BIN="$HERE/../../moonGit/target/release/bin/main"
  if [[ -x "$REPO_BIN" ]]; then
    export DEEPGIT_BIN="$REPO_BIN"
  fi
fi

cd "$HERE"
exec ./target/release/bin/main "$@"
