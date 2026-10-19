#!/usr/bin/env bash
# probe-sni-icon.sh — **端到端**判据：总线上我们的 SNI 项的 IconPixmap 像素是不是真图。
#
# 【为什么要有它 —— 判据分层】
#   `--selfcheck` 跑在 QApplication 构造**之前** ⇒ 没有总线 ⇒ 测不了「字节有没有被编坏」。
#   而 `QDBusArgument` 一旦写入就是**只写**的（「read from a write-only object」）
#   ⇒ 同一份数据在进程内**读不回来** ⇒ 字节级判据只能**从总线另一端**看。
#   ⇒ 本脚本用**外部进程**（gdbus）读我们自己的项，统计 IconPixmap 的非零字节数。
#
# 【判据】
#   · 应用自报的**后端**必须确实是 `sni`（强制开关生效了 ⇒ 走的就是要验的那条路）
#   · 必须能读到项（服务名 + 对象路径都在）
#   · IconPixmap 必须是 **32×32**（我们的图标画布）
#   · 字节总数必须 = 32×32×4（ARGB32、每像素 4 字节、不补行对齐）
#   · **非零字节必须 > 0** —— 全 0 就是「一张透明图」⇒ 宿主拿到空图 ⇒ 托盘里不画它
#     （实测踩过这个坑：圆形图标的**边缘像素本来就是透明的**，
#       只看开头几行会误判成「全 0」—— 必须统计**整张图**的非零字节数。）
#
# 【为什么要「强制 SNI」】
#   批 Y 实测：DDE 25 上自动选的是 **deepin 托盘窗口协议**（`_NET_SYSTEM_TRAY_S0`
#   选区在场）⇒ SNI 那条路**根本不会被走** ⇒ 不强制的话本机上这个判据**永远假红**
#   （SNI 服务不上线）。⇒ 用环境变量 `DEEPDOLPHIN_TRAY_BACKEND=sni` 显式强制，
#   并**核对应用自报的后端**（强制开关被忽略 ⇒ 判据必须红）。
#
# 【用法】sh scripts/probe-sni-icon.sh [程序路径]
#   退出码 0 = 通过；非 0 = 失败（stderr 里有原因）。
set -uo pipefail

SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
APP="${2:-$SRC/build/deepDolphin}"
SERVICE="org.deepin.deepDolphin"
OBJPATH="/StatusNotifierItem"
LOG=/tmp/probe-sni-icon.app.log

fail() { echo "✗ $1" >&2; exit 1; }

[ -x "$APP" ] || fail "程序不存在或不可执行：$APP"

# ① 起程序（要有图形会话；离屏/无 DISPLAY 时这层就没有托盘可言）
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    fail "没有图形会话（DISPLAY/WAYLAND_DISPLAY 都空）"
fi
# ⚠ **强制走 SNI 那条路**（理由见文件头「为什么要强制 SNI」）
DEEPDOLPHIN_TRAY_BACKEND=sni "$APP" >"$LOG" 2>&1 &
APP_PID=$!
cleanup() { kill "$APP_PID" 2>/dev/null; }
trap cleanup EXIT

# ② 应用自报走的是哪条路（强制开关生效了吗）
BACKEND=""
for _ in $(seq 1 50); do
    if [ -f "$LOG" ]; then
        BACKEND="$(sed -n 's/.*托盘后端 = \([a-z-]*\).*/\1/p' "$LOG" | head -1)"
        [ -n "$BACKEND" ] && break
    fi
    sleep 0.2
done
[ "$BACKEND" = "sni" ] \
    || fail "应用没走 SNI 那条路（自报 '${BACKEND:-<没报>}'）—— 强制开关可能失效了，见 $LOG"

# ③ 等服务名上线（最多 10s）
for _ in $(seq 1 50); do
    if gdbus call --session --dest "$SERVICE" --object-path "$OBJPATH" \
        --method org.freedesktop.DBus.Introspectable.Introspect >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done
gdbus call --session --dest "$SERVICE" --object-path "$OBJPATH" \
    --method org.freedesktop.DBus.Introspectable.Introspect >/dev/null 2>&1 \
    || fail "服务 $SERVICE 没上线（程序没起来？见 $LOG）"

# ④ 读 IconPixmap 并统计（外部进程 ⇒ 走的是真实总线）
OUT="$(gdbus call --session --dest "$SERVICE" --object-path "$OBJPATH" \
    --method org.freedesktop.DBus.Properties.Get org.kde.StatusNotifierItem IconPixmap 2>&1)" \
    || fail "读 IconPixmap 失败：$OUT"

RES="$(printf '%s' "$OUT" | python3 -c '
import re, sys
text = sys.stdin.read()
m = re.search(r"\((\d+), (\d+), \[(.*?)\]\)", text, re.S)
if not m:
    print("PARSE_FAIL\t" + text[:200].replace("\n", " "))
    raise SystemExit(0)
w, h, blob = int(m.group(1)), int(m.group(2)), m.group(3)
byts = [int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]{2})", blob)]
nz = sum(1 for b in byts if b != 0)
print(f"{w}\t{h}\t{len(byts)}\t{nz}")
')"

case "$RES" in
    PARSE_FAIL*) fail "解析 IconPixmap 失败：${RES#PARSE_FAIL	}" ;;
esac

W=$(printf '%s' "$RES" | cut -f1)
H=$(printf '%s' "$RES" | cut -f2)
N=$(printf '%s' "$RES" | cut -f3)
NZ=$(printf '%s' "$RES" | cut -f4)

[ "$W" = "32" ] || fail "IconPixmap 宽度是 $W，期望 32（我们的图标画布）"
[ "$H" = "32" ] || fail "IconPixmap 高度是 $H，期望 32（我们的图标画布）"
[ "$N" = "4096" ] || fail "IconPixmap 字节数是 $N，期望 4096（32×32×4，ARGB32 不补行对齐）"
[ "${NZ:-0}" -gt 0 ] || fail "IconPixmap 整张图**非零字节为 0** ⇒ 宿主拿到的是一张透明图 ⇒ 托盘里不会画它"

echo "✓ SNI IconPixmap 端到端：32×32 / 4096 字节 / 非零 $NZ 字节（真图，不是透明图）"
exit 0
