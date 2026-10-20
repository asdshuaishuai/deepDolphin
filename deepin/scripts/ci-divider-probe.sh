#!/usr/bin/env bash
# ci-divider-probe.sh — 分隔线的**正式断言**（批 AW）。
#
# 【为什么要有这一门】
#   · 详情页**不在快照矩阵里**（快照拍 dashboard / board / milestones / setupguide）
#     ⇒ 快照**抓不到**分隔线 ⇒ 它必须另有判据，否则这次修复等于没门。
#   · 静态门（源码扫描）能证明「页面用的是 `vDivider(...)` 而不是 `QLabel("|")`」，
#     但**证明不了**「画出来真的只有 1 逻辑像素宽、且颜色是 DS token」
#     ⇒ 这一门**真渲染**一次，量墨迹。
#
# 【断言什么】（inkWidth/inkHeight 是**物理**像素 ⇒ 按 dpr 换算）
#   ① 探针 exit 0
#   ② 逻辑尺寸：宽 **1**、高 **14**（14 = 对位 mac `Divider().frame(height: 14)`）
#   ③ inkWidth  == round(dpr)  ⇒ 恰好 **1 逻辑像素**宽（文字版是 4 ⇒ 这里分叉）
#   ④ inkHeight == round(14*dpr) ⇒ 高度没有被拉成字体高（文字版是 18 ⇒ 这里分叉）
#   ⑤ inkColor  == tokenColor ⇒ 颜色走 DS token（写死颜色 ⇒ 这里分叉）
#   ⑥ opaque   == 1 ⇒ 边缘没有半透明（开了抗锯齿 ⇒ 这里分叉）
#
# 用法：scripts/ci-divider-probe.sh <deepDolphin 二进制>
set -uo pipefail
BIN="${1:-}"
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    echo "✗ 用法：$0 <deepDolphin 二进制>" >&2
    exit 2
fi

PROBE_RC=0
# ⚠ stderr 丢掉：DTK 会打「setHighDpiScaleFactorRoundingPolicy…」等噪声，
#   那些不是探针的结论。断言只看 stdout。
PROBE_OUT="$(QT_QPA_PLATFORM=offscreen "$BIN" --divider-probe 2>/dev/null)" || PROBE_RC=$?
printf '%s\n' "$PROBE_OUT"
if [ "$PROBE_RC" -ne 0 ]; then
    echo "✗ divider-probe 退出码 $PROBE_RC（要求 0）" >&2
    exit 1
fi

field() { # field <键> —— 取该键的值
    printf '%s\n' "$PROBE_OUT" | sed -n "s/^$1=//p" | head -1
}

W="$(field width)"
H="$(field height)"
DPR="$(field dpr)"
IW="$(field inkWidth)"
IH="$(field inkHeight)"
INK="$(field inkColor)"
TOKEN="$(field tokenColor)"
OPAQUE="$(field opaque)"

for v in "$W" "$H" "$DPR" "$IW" "$IH" "$INK" "$TOKEN" "$OPAQUE"; do
    if [ -z "$v" ]; then
        echo "✗ divider-probe 的输出缺字段（width/height/dpr/inkWidth/inkHeight/inkColor/tokenColor/opaque）" >&2
        exit 1
    fi
done

# ② 逻辑尺寸
if [ "$W" != "1" ]; then
    echo "✗ 分隔线逻辑宽 = $W（要求 1 逻辑像素；文字版 QLabel(\"|\") 是 4）" >&2
    exit 1
fi
if [ "$H" != "14" ]; then
    echo "✗ 分隔线逻辑高 = $H（要求 14：对位 mac Divider().frame(height: 14)）" >&2
    exit 1
fi

# ③ ④ 物理像素按 dpr 换算（bash 没有 round ⇒ 用 awk）
rnd() { awk -v x="$1" 'BEGIN{printf "%d", int(x+0.5)}'; }
EXP_W="$(rnd "$DPR")"
EXP_H="$(rnd "$(awk -v h="$H" -v d="$DPR" 'BEGIN{print h*d}')")"
if [ "$IW" != "$EXP_W" ]; then
    echo "✗ 分隔线墨迹宽 = $IW 物理像素（dpr=$DPR ⇒ 期望 $EXP_W）⇒ 不是 1 逻辑像素宽" >&2
    exit 1
fi
if [ "$IH" != "$EXP_H" ]; then
    echo "✗ 分隔线墨迹高 = $IH 物理像素（dpr=$DPR ⇒ 期望 $EXP_H）⇒ 高度被拉了" >&2
    exit 1
fi

# ⑤ 颜色走 DS token
if [ "$INK" != "$TOKEN" ]; then
    echo "✗ 分隔线画出来的颜色 $INK ≠ DS token $TOKEN ⇒ 颜色被写死了" >&2
    exit 1
fi

# ⑥ 边缘不半透明（开了抗锯齿就会有灰边而不是线）
if [ "$OPAQUE" != "1" ]; then
    echo "✗ 分隔线墨迹里有半透明像素 ⇒ 开了抗锯齿（1px 线不该 AA）" >&2
    exit 1
fi

echo "✓ 分隔线探针通过（1 逻辑像素宽 × 14 高、颜色走 DS token、边缘不透明）"
