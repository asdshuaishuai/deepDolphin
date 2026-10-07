# deepDolphin — 客户端路线图（跟随引擎）

> **原则**：deepDolphin 本质上是 moonGit 引擎的上层实现——引擎每新增一个端点，
> 客户端就新增一个 UI 入口。本路线图跟随 [moonGit ROADMAP](https://github.com/asdshuaishuai/moongit/blob/main/docs/ROADMAP.md) 的 Phase 划分。
>
> **四大平台能力必须一致**（PLATFORM-CHARTER.md C1–C11），交互 UI 允许差异。

---

## 当前状态（v0.1.x）

| 完成 | 能力 |
|---|---|
| ✅ | CLI 子进程通信（EngineCLI，无 HTTP） |
| ✅ | 仪表盘（统计卡 + 提交构成 + 语言分布 + 看板 + 里程碑 + 活跃项目） |
| ✅ | 项目详情（脉搏 / 提交构成 / 分支进度 / Git 操作 / 进度日志 / 文档平铺） |
| ✅ | 看板独立页（四列状态卡片） |
| ✅ | 里程碑管理（CRUD + tag 自动达成 + 行内按钮） |
| ✅ | AI 整合更新流（浅+AI摘要 / 深+AI报告 / 一键项目说明 / 一键项目群说明 / 定时简报） |
| ✅ | AI 设置（models.dev 目录驱动 / 钥匙串 / 测试连接） |
| ✅ | 菜单栏常驻（速览弹窗） |
| ✅ | ScanSheet（添加单个 + 批量扫描） |
| ✅ | zh_CN 本地化 |

---

## Phase 1 跟进（引擎 v0.2.x）

| 引擎能力 | deepDolphin 需要做的 | 优先级 |
|---|---|---|
| 1.1 进度差分 | 详情页新增「变化」tab：展示两次快照之间的分支增减/提交增减/里程碑变化 | P0 |
| 1.2 速度追踪 | 仪表盘新增速度曲线图（Sparkline / Charts framework） | P1 |
| 1.4 并发 serve | 无（引擎内部） | — |
| 1.5 Linux 二进制 | 无（客户端已支持选择引擎二进制路径） | — |
| 1.6 数据导出 | 工具栏「导出」按钮 → NSSavePanel → 写文件 | P1 |
| 1.7 registry v2 | 侧栏项目分组展示（按 group 折叠/展开） | P1 |
| 1.8 进度历史 API | 详情页「趋势」tab（Charts framework 绘制） | P1 |

**macOS 特有**：
- [ ] 菜单栏弹窗增加「里程碑到期」快捷区
- [ ] 通知点击跳转指定项目（通过 `--project` 深链）
- [ ] 触控板手势：双指滑动切换页面

---

## Phase 2 跟进（引擎 v0.3.x–v0.4.x）

| 引擎能力 | deepDolphin 需要做的 | 优先级 |
|---|---|---|
| 2.1 watch 模式 | 设置页「实时模式」开关；状态栏图标实时刷新 | P1 |
| 2.2 分支生命周期 | 看板卡片 / 项目详情增加分支操作按钮 | P0 |
| 2.3 多根扫描 | ScanSheet 支持多目录输入 | P1 |
| 2.4 webhook 通知 | 设置页 webhook 管理（列表 + 测试） | P1 |
| 2.5 查询语言 | 搜索栏升级：支持表达式语法（`dirty>10 AND stale`） | P1 |
| 2.6 模板系统 | 设置页模板选择器 | P2 |
| 2.7 Windows 二进制 | 无（客户端基础设施） | — |
| 2.8 快照回滚 | 详情页「撤销」按钮 + 快照列表 | P1 |

**macOS 特有**：
- [ ] Shortcuts app 集成（AppIntents framework）
- [ ] MenuBarExtra 弹窗增加迷你看板
- [ ] Touch Bar 支持（如果用户还有 Touch Bar Mac）

---

## Phase 3 跟进（引擎 v0.5.x）

| 引擎能力 | deepDolphin 需要做的 | 优先级 |
|---|---|---|
| 3.1 远程同步 | 设置页同步配置；冲突 UI；同步状态指示器 | P0 |
| 3.2 团队聚合 | 「团队」页：按 author 统计 / 项目贡献者列表 | P1 |
| 3.3 review 工作流 | 「待审核」队列；approve/reject 操作 | P1 |
| 3.4 Web Dashboard | 无（引擎内置，浏览器直接看） | — |
| 3.5 OpenAPI | 无（第三方自己生成客户端） | — |

---

## Phase 4 跟进（引擎 v1.0+）

| 引擎能力 | deepDolphin 需要做的 |
|---|---|
| 4.1 插件系统 | 插件管理 UI；第三方插件的沙箱执行环境 |
| 4.3 AI agent 框架 | 客户端可作为 agent 的前端聊天界面 |
| 4.5 自定义仪表盘 | 拖拽式 dashboard 布局编辑器 |

---

## Windows / Linux / 鸿蒙 跟进

参照 [PLATFORM-CHARTER.md](PLATFORM-CHARTER.md) C1–C11 矩阵逐项实现。

每个新平台客户端的验收标准：
- 引擎发现与拉起（含 FDA/TCC 等权限问题处理）
- 仪表盘 / 看板 / 里程碑 / 项目详情 四页
- AI 整合更新流（C5）
- AI 助手对话（C6）
- AI 设置（C7，key 存平台安全存储）
- 系统集成（托盘/菜单栏 + 通知 + 自启）

---

## 技术债

| 项 | 说明 | 目标 |
|---|---|---|
| 平台版本 13→14 | `.macOS(.v14)` 已升但需回归测试 | Phase 1 |
| EngineCLI 大 JSON 主线程解码 | status 70KB 在 MainActor 解码；改为 detached 解码后回传 | Phase 1 |
| withLock 竞态 | execCapture 超时后 outFuture 泄漏读线程；需要 SubProcess kill API | 等 Cangjie 暴露 |
| TCC 预检 | contentsOfDirectory 在 TCC 阻塞下无限挂起；需要带超时的文件系统检测 | Phase 1 |
