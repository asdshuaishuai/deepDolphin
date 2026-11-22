#!/usr/bin/env bash
# build.sh —— BUI 客户端编译（Release）。产物：target/release/deepdolphin-client。
#
# 典型功能测试动线：
#   scripts/build.sh                 # 编译（首次会自举链接环境）
#   scripts/build.sh --test          # 编译后顺带跑全量判据（cargo test）
#   scripts/run.sh                   # 启动（真窗口，需要图形会话 DISPLAY=:0）
#
# 环境说明：需要 Rust 工具链（rustup/cargo）与一个能用的 C 编译器。
# 本机（deepin 25，无系统 cc）由本脚本自举 ~/.local/bin/cc：指向
# dd-sysroot 的 x86_64-linux-gnu-gcc-13（**真 C 驱动**；不能像 ~/.local/bin/gcc
# 那样指向 g++ 驱动——cmake 的 C 编译器 ABI 探测会判 broken）。
# blenderui 0.5 的 C 部分（blenderui-sys）经 cmake 编译，依赖 cmake + cc；
# X11 宿主运行期用系统 libX11/libGL（本机已具备）。

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$HERE/target/release/deepdolphin-client"

# ── 自举 cc（幂等）：已有可用 cc 就跳过 ──
if ! command -v cc >/dev/null 2>&1; then
    CRT="$(ls -d "$HOME"/.local/dd-sysroot/usr/lib/gcc/x86_64-linux-gnu/*/ 2>/dev/null | sort -V | tail -1 || true)"
    [ -n "$CRT" ] || { echo "✗ 找不到可用的 C 编译器（无 cc 且无 dd-sysroot GCC）" >&2; exit 1; }
    echo "› 自举 ~/.local/bin/cc（dd-sysroot gcc-13 真驱动）…"
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/cc" <<WRAPPER
#!/bin/sh
export LD_LIBRARY_PATH="$HOME/.local/dd-sysroot/usr/lib/x86_64-linux-gnu\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$HOME/.local/dd-sysroot/usr/bin/x86_64-linux-gnu-gcc-13" -B"${CRT}" -B"$HOME/.local/dd-sysroot/usr/bin/x86_64-linux-gnu-" -L"$HOME/.local/dd-sysroot/usr/lib/x86_64-linux-gnu" -isystem "${CRT}include" -isystem "$HOME/.local/dd-sysroot/usr/include" -isystem "$HOME/.local/dd-sysroot/usr/include/x86_64-linux-gnu" "\$@"
WRAPPER
    chmod +x "$HOME/.local/bin/cc"
fi

echo "› 编译中（cargo build --release）…"
cd "$HERE"
cargo build --release

[[ -x "$BIN" ]] || { echo "✗ 编译成功但找不到产物：$BIN" >&2; exit 1; }
echo "✓ 产物：$BIN"

if [ "${1:-}" = "--test" ]; then
    cargo test --release
fi
