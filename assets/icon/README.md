# Canopy 应用图标 ——「森林谱系」，全平台唯一一套

项目叫 Sylva：整个仓库如同一片森林，谱系就是它的图谱。图标画的是一张谱系图——
地面上一根主干分出两枝，两枝再各向上分出一棵、并向顶冠汇合；五个圆是树冠也是节点，
整体轮廓是一棵树，拆开看是一张图。

## 结构

```
assets/icon/
  mark.svg          ← 唯一真相源（矢量）。1024×1024 满幅圆角方底，四边不留透明边距
  mark-small.svg    ← 小尺寸母版（像素 ≤ 32 的档位）：五个圆冠缩到 32px 以下会粘成一团，
                      这里留三个圆冠、线更粗；方底/配色/圆角与主母版一致——同一张图的两个密度
  mark.png          ← 主母版的同步位图（SVG 为真相源时每次导出重写；无 mark.svg 时它自己就是母版）
  make-icons.py     ← 从母版导出全部平台产物（唯一允许生成像素的地方）
  check-icon.sh     ← 判据：结构一致性 + CMP 客户端接线
  out/              ← 产物，**已入库**（各平台构建不依赖本机装了 Pillow / 渲染器）
    png/{16..1024}.png          通用位图（客户端窗口图标 = 256.png 在构建时并入资源）
    macos/AppIcon.icns          macOS（无 iconutil 的机器按容器格式直接写，十档齐全）
    AppIcon.ico                 Windows
    linux/hicolor/…/canopy.png   Linux 主题图标
    linux/canopy.desktop   Linux 桌面条目模板
```

**任何目录里都不许再放第二份图标。** 平台目录与 `client/src` 下的图标文件由判据挡住；
客户端的资源目录同样不许有拷贝——窗口图标在构建时从 `out/png/256.png` 并进
（`client/build.gradle.kts` 的 `jvmProcessResources`），`IconAssetTest` 钉「资源与 out/ 同一份字节」。

## 改图标

```sh
# 1. 改 mark.svg（改几何时同步改 mark-small.svg；两份的方底/配色/圆角必须一致）
# 2. 重新导出
python3 assets/icon/make-icons.py
# 3. 跑判据
bash assets/icon/check-icon.sh       # 结构 + 接线
python3 assets/icon/make-icons.py --check   # 产物与母版逐像素一致（check-icon.sh 内部会跑）
```

产物入库。`make-icons.py --check` 把每个产物按它的档位从母版重新缩一遍、合成到实底后
逐像素比——「尺寸正确但内容是旧图」这类分家以前查不出来（换母版忘重导就是这么溜进去的）。

## 为什么有两种导出几何

## CMP 客户端怎么接（2026-11-28 起）

- **窗口图标**：`Main.kt` 的 `Window(icon = painterResource("icon/canopy.png"))`。不传就是
  Compose 自带的 Kotlin 图标——这就是「别用 Kotlin 那个」此前一直没兑现的原因：图标流水线
  早就在，CMP 客户端从来没接过。资源在构建时从 `out/png/256.png` 并进，仓内不留第二份。
- **包图标**：`build.gradle.kts` 的 `nativeDistributions` 三平台 `iconFile` 全部指向 `out/`
  （Linux 512.png / Windows AppIcon.ico / macOS AppIcon.icns）。Linux 的 jpackage 把
  512.png 拷成应用镜像里的 `lib/canopy.png`，`install-user.sh` 写的桌面项 `Icon=` 指向它。
- **托盘**：`TrayQuickView` 的 22px 图是随状态画的状态指示（双圆 / 感叹三角），不是应用标——不改。

## 已知限制（如实）

- `.icns` 在没有 iconutil 的机器上按容器格式直接写（PNG 载荷，十档齐全）。判据会解开
  逐档与母版比对，两个平台产出的档位集合一致。
- 真窗口任务栏图标的实证走 `_NET_WM_ICON`：AWT 写入的像素槽是小端读出的
  `[G, R, A, B]` 字节序（`/tmp/ui/dg/wm-icon.py` 记了这个坑），解码后与母版差
  1.8/255（AWT 与 LANCZOS 的重采样差，噪声级）。
- 网站主页（`website/`）目前用 emoji 当标，没有 favicon——要接的话从 `out/png/64.png`
  取，同样不许在 website 下留拷贝。
- deepin 端已冻结（2026-11-26 起全平台只做 CMP 客户端）：`make-icons.py` 默认**不**生成
  也不校验 `deepin/data/icons`（要动加 `--with-deepin`），那里保留仓内已入库的旧品牌文件。
