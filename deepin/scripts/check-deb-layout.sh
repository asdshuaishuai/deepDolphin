#!/usr/bin/env bash
# check-deb-layout.sh — **D7 准验收**：deb 产物的「装完能不能用」静态+行为检查。
#
# 【为什么要有它】D7 的最终验收是「干净 deepin 25 容器里 dpkg -i + 启动」，
#   本机**没有容器运行时**（无 docker/podman）⇒ 那一段做不了。
#   ⇒ 但「装完能不能用」里**不依赖容器**的那部分是可以做的：
#     把 deb **解包**到临时目录（不装进系统，不污染本机），
#     然后按**包内的真实布局**逐项检查「装完之后点图标能不能起来」。
#   ⚠ 这**不是**替代 D7 容器验收 —— 它覆盖的是「产物自身自洽」这一半，
#     「目标机依赖齐不齐」那一半仍然要真机/容器。
#
# 【查什么】（每条都是「装完能不能用」的一个必要条件）
#   ① 可执行在包内 /usr/bin 且可执行
#   ② D-Bus service 的 Exec 是**绝对路径**且指向**包内存在的可执行**
#      ⇒ ⚠ dbus-daemon 激活时**不做 PATH 搜索**（实测：裸名 `true` 也报
#        Spawn.ExecFailed）⇒ 写裸名 ⇒ 从启动器点图标激活失败。
#   ③ D-Bus service 的 Exec **不带参数** ⇒ 激活 = 正常启动客户端，
#      由它自己在 GUI 主路径里注册总线名（带客户端不认识的 flag = 白带）
#   ④ desktop 的 Exec 指向的可执行在包内存在（裸名要在 /usr/bin 里找得到）
#   ⑤ desktop 的 Icon 在包内有对应图标（scalable 或各尺寸 png）
#   ⑥ desktop 若 DBusActivatable=true ⇒ service 文件**必须**存在
#      （否则点图标既不启动也不激活 ⇒ 点了没反应）
#   ⑦ metainfo 的 <id> == desktop 文件名去后缀（app id 三处一致）
#   ⑧ 可执行在**空环境**下能跑 --version（不依赖构建机环境变量）
#   ⑨ 图标文件非空（0 字节的图标 = 装了也是空白）
#
# 【用法】sh scripts/check-deb-layout.sh <deb 路径>
#   退出码 0 = 全部通过；非 0 = 有失败项（stderr 有原因）。
set -uo pipefail

DEB="${1:-}"
pass=0
fail=0

if [ -z "$DEB" ] || [ ! -f "$DEB" ]; then
    echo "✗ 用法：$0 <deb 路径>" >&2
    exit 2
fi
if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "SKIP: 没有 dpkg-deb（本门**未验证**，不算通过）" >&2
    exit 3
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/root"
mkdir -p "$ROOT"
if ! dpkg-deb -x "$DEB" "$ROOT" 2>"$TMP/extract.log"; then
    # ⚠⚠⚨ 批 DZ：解包日志里**可能带随机临时目录名** ⇒ 剥掉再打印
    #   ⇒ 输出里不许有随机量 ⇒ 两遍输出才能**逐字节相同**（批 DY 纪律：清随机量在**产出侧**）
    _ex="$(head -3 "$TMP/extract.log" | sed "s|$TMP||g")"
    echo "✗ 解包失败：$_ex" >&2
    exit 1
fi

ok() { echo "  ✓ $1"; pass=$((pass+1)); }
no() { echo "  ✗ $1" >&2; fail=$((fail+1)); }

# 读 desktop / service 的键值（只看主段，不看 Desktop Action 段）
dval() { # dval <文件> <键>
    sed -n 's/^'"$2"'=//p' "$1" 2>/dev/null | head -1
}

# ⚠⚠⚨ 批 DZ · **包内相对路径**单独记一份（打印用）⇒ 输出里不许出现随机量
#   ⇒ `$ROOT` 是 `mktemp -d` 的**随机名** ⇒ 直接打印它 ⇒ 两遍输出**必然不同**
#   ⇒ ⇒ 双跑门**恒红** ⇒ **假红**（批 DL：假红比假绿更坏）⇒ 打印一律用相对路径
DESKTOP_REL="/usr/share/applications/cn.deepdolphin.app.desktop"
SERVICE_REL="/usr/share/dbus-1/services/cn.deepdolphin.app.service"
METAINFO_REL="/usr/share/metainfo/cn.deepdolphin.app.metainfo.xml"
BIN_REL="/usr/bin/deepDolphin"
DESKTOP="$ROOT$DESKTOP_REL"
SERVICE="$ROOT$SERVICE_REL"
METAINFO="$ROOT$METAINFO_REL"
BIN="$ROOT$BIN_REL"

# ① 可执行
if [ -x "$BIN" ]; then ok "可执行在包内且可执行（/usr/bin/deepDolphin）"; else no "可执行缺失或不可执行：$BIN_REL"; fi

# ② D-Bus service：绝对路径 + 指向包内存在的可执行
if [ ! -f "$SERVICE" ]; then
    no "D-Bus service 文件缺失（$SERVICE_REL）"
else
    SEXEC="$(dval "$SERVICE" Exec)"
    SPATH="${SEXEC%% *}"
    case "$SPATH" in
        /*) ok "D-Bus service 的 Exec 是绝对路径（$SPATH）" ;;
        *)  no "D-Bus service 的 Exec 不是绝对路径（$SPATH）—— dbus 激活不做 PATH 搜索，会激活失败" ;;
    esac
    if [ -n "$SPATH" ] && [ -x "$ROOT$SPATH" ]; then
        ok "D-Bus service 的 Exec 指向的可执行在包内存在（$SPATH）"
    else
        no "D-Bus service 的 Exec 指向的可执行**不在包内**（$SPATH）"
    fi
    # ③ 不带参数
    # ⚠ `${SEXEC#* }` 在**没有空格**时原样返回 ⇒ 无参数会被误判成「有参数」。
    case "$SEXEC" in
        *\ *) SARGS="${SEXEC#* }" ;;
        *)   SARGS="" ;;
    esac
    if [ -z "$SARGS" ]; then
        ok "D-Bus service 的 Exec 不带参数（激活 = 正常启动客户端）"
    else
        no "D-Bus service 的 Exec 带了参数（$SARGS）—— 客户端没有对应 flag，带了会被忽略"
    fi
fi

# ④ desktop 的 Exec
if [ ! -f "$DESKTOP" ]; then
    no "desktop 文件缺失（$DESKTOP_REL）"
else
    DEXEC="$(dval "$DESKTOP" Exec)"
    DPATH="${DEXEC%% *}"
    case "$DPATH" in
        /*) DABS="$ROOT$DPATH" ;;
        *)  DABS="$ROOT/usr/bin/$DPATH" ;;   # 裸名 ⇒ 按 desktop 规范在 PATH 里找 ⇒ /usr/bin
    esac
    if [ -x "$DABS" ]; then ok "desktop 的 Exec 指向的可执行在包内存在（$DEXEC）"; else no "desktop 的 Exec 指向的可执行不在包内（$DEXEC）"; fi

    # ⑤ Icon
    ICON="$(dval "$DESKTOP" Icon)"
    if [ -z "$ICON" ]; then
        no "desktop 没有 Icon 键（装了也没有图标）"
    elif [ -f "$ROOT/usr/share/icons/hicolor/scalable/apps/$ICON.svg" ] \
        || ls "$ROOT/usr/share/icons/hicolor/"*/apps/"$ICON".png >/dev/null 2>&1; then
        ok "desktop 的 Icon 在包内有对应图标（$ICON）"
    else
        no "desktop 的 Icon 在包内找不到（$ICON）"
    fi

    # ⑥ DBusActivatable=true ⇒ service 必须存在
    if [ "$(dval "$DESKTOP" DBusActivatable)" = "true" ]; then
        if [ -f "$SERVICE" ]; then ok "desktop 声明 DBusActivatable=true ⇒ service 文件在（激活路径有落点）"
        else no "desktop 声明 DBusActivatable=true 但 service 文件缺失 ⇒ 点图标会没反应"; fi
    fi
fi

# ⑦ metainfo 的 app id
if [ ! -f "$METAINFO" ]; then
    no "metainfo 缺失（$METAINFO_REL）"
else
    MID="$(sed -n 's/.*<id>\(.*\)<\/id>.*/\1/p' "$METAINFO" | head -1)"
    if [ "$MID" = "cn.deepdolphin.app" ]; then
        ok "metainfo 的 <id> 与 desktop 文件名一致（$MID）"
    else
        no "metainfo 的 <id>（$MID）与 desktop 文件名（cn.deepdolphin.app）不一致"
    fi
fi

# ⑧ 空环境下能跑 --version
if [ -x "$BIN" ]; then
    # ⚠⚠⚨ 批 BX：**必须查退出码**，且 **stderr 不许混进 stdout**。
    #   以前这一门是 `VOUT="$(env -i "$BIN" --version 2>&1 | head -3)"` +「有输出就算过」
    #   ⇒ **退出码完全没查** + **stderr 被合并进 stdout**
    #   ⇒ 实测：一个「先往 stderr 打一行警告、再段错误崩掉」的二进制
    #   **也能过这一门**（判「✓ 可执行在空环境下能跑起来」）⇒ **假绿**。
    #   ⇒ 现在：退出码非 0 ⇒ 判失败；stdout 空 ⇒ 判失败；stderr 原样透出（崩点看得见）。
    VRC=0
    VOUT="$(env -i "$BIN" --version)" || VRC=$?
    if [ "$VRC" -ne 0 ]; then
        no "可执行在空环境下跑 --version 退出码 $VRC（装完起不来；崩了也走这里）"
    elif ! printf '%s' "$VOUT" | grep -q .; then
        no "可执行在空环境下跑 --version 没有输出（装完可能起不来）"
    else
        ok "可执行在**空环境**下能跑起来（--version：$(printf '%s' "$VOUT" | head -1)）"
    fi
fi

# ⑨ 图标非空
EMPTY_ICON=0
for f in $(cd "$ROOT/usr/share/icons" 2>/dev/null && find . -type f 2>/dev/null | LC_ALL=C sort); do
    [ -s "$ROOT/usr/share/icons/$f" ] || { EMPTY_ICON=1; echo "      零字节图标：/usr/share/icons/${f#./}"; }
done
if [ "$EMPTY_ICON" -eq 0 ]; then ok "包内图标都非空"; else no "包内存在零字节图标（装了也是空白）"; fi

echo "──── check-deb-layout: $pass passed, $fail failed ────"
[ "$fail" -eq 0 ]
