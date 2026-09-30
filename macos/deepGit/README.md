# deepGit — macOS 客户端

> 双形态原生客户端：**主面板窗口**（完整 git 项目管理面板）+ **菜单栏 bar**（辅助速览）。
> 本项目是纯客户端，独立于引擎构建与发布。

## 形态

| 形态 | 入口 | 内容 |
|---|---|---|
| **主面板**（主体） | 菜单栏「打开面板」、点击 bar 项目行、或 `deepGit --open-panel` | 侧栏导航：**仪表盘**（统计卡/语言分布/里程碑/活跃项目）、**里程碑**（列表 + 新建/达成/放弃/删除）、**项目详情**（工程脉搏、提交构成、分支进度、Git 操作、进度日志、**README/AGENTS/CLAUDE 平铺渲染**） |
| **菜单栏 bar**（辅助） | 常驻状态项（如 `15 ⚠︎1`） | `.window` 富弹窗：汇总行 + 项目速览行（状态点/未提交徽标/待记录迷你进度条）+ 全部浅更新 + 退出 |

状态项标题即健康度：项目数 + `⚠︎N`（有停滞分支）或 `●N`（有未提交改动），图标颜色随状态变化（绿/橙/红）。

## 引擎 / 客户端边界（重要）

| 职责 | 归属 | 说明 |
|---|---|---|
| 项目注册、进度记录、文档写入 | **引擎** | `deepgit scan/update/deep/track`，CLI 与 HTTP API |
| 状态 / 仪表盘 / 里程碑 / 日志数据 | **引擎** | `GET /api/status`、`/api/dashboard`、`/api/milestones` |
| 更新 / 里程碑 / git 操作 | **引擎** | `POST /api/update`、`/api/deep`、`/api/milestones`、`/api/milestones/action`、`/api/git`（pull/push/commit/stash/unstash/fetch 白名单，无破坏性命令） |
| 文档内容 | **引擎** | `GET /api/docs?name=` 返回 README/AGENTS/CLAUDE 原文（单文件 200KB 截断），客户端本地渲染 |
| 进度存储（`~/.deepgit/store/`） | **引擎** | 客户端不落任何业务数据 |
| 引擎发现与拉起 | **客户端** | `DEEPGIT_BIN` → app 内嵌副本（`Contents/Resources/deepgit`）→ `~/.local/bin` → `/usr/local/bin` → 登录 shell PATH；找到后按需 `deepgit serve` |
| 数据获取与渲染、通知、自启 | **客户端** | 本仓库全部代码 |
| 退出清理 | **客户端** | 若引擎服务是本 app 拉起的，退出时一并停止 |

契约：引擎 `--json` / HTTP 的键名是**唯一耦合面**，改动必须同步
`Sources/deepGit/Models.swift` 与引擎 `flow/*.cj`。

## 系统集成

- **开机自启**：`SMAppService`（bar 或面板内开关，macOS 13+）
- **系统通知**：分支停滞 / 未提交过多 / 更新完成（只在状态「新变差」时提醒）
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
  Model.swift           AppModel（数据编排/动作/提醒策略）+ 通知 + SMAppService
  BarView.swift         菜单栏弹窗 UI
  PanelView.swift       主面板骨架（NavigationSplitView 侧栏 + 路由）
  DetailViews.swift     项目详情页 + 仪表盘页
  MilestonesView.swift  里程碑管理页（含新建 Sheet）
  Components.swift      StatusDot / StatCard / SegmentedBar / Card 等基础件
```
