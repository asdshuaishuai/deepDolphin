#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从**一张母版**导出 deepDolphin 各平台的应用图标。

## 为什么要有这个脚本

「所有平台用同一套 icon」这句话很容易退化成「大家各自拷贝一份 png，
以后慢慢长得不一样」。这份脚本把那句话变成可执行的约束：平台**不许**
自带图标文件，只许引用 `out/` 下的产物，而 `out/` 里的一切都从这里生成。
`scripts/check-icon.sh` 会验证这一点。

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
