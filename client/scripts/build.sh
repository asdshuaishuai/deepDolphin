#!/usr/bin/env bash
# build.sh —— BUI→CMP 客户端编译。产物：build/libs/… 或 gradle run 直接启动。
#
# 前置：JDK 21 + Gradle（本机装在 ~/.local/jdk 与 ~/.local/gradle，见仓库 docs）。
# 用法：scripts/build.sh [--run]      # --run 编译后真窗口启动（需 DISPLAY）
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export JAVA_HOME="$(ls -d "$HOME"/.local/jdk/jdk-21* 2>/dev/null | sort -V | tail -1)"
export PATH="$JAVA_HOME/bin:$HOME/.local/gradle/gradle-8.10.2/bin:$PATH"
: "${JAVA_HOME:?未找到 JDK 21（~/.local/jdk/jdk-21*）}"

cd "$HERE"
echo "› 编译中（gradle build，首次会下载依赖）…"
gradle build
echo "✓ 编译通过"
if [ "${1:-}" = "--run" ]; then
  echo "› 启动（DISPLAY=${DISPLAY:-:0}）…"
  exec gradle run
fi
