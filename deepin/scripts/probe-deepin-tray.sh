#!/usr/bin/env bash
# probe-deepin-tray.sh — **端到端**判据：deepin 托盘窗口协议到底通没通。
#
# 【为什么要有它 —— 判据分层】
#   `--selfcheck` 跑在 QApplication 构造**之前** ⇒ 没有总线、没有 X11 ⇒ 测不了
#   「我们的图标窗口有没有被 deepin 的托盘托管方认领」。
#   ⇒ 判据必须**从总线/X11 另一端**看（外部进程 `gdbus` / `xprop`）。
#
# 【判据（三步，各自独立）】
#   ⓪ 应用自报走的后端是 `deepin-window`（自动选路对不对）
#   ① 应用自报「已认领」——它自己先调过 daemon 的 `GetName` 才敢这么说
#      （这步等价于「daemon 认得我们是谁」）；
#   ② 我们的窗口 id 出现在 `org.deepin.dde.TrayManager1.TrayIcons` 里
#      （= daemon 确实登记了它）；
#   ③ 该窗口的 `WM_NAME` 是我们的名字（= 这个 id 确实是我们的窗口，不是别的窗口）。
#   ⚠ **判据不看「图标有没有画出来」**：本机 deepin 25 的托盘图标渲染本身是坏的
#     （连 cc-switch / clash-verge 也只显示空的深灰占位圆）⇒ 那个信号不可采信。
#     端到端像素验收要等真机/容器。
#   ⚠ ① 与 ② 之间有**时间差**（daemon 登记与属性发布不是同一瞬间）⇒ 分开判、
#     各自重试，不要合成一次判断（负控实测：合成一次会偶发假红）。
#
# 【用法】sh scripts/probe-deepin-tray.sh [程序路径]
#   退出码 0 = 通过；非 0 = 失败（stderr 里有原因）。
set -uo pipefail

SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
APP="${2:-$SRC/build/deepDolphin}"
TRAY_SERVICE="org.deepin.dde.TrayManager1"
TRAY_PATH="/org/deepin/dde/TrayManager1"
EXPECT_NAME="deepDolphin"
LOG=/tmp/probe-deepin-tray.app.log

fail() { echo "✗ $1" >&2; exit 1; }

[ -x "$APP" ] || fail "程序不存在或不可执行：$APP"

# ① 图形会话（无 DISPLAY ⇒ 托盘窗口根本不存在）
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    fail "没有图形会话（DISPLAY/WAYLAND_DISPLAY 都空）"
fi

# ② 托管方在不在（不在 ⇒ 这台机器不是 deepin 式托盘 ⇒ 判据不适用）
if ! gdbus call --session --dest "$TRAY_SERVICE" --object-path "$TRAY_PATH" \
        --method org.freedesktop.DBus.Introspectable.Introspect >/dev/null 2>&1; then
    fail "没有 $TRAY_SERVICE 服务（这不是 deepin 式托盘？判据不适用）"
fi

# ③ 起程序
#   ⚠ **不强制后端** —— 这个探针要验的正是「DDE 上自动选得对不对」
#   （强制了就只是在验那条路本身通不通，验不到「选路」这一层）。
rm -f "$LOG"
"$APP" >"$LOG" 2>&1 &
APP_PID=$!
cleanup() { kill "$APP_PID" 2>/dev/null; }
trap cleanup EXIT

# ③' 应用自报走的是哪条路（自动选的结果必须是 deepin 窗口协议）
BACKEND=""
for _ in $(seq 1 60); do
    if [ -f "$LOG" ]; then
        BACKEND="$(sed -n 's/.*托盘后端 = \([a-z-]*\).*/\1/p' "$LOG" | head -1)"
        [ -n "$BACKEND" ] && break
    fi
    sleep 0.25
done
[ "$BACKEND" = "deepin-window" ] \
    || fail "应用自报的后端是 '${BACKEND:-<没报>}'，期望 'deepin-window'（DDE 上应自动选窗口协议）"

# ④ 等应用自报「已认领」（应用自己先验过 daemon 的 GetName 才打这行）
WID_HEX=""
for _ in $(seq 1 60); do
    if [ -f "$LOG" ]; then
        WID_HEX="$(sed -n 's/.*已认领，窗口 id = "\(0x[0-9a-f]*\)".*/\1/p' "$LOG" | head -1)"
        [ -n "$WID_HEX" ] && break
    fi
    sleep 0.25
done
[ -n "$WID_HEX" ] || fail "应用没报「已认领」——daemon 的 GetName 认不出我们的窗口（见 $LOG）"

WID=$((WID_HEX))

# ⑤ 窗口 id 在 TrayIcons 里吗
IN_LIST=0
for _ in $(seq 1 20); do
    if gdbus call --session --dest "$TRAY_SERVICE" --object-path "$TRAY_PATH" \
            --method org.freedesktop.DBus.Properties.Get "$TRAY_SERVICE" TrayIcons 2>/dev/null \
        | grep -q "$WID"; then
        IN_LIST=1
        break
    fi
    sleep 0.25
done
[ "$IN_LIST" = "1" ] || fail "窗口 $WID_HEX 不在 TrayIcons 里（daemon 没登记它）"

# ⑥ X 侧核对：这个 id 确实是我们的窗口
WM="$(xprop -id "$WID" WM_NAME 2>/dev/null | sed -n 's/.*= "\(.*\)"$/\1/p' | head -1)"
[ "$WM" = "$EXPECT_NAME" ] || fail "窗口 $WID_HEX 的 WM_NAME 是 '$WM'，期望 '$EXPECT_NAME'"

# ⑦ 旁证：daemon 侧此刻也认得它
DNAME="$(gdbus call --session --dest "$TRAY_SERVICE" --object-path "$TRAY_PATH" \
    --method "$TRAY_SERVICE.GetName" "$WID" 2>/dev/null | sed -n "s/^('\(.*\)',)$/\1/p" | head -1)"

echo "✓ deepin 托盘窗口协议端到端：窗口 $WID_HEX 已被 daemon 认领"
echo "  （WM_NAME='$WM'；daemon GetName='${DNAME:-<此刻未认出>}'；窗口在 TrayIcons 里 ✓）"
exit 0
