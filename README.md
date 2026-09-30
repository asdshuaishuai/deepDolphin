# deepGit Clients

**deepGit 的各平台 UI 交互层（含 AI 层）。** 业务核心全部在 [deepgit-engine](https://github.com/asdshuaishuai/deepgit-engine)（仓颉引擎，AI 无关），
本仓库的每个客户端都是**展示与 AI 层**：通过引擎的本地 HTTP API（`127.0.0.1`）读数据、POST 写操作，AI 的配置/调用/工具循环在客户端完成。

**跨平台能力基准**：见 [PLATFORM-CHARTER.md](PLATFORM-CHARTER.md) —— 四大平台交互 UI 自由，能力必须一致（C1–C11 矩阵）。

## 目录结构

```
clients/
  macos/        macOS 客户端（SwiftUI，已实现）——菜单栏常驻 + 主面板窗口
  windows/      Windows 客户端（规划中：WinUI 3 / WPF，消费同一套 API）
  linux/        Linux 客户端（规划中：GTK4 / Tauri，消费同一套 API）
  harmonyos/    鸿蒙 PC 客户端（规划中：ArkUI，消费同一套 API）
```

> 引擎是多平台共用的唯一核心；新平台客户端只需实现「引擎发现 + 拉起 + API 消费 + 原生 UI」。

## 引擎 / 客户端职责边界

| 职责 | 归属 |
|---|---|
| git 采集、进度库、文档托管写入、AI 摘要 | **引擎** |
| 状态 / 仪表盘 / 里程碑 / 文档内容数据 | **引擎**（`GET /api/*`） |
| 更新 / git 操作 / 里程碑写操作 | **引擎**（`POST /api/*`） |
| 引擎发现与拉起、数据渲染、系统集成（通知/自启/菜单栏） | **客户端** |

契约：引擎 HTTP API 与 `--json` CLI 的键名是唯一耦合面，改动必须同步各客户端的模型层。

## macOS 客户端

见 [macos/deepGit/README.md](macos/deepGit/README.md)。

```sh
cd macos/deepGit
sh build.sh        # swift build -c release + 组装 deepGit.app + ad-hoc 签名
open deepGit.app
```

构建期会尝试把引擎二进制与仓颉运行时内嵌进 .app（自包含分发）；不内嵌则按
`DEEPGIT_BIN → 内嵌副本 → ~/.local/bin → 登录 shell PATH` 的顺序发现引擎。
