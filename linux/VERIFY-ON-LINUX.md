# 在 Linux 上要确认的事

这份文档只记一件事：**哪些结论是在 macOS 上得出的、还没在 Linux 上核对过**。

背景：本客户端的全部开发与自动化验证都在 **macOS + 仓颉 1.0.5** 上做。
代码里 `CUI 本身跨平台` 这句话成立，但**跨平台 ≠ 已验证**。
下面每一条都标了「怎么查 / 期望看到什么 / 出问题意味着什么」，
不需要你读代码，照着做就行。

---

## 0. 先决条件

```sh
# 1. 仓颉 SDK 必须是 1.0.5，禁止升级。
#    两种解包布局都合法：envsetup.sh 直接在 $CANGJIE_HOME 下，
#    或多套一层 cangjie/（deepin 25 实测是后者）。仓内脚本
#    （scripts/cj-env.sh 的 dd_cj_locate_sdk）两级都会探测。
export CANGJIE_HOME="$HOME/.local/share/cangjie/current"
ls "$CANGJIE_HOME/envsetup.sh" "$CANGJIE_HOME/cangjie/envsetup.sh"   # 至少一个存在
"$CANGJIE_HOME/cangjie/bin/cjc" --version 2>/dev/null || "$CANGJIE_HOME/bin/cjc" --version   # 期望 1.0.5

# 2. SDL3 三件套（fetch-deps.sh 会从系统库拷进 vendor/）
sudo apt install libsdl3-dev libsdl3-ttf-dev libsdl3-image-dev

# 3. 中文与等宽字体（缺了界面全是方块）
sudo apt install fonts-noto-cjk fonts-noto-cjk-extra fonts-dejavu-core

# 4. 第三方依赖
cd linux && sh scripts/fetch-deps.sh

# 5. 构建 + 判据
cjpm test
```

`cjpm test` 期望 **119 条，116 通过 + 3 跳过（端到端），0 失败**。
3 条跳过的是 AI 端到端，要 `bash scripts/ai-e2e.sh` 才跑（它起一个假 provider，
不需要 API key）。

> ⚠️ **如果你在第 5 步之前就跑 `scripts/run.sh`，本轮已修过一个 Linux 专属 bug**：
> 原来它按 `uname -m` 选仓颉运行时目录，Linux 上是 `x86_64`，
> 落进只认 `darwin_` 前缀的兜底分支 → 目录名变空串 →
> `error while loading shared libraries: libcangjie-runtime.so`。
> 症状像「仓颉没装好」，重装 SDK 修不好。已改为按操作系统选，
> 并把逻辑抽到 `scripts/cj-env.sh` 供 `run.sh` / `dev-launch.sh` 共用。
> 现在找不到对应目录会**直接报错并告诉你 `ls` 哪里**，不会再静默跑歪。

---

## 1. 真窗口能不能开起来（最高优先级）

**这是所有交互验证的前提。在 macOS 上开不出窗口**，报错是：

```
SDL_CreateWindowAndRenderer failed: NSWindow should only be instantiated on the main thread!
```

已查明是 AppKit 的主线程判定（`pthread_main_np()` 为真，但 Foundation
被仓颉运行时在别的线程上先初始化了，AppKit 不认）。**这是 macOS 特有**，
Linux 走 X11/Wayland，没有这个障碍。

```sh
cd linux && sh scripts/run.sh
```

- **期望**：出现一个 1180×760 的窗口，标题 `deepDolphin`。
- **如果失败**，请把**完整错误串**贴回来。特别留意：
  - SDL 选的是 **wayland** 还是 **x11**？两者行为不同，Wayland 下没有
    `XDG_RUNTIME_DIR` 会退到 X11，而 X11 下没有 `DISPLAY` 就彻底起不来。
  - 报的是 `No available video device` 还是别的？——「自动探测失败但显式指定
    驱动就成功」这种情况在 macOS 上出现过，值得排除一下：

    ```sh
    # GNOME/Wayland 会话
    SDL_VIDEODRIVER=wayland sh scripts/run.sh
    # X11 会话（或从 TTY 启动）
    SDL_VIDEODRIVER=x11 sh scripts/run.sh
    ```

- 另外记一下后端与桌面环境，方便复现：`echo $XDG_SESSION_TYPE $XDG_CURRENT_DESKTOP $XDG_RUNTIME_DIR`

## 2. 交互（macOS 上全部零证据）

点击的**路由**已经用快照证明过了（`DD_SNAP_CLICK`，见 README「验证」一节），
但那走的是 `post`，**不是真的鼠标事件**。下面这些一个都没验过：

| 动作 | 怎么查 | 出问题意味着 |
|---|---|---|
| **滚动** | 在项目详情页（很长）滚到底；代码块与表格尤其要试 | 滚不动，或滚过头 |
| **悬停** | 鼠标停在按钮/列表行上 | 无提示，或提示错位 |
| **侧栏点击** | 点「视图」组三项 + 「仓库」组各行 | 高亮了但主区不换页 |
| **键盘输入** | 在「提交信息」框、AI 输入框里打字 | 收不到字符 / 焦点乱跳 |
| **窗口缩放** | 拖到最小（940×640）与很大 | 布局塌陷或留白 |
| **关闭** | 点关闭按钮、Alt+F4 | 见第 7 条的拆卸异常 |

## 3. 系统集成 C10（三件在 macOS 上一个都没验过）

`linux/src/sysint.cj` 里实现了，但 macOS 上没有 `notify-send`、没有 XDG、
所以全部无证据。

### 3.1 系统通知

```sh
which notify-send || sudo apt install libnotify-bin
```

跑起来后在设置页或触发一次更新动作，看有没有弹出通知。

- **注意一个已知取舍**：本端**没有托盘**。README 写着「CUI 不暴露托盘 API」，
  这个结论是在 **macOS** 上得出的，**请在 Linux 上复核** ——
  Linux 上托盘（StatusNotifier）是主流用法，如果 CUI 在 Linux 上其实能用，
  那这页「已知差异」就该改。

### 3.2 开机自启

在设置页打开自启开关，然后：

```sh
cat ~/.config/autostart/deepdolphin.desktop
```

- **期望**：文件存在，`Exec=` 指向一个**真实存在**的路径。
- 重点看路径里的空格有没有被转义（`escapeDesktopExec` 专门处理这个）。
- 注销重登，确认它真的自启了。

### 3.3 启动深链

```sh
./target/release/bin/main --section board
./target/release/bin/main --project <某个真实项目名>
```

- **期望**：窗口直接开在指定页 / 指定项目。
- 顺带试**不存在的项目名**：应当落到仪表盘，而不是停在空页或报错。

## 4. 字体（Linux 上最可能翻车的地方）

字体文件路径在 `linux/src/fonts.cj` 的 `cjkFontCandidates()` 里，
Linux 分支列了 Noto CJK、文泉驿、文鼎、Droid 回退。

- 中文**不是方块**。
- emoji 能显示（AI 回复里可能有）。
- **等宽字体生效**：代码块、diff（`提交变动` 里的行）要真的等宽，
  否则对齐全乱。
- 换字体后**不会重排**（CUI 不自动重排，只在建窗前装一次）——
  这是设计限制，界面上已说明，不用报。

## 5. 图标

```sh
bash ../assets/icon/check-icon.sh     # 应六项全绿（校验的是三端同一套）
bash scripts/install-icon.sh          # 装进 ~/.local/share
```

- 启动器 / 文件管理器里出现 `deepDolphin` 且**图标正确**。
- `.desktop` 的 `Exec=` 点得动。
- 三个名字必须同名：`.desktop` 文件名、hicolor 图标名、窗口 `identifier`。

## 6. 缩放与多屏

- **HiDPI 分数缩放**（125% / 150%）下布局是否还成立。
- 双屏不同缩放比之间拖动窗口。
- 这块 macOS 上完全没验（Retina 是整数 2x）。

## 7. 已知异常，等你确认影响

`Cannot inspect commands through a released scene node`（`IllegalStateException`）——
**拆卸阶段**抛出，快照写盘后发生，普通仪表盘快照也会报。

- 请确认：正常关闭窗口时，**用户会不会看到崩溃 / 控制台有没有红字**。
- 如果只发生在 `--snapshot` 模式、不影响正常关闭，也请说一声。

## 8. 真实 provider（如果你有 API key）

协议层照 macOS 端逐条搬，端到端用的是**假 provider**，所以下面这些从未跑过：

- 真 key 下的**流式 / 分块**响应
- 真 HTTP 错误码（401 / 429 / 5xx）在界面上说的话对不对
- 超时与重试
- 工具调用（tool_calls）多轮循环在真 provider 上的形状

配置走设置页。有 key 的话，**发一条真实提问**是本轮最有价值的补充。

## 9. 引擎真的被调起来的样子

**夹具模式（`DD_FIXTURE_DIR`）不起引擎子进程**，所以下面这些只在真跑时才有证据：

- 启动自动读一次项目群（不点刷新）
- 周期轮询（默认 5 分钟）
- **浅更新 / 深更新**真的执行（深更新要几分钟，注意别与自动轮询抢锁）
- git 操作：拉取 / 推送 / 提交 / 暂存 / 取出暂存 / 获取
- 项目详情页的「进度日志」与「托管文档」是真读引擎出来的，不是夹具

## 10. 三条「防御性通路」没有真实数据背书

这三种形状在本机 15 个项目里**一个都不出现**（代码注释里如实标注了），
所以对应分支**从未被真实载荷走过**。如果你手上有别的项目群，麻烦留意一下：

| 形状 | 界面上的话 |
|---|---|
| `dirty.ok = false` | 「脏度读不出来」 |
| `journal.unparsableLines > 0` | 「另有 N 行日志解析不了」 |
| `userDirtyCount = -1` | 未提交数显示成「读不出来」而不是 0 |

**如果你的项目群里出现了这三种，请记下项目名** —— 那说明引擎确实会发，
防御性代码是有用的；如果始终不出现，那也是有效信息（说明这三条是纯防御）。

---

## 怎么回报

每条只要三样：**你做了什么 → 看到什么 → 期望是什么**。

出问题时**把完整错误串贴回来**，别只写「报错了」——
本轮至少有三次是因为「我猜的原因」和「真实报错」不一致而白查了半天。
截图比文字有用。

优先级：**第 1 条（窗口能不能开）> 第 2 条（交互）> 第 3 条（C10）> 其余**。
第 1 条要是就卡住了，后面几条都验不了，先把它解决。
