# deepGit — macOS 客户端

> 双形态原生客户端：**主面板窗口**（完整 git 项目管理面板）+ **菜单栏 bar**（辅助速览）。
> 本项目是纯客户端，独立于引擎构建与发布。

## 形态

| 形态 | 入口 | 内容 |
|---|---|---|
| **主面板**（主体） | 菜单栏「打开面板」、点击 bar 项目行、或 `deepGit --open-panel` | 侧栏导航：**仪表盘**（项目群脉搏 hero + 一键说明 + 图标统计卡/语言分布/里程碑/活跃项目）、**看板**（按健康状态分列：活跃/待处理/停滞/其他，卡片带快捷动作）、**里程碑**（行内直操作：点击行跳项目、··· 菜单达成/重开/放弃/删除）、**项目详情**（工程脉搏、提交构成、分支进度、Git 操作、进度日志、README/AGENTS/CLAUDE 平铺） |
| **菜单栏 bar**（辅助） | 常驻状态项（如 `15 ⚠︎1`） | `.window` 富弹窗：汇总行 + 项目速览行（状态点/未提交徽标/待记录迷你进度条）+ 全部浅更新 + 退出 |

状态项标题即健康度：项目数 + `⚠︎N`（有停滞分支）或 `●N`（有未提交改动），图标颜色随状态变化（绿/橙/红）。

## AI 助手（客户端 AI 层，deepDesign 模式 · models.dev + ai-sdk）

引擎是 **AI 无关**内核；AI 的目录、通道、配置与 agent 循环全部在本客户端，
实现方式与 deepOrca 同构：**models.dev 目录 + ai-sdk 通道**。

- **models.dev 目录**（`ModelsDev.swift`）：vendor 快照 `Resources/models-dev.json`
  （从 deepOrca 的 models-dev/api.json 瘦身，225 家 provider）+ 启动后静默刷新最新目录。
  数据仅作选择器与通道元数据：模型 id、tool_call、reasoning、上下文窗口、成本、provider api 端点。
- **ai-sdk 通道**（`AISDK.swift`）：`LanguageModel.generateText` ——
  OpenAI 兼容（deepseek/openai/ollama/openrouter/网关…）与 Anthropic 双协议，
  **原生 tool_calls / tool_use 线格式**（不是文本协议）；baseURL 默认取目录 `api` 字段。
- **设置**（AI 助手页 ⚙️）：provider/model 选择器由目录填充（⚡︎=tool_call、🧠=reasoning、
  上下文窗口徽标），Base URL 默认目录端点可覆盖；**key 存 macOS 钥匙串**；一键测试连通。
- **AI 助手**（侧栏 ✦）：选范围提问 → 引擎 `/api/context` 上下文包 + `/api/tools` 工具清单 →
  模型原生调用引擎工具（更新/读文档/提交改动…），客户端执行后回喂，≤4 轮 → Markdown 渲染。
- 无头自测（CI/排查）：`deepGit --agent-selftest "总结一下项目群现状"`；
  本地 mock 验证：`defaults write cn.deepgit.app ai.providerID mock` +
  `ai.baseURL http://127.0.0.1:5999/v1` + `ai.apiKey mock-key`（配一个回 tool_calls 的假 provider）。

## 引擎 / 客户端边界（重要）

| 职责 | 归属 | 说明 |
|---|---|---|
| 项目注册、进度记录、文档写入 | **引擎** | `deepgit scan/update/deep/track`，CLI 与 HTTP API |
| 状态 / 仪表盘 / 里程碑 / 日志数据 | **引擎** | `GET /api/status`、`/api/dashboard`、`/api/milestones` |
| 更新 / 里程碑 / git 操作 | **引擎** | `POST /api/update`、`/api/deep`、`/api/milestones`、`/api/milestones/action`、`/api/git`（pull/push/commit/stash/unstash/fetch 白名单，无破坏性命令） |
| agent 喂养（上下文包/工具清单） | **引擎** | `GET /api/context`、`GET /api/tools`——引擎 AI 无关，只供事实与动作 |
| **AI 目录/通道/配置、工具循环** | **客户端** | models.dev 目录（快照+刷新）选型；ai-sdk 风格通道（OpenAI 兼容 + Anthropic 原生 tool_calls）；key 存钥匙串；agent 循环在 AgentView |
| 文档内容 | **引擎** | `GET /api/docs?name=` 返回 README/AGENTS/CLAUDE 原文（单文件 200KB 截断），客户端本地渲染 |
| 进度存储（`~/.deepgit/store/`） | **引擎** | 客户端不落任何业务数据 |
| 引擎发现与拉起 | **客户端** | `DEEPGIT_BIN` → app 内嵌副本（`Contents/Resources/deepgit`）→ `~/.local/bin` → `/usr/local/bin` → 登录 shell PATH；找到后按需 `deepgit serve` |
| 数据获取与渲染、通知、自启 | **客户端** | 本仓库全部代码 |
| 退出清理 | **客户端** | 若引擎服务是本 app 拉起的，退出时一并停止 |

契约：引擎 `--json` / HTTP 的键名是**唯一耦合面**，改动必须同步
`Sources/deepGit/Models.swift` 与引擎 `flow/*.cj`。

## 系统集成

- **开机自启**：`SMAppService`（bar 或面板内开关，macOS 13+）
- **系统通知**：分支停滞 / 未提交过多 / 更新完成 / 定时简报（只在状态「新变差」时提醒）；**点击通知 = 打开面板**，通知自带「打开面板」动作按钮
- **Dock 菜单**：右键 Dock 图标 = 打开面板 / 全部浅更新
- **服务托管**：打开面板时自动拉起引擎 HTTP 服务（默认 `127.0.0.1:5177`，可用 `DEEPGIT_PORT` 覆盖）
- **应用图标**：`AppIcon.png`（PIL 生成的 git 分支拓扑 + ◆ 记号）→ `AppIcon.icns`，
  build.sh 自动拷入 bundle（CFBundleIconFile）。
- **深链启动参数**：
  - `deepGit --open-panel` 启动即开主面板
  - `--project <名称>` 直达项目详情
  - `--section milestones|dashboard` 直达对应页

## 构建

```sh
sh build.sh        # swift build -c release + 组装 deepGit.app + ad-hoc 签名
open deepGit.app
# 安装：cp -R deepGit.app /Applications/
```

`build.sh` 会尝试把引擎二进制与仓颉运行时 dylib 内嵌进 .app（~59MB），
使其可独立分发；不内嵌则按上面的发现链找系统里的引擎。

## 代码结构

```
Sources/deepGit/
  DeepGitApp.swift      入口：MenuBarExtra(.window) + AppDelegate（深链参数/退出清理）
  PanelWindow.swift     主面板 NSWindow 管理（确定性开窗）
  Engine.swift          引擎发现 + serve 托管 + APIClient（ URLSession ）
  Models.swift          HTTP 契约 Codable 模型（与引擎 flow 层 JSON 严格同名）
  ModelsDev.swift       models.dev 目录（vendor 快照 + 静默刷新）→ provider/model 元数据
  AISDK.swift           ai-sdk 风格通道：generateText + 原生 tool_calls/tool_use；配置（钥匙串）
  AgentView.swift       AI 助手：会话 UI + 工具调用循环（引擎 /api/tools 驱动）
  AISettingsView.swift  AI 设置页（provider/模型/密钥/测试连接）
  MarkdownView.swift    轻量 Markdown 渲染（文档平铺与 AI 回答共用）
  Model.swift           AppModel（数据编排/动作/提醒策略）+ 通知 + SMAppService
  BarView.swift         菜单栏弹窗 UI
  PanelView.swift       主面板骨架（NavigationSplitView 侧栏 + 路由）
  DetailViews.swift     项目详情页 + 仪表盘页
  MilestonesView.swift  里程碑管理页（含新建 Sheet）
  Components.swift      StatusDot / StatCard / SegmentedBar / Card 等基础件
```
