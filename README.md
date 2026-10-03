# deepDolphin Clients

**deepDolphin 的各平台 UI 交互层（含 AI 层）。** 业务核心全部在 [moongit](https://github.com/asdshuaishuai/moongit)（仓颉引擎，AI 无关），
本仓库的每个客户端都是**展示与 AI 层**：通过 **CLI 子进程**调用引擎（`moongit <命令> --json`）读写数据，AI 的配置/调用/工具循环在客户端完成。

**跨平台能力基准**：见 [PLATFORM-CHARTER.md](PLATFORM-CHARTER.md) —— 四大平台交互 UI 自由，能力必须一致（C1–C11 矩阵）。

## 目录结构

```
deepDolphin/
  assets/icon/  全平台唯一应用图标（母版 mark.png + 派生 out/ + 判据 check-icon.sh）
  macos/        macOS 客户端（SwiftUI，已实现）——菜单栏常驻 + 主面板窗口
  linux/        Linux 客户端（仓颉 + CangjieGUI，已实现读侧与写侧）
  deepin/       deepin 客户端（DDE 专属，DTK6 原生，已实现）——1:1 复刻 macos/ 功能基准
  windows/      Windows 客户端（规划中：WinUI 3 / WPF，消费同一套 CLI 契约）
  harmonyos/    鸿蒙 PC 客户端（规划中：ArkUI，消费同一套 CLI 契约）
```

> 引擎是多平台共用的唯一核心；新平台客户端只需实现「引擎发现 + 拉起 + CLI 调用 + 原生 UI」。
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
sh build.sh        # swift build -c release + 组装 deepDolphin.app + ad-hoc 签名
open deepDolphin.app
```

构建期会尝试把引擎二进制与仓颉运行时内嵌进 .app（自包含分发）；不内嵌则按
`DEEPGIT_BIN → 内嵌副本 → ~/.local/bin → 登录 shell PATH` 的顺序发现引擎。

> `DEEPGIT_BIN` / `DEEPGIT_HOME` 这两个环境变量名**保持旧名不变** —— 它们是外部调用方的既有接口，
> 改名会让所有现存的启动脚本与文档一次性失效。引擎侧同理：`~/.deepgit` 数据目录与
> `<!-- deepgit:begin -->` 文档托管标记都是硬编码的既有数据身份，跟着改名会让引擎认不出已托管的区域、另开新区。
> 只有**名字**（引擎 moonGit、应用 deepDolphin、CLI 命令 moongit）改了，**身份**没改。

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
./build/deepDolphin --selfcheck                # 模型层自检（55 例）
./build/deepDolphin                            # 或先 scripts/smoke.sh
```

DTK6/Qt6 原生（QWidget），放在专属目录 `deepin/`，与 `linux/`（仓颉 + CangjieGUI 通用版）互不影响；
功能以 `macos/` 为 1:1 基准，C1–C11 逐项实现位置与快捷键映射见 deepin/README.md。
AI 未显式配置时默认走系统级 AI（UOS AI 只能唤起对话窗口，如实降级、不假装补全）；
显式配置的 OpenAI 兼容 / Anthropic 渠道优先。
