#!/usr/bin/env bash
# ci.sh — deepin 客户端本地 CI 门（DDE-INTEGRATION-PLAN.md §4.1/§4.3）。
#
# 1. --selfcheck：断言「0 failed 且 ≥58 passed」（例数只增不减）
# 2. 截图矩阵（亮/暗 × 4 页）→ docs/snapshots，落盘后人工 diff 基线
# 3. desktop / metainfo 校验：desktop-file-validate / appstream-util 缺工具显式 SKIP
#    （SKIP 不算失败——工具随 deepin 打包环境到位，硬门随之生效）
# 4. --platform-probe 正式断言：exit 0 且输出含 backend= 行
# 5. D2 grep 门：DS::*（DesignTokens）之外出现色值/px 字号即缺陷 —— 独立成
#    scripts/ci-d2.sh（可单独跑，负控能精确打）。批 N 已把 M3-3 登记的 4 处存量
#    全收进 token，上限降到 0（只减不增）
# 6. --agent-selftest（恒走 mock 渠道）
# 7. verify 接线源扫描门：引擎 verify 的判定层与接线点必须都在（判定不许藏回视图）
# 8. 图谱 Canvas 契约门：Canvas2D 覆盖契约清单 24 个方法 + logic/models 零 QWidget 头
#  9. 架构图接线门：取数（graph arch --format scene）→ 判定（视口/命中/回执）→
#     渲染（SceneRender）→ 接线（详情页入口 → 面板 → 架构图窗 → 画布）四段都在；
#     生成/导出必须走 Text 契约（回执型命令，stdout 是人话不是 JSON）
#
# 用法：scripts/ci.sh [build目录]（默认 build/）
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-$SRC/build}"
BIN="$BUILD/deepDolphin"

# 运行库环境提前到步骤 1 之前：selfcheck 也要加载 sysroot 的 Qt6/DTK6——原先导出
# 在步骤 2，无 sysroot rpath 的环境下步骤 1 的二进制根本起不来。用"无条件前置 +
# 保留旧值"而非 ${VAR:-默认}：预置了 LD_LIBRARY_PATH 的环境（如容器运行时自带
# /opt/... 路径）会原样沿用旧值，sysroot 永远进不去。
export LD_LIBRARY_PATH="$HOME/.local/dd-sysroot/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$HOME/.local/dd-sysroot/usr/lib/x86_64-linux-gnu/qt6/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

echo "› 1/12 selfcheck（断言 0 failed 且 ≥58 passed）"
SELFCHECK_OUT="$("$BIN" --selfcheck || true)"
printf '%s\n' "$SELFCHECK_OUT" | tail -1
SC_PASSED="$(printf '%s\n' "$SELFCHECK_OUT" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '[0-9]+' || true)"
SC_FAILED="$(printf '%s\n' "$SELFCHECK_OUT" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '[0-9]+' || true)"
if [ -z "$SC_PASSED" ] || [ -z "$SC_FAILED" ]; then
    echo "✗ selfcheck 输出无法解析（期待尾行 selfcheck: N passed, M failed——崩溃/早退？）" >&2
    exit 1
fi
if [ "$SC_FAILED" -ne 0 ] || [ "$SC_PASSED" -lt 58 ]; then
    echo "✗ selfcheck 未达标：${SC_PASSED} passed / ${SC_FAILED} failed（要求 0 failed 且 ≥58 passed）" >&2
    exit 1
fi
echo "✓ selfcheck ${SC_PASSED} passed, ${SC_FAILED} failed"

echo "› 2/12 截图矩阵（离屏）"
# ⚠ 这一步**强制** offscreen，不继承环境里的 QT_QPA_PLATFORM。
#   理由（决策 86）：基线是离屏拍的；若宿主已设 QT_QPA_PLATFORM=dxcb;xcb，
#   快照会带 DTK 原生窗口装饰与 chameleon 样式 —— 同一份代码拍出另一张脸，
#   视觉 diff 门被环境牵着走。离屏才是「同机位」的可复现前提。
#   注意：第 4 步的平台探针**要**真实 backend，故那里不强制 offscreen。
mkdir -p "$SRC/docs/snapshots"
for theme in light dark; do
    # ⚠ setupguide = **引擎缺失首屏**（批 AH）：那个界面在正常启动时根本不出现
    #   （引擎在 ⇒ 落仪表盘）⇒ 以前 docs/snapshots/*-setupguide.png 是**死基线**
    #   （拍不出、没人比）——死基线比没基线更隐蔽：它让人以为「首屏有视觉保障」。
    for sec in dashboard board milestones setupguide; do
        QT_QPA_PLATFORM=offscreen DEEPDOLPHIN_THEME="$theme" "$BIN" --snapshot \
            "$SRC/docs/snapshots/${theme}-${sec}.png" --section "$sec" \
            | tail -1
    done
    # 状态色样张（批 R）：把**每一档状态色**都画出来，改色 ⇒ 色卡 diff 红。
    #   （批 T 之前，面板快照拍的是空态 ⇒ 状态点一个都没画进去，对状态色是**空门**；
    #     批 T 起用夹具后面板快照已有真实内容，但这张色卡仍留着 ——
    #     它是**逐档**的，面板快照只覆盖夹具里恰好出现的那几档。）
    QT_QPA_PLATFORM=offscreen DEEPDOLPHIN_THEME="$theme" "$BIN" --color-sample \
        "$SRC/docs/snapshots/${theme}-colors.png" | tail -1
done

# ⚠ **重拍比字节**（批 T）—— 基线必须**逐字节可重现**。
#   为什么这道门是硬的：基线一旦带墙钟（侧栏「上次刷新 HH:mm」是本地时区渲染），
#   CI **每次**都出 diff ⇒ 人就学会忽略 diff ⇒ 基线退化成空门（比没门更糟）。
#   这道门盯的是**行为**（同一份代码两次拍出同一张图），不是「我改的这两个文件看着对」——
#   将来谁往渲染路径里塞了墙钟，它就红。
#   夹具 + 固定刷新时刻 + 快照进程固定 TZ=UTC（见 main.cpp）⇒ 6 张面板快照逐字节恒定。
#
# ⚠ **再拍一份「换了时区的」**：这一拍专门抓「渲染跟着宿主时区走」。
#   应用内部固定 TZ=UTC ⇒ 外层 TZ 传什么都一样 ⇒ 字节必须相同。
#   哪天有人把 main.cpp 里那句 qputenv("TZ","UTC") 删了 ⇒ 宿主时区渗进来
#   ⇒ 这两张立刻不同 ⇒ 门红（而只靠接线门盯那一行是不够的：门要能**行为**地抓住）。
# ⚠ 对比的必须是**两个互相不同**的时区（UTC 与 America/New_York）——
#   若拿「宿主时区」当其中一个，宿主恰好就是那个时区时（实测本机就是 Asia/Shanghai）
#   ⇒ 两张必然相同 ⇒ 门永远绿 ⇒ 又一个空门（负控实测，第十五次「同名/同形互相顶替」）。
REPRO_DIR="$(mktemp -d)"
repro_fail=0
repro_shoot() { # repro_shoot <主题> <区块> <输出路径> <TZ>
    TZ="$4" QT_QPA_PLATFORM=offscreen DEEPDOLPHIN_THEME="$1" "$BIN" --snapshot \
        "$3" --section "$2" >/dev/null 2>&1
}
for theme in light dark; do
    for sec in dashboard board milestones setupguide; do
        again="$REPRO_DIR/${theme}-${sec}.png"
        if ! repro_shoot "$theme" "$sec" "$again" "UTC"; then
            echo "✗ 重拍失败：${theme}-${sec}" >&2
            repro_fail=1
            continue
        fi
        if ! cmp -s "$SRC/docs/snapshots/${theme}-${sec}.png" "$again"; then
            echo "✗ 快照不可重现：${theme}-${sec}.png 两次拍出不同字节（基线会天天漂）" >&2
            repro_fail=1
        fi
        # 换**另一个**时区再拍一张：字节必须一模一样
        other="$REPRO_DIR/${theme}-${sec}-tz.png"
        if ! repro_shoot "$theme" "$sec" "$other" "America/New_York"; then
            echo "✗ 换时区重拍失败：${theme}-${sec}" >&2
            repro_fail=1
            continue
        fi
        if ! cmp -s "$again" "$other"; then
            echo "✗ 快照跟着宿主时区走：${theme}-${sec}.png 换 TZ 后字节不同（基线不可跨机重现）" >&2
            repro_fail=1
        fi
    done
done
rm -rf "$REPRO_DIR"
if [ "$repro_fail" -ne 0 ]; then
    echo "✗ 基线不可重现 —— 基线带墙钟就等于没有基线" >&2
    exit 1
fi
echo "✓ 8 张快照两次重拍逐字节一致，且换宿主时区后仍一致（基线可重现）"

echo "› 3/12 desktop / metainfo 校验（缺工具显式 SKIP）"
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$SRC/data/cn.deepdolphin.app.desktop" && echo "✓ desktop 合法"
else
    echo "SKIP: desktop-file-validate 未安装（装 desktop-file-validate 包后此门生效）"
fi
if command -v appstream-util >/dev/null 2>&1; then
    appstream-util validate-relax --nonet "$SRC/data/metainfo/cn.deepdolphin.app.metainfo.xml" \
        && echo "✓ metainfo 合法"
else
    echo "SKIP: appstream-util 未安装（README 决策 69 的硬门随工具到位生效）"
fi

echo "› 4/12 无头探针（平台探针 + 固定文档页四语言探针）"
# 探针断言独立成 scripts/ci-platform-probe.sh：可单独跑，负控也能精确打它。
if ! sh "$SRC/scripts/ci-platform-probe.sh" "$BIN"; then
    echo "✗ 平台探针门失败" >&2
    exit 1
fi
# ⚠ 文档语言探针（批 AA）：**真跑**一遍四语言切换，看文档窗的实际呈现有没有跟着换。
#   接线门是**源码扫描** —— 它能证明「代码里写了 setButtonText」，但证明不了
#   「换语言后按钮真的变了」⇒ 这一门补的是**行为**证据。
if ! sh "$SRC/scripts/ci-docs-lang-probe.sh" "$BIN"; then
    echo "✗ 文档语言探针门失败（换语言后界面没跟着换）" >&2
    exit 1
fi

strip_comments() {
    if command -v perl >/dev/null 2>&1; then
        perl -pe 's{//(?!:).*$}{}' "$1"
    else
        sed -e 's|//[^/].*$||' "$1"
    fi
}

echo "› 5/12 D2 grep 门（DS::* 单点真相源；散值上限 0，存量已清零）"
# 散值门独立成 scripts/ci-d2.sh：可单独跑，负控也能精确打它。
if ! sh "$SRC/scripts/ci-d2.sh" "$SRC"; then
    echo "✗ 设计系统散值门失败：src/ 下出现色值/硬编码 px 字号" >&2
    exit 1
fi

echo "› 6/12 agent 自测（mock 渠道）"
"$BIN" --agent-selftest | tail -2

echo "› 7/12 verify 接线在（源扫描：判定不许藏回视图，撤入口 ≠ 撤能力）"
# 剥注释再匹配：注释里出现的字样不算接线（否则加一行注释就能骗过门）。
WIRING_HITS=0
WIRING_FAIL=0
wire_need() { # wire_need <文件> <正则> <说明>
    local f="$1" re="$2" label="$3"
    if [ ! -f "$f" ]; then
        echo "  ✗ $label：文件不存在 $f" >&2
        WIRING_FAIL=1
        return
    fi
    # ⚠ 不用 `grep -q`：它一匹配就退出，剥注释的 perl 会收 SIGPIPE，
    #   配 set -o pipefail 整个管道判失败（接线明明在却报 ✗ —— 门自己坏了比门放水更糟）。
    if strip_comments "$f" | grep -E -- "$re" >/dev/null; then
        echo "  ✓ $label"
        WIRING_HITS=$((WIRING_HITS + 1))
    else
        echo "  ✗ $label：$f 里找不到 $re" >&2
        WIRING_FAIL=1
    fi
}
wire_need "$SRC/src/app/AppModel.cpp" 'QStringLiteral\("verify"\)' 'AppModel 调引擎 verify 命令'
wire_need "$SRC/src/app/AppModel.h" 'loadVerify' 'AppModel 暴露 loadVerify'
wire_need "$SRC/src/ui/PanelWindow.cpp" '&AppModel::verifyChanged' 'PanelWindow 消费 verifyChanged 信号'
wire_need "$SRC/src/ui/PanelWindow.cpp" 'loadVerify\(' 'PanelWindow 进详情时发起校验'
wire_need "$SRC/src/ui/pages/ProjectDetailPage.cpp" 'addWidget\(buildIntegrityCard\(\)\)' '详情页挂了文档完整性卡'
wire_need "$SRC/src/app/SelfCheck.cpp" 'DocumentIntegrity::stateOf' 'SelfCheck 覆盖四态判定'
if [ "$WIRING_FAIL" -ne 0 ]; then
    echo "✗ verify 接线门失败：判定层或接线被摘掉（撤入口 ≠ 撤能力）" >&2
    exit 1
fi
echo "✓ verify 接线完整（$WIRING_HITS 项）"

echo "› 8/12 图谱 Canvas 契约清单齐（章程 §3.5：方法清单就是移植验收清单）"
# 契约清单（引擎 docs/graph-scene-schema.md 的渲染契约层）：26 个标准 Canvas2D 方法。
# 「少实现一项，渲染器就跑不完」——本门逐个核 Canvas2D 是否声明为 override。
CANVAS_METHODS="setTransform fillRect strokeRect rect beginPath moveTo lineTo arcTo closePath arc bezierCurveTo fill stroke fillText createLinearGradient addColorStop setLineDash setLineDashOffset setShadowBlur setShadowColor setGlobalAlpha setLineWidth setStrokeStyle setFillStyle setFont setTextAlign"
CANVAS_FAIL=0
CANVAS_N=0
for m in $CANVAS_METHODS; do
    CANVAS_N=$((CANVAS_N + 1))
    # 匹配「<空白或指针星号>方法名( … override」—— 返回类型随方法而变
    # （void / QLinearGradient *），方法名前可能是空格也可能是紧贴的 '*'。
    if ! grep -qE "[[:space:]\*]$m\(.*override" "$SRC/src/platform/Canvas2D.h"; then
        echo "  ✗ Canvas2D 缺契约方法：$m" >&2
        CANVAS_FAIL=1
    fi
done
# 判定层（logic/）零 QWidget 头 —— 分层纪律不能因为新加了图谱层而破。
GW_HITS="$(grep -rlE '#include[[:space:]]*<[Qq]Widget|#include[[:space:]]*<[A-Za-z]*Widget' \
    "$SRC/src/logic" "$SRC/src/models" 2>/dev/null || true)"
if [ -n "$GW_HITS" ]; then
    echo "✗ logic/ 或 models/ 出现了 QWidget 头（分层纪律）：" >&2
    printf '%s\n' "$GW_HITS" >&2
    CANVAS_FAIL=1
fi
# 新文件必须进了构建（漏登记 = 代码在仓里但没编进去）
# ⚠ 必须**整词**匹配：`grep -qF "$f"` 是子串匹配，把登记项改成
#   `src/logic/GraphToken.cpp.disabled` 照样命中 —— 门绿着，文件却没编进去。
for f in src/logic/GraphToken.cpp src/logic/SceneRender.cpp src/models/GraphScene.cpp src/platform/Canvas2D.cpp; do
    if ! grep -qE "(^|[[:space:]])$f([[:space:]]|$)" "$SRC/CMakeLists.txt"; then
        echo "  ✗ 构建未登记：$f" >&2
        CANVAS_FAIL=1
    fi
done
if [ "$CANVAS_FAIL" -ne 0 ]; then
    echo "✗ 图谱 Canvas 契约门失败" >&2
    exit 1
fi
echo "✓ Canvas2D 覆盖契约清单 ${CANVAS_N}/26 个方法；logic/ 与 models/ 零 QWidget 头；新文件均已登记构建"

echo "› 9/12 接线门（源扫描：判定层与接线点必须都在，撤入口 ≠ 撤能力）"
# 接线门独立成 scripts/ci-wiring.sh：可单独跑，负控也能精确打它。
if sh "$SRC/scripts/ci-wiring.sh" "$SRC"; then
    :
else
    echo "✗ 接线门失败：取数/判定/渲染/接线任一段被摘掉" >&2
    exit 1
fi

echo "› 10/12 引擎契约门（真引擎沙箱；引擎缺席显式 SKIP 且不算通过）"
# contract-check.sh 之前是**游离脚本** —— CI 从来没跑过它，契约漂移不会被拦。
# 接进 CI 后：引擎在 → 真跑（32 条）；引擎不在 → 脚本自己 SKIP 并如实说明
# 「本组未验证」（不是静默通过）。
if [ -n "${DEEPGIT_BIN:-}" ] || command -v moongit >/dev/null || command -v deepgit >/dev/null; then
    # ⚠ 别写成 `if cmd | tail -3` —— 那样 if 判的是 tail 的退出码（永远 0），
    #   契约挂了门也是绿的。必须拿脚本自己的退出码。
    _cc_log="$BUILD/contract-check.log"
    if DEEPGIT_CLIENT_BIN="$BIN" sh "$SRC/scripts/contract-check.sh" > "$_cc_log" 2>&1; then
        tail -3 "$_cc_log"
        echo "✓ 引擎契约门通过"
    else
        tail -20 "$_cc_log" >&2
        echo "✗ 引擎契约门失败" >&2
        exit 1
    fi
else
    echo "‣ SKIP 引擎契约门：未找到 moongit/deepgit（可设 DEEPGIT_BIN 指定）"
    echo "‣ 本组**未验证**，不算通过"
fi

echo "› 11/12 deb 打包（D7 达标的必经：能出包装进 deepin，且装后零环境变量）"
# PLAN §「CI 流程」明确列了「⑥ deb 构建」—— 这一门以前根本不存在，
# 于是「能不能出包装进 deepin」从没被验证过。
# build-deb.sh 自带**依赖清单双向校验**（清单 ↔ 二进制实际 DT_NEEDED）：
# 漏声明（装上跑不起来）/ 多声明（包名不存在装不上）/ 包名抄错，一律构建失败。
if command -v dpkg-deb >/dev/null 2>&1; then
    if sh "$SRC/scripts/build-deb.sh" "$BUILD/deb" > "$BUILD/build-deb.log" 2>&1; then
        tail -3 "$BUILD/build-deb.log"
        # ⚠ 解包后「零环境变量下无缺失库」的校验**在 build-deb.sh 里**（产物自检归打包脚本，
        #   别在这里再写一份 —— 两处定义会漂）。
        echo "✓ deb 构建通过（依赖清单自洽 + 产物零环境变量下无缺失库）"
    else
        tail -20 "$BUILD/build-deb.log" >&2
        echo "✗ deb 构建失败" >&2
        exit 1
    fi
else
    echo "‣ SKIP deb 构建：没有 dpkg-deb"
    echo "‣ 本组**未验证**，不算通过"
fi

echo "› 12/12 deb 布局验收（D7 的**准**验收：装完能不能用）"
# ⚠ D7 的最终验收是「干净 deepin 25 容器里 dpkg -i + 启动」—— 本机**没有容器
#   运行时**（无 docker/podman）⇒ 那一段做不了。
#   ⇒ 这里做「不依赖容器的那一半」：把 deb **解包**到临时目录（不装进系统），
#     按**包内真实布局**逐项查「装完之后点图标能不能起来」。
# ⚠ 这一门**抓到过真 bug**：D-Bus service 文件原来写 `Exec=deepDolphin --dbus-service`
#   —— ① 裸名（dbus 激活**不做 PATH 搜索**，实测裸名 `true` 也 Spawn.ExecFailed）
#   ② `--dbus-service` 这个 flag **客户端根本不认识**（全项目 grep 无此 flag）
#   ⇒ 两处合起来 = **从启动器点图标激活失败、应用起不来**。
DEB_OUT="$(ls -t "$BUILD"/deb/*.deb 2>/dev/null | head -1)"
if [ -z "$DEB_OUT" ]; then
    echo "‣ SKIP deb 布局验收：没有 deb 产物（本组**未验证**，不算通过）"
elif sh "$SRC/scripts/check-deb-layout.sh" "$DEB_OUT"; then
    echo "✓ deb 布局验收通过（装完能不能用：service/desktop/图标/metainfo/空环境启动）"
else
    echo "✗ deb 布局验收失败" >&2
    exit 1
fi

echo "✓ CI 门通过：请 git diff docs/snapshots 人工确认视觉变化符合预期"
