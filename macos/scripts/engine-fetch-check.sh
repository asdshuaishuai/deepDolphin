#!/bin/bash
# engine-fetch-check.sh — **引擎下载链**的判据（批 AQ）。
#
# 【为什么这条判据存在】
# 原来 mac 侧 `build.sh` 的下载路径有**三个**叠在一起的错：
#   ① URL 写死 `releases/latest/download/moongit-darwin-arm64.tar.gz`
#      —— 资产名**带版本号**（`moongit-v0.2.1-darwin-arm64.tar.gz`），
#      而 `latest/download` 要求**资产名精确匹配** ⇒ **必然 404**；
#   ② 找的是「包根的 `moongit-cli`」—— 真实包里**没有**那个文件
#      （真二进制在 `bin/moongit-cli`）⇒ 就算 URL 修好也**找不到**；
#   ③ 只复制 CLI、**丢掉 `runtime/lib/`** ⇒ 装下来的引擎**根本起不来**。
# ⇒ 这条判据把「下载链对不对」变成**可执行的事实**：
#   查 API → 挑资产 → 下载 → 解包 → 验三样齐全 → **启动器真跑一次 `version`**。
#
# ⚠ 本脚本**不依赖 macOS**（只用 curl/tar/grep + 被测包自己的启动器）
#   ⇒ 判据在 Linux 上就能跑，不必等真机。
#
# 用法：scripts/engine-fetch-check.sh [--full]
#   默认：只验「URL 选取 + 资产可达」（快，不下 8MB）
#   --full：真下载 + 解包 + 验布局 + 跑启动器（慢，但把整条链走完）
set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FETCH="$PKG_DIR/scripts/fetch-engine.sh"
[ -f "$FETCH" ] || { echo "✗ 找不到 fetch-engine.sh" >&2; exit 2; }

FULL=0
[ "${1:-}" = "--full" ] && FULL=1

FAIL=0
ok()   { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1" >&2; FAIL=1; }

echo "› 引擎下载链判据（批 AQ）"

# ── 1. URL 选取 ──
# ⚠ 平台后缀：mac 上是 darwin-arm64；本机（Linux CI）是 linux-x64。
#   两者都要能选出来 ⇒ 逐个试，不假设本机就是 mac。
for SUFFIX in darwin-arm64 linux-x64; do
    URL="$(bash "$FETCH" --url-only "$SUFFIX" 2>/dev/null || true)"
    if [ -z "$URL" ]; then
        bad "选不出「-${SUFFIX}.tar.gz」的资产 URL"
        continue
    fi
    ok "选出 ${SUFFIX} 的资产 URL"
    # ① **不许**是那个写死的 404 URL（不带版本号 ⇒ GitHub 精确匹配不到）
    case "$URL" in
        *"/releases/latest/download/moongit-"*)
            bad "URL 仍是写死的 latest/download 形式（资产名不带版本号 ⇒ 404）：$URL" ;;
        *)
            ok "URL 不是写死的 latest/download 形式" ;;
    esac
    # ② URL 里必须带**版本号**（`/download/v<版本>/`）
    case "$URL" in
        *"/releases/download/v"*"/moongit-v"*)
            ok "URL 带版本号（资产名精确匹配 ⇒ 不会 404）" ;;
        *)
            bad "URL 里没有版本号段（资产名对不上 ⇒ 404）：$URL" ;;
    esac
    # ③ 资产可达（HEAD 200/302 ⇒ GitHub 的 302 跳转到 CDN 也算可达）
    CODE="$(curl -s -o /dev/null -w '%{http_code}' -I --max-time 30 "$URL" 2>/dev/null || echo 000)"
    case "$CODE" in
        200|302) ok "资产可达（HTTP $CODE）" ;;
        *)       bad "资产不可达（HTTP $CODE）：$URL" ;;
    esac
done

# ── 2. 整条链（--full）：真下载 + 验布局 + 跑启动器 ──
if [ "$FULL" -eq 1 ]; then
    SUFFIX="$(case "$(uname -s)" in Darwin) echo darwin-arm64 ;; *) echo linux-x64 ;; esac)"
    DEST="$(mktemp -d)/engine"
    # ⚠⚠⚨ **批 EJ-34**：临时路径**必须进程唯一**（带 PID）⇒ ⇒ 全局固定路径 ⇒ ⇒
    #   并发跑本脚本 ⇒ ⇒ 后写的**覆盖**先写的 ⇒ ⇒ 而下面**读回自己的错误输出**
    #   ⇒ ⇒ 报错可能**读成对方的** ⇒ ⇒ ⇒ **假红/假绿** ⇒ ⇒ 路径**一律**带 PID。
    FETCH_ERR="/tmp/engine-fetch-err.$$.txt"
    BIN="$(bash "$FETCH" "$DEST" "$SUFFIX" 2>"$FETCH_ERR" || true)"
    if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
        bad "下载/解包失败：$(cat "$FETCH_ERR" 2>/dev/null | tail -3)"
        rm -f "$FETCH_ERR"
    else
        ok "下载并解包成功：$BIN"
        # ② 包根的启动器
        [ -x "$DEST/moongit" ] && ok "包根有启动器 moongit" || bad "包根缺启动器 moongit"
        # ③ 真二进制
        [ -x "$DEST/bin/moongit-cli" ] && ok "包里有 bin/moongit-cli" || bad "包里缺 bin/moongit-cli"
        # ④ 仓颉运行时（**非空**）
        if [ -d "$DEST/runtime/lib" ] && [ -n "$(ls -A "$DEST/runtime/lib" 2>/dev/null)" ]; then
            ok "包里有 runtime/lib（仓颉运行时，非空）"
        else
            bad "包里缺 runtime/lib 或它是空的（引擎会 Library not loaded）"
        fi
        # ⑤ **启动器真跑一次**（这是整条链的终点：装下来的引擎能起来吗）
        OUT="$("$DEST/moongit" version 2>&1 | head -2)"
        case "$OUT" in
            *"moonGit Engine"*) ok "启动器真能跑：$OUT" ;;
            *) bad "启动器跑不起来：${OUT:-（无输出）}" ;;
        esac
    fi
else
    echo "  · （加 --full 可把整条链走完：真下载 + 验布局 + 跑启动器）"
fi

if [ "$FAIL" -ne 0 ]; then
    echo "✗ 引擎下载链判据未通过" >&2
    exit 1
fi
echo "✓ 引擎下载链判据通过（URL 可达且带版本号；发布包三样齐全，启动器能跑）"
