#!/usr/bin/env bash
# ci-platform-probe.sh — 平台探针的**正式断言**（从 ci.sh 第 4 门抽出，可单独跑）。
#
# 【为什么抽出来】这一门是**纯输出断言**：探针跑一次，输出若干 key=value，
#   门逐条核对「字段在不在、形状对不对、值之间自洽不自洽」。
#   单独成脚本有两个用处：
#   ① 真机回归时能只跑这一门（看平台事实）；
#   ② **负控**能精确打这一门（把探针的输出改坏 → 这一门必须红）——
#      门内嵌在 ci.sh 里时，负控得跑整条 CI 才看得到红。
#
# 用法：scripts/ci-platform-probe.sh <deepDolphin 二进制>
set -uo pipefail
BIN="${1:-}"
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    echo "✗ 用法：$0 <deepDolphin 二进制>" >&2
    exit 2
fi
PROBE_RC=0
PROBE_OUT="$("$BIN" --platform-probe)" || PROBE_RC=$?
printf '%s\n' "$PROBE_OUT"
if [ "$PROBE_RC" -ne 0 ]; then
    echo "✗ platform-probe 退出码 $PROBE_RC（要求 0）" >&2
    exit 1
fi
# ⚠ 批 BV：退出时 QApplication 必须**还活着**（事实行 appAlive）。
#   appAlive 为 0 ⇒ 探针的退出点在 app 作用域之外 ⇒ 析构 QApplication 会把静态
#   QCoreApplication::self 置空 ⇒ 后台线程（QDBusConnection / DConfigGlobalTh）
#   此刻正派发事件时，它第二次读 self 拿到 NULL ⇒ 空指针解引用 ⇒ **SIGSEGV**
#   （CI 偶发段错误的真身，core 取证坐实）。这一条把那个竞态**变成必红**。
APP_ALIVE="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^appAlive=//p')"
if [ "$APP_ALIVE" != "1" ]; then
    echo "✗ platform-probe 报 appAlive=${APP_ALIVE:-缺失}（要求 1：退出时 QApplication 必须还活着 ⇒ 后台线程派发事件才不会被空指针打死）" >&2
    exit 1
fi
if ! printf '%s\n' "$PROBE_OUT" | grep -q '^backend='; then
    echo "✗ platform-probe 输出缺 backend= 行" >&2
    exit 1
fi
# ⚠ 后端分档（批 V · M1-7）：探针必须报得出「X11 / Wayland / Other」。
#   报不出来 = 平台差异没有可见面 ⇒ 真机回归时「这台机器跑的是哪套后端」没人知道。
BACKEND_KIND="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^backendKind=//p')"
case "$BACKEND_KIND" in
    x11|wayland|other) ;;
    *)
        echo "✗ platform-probe 的 backendKind= 缺失或不是 x11/wayland/other（得到 '$BACKEND_KIND'）" >&2
        exit 1
        ;;
esac
# ⚠ 任务栏几何（批 V · M1-7）：四边边距必须是四个整数（面板占位是平台事实，
#   看不见就等于没有 —— Wayland 分支要靠它接 DDE 面板）。
TASKBAR_INSETS="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^taskbarInsets=//p')"
if ! printf '%s' "$TASKBAR_INSETS" | grep -Eq '^[0-9]+,[0-9]+,[0-9]+,[0-9]+$'; then
    echo "✗ platform-probe 的 taskbarInsets= 缺失或不是四个整数（得到 '$TASKBAR_INSETS'）" >&2
    exit 1
fi
# ⚠ DDE 面板真几何（批 W · M1-8）：面板**自己**报的几何 + 由此算出的弹窗落点。
#   断言分两层：① 字段在不在且形状对；② **落点必须在屏幕内**（真不变量）。
PANEL_VALID="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^panelValid=//p')"
SCREEN_RECT="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^screenRect=//p')"
TARGET_RECT="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^trayPopupTarget=//p')"
if [ -z "$PANEL_VALID" ] || [ -z "$SCREEN_RECT" ] || [ -z "$TARGET_RECT" ]; then
    echo "✗ platform-probe 缺 panelValid/screenRect/trayPopupTarget（面板几何不可见 ⇒ 弹窗落点没人知道）" >&2
    exit 1
fi
if ! printf '%s' "$SCREEN_RECT" | grep -Eq '^-?[0-9]+,-?[0-9]+,-?[0-9]+,-?[0-9]+$'; then
    echo "✗ screenRect= 不是四个整数（得到 '$SCREEN_RECT'）" >&2
    exit 1
fi
if ! printf '%s' "$TARGET_RECT" | grep -Eq '^-?[0-9]+,-?[0-9]+,-?[0-9]+,-?[0-9]+$'; then
    echo "✗ trayPopupTarget= 不是四个整数（得到 '$TARGET_RECT'）" >&2
    exit 1
fi
if [ "$PANEL_VALID" = "1" ]; then
    PANEL_RECT="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^panelRect=//p')"
    PANEL_EDGE="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^panelEdge=//p')"
    if ! printf '%s' "$PANEL_RECT" | grep -Eq '^-?[0-9]+,-?[0-9]+,-?[0-9]+,-?[0-9]+$'; then
        echo "✗ panelRect= 不是四个整数（得到 '$PANEL_RECT'）" >&2
        exit 1
    fi
    case "$PANEL_EDGE" in
        top|right|bottom|left|unknown) ;;
        *)
            echo "✗ panelEdge= 不是 top/right/bottom/left/unknown（得到 '$PANEL_EDGE'）" >&2
            exit 1
            ;;
    esac
fi
# 弹窗落点必须**整个落在屏幕内** —— 落点算错就是「弹窗开在屏幕外，用户看不见」。
if ! printf '%s\n' "$SCREEN_RECT $TARGET_RECT" | awk '
{
    split($1, s, ","); split($2, t, ",");
    sx1 = s[1]; sy1 = s[2]; sw = s[3]; sh = s[4];
    tx1 = t[1]; ty1 = t[2]; tw = t[3]; th = t[4];
    sx2 = sx1 + sw - 1; sy2 = sy1 + sh - 1;
    tx2 = tx1 + tw - 1; ty2 = ty1 + th - 1;
    if (tx1 < sx1 || ty1 < sy1 || tx2 > sx2 || ty2 > sy2) {
        printf "弹窗落点 %d,%d,%d,%d 超出屏幕 %d,%d,%d,%d\n", tx1, ty1, tw, th, sx1, sy1, sw, sh;
        exit 1;
    }
    exit 0;
}'; then
    echo "✗ 托盘弹窗落点不在屏幕内（弹窗会开在用户看不见的地方）" >&2
    exit 1
fi
# ⚠⚠ HiDPI 自绘位图（批 AP · M3c）：**结构事实** + **缩放下的效果事实**，两层都要。
#
# 【为什么探针要报这些】我们有 9 处用 QPainter **自己画**小图形（状态点 / 迷你条 /
#   托盘图标 / 里程碑图标）。原来它们都开 `QPixmap pm(8, 8)` —— 8×8 **设备**像素。
#   ⇒ 缩放到 125%/150%/200% 时，这张图被控件放大 ⇒ **发虚**。
#   实测（dpr=2）：1x 圆点的边缘只有 **6 层**半透明过渡，dpr 感知的是 **11 层**。
#
# 【两层断言】
#   ① **结构事实**（任何 dpr 下都成立）：缓冲区必须 = logical × dpr，
#      且 pixmap 的 devicePixelRatio 必须等于应用 dpr
#      ⇒ 这就是「不发虚」的充要结构条件。
#   ② **效果事实**（**只在 dpr>1 下有意义**）：dpr 感知的圆点边缘过渡层数必须
#      **多于** 1x 圆点 ⇒ 实测真的更细腻。
#      ⚠ dpr=1 时两列必然相同（同一张 8×8 图）⇒ 上面那一跑**不比较**；
#        下面**另外用 QT_SCALE_FACTOR=2 再跑一次**（dpr=2）来执行这一条
#        —— 否则这条断言永远是空的（批 AJ 教训：承诺没有门 = 承诺不存在）。

# dpi_struct_assert <probe 输出>：断言 dpiPixmap= 那行的结构事实。
dpi_struct_assert() {
    dpi_a_dpr="$(printf '%s\n' "$1" | sed -n 's/^devicePixelRatio=//p')"
    if ! printf '%s' "$dpi_a_dpr" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
        echo "✗ platform-probe 输出缺 devicePixelRatio= 行（缩放倍率不可见 ⇒ HiDPI 无从断言）" >&2
        return 1
    fi
    dpi_a_nums="$(printf '%s\n' "$1" | sed -n 's/^dpiPixmap=//p' | awk '{
        for (i = 1; i <= NF; i++) {
            if (split($i, a, ":") < 2) continue;
            if (a[1] == "logical") { split(a[2], b, "x"); printf "%s %s ", b[1], b[2] }
            else if (a[1] == "buffer") { split(a[2], b, "x"); printf "%s %s ", b[1], b[2] }
            else if (a[1] == "dpr") printf "%s ", a[2]
        }
    }')"
    # shellcheck disable=SC2086
    set -- $dpi_a_nums
    if [ $# -lt 5 ]; then
        echo "✗ platform-probe 的 dpiPixmap= 行形状不对（要 logical:WxH buffer:BxB dpr:D）" >&2
        return 1
    fi
    dpi_a_lw="$1"; dpi_a_lh="$2"; dpi_a_bw="$3"; dpi_a_bh="$4"; dpi_a_pd="$5"
    dpi_a_rc=0
    dpi_a_err="$(awk -v lw="$dpi_a_lw" -v lh="$dpi_a_lh" -v bw="$dpi_a_bw" -v bh="$dpi_a_bh" \
        -v pd="$dpi_a_pd" -v dpr="$dpi_a_dpr" 'BEGIN {
        if (lw + 0 <= 0 || lh + 0 <= 0) { print "logical 尺寸非法"; exit 1 }
        if (pd + 0 <= 0) { print "dpr 非法"; exit 1 }
        if (bw + 0 != int(lw * pd + 0.5) || bh + 0 != int(lh * pd + 0.5)) {
            printf "缓冲区 %sx%s ≠ logical %sx%s × dpr %s（自绘位图没按 dpr 放大 ⇒ 缩放下发虚）", bw, bh, lw, lh, pd
            exit 1
        }
        if (pd + 0 != dpr + 0) {
            printf "pixmap 的 devicePixelRatio %s ≠ 应用 dpr %s", pd, dpr
            exit 1
        }
    }')" || dpi_a_rc=$?
    if [ "$dpi_a_rc" -ne 0 ]; then
        echo "✗ HiDPI 结构断言失败：${dpi_a_err}" >&2
        return 1
    fi
    return 0
}

dpi_struct_assert "$PROBE_OUT" || exit 1

# ── 第二跑：强制 200% 缩放（dpr=2），执行「效果事实」那一条 ──
# ⚠ 批 BV：**不許**把 stderr 扔掉（`2>/dev/null`）—— 探针崩了时 CrashHandler 的
#   栈回溯（崩点）全在 stderr 里 ⇒ 扔掉 = CI 只剩一句「退出码 139」，没人知道崩在哪。
dpi_b_rc=0
dpi_b_out="$(QT_SCALE_FACTOR=2 "$BIN" --platform-probe)" || dpi_b_rc=$?
if [ "$dpi_b_rc" -ne 0 ]; then
    echo "✗ QT_SCALE_FACTOR=2 下 platform-probe 退出码 $dpi_b_rc（要求 0）" >&2
    exit 1
fi
# ⚠ 批 BV：第二跑**同样**要断言 appAlive（两趟都必须在 app 存活时退出）。
APP_ALIVE="$(printf '%s\n' "$dpi_b_out" | sed -n 's/^appAlive=//p')"
if [ "$APP_ALIVE" != "1" ]; then
    echo "✗ dpr=2 那趟报 appAlive=${APP_ALIVE:-缺失}（要求 1：退出时 QApplication 必须还活着）" >&2
    exit 1
fi
dpi_b_dpr="$(printf '%s\n' "$dpi_b_out" | sed -n 's/^devicePixelRatio=//p')"
if ! printf '%s' "$dpi_b_dpr" | awk '{ if ($1 + 0 >= 2) exit 0; exit 1 }'; then
    echo "✗ QT_SCALE_FACTOR=2 没生效（devicePixelRatio=${dpi_b_dpr:-空}）⇒ HiDPI 的效果断言跑不到缩放档，等于空门" >&2
    exit 1
fi
dpi_struct_assert "$dpi_b_out" || exit 1
dpi_b_legacy="$(printf '%s\n' "$dpi_b_out" | sed -n 's/^dpiEdgeLevels=legacy:\([0-9]*\).*/\1/p')"
dpi_b_aware="$(printf '%s\n' "$dpi_b_out" | sed -n 's/^dpiEdgeLevels=.*aware:\([0-9]*\).*/\1/p')"
if [ -z "$dpi_b_legacy" ] || [ -z "$dpi_b_aware" ]; then
    echo "✗ platform-probe 缺 dpiEdgeLevels= 行（边缘锐度不可见 ⇒ 发虚没人知道）" >&2
    exit 1
fi
if [ "$dpi_b_aware" -le "$dpi_b_legacy" ]; then
    echo "✗ dpr=2 下 dpr 感知自绘的边缘过渡层数（$dpi_b_aware）不多于 1x 自绘（$dpi_b_legacy）⇒ 自绘位图没按 dpr 放大（发虚）" >&2
    exit 1
fi
echo "✓ HiDPI 自绘位图：结构（buffer=logical×dpr）与效果（dpr=2 边缘层数 $dpi_b_legacy → $dpi_b_aware）都对"

# ⚠ 图标解析（批 U · M1-2）：**有图标主题时**，每个逻辑图标都必须解析得到。
#   解析不到 = 候选链没覆盖该主题的名字 ⇒ 界面上那个位置是占位圆点 ⇒ 得加候选。
#   没有图标主题时（offscreen / 极简环境）一律报 `none` 不报 `missing`，
#   那不是我们的问题（环境事实），故此时不断言。
ICON_THEME="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^iconTheme=//p')"
ICON_MISSING="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^iconMissing=//p')"
if [ -z "$ICON_MISSING" ]; then
    echo "✗ platform-probe 输出缺 iconMissing= 行（图标解析不可见 ⇒ 缺失没人知道）" >&2
    exit 1
fi
if [ -n "$ICON_THEME" ] && [ "$ICON_MISSING" != "0" ]; then
    echo "✗ 有图标主题（$ICON_THEME）但 $ICON_MISSING 个逻辑图标解析不到 ⇒ 候选链要补" >&2
    exit 1
fi
echo "✓ 平台探针通过（backend=$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^backend=//p')，图标主题=${ICON_THEME:-无} 缺失 ${ICON_MISSING} 个，托盘/主题/字号档位见上，offscreen 下托盘无效属预期）"
