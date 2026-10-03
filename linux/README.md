# deepDolphin — Linux 客户端

**仓颉 + [CangjieGUI](https://github.com/SunriseSummer/CangjieGUI)（CUI）的桌面实现**，消费 moonGit 引擎的 `--json` 契约。
CUI 本身跨平台（Windows / macOS / Linux），所以这一份代码在 macOS 上也能构建和运行 ——
**本机验证就是在 macOS 上做的**，不需要 Linux 机器。

> 定位见 [../PLATFORM-CHARTER.md](../PLATFORM-CHARTER.md)：交互 UI 各平台自由，**能力必须一致**。
> 这一份实现了 C1（引擎发现与拉起）、C2（状态轮询）、C3（面板四页）、C4（更新动作）、
> C8（git 操作）、C9（里程碑管理）、C11（文档只经引擎），
> 并按 macOS 端**一比一镜像**了布局。尚未接入：C5/C6/C7（AI 三项）、C10（系统集成）。
>
> 图标与其他平台共用一套，见 [../assets/icon/README.md](../assets/icon/README.md)。

## 快速开始

```sh
# 1. 拉第三方依赖（CangjieGUI + CangjieSDL + SDL3 动态库）
sh scripts/fetch-deps.sh

# 2. 跑
sh scripts/run.sh
```

`run.sh` 会自动把 `DEEPGIT_BIN` 指向仓内 `moonGit/target/release/bin/main`；
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
source "$CANGJIE_HOME/envsetup.sh"
export SDKROOT="$HOME/.local/share/sdks/MacOSX.minimal/latest"
cjpm build && cjpm test     # 35 项，全绿

bash ../assets/icon/check-icon.sh   # 图标一致性
```

实机（本机 macOS）已验：

- 引擎定位命中仓内 release，窗口以 metal 后端跑起来，1180×760
- 空态 8 次文本绘制 → 引擎结果经 `post` 回来触发 2 个状态帧 → 稳定到 44 次/帧

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

**未验**：真窗口的**交互**没验过。显示器全程熄屏，SDL 报
`No available video device`，`caffeinate -u` 与合成按键都无效 ——
需要在本机物理操作唤醒屏幕。快照只能证明静态布局对，
证明不了点击、滚动、悬停。

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
| C10 通知 | `notify-send`，更新动作结束时发 |
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
