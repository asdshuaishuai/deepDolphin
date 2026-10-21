#!/bin/sh
# build-deb.sh — 出 deepin/UOS 可安装的 deb（M2-7 · D7 达标的必经一步）。
#
# 【它解决什么】
#   D7 达标标准：「可以出包装进 deepin（deb），安装后不依赖任何 sysroot/开发容器环境变量」。
#   本脚本做两件事：
#     ① **组装包**（二进制 / desktop / D-Bus service / 图标 / metainfo / control / postinst）；
#     ② **校验依赖清单与二进制实际依赖一致**（双向差集必须为空）——
#        漏声明 = 装上跑不起来；多声明 = 装不上（包名不存在）。
#        「加了新依赖忘改清单」在这一步就会红，而不是等用户装完才发现。
#
# 【依赖清单在哪】
#   `scripts/deb-deps.txt` —— **唯一出处**。本脚本只读它，不在别处抄一份。
#
# 【用法】
#   sh scripts/build-deb.sh [输出目录]
#   默认输出到 `build/deb/`。
#
# 【为什么不用 debuild】
#   debuild 需要 debian/ 目录树（一整套打包规范）；本仓只要一个能装能跑的 deb，
#   `dpkg-deb` 足够，且不引入「debian/ 目录与 CMake 版本号两处真相源」。
#   版本号仍取 **CMakeLists.txt 的 project(VERSION …)**（单一真相源，不手抄）。
#
# 退出码：0 = 成功；非 0 = 校验失败或打包失败（响亮失败，别产出半成品）。

set -e

SRC="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$SRC/build/deb}"
BIN="$SRC/build/deepDolphin"
DEPS="$SRC/scripts/deb-deps.txt"

die() { echo "✗ build-deb: $*" >&2; exit 1; }
step() { echo "› $*"; }

# ── 0. 前置检查 ───────────────────────────────────────────────
[ -f "$BIN" ] || die "找不到可执行文件 $BIN（先 cmake --build build）"
[ -f "$DEPS" ] || die "找不到依赖清单 $DEPS"
command -v dpkg-deb >/dev/null 2>&1 || die "没有 dpkg-deb"
command -v readelf >/dev/null 2>&1 || die "没有 readelf（binutils）"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── 1. 版本号：唯一真相源 = CMakeLists 的 project(VERSION …) ──
VER="$(sed -n 's/^project(deepDolphin VERSION \([0-9.]*\).*/\1/p' "$SRC/CMakeLists.txt" | head -1)"
[ -n "$VER" ] || die "从 CMakeLists.txt 读不到版本号（project(deepDolphin VERSION …) 变了？）"
step "版本 $VER（取自 CMakeLists.txt）"

# ── 2. 依赖清单校验（双向差集必须为空）─────────────────────
step "校验依赖清单 ↔ 二进制实际依赖"

# 2a. 清单里的包名（去注释去空行）
sed 's/#.*//' "$DEPS" | tr -d ' \t' | grep -v '^$' | sort -u > "$TMP/deps.list"

# 2b. 二进制实际 DT_NEEDED → soname
readelf -d "$BIN" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | sort -u > "$TMP/needed.txt"
[ -s "$TMP/needed.txt" ] || die "从 $BIN 读不出 DT_NEEDED（readelf 输出格式变了？）"

# 2c. 每个 soname 反查包名（ldconfig 找真实路径 → dpkg -S 反查；/lib 是 /usr/lib 的软链，要归一）
: > "$TMP/needed.pkgs"
missing_soname=""
while IFS= read -r soname; do
    [ -n "$soname" ] || continue
    path="$(ldconfig -p 2>/dev/null | grep -F "$soname " | head -1 | sed 's/.*=> //' | sed 's|^/lib/|/usr/lib/|')"
    if [ -z "$path" ]; then
        missing_soname="$missing_soname $soname"
        continue
    fi
    pkg="$(dpkg -S "$path" 2>/dev/null | head -1 | cut -d: -f1)"
    [ -n "$pkg" ] || pkg="__UNKNOWN__$soname"
    echo "$pkg" >> "$TMP/needed.pkgs"
done < "$TMP/needed.txt"
if [ -n "$missing_soname" ]; then
    die "本机找不到这些库：$missing_soname（打包机上要先装齐运行库）"
fi
sort -u "$TMP/needed.pkgs" > "$TMP/needed.pkgs.sorted"

# 2d. 差集：清单缺的（装上跑不起来）
MISSING="$(comm -23 "$TMP/needed.pkgs.sorted" "$TMP/deps.list" | tr '\n' ' ')"
[ -z "$MISSING" ] || die "依赖清单缺这些包（漏了 = 装上跑不起来）：$MISSING
    → 补进 $DEPS"

# 2e. 差集：清单多的（包名不存在 = 装不上）
EXTRA="$(comm -13 "$TMP/needed.pkgs.sorted" "$TMP/deps.list" | tr '\n' ' ')"
# 插件包不在 DT_NEEDED 里，是**故意**多出来的 —— 单独放行那几条。
EXTRA_PKG=""
for p in $EXTRA; do
    case "$p" in
        dde-qt6integration|dde-qt6xcb-plugin) ;;
        *) EXTRA_PKG="$EXTRA_PKG $p" ;;
    esac
done
[ -z "$EXTRA_PKG" ] || die "依赖清单里这些包没有对应的 DT_NEEDED（写错了？）：$EXTRA_PKG"

# 2f. 清单里每个包名都必须真实存在（抓「包名抄错」）
# ⚠ 用 `dpkg-query -W` 而不是 `dpkg -s`：libc6 这类**多架构包**（amd64 + i386 同时装）
#   会让 `dpkg -s libc6` 报「软件包名含糊不清」—— 按实例逐个看 Status 更稳。
for p in $(cat "$TMP/deps.list"); do
    dpkg-query -W -f='${Status}\n' "$p" 2>/dev/null | grep -q "install ok installed" \
        || die "依赖清单里的包「$p」在本机没装 —— 包名写错了？（装不上）"
done

# 2g. 运行时插件包必须在清单里（缺了 → 静默降级成「纯 Qt 感」，不报错）
for plugin in /usr/lib/x86_64-linux-gnu/qt6/plugins/styles/libchameleon.so \
              /usr/lib/x86_64-linux-gnu/qt6/plugins/platforms/libdxcb.so; do
    [ -f "$plugin" ] || continue
    pkg="$(dpkg -S "$plugin" 2>/dev/null | head -1 | cut -d: -f1)"
    [ -n "$pkg" ] || continue
    grep -qx "$pkg" "$TMP/deps.list" || die "运行时插件 $plugin 属于「$pkg」，但依赖清单里没有它
    → 缺了不会报错，只会静默降级（DTK 样式丢失 = 纯 Qt 感）"
done

# 2h. 依赖清单里的包必须在 **apt 仓库**里能装到（不只是「本机已装」）
#   ⚠⚠ **与 2f 的分工**（别以为 2h 能单独抓包名错误）：
#   · 2f 抓「**包名写错 / 本机没装**」⇒ dpkg-query 直接红；
#   · 2h 抓「**本机装着、但目标机源里没有**」⇒ 典型场景：开发机装的是私有源/已从源里
#     移除的版本 ⇒ 本机 `dpkg-query` 说「装着」⇒ 目标机却**装不上**。
#   ⚠ **「apt 查不到该包」会输出空**（与「本机没配源/离线」无法区分）⇒ 那种情况
#     本检查判为 SKIP（不误红）⇒ 由 **2f** 兜住（包名写错 ⇒ 本机也没装 ⇒ 2f 红）。
#   ⚠ 2f 验的是「**本机装着**」—— 那**不等于**「**目标机装得上**」：
#   本机装着的包可能已经不在源里（被移除 / 从别处装的 / 私有源），
#   ⇒ 目标机（干净 deepin 25）会「找不到包」⇒ **deb 装了却用不了**。
#   ⇒ 这一条是 D7「装得上」那一半里**不依赖容器**就能做的那部分。
# ⚠⚠ **必须 LC_ALL=C**：apt 的输出是**本地化**的 —— 本机是中文「候选：」而不是
#   `Candidate:` ⇒ 只按英文写脚本，换台机器/换 locale 就**全部误判成缺失**
#   （实测踩过：17 个明明存在的包全被判「查不到」）。
if command -v apt-cache >/dev/null 2>&1; then
    MISSING_PKG=""
    NO_CAND=0
    for p in $(cat "$TMP/deps.list"); do
        CAND="$(LC_ALL=C apt-cache policy "$p" 2>/dev/null | sed -n 's/^  Candidate: //p')"
        if [ -z "$CAND" ]; then
            NO_CAND=1
            break
        fi
        [ "$CAND" = "(none)" ] && MISSING_PKG="$MISSING_PKG $p"
    done
    if [ "$NO_CAND" -eq 1 ]; then
        echo "‣ SKIP：apt 查不到候选版本（本机可能没配源 / 离线）—— 这一项**未验证**，不算通过"
    elif [ -n "$MISSING_PKG" ]; then
        die "依赖清单里这些包在 apt 仓库里**查不到**（目标机装不上）：$MISSING_PKG"
    else
        step "依赖包在 apt 仓库里都存在 ✓（$(wc -l < "$TMP/deps.list") 个，目标机装得上）"
    fi
else
    echo "‣ SKIP：没有 apt-cache —— 这一项**未验证**，不算通过"
fi

step "依赖清单自洽 ✓（$(wc -l < "$TMP/deps.list") 个包，无缺无多）"

# ── 3. 组装目录树 ───────────────────────────────────────────
step "组装包内容"
PKG="$TMP/deepdolphin"
mkdir -p "$PKG/DEBIAN" \
         "$PKG/usr/bin" \
         "$PKG/usr/share/applications" \
         "$PKG/usr/share/dbus-1/services" \
         "$PKG/usr/share/metainfo" \
         "$PKG/usr/share/icons/hicolor/scalable/apps" \
         "$PKG/usr/share/icons/hicolor/symbolic/apps"

# ⚠⚠ **可执行的安装路径是唯一真相源**（DEST_BIN）——
#   D-Bus service 文件里的 `Exec=` **必须**写绝对路径（dbus 激活不做 PATH 搜索，
#   实测见 data/cn.deepdolphin.app.service 的注释）⇒ 那条路径要跟这里一致。
#   ⇒ 装之前先**校验**：不一致直接构建失败，不让两处悄悄漂。
DEST_BIN="/usr/bin/deepDolphin"
SERVICE_SRC="$SRC/data/cn.deepdolphin.app.service"
SERVICE_EXEC="$(sed -n 's/^Exec=//p' "$SERVICE_SRC" | head -1 | awk '{print $1}')"
if [ "$SERVICE_EXEC" != "$DEST_BIN" ]; then
    die "D-Bus service 的 Exec（$SERVICE_EXEC）与实际安装路径（$DEST_BIN）不一致！\
     dbus 激活不做 PATH 搜索，路径写错 ⇒ 从启动器点图标会激活失败。"
fi
# ⚠ service 的 Exec **不许带参数**：激活 = 正常启动客户端，它自己在 GUI 主路径里
#   注册总线名（main.cpp 的 AppService::registerOnBus）。
#   ⚠ 原来写的 `--dbus-service` 这个 flag **客户端根本不认识**（全项目 grep 无此 flag）。
# ⚠ `${SEXEC#* }` 在**没有空格**时会原样返回（没匹配到 `* `）⇒ 会把
#   「无参数」误判成「有参数」⇒ 这里显式分两种情况取。
SERVICE_LINE="$(sed -n 's/^Exec=//p' "$SERVICE_SRC" | head -1)"
case "$SERVICE_LINE" in
    *\ *) SERVICE_ARGS="${SERVICE_LINE#* }" ;;
    *)   SERVICE_ARGS="" ;;
esac
if [ -n "$SERVICE_ARGS" ]; then
    die "D-Bus service 的 Exec 不该带参数（当前：$SERVICE_ARGS）——\
     客户端没有对应的 flag，带了会被忽略。"
fi

install -m 0755 "$BIN" "$PKG${DEST_BIN}"
install -m 0644 "$SRC/data/cn.deepdolphin.app.desktop" \
                "$PKG/usr/share/applications/cn.deepdolphin.app.desktop"
install -m 0644 "$SRC/data/cn.deepdolphin.app.service" \
                "$PKG/usr/share/dbus-1/services/cn.deepdolphin.app.service"
install -m 0644 "$SRC/data/metainfo/cn.deepdolphin.app.metainfo.xml" \
                "$PKG/usr/share/metainfo/cn.deepdolphin.app.metainfo.xml"
install -m 0644 "$SRC/data/icons/deepdolphin.svg" \
                "$PKG/usr/share/icons/hicolor/scalable/apps/deepdolphin.svg"

# hicolor 各尺寸位图
for png in "$SRC"/data/icons/hicolor/*/apps/deepdolphin.png; do
    [ -f "$png" ] || continue
    size="$(basename "$(dirname "$(dirname "$png")")")"
    mkdir -p "$PKG/usr/share/icons/hicolor/$size/apps"
    install -m 0644 "$png" "$PKG/usr/share/icons/hicolor/$size/apps/deepdolphin.png"
done
# symbolic 图标
for svg in "$SRC"/data/icons/symbolic/apps/*.svg; do
    [ -f "$svg" ] || continue
    install -m 0644 "$svg" "$PKG/usr/share/icons/hicolor/symbolic/apps/$(basename "$svg")"
done

# ── 4. DEBIAN/control（Depends 来自清单，不手抄）────────────
DEPS_CSV="$(paste -sd, "$TMP/deps.list")"
cat > "$PKG/DEBIAN/control" <<EOF
Package: cn.deepdolphin.app
Version: $VER
Architecture: amd64
Maintainer: deepin Community <deepin-community@union.org>
Depends: $DEPS_CSV
Section: utils
Priority: optional
Homepage: https://github.com/asdshuaishuai/deepDolphin
Description: moonGit/deepGit 项目群进度面板（deepin/DDE 客户端）
 deepDolphin 是 moonGit 引擎的 deepin/DDE 客户端：一眼看全项目群的进度
 （KPI 卡片、语言分布、里程碑、工程脉搏、提交构成），并对接引擎完成更新、
 git 操作与里程碑管理。AI 摘要与 AI 助手在客户端本地完成，未配置时如实降级。
EOF

# ── 5. postinst（DBus 激活环境；缺了 DBusActivatable 拉不起来）──
cat > "$PKG/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
# desktop 文件是 DBusActivatable=true：面板没起来时会话总线会拉起本服务，
# 拉起时拿得到 DISPLAY / XDG_CURRENT_DESKTOP 才能落到 X11 界面上。
if [ "$1" = "configure" ] && command -v dbus-send >/dev/null 2>&1; then
    dbus-send --system --type=method --dest=org.freedesktop.DBus / \
        org.freedesktop.DBus.UpdateActivationEnvironment \
        "dict:string:variant:" \
        "DISPLAY" "string:${DISPLAY:-}" \
        "XDG_CURRENT_DESKTOP" "string:${XDG_CURRENT_DESKTOP:-}" \
        "XDG_SESSION_COOKIE" "string:${XDG_SESSION_COOKIE:-}" >/dev/null 2>&1 || true
fi
exit 0
EOF
chmod 0755 "$PKG/DEBIAN/postinst"

# ── 6. 打包 ─────────────────────────────────────────────────
mkdir -p "$OUT_DIR"
DEB_PATH="$OUT_DIR/cn.deepdolphin.app_${VER}_amd64.deb"
rm -f "$DEB_PATH"
dpkg-deb --root-owner-group --build "$PKG" "$DEB_PATH" >/dev/null

# ── 7. 产物自检（响亮失败：别把坏包交给用户）────────────────
step "自检产物"
dpkg-deb --info "$DEB_PATH" > "$TMP/info.txt" 2>/dev/null || die "dpkg-deb --info 失败（包坏了）"
dpkg-deb --contents "$DEB_PATH" >/dev/null 2>&1 || die "dpkg-deb --contents 失败（包坏了）"
grep -q "libdtk6widget" "$TMP/info.txt" \
    || die "产物的 Depends 里没有 libdtk6widget（DTK 依赖漏了 = 装上跑不起来）"
grep -q "dde-qt6integration" "$TMP/info.txt" \
    || die "产物的 Depends 里没有 dde-qt6integration（DTK 样式漏了 = 静默降级成纯 Qt 感）"
# 包内二进制不许带 RPATH（指向开发机路径 = 换台机器就起不来）
# ⚠⚠⚨ 批 CE：**外部工具的失败不许被当成「检查通过」**。
#   ⇒ 以前是 `if readelf … | grep -qiE "rpath|runpath"; then die; fi`
#     ⇒ readelf **失败**（读不了二进制 / 工具崩了）⇒ 管道无输出 ⇒
#     **不进 then 分支** ⇒ **静默判「没带 RPATH」⇒ 通过** ⇒ **假绿**
#     ⇒ ⚠⚠⚨ 实测（stub 一个失败的 readelf）：旧形态 **rc=0 走到末尾**。
#   ⇒ 现在：**接住 readelf 的退出码** ⇒ 非 0 ⇒ **判失败**（工具失败 = 没验过，
#     不许当成「检查通过」—— 与批 CB/CC/CD 同款口径）。
_re_rc=0
_re_out="$(readelf -d "$PKG/usr/bin/deepDolphin" 2>&1)" || _re_rc=$?
if [ "$_re_rc" -ne 0 ]; then
    die "readelf 读不了包内二进制（退出码 $_re_rc）⇒ **RPATH 检查未验证**，不算通过（$_re_out）"
fi
if printf '%s\n' "$_re_out" | grep -qiE "rpath|runpath"; then
    die "包内二进制带 RPATH/RUNPATH —— 指向开发机路径，装到别的机器就找不到库"
fi
# D7 的核心：解包后**零环境变量**下不许有缺失的库（不靠 LD_LIBRARY_PATH 救）
#   —— 装到干净 deepin 25 上能不能起来，就看这一条。
rm -rf "$TMP/unpack" && mkdir -p "$TMP/unpack"
# ⚠⚠⚨ 批 CE：解包失败**必须响亮失败**（以前靠 `set -e` 静默中止 ⇒ 没有 die 消息，
#   看着像「跑到一半没了」⇒ **诊断失真**）。
dpkg-deb -x "$DEB_PATH" "$TMP/unpack" || die "解包失败：$DEB_PATH（产物自检的前提就没有 ⇒ 后面全是空转）"
# ⚠⚠⚨ 批 CE：**外部工具的失败不许被当成「检查通过」**（D7 的核心验收！）。
#   ⇒ 以前是 `_nf="$(ldd … | grep -c 'not found' || true)"`
#     ⇒ ldd **失败**（二进制不存在 / 不可读 / 工具崩了 ⇒ 报 "cannot open"）
#     ⇒ 计数 **0** ⇒ 「无缺失库」⇒ **判通过** ⇒ **假绿**
#     ⇒ ⚠⚠⚨ 实测（stub 一个失败的 ldd）：旧形态 **rc=0 走到末尾**。
#     ⇒ ⚠⚠⚨ 假绿的代价：**发出一个装不起来的 deb**。
#   ⇒ 现在：**接住 ldd 的退出码** ⇒ 非 0 ⇒ **判失败**（没验过 ≠ 验过了）。
#   ⚠ `grep -c` 没匹配时退出码是 1 ⇒ 计数那步仍要 `|| true`（否则 set -e 静默中止）。
_ldd_rc=0
_ldd_out="$(env -u LD_LIBRARY_PATH ldd "$TMP/unpack/usr/bin/deepDolphin" 2>&1)" || _ldd_rc=$?
if [ "$_ldd_rc" -ne 0 ]; then
    die "ldd 读不了解包后的二进制（退出码 $_ldd_rc）⇒ **D7 缺库检查未验证**，不算通过（$_ldd_out）"
fi
_nf="$(printf '%s\n' "$_ldd_out" | grep -c 'not found' || true)"
_nf="${_nf:-0}"
[ "$_nf" = "0" ] || die "解包后的二进制有 $_nf 个库 not found（D7 不达标：装到干净系统上起不来）"

echo "✓ 已生成 $DEB_PATH"
dpkg-deb --info "$DEB_PATH" | sed -n '1,12p'
