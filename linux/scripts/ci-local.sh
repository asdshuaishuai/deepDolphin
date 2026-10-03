#!/usr/bin/env bash
# ci-local.sh —— Linux 开发机上的本地验证门禁（无 root、用户空间可复现）。
#
# 解决的问题：本机（deepin 25，glibc 2.38，无 sudo）没有 SDL3 的系统包，
# 而 CangjieSDL 的绑定按 SDL 3.4 生成。本脚本把「仓颉 SDK + 用户空间 SDL3 +
# 链接垫片」的整套拼装固化下来，让 `cjpm test` 可以完整跑通。
#
# 做什么（全部幂等）：
#   1) vendor/ 缺 CangjieGUI/CangjieSDL 时调 fetch-deps.sh 拉；
#   2) SDL3 3.2.10 + SDL3_image 3.2.4 + SDL3_ttf 3.2.2 从 Debian 池下 .deb
#      解到 ~/.local/sdl3（glibc 2.38 兼容；3.4.x 全系要 glibc 2.43 装不了），
#      拷进 vendor/CangjieSDL/.sdl3 供链接；
#   3) 若系统 ld 找不到 crtbeginS.o/crtendS.o（cjc 以裸位置参数传给 ld，
#      GNU ld 对位置参数不做 -L 搜索），装 ~/.local/bin/ld 包装器：
#      把两个 crt 换成 dd-sysroot GCC13 的绝对路径，并只在链接 app 测试
#      二进制时追加 sdl-shim.o（CangjieSDL 的 6 个 SDL3.4 专属绑定的 no-op
#      占位——测试路径从不调用；testrunner 自带定义，追加反而撞重定义）；
#   4) moonGit 引擎仓目录大小写兼容链接（~/code/moonGit → moongit）；
#   5) 跑 cjpm test 并输出机器可读汇总行。
#
# 用法：bash scripts/ci-local.sh        # 验证门禁（CI 用这个）
#       bash scripts/ci-local.sh setup  # 只装环境不跑测试
#
# 期望：PASSED ≥ 116, FAILED = 0, SKIPPED = 3（3 条 AI 端到端需 ai-e2e.sh）。

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANGJIE_HOME="${CANGJIE_HOME:-$HOME/.local/share/cangjie/current/cangjie}"
SDL_USER="$HOME/.local/sdl3"
SDL3DIR="$HERE/vendor/CangjieSDL/.sdl3"
DEB_BASE="http://deb.debian.org/debian/pool/main/libs"

say() { printf '\033[36m›\033[0m %s\n' "$*"; }
die() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[ -x "$CANGJIE_HOME/bin/cjc" ] || die "仓颉 SDK 没找到：$CANGJIE_HOME/bin/cjc（本仓钉死 1.0.5）"
export CANGJIE_HOME
export PATH="$HOME/.local/bin:$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:$PATH"
# shellcheck disable=SC1091
source "$CANGJIE_HOME/envsetup.sh" >/dev/null 2>&1 || true

# ── 1) vendor/ ──
if [ ! -d "$HERE/vendor/CangjieGUI" ] || [ ! -d "$HERE/vendor/CangjieSDL" ]; then
    say "拉取 CangjieGUI / CangjieSDL …"
    bash "$HERE/scripts/fetch-deps.sh"
fi

# ── 2) 用户空间 SDL3（幂等：.sdl3 里已有 libSDL3.so 就跳过下载）──
if [ ! -e "$SDL3DIR/libSDL3.so" ]; then
    say "下载用户空间 SDL3（3.2.10 / image 3.2.4 / ttf 3.2.2 + 两个可选依赖）…"
    mkdir -p "$SDL_USER/ex/usr/lib/x86_64-linux-gnu"
    fetch_deb() { # $1=池子路径 $2=文件名
        local f="$2"
        [ -s "$SDL_USER/$f" ] || curl -sSL --max-time 300 -o "$SDL_USER/$f" "$DEB_BASE/$1/$f"
        dpkg-deb -x "$SDL_USER/$f" "$SDL_USER/ex"
    }
    fetch_deb "libsdl3" "libsdl3-0_3.2.10+ds-1_amd64.deb"
    fetch_deb "libsdl3-image" "libsdl3-image0_3.2.4+ds-1+deb13u1_amd64.deb"
    fetch_deb "libsdl3-ttf" "libsdl3-ttf0_3.2.2+ds-2_amd64.deb"
    # SDL3 的可选后端依赖（链接期要能解析 DT_NEEDED）
    fetch_deb "libx/libxss" "libxss1_1.2.3-1+b4_amd64.deb"
    fetch_deb "s/sndio" "libsndio7.0_1.9.0-0.3+b2_amd64.deb"
    SDLUSR="$SDL_USER/ex/usr/lib/x86_64-linux-gnu"
    mkdir -p "$SDL3DIR"
    cp -a "$SDLUSR"/libSDL3.so.0 "$SDLUSR"/libSDL3.so.0.2.10 \
        "$SDLUSR"/libSDL3_image.so.0 "$SDLUSR"/libSDL3_image.so.0.2.4 \
        "$SDLUSR"/libSDL3_ttf.so.0 "$SDLUSR"/libSDL3_ttf.so.0.2.2 "$SDL3DIR/"
    ln -sf libSDL3.so.0 "$SDL3DIR/libSDL3.so"
    ln -sf libSDL3_image.so.0 "$SDL3DIR/libSDL3_image.so"
    ln -sf libSDL3_ttf.so.0 "$SDL3DIR/libSDL3_ttf.so"
fi

# ── 3) 链接垫片：crt 两个对象 + SDL3.4 绑定占位 ──
CRT_GCC="$(ls -d "$HOME"/.local/dd-sysroot/usr/lib/gcc/x86_64-linux-gnu/*/ 2>/dev/null | sort -V | tail -1 || true)"
if [ -n "$CRT_GCC" ] && [ -f "${CRT_GCC}crtbeginS.o" ] && ! ld crtbeginS.o -r -o /dev/null 2>/dev/null; then
    # 本机 ld 现在就解析不了裸 crtbeginS.o → 需要 ~/.local/bin/ld 包装器
    if [ ! -x "$HOME/.local/bin/ld" ] || ! grep -q "sdl-shim" "$HOME/.local/bin/ld" 2>/dev/null; then
        say "安装 ~/.local/bin/ld 链接包装器（crt 绝对路径 + app 测试链接追加 shim）…"
        SDLUSR="$SDL_USER/ex/usr/lib/x86_64-linux-gnu"
        gcc -fPIC -x c -c -o "$SDL_USER/sdl-shim.o" - <<'EOF'
/* sdl-shim.c —— 仅本类开发容器（glibc 2.38 + SDL 3.2）的 cjpm test 门禁用。
 * CangjieSDL 绑定按 SDL 3.4 生成；下列符号在测试路径上从不被调用，
 * no-op 占位让测试二进制完成链接。真实 Linux 环境（SDL 3.4）不需要。 */
int SDL_SetWindowProgressState(void *w, int s) { (void)w; (void)s; return 0; }
int SDL_SetWindowProgressValue(void *w, float v) { (void)w; (void)v; return 0; }
int SDL_GetWindowProgressState(void *w) { (void)w; return 0; }
float SDL_GetWindowProgressValue(void *w) { (void)w; return 0.0f; }
int SDL_SetWindowFillDocument(void *w, int f) { (void)w; (void)f; return 0; }
void *SDL_LoadPNG(void *io) { (void)io; return (void *)0; }
int SDL_SavePNG(void *sf, void *io) { (void)sf; (void)io; return 0; }
int SDL_GetSystemPageSize(void) { return 4096; }
EOF
        mkdir -p "$HOME/.local/bin"
        cat > "$HOME/.local/bin/ld" <<WRAPPER
#!/usr/bin/env bash
# 由 deepDolphin linux/scripts/ci-local.sh 安装：cjc 的链接缺口修补（透明包装）。
SHIM="$SDL_USER/sdl-shim.o"
CRTDIR="${CRT_GCC%/}"
args=()
for a in "\$@"; do
    case "\$a" in
        crtbeginS.o) args+=("\$CRTDIR/crtbeginS.o") ;;
        crtendS.o) args+=("\$CRTDIR/crtendS.o") ;;
        *) args+=("\$a") ;;
    esac
done
[ -f "\$SHIM" ] && [[ "\$*" == *"unittest_bin/deepdolphin_linux"* ]] && args+=("\$SHIM")
exec /usr/bin/ld "\${args[@]}"
WRAPPER
        chmod +x "$HOME/.local/bin/ld"
    fi
fi

# ── 4) 引擎仓大小写兼容（ai-e2e.sh 硬编码 ~/code/moonGit）──
if [ -d "$HOME/code/moongit" ] && [ ! -e "$HOME/code/moonGit" ]; then
    ln -sfn "$HOME/code/moongit" "$HOME/code/moonGit"
fi

# ── 5) 跑门禁 ──
if [ "${1:-}" = "setup" ]; then
    say "环境就绪（未跑测试）。"
    exit 0
fi

cd "$HERE"
# 链接期 ld 要解析 libSDL3.so 的 DT_NEEDED（libsndio/libXss 等）：
# .sdl3 放 SDL 三件套本体，用户解包目录放可选依赖。顺序敏感——.sdl3 的 3.2.10 必须先于
# 任何混入 3.4.x 的目录被找到（3.4 要 glibc 2.43，本机 2.38）。
export LD_LIBRARY_PATH="$SDL3DIR:$SDL_USER/ex32/usr/lib/x86_64-linux-gnu:$SDL_USER/ex/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
say "cjpm test …"
if ! cjpm test 2>&1 | tee /tmp/dd-cjtest.log; then
    die "cjpm test 失败（详见上方输出）"
fi
CLEAN_LOG="$(sed -e $'s/\x1b\\[[0-9;?]*[A-Za-z]//g' /tmp/dd-cjtest.log)"
PASSED="$(printf '%s' "$CLEAN_LOG" | grep -E 'PASSED: *[0-9]+, *SKIPPED: *[0-9]+' | tail -1 | grep -oE 'PASSED: *[0-9]+' | grep -oE '[0-9]+' || echo 0)"
SKIPPED="$(printf '%s' "$CLEAN_LOG" | grep -E 'PASSED: *[0-9]+, *SKIPPED: *[0-9]+' | tail -1 | grep -oE 'SKIPPED: *[0-9]+' | grep -oE '[0-9]+' || echo 0)"
FAILED="$(printf '%s' "$CLEAN_LOG" | grep -E 'FAILED: *[0-9]+' | tail -1 | grep -oE '[0-9]+' || echo 1)"
echo "CJTEST_SUMMARY passed=$PASSED skipped=$SKIPPED failed=$FAILED"
[ "$FAILED" = "0" ] || die "有失败用例（$FAILED）"
exit 0
