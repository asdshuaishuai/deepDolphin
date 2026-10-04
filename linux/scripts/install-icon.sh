#!/usr/bin/env bash
# install-icon.sh —— 把 deepDolphin 的应用图标装进当前用户的桌面环境。
#
# 装的是**仓库根公共资源**里生成好的产物（assets/icon/out/linux/），
# 本脚本不生成、不修改任何像素 —— 那是 make-icons.py 的活。
# 平台侧只负责「把公共产物摆到桌面环境约定找它的位置」。
#
# 装到用户目录（~/.local/share）而不是 /usr/share：不需要 root，
# 也不会污染系统。KDE/GNOME/XFCE 都会在 `~/.local/share/icons` 里找
# hicolor 主题，优先级仅次于系统目录。
#
# 依赖桌面环境的缓存刷新：
#   - 图标缓存：多数环境监听目录变化，不刷新也能生效；`gtk-update-icon-cache`
#     存在时显式跑一次，稳一手。
#   - .desktop 缓存：必须刷新，否则启动器仍显示旧条目。
#     `update-desktop-database` 没有就跳过（很多精简环境没装）。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # → 仓库根
ICON_SRC="$HERE/assets/icon/out/linux"
APP_ID="deepdolphin"
APP_NAME="deepDolphin"

ICON_DST="$HOME/.local/share/icons/hicolor"
APPS_DST="$HOME/.local/share/applications"
DESKTOP_DST="$APPS_DST/$APP_ID.desktop"

# .desktop 的 Exec 指向仓内包装脚本而不是二进制本体。
# 仓颉产物靠 rpath 找 libstdcangjie-runtime，直接在 .desktop 里写二进制路径
# 的话，图标能点开但一启动就 dyld 报错 —— 那症状很难联想到是 .desktop 写错了。
RUN_SH="$HERE/linux/scripts/run.sh"

MODE="install"
if [[ "${1:-}" == "--uninstall" ]]; then
  MODE="uninstall"
fi

if [[ ! -d "$ICON_SRC/hicolor" ]]; then
  echo "✗ 找不到图标产物：$ICON_SRC/hicolor" >&2
  echo "  先跑：python3 assets/icon/make-icons.py" >&2
  exit 1
fi

if [[ "$MODE" == "uninstall" ]]; then
  # 逐档删而不是 rm -rf 整个 hicolor —— 那个目录属于用户，可能还有别的图标。
  while IFS= read -r f; do
    rm -f "$f"
  done < <(find "$ICON_DST" -path "*/apps/$APP_ID.png" -type f 2>/dev/null)
  # 只删空目录，一路由下往上，避免删掉用户自己的目录
  find "$ICON_DST" -type d -empty -delete 2>/dev/null || true
  rm -f "$DESKTOP_DST"
  command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$APPS_DST" 2>/dev/null || true
  echo "✓ 已卸载 $APP_ID 的图标与桌面条目"
  exit 0
fi

echo "› 装图标 → $ICON_DST"
mkdir -p "$ICON_DST"
count=0
while IFS= read -r f; do
  # hicolor 目录结构自带尺寸（16x16/…），原样搬运，不能压平成一个目录。
  rel="${f#"$ICON_SRC"/hicolor/}"          # 16x16/apps/deepdolphin.png
  dst="$ICON_DST/$rel"
  mkdir -p "$(dirname "$dst")"
  cp "$f" "$dst"
  count=$((count + 1))
done < <(find "$ICON_SRC/hicolor" -name "$APP_ID.png" -type f)
echo "  · $count 个尺寸"

echo "› 装桌面条目 → $DESKTOP_DST"
mkdir -p "$APPS_DST"
# Exec= 的值按 freedesktop Desktop Entry 规范整参数加双引号：run.sh 路径
# 含空格或 & | ; 这类分隔符时，不加引号会被会话按分隔符切开 —— 与
# linux/src/sysint.cj 的 escapeDesktopExec 是同一条规则（那边管自启条目，
# 这边管启动器条目），两处写法不能分叉。
EXEC_VALUE="\"$RUN_SH\""
sed "s|^Exec=__EXEC__|Exec=$EXEC_VALUE|" "$ICON_SRC/$APP_ID.desktop" > "$DESKTOP_DST"
chmod +x "$DESKTOP_DST"
# 落盘校验：Exec 行必须逐字节等于我们想写的内容。模板改了占位符、
# 或 sed 没命中时，这里当场报 —— 不能让安装器装作成功，
# 留一个指向上一次路径（或占位符）的条目给启动器。
if ! grep -Fqx "Exec=\"$RUN_SH\"" "$DESKTOP_DST"; then
  echo "✗ .desktop 的 Exec= 行没写对（期望：Exec=\"$RUN_SH\"）：" >&2
  grep -n '^Exec=' "$DESKTOP_DST" >&2 || echo "  （写出的文件里连 Exec= 行都没有）" >&2
  exit 1
fi

# 图标名、.desktop 文件名、SDL app_id 必须同名，否则任务栏没有图标。
# 这里查一次，别等到"图标不显示"再去猜是哪一环对不上。
icon_name="$(sed -n 's/^Icon=//p' "$DESKTOP_DST")"
if [[ "$icon_name" != "$APP_ID" ]]; then
  echo "✗ .desktop 的 Icon= 是 '$icon_name'，与图标文件名 '$APP_ID' 不一致" >&2
  echo "  桌面环境会找不到图标。重跑：python3 assets/icon/make-icons.py" >&2
  exit 1
fi
if ! grep -q "AppMetadata" "$HERE/linux/src/main.cj" 2>/dev/null; then
  echo "! 提醒：main.cj 里没有 AppMetadata，窗口不会向桌面环境报 app_id，" \
       "任务栏里可能不显示图标。" >&2
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$ICON_DST" >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS_DST" >/dev/null 2>&1 || true
fi

echo "✓ $APP_NAME 图标已装（Icon=${icon_name}，Exec=${RUN_SH}）"
echo "  找不到时先查缓存：gtk-update-icon-cache -f -t $ICON_DST"
