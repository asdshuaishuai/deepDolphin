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

# 仓颉运行时环境与 SDK 定位。**逻辑都在 cj-env.sh 里**，dev-launch.sh /
# ai-e2e.sh 用同一份。SDK 走两级探测（$CANGJIE_HOME/envsetup.sh →
# $CANGJIE_HOME/cangjie/envsetup.sh）：本机解包的 SDK 根多套一层 cangjie/，
# 老的单一默认值在这台机器上 source 不到 envsetup.sh，第一行就退出。
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/cj-env.sh"
dd_cj_pre_source
dd_cj_locate_sdk
# shellcheck disable=SC1091
source "$CANGJIE_HOME/envsetup.sh"

# ci-local.sh 装的 ld 链接包装器（crt 缺口修补，见 ci-local.sh 头注释）存在就挂上
# PATH：本机系统 ld 解析不了裸 crtbeginS.o，没有它 cjpm build 链接必挂。
# 没有这个文件的机器（系统工具链健全）不受影响。
if [[ -x "$HOME/.local/bin/ld" ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

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

dd_cj_setup_runtime

# SDL3 用户空间库（ci-local.sh 解包到 vendor/CangjieSDL/.sdl3）。本机没有系统
# SDL3 包，产物的 DT_NEEDED 靠这个路径解析；系统装了 SDL3 的机器上这个前缀
# 多余但无害（与 ci-local.sh 的 LD_LIBRARY_PATH 同一顺序：.sdl3 的 3.2.10
# 必须先于任何混入 3.4.x 的目录被找到，3.4 要 glibc 2.43）。
SDL3DIR="$HERE/vendor/CangjieSDL/.sdl3"
if [[ -e "$SDL3DIR/libSDL3.so.0" ]]; then
  export LD_LIBRARY_PATH="$SDL3DIR:$LD_LIBRARY_PATH"
fi

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
