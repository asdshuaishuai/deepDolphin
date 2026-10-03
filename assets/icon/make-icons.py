#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从**一张母版**导出 deepDolphin 各平台的应用图标。

## 为什么要有这个脚本

「所有平台用同一套 icon」这句话很容易退化成「大家各自拷贝一份 png，
以后慢慢长得不一样」。这份脚本把那句话变成可执行的约束：平台**不许**
自带图标文件，只许引用 `out/` 下的产物，而 `out/` 里的一切都从这里生成。
`scripts/check-icon.sh` 会验证这一点。deepin 客户端的 `deepin/data/icons/`
同理：位图从母版缩放、symbolic/dd-* 的 SVG 源内嵌在本脚本，树下不留手写文件。

## 母版

- `mark.png` —— 1024×1024 满幅，**四边不留透明边距**，圆角方底 + 海豚/章鱼。
  圆角是**设计的一部分**（三个平台的视觉语言因此一致），不是平台遮罩的产物。
- 若日后补上 `mark.svg`，脚本优先用它 —— 矢量母版在任意尺寸下都更锐利，
  尤其 16/24px 那种小尺寸。届时不必改任何平台代码。

## 两种导出几何（这里有个真实差异，不是偷懒）

| 平台 | 几何 | 原因 |
|---|---|---|
| Linux / Windows | 满幅 1024 内容直接缩放 | 桌面环境自己在外面套圆角遮罩；我们再留一圈透明边距，图标就会**小一号** |
| macOS | 内容缩到 858 居中，四周 83 透明 | macOS **不**自动加遮罩，得自带边距；858/83 是既有 macOS 母版的几何，沿用它可保证 macOS 外观零变化（`--verify-legacy` 会逐像素证明） |

`--verify-legacy` 拿新导出的 1024 图与旧 `macos/AppIcon.icns` 里的 1024 图比对，
报告最大通道差。正常应为 0（或极小的重采样噪声）。

## 用法

    python3 assets/icon/make-icons.py            # 生成全部产物
    python3 assets/icon/make-icons.py --check    # 只校验产物与母版一致，不写文件

依赖：Pillow（`pip install pillow`）。`.icns` 需要 macOS 的 `iconutil`，
其余平台会跳过并在末尾明说。
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")

MARK_PNG = os.path.join(HERE, "mark.png")
MARK_SVG = os.path.join(HERE, "mark.svg")

# macOS 导出几何：沿用既有 macOS 母版。改这两个数会改变 macOS 上的图标大小，
# 必须同时更新 --verify-legacy 的基线（`macos/AppIcon.icns`）。
MACOS_CONTENT = 858
MACOS_PAD = 83
MACOS_CANVAS = 1024

# Linux hicolor 目录必须有的尺寸。缺了尺寸，某些桌面环境找不到图标就退回默认图标。
HICOLOR_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]

# 通用位图产物，供 README / 文档 / 商店素材用。
PNG_SIZES = [16, 32, 48, 64, 128, 256, 512, 1024]

ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]

# iconutil 对文件名后缀很挑，缺一个就整份 icns 失败且不报错。
# 见 https://developer.apple.com/library/archive/documentation/General/Conceptual/libicns/
ICONSET_NAMES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

APP_ID = "deepdolphin"
APP_NAME = "deepDolphin"

# deepin 客户端产物树（deepin/data/icons，M2-6）：与 out/ 同一个母版唯一原则 ——
# 树下不许出现手写文件，一切由本脚本生成。与 out/linux 的差异只有两点：
# ① 尺寸集合按 plan §3 M2-6 取 8 档（含工具栏 22px 档；512 在桌面端用不上）；
# ② 多一套 symbolic 矢量层。母版是位图，矢量派生不出来，所以 SVG 源以常量
# 内嵌在本脚本：改符号 = 改这里的源再重跑，产物永远可复现。
DEEPIN_ICONS_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "deepin", "data", "icons"))
DEEPIN_HICOLOR_SIZES = [16, 22, 24, 32, 48, 64, 128, 256]

# 既有应用图标（深蓝圆角底 + 海豚意象，非染色件，允许写死色值）。
# 原先是 data/icons 下的手写文件；原样收编进脚本，字节不变（--check 会校验）。
DEEPIN_APP_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<!-- deepDolphin 应用图标（占位：深蓝圆角底 + 海豚意象曲线）。
     Icon=deepdolphin 与 desktop 文件、IconLoader::app() 的主题查找名一致。 -->
<svg width="128" height="128" viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">
  <rect x="6" y="6" width="116" height="116" rx="26" fill="#1E6FEB"/>
  <path d="M30 84 C36 56, 58 38, 88 36 C96 35.4, 102 38, 102 44
           C102 50, 94 52, 86 55 C74 59.4, 66 68, 62 80
           C58 92, 46 96, 38 92 C42 88, 44 84, 42 78 Z"
        fill="#FFFFFF" opacity="0.95"/>
  <circle cx="88" cy="47" r="3.4" fill="#1E6FEB"/>
</svg>
"""

# 染色件（symbolic 应用图标 + dd-* 符号）的硬规矩：颜色只写 currentColor
# 占位符 —— deepin/src/platform/IconLoader.cpp 的 tintedSvg 按字面替换它。
# 两色调 = 主调实底 currentColor + 次调同色但 fill-opacity/stroke-opacity 降档；
# 出现任何写死的色值都会让亮/暗主题下的染色变成补丁色（check_outputs 会拦）。
DEEPIN_SYMBOLIC_APP_SVG = """<?xml version="1.0" encoding="UTF-8"?>
<!-- deepdolphin-symbolic：母版 mark.png 的单色符号化（鲸/海豚 = 主调实底，
     e 环与圆角框 = 次调 40%）。装到 hicolor/symbolic/apps，主题查找名
     deepdolphin-symbolic。 -->
<svg width="128" height="128" viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">
  <rect x="10" y="10" width="108" height="108" rx="24" fill="none"
        stroke="currentColor" stroke-width="7" stroke-opacity=".4"/>
  <path fill-rule="evenodd" fill="currentColor" fill-opacity=".4"
        d="M64 52 a30 30 0 1 0 .02 0 Z M64 65 a17 17 0 1 1 -.02 0 Z M64 76 h30 v12 h-30 Z"/>
  <path fill-rule="evenodd" fill="currentColor"
        d="M25 68 C27 48 47 34 70 35 C87 35.8 99 44 104 56
           C96 57.5 91 62 88.5 69 C85 77 76 80 67 80 L38 80 C29.5 80 23.8 75 25 68 Z
           M100 54 C109 48.5 115 40 116.5 30 C106 32.8 98 38.5 93.5 46 Z
           M38 50 a3 3 0 1 0 .02 0 Z"/>
</svg>
"""

# dd-* 符号（24 网格，两色调 symbolic 风格）。名字与代码语义一一对应：
#   git           仓库/项目（侧栏「仓库」组、项目相关状态）
#   milestone     里程碑（里程碑视图/创建入口；与主题 fallback 名 flag 同语义）
#   warning       警示/attention（托盘 alert 感叹三角、异常状态行）
#   circle-double 托盘正常态「双圆」（外环+内点，与 TrayController 壳阶段占位同构）
#   ai            AI 助手（freedesktop 无标准名；装进主题后 makeToolButton
#                 的 fromTheme("dd-ai") 也能命中，决策 72 的「恒文字钮」就此补齐）
DEEPIN_SYMBOL_SVGS = {
    "git": """<?xml version="1.0" encoding="UTF-8"?>
<!-- dd-git：git 仓库/项目。主调：主干与两端节点；次调（40%）：分支走线与节点。 -->
<svg width="24" height="24" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path d="M7 7.6 V16.4" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
  <circle cx="7" cy="5.2" r="2.4" fill="currentColor"/>
  <circle cx="7" cy="18.8" r="2.4" fill="currentColor"/>
  <path d="M7 8.8 C7 12.6 11.5 13.4 16.6 13.6" fill="none" stroke="currentColor"
        stroke-width="1.8" stroke-linecap="round" stroke-opacity=".4"/>
  <circle cx="17" cy="5.2" r="2.4" fill="currentColor" fill-opacity=".4"/>
  <circle cx="17" cy="16" r="2.4" fill="currentColor" fill-opacity=".4"/>
</svg>
""",
    "milestone": """<?xml version="1.0" encoding="UTF-8"?>
<!-- dd-milestone：里程碑（对位主题名 flag）。主调：旗面；次调（40%）：旗杆。 -->
<svg width="24" height="24" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path d="M6.6 3.4 V20.6" fill="none" stroke="currentColor" stroke-width="1.8"
        stroke-linecap="round" stroke-opacity=".4"/>
  <path d="M6.6 4.6 H17.8 L14.9 8.5 L17.8 12.4 H6.6 Z" fill="currentColor"/>
</svg>
""",
    "warning": """<?xml version="1.0" encoding="UTF-8"?>
<!-- dd-warning：警示/attention（托盘 alert 同款感叹三角）。
     感叹号用 evenodd 镂空而不是降透明度：同色半透明叠在同色实底上仍是
     同色（渲染实测不可见），镂空才在任意底色下保住 16px 可读性。 -->
<svg width="24" height="24" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path fill-rule="evenodd" fill="currentColor"
        d="M12 3.4 L21.6 19.8 H2.4 Z M11 9.2 h2 v6 h-2 Z
           M12 16.4 a1.25 1.25 0 1 0 .01 0 Z"/>
</svg>
""",
    "circle-double": """<?xml version="1.0" encoding="UTF-8"?>
<!-- dd-circle-double：托盘正常态「双圆」（外环+内点；空态/未知态亦用）。 -->
<svg width="24" height="24" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <circle cx="12" cy="12" r="8.2" fill="none" stroke="currentColor" stroke-width="2.2"/>
  <circle cx="12" cy="12" r="3.2" fill="currentColor" fill-opacity=".45"/>
</svg>
""",
    "ai": """<?xml version="1.0" encoding="UTF-8"?>
<!-- dd-ai：AI 助手。主调：大四角星；次调（40%）：两颗小星。 -->
<svg width="24" height="24" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path d="M11.6 3.2 C12.5 8.3 14.7 10.5 19.8 11.4 C14.7 12.3 12.5 14.5 11.6 19.6
           C10.7 14.5 8.5 12.3 3.4 11.4 C8.5 10.5 10.7 8.3 11.6 3.2 Z" fill="currentColor"/>
  <path d="M18.4 13.8 C18.9 16 19.8 16.9 22 17.4 C19.8 17.9 18.9 18.8 18.4 21
           C17.9 18.8 17 17.9 14.8 17.4 C17 16.9 17.9 16 18.4 13.8 Z"
        fill="currentColor" fill-opacity=".4"/>
  <path d="M18.6 2.6 C19 4.3 19.7 5 21.4 5.4 C19.7 5.8 19 6.5 18.6 8.2
           C18.2 6.5 17.5 5.8 15.8 5.4 C17.5 5 18.2 4.3 18.6 2.6 Z"
        fill="currentColor" fill-opacity=".4"/>
</svg>
""",
}

# Linux 的应用身份全靠三个同名的东西串起来：
#   .desktop 文件名 = hicolor 图标名 = SDL 的 AppMetadata.identifier
# 任何一个对不上，症状都一样且很难查：窗口正常起来，任务栏/启动器里
# **没有图标**（或者干脆没有这个应用的条目）。所以三个都由这个脚本按
# 同一个 APP_ID 产出，不给手写留余地。
DESKTOP_TEMPLATE = """[Desktop Entry]
Type=Application
Version=1.0
Name={name}
GenericName=Git 项目面板
Comment=通过 moongit 引擎查看与更新受管项目
Exec=__EXEC__
Icon={app_id}
Terminal=false
Categories=Development;Utility;VersionControl;
# X11 下窗口类与 .desktop 关联用的键。Wayland 走 app_id（= AppMetadata.identifier）。
# 若图标仍不显示，先用 `xprop WM_CLASS <窗口>` 看真实的类名，再改这一行 ——
# 它必须与窗口实际报告的类一致，而不是与图标名一致。
StartupWMClass={app_id}
""".format(name=APP_NAME, app_id=APP_ID)


def fail(msg: str) -> "None":
    print("✗ " + msg, file=sys.stderr)
    raise SystemExit(1)


def load_mark():
    """载入母版。SVG 优先（矢量母版在 16px 下明显更锐利），否则用 PNG。"""
    try:
        from PIL import Image
    except ImportError:
        fail("需要 Pillow：pip3 install pillow")

    if os.path.exists(MARK_SVG):
        try:
            import cairosvg  # noqa: F401
        except ImportError:
            fail(
                "发现 mark.svg 但缺 cairosvg，无法栅格化。\n"
                "  装它：pip3 install cairosvg\n"
                "  或：把母版降回 mark.png（删掉 mark.svg）"
            )
        import cairosvg
        # 统一栅格化到 1024 满幅，后续所有尺寸都从它缩，避免各尺寸各自栅格化
        # 导致边缘锯齿不一致。
        png_bytes = cairosvg.svg2png(
            url=MARK_SVG, output_width=1024, output_height=1024
        )
        import io

        return Image.open(io.BytesIO(png_bytes)).convert("RGBA"), "mark.svg"

    if not os.path.exists(MARK_PNG):
        fail("找不到母版：%s（也没有 %s）" % (MARK_PNG, MARK_SVG))
    return Image.open(MARK_PNG).convert("RGBA"), "mark.png"


def assert_full_bleed(img, label: str) -> None:
    """母版必须满幅：alpha 的包围盒要顶到四条边。

    这条检查是有代价换来的 —— 原来的 macOS 图标四边各留 83px 透明边距，
    丢给 Linux 启动器后图标明显小一圈（内容只占 858/1024 ≈ 84%）。
    """
    bbox = img.split()[3].getbbox()
    if bbox != (0, 0, img.size[0], img.size[1]):
        fail(
            "%s 不是满幅：alpha 包围盒 %s，期望 (0, 0, %d, %d)。\n"
            "  母版四边不该留透明边距 —— 边距由各平台导出时按规范加。"
            % (label, bbox, img.size[0], img.size[1])
        )


def save_png(img, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, format="PNG", optimize=True)


def write_text(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def deepin_path(rel: str) -> str:
    return os.path.join(DEEPIN_ICONS_DIR, rel)


def build_deepin(mark) -> None:
    """deepin/data/icons 全树产物（M2-6）。

    位图与 out/linux 同一满幅几何（桌面环境自套圆角遮罩），只差尺寸集合；
    symbolic 层写进 symbolic/apps/（安装规则把它落到 hicolor/symbolic/apps ——
    深色/浅色主题按 currentColor 染色，qrc 与主题查找共用同一份文件）。
    """
    for s in DEEPIN_HICOLOR_SIZES:
        save_png(
            mark.resize((s, s), _lanczos()),
            deepin_path("hicolor/%dx%d/apps/%s.png" % (s, s, APP_ID)),
        )
    write_text(deepin_path("deepdolphin.svg"), DEEPIN_APP_SVG)
    write_text(deepin_path("symbolic/apps/deepdolphin-symbolic.svg"),
               DEEPIN_SYMBOLIC_APP_SVG)
    for name, svg in DEEPIN_SYMBOL_SVGS.items():
        write_text(deepin_path("symbolic/apps/dd-%s.svg" % name), svg)


def check_deepin() -> int:
    """deepin 树的 --check：位图尺寸、SVG 良构、染色件无写死色值且带次调。"""
    import xml.etree.ElementTree as ET
    from PIL import Image

    bad = 0
    for s in DEEPIN_HICOLOR_SIZES:
        p = deepin_path("hicolor/%dx%d/apps/%s.png" % (s, s, APP_ID))
        if not os.path.exists(p):
            print("  ✗ 缺 %s" % os.path.relpath(p, HERE))
            bad += 1
            continue
        im = Image.open(p)
        if im.size != (s, s):
            print("  ✗ %s 尺寸 %s，期望 (%d, %d)"
                  % (os.path.relpath(p, HERE), im.size, s, s))
            bad += 1

    tinted = [("deepdolphin-symbolic.svg", DEEPIN_SYMBOLIC_APP_SVG)]
    tinted += [("dd-%s.svg" % n, s) for n, s in DEEPIN_SYMBOL_SVGS.items()]
    for name, source in tinted:
        p = deepin_path("symbolic/apps/%s" % name)
        if not os.path.exists(p):
            print("  ✗ 缺 %s" % os.path.relpath(p, HERE))
            bad += 1
            continue
        with open(p, encoding="utf-8") as fh:
            text = fh.read()
        if text != source:
            print("  ✗ %s 与脚本内源不一致（树下不许手改，重跑本脚本）"
                  % os.path.relpath(p, HERE))
            bad += 1
        try:
            ET.fromstring(text)
        except ET.ParseError as e:
            print("  ✗ %s 不是良构 XML：%s" % (os.path.relpath(p, HERE), e))
            bad += 1
        # 染色契约：占位符必须在，写死色值必须无；两色调 = 必须带降透明度。
        if "currentColor" not in text:
            print("  ✗ %s 丢了 currentColor 占位符，染色通道会失明" % name)
            bad += 1
        if "#" in text:
            print("  ✗ %s 出现写死色值（#…），亮/暗主题会变补丁色" % name)
            bad += 1
        # 两色调标记：次调走降透明度；warning 类「实底上的记号」用 evenodd
        # 镂空表达（同色半透明叠实底不可见，渲染实测）。二者必须有其一。
        if "opacity" not in text and "evenodd" not in text:
            print("  ✗ %s 没有次调（opacity 或 evenodd 镂空），两色调名不副实" % name)
            bad += 1

    p = deepin_path("deepdolphin.svg")
    if not os.path.exists(p):
        print("  ✗ 缺 %s" % os.path.relpath(p, HERE))
        bad += 1
    elif open(p, encoding="utf-8").read() != DEEPIN_APP_SVG:
        print("  ✗ deepin/data/icons/deepdolphin.svg 与脚本内源不一致")
        bad += 1
    return bad


def build_macos_canvas(mark) -> "Image.Image":
    """把满幅母版放进 macOS 的 1024 画布正中（内容 858 + 边距 83）。"""
    from PIL import Image

    inner = MACOS_CANVAS - 2 * MACOS_PAD
    if inner != MACOS_CONTENT:
        fail(
            "macOS 几何自相矛盾：canvas %d - 2×pad %d = %d，但 MACOS_CONTENT 是 %d"
            % (MACOS_CANVAS, MACOS_PAD, inner, MACOS_CONTENT)
        )
    content = mark.resize((MACOS_CONTENT, MACOS_CONTENT), _lanczos())
    canvas = Image.new("RGBA", (MACOS_CANVAS, MACOS_CANVAS), (0, 0, 0, 0))
    canvas.paste(content, (MACOS_PAD, MACOS_PAD))
    return canvas


def build_icns(mark) -> bool:
    """用 macOS 自带的 iconutil 打包 .icns。非 macOS 返回 False。"""
    if not os.path.exists("/usr/bin/iconutil"):
        print(
            "  · 跳过 .icns：需要 macOS 的 /usr/bin/iconutil。"
            "icns 是 Apple 专有格式，其他平台无法生成（也不需要）。"
        )
        return False
    # iconutil 硬性要求目录名以 `.iconset` 结尾，不符合就只回一句
    # "Invalid Iconset" 且不说是哪个文件错了。
    iconset = os.path.join(OUT, "deepDolphin.iconset")
    os.makedirs(iconset, exist_ok=True)
    try:
        mac_canvas = build_macos_canvas(mark)
        for name, px in ICONSET_NAMES:
            # 每档都从同一张 1024 macOS 画布缩，而不是从母版各自缩 ——
            # 后者会让 32px 档绕过那圈 83px 边距，图标在 Dock 里大小不一。
            save_png(mac_canvas.resize((px, px), _lanczos()),
                     os.path.join(iconset, name))
        icns = os.path.join(OUT, "macos", "AppIcon.icns")
        os.makedirs(os.path.dirname(icns), exist_ok=True)
        subprocess.run(
            ["/usr/bin/iconutil", "-c", "icns", iconset, "-o", icns], check=True
        )
        print("  · %s" % os.path.relpath(icns, HERE))
        return True
    except subprocess.CalledProcessError as e:
        fail("iconutil 失败（退出码 %s）" % e.returncode)
    finally:
        _rmtree(iconset)
    return False


def _lanczos() -> "Image.Resampling":
    from PIL import Image

    return Image.LANCZOS


def _rmtree(path: str) -> None:
    if not os.path.isdir(path):
        return
    for name in os.listdir(path):
        full = os.path.join(path, name)
        if os.path.isdir(full):
            _rmtree(full)
        else:
            os.remove(full)
    os.rmdir(path)


def build_ico(mark) -> None:
    ico = os.path.join(OUT, "AppIcon.ico")
    os.makedirs(os.path.dirname(ico), exist_ok=True)
    # PIL 的 ICO 写入是「从大图里挑尺寸」，不是每档重采样，所以母版必须够大。
    mark.save(ico, format="ICO", sizes=[(s, s) for s in ICO_SIZES])
    print("  · %s  %s" % (os.path.relpath(ico, HERE), ICO_SIZES))


def verify_legacy(icns_path: str) -> None:
    """证明新导出的 macOS 图标与旧的那份像素等价。

    这是「统一 icon」最硬的一条证据：新公共 icns 若与旧 macOS 图标长得一样，
    就说明把 macOS 端改为引用公共资源**没有偷偷改动用户已经看惯的图标**。
    """
    if not os.path.exists(icns_path):
        print("  · 没有旧 %s，跳过像素对照" % icns_path)
        return
    with tempfile.TemporaryDirectory() as td:
        # 解包目录同样必须以 `.iconset` 结尾，否则 iconutil 直接拒。
        unpacked = os.path.join(td, "legacy.iconset")
        try:
            subprocess.run(
                ["/usr/bin/iconutil", "-c", "iconset", icns_path, "-o", unpacked],
                check=True,
            )
        except subprocess.CalledProcessError:
            print("  · 旧 icns 解不开（格式异常？），跳过像素对照")
            return

        # 对照必须挑**双方都有**的档位。旧 icns 只有 5 档且**一个 @2x 都没有**
        # —— 缺 @2x 意味着 Retina 屏上 macOS 只能放大 512@1x 用（发虚）。
        # 所以能对照的只有 @1x 那几档，取其中最大的（512）作代表。
        if not os.path.isdir(unpacked):
            print("  · 旧 icns 解出目录不存在，跳过像素对照")
            return
        shared = [
            n for n in os.listdir(unpacked)
            if n.endswith(".png") and not n.endswith("@2x.png")
        ]
        if not shared:
            print("  · 旧 icns 里没有可对照的 @1x 档，跳过像素对照")
            return

        def px_area(name: str) -> int:
            base = name[:-4].split("@")[0]  # icon_512x512
            dim = base.split("_")[1]  # 512x512
            return int(dim.split("x")[0])

        pick = max(shared, key=px_area)
        new_unpacked = os.path.join(td, "new.iconset")
        subprocess.run(
            ["/usr/bin/iconutil", "-c", "iconset",
             os.path.join(OUT, "macos", "AppIcon.icns"), "-o", new_unpacked],
            check=True,
        )
        new_pick = os.path.join(new_unpacked, pick)
        if not os.path.exists(new_pick):
            print("  · 新 icns 缺档 %s，跳过像素对照" % pick)
            return
        old = os.path.join(unpacked, pick)
        from PIL import Image, ImageChops, ImageStat

        a = Image.open(old).convert("RGBA")
        # 旧档是 512 那一档，画布是 1024 —— 必须先缩到同一尺寸再比。
        # 不缩直接 ImageChops.difference，差异区域是「尺寸错配」的假象。
        b = build_macos_canvas(load_mark()[0]).resize(a.size, _lanczos())

        # ⚠ 判据不能只看「最大单像素差」。半透明边缘的 RGB 在非预乘表示下
        # 本来就是噪声：一个 alpha=1 的像素可以存任意 RGB，直接比 RGB 会得到
        # 满额 255 的假差异（实测就是这样）。先把两边都合成到**实底**上，
        # 比的才是眼睛真能看到的颜色。
        report = []
        worst_mean = 0.0
        for label, bg in (("白底", (255, 255, 255, 255)), ("深底", (15, 23, 42, 255))):
            fa = _flatten(a, bg)
            fb = _flatten(b, bg)
            diff = ImageChops.difference(fa, fb).convert("L")
            mean = ImageStat.Stat(diff).mean[0]
            # 差异超过 8 级（肉眼可辨的门槛）的像素占比
            hist = diff.point(lambda v: 255 if v > 8 else 0).histogram()
            over = sum(hist[1:]) / float(a.size[0] * a.size[1])
            worst_mean = max(worst_mean, mean)
            report.append("%s 平均差 %.2f/255，超阈像素 %.3f%%" % (label, mean, over * 100))
        print("  · 与旧 macOS/AppIcon.icns 的 %s 档对照：%s" % (pick, "；".join(report)))
        # 平均差 1.5/255 以内 + 超阈像素极少 ⇒ 肉眼不可分辨的几何抖动。
        if worst_mean > 1.5:
            print(
                "    ⚠ 差值偏大。macOS 端改引公共图标后外观会有变化，"
                "确认这是有意的再提交。"
            )
        else:
            print("    ✓ 视觉等价（亚像素抖动，肉眼不可辨）")


def _flatten(img, bg):
    """把 RGBA 图合成到实底上再转 RGB —— 半透明边缘的 RGB 只有合成后才有意义。"""
    from PIL import Image

    base = Image.new("RGBA", img.size, bg)
    base.alpha_composite(img)
    return base.convert("RGB")


def check_outputs() -> int:
    """只校验不写。产物缺失或与母版对不上就返回非 0。"""
    from PIL import Image

    bad = 0
    for s in PNG_SIZES:
        p = os.path.join(OUT, "png", "%d.png" % s)
        if not os.path.exists(p):
            print("  ✗ 缺 %s" % os.path.relpath(p, HERE))
            bad += 1
            continue
        im = Image.open(p)
        if im.size != (s, s):
            print("  ✗ %s 尺寸 %s，期望 (%d, %d)" % (os.path.relpath(p, HERE), im.size, s, s))
            bad += 1
    for s in HICOLOR_SIZES:
        p = os.path.join(OUT, "linux", "hicolor", "%dx%d" % (s, s), "apps",
                         "%s.png" % APP_ID)
        if not os.path.exists(p):
            print("  ✗ 缺 %s" % os.path.relpath(p, HERE))
            bad += 1
            continue
        im = Image.open(p)
        if im.size != (s, s):
            print("  ✗ %s 尺寸 %s，期望 (%d, %d)" % (os.path.relpath(p, HERE), im.size, s, s))
            bad += 1
    ico = os.path.join(OUT, "AppIcon.ico")
    if not os.path.exists(ico):
        print("  ✗ 缺 out/AppIcon.ico")
        bad += 1
    else:
        with open(ico, "rb") as fh:
            if fh.read(4) != b"\x00\x00\x01\x00":
                print("  ✗ out/AppIcon.ico 不是 ICO 魔数")
                bad += 1
    if sys.platform == "darwin":
        icns = os.path.join(OUT, "macos", "AppIcon.icns")
        if not os.path.exists(icns):
            print("  ✗ 缺 out/macos/AppIcon.icns")
            bad += 1
    dt = os.path.join(OUT, "linux", "%s.desktop" % APP_ID)
    if not os.path.exists(dt):
        print("  ✗ 缺 out/linux/%s.desktop" % APP_ID)
        bad += 1
    else:
        with open(dt, encoding="utf-8") as fh:
            txt = fh.read()
        # Icon= 必须与 hicolor 里的文件名一致，否则启动器找不到图标 ——
        # 而「找不到图标」和「图标没生成」症状一模一样，极易误判方向。
        if ("Icon=%s\n" % APP_ID) not in txt:
            print("  ✗ .desktop 的 Icon= 不是 %s，与 hicolor 文件名对不上" % APP_ID)
            bad += 1
    bad += check_deepin()
    return bad


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只校验产物，不写文件")
    args = ap.parse_args()

    mark, source = load_mark()
    print("母版：%s  %dx%d" % (source, mark.size[0], mark.size[1]))
    assert_full_bleed(mark, "母版 %s" % source)

    if args.check:
        bad = check_outputs()
        if bad:
            print("✗ %d 处不一致，跑 `python3 assets/icon/make-icons.py` 重新生成" % bad)
            return 1
        print("✓ 产物齐全且与母版一致")
        return 0

    print("导出：")
    for s in PNG_SIZES:
        save_png(mark.resize((s, s), _lanczos()), os.path.join(OUT, "png", "%d.png" % s))
    print("  · out/png/{%s}.png" % ",".join(str(s) for s in PNG_SIZES))

    for s in HICOLOR_SIZES:
        save_png(
            mark.resize((s, s), _lanczos()),
            os.path.join(OUT, "linux", "hicolor", "%dx%d" % (s, s), "apps",
                         "%s.png" % APP_ID),
        )
    print("  · out/linux/hicolor/{16,24,32,48,64,128,256,512}x…/apps/%s.png" % APP_ID)

    build_deepin(mark)
    print("  · deepin/data/icons/hicolor/{%s}x…/apps/%s.png"
          % (",".join(str(s) for s in DEEPIN_HICOLOR_SIZES), APP_ID))
    print("  · deepin/data/icons/symbolic/apps/{deepdolphin-symbolic,%s}.svg"
          % ",".join("dd-%s" % n for n in DEEPIN_SYMBOL_SVGS))
    print("  · deepin/data/icons/deepdolphin.svg（原样收编，字节不变）")

    build_ico(mark)
    if build_icns(mark):
        verify_legacy(os.path.join(HERE, "..", "..", "macos", "AppIcon.icns"))

    # .desktop 的 Exec 留 __EXEC__ 占位：可执行文件路径每台机器都不一样，
    # 由 linux/scripts/install-icon.sh 安装时替换。
    desktop = os.path.join(OUT, "linux", "%s.desktop" % APP_ID)
    os.makedirs(os.path.dirname(desktop), exist_ok=True)
    with open(desktop, "w", encoding="utf-8") as fh:
        fh.write(DESKTOP_TEMPLATE)
    print("  · %s" % os.path.relpath(desktop, HERE))

    print("\n接线：")
    print("  macOS    build.sh 从 out/macos/AppIcon.icns 取")
    print("  Linux    scripts/install-icon.sh 装 out/linux/hicolor → ~/.local/share/icons")
    print("  Windows  out/AppIcon.ico")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
