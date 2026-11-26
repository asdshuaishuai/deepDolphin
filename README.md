# Canopy — Sylva 的跨平台客户端

**Canopy** 是 **Sylva** 家族的客户端（Kotlin + Compose Multiplatform，**全平台唯一客户端**：macOS / Linux / Windows）——UI 交互层与 AI 层。
业务核心全部在 [cambium](https://github.com/asdshuaishuai/moongit)（仓颉引擎，AI 无关），
本仓库的每个客户端都是**展示与 AI 层**：通过 **CLI 子进程**调用引擎（`cambium <命令> --json`）读写数据，AI 的配置/调用/工具循环在客户端完成。

**跨平台能力基准**：见 [PLATFORM-CHARTER.md](PLATFORM-CHARTER.md) —— 四大平台交互 UI 自由，能力必须一致（C1–C11 矩阵）。

## 目录结构

```
Canopy/
  client/       **Canopy**——Compose Multiplatform 客户端（全平台唯一客户端，功能对齐的唯一目标）
  assets/icon/  全平台唯一应用图标（母版 mark.png + 派生 out/ + 判据 check-icon.sh）
  macos/ linux/ deepin/ windows/ harmonyos/
                各平台原生客户端（历史实现 / 规划）——**已冻结**：2026-11-26 定「全平台都用 CMP，
                不再做专属平台的原生开发」，目录暂留，不再是功能对齐目标
```

> 名字（2026-11-26 品牌升级）：整个项目 **Sylva**；引擎 **Cambium**（本仓库通过 CLI 子进程调用）；
> 置信度 **Dendro**（引擎内的独立包，命令 `cambium dendro …`）；客户端 **Canopy**。
>
> **图标不按平台分家**：唯一母版在 `assets/icon/mark.png`，各平台产物由
> `assets/icon/make-icons.py` 生成、只许引用不许复制，
> `assets/icon/check-icon.sh` 守住这条线。详见
> [assets/icon/README.md](assets/icon/README.md)。

## 引擎 / 客户端职责边界

| 职责 | 归属 |
|---|---|
| git 采集、进度库、文档托管写入、AI 摘要 | **引擎** |
| 状态 / 仪表盘 / 里程碑 / 文档内容数据 | **引擎**（CLI 只读命令 + `--json`） |
| 更新 / git 操作 / 里程碑写操作 | **引擎**（CLI 写命令） |
| 引擎发现与拉起、数据渲染、系统集成（通知/自启/菜单栏） | **客户端** |

契约：引擎 `--json` CLI 与 MCP 工具输出的键名是唯一耦合面，改动必须同步各客户端的模型层。

## macOS 客户端

见 [macos/README.md](macos/README.md)。

```sh
cd macos
sh build.sh        # swift build -c release + 组装 Canopy.app + ad-hoc 签名
open Canopy.app
```

构建期会尝试把引擎二进制与仓颉运行时内嵌进 .app（自包含分发）；不内嵌则按
`CAMBIUM_BIN → MOONGIT_BIN / DEEPGIT_BIN（旧名兜底）→ 内嵌副本 → ~/.local/bin → 登录 shell PATH` 的顺序发现引擎
（PATH 上依次找 `cambium`、`moongit`、`deepgit`）。

> `DEEPGIT_BIN` / `DEEPGIT_HOME` 这两个环境变量名**保持旧名不变** —— 它们是外部调用方的既有接口，
> 改名会让所有现存的启动脚本与文档一次性失效。引擎侧同理：`~/.cambium` 数据目录与
> `<!-- deepgit:begin -->` 文档托管标记都是硬编码的既有数据身份，跟着改名会让引擎认不出已托管的区域、另开新区。
> 只有**名字**（引擎 Cambium、应用 Canopy、CLI 命令 cambium）改了，**身份**没改。
> 客户端自己的私有目录跟着改名并自动迁移：`~/.config/deepDolphin → ~/.config/canopy`、
> `~/.cache/deepDolphin → ~/.cache/canopy`、自启条目 `deepdolphin.desktop → canopy.desktop`（见 `LegacyPaths.kt`）。
> 整个项目叫 **Sylva**：Cambium（引擎）+ Dendro（引擎内的置信度包）+ Canopy（客户端）。

## Linux 客户端

见 [linux/README.md](linux/README.md)。

## deepin 客户端（DDE 专属）

见 [deepin/README.md](deepin/README.md)。

```sh
cd deepin
python3 scripts/bootstrap-deps.py --download   # 用户态工具链 sysroot（无需 root，详见 deepin/README.md）
sh scripts/setup-deps.sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel 4
./build/Canopy --selfcheck                # 模型层自检（55 例）
./build/Canopy                            # 或先 scripts/smoke.sh
```

DTK6/Qt6 原生（QWidget），放在专属目录 `deepin/`，与 `linux/`（仓颉 + CangjieGUI 通用版）互不影响；
功能以 `macos/` 为 1:1 基准，C1–C11 逐项实现位置与快捷键映射见 deepin/README.md。
AI 未显式配置时默认走系统级 AI（UOS AI 只能唤起对话窗口，如实降级、不假装补全）；
显式配置的 OpenAI 兼容 / Anthropic 渠道优先。
