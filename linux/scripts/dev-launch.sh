#!/usr/bin/env bash
# 跳过构建直接启动（仅本机开发用；正式入口是 scripts/run.sh）。
#
# 为什么要单独一个脚本：`run.sh` 每次都 `cjpm build`，一次两分钟，
# 而反复调界面布局时改一行就要等两分钟。加上 `timeout` 更不能用 run.sh
# （build 阶段就把时间用光了）。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export CANGJIE_HOME="${CANGJIE_HOME:-$HOME/.local/share/cangjie/current}"
# 仓颉运行时环境。**逻辑在 cj-env.sh 里**，与 run.sh 共用同一份 ——
# 原来两处各抄一遍，而两遍都写错了 Linux 分支（见 cj-env.sh 顶部注释）。
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/cj-env.sh"
dd_cj_pre_source
# shellcheck disable=SC1091
source "$CANGJIE_HOME/envsetup.sh"

if [[ -d "$HOME/.local/share/sdks/MacOSX.minimal/latest" ]]; then
  export SDKROOT="$HOME/.local/share/sdks/MacOSX.minimal/latest"
fi

dd_cj_setup_runtime

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
