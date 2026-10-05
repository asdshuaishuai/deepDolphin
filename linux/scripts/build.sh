#!/usr/bin/env bash
# build.sh —— Linux 客户端编译（含首次环境自举）。产物：target/release/bin/main。
#
# 典型功能测试动线：
#   scripts/build.sh                 # 环境自举（幂等）+ 编译
#   scripts/build.sh --test          # 编译后顺带跑全量判据（cjpm test）
#   scripts/run.sh                   # 启动（会再编译一次；真窗口，跟随会话 X11/Wayland）
#   scripts/dev-launch.sh            # 不编译快速重启（改界面后反复试时用）
#
# 环境说明：本机没有系统 SDL3 时，ci-local.sh 的 setup 会自举用户空间 SDL3
# （vendor/CangjieSDL/.sdl3）与链接包装器（~/.local/bin/ld），全部幂等；
# 有系统 SDL3 的机器上这些步骤自动空转。运行时的库路径由 run.sh /
# dev-launch.sh 注入，本脚本不用管。
#
# 引擎：DEEPGIT_BIN 或 PATH 里的 moongit 都行；都没有则面板进安装引导页。

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$HERE/target/release/bin/main"

# ── 环境自举（幂等）：vendor/、用户空间 SDL3、链接包装器 ──
bash "$HERE/scripts/ci-local.sh" setup

# ── 工具链（SDK 两级探测，与 run.sh / dev-launch.sh 同一份逻辑）──
# shellcheck disable=SC1091
source "$HERE/scripts/cj-env.sh"
dd_cj_pre_source
dd_cj_locate_sdk
# shellcheck disable=SC1091
source "$CANGJIE_HOME/envsetup.sh"

# 链接包装器（crt 缺口修补）在 PATH 上，同 run.sh
if [[ -x "$HOME/.local/bin/ld" ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

# SDL3 库路径（链接期 ld 要解析 libSDL3 的 DT_NEEDED：libsndio/libXss）：
# .sdl3 是 SDL 三件套本体，~/.local/sdl3 的两个目录是可选后端依赖。
# ⚠ 顺序敏感：.sdl3 的 3.2.10 必须先于任何混入 3.4.x 的目录（3.4 要
# glibc 2.43）——与 ci-local.sh / run.sh / dev-launch.sh 同一口径。
SDL3DIR="$HERE/vendor/CangjieSDL/.sdl3"
export LD_LIBRARY_PATH="$SDL3DIR:$HOME/.local/sdl3/ex32/usr/lib/x86_64-linux-gnu:$HOME/.local/sdl3/ex/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

echo "› 编译中（cjpm build）…"
cd "$HERE"
cjpm build

[[ -x "$BIN" ]] || { echo "✗ 编译成功但找不到产物：$BIN" >&2; exit 1; }
echo "✓ 产物：$BIN"

if [ "${1:-}" = "--test" ]; then
  bash "$HERE/scripts/ci-local.sh"
fi
