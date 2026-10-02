#!/usr/bin/env bash
# fetch-deps.sh —— 拉取 CangjieGUI 与 CangjieSDL 到 vendor/。
#
# 两个依赖都是**第三方源码**，不进本仓（.gitignore 已排除 vendor/）。
# 跑一次就绪，之后 `cjpm build` / `cjpm test` 都在本地解析，不再联网。
#
# 为什么需要这个脚本，而不是在 cjpm.toml 里直接写 git 依赖：
#   1) CangjieGUI 的 cjpm.toml 把 sdl 写成 git 依赖，而它**不带** macOS 的
#      SDL3 动态库（只预置了 Windows 的 .dll）。要在 macOS/Linux 上构建，
#      必须先把 sdl 改成 path 依赖并把动态库放进 .sdl3/ —— 这两件事
#      无论如何都要在本地做一遍，写在脚本里才有可复现性。
#   2) 直接写 git 依赖时，构建是否成功取决于**当时能不能连上 github**。
#      本脚本跑完后构建完全离线。
#
# 幂等：vendor/ 下已有就跳过，重新下载用 `FORCE=1`。
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$HERE/vendor"
FORCE="${FORCE:-0}"

CUI_REPO="SunriseSummer/CangjieGUI"
SDL_REPO="SunriseSummer/CangjieSDL"
REF="${REF:-main}"

say() { printf '\033[36m›\033[0m %s\n' "$*"; }
die() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 平台判定
# SDL3 动态库的目录名。macOS 是 dylib，Linux 是 so。
case "$(uname -s)" in
  Darwin) LIB_SUFFIX="dylib" ;;
  Linux)  LIB_SUFFIX="so" ;;
  *) die "未支持的平台 $(uname -s)。CangjieGUI 目前文档覆盖 Windows/Mac/Linux。" ;;
esac

# SDL3 的安装位置。macOS 上 brew 装到 /opt/homebrew/lib 或 /usr/local/lib，
# Linux 上一般在 /usr/lib/x86_64-linux-gnu 或 /usr/lib。
find_sdl_libdir() {
  local d
  for d in /opt/homebrew/lib /usr/local/lib /usr/lib/x86_64-linux-gnu /usr/lib /usr/lib64; do
    if compgen -G "$d/libSDL3.$LIB_SUFFIX" > /dev/null 2>&1; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------- 下载
# codeload 而不是 git clone：部分网络环境下 git 的 https 传输会卡死，
# 而 codeload 的 tarball 走的是另一条路。两者内容一致。
fetch() {
  local repo="$1" dest="$2" tarball
  if [[ -d "$dest" && "$FORCE" != "1" ]]; then
    say "$(basename "$dest") 已存在，跳过（FORCE=1 可强制重下）"
    return 0
  fi
  tarball="$(mktemp "${TMPDIR:-/tmp}/dep-XXXXXX.tar.gz")"
  say "下载 $repo@$REF"
  curl -sSL --max-time 300 -o "$tarball" \
    "https://codeload.github.com/$repo/tar.gz/refs/heads/$REF" \
    || die "下载失败：$repo"
  [[ -s "$tarball" ]] || die "下载到空文件：$repo"

  rm -rf "$dest.tmp"
  mkdir -p "$dest.tmp"
  # macOS 的 bsdtar 在遇到 pax 扩展头里的大尺寸字段时会报
  # "Special header too large"，python 的 tarfile 则能正常解开。
  # 两个都试一遍：哪个先成功用哪个。
  if ! tar xzf "$tarball" -C "$dest.tmp" 2>/dev/null; then
    say "tar 解压失败，改用 python tarfile"
    python3 - "$tarball" "$dest.tmp" <<'PY' || die "python 解压也失败"
import sys, tarfile
tarball, dest = sys.argv[1], sys.argv[2]
with tarfile.open(tarball) as t:
    for m in t:
        try:
            t.extract(m, dest, filter='data')
        except Exception:
            pass  # 个别成员的路径在某些 tar 实现下不合法，跳过
PY
  fi
  rm -f "$tarball"

  # tarball 解出来是 <Repo>-<ref>/ 一层
  local top
  top="$(find "$dest.tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
  [[ -n "$top" ]] || die "解压结果里没找到顶层目录：$repo"
  rm -rf "$dest"
  mv "$top" "$dest"
  rmdir "$dest.tmp" 2>/dev/null || true
  say "$(basename "$dest") 就绪"
}

mkdir -p "$VENDOR"
fetch "$CUI_REPO" "$VENDOR/CangjieGUI"
fetch "$SDL_REPO" "$VENDOR/CangjieSDL"

# ---------------------------------------------------------------- 打补丁
# CangjieGUI 的 sdl 依赖改成 path —— 见文件头第 1) 条理由。
CUI_TOML="$VENDOR/CangjieGUI/cjpm.toml"
[[ -f "$CUI_TOML" ]] || die "找不到 $CUI_TOML"
if grep -q 'sdl = { git' "$CUI_TOML"; then
  say "把 CangjieGUI 的 sdl 依赖从 git 改为本地 path"
  # 用相对路径，两处都在 vendor/ 下，移动整个目录也不会失效
  sed -i '' "s#sdl = { git = .*#sdl = { path = \"../CangjieSDL\" }#" "$CUI_TOML" 2>/dev/null \
    || sed -i "s#sdl = { git = .*#sdl = { path = \"../CangjieSDL\" }#" "$CUI_TOML"
fi

# ---------------------------------------------------------------- SDL3 动态库
# CangjieSDL 的 .sdl3/ 只预置了 Windows 的 dll。macOS/Linux 必须自己放。
SDL3_DIR="$VENDOR/CangjieSDL/.sdl3"
mkdir -p "$SDL3_DIR"

LIBDIR="$(find_sdl_libdir || true)"
if [[ -z "$LIBDIR" ]]; then
  cat >&2 <<EOF
✗ 找不到 SDL3 动态库（libSDL3.$LIB_SUFFIX）。

  CUI 的渲染与字体依赖 SDL3 + SDL_ttf + SDL_image 三个库，
  缺任何一个都会在链接期失败。按平台装：
$(if [ "$LIB_SUFFIX" = dylib ]; then
    echo "    brew install sdl3 sdl3_ttf sdl3_image"
  else
    echo "    sudo apt install libsdl3-dev libsdl3-ttf-dev libsdl3-image-dev"
  fi)
  装完重跑本脚本。
EOF
  exit 1
fi

for lib in SDL3 SDL3_ttf SDL3_image; do
  src="$(compgen -G "$LIBDIR/lib$lib.$LIB_SUFFIX*" | head -1)"
  [[ -n "$src" ]] || die "$LIBDIR 下找不到 lib$lib.$LIB_SUFFIX"
  cp "$src" "$SDL3_DIR/lib$lib.$LIB_SUFFIX"
  say "lib$lib.$LIB_SUFFIX  ← $src"
done

echo
say "依赖就绪。下一步："
echo "    cd $HERE && cjpm build && cjpm run"
