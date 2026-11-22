#!/usr/bin/env bash
# run.sh —— 启动 CMP 客户端（gradle run，需要 DISPLAY）。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export JAVA_HOME="$(ls -d "$HOME"/.local/jdk/jdk-21* 2>/dev/null | sort -V | tail -1)"
export PATH="$JAVA_HOME/bin:$HOME/.local/gradle/gradle-8.10.2/bin:$PATH"
: "${DISPLAY:=:0}"; export DISPLAY
cd "$HERE"
exec gradle run
