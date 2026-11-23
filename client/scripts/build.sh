#!/usr/bin/env bash
# build.sh —— CMP 客户端编译与判据门禁。产物：build/libs/… 或 gradle run 直接启动。
#
# 前置：JDK 21 + Gradle（本机装在 ~/.local/jdk 与 ~/.local/gradle，见仓库 docs）。
# 用法：scripts/build.sh            # 编译（gradle build）
#       scripts/build.sh --test     # 编译 + 全量判据（jvmTest），末行输出
#       CMPTEST_SUMMARY passed=N skipped=S failed=M
#       scripts/build.sh --run      # 编译后真窗口启动（需 DISPLAY）
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export JAVA_HOME="$(ls -d "$HOME"/.local/jdk/jdk-21* 2>/dev/null | sort -V | tail -1)"
export PATH="$JAVA_HOME/bin:$HOME/.local/gradle/gradle-8.10.2/bin:$PATH"
: "${JAVA_HOME:?未找到 JDK 21（~/.local/jdk/jdk-21*）}"

cd "$HERE"
echo "› 编译中（gradle build）…"
gradle build
echo "✓ 编译通过"

if [ "${1:-}" = "--run" ]; then
  echo "› 启动（DISPLAY=${DISPLAY:-:0}）…"
  exec gradle run
fi

if [ "${1:-}" = "--test" ]; then
  echo "› 全量判据（jvmTest）…"
  gradle jvmTest
  PASSED="$(grep -hoE 'tests="[0-9]+"' build/test-results/jvmTest/TEST-*.xml | grep -oE '[0-9]+' | paste -sd+ | bc 2>/dev/null || echo 0)"
  FAILED="$(grep -hoE 'failures="[0-9]+"' build/test-results/jvmTest/TEST-*.xml | grep -oE '[0-9]+' | paste -sd+ | bc 2>/dev/null || echo 1)"
  SKIPPED="$(grep -hoE 'skipped="[0-9]+"' build/test-results/jvmTest/TEST-*.xml | grep -oE '[0-9]+' | paste -sd+ | bc 2>/dev/null || echo 0)"
  echo "CMPTEST_SUMMARY passed=$PASSED skipped=$SKIPPED failed=$FAILED"
  [ "$FAILED" = "0" ] || { echo "✗ 有失败用例" >&2; exit 1; }
  exit 0
fi
