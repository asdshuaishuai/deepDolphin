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

PROBE_RC=0
PROBE_OUT="$("$BIN" --platform-probe)" || PROBE_RC=$?
printf '%s\n' "$PROBE_OUT"
if [ "$PROBE_RC" -ne 0 ]; then
    echo "✗ platform-probe 退出码 $PROBE_RC（要求 0）" >&2
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
