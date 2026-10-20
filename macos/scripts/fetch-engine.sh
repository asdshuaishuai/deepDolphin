#!/bin/bash
# fetch-engine.sh — 按 release 资产**精确名**下载并解包引擎发布包。
#
# 【为什么不能写死 URL】（实测，2026-10-20）
# release 的资产名**带版本号**：`moongit-v0.2.1-darwin-arm64.tar.gz`。
# GitHub 的 `releases/latest/download/<name>` 要求**资产名精确匹配**
# ⇒ 写死 `moongit-darwin-arm64.tar.gz` 这种**不带版本号**的名字必然 **404**
#   （原来 build.sh 用的就是它 ⇒ 那条下载路径**从来没成功过**）。
#   deepin 侧早就踩过并记在 `deepin/src/logic/EngineDownload.h`（同一件事）。
# ⇒ 这里查 API 拿最新 release 的资产列表，按**后缀**挑
#   （架构差异由资产名表达，不写死在 URL 里）。
#
# 【发布包不是单个裸二进制】（实测 tar 清单）
#   moongit            ← 包根的**启动器**（POSIX shell 脚本）
#   bin/moongit-cli    ← 真二进制
#   runtime/lib/*.so   ← 仓颉运行时
# 启动器按**自身所在目录**去找后两样（`ROOT=$(dirname "$0")`），
# 且**不解析软链** ⇒ 启动器必须待在**包根**。
# ⇒ 原来 build.sh 找的「包根的 moongit-cli」是**虚构的布局**（真实包里没有那个文件），
#   就算 URL 修好了也**找不到**；而且它只复制 CLI、把 `runtime/lib/` 丢掉
#   ⇒ 装下来的引擎**根本起不来**（缺仓颉运行时）。
#
# 【用法】
#   fetch-engine.sh --url-only [资产后缀]   只打印资产 URL（不下载）
#   fetch-engine.sh <解包目标目录> [资产后缀]
#     · 目标目录 = **包根**（解包后含 moongit / bin/ / runtime/）
#     · 资产后缀默认按平台猜：darwin-arm64 / linux-x64
#   stdout：成功时打印**启动器的绝对路径**（--url-only 时打印 URL）
#   退出码：0 成功；1 失败（原因写 stderr）
#
# ⚠ 本脚本**不依赖 macOS**（只用 curl/tar/grep）⇒ 可以在 Linux 上跑，
#   所以「下载链对不对」这件事**有判据**，不必等真机。
set -uo pipefail

REPO="${ENGINE_REPO:-asdshuaishuai/moongit}"

die() { echo "✗ $*" >&2; exit 1; }

# 平台 → 资产后缀
default_suffix() {
    case "$(uname -s)" in
        Darwin) echo "darwin-arm64" ;;
        Linux)  echo "linux-x64" ;;
        *)      echo "" ;;
    esac
}

URL_ONLY=0
if [ "${1:-}" = "--url-only" ]; then
    URL_ONLY=1
    shift
fi

DEST="${1:-}"
SUFFIX="${2:-}"
if [ -z "$SUFFIX" ]; then
    SUFFIX="$(default_suffix)"
    [ -n "$SUFFIX" ] || die "认不出本机架构（uname -s=$(uname -s)）⇒ 请显式给资产后缀"
fi

# ── 1. 查 API 拿资产 URL（按**后缀**挑，不写死版本号）──
api_json="$(curl -fsSL --max-time 30 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)"
[ -n "$api_json" ] || die "取不到 ${REPO} 的最新 release（api.github.com 不通？离线？）"

asset_url="$(printf '%s' "$api_json" | tr ',' '\n' \
  | grep -o '"browser_download_url": *"[^"]*"' \
  | sed 's/.*"browser_download_url": *"//; s/"$//' \
  | grep -- "-${SUFFIX}\.tar\.gz$" | head -1)"
[ -n "$asset_url" ] || die "最新 release 里没有匹配「-${SUFFIX}.tar.gz」的资产"

if [ "$URL_ONLY" -eq 1 ]; then
    printf '%s\n' "$asset_url"
    exit 0
fi

[ -n "$DEST" ] || die "用法：fetch-engine.sh <解包目标目录> [资产后缀]"

# ── 2. 下载 ──
tmp_tgz="$(mktemp -t moongit-dl.XXXXXX.tar.gz)"
tmp_dir="$(mktemp -d)"
cleanup() { rm -f "$tmp_tgz"; rm -rf "$tmp_dir"; }
trap cleanup EXIT

curl -fsSL --max-time 600 "$asset_url" -o "$tmp_tgz" || die "下载失败：$asset_url"
[ -s "$tmp_tgz" ] || die "下载到的是空文件：$asset_url"

# ── 3. 解包（**整包**，不挑文件）──
tar xzf "$tmp_tgz" -C "$tmp_dir" || die "解包失败：$asset_url"

# ⚠ 发布包里可能带一层**版本目录**（不同打包脚本不一样）⇒ 找**含启动器**的那层。
pkg_root=""
for cand in "$tmp_dir/" "$tmp_dir"/*/; do
    if [ -x "${cand}moongit" ]; then pkg_root="${cand%/}"; break; fi
done
[ -n "$pkg_root" ] || die "包里找不到启动器「moongit」（包结构变了？）"

# ── 4. 验布局（三样必须**一起**）──
[ -x "$pkg_root/bin/moongit-cli" ] || die "包里没有 bin/moongit-cli（真二进制）"
[ -d "$pkg_root/runtime/lib" ] || die "包里没有 runtime/lib（仓颉运行时）"
[ -n "$(ls -A "$pkg_root/runtime/lib" 2>/dev/null)" ] || die "runtime/lib 是空的（坏包）"

# ── 5. 落盘到目标目录（**整包**）──
mkdir -p "$DEST"
# 先清干净（避免旧包残留的 bin/ 或 runtime/ 混进来）
rm -rf "$DEST/bin" "$DEST/runtime" "$DEST/moongit"
cp "$pkg_root/moongit" "$DEST/moongit"
chmod +x "$DEST/moongit"
cp -R "$pkg_root/bin" "$DEST/bin"
cp -R "$pkg_root/runtime" "$DEST/runtime"

printf '%s\n' "$DEST/moongit"
