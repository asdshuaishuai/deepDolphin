# deepDolphin 应用图标 —— 全平台唯一一套

## 结构

```
assets/icon/
  mark.png          ← 唯一真相源。1024×1024 满幅，四边不留透明边距
  make-icons.py     ← 从母版导出全部平台产物（唯一允许生成像素的地方）
  check-icon.sh     ← 判据：验证「同一套」在结构上成立
  out/              ← 产物，**已入库**（各平台构建不依赖本机装了 Pillow）
    png/{16..1024}.png          通用位图，文档/商店素材用
    macos/AppIcon.icns          macOS
    AppIcon.ico                 Windows
    linux/hicolor/…/deepdolphin.png   Linux 主题图标
    linux/deepdolphin.desktop   Linux 桌面条目模板
```

**平台目录里不许再放第二份图标。** `macos/AppIcon.icns` 这类文件在
2026-10-04 之前确实存在（同时 macOS 和 Linux 各自为政），现在由判据挡住。

## 改图标

```sh
# 1. 换掉 mark.png（1024×1024 满幅圆角方底，别留透明边距）
# 2. 重新导出
python3 assets/icon/make-icons.py
# 3. 跑判据
bash assets/icon/check-icon.sh
```

产物入库，所以第 2 步在 macOS 上做一次即可；`.icns` 需要 macOS 的
`iconutil`，其他平台会跳过并明说（`icns` 是 Apple 专有格式，
别的平台既生成不了也不需要）。

## 为什么有两种导出几何

这不是偷懒，是平台规范真的不同：

| 平台 | 几何 | 原因 |
|---|---|---|
| Linux / Windows | 满幅内容直接缩放 | 桌面环境自己在外面套圆角遮罩。我们再留一圈透明边距，图标就会**小一号** —— 原来那张 macOS 图标内容只占 858/1024 ≈ 84%，放到 48×48 的启动器里只有 40px。 |
| macOS | 内容缩到 858 居中，四周 83 透明 | macOS **不**自动加遮罩，图标必须自带边距。 |

macOS 用 858/83（而不是 Apple 规范的 824/100）是为了让新导出的 icns 与
原本那张**视觉等价**，不改动用户已经看惯的图标。`make-icons.py` 每次
生成都会做像素对照并打印结果。

### 对照判据里一个真发现

原本的 `macos/AppIcon.icns` **只有 5 个档位，一个 `@2x` 都没有**
（16/32/128/256/512 @1x）。缺 `@2x` 意味着 Retina 屏上 macOS 只能放大
512@1x 来用，图标发虚。新产物是完整 10 档 —— 这次统一图标顺带补齐了
Retina 支持。

对照时有个陷阱：一开始用「最大单像素通道差」当判据，报出 255 的差异，
看着像图标完全变了。实际那是**半透明边缘的 RGB 在非预乘表示下没有意义**
——一个 `alpha=1` 的像素可以存任意 RGB。改成先把两边合成到实底再比，
真实差异是白底平均 0.86/255、超阈像素 2.7%（集中在圆角抗锯齿边），
属于亚像素抖动，肉眼不可辨。

## 各平台怎么用

### macOS

`macos/build.sh` 从 `out/macos/AppIcon.icns` 取，并且**在缺失时直接失败**
（不打出一个没图标的 app —— 那个更难排查）。

### Linux

```sh
bash linux/scripts/install-icon.sh              # 装
bash linux/scripts/install-icon.sh --uninstall  # 卸
```

装到 `~/.local/share/`（不需要 root）。三处名字必须一致，否则窗口起来
了但任务栏没有图标：

| 位置 | 值 | 谁定的 |
|---|---|---|
| `.desktop` 文件名 | `deepdolphin` | `make-icons.py` 的 `APP_ID` |
| hicolor 图标名 | `deepdolphin.png` | 同上 |
| SDL `AppMetadata.identifier` | `deepdolphin` | `linux/src/main.cj` |

`.desktop` 的 `Exec` 指向 `linux/scripts/run.sh` 而不是二进制本体：仓颉
产物靠 rpath 找 `libstdcangjie-runtime`，直接在 `.desktop` 里写二进制
路径的话，图标能点开但一启动就 dyld 报错 —— 那症状很难联想到是
`.desktop` 写错了。

### Windows / 鸿蒙

`out/AppIcon.ico` 已备好。客户端实现时直接引用，别在平台目录里另存一份。

## 已知限制

**CUI 没有暴露 `SDL_SetWindowIcon`**，所以 Linux 上「运行时给窗口设置
图标」这条路在本框架下走不通。图标由 hicolor + `.desktop` 兑现
（Wayland 下走 `app_id`，X11 下走 `WM_CLASS`），这也是 Linux 桌面应用
的正规做法。`vendor/` 是第三方，不改。

X11 下若图标仍不显示，先 `xprop WM_CLASS <窗口id>` 看窗口实际报告的类名，
再改 `.desktop` 的 `StartupWMClass` —— 那个键必须与窗口真实的类一致，
而不是与图标名一致。
