#!/usr/bin/env bash
# 跳过构建直接启动（仅本机开发用；正式入口是 scripts/run.sh）。
#
# 为什么要单独一个脚本：`run.sh` 每次都 `cjpm build`，一次两分钟，
# 而反复调界面布局时改一行就要等两分钟。加上 `timeout` 更不能用 run.sh
# （build 阶段就把时间用光了）。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 仓颉运行时环境与 SDK 定位，与 run.sh / ai-e2e.sh 共用 cj-env.sh。
# SDK 走两级探测（$CANGJIE_HOME/envsetup.sh → $CANGJIE_HOME/cangjie/envsetup.sh），
# 本机解包的 SDK 根多套一层 cangjie/，老的单一默认值 source 直接挂。
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/cj-env.sh"
dd_cj_pre_source
dd_cj_locate_sdk
# shellcheck disable=SC1091
source "$CANGJIE_HOME/envsetup.sh"

if [[ -d "$HOME/.local/share/sdks/MacOSX.minimal/latest" ]]; then
  export SDKROOT="$HOME/.local/share/sdks/MacOSX.minimal/latest"
fi

dd_cj_setup_runtime

# SDL3 动态库：仓内 vendor 里那份（ci-local.sh 解包的用户空间 SDL3），
# 与构建时链的是同一个。macOS 走 DYLD_LIBRARY_PATH；Linux 走 LD_LIBRARY_PATH
# —— 没有系统 SDL3 包的机器上，没有这行产物起不来。
export DYLD_LIBRARY_PATH="$HERE/vendor/CangjieSDL/.sdl3:$DYLD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$HERE/vendor/CangjieSDL/.sdl3:$LD_LIBRARY_PATH"

if [[ -z "${DEEPGIT_BIN:-}" ]]; then
  REPO_BIN="$HERE/../../moonGit/target/release/bin/main"
  if [[ -x "$REPO_BIN" ]]; then
    export DEEPGIT_BIN="$REPO_BIN"
  fi
fi

# models.dev 目录快照注入：与 run.sh 同一套（ai_catalog.cj 的候选链第一位）；
# 用户已显式指定时不覆盖，仓内快照不在时不指死路。
if [[ -z "${DEEPDOLPHIN_MODELS:-}" && -e "$HERE/../assets/models/models-dev.json" ]]; then
  export DEEPDOLPHIN_MODELS="$HERE/../assets/models/models-dev.json"
fi

cd "$HERE"
# 绝对路径 exec：argv[0] 必须以 `/` 开头，自启入口才上溯得出 scripts/run.sh
# （见 run.sh 末行注释；源码扫描判据两头钉住这一行）。
exec "$HERE/target/release/bin/main" "$@"
