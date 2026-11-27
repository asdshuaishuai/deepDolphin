#!/usr/bin/env bash
# install-user.sh —— 把打好的客户端装到**用户目录**（不需要 root）。
#
# 【为什么要有它】系统级安装是 deb（/opt/canopy，要 sudo）。没有 root、或者不想动系统的机器，照样该用得上
# 打包态——开机自启、应用菜单项、命令行入口这些只有打包态才有（gradle run 没有客户端入口）。引擎在本机
# 也是这么装的（~/.local/bin/cambium）。
#
# 【装到哪】
#   ~/.local/opt/canopy/                         应用镜像 = deb 里的 /opt/canopy 整个目录（jpackage 镜像可搬）
#   ~/.local/bin/canopy                          启动器：系统级装了 deb（/opt/canopy/bin/canopy）就用那份，否则用用户级的
#   ~/.local/share/applications/canopy.desktop   应用菜单项（只对当前用户）
# 配置（~/.config/canopy）、缓存（~/.cache/canopy）、引擎发现与系统级安装完全一样。以后装了 deb，启动器自动
# 改走系统级那份；想收掉用户级的这一份，`--uninstall`（不碰系统级的包、配置和缓存）。
#
# 【怎么用】
#   scripts/install-user.sh                 # 用 build/compose/binaries/main/deb/ 里最新的 deb（没有就先打一个）
#   scripts/install-user.sh path/to/x.deb   # 指定 deb
#   scripts/install-user.sh --uninstall     # 卸掉用户级的这三样
#
# 【不做的事】不碰 /opt、不跑 sudo、不动 ~/.config 与 ~/.cache；~/.local/bin/canopy 如果已存在又不是本脚本
# 写的（没有标记行），不覆盖——那是别人的东西，报错退出。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="$HOME/.local"
APP_DIR="$PREFIX/opt/canopy"
LAUNCHER="$PREFIX/bin/canopy"
DESKTOP_DIR="$PREFIX/share/applications"
DESKTOP="$DESKTOP_DIR/canopy.desktop"
MARKER="# canopy 启动器：由 client/scripts/install-user.sh 写入"
SYSTEM_LAUNCHER="/opt/canopy/bin/canopy"

owned() { [ -f "$1" ] && grep -qF -- "$MARKER" "$1"; }

uninstall() {
  if [ -L "$LAUNCHER" ] || { [ -e "$LAUNCHER" ] && ! owned "$LAUNCHER"; }; then
    echo "✗ $LAUNCHER 不是本脚本写的，留着没动" >&2
  elif [ -e "$LAUNCHER" ]; then
    rm -f "$LAUNCHER"; echo "  去掉 $LAUNCHER"
  fi
  if [ -e "$DESKTOP" ] && grep -qF "install-user.sh" "$DESKTOP"; then rm -f "$DESKTOP"; echo "  去掉 $DESKTOP"; fi
  if [ -d "$APP_DIR" ]; then rm -rf "$APP_DIR"; echo "  去掉 $APP_DIR"; fi
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
  echo "✓ 用户级的 Canopy 已卸掉（配置 ~/.config/canopy 与缓存 ~/.cache/canopy 没动）"
}

case "${1:-}" in
  --uninstall) uninstall; exit 0 ;;
  -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

# 运行中就不换文件：换到一半还要加载类，会起不来
if pgrep -f "$APP_DIR/bin/canopy" >/dev/null 2>&1; then
  echo "✗ Canopy 正从 $APP_DIR 运行，先退出它再装" >&2
  exit 1
fi

DEB="${1:-}"
if [ -z "$DEB" ]; then
  DEB="$(ls -t "$HERE"/build/compose/binaries/main/deb/*.deb 2>/dev/null | head -1 || true)"
  if [ -z "$DEB" ]; then
    echo "› 没有现成的 deb，先打一个（gradle packageDeb）…"
    export JAVA_HOME="$(ls -d "$HOME"/.local/jdk/jdk-21* 2>/dev/null | sort -V | tail -1)"
    export PATH="$JAVA_HOME/bin:$HOME/.local/gradle/gradle-8.10.2/bin:$PATH"
    : "${JAVA_HOME:?未找到 JDK 21（~/.local/jdk/jdk-21*）}"
    (cd "$HERE" && gradle packageDeb)
    DEB="$(ls -t "$HERE"/build/compose/binaries/main/deb/*.deb | head -1)"
  fi
fi
[ -f "$DEB" ] || { echo "✗ 找不到 deb：$DEB" >&2; exit 1; }
command -v dpkg-deb >/dev/null 2>&1 || { echo "✗ 需要 dpkg-deb（解包用，不需要 root）" >&2; exit 1; }

if { [ -e "$LAUNCHER" ] || [ -L "$LAUNCHER" ]; } && ! owned "$LAUNCHER"; then
  echo "✗ $LAUNCHER 已存在且不是本脚本写的——不覆盖。确认可以替换就先挪走它" >&2
  exit 1
fi

echo "› 解包 $(basename "$DEB")…"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
dpkg-deb -x "$DEB" "$STAGE"
[ -x "$STAGE/opt/canopy/bin/canopy" ] || { echo "✗ deb 里没有 /opt/canopy/bin/canopy，不是客户端的包" >&2; exit 1; }

# 整目录换：先放新的，再把旧的整个拿掉——中途失败也不会剩半个应用
mkdir -p "$PREFIX/opt" "$PREFIX/bin" "$DESKTOP_DIR"
rm -rf "$APP_DIR.new" "$APP_DIR.old"
mv "$STAGE/opt/canopy" "$APP_DIR.new"
if [ -d "$APP_DIR" ]; then mv "$APP_DIR" "$APP_DIR.old"; fi
mv "$APP_DIR.new" "$APP_DIR"
rm -rf "$APP_DIR.old"

cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
$MARKER。系统级装了 deb（/opt/canopy）就用那份。
if [ -x "$SYSTEM_LAUNCHER" ]; then exec "$SYSTEM_LAUNCHER" "\$@"; fi
exec "$APP_DIR/bin/canopy" "\$@"
EOF
chmod 755 "$LAUNCHER"

cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Canopy
GenericName=项目群进度引擎
Comment=Cambium 引擎的跨平台桌面客户端（Compose Multiplatform）
# 由 client/scripts/install-user.sh 写入（用户级，只对当前用户）
Exec="$APP_DIR/bin/canopy"
Icon=$APP_DIR/lib/canopy.png
Terminal=false
Categories=Development;
StartupWMClass=canopy-MainKt
EOF
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true

echo "✓ 装好了："
echo "  应用    $APP_DIR"
echo "  命令    $LAUNCHER$([ -x "$SYSTEM_LAUNCHER" ] && echo "（系统级有 /opt/canopy，启动器走那份）")"
echo "  菜单项  $DESKTOP"
case ":$PATH:" in
  *":$PREFIX/bin:"*) echo "  可以用了：canopy（或从应用菜单启动 Canopy）" ;;
  *) echo "  ⚠ $PREFIX/bin 不在 PATH 里：把 export PATH=\"\$HOME/.local/bin:\$PATH\" 加进 ~/.bashrc，或从应用菜单启动" ;;
esac
