#!/usr/bin/env bash
# package-device.sh —— 构建本设备的安装包：客户端 deb + **捆绑 Cambium 引擎**（二进制 + 仓颉运行时 + 启动器）。
#
# 为什么要有它：装一个客户端就该拿到全部能力（2026-11-28 用户）。引擎从本机已装的 Cambium 取
# （~/.local/libexec/cambium/cambium.bin + ~/.local/runtime；ENGINE_BIN / ENGINE_RUNTIME 可覆盖），
# 注入 deb 的 /opt/canopy/engine/ 后原样重打（DEBIAN/ 控制元数据不动）。装机后：
#   · 设置 → AI Agent 集成 → 「安装 CLI」把捆绑引擎挂到 ~/.local/bin/cambium（PATH 上，agent 直接可用）；
#   · 同页可把 cambium mcp 注册进 Claude Code / Codex 的配置、把 SKILL.md 装进 agent 技能目录
#     （canopy/agent/AgentIntegration.kt，改用户配置前自动留 .bak-before-cambium 备份）。
# 用法：scripts/package-device.sh            # 打包 + 重打 deb（不安装）
#       scripts/package-device.sh --install  # 打包后交给 scripts/install-user.sh 装到本机
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # client/
export JAVA_HOME="$(ls -d "$HOME"/.local/jdk/jdk-21* 2>/dev/null | sort -V | tail -1)"
export PATH="$JAVA_HOME/bin:${GRADLE_HOME:-$HOME/.local/gradle/gradle-8.10.2}/bin:$PATH"

ENG_BIN="${ENGINE_BIN:-$HOME/.local/libexec/cambium/cambium.bin}"
RUNTIME="${ENGINE_RUNTIME:-$HOME/.local/runtime}"
[ -x "$ENG_BIN" ] || { echo "✗ 引擎二进制不可执行：$ENG_BIN（先装 Cambium 引擎，或用 ENGINE_BIN= 指定）"; exit 1; }
[ -d "$RUNTIME" ] || { echo "✗ 引擎运行时缺失：$RUNTIME（用 ENGINE_RUNTIME= 指定）"; exit 1; }

echo "› gradle packageDeb"
( cd "$HERE" && gradle packageDeb -q )
DEB=$(ls -t "$HERE"/build/compose/binaries/main/deb/canopy_*.deb | grep -v -- "-with-engine" | head -1)
[ -n "$DEB" ] || { echo "✗ packageDeb 没产出 deb"; exit 1; }
echo "  $DEB  $(du -h "$DEB" | cut -f1)"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
# --raw-extract 保留 DEBIAN/ 控制目录：重打出来的包元数据（包名/版本/依赖/脚本）与原包一致
dpkg-deb --raw-extract "$DEB" "$STAGE"

E="$STAGE/opt/canopy/engine"
mkdir -p "$E/bin"
cp "$ENG_BIN" "$E/cambium.bin"
cp -r "$RUNTIME" "$E/runtime"
cat > "$E/bin/cambium-engine" <<'LAUNCH'
#!/usr/bin/env bash
# Canopy 应用镜像捆绑的 Cambium 引擎（客户端「设置 → AI Agent 集成」会把它挂到 ~/.local/bin/cambium）。
DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
exec env LD_LIBRARY_PATH="$DIR/runtime${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$DIR/cambium.bin" "$@"
LAUNCH
chmod +x "$E/bin/cambium-engine"

OUT="${DEB%.deb}-with-engine.deb"
dpkg-deb --root-owner-group -b "$STAGE" "$OUT"
echo "✓ $OUT  $(du -h "$OUT" | cut -f1)"
echo "  校验："; dpkg-deb -c "$OUT" | grep -E "engine/(bin/cambium-engine|cambium.bin|runtime/$|runtime/lib)" | head -5

if [ "${1:-}" = "--install" ]; then
  echo "› scripts/install-user.sh（装最新 deb = 捆绑引擎版）"
  bash "$HERE/scripts/install-user.sh" "$OUT"
fi
