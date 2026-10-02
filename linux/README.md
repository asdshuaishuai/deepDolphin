# deepDolphin — Linux 客户端

**仓颉 + [CangjieGUI](https://github.com/SunriseSummer/CangjieGUI)（CUI）的桌面实现**，消费 moonGit 引擎的 `--json` 契约。
CUI 本身跨平台（Windows / macOS / Linux），所以这一份代码在 macOS 上也能构建和运行 ——
**本机验证就是在 macOS 上做的**，不需要 Linux 机器。

> 定位见 [../PLATFORM-CHARTER.md](../PLATFORM-CHARTER.md)：交互 UI 各平台自由，**能力必须一致**。
> 这一份目前实现了 C1（项目列表）、C2（现状/仪表盘）、C3（分支进度）、C5（失败披露），
> 写操作（更新 / 里程碑 / git 操作）尚未接入。

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
  src/
    json.cj         只读 JSON 解析（移植自引擎，零第三方依赖）
    engine.cj       引擎子进程通道：定位、调用、失败披露
    model.cj        引擎载荷 → 数据模型（唯一与引擎耦合的地方）
    appstate.cj     全部界面状态 + 后台取数
    views.cj        怎么显示
    main.cj         入口
    model_test.cj   判据（纯函数，19 项）
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
cjpm build && cjpm test     # 19 项，全绿
```

实机（本机 macOS）已验：

- 引擎定位命中仓内 release，窗口以 metal 后端跑起来，1180×760
- 空态 8 次文本绘制 → 引擎结果经 `post` 回来触发 2 个状态帧 → 稳定到 44 次/帧

**未验**：窗口**像素**没看过。本机 `screencapture` 抓不到 CUI 的 Metal 窗口
（官方示例 `calculator` 同样抓不到，而它的 `--profile` 显示渲染正常），
所以「画面对不对」目前只有帧统计与语义树作为间接证据。要看画面需在有
GUI session 的 Linux 桌面上跑，或用 CUI 的 `WidgetTestHost` 截图比对。

## 命名边界

与其他端一致：**改名字，不改身份**。
`DEEPGIT_BIN` / `DEEPGIT_HOME` 保持旧名；引擎数据目录 `~/.deepgit` 与文档托管标记
`<!-- deepgit:begin -->` 是引擎侧的身份，本端不碰。详见
[../../moonGit/README.md](../../moonGit/README.md) 的「命名」一节。
