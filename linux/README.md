# deepDolphin — Linux 客户端

**仓颉 + [CangjieGUI](https://github.com/SunriseSummer/CangjieGUI)（CUI）的桌面实现**，消费 moonGit 引擎的 `--json` 契约。
CUI 本身跨平台（Windows / macOS / Linux），所以这一份代码在 macOS 上也能**构建**，
**本机验证就是在 macOS 上做的**，不需要 Linux 机器。

⚠ 但**在 macOS 上开不出真窗口** —— AppKit 的主线程判定，见下文「验证」一节。
真要在这个平台跑起来，得先解决仓颉运行时与 AppKit 的线程问题。
Linux / Windows 上没有这个障碍。

> 定位见 [../PLATFORM-CHARTER.md](../PLATFORM-CHARTER.md)：交互 UI 各平台自由，**能力必须一致**。
> 这一份实现了 C1（引擎发现与拉起）、C2（状态轮询）、C3（面板四页）、C4（更新动作）、
> C5（AI 整合更新）、C6（AI 助手）、C7（AI 设置）、C8（git 操作）、
> C9（里程碑管理）、C10（系统集成）、C11（文档只经引擎），
> 并按 macOS 端**一比一镜像**了布局。唯一没有对应物的是**托盘/菜单栏常驻** ——
> CUI 不暴露托盘 API，详见下方「已知差异」第 1 条。
>
> 图标与其他平台共用一套，见 [../assets/icon/README.md](../assets/icon/README.md)。

## 快速开始

> ⚠ **在 Linux 上跑之前先读 [VERIFY-ON-LINUX.md](VERIFY-ON-LINUX.md)** ——
> 本客户端的全部开发与自动化验证都在 **macOS** 上做，跨平台 ≠ 已验证。
> 那份文档逐条列了「哪些结论还没在 Linux 上核对过、怎么查、期望看到什么」。

```sh
# 1. 拉第三方依赖（CangjieGUI + CangjieSDL + SDL3 动态库）
sh scripts/fetch-deps.sh

# 2. 跑
sh scripts/run.sh
```

`run.sh` 会自动把 `DEEPGIT_BIN` 指向仓内 `moonGit/target/release/bin/main`，
并把 `DEEPDOLPHIN_MODELS` 指向仓内快照 `assets/models/models-dev.json`
（AI 设置页的 provider 目录数据源；用户已显式指定时这两个变量都不覆盖）；
装过 `install.sh` 的话走 PATH 上的 `moongit` / `deepgit` 也行。

## 依赖

| 依赖 | 版本 | 说明 |
|---|---|---|
| 仓颉 SDK | **1.0.5 LTS**（禁止升级） | 与引擎、CUI 一致 |
| CUI（CangjieGUI） | 0.9.6 | `vendor/`，由 `fetch-deps.sh` 拉取 |
| CangjieSDL | 0.9.6 | 同上，底层 SDL3 绑定 |
| SDL3 / SDL3_ttf / SDL3_image | 系统 | `fetch-deps.sh` 会从系统库目录拷进 `vendor/CangjieSDL/.sdl3/` |

CUI 与 CangjieSDL 是**第三方源码，不进本仓**（`.gitignore` 排除了 `vendor/`）。

macOS 装 SDL3：`brew install sdl3 sdl3_ttf sdl3_image`
Linux 装 SDL3：`sudo apt install libsdl3-dev libsdl3-ttf-dev libsdl3-image-dev`

## 目录

```
linux/
  cjpm.toml
  scripts/
    fetch-deps.sh   拉第三方依赖 + 放 SDL3 动态库
    run.sh          构建并启动（自动配运行时路径与引擎定位）
    dev-launch.sh   跳过构建直接启动（布局自查用）
    install-icon.sh 把公共图标装进 ~/.local/share（.desktop + hicolor）
  src/
    json.cj         只读 JSON 解析（移植自引擎，零第三方依赖）
    engine.cj       引擎子进程通道：定位、调用、契约闸门、失败披露
    engine_ops.cj   每个引擎操作声明自己的载荷形状与超时
    isotime.cj      ISO8601 → 天数（与引擎逐字一致的整数除法）
    model.cj        引擎载荷 → 数据模型（唯一与引擎耦合的地方）
    appstate.cj     全部界面状态 + 后台取数
    tokens.cj       设计令牌（纯数据：色板 / 间距 4-8-12-16-20-24 / 字号）
    theme.cj        视图层：令牌 → 具体颜色
    components.cj   基础视图件（胶囊 / 分段条 / 统计卡 / 告警）
    appearance.cj   深浅色探测与三档覆盖
    sidebar.cj      侧栏（视图组 + 仓库组 + 状态条）
    views.cj        根 / 工具栏 / WorkBar / 看板 / 引擎引导
    detail.cj       里程碑页 + 项目详情一列长卡片
    main.cj         入口
    model_test.cj   判据（纯函数）
  tests/fixtures/   引擎真实输出（布局自查的夹具）
  vendor/           第三方依赖，git 忽略
```

## 与 macOS 端同源的纪律

这几条是照着 macOS 客户端踩过的坑写的，不是风格偏好：

1. **引擎找不到 / 契约过旧 / 部分项目失败，三种情况分开说。**
   揉成一句「加载失败」，用户就得自己猜是哪一种，而三种的处置完全不同。
   状态条与空态各有一处专门的写法（`views.cj` 的 `kindText`）。

2. **失败的项目留在列表里，并显示引擎给的原因。**
   过滤掉它们，界面上「已注册 6 个」会变成 3 个，用户无从知道少了什么。

3. **采集失败的项目不显示「0 提交 / 0 分支」。**
   采集失败时这些计数本来就是 0，画出来等于谎称读过这个仓库。

4. **「还没读到」与「读到了确实是空的」必须长得不一样。**

5. **缺字段不能回落成 0。** 引擎没报失败数时写「?」而不是 0 ——
   把「引擎没说」说成「没问题」，是最难被发现的一类显示错误。

6. **连点两次「刷新」只发一次引擎调用**（`busy` 闸门），且闸门只挡重复发起、不排队。

## 一条真实的坑：过旧的引擎会把「读不到」显示成「读到且是空的」

本机 `~/.local/bin/deepgit` 装着一版旧引擎，它的 `status --json`：

- `summary` 里**没有** `failedProjects` / `listedProjects`
- 每个项目**没有** `error` 字段

而测试沙箱里有 3 个项目路径不可达。客户端第一次跑时，
`Json.intAt(s, "failedProjects", 0)` 把缺键回落成 0、`Json.strAt(v, "error", "")`
把缺字段回落成空串 —— 于是那 3 个读不到的项目**和 3 个健康项目长得一模一样**，
界面上一个警告都没有。

这不是假想：`model_test.cj` 里的 `OLD_ENGINE_STATUS` 就是那份输出的原样拷贝。

两道闸门：

- `engine.cj` 的 `checkContract()` 在入口拦一道，缺披露字段直接判为契约过旧并提示升级
- `model.cj` 的 `failedKnown` 在模型层兜一道，缺字段时 `failedLabel()` 给「?」

两条都验过能红：把 `failedKnown` 改成恒 `true` → `missingFailedCountIsReportedAsUnknownNotZero` 红；
把 `checkContract` 整个换成 `return true` → 两条契约用例红、其余 17 项仍绿。

## 验证

```sh
export CANGJIE_HOME="$HOME/.local/share/cangjie/current"
# SDK 有两种解包布局：envsetup.sh 直接在根，或多套一层 cangjie/（deepin 25 实测是后者）。
# scripts/cj-env.sh 的 dd_cj_locate_sdk 两级都会探测；手动 source 也照两级试。
source "$CANGJIE_HOME/envsetup.sh" 2>/dev/null || source "$CANGJIE_HOME/cangjie/envsetup.sh"
export SDKROOT="$HOME/.local/share/sdks/MacOSX.minimal/latest"
cjpm build && cjpm test     # 35 项，全绿

bash ../assets/icon/check-icon.sh   # 图标一致性
```

实机（本机 macOS）已验：

- 引擎定位命中仓内 release
- `SDL_VIDEODRIVER=dummy` 下渲染循环跑得起来（帧计数、空态绘制、
  引擎结果经 `post` 回来触发状态更新）

**布局自查**（走文件夹具，不起引擎子进程）：

```sh
DD_FIXTURE_DIR="$PWD/tests/fixtures" DD_SNAP_PROJECT=atlas \
  SDL_VIDEODRIVER=dummy bash scripts/dev-launch.sh --snapshot /tmp/x.bmp
sips -s format png /tmp/x.bmp --out /tmp/x.png
```

CUI 的 `--snapshot` 是「连续强制重绘 48 帧就拍照」，而引擎调用走后台线程要
两秒 —— 拍到的永远是「读取项目群…」。所以改用 `DD_FIXTURE_DIR` 从磁盘读
**引擎真实输出**（由 `moongit --json` 直接导出到 `tests/fixtures/`），
`DD_SNAP_ROOT` / `DD_SNAP_PROJECT` 指定拍哪一页。仪表盘、看板、项目详情
三页都用这个路径看过。

### 模拟一次点击（验侧栏接线）

```sh
DD_FIXTURE_DIR="$PWD/tests/fixtures" DD_SNAP_PROJECT=atlas DD_SNAP_CLICK=1 \
  DD_SNAP_W=1400 DD_SNAP_H=2400 SDL_VIDEODRIVER=dummy \
  bash scripts/dev-launch.sh --snapshot /tmp/click.bmp
sips -s format png /tmp/click.bmp --out /tmp/click.png
```

`DD_SNAP_CLICK=<行号>` 会在渲染途中由后台线程 `post` 一次
`model.selected = 行号` —— **就是 ListView 点击时写的那一个 State**。
快照上侧栏高亮换到那一行、主区跟着换成那个项目，说明
`sidebar()` → `mountEffect` → 接线 → 路由 整条链是通的。

**为什么需要它**：这条接线住在 `mountEffect` 的闭包里，
单元判据不开窗就执行不到那个闭包。把 `sidebar()` 里的调用删掉，
119 条判据**照样全绿**，而侧栏从此点了不换页。
（接线函数本身已由 `clickingTheSidebarActuallyRoutesBecauseSomebodyIsListening`
覆盖；`DD_SNAP_CLICK` 守的是「sidebar() 还调不调它」这一截。）

⚠ 负控已验，两张图可直接对比：

| 状态 | 侧栏高亮 | 主区 |
|---|---|---|
| 接线在 | beacon | **beacon** ✓ |
| 接线被摘 | beacon | **atlas** ✗ |

接线被摘时高亮仍跟着动（`selected` 写进去了），但**没人路由** ——
主区停在 atlas 而侧栏亮着 beacon，正是本仓反复警告的
「主区是 B、侧栏亮着 A」分家。

⚠ 试过并且都不行的两条路：写在 `app.run` 的构建闭包里（夹具模式下
无状态变化，闭包**只跑一遍**，而首遍时 `mountEffect` 的 prepare 阶段
还没执行，那时的点击必然无人接 —— 症状与「接线被摘」一模一样）；
以及用「构建遍数计数」等第 2 遍（同样等不到，闭包根本不重跑）。

### 拍破坏性操作确认框（T1）

```sh
DD_FIXTURE_DIR="$PWD/tests/fixtures" DD_SNAP_ROOT=milestones \
  DD_SNAP_CONFIRM="remove:接入统一登录" \
  SDL_VIDEODRIVER=dummy bash scripts/dev-launch.sh --snapshot /tmp/confirm.bmp
```

`DD_SNAP_CONFIRM` 预置一次**挂起的破坏性确认**再拍照 —— CUI 快照只在
启动即拍，用户点不出一个确认框；没有这个开关，确认框的布局（点名对象、
代价句、按钮排布）只能靠「代码读着像对的」来相信。形状：

- `remove:<里程碑名>` / `drop:<里程碑名>` —— 里程碑删除/放弃确认
- `commit[:<项目名>]` —— 提交全部改动确认（缺省取项目群第一个；
  指定一个工作区非空的项目，规模句才有数字可拍）
- `update:deep` / `update:shallow` —— 批量更新确认

预置走的是 `pendConfirm`（与真实按钮同一条入口）：免确认档（达成/重开）
会被拒、框不开 —— 快照上拍不到框，一眼就是接线错了。

### 拍「添加 / 扫描项目」面板（T3）

```sh
DD_FIXTURE_DIR="$PWD/tests/fixtures" DD_SNAP_ADD=single \
  SDL_VIDEODRIVER=dummy bash scripts/dev-launch.sh --snapshot /tmp/add.bmp
DD_FIXTURE_DIR="$PWD/tests/fixtures" DD_SNAP_ADD=scan \
  SDL_VIDEODRIVER=dummy bash scripts/dev-launch.sh --snapshot /tmp/scan.bmp
```

`DD_SNAP_ADD=single|scan` 打开「添加 / 扫描项目」面板再拍 —— CUI 快照只在
启动即拍，用户点不出这个面板。`single` 预填一个**不存在**的路径，让实时
校验披露（「…不存在。请确认目录名后再填绝对路径。」）在场；`scan` 拍批量档
的扫描根 + 深度 Stepper。走 `openAddPane`（与真实按钮同一条入口）。
面板在场与控件接线的可执行判据在 model_test.cj 的
`addScanPaneLensSwitchesModesAndStepsDepthThroughRealControls`（无头镜头）。

### 拍「写动作进行中 / 结果一行」（T5，交互流 D-01）

```sh
DD_FIXTURE_DIR="$PWD/tests/fixtures" DD_SNAP_ACTION=busy \
  SDL_VIDEODRIVER=dummy bash scripts/dev-launch.sh --snapshot /tmp/action-busy.bmp
DD_FIXTURE_DIR="$PWD/tests/fixtures" DD_SNAP_ACTION=fail \
  SDL_VIDEODRIVER=dummy bash scripts/dev-launch.sh --snapshot /tmp/action-fail.bmp
```

`DD_SNAP_ACTION=busy|fail` 预置「写动作进行中 / 上一条失败的批量结果」再拍 ——
深更新一跑几分钟，「按了按钮之后的界面」与「跑完之后的那一行」都点不出来。
`busy` 走 `beginAction`（与真实按钮同一条闸门入口：它只置状态、不起子进程），
拍主区顶部的「进行中」条（**没有关闭按钮** —— 动作在跑时横幅不可关，
见 `bannerDismissible`）＋ 侧栏状态条的「正在执行：…」；`fail` 走 `report`
（与 `endAction` 同一条出口），拍「未完成」红 pill + 逐项目成败名单 +
「关闭」按钮。落点规则（详情页走页头、其他页走横幅）由纯函数
`actionStripOf` 裁决，判据在 model_test.cj 的
`actionStripLandsOnTheDetailHeaderThereAndOnTheMainBannerEverywhereElse`。

⚠ 本节命令在 **Linux 开发机**上真实出图（T5 批次起 ci-local.sh 的 ld 包装
也给主程序 `bin/main` 追加链接垫片，此前主程序在这台机器上链不出来，
见下方「已知代价与边界」第 2 条）；BMP 转 PNG 本机没有 sips/ImageMagick，
用纯 Python 按 BMP 头解 24 位像素再封 PNG 即可。

**未验，且已查明是框架级阻塞**：真窗口的**交互**（滚动、悬停、真实输入）
没验过 —— `DD_SNAP_CLICK` 能证明**点击的路由**通了，但它仍然走的是
`post` 而不是真的鼠标事件，也证明不了滚动与悬停。
真窗口在本机开不出来，原因如下：

⚠ 此前这里写的是「显示器全程熄屏导致 `No available video device`」——**那个解释是错的**，
已按实测推翻。真实原因与屏幕亮不亮无关：

1. 显示器是**亮的**（`IOPMrootDomain` = ON，`PreventUserIdleDisplaySleep` = 1），
   会话是 **Aqua**（`__CFBundleIdentifier = com.apple.Terminal`），
   `screencapture` 能正常抓整屏。
2. 同一时刻、同一会话、**同一份 SDL3**（app 加载的是
   `/opt/homebrew/Cellar/sdl3/3.4.18/lib/libSDL3.0.dylib`；仓内
   `vendor/CangjieSDL/.sdl3/libSDL3.dylib` 的 install_name 正是这个路径，
   两者是同一个文件）——一个纯 C 探针调 `SDL_Init(SDL_INIT_VIDEO)`
   **成功**，`SDL_GetCurrentVideoDriver()` 返回 `cocoa`。
   仓颉进程内插桩同样返回 `Init=true cur=cocoa`。
3. 但紧接着建窗必失败，且报的是：
   `SDL_CreateWindowAndRenderer failed: NSWindow should only be instantiated on the main thread!`
   同一处插桩里 `pthread_main_np()` 返回**真** —— 进程主线程是对的。

也就是说：pthread 上确实是主线程，但 AppKit 不认。
`[NSThread isMainThread]` 比对的是「Foundation 首次初始化时记下的那个线程」，
仓颉运行时若在别的线程上先碰了 Foundation / `NSApplication`，
AppKit 就会在真正的主线程上同样判定「不是主线程」。

**为什么改不了**：要让 `DesktopApp` 建成，得让 CangjieGUI 在 AppKit 认可的那个线程上
建窗 —— 要么改仓颉运行时的线程模型（**1.0.5 锁定，不升级**），
要么改 vendored CangjieGUI/CangjieSDL（第三方，本仓纪律是不改）。
本机**试过并且都不行**的路，留在这儿免得下个人再走一遍：

- 显式 `SDL_VIDEODRIVER=cocoa`：失败信息从 `No available video device`
  变成 `cocoa not available` —— 更早暴露，但不是同一个病
- `nohup … &` 后台起：与前台起**无差别**，不是后台化的问题
- 换 SDL 来源（仓内 vendored ↔ Homebrew）：install_name 相同，是同一个文件
- 预载 `libSDL3_image` / `libSDL3_ttf` / 仓颉运行时后再 `SDL_Init`：都不影响结果
- 在工作线程而非主线程调 `SDL_Init`：C 探针里照样成功，不是线程的问题

所以：**快照能证明静态布局对，证明不了交互。** 交互验收需要先解决上面的
AppKit 线程问题（或换一台非 macOS 的 Linux 机器直接验）。

## 命名边界

与其他端一致：**改名字，不改身份**。
`DEEPGIT_BIN` / `DEEPGIT_HOME` 保持旧名；引擎数据目录 `~/.deepgit` 与文档托管标记
`<!-- deepgit:begin -->` 是引擎侧的身份，本端不碰。详见
[../../moonGit/README.md](../../moonGit/README.md) 的「命名」一节。

## AI 通道（C5 / C6 / C7）与系统集成（C10）

### 已实现

| 能力 | 状态 |
|---|---|
| C7 AI 设置 | provider / 模型 / API Key / Base URL、测试连接、开机自启开关 |
| C6 AI 助手 | 多轮 tool_calls agent 循环，对话界面，停止按钮 |
| C5 AI 整合更新 | 单项目说明 / 项目群说明，结果面板 |
| C5 定时更新 | 六档（关/1/3/6/12/24h，settings.conf 的 `schedule=`），启动（或改档）后 600 秒首轮、之后按档周期对全部项目浅更新；完成后通知三分支：失败带原因 / AI 简报截 180 字 / 未配置 AI 报完成数。有动作在跑时跳过本轮、顺延到下个周期。档位改动最迟 60 秒生效（后台线程 60 秒 tick 读现档） |
| C10 通知 | `notify-send`，更新动作结束时发；定时简报（见上）；停滞提醒——刷新后扫非默认分支 `stale`（`stale:<项目>:<分支>` 键）与未提交 ≥10（`dirty:<项目>:<count/10>` 键按 10 取整换档），键集会话内去重，`headAgo` 进正文；采集失败的项目整只跳过（拿没读到的数据报「停滞」是替引擎下结论） |
| C10 开机自启 | XDG `~/.config/autostart/deepdolphin.desktop` |
| C10 深链 | `--section dashboard\|board\|milestones`、`--project <名>` |

### 与 macOS 端的**已知差异**（如实记，不假装一致）

1. **没有托盘**。CUI 不暴露托盘 API（无 `SDL_SetWindowIcon`、
   无 StatusNotifier 绑定），所以 macOS 的「菜单栏速览」（`MenuBarExtra` + `BarView`）
   在本端没有对应物。不拿「通知」冒充「托盘」—— 那不是同一件事。
2. **AI 面板是主区视图，不是独立窗口/sheet**。CUI 的 `DesktopApp` 只有一扇窗。
   代价：聊天时看不到仪表盘。
3. **密钥降级到 600 权限文件**。macOS 走 Keychain；本端优先 libsecret
   （`secret-tool`），没有时退到 `~/.config/deepdolphin/api-key`（chmod 600），
   **并在设置页显式写明**。不静默降级。
4. **`providerToolModels` 只列支持 tool_calls 的模型** —— 不支持的模型
   在第一轮提问就会撞墙。与 macOS 端 `modelWithToolCall` 同一条规则。
5. **「停止」不是杀请求，是立刻放弃这一轮**。macOS 端 `stop()` 取消任务；
   本端按下停止后：UI 马上解锁、显示已写出来的内容、主循环在**每个工具
   调用之前**与每轮之间检查停止标志、迟到的回写被轮次代号拦住。
   **已经发出但还没回来的那次 HTTP 请求仍然会跑完**（最多到它自己的超时），
   结果被丢弃 —— 这一点在界面上如实写出来。
   为什么不杀 curl：`SubProcess` 句柄由派发它的那条线程持有并在里面 `wait()`，
   从 UI 线程对同一句柄调 `terminate` 是跨线程操作，CUI/SDL 都没承诺它安全。
   赌它不崩，不如换一条确定不崩的路。
6. **Markdown 解析比 macOS 端多修了三处，两端因此不完全一致**。
   这三处都是 macOS 端**同一个病**（`MarkdownParser.swift` 里的悬挂缩进分支是
   死代码：先 `trimmingCharacters` 再问「是不是以两个空格开头」，恒为 false），
   本端按真实输入形状补上：
   - **列表悬挂缩进续行并入上一项**。有序、无序都补。真实的续行长这样
     （本仓库 `linux/README.md` 原文）：序号项下面挂 1-3 行缩进续行。
     macOS 端会把它们拆成独立的段落块 —— 一段 5 条的清单在界面上
     变成「列表 / 段落 / 列表 / 段落」十几块。
   - **`)` 序号分隔符规范化成 `. `**。macOS 端 `12) b` 会渲染成 `12. ) b`
     （漏出一个悬空的 `)`）；本端渲染成 `12. b`。
   - **段落遇到 `***` / `___` 也要断**。macOS 端只判 `---`，
     于是 `***` 会被并进上一段，界面上凭空多出三个星号。
7. **代码块与表格不套内层横向滚动**。macOS 端对这两类用的是
   `ScrollView(.horizontal)`，本端做不到等价：CUI 的 `ScrollView`
   **只有 `scrollState`、没有 `hug()`**，无法按内容定高。硬套上去的后果是
   快照上「正文画到表格就断了」—— 它之后的兄弟节点全被挤成零高，
   看着像解析漏了块（实测踩过）。改成靠外层竖向滚动 + `Label.wrap()` 换行。
   同理，表格**不拆列**：引擎 `context` 里的分支表一行能到 100+ 字符，
   拆列就得自己算列宽，而中文与等宽混排的列宽在 CUI 里没有可靠的测量接口 ——
   算错了比不拆更难看。
   标题字号 22/18/15/14 则**照抄** macOS 端 `MarkdownView`，
   没有套用 `tokens.cj` 的 22/20/16/13：那边也是这套刻度，
   两端都存在「面板刻度 + markdown 刻度」并存。

### 怎么验

```sh
bash scripts/ai-e2e.sh     # 端到端：真 curl + 真引擎 + 假 provider
cjpm test                  # 88 条判据（其中 3 条端到端标 @Skip，日常跳过）
```

端到端脚本会起一个**逐项校验请求体**的假 provider：中文有没有被转义坏、
`stream` 是不是 false、`max_tokens` 是不是整数、工具的 JSON Schema 对不对 ——
校验不过就回标记串让判据红。这一层不能省：纯函数判据只测 ASCII，
而 UTF-8 转义、curl 调用、临时文件读写顺序这三类缺陷**只有真发一次请求才暴露**。

### 依赖

- **`curl`**（AI 通道）。仓颉没有 HTTP 客户端：`std.net` 只有裸 socket，
  `std.crypto` 没有可用的 TLS。
- **`secret-tool`**（可选，系统钥匙串）。没有就退到 0600 文件。
- **`notify-send`**（可选，系统通知）。没有时设置页会写明。

## 2026-10-04 审查批次 —— Linux 第一次系统检验

上面各节的「在 macOS 上验证」到这一节为止：本批在 Linux（deepin 25，
glibc 2.38，无 root、无图形会话）上做了第一次系统性审查与修复，
四个 commit：`5ce9bb4` → `e257732` → `a54dd42` → `5eab21e`。
门禁 `bash scripts/ci-local.sh` 收口：**cjpm test 147 通过 / 0 失败 /
3 端到端跳过**（判据从批前基线 116 只增不减：119 → 125 → 137 → 147），
`scripts/ai-e2e.sh` 端到端实跑通过。其后是功能与交互批 T1–T5
（`586993e` 破坏性操作确认 → `4991424` 启动脚本契约 → `46cea31`
添加 / 扫描项目面板 → `eba9c7e` C5 定时更新 ＋ C10 停滞提醒 →
`4c0aeeb` 写动作可见性），各批收口门禁依次 160 / 165 / 173 / 180 / 184 ——
当前门禁 **184 通过 / 0 失败 / 3 端到端跳过**（共 187 条；只增不减链：
… → 147 → 160 → 165 → 173 → 180 → 184）。本文早前小节里出现的 35 / 88 / 119
是各自写就当时的判据数，以本节为准。

### 修了什么 / 为什么

**1. 通用性：脚本通路与 freedesktop 集成（`5ce9bb4`）**
全是「macOS 上能跑、所以看不出」的路径假设，Linux 第一跑就暴露：

- **自启落对目录**：第一版把 .desktop 写进应用私有目录
  （`~/.config/deepdolphin/autostart/`），而会话登录只扫
  `$XDG_CONFIG_HOME/autostart` —— 整个自启功能等于不存在（`sysint.cj` 的
  `xdgAutostartDir`）。
- **自启 Exec 走 run.sh**：会话拉起的入口必须自己摆好仓颉运行时库路径，
  直接指二进制缺 `libcangjie-runtime.so` 必挂。`Exec=` 现在指向仓内
  `scripts/run.sh` 绝对路径，`--engine` 参数去掉（引擎由 run.sh 的
  `DEEPGIT_BIN` → 仓内 release → PATH 链自己找，与手动启动同一条链）；
  `Exec=` 改为**整参数双引号**转义（旧版 `\s` 在 Desktop Entry 规范里
  不存在，会话会留成字面 `\ `）。
- **三脚本共用 `scripts/cj-env.sh`**：按操作系统（不再按 `uname -m`）选
  仓颉运行时目录、SDK 两级探测（`envsetup.sh` 在根或在 `cangjie/` 一层，
  deepin 25 实测是后者）；ai-e2e.sh 里 source 改绝对 `$DIR`（脚本先
  `cd`，`BASH_SOURCE` 相对路径已失效 —— 首次实跑当场暴露）。
- **工具不再钉死 `/usr/bin`**：`notify-send` 等先走 PATH，找不到才回退
  （`sysint.cj` 的 `firstToolOnPath`）。
- **ai-e2e.sh 的 ANSI 清洗对齐 ci-local.sh**：必须清**全部 CSI 序列**
  而非只清 `m` 结尾的 SGR —— `\x1b[K` 残留曾让 122 条全绿却假报
  「端到端判据没被跑到」。
- run.sh 补 Linux 运行期 SDL3 库路径与 ld 包装器 PATH（见 ci-local.sh
  头注释的链接垫片一节）。

**2. AI 子系统：密钥生命周期与 UI 线程纪律（`e257732`）**

- **密钥原子私有写**：同目录临时文件 → 立即 `chmod 600` → `rename` 原子
  替换；配置目录收紧 **700**。临时文件从创建到 chmod 之间按 umask 可见
  （常见 0644），「写完再 chmod 文件」挡不住那个瞬间（`ai_config.cj`）。
- **AI 响应有损解码**（`fromUtf8Lossy`，GBK 错误页不再整个请求报废）+
  `try/finally` 清临时文件 + **启动清扫**兜 SIGKILL/崩溃残留（临时文件
  头里有 API Key，`ai_http.cj` 的 `sweepAITempLeftovers`）。
- **`stopAI` 同时推进轮次代号**：被放弃轮次的迟到回写被拦，主循环在每轮
  与每个工具调用前检查停止标志 —— 「停止」不会把界面留在忙碌态。
- secret-tool 移出 UI 线程；对话新消息贴底；Markdown 渲染缓存
  （64 条 + 全字节指纹）。

**3. 引擎链路：契约诚实与管道稳健（`a54dd42`）**

- **批量更新改读聚合信封的 `results` 键**（兼容单项目逐仓形状）—— 旧读法
  在真信封下把更新结果整个读丢；里程碑写操作载荷缺结果键**按失败渲染**，
  不再假 ✓。
- `describeEngineFailure` 增读 `{error, code, message}` 形状，更多引擎
  失败原因能被带到界面；`writeOp` 无 JSON 分支带上 stderr。
- **`app.run` 顶层 catch**：异常打印原因后**以 0 退出**（`main.cj`）——
  窗口生命周期已结束，再按崩溃对待只会误导会话与调试器。
- 管道读改**分块缓冲**（逐字节 `add` 在大输出下是平方级）；
  `requestRefresh` 与引擎定位的 `spawn` 整体兜异常 —— spawn 里没人接的
  异常会让线程死掉、`post` 永不来，`busy` 永不复位。
- **notify-send 挪后台线程**，发送卡住不再拖 UI。
- **引擎定位挪到首帧之后**：定位要起子进程探活、挂住的候选要等满超时，
  在建窗前做能把首屏拖几十秒。现在窗口先出、显示「正在定位引擎…」
  （`views.cj`），定位完挂载再读数。

**4. CUI 美学：可点性、对比度与令牌统一（`5eab21e`）**

- **五处 `.enabled` 方向反转**：空闲主按钮灰死、忙碌时被闸门拒掉的按钮
  误亮 —— 可点性与真实状态相反，比不可点更误导。
- 侧栏「＋添加/扫描项目」**伪可点 Label 降级**为 muted 说明，并写明
  `moongit scan` 真实命令（画成可点但点了没反应，是最坏的一种）。
  （T3 批次起这里已换成真按钮，开「添加 / 扫描项目」面板，
  见「功能与交互批」一节。）
- **外观三档接入设置页**：跟随系统/亮/暗，写
  `$XDG_CONFIG_HOME/deepdolphin/settings.conf`；启动没探到系统外观时
  （`appearanceUnknown`）渲染成 muted 披露，不假装跟随了系统。
- **状态色文字新增亮底深变体 `dsTextColor`**（amber-700/orange-700）：
  白卡上黄/橙文字从 1.92:1 / 2.8:1 提到 ≥4.5:1，判据里**实算 WCAG
  对比度**。
- 删 tokens 的 `FS_*` 死令牌；视图层裸 `fontSize` 全量收进 `fs*` 七档
  （仪表盘 KPI 大数字从 30 收到 22，视觉变小是**有意的统一**）。
- 筛选 chip 改框架 `Chip` + `State.project` 镜头：恢复 hover / 焦点环 /
  键盘切换，选中态从筛选值推导（旧手写选中态会和真实筛选值分家）。
- `milestoneDueText` 逾期分支收窄为契约哨兵 `daysToTarget == -1`：
  此前 `< 0` 一律报「日期无效」，真实的「已逾期 N 天」被吞
  （`views.cj`）。

### 功能与交互批（T1–T5）落了什么

审查批之后同一张门禁（`ci-local.sh`）上又收五批，对能力清单的增量按批记；
各批快照拍法见「验证」一节对应小节：

- **T1 破坏性操作零确认收口**（`586993e`）：删/放弃里程碑、「全部」浅/深
  更新、「提交全部改动」四类动作一律先过确认 Modal（mac 端
  `DestructiveGuard` 的移植）：标题/正文点名具体对象、写明「不留备份、
  无法恢复」的代价；提交含未跟踪文件时单独点名密钥风险 —— 引擎的
  `commit` 走 `git add -A`，提交的是整个工作区。达成/重开**故意**免确认
  （可逆操作弹框只会教会确认疲劳，负控判据钉着这条边界不许扩散）；
  单项目更新与 mac 端 `.project` 分支同口径保持直连，「全部」目标才弹框。
- **T2 启动脚本契约修复**（`4991424`）：自启入口算不出、C7 模型目录够不着
  这两个「文档说的、脚本没做」，见下文「文档同步时新发现的缺陷：已修」。
- **T3 应用内「添加 / 扫描项目」面板**（`46cea31`）：侧栏与空态换真按钮，
  新装用户不再被推去终端。单项目添加（路径校验：空 / 相对 / 是文件 /
  不存在均拒，输入框下实时判行）＋ 目录批量扫描（深度 1–6 Stepper）；
  结果读真实信封（found / added / existing）并披露覆盖度三因
  （截断 / 深度封顶 / 读不出来，mac 端 `ScanCoverage` 的移植）。
  审查批次把侧栏入口降级成「终端运行 moongit scan」说明的那一条，
  本批起被本面板取代。
- **T4 C5 定时更新 ＋ C10 停滞提醒**（`eba9c7e`）：章程 C10 的三类通知
  （更新完成 / 停滞提醒 / 定时简报）补齐后两类，能力与档位见上方
  「已实现」表的 C5 / C10 两行。
- **T5 写动作「正在执行 / 结果一行」出详情页外可见**（`4c0aeeb`）：
  批量更新一跑几分钟，「按了按钮之后」与「跑完之后」各有一行 ——
  主区顶部横幅（进行中 ＝ pill＋「正在执行：…」，**不可关**；结束 ＝
  完成 / 未完成 pill＋结果一行，可关；详情页页头已在场就不重复挂，
  落点由纯函数 `actionStripOf` 裁决），侧栏状态条同步消费同一句状态
  （引擎断连染警示色）。顺带清零 pollCountdown / emptyHint / detailTab /
  docTab 四个只写不读的死状态。

### 已知代价与边界（如实记，不假装没付出）

1. **外观探测不能跟着挪到首帧后**。审查项原设想「外观探测也挪」，
   与 CUI 不变量冲突：`Theme` 是 `DesktopApp` 构造参数且不可变
   （vendor `src/core/theme.cj` 标注 "Immutable"，无 setTheme），
   首帧后翻暗色会得到半套错色板。按红线如实说明而非绕过：探测留在
   建窗前但超时 3000→1500ms，**外观切换是「落盘 + 重启生效」**，
   设置页文案写明 —— 这是有意的不做，不是遗留。
2. **主程序在本机的链接曾经断着（T5 批次起打通了无头这条路）**。release
   主程序因 CangjieSDL 的 SDL 3.4 专属绑定符号在本机链不出来（ci-local.sh
   的 ld 包装原本只把垫片追加给测试二进制，见 `sdl-shim.c` 注释）——
   后果是「界面快照实拍」整条自查路径瘫痪。T5 批次把垫片同样追加给
   主程序 `bin/main` 的链接（同一份 no-op 垫片，快照路径同样不调那几个
   符号；只活在这台开发机的 `~/.local/bin/ld`，真机 SDL 3.4 环境没有
   包装器、不受影响），`DD_SNAP_ACTION=busy|fail` 两张实拍即本批出图。
   **真窗口与交互（滚动 / 悬停 / 键盘）仍然未验** —— 无图形会话，
   快照证明的是静态布局，不是交互。
3. **暗色主题下橙字压橙胶囊实测 4.27:1**，仍略低于 4.5 —— 本批变体只收
   亮底方向（暗底亮色对暗卡 5.2~7.6:1 达标），暗色未另立变体；
   `C_RED` 文字对白卡 3.76:1 未动（现有红字都在告警卡/胶囊语境）。
4. `fromUtf8Lossy` 对尾部残缺序列按 WHATWG 口径**每个滞留字节各出
   一个 U+FFFD**，与 Python 式「整段一个」口径不同 —— 接其他语言实现时
   注意对齐。`AIConfig.loadProblem` 是读取诊断字段，不属于与 macOS 端
   对齐的四个落盘字段（类注释已划界）。
5. 自启的**写盘动作**曾长期没有单测（碰真实 `~/.config/autostart`，不宜在
   判据里写真文件）。T2 批次起写盘核心抽成收目录的 `setAutostartIn`，
   `/tmp` 沙盒判据覆盖写→回读→删→幂等→拒写→建目录全链；真实
   `~/.config` 仍然只在用户机器上写。
6. `hasNotifySend` / `hasSecretTool` 在没装这些工具的机器上**如实报缺**
   —— 是环境事实，不是缺陷。
7. **定时更新与停滞提醒的三个已知代价（T4）**：① 档位改动**最迟 60 秒
   生效**（mac 端重建 timer 立即生效）—— 周期线程每 60 秒醒来读现档，
   换来不跨线程打断一条睡眠中的线程；② 停滞提醒的去重键以**项目名**为
   身份（mac 端用 `p.id`，本端 `Project` 没有 id 字段），项目改名后会
   重报一次；③ 去重键集不落盘、**只活在会话内**（`notifiedKeys`，
   `appstate.cj`）—— 重启客户端后第一轮刷新会把仍在的停滞/积压再报
   一遍。

### 文档同步时新发现的缺陷：已修（T2 批次，启动脚本契约）

上一批文档同步时发现两处「注释/文档声称的启动脚本行为，脚本根本没做」，
T2 批次修掉：

- **从 run.sh 启动时，自启开关必然拒绝（已修）**：run.sh 末行曾是
  `exec ./target/release/bin/main`（**相对路径**），而 `getCommandLine()[0]`
  返回的就是这个相对串（上轮以最小仓颉程序实测定谳：`exec ./argvprobe` 下
  `getCommandLine()[0]` = `"./argvprobe"`）；`sysint.cj` 的
  `autostartClientEntry()` 要求 `argv[0]` 以 `/` 开头，否则返回空串，
  设置页于是永远给出「算不出自启入口」的提示。拒绝本身是 R3-02 的守卫在
  **正确地**工作，但文档给的主入口（run.sh）满足不了它。本批两脚本末行改
  `exec "$HERE/target/release/bin/main"`，上溯逻辑抽成纯函数
  `autostartEntryFromArgv`（`/r/linux/target/release/bin/main` →
  `/r/linux/scripts/run.sh`；相对串 → 空串，拒写守卫不松动），空入口的
  界面提示也改写为「请通过 scripts/run.sh 启动」—— 旧文案让用户走
  裸二进制，那条路永远满足不了守卫。
- **`DEEPDOLPHIN_MODELS` 声称注入、七个脚本零命中（已修）**：
  `ai_catalog.cj` 的注释一直说「启动脚本注入 DEEPDOLPHIN_MODELS」，
  实际没有一个脚本做 —— 从文档主入口 run.sh 启动时，候选链只剩 XDG
  数据目录两条，仓内快照 `assets/models/models-dev.json` 够不着，
  C7 目录驱动的 provider 选择整体死亡（红色「模型目录不可用」卡；
  mac 基准是 bundle 内快照启动即用）。本批 run.sh / dev-launch.sh 都
  注入 `DEEPDOLPHIN_MODELS="$HERE/../assets/models/models-dev.json"`
  （与注入 `DEEPGIT_BIN` 同一套做法：用户显式指定时不覆盖，快照不在时
  不指死路）；候选构造抽成纯函数 `catalogSearchPathCandidates`，判据
  断言三条候选齐全、缓存先于安装位。
- **判据**：argv 纯函数、目录候选纯函数、自启写盘 `/tmp` 沙盒全链
  （写→回读→删→幂等→空入口拒写连目录都不建→mkdir -p 分支），外加
  源码扫描对两脚本各钉四条断言（绝对路径 exec、禁相对 exec、注入键、
  快照路径；负控验红：删任一关键行判据红）。

### 仍未验（详见 [VERIFY-ON-LINUX.md](VERIFY-ON-LINUX.md)）

- 真窗口与一切交互（滚动 / 悬停 / 键盘 / 缩放）—— 本机无图形会话；
- 自启「注销重登真实拉起」；
- 真实 provider（真 key / 流式 / 401 429 5xx）从未跑过。

（「界面快照实拍」已不在未验之列：T5 批次起主程序链接通了，
`DD_SNAP_ACTION` 两张实拍即证据，见「验证」一节与「已知代价与边界」第 2 条。）
