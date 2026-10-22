#!/bin/sh
# ci-shell-parity.sh — 批 DV · 「判据层的结论不许随执行 shell 变」的门（覆盖面版）
#
# 【为什么要有它 —— 承接批 DT / 批 DU】
#   批 DT 立了承诺（「判据结果的诊断输出不许随执行 shell 变」）⇒ 批 DU 给它装上牙齿
#   （`ci.sh` 第 9 步双跑**接线门**）⇒ 但**只覆盖了一个脚本** ⇒
#   ⚠⚠⚨ 别的判据脚本（`ci-d2.sh` / `ci-orphan-probe.sh` …）**结论照样可能随 shell 变**
#   ⇒ 而**没有任何一道门**会发现 ⇒ 本脚本把覆盖面扩出去。
#
# 【机制】
#   读**仓内常驻登记册** `ci-shell-parity.baseline` ⇒ 逐条对「标 DUAL 且双跑位置是本脚本」的条目
#   ⇒ `sh` 跑一遍 + `bash` 跑一遍 ⇒ **退出码必须一致** + **输出必须逐字节一致**
#   ⇒ 任一不同 ⇒ 判红（批 DU 同款口径：假红比假绿更坏 ⇒ 差异落文件再读，不用 `| head`）。
#
# ⚠⚠⚨ **为什么登记册里要有「豁免」条目（EXEMPT）**：
#   「哪些判据脚本被双跑」这条承诺，**若只记被双跑的那些** ⇒ 覆盖面可以被**悄悄改窄**
#   （新增一个判据脚本 ⇒ 不双跑 ⇒ 没人知道）⇒ 批 DQ 立过的教训
#   （「一条本该被登记的承诺，在三个目录上从未生效」）⇒
#   ⇒ **CI 里跑的每一个 shell 判据脚本都必须在登记册里** ⇒ 要么 DUAL，要么 EXEMPT + 理由
#   ⇒ 且 EXEMPT 的理由必须**真实**（不是「懒得跑」）。
#
# ⚠⚠⚨ **「入口共用 ≠ 口径共用」**（批 DG 教训）：
#   `ci.sh` 第 9 步也双跑接线门（批 DU）⇒ 那**不是**本脚本的口径 ⇒
#   ⇒ 登记册里用「**双跑位置**」这一列区分（`ci.sh` / `parity`）⇒ 两边各算各的。
#
# 用法：scripts/ci-shell-parity.sh [源码根目录]（默认脚本所在目录的上一级）
set -uo pipefail

SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
# ⚠⚠⚨ 归一化成**绝对路径**（批 DV 实测）：相对路径传给子判据脚本 ⇒ 子脚本按**自己**
#   的口径去解析那个路径 ⇒ 两遍**一起红**（孤儿探针会把整棵树判成「游离」）
#   ⇒ 「两版一致」变成**空洞的一致** ⇒ 假绿 ⇒ 绝对路径 ⇒ 两遍跑的才是真判据
SRC_ABS="$(cd "$SRC" 2>/dev/null && pwd)"
# ⚠ 仓库根（`macos/` 与 `deepin/` 同仓）⇒ 登记册的键用**相对仓库根的路径**（批 CY 教训）
ROOT="$(cd "$SRC/.." && pwd)"
BASE="$SRC/scripts/ci-shell-parity.baseline"

TAB=$(printf '\t')

if [ ! -f "$BASE" ]; then
    echo "✗ 双跑登记册不存在：$BASE ⇒ 「哪些判据脚本被双跑」这件事**无处可查** ⇒ 拒绝继续" >&2
    exit 1
fi

# ⚠⚠⚨ 差异落文件（不落 `$BUILD` ⇒ 免得第二遍比第一遍多看到第一遍的产物 ⇒ 自己制造分叉）
_SA="${TMPDIR:-/tmp}/deepdolphin-parity-sh.$$.log"
_SB="${TMPDIR:-/tmp}/deepdolphin-parity-bash.$$.log"
_SD="${TMPDIR:-/tmp}/deepdolphin-parity-diff.$$.log"

n_dual=0
n_exempt=0
n_ok=0

while IFS="$TAB" read -r rel mode where why; do
    [ -z "$rel" ] && continue
    case "$rel" in '#'*) continue ;; esac
    if [ "$mode" = "EXEMPT" ]; then
        # ⚠⚠⚨ 豁免**必须**写理由（否则「不双跑」就成了一句空话 ⇒ 覆盖面被悄悄改窄）
        if [ -z "$why" ]; then
            echo "✗ 双跑登记册里 $rel 标了 EXEMPT 却**没写理由** ⇒ 「为什么不双跑」没人负责 ⇒ 拒绝继续" >&2
            exit 1
        fi
        n_exempt=$((n_exempt + 1))
        continue
    fi
    if [ "$mode" != "DUAL" ]; then
        echo "✗ 双跑登记册里有不认识的状态：$rel ⇒ $mode（只许 DUAL 或 EXEMPT）" >&2
        exit 1
    fi
    if [ -z "$why" ]; then
        echo "✗ 双跑登记册里 $rel 标了 DUAL 却**没写理由**（为什么它能双跑）⇒ 拒绝继续" >&2
        exit 1
    fi
    if [ "$where" != "parity" ] && [ "$where" != "ci.sh" ]; then
        echo "✗ 双跑登记册里有不认识的双跑位置：$rel ⇒ $where（只许 parity 或 ci.sh）" >&2
        exit 1
    fi
    if [ "$where" != "parity" ]; then
        # 位置是 `ci.sh` ⇒ 由批 DU 的门项负责（那半边在 CI 入口里）⇒ 本脚本不管
        continue
    fi
    n_dual=$((n_dual + 1))
    _script="$ROOT/$rel"
    if [ ! -r "$_script" ]; then
        echo "✗ 双跑登记册里的脚本读不了：$_script ⇒ 双跑做不了 ⇒ 这一组**根本没验过**（不许当成通过）" >&2
        exit 1
    fi
    _rc_a=0
    sh   "$_script" "$SRC_ABS" > "$_SA" 2>&1 || _rc_a=$?
    _rc_b=0
    bash "$_script" "$SRC_ABS" > "$_SB" 2>&1 || _rc_b=$?
    if [ "$_rc_a" -ne "$_rc_b" ]; then
        echo "✗ ⚠⚠⚨ $rel 在 sh 与 bash 下**退出码不同**（sh=$_rc_a / bash=$_rc_b）⇒ 判据层的**结论随执行 shell 变** ⇒ 不可信（批 DT）" >&2
        exit 1
    fi
    if ! cmp -s "$_SA" "$_SB"; then
        echo "✗ ⚠⚠⚨ $rel 在 sh 与 bash 下**输出不同** ⇒ 诊断文案**随执行 shell 变** ⇒ 负控的文案命中判定不可信（批 DT）" >&2
        _drc=0
        diff "$_SA" "$_SB" > "$_SD" 2>&1 || _drc=$?
        echo "   差异已写 $_SD（diff 退出码 $_drc）前 20 行：" >&2
        head -20 "$_SD" >&2
        exit 1
    fi
    n_ok=$((n_ok + 1))
done < "$BASE"

echo "✓ 双跑覆盖面：本脚本双跑了 $n_dual 个判据脚本，在 sh 与 bash 下**输出与退出码一致**（豁免 $n_exempt 个，每个带理由）"
