# deepin / DDE 版（DTK6）修复计划 —— 完美融入 deepin 生态与 DTK 生态

> **本文档性质**：既是设计计划，也是**可交接的执行手册**。文中每个任务都有唯一 ID（M0-1、M3-4 …）、精确落点（`文件:行号`）、验证命令与验收判据。
> **任何智能体接手时**：先读 §0（目标）→ §11（环境速查）→ §12（交接须知与不变量）→ §9（进度看板）找到第一个 `□`，做完打 `☑` 并在 §10 执行日志追加一行，**再动下一个**。
> 接手的智能体**不需要**读其它文档即可开工；需要背景时按 §12 的索引去读。
>
> 对象：`deepin/`（deepDolphin，DTK6/Qt6 Widgets 客户端）。
> 依据：`PLATFORM-CHARTER.md`（C1–C11）、`deepin/README.md`（功能/取舍全录）、以及对 `deepin/src`（≈90 源文件、9.4k 行）的四个维度审计（DTK 用法 / 视觉审美 / DDE 生态 / 运行时质量）。
> 目标只有一句话：**让它在真机 deepin 25 上「看起来、动起来、融进去」都像一个原生 DDE 应用，而不是一个用 Qt 写的开发者工具。**
> 命令/契约/能力基准（mac 1:1）不动；本计划只改「客户端层的原生性、生态接入、视觉一致性、真机可用性」。

---

## 0. 完成定义（DoD，全部可机器判定）

| # | 验收项 | 判定方式 |
|---|---|---|
| D1 | 主窗与全部对话框的可见控件 ≥95% 为 DTK 原生（`DPushButton/DSuggestButton/DLineEdit/DPasswordEdit/DSpinBox/DTextEdit/DComboBox/DListView/DTreeView/DProgressBar/DIconButton/DScrollArea/DBlurEffectWidget/DFloatingMessage/…`） | `grep -rc "new Q\(PushButton\|LineEdit\|ComboBox\|SpinBox\|PlainTextEdit\|TextEdit\|ListWidget\|TreeWidget\|ProgressBar\|ScrollArea\)(" src/ui` 降到个位数，且每处有注释说明为何必须裸 Qt（`ui/common/` 自绘控件——状态点/进度段——是 DDE 内建先例，允许存在） |
| D2 | 无任何散落的表面/描边/文字色与字号：颜色、字号、间距、圆角、图标尺寸、几何、阈值各有单点真相源 | `grep -rnE "#[0-9A-Fa-f]{6}|setPixelSize|font-size: *[0-9]+px" src/ui src/tray` 命中 = 0（`logic/CommitTypeComposition.cpp` 12 色板、`ui/DesignTokens.cpp` token 实现点、`src/platform/*` 允许在白名单内） |
| D3 | 亮/暗主题、系统字号档位、系统强调色**运行时**全部跟随 | 会话中切换主题与字号，9 个界面区域刷新而无残留旧色（见 §4.1 截图矩阵） |
| D4 | HiDPI 100%/125%/150%/200% 下无模糊发虚、无文字截断 | 控制中心缩放下 `--snapshot` 矩阵 + 目视 |
| D5 | Wayland 会话托盘、速览弹窗、通知叫醒三项系统集成可用（不再退化成"永远弹在主屏右上/点不动"） | 真机 `QT_QPA_PLATFORM=wayland` 会话逐项点一遍 |
| D6 | 桌面身份完整：启动器可搜到（含中文关键词）、任务栏分组、通知可点回、「关于」有元信息、右键有快捷动作 | `desktop-file-validate` + `appstream-util validate` + 真机逐项 |
| D7 | 可以出包装进 deepin（deb），安装后不依赖任何 sysroot/开发容器环境变量 | 干净 deepin 25 容器内 `dpkg-deb -b` + 安装 + 启动，`ldd \| grep "not found"` = 0 |
| D8 | `--selfcheck` 例数不下降，且新增主题/字号/DPI/图标/路由回归项 | `./build/deepDolphin --selfcheck` 全绿 |
| D9 | 中英文可切换（界面文案不再硬编码中文字面量） | `LANG=zh_CN.UTF-8` / `en_US.UTF-8` 各跑一遍 `--snapshot` |

---

## 1. 现状盘点（审计事实摘要）

### 1.1 已经做对的（**不要推翻**）

| 项 | 证据 |
|---|---|
| `logic/` + `models/` 零 GUI 依赖 + `--selfcheck` 55 例契约判定 | `src/app/SelfCheck.cpp:102-466`（466 行、10 组 fixtures，含"缺键必须整体被拒"） |
| 单实例 + 二实例深链转发、DBus 友/客用法、libsecret 只进 key | `src/main.cpp:199,246-251`；`src/ai/SecretStore.cpp` |
| 引擎发现链诚实报错、`EngineCli` 超时/信号收尾、`ProcessRegistry` 停止语义 | `EngineLocator.cpp:20-49`、`EngineCli.cpp:132-165`、`ProcessRegistry.cpp:45-49` |
| 托盘 tooltip=menuTitle、通知不替换未读、`--snapshot`/`--agent-selftest` 无头夹具 | `TrayController.cpp:92-96`、`Notifier.cpp:50`、`main.cpp:85-119` |
| 语义色 funnel（`DS::semColor`）与间距/圆角/字号 token 的**意图正确** | `DesignTokens.h:17-31`、`DesignTokens.cpp:31-34` 唯一亮暗分派点 |
| UI 自由、能力与 mac 1:1、文档注释密度高（"为什么"注释文化） | `deepin/README.md` 决策 1–27 |

### 1.2 缺口（按"离完美融入"的距离排序）

| 域 | 现状（证据） | 后果 |
|---|---|---|
| **真机可用性（P0）** | `AppModel.cpp:970-974 setEngineResult` **没回灌 `EngineCli::setEngineBin`**；`EngineLocator::locate()` 同步探活在 GUI 线程（`main.cpp:205` 在 `show()` 前，最坏 ~100s 白屏）；`AiSettingsDialog.cpp:83` 构造内同步读 libsecret；`--agent-selftest` 不强制 mock 渠道（可能真打 HTTP 烧额度） | 装完引擎点「重新检测」→ 提示已找到 → 实际每次 notFound 且状态翻回"未找到"，必须重启 |
| **DTK 原生性** | `setStyleSheet` 86 处 / 24 文件；`new QPushButton` 30+ 处；`QLineEdit/QComboBox/QSpinBox/QPlainTextEdit/QListWidget/QTreeWidget/QProgressBar/QScrollArea` 遍布；`AiSettingsPane.cpp:80` 用 `QLineEdit` 而头文件注释明写 `DPasswordEdit` | "纯 Qt 感"，与 DDE 内建应用并排一眼可辨 |
| **调色板/主题** | `DesignTokens.cpp:70-91` 表面三级手写双主题；`main.cpp:167-184` 同一批色值**重复装配第二遍**；`main.cpp:246-251` 只接 `newProcessInstance`，**没接 `themeTypeChanged/paletteTypeChanged/fontChanged`** | 运行中切主题大面积不刷新（整树 `setStyleSheet(...name())` 是"重建时拍快照"，`ProjectDetailPage` 每次 `delete layout()`） |
| **字号** | 6 档硬编码 px（`DesignTokens.cpp:99-116`）+ 3 处 QSS 内联 `font-size`；全仓 0 处 `DFontSizeManager/DFontManager` | 用户在控制中心放大字号，本应用纹丝不动，`AgentDialog.cpp:49 setFixedSize(720,620)` 直接裁切 |
| **图标** | `IconLoader::symbol()` 无调用方，`TrayController.cpp:12-34` 私抄第二套 `tintedIcon()`；`data/icons/` 仅 1 个 SVG，无 `dd-*.svg`；本容器 Qt6Svg 缺失 → 染色通道整体是死代码，"引擎未找到"只看到手绘占位方块 | 真机观感受损最直观的一处 |
| **不一致** | 两种红并存（`Derived.cpp:261,282,292,299` `#EF4444` vs `DesignTokens.cpp:53` `#DC2626`）；两种 accent 蓝（`#0081ff` vs `TrayPopupWindow.cpp:207 #1E6FEB`）；进度条 4 种高度、状态点 5 种尺寸、按钮 padding 5 种、圆角 4 个游离值（含 `PanelWindow.cpp:104` 的 4px——设计系统里不存在的值） | 单点改一处不可能统一 |
| **状态/动效** | 唯一动效是 agent 滚动 0.20s；页面切换、卡片 hover/焦点全无；busy 5 种表达（文本/`…`/spinner/禁用），全局刷新零反馈；空态两种风格且无 CTA；无骨架屏 | "静态工具感" |
| **DDE 生态** | 无 `setDesktopFileName`；无自有 DBus 服务；desktop 缺 `Keywords[zh_CN]/SingleMainWindow/MimeType/Actions/Version`；无 appdata/metainfo；无 deb 打包；无 i18n；无 `.service`；`AutostartManager.cpp:89-99` 缺 `OnlyShowIn=Deepin/X-GNOME-Autostart-Phase/X-Deepin-Autostart`，且 Exec 写开发容器绝对路径 | 进不了 DDE 桌面生态：搜不到、点不回、装不了 |
| **Wayland** | `TrayController.cpp:119` 依赖 `QSystemTrayIcon::geometry()`（Wayland 恒无效）；`PanelWindow.cpp:838-843 bringToFront` 只有 raise/activate；弹窗 `Qt::Tool` 失焦收起不可靠；全仓 0 处 platform 分支 | deepin 25 默认 Wayland 下系统集成三项全劣化，而 X11/offscreen 测不出来 |
| **HiDPI** | 0 处 `devicePixelRatio` 处理；托盘/状态点/迷你条全是 1x QPixmap | 125%/200% 缩放下发虚 |
| **可观测** | 装了 DLog appender 但 `dInfo/dWarning` 0 处；`--version` 字面量与 CMake 脱节；关键路径无日志 | 用户报障无日志 |
| **代码组织** | `AppModel.cpp` 1081 行、`ProjectDetailPage.cpp` 858 行；`segSheet` 两份实现（`AutomationPane.cpp:15-22` 那份残留跨函数 `.arg`，正是 `DashboardFilterBar.cpp:10-22` 注释记录过的告警 bug 同类）；卡片内边距 6 处复制 | 改一处要改 N 处 |

---

## 2. 修复原则（红线，先立规矩再动手）

R1. **单点真相源**：颜色/字号/间距/圆角/图标/几何/阈值，一律只准出现在 `ui/DesignTokens.*`、`src/platform/*`、`logic/Thresholds.h` 三个收口内；`logic/` 与 `tray/` 不得持有颜色（`Derived.cpp:254-300`、`TrayPopupWindow.cpp` 的私有色板全部回收）。
R2. **原生优先、降级诚实**：DTK 原生控件是默认路径；仅在 dev 容器（`DApplication::loadDXcbPlugin()` 返回 false）允许 QSS 兜底，且兜底样式**只准从 `DS::*` 取值**。不得因为容器观感不好而长期用手搓替代原生（这是当前最大历史债务：`README.md:482-485`）。
R3. **运行时跟随系统**：主题/字号/强调色/圆角/动效开关全部接 `DGuiApplicationHelper` 信号与 `DStyle::pixelMetric`，不允许"启动时拍一次快照"。
R4. **每个改动可无头回归**：视觉改动必须落在 `--snapshot` 矩阵（亮/暗 × 4 页 × 2 字号）里，截图基线入库（`deepin/docs/snapshots/`），CI 比对。
R5. **能力基准不动**：C1–C11、CLI `--json` 契约、`macos/` 1:1 语义、`--selfcheck` 例数不减。
R6. **诚实降级不假装**：UOS AI 无程序化补全出口（决策 20 已实测）→ 继续"唤起 + 明说原因"，不得编造补全；新增能力同样区分"跑成了 / 没跑成（附原因与下一步）/ 跑了没产出"。
R7. **文档同步**：每完成一个任务，把「为什么这么定 + 已知代价」写进 `deepin/README.md` 的「取舍与已知边界」，决策编号**从 28 起续**（见 §12.4）。

---

## 3. 分阶段修复路线

> 工期按 1 人估（含自测）。三波次见 §7。**任务 ID 即交接单元**：一个任务 = 一次可编译、可验证、可单独 commit 的改动。

### M0. 真机可用性（阻断缺陷，先做；约 3–5 天）

| # | 任务 | 落点（文件:行号） | 验证命令 / 判据 |
|---|---|---|---|
| M0-1 | 「重新检测引擎」回灌 `EngineCli::setEngineBin`；`engineMissing` 区分"从未设过 bin"与"运行中丢失" | `app/AppModel.cpp:970-974`、`:111-115` | 真机或桩引擎：无引擎启动 → 设 `DEEPGIT_BIN` → 点「重新检测引擎」→ 面板出数据，`--selfcheck` 保持全绿 |
| M0-2 | `EngineLocator::locate()` 异步化（首个候选先行 + 「正在检测引擎…」忙态），启动先 `show()` 后探活 | `app/EngineLocator.cpp:59-81`、`main.cpp:205`、`ui/PanelWindow.cpp:266-277` | 无引擎机器启动到可见面板 <1s；点重新检测 UI 不冻结（`time` 测两次点击响应） |
| M0-3 | `AiSettingsDialog` 构造内 libsecret 读挪进 worker（对位 `AgentDialog::probeConfiguredAsync`），回填 `m_original/apiKey` | `ui/dialogs/AiSettingsDialog.cpp:79-86` | 密钥环卡住时打开设置不冻结 |
| M0-4 | `Settings` 单例不再被 worker 直接读写（worker 侧本地快照 / `QMetaObject::invokeMethod` 取回）；`sync()` 移出主线程关键路径 | `app/Settings.*`、`AppModel.cpp:148/542/639/676`、`AgentDialog.cpp:75`、`main.cpp:254-257` | 运行期无 "QObject::setParent: Cannot set parent, new parent is in a different thread" / QSettings 跨线程告警 |
| M0-5 | `AgentCore` 的引擎子进程纳入可 kill 注册（或加 `cancelled` 周期检查 + kill）；UI 文案改「停止（当前工具会跑完）」 | `ai/AgentCore.cpp:34`、`AppModel.cpp:754-771`、`ui/dialogs/AgentDialog.*` | 见决策 D-9；README 需记录与 mac 相同的已知限制 |
| M0-6 | 批量闸门改专用信号，`refreshLight` 不再误触发 `updateAll` | `AppModel.cpp:613-621,269-273` | 300s 轻刷新窗口内批量更新不被提前触发 |
| M0-7 | CLI 健壮性：`--agent-selftest` 强制 `providerID="mock"`（不再烧真额度）；2500ms 睡眠改有界轮询；`--snapshot` 等 `hasLoadedProjectsOnce()`/`refreshCycleFinished` 再抓；`--version` 改由 CMake 生成 `DD_VERSION` 单源 | `main.cpp:36-119`、`main.cpp:136-139`、`CMakeLists.txt` | `./build/deepDolphin --version` 与 `CMakeLists.txt project()` 版本号一致；`--snapshot` 无引擎时 exit 失败而非拍空图 |
| M0-8 | 真机构建矩阵：干净 deepin 25（系统 Qt6/DTK6，无 sysroot）跑通 configure+build+selfcheck，**首次编译 `DD_HAVE_QTSVG` 分支**并单独验证 | `scripts/build-system.sh`（新）、`scripts/smoke.sh` | CI 两条矩阵（sysroot / system）都绿 |
| M0-9 | 关键路径补日志：`EngineCli::callJson`（命令/退出码/耗时/是否超时）、`AIChannel` 失败（已有 `redact`）、`SecretStore` 失败、刷新轮次结果；`DLogManager::registerJournalAppender()`；设置页「打开日志目录」（`DLogManager::getlogFilePath()`） | `EngineCli.cpp:136-148`、`AIChannel.cpp:96-102`、`SecretStore.cpp:67-69/92-95`、`ui/dialogs/panes/GeneralPane.*` | `~/.log/deepin/deepDolphin.log` 有内容，`journalctl` 可检索 |

### M1. DTK 原生化（生态一致的载体；约 8–12 天）

**1a 控件替换表（对应 D1）**

| 位置 | 现在 | 换成 |
|---|---|---|
| `ui/dialogs/panes/AiSettingsPane.cpp:80`（key） | `QLineEdit` | `DPasswordEdit`（注释早已这么写，仅改实现） |
| `ui/dialogs/AgentDialog.cpp:190`、`ui/pages/ProjectDetailPage.cpp:370`、`ui/dialogs/AddMilestoneDialog.cpp:60` | `QPlainTextEdit/QTextEdit` | `DTextEdit` |
| `AiSettingsPane.cpp:45/61/73/83`、`AddMilestoneDialog.cpp:36/41`、`ScanDialog.cpp:82`、`MilestonesPage.cpp:29`、`ProjectDetailPage.cpp:333` | `QLineEdit` | `DLineEdit` |
| `ScanDialog.cpp:98` | `QSpinBox` | `DSpinBox` |
| `AddMilestoneDialog.cpp:27`、`AiSettingsPane.cpp:45/65`、`DashboardFilterBar.cpp:60`、`MilestonesPage.cpp:50` | `QComboBox` | `DComboBox`（仓内已有用法：`ui/WorkBar.cpp:29`） |
| `ui/pages/BoardPage.cpp:132`、`ui/pages/MilestonesPage.cpp:169` | `QTreeWidget` | `DTreeView` + `DHeaderView` |
| `ui/SidebarNav.cpp:71` | `QListWidget` | `DListView`（选中态改 `DStyle::PE_ItemBackground`/`DPalette::ItemBackground`，修掉默认灰蓝选中） |
| `ui/pages/DashboardPage.cpp:188`、`ui/pages/ProjectDetailPage.cpp:686` | `QProgressBar` | `DProgressBar` |
| `DashboardPage.cpp:30`、`ProjectDetailPage.cpp:61`、`AgentDialog.cpp:129`、`AiSettingsDialog.cpp:45/51` | `QScrollArea` | `DScrollArea` |
| `ui/PanelWindow.cpp:487-506`（✕/刷新/AI助手/设置/搜索） | flat `QPushButton` | `DIconButton`（24px 档，尺寸走 `DStyle::PM_IconButtonIconSize`） |
| `ui/pages/MilestoneRowWidget.cpp:165/171/177` | `QPushButton` | `DPushButton`/`DWarningButton`（破坏性） |
| `ui/DualTrackButtons.cpp:20/22`（主操作） | QSS 强调色实底 | `DSuggestButton`（凭 `loadDXcbPlugin()` 判定；容器内保留 `DS::` 取值的兜底 QSS，见原则 R2） |
| `ui/pages/DashboardFilterBar.cpp:39/109`、`ui/dialogs/panes/AutomationPane.cpp:43/80` | 多钮 + QSS 分段 | `DButtonBox`，或统一抽 `ui/common/SegmentedButton`（**单一实现**：收掉 `AutomationPane.cpp:15-22` 残留的跨函数 `.arg` bug） |
| `PanelWindow.cpp:89-107`（提示条）、`ui/DualTrackButtons.cpp:33-37`（徽章） | `QLabel`+QSS | `DFloatingMessage` / `DTipLabel` |
| `src/tray/TrayPopupWindow.cpp:16-18` | 裸 `Qt::Tool\|Frameless` + 自绘 | `DBlurEffectWidget`（DDE 圆角+高斯模糊；圆角 `DStyle::PM_TopLevelWindowRadius`）；Wayland 下改 `Qt::Popup`（见 M1c） |
| 全仓 8 处 `palette(mid/midlight/text)` QSS | 两套颜色语言 | 统一 `DS::textSecondary()/surfaceBorder()`（`TrayPopupWindow.cpp:33/194/201/238`、`SidebarNav.cpp:86/100`、`DashboardFilterBar.cpp:21`、`AutomationPane.cpp:21`） |

**1b 生态 API 统一**

| # | 任务 | 落点 |
|---|---|---|
| M1-1 | `QStandardPaths` → `DStandardPaths`（口径与 DDE 一致） | `EngineLocator.cpp:6/46/49`、`AutostartManager.cpp:57`、`SysOpen.cpp:5-27`、`ModelsDevCatalog.cpp:113/150` |
| M1-2 | 图标走统一 `platform::icon(name, size, tone)`：带 `IconLoader::symbol()` 染色 fallback 链 + 缺失告警；DTK6 深之度图标格式 `DDciIcon` 优先 | 8 处 `QIcon::fromTheme` 直调（`ProjectDetailPage.cpp:41`、`SidebarNav.cpp:78/118`、`PanelWindow.cpp:498`、`MilestonesPage.cpp:41`、`DashboardFilterBar.cpp:69`、`WorkBar.cpp:26`、`AiSettingsDialog.cpp:35-38`） |
| M1-3 | 托盘迁移 StatusNotifierItem 模型（DDE 任务栏按 SNI 管托盘）。优先 `KStatusNotifierItem`；DTK6 未提供则自建最小 `org.kde.StatusNotifierItem` D-Bus 服务，**保留 `TrayController` 对外接口不变** | `tray/TrayController.cpp:60` |
| M1-4 | 通知补齐 DDE hint：`desktop-entry=cn.deepdolphin.app`、`image-path`（亮/暗两套）；同类失败通知按类别持有 `replaceId`（顶替而非堆积）；`timeOut` 由 Settings 驱动 | `app/Notifier.cpp:43-60` |
| M1-5 | 自启模板补 `OnlyShowIn=Deepin;`、`X-GNOME-Autostart-phase=Desktop`、`X-Deepin-Autostart=true`；Exec 策略：已安装优先 `Exec=deepDolphin`（不写绝对路径），开发树路径则拒绝勾选自启并说明 | `platform/AutostartManager.cpp:53,89-99` |
| M1-6 | UOS AI：`launchChat` 改 `asyncCall` + watcher；`probe()` 加锁（`mutable` 缓存）；探测时 dump `org.deepin.copilot` 全部接口名进日志（未来出现程序化补全出口可第一时间发现） | `ai/SystemAiEngine.cpp:21,80-87` |

**1c Wayland / 平台层（M1 后段）**

| # | 任务 | 落点 |
|---|---|---|
| M1-7 | 新增 `src/platform/Backend.{h,cpp}`：`enum Backend { X11, Wayland, Other }`，`current()` 判定 `QGuiApplication::platformName()`；收口「托盘弹窗定位 / 窗口激活 / 任务栏几何」三件事 | 新文件 + `PanelWindow.cpp:838-843`、`tray/TrayPopupWindow.cpp:120-137`、`tray/TrayController.cpp:119` |
| M1-8 | Wayland 分支：速览弹窗优先用托盘所在屏幕 + `org.deepin.dde.Panel` 位置/光标位置定位；`bringToFront` 改用 `windowHandle()->requestActivate()` + `showNormal()`；弹窗失焦收起加 `QGuiApplication::applicationStateChanged` 兜底（或改 `Qt::Popup`） | 同上 |
| M1-9 | `--platform-probe` headless 夹具：打印当前 backend + `QSystemTrayIcon::geometry()` 是否有效 + 当前主题 + 字号档位，真机回归可断言 | `main.cpp` + `scripts/` |

### M2. DDE 桌面生态融合（应用身份与分发；约 5–8 天）

| # | 任务 | 落点/产出 | 验证 |
|---|---|---|---|
| M2-1 | `main.cpp` 增加 `QGuiApplication::setDesktopFileName("cn.deepdolphin.app")`（Wayland 窗口分组、通知点回的前提） | `main.cpp:148-152` | `GTK_DEBUG` 无关；真机任务栏分组、通知点回生效 |
| M2-2 | desktop 补全：`Version=1.0`、`GenericName[zh_CN]`、`Keywords`、`Keywords[zh_CN]=git;项目;进度;面板;`、`SingleMainWindow=true`、`MimeType=inode/directory;`（与 `logic/Route.cpp::parseArgs` 实际消费能力对齐，否则去掉 `%F`）、`Actions`（打开面板 / 扫描项目） | `data/cn.deepdolphin.app.desktop` | `desktop-file-validate data/cn.deepdolphin.app.desktop` 零告警（进 CI） |
| M2-3 | 注册自有 DBus 服务（服务名**另起** `cn.deepdolphin.app.Runtime`，勿与单实例 id `cn.deepdolphin.app` 相撞）：提供 `Activate()` / `OpenProject(QString)`；`DBusActivatable=true` + 安装 `data/cn.deepdolphin.app.service`；`--project` 深链走 DBus 触发 | `src/platform/AppService.*`（新）、`data/`、`CMakeLists.txt` install | `dbus-send --session --dest=cn.deepdolphin.app.Runtime --type=method_call /cn/deepdolphin/app cn.deepdolphin.app.Runtime.Activate` 叫醒面板 |
| M2-4 | 元信息：`metainfo/cn.deepdolphin.app.appdata.xml`（摘要/描述/分类/截图文案/Changelog），安装到 `${DATADIR}/metainfo` | `CMakeLists.txt` install 段 | `appstream-util validate-relax --nonet metainfo/*.xml`（进 CI） |
| M2-5 | i18n：建 `translations/`，`lupdate`+`lrelease` 产物化 `.qm`（至少 `zh_CN`/`en_US`），安装到 `${DATADIR}/deepdolphin/translations`；`main.cpp` 保留 `loadTranslator()`（DTK 译本）后追加项目译本装载；硬编码中文常量搬进 `tr()` | `TrayPopupWindow.cpp:27`、`tray/TrayController.cpp:82-88` 等 | 两套 locale 下 `--snapshot` 各一张基线图（D9） |
| M2-6 | 图标集：`data/icons/hicolor/{16,22,24,32,48,64,128,256}/apps/deepdolphin.png` + `symbolic/apps/deepdolphin-symbolic.svg`；新增 `dd-*.svg`（`dd-git`、`dd-milestone`、`dd-warning`、`dd-circle-double`、`dd-ai`），登记 `resources/resources.qrc`，改 `install(DIRECTORY)` | `data/icons/`、`CMakeLists.txt:142-143` | 托盘/菜单/空态图标不再出现"手绘占位方块"（M3 后目视） |
| M2-7 | 出包：`debian/`（control 声明 `dtk6-core,dtk6-gui,dtk6-widget`、`qt6-*`、`libsecret-1-0`；changelog；rules 走 `dh`+CMake；postinst 跑 `update-desktop-database`/`gtk-update-icon-cache`；postrm 清自启）+ `scripts/build-deb.sh` | `deepin/debian/`（新） | 干净 deepin 25 容器内 `scripts/build-deb.sh` → `dpkg -i` → 启动 → `ldd \| grep "not found"` = 0 |
| M2-8 | 安装后零环境变量：开发树的 rpath/sysroot 依赖不得进包（包内 binary 只准链系统库） | `scripts/build-deb.sh` + `CMakeLists.txt` | 同 M2-7 |

### M3. 审美系统化（D2/D3/D4/D9；约 10–15 天）

**3a DesignTokens 2.0（全部审美的地基，先做）**

| # | 任务 | 说明 | 落点 |
|---|---|---|---|
| M3-1 | 表面三级接调色板：`surfaceCard()=applicationPalette().color(DPalette::ItemBackground)`、`surfaceAlt()=QPalette::Window`、`surfaceBorder()=DPalette::FrameBorder`、`textPrimary()=QPalette::Text`、`textSecondary()=DPalette::TextTips`；删除 `main.cpp:164-192` 15 行手工 palette，改为 `app.setPalette(DGuiApplicationHelper::instance()->applicationPalette())` + 仅补 `Mid/Midlight` 缺失角色 | 消掉"同一批色值写两遍"的漂移面 | `DesignTokens.cpp:67-92`、`main.cpp:161-192` |
| M3-2 | accent 接系统强调色 `DPalette::LightLively`（用户改 LightLively 时应用跟随）；语义色不跟随系统（绿/紫/青/橙/红/黄承载跨页状态语义，属 mac 对位契约） | 与决策 D-2 一致 | `DesignTokens.cpp:41-43` |
| M3-3 | 字号接 `DGuiApplicationHelper::instance()->fontManager()`：映射 `metric=T5`、`body=T6`、`sectionTitle=T6`、`cardTitle=T7`、`label=T8`、`badge=T9`；`MD_H1/H2/H3` 改基于 `SizeType::T7` 派生比例；消掉 `Chip.h:42`、`DualTrackButtons.cpp:36`、`MarkdownView.h:45` 三处 QSS 内联 `font-size` | 系统字号档位生效的前提 | `DesignTokens.cpp:94-120` 及上述三处 |
| M3-4 | **全局响应系统变化**：接 `themeTypeChanged/paletteTypeChanged/fontChanged` → ① 重设 app palette；② 顶层窗口 `update()` + `ensurePolished()`；③ 对依赖 `setStyleSheet` 的树走统一 `DS::repolish(QWidget*)`。长效方案：凡"靠 QSS 注入颜色"的子类改为 `paintEvent` 读 `DS::*`（`ui/common/Card.h:36-38` 已是正确范式），QSS 只留几何与状态 | 修掉"运行中切主题大面积不刷新" | `main.cpp:246-251` + 全树 |
| M3-5 | 几何/metric 收口：新增 `DS::Height{bar=6,barMini=4,dot=8,dotLg=10}`、`DS::Radius{pill=8,window=DStyle::PM_TopLevelWindowRadius,frame=DStyle::PM_FrameRadius}`、控件最小高度 `DStyle::PM_ButtonMinimizedSize`；按钮 padding 收成一档 `4px 16px`；进度条统一 6px；圆点统一 8px；`PanelWindow.cpp:104` 的 4px 圆角归入 token | 修掉"同类控件几种尺寸" | 全仓 |
| M3-6 | `Card` 增加 `static constexpr QMargins kPadding{Spacing::lg,Spacing::md,Spacing::lg,Spacing::md}`，构造即设置；6 处复制（`ProjectDetailPage.cpp:402,517,554,668,730`）与 4 处（`DashboardPage.cpp:166,278,315,368`）回收；`SidebarNav.cpp:34-35 ≡ 231-232` 复制回收为 `rowMargins/rowSpacing` | 间距真正的单点 | `ui/common/Card.h:13-18` |
| M3-7 | 阈值/几何 token：`logic/Thresholds.h`（未提交 10、停滞分桶 10）；`TrayGeometry`（380/12/44/4/120，`TrayPopupWindow.cpp:11-12,184-224`）；托盘几何常量从 `TrayController.cpp:14-29` 回收 | 消除 magic number | 新头文件 |

**3b 组件化（把"同一件事 N 种写法"收敛）**

| 新组件 | 替换对象 |
|---|---|
| `ui/common/SecondaryLabel` | 28 处 `setStyleSheet("color: %1;").arg(DS::textSecondary().name())` 复制（`ProjectProgressCard.cpp:108/114/121/131/175`、`DashboardPage.cpp:81/108/181/233/250/287/337/391/395`、`MilestonesPage.cpp:63/130/224`、`MilestoneRowWidget.cpp:96/117/123/156`、`GeneralPane.cpp:28`、`AutomationPane.cpp:58/67`、`AiSettingsPane.cpp:50/55/70/101`） |
| `ui/common/FlatButton` | 30+ 处 `new QPushButton`（对位 `ProjectDetailPage.cpp:38 headerButton` 助手） |
| `ui/common/BusyRow`（spinner + 文案，尊重 `DGuiApplicationHelper::testAttribute(HasAnimations)`） | `DualTrackButtons.cpp:75`、`DashboardFilterBar.cpp:101`、`TrayPopupWindow.cpp:157/193`、`PanelWindow.cpp:487` 五种 busy 表达；标题栏刷新按钮 busy 时转圈 |
| `ui/common/EmptyState` 统一 + `iconTone` + 主 CTA 槽位 | `DashboardPage.cpp:248-250,286,329,336` 等内联空态半数无图标；"空"与"读不出来"在图标上区分；给出下一步按钮 |
| `ui/common/SegmentedButton` | `DashboardFilterBar.cpp:10-22` 与 `AutomationPane.cpp:15-22` 两份 `segSheet` |
| KPI 骨架屏（`Card(Level::inset)` 中性占位块） | 首屏"空白→全量内容"跳动 |

**3c 一致性与响应式**

- 清第二套色板：`Derived.cpp:254-300`、`TrayController.cpp:36-54`、`TrayPopupWindow.cpp:189/201/207/218`、`SegmentedBar.h:41`、`IconLoader.cpp:21/64/92` 全部走 `DS::*`（`logic/` 层不再持有颜色）。
- 修两种红：`#EF4444` → `DS::SemColor::red`，色值唯一。
- 修两种蓝：`#1E6FEB` 归并 accent 或登记为 token，禁止第三处。
- 图标名规范：`WorkBar.cpp:26 "globe"`（非 freedesktop 名，静默返回空）→ `applications-internet`；`SidebarNav.cpp:113-116 "preferences-desktop-wallpaper"`（壁纸图标表达仪表盘，语义错配）→ `view-grid-symbolic`；尺寸走 `DStyle`/hicolor（空态 48、工具钮 24、菜单 16）；`TrayController::tintedIcon()`（`:12-34`）删除并转发 `IconLoader::symbol()`。
- 动效：页面切换 200ms 淡入（`DS::MotionStandardMs`）、卡片 hover/按下/焦点环（`paintEvent` + `SS_HoverState/SS_PressFlag`）；`testAttribute(HasAnimations)` 为假时全静默。
- 响应式：KPI 网格按窗宽 1/2/4 列（`resizeEvent` 改写 `QGridLayout` 列数）；`AgentDialog.cpp:49 setFixedSize` 改 `resize+setMinimumSize`（`AiResultDialog.cpp:14-15` 已写下这条教训）；`ProjectProgressCard.cpp:59`、`SidebarNav.cpp:42/236`、`DashboardPage.cpp:396`、`TrayPopupWindow.cpp:184` 定宽截断改 `elidedText` + 字号自适应。
- 字符分隔线（`ProjectDetailPage.cpp:271-281` 两个 `QLabel("\|")`）改 `QFrame::VLine`。
- **HiDPI**：新增 `platform::dpiPixmap(logical, dpr)`（`setDevicePixelRatio` + 按 dpr 放大绘制），替换 `IconLoader.cpp:28-32/60-69/88-96`、`TrayController.cpp:14-33`、`TrayPopupWindow.cpp:174-181/213-224`、`SidebarNav.cpp:292-299`、`ProjectProgressCard.cpp:72-79`、`ProjectDetailPage.cpp:576-583`、`MilestoneRowWidget.cpp:15-38`、`DashboardPage.cpp:379-382`、`LegendRow.h:36-39` 九处 1x 自绘；托盘图标改 SVG/多尺寸 `QIcon::addFile`。
- 托盘：五态补 busy 帧；`DBlurEffectWidget`（M1a）后弹窗观感与 DDE 一致。

### M4. 工程支撑（长期可维护，约 5–8 天）

- 拆分 `AppModel.cpp`（1081 行 → 数据编排 / 更新编排 / 通知规则 / tray 派生）与 `ProjectDetailPage.cpp`（858 行 → `BranchRow`/`MilestoneProgressCard`/`JournalCard`/`DocsBlock`）。
- `scripts/ci.sh`：① `--selfcheck` 例数不回退；② `--snapshot` 截图矩阵（亮/暗 × 4 页 × 2 字号）与 `deepin/docs/snapshots/` 基线 diff；③ `desktop-file-validate`；④ `appstream-util validate-relax --nonet`；⑤ `--platform-probe`；⑥ deb 构建；⑦ 系统 Qt6/DTK6 无 sysroot 矩阵（M0-8）。
- 崩溃可观测：SIGSEGV/SIGABRT 最小 handler（backtrace 后重新 raise）+ dtk6log journal appender（M0-9）。

---

## 4. 验证方案（不是"应该没问题"，全是要跑的东西）

### 4.1 视觉/交互回归（无头，CI 门）
```sh
cd deepin
for theme in light dark; do for sec in dashboard board milestones; do
  DEEPDOLPHIN_THEME=$theme ./build/deepDolphin --snapshot docs/snapshots/${theme}-${sec}.png --section $sec
done; done
./build/deepDolphin --snapshot docs/snapshots/project.png --project <名>
```
基线入库、CI diff。**M3 的每个任务必须至少新增/更新一张基线图**（否则视为未验证）。

### 4.2 真机验证清单（deepin 25，X11 + Wayland 两个会话）

| 区域 | 检查点 |
|---|---|
| 桌面身份 | 启动器中文搜「进度/项目/git」能否列出；点通知能否回面板；任务栏/窗口按图标分组；右键图标有快捷动作；软件中心/「关于」显示 appdata 摘要 |
| 主题 | 会话中切换亮暗 3 次（每个页面各切 1 次）无残留旧色；改系统强调色 → accent 跟随；改字号档位 → 全应用字号变化且无裁切 |
| HiDPI | 100/125/150/200% 下截图比对（模糊、截断、伪影） |
| 托盘 | 图标五态 + busy 态可见；右键菜单；点图标出速览弹窗且贴托盘；弹窗外点击收起；**Wayland 下同样成立** |
| 通知 | 更新完成/定时简报/失败三类可达，通知中心可点回，同类失败不堆积 |
| 自启 | 勾选后注销重登确有一例（未安装的 dev 树勾选应被拒）；`OnlyShowIn=Deepin` 不污染其他桌面 |
| AI | 系统级 AI 缺席/在场两条路径文案诚实；显式渠道 + Anthropic 双协议；key 只进 libsecret |
| 引擎 | 无引擎 → 装引擎 → 重新检测（M0-1）；引擎探活不冻结 |
| 打包 | `dpkg -i` 后启动、`ldd \| grep "not found"` = 0、卸载后不残留自启 |

### 4.3 headless 夹具新增
- `--platform-probe`：backend / tray geometry 有效性 / 当前主题 / 字号档位 → 真机回归可断言。
- `--selfcheck` 新增 fixtures：`Route` 的 desktop Actions 参数、`Thresholds`、`SegmentedButton` 样式（不再有未填 `%1`）、图标 fallback 链。

---

## 5. 决策草案（延续仓内"决策 + 代价"文化；完成后写进 README，编号从 28 起）

| # | 决策 | 为什么 | 已知代价 |
|---|---|---|---|
| D-1 | DTK 原生控件优先，own-QSS 只在 `loadDXcbPlugin()==false`（dev 容器）启用 | 真机永远有插件；否则观感永远停在"容器水平" | 双路径观感差异需在两种环境各自测 |
| D-2 | 语义色保留 mac 取值（不跟系统强调色），表面/文字/accent 接 `DPalette` | 状态语义是跨页契约；皮肤应跟系统 | 用户改强调色时只有 accent 变，属预期 |
| D-3 | `DS::*` 之外的任何色值/px 值出现即视为缺陷（CI grep 门） | 单点真相源 | 个别特例需显式加白名单注释 |
| D-4 | Markdown/气泡等富文本用 `DS::font()` 派生比例而非绝对 px | 字号档位要生效 | 富文本排版需重调 |
| D-5 | 托盘用 SNI（DDE 标准） | deepin 任务栏按 SNI 管托盘 | KF6 依赖或需自建最小 SNI 服务（若 DTK6 未提供） |
| D-6 | 弹出类窗口（速览弹窗、失败条）用 `DBlurEffectWidget` / `DFloatingMessage` | DDE 观感（圆角 + 模糊） | Wayland 下需 `Qt::Popup` 变体 |
| D-7 | 配置分层：装机模式走 DConfig（`org.deepin.deepdolphin` + `/usr/share/dsg/configs/<AppID>/meta.json`），开发树回退 QSettings；`ai.apiKey` **不进 dconfig** | DDE 配置体系 + 开发树免安装 | 键名迁移（`update.autoHours`→`update.auto-hours`）需兼容读一次旧键 |
| D-8 | i18n 只做 zh_CN/en_US 两套 | 语种越多越没有维护方 | 其他语种暂缺（desktop 翻译字段同样只这两套） |
| D-9 | agent 内引擎子进程纳入可 kill；不可 kill 时 UI 明确说"当前工具会跑完" | 用户点停止仍在改仓库 = 违约 | 与 mac 相同的已知限制需在 README 记一笔 |
| D-10 | 截图基线入库 + CI diff | 视觉回归没有"截图门"就等于没有回归 | 基线更新需人工确认（避免把 bug 固化成基线） |

---

## 6. 明确不做（防止范围膨胀）

- 不改引擎（moongit）契约、不加客户端侧 AI 之外的业务能力、不新增平台。
- 不做 `linux/`（仓颉+CangjieGUI）版本；`macos/windows` 只在必要处同步文档。
- 不引入 Web 技术（QML/QWebEngine）——DTK Widgets 是既定路线。
- 不做 per-user 自定义主题编辑器；不自己做 AI 补全（UOS AI 无出口时只能唤起 + 诚实降级）。
- 不追求 100% 消灭自绘控件：状态点、进度段、迷你条属于 DDE 内建也自绘的先例，保留但收口到 `ui/common/` 统一实现。

---

## 7. 优先级与裁剪（额度不足时按这个砍）

| 波次 | 内容 | 价值 |
|---|---|---|
| **第 1 波（必做）** | M0 全部 + M1a 控件替换（含 `DPasswordEdit`、`DIconButton`、`DSuggestButton`、`DListView/DTreeView/DProgressBar`）+ M2-1/M2-2（`setDesktopFileName`、desktop 字段） | 真机能用、DTK 原生、桌面身份完整 |
| **第 2 波** | M3-1/3-2/3-3/3-4/3-5（tokens 2.0 + 全局响应）+ M3b 组件化 + M3c 一致性/HiDPI + M2-6 图标集 | 观感与一致性质变，D2/D3/D4 达标 |
| **第 3 波** | M1b 生态 API 统一（DConfig 分层、`DStandardPaths`、通知 hint、自启模板、UOS AI 异步）+ M1c Wayland/SNI + M2-3/2-4/2-5/2-7 + M4 | 真正"融进 DDE"并可分发 |

**极限最小可交付**（只剩半天额度）：`M0-1`（真机 P0）→ `M0-2`（不冻结）→ `M3-1~M3-3`（tokens 接调色板/强调色/字号）→ `AiSettingsPane.cpp:80` 改 `DPasswordEdit` → `M2-1 setDesktopFileName` → `M2-2 desktop 字段`。这 6 项 = 真机可用 + 一眼原生感，其他都可以等。

---

## 8. 常见坑（接手前必读，都是本仓踩过的）

1. **`<libsecret/secret.h>` 必须先于任何 Qt 头**：glib 的 `GDBusInterfaceInfo.signals` 会被 Qt 的 `signals` 宏改名，炸出 `expected unqualified-id before 'public'`（README 决策 13）。
2. **不要叫 `LINE_MAX`**：glibc `limits.h` 已有同名宏，展开后炸 QColor 链 → 改名 `PULSE_LINE_MAX`（README 决策 15）。
3. **QSS 占位符不要跨函数 `.arg`**：`AutomationPane.cpp:15-22` 仍有这个 bug 模式，运行时刷 `QString::arg: Argument missing` 告警（README 决策与 `DashboardFilterBar.cpp:10-22` 注释记录过同类）。
4. **本容器没有 `libqt6svg6-dev`/`libdxcb.so`/`libchameleon.so`**：`DD_HAVE_QTSVG` 分支从未编译过；**容器观感 ≠ 真机 DDE 观感**，不得拿容器表现当验收结论。用 `DApplication::loadDXcbPlugin()` 返回值做双路径。
5. **`CMAKE_RUNTIME_OUTPUT_DIRECTORY` 钉死 build 根**：`scripts/smoke.sh` 按硬路径断言，改它先改脚本。
6. **单实例 id = `cn.deepdolphin.app`**：新增 DBus 服务名要另起（`cn.deepdolphin.app.Runtime`），否则与 `DApplication` 单实例相撞。
7. **offscreen 下 `QSystemTrayIcon::geometry()` 无效**，托盘弹窗定位相关测试只能在真机/`--platform-probe` 判。
8. **批量更新链用 `QTimer::singleShot(0)` 延后销毁 `shared`/`report`**（`AppModel.cpp:706-720`，修过必现段错误）——重构时不要"顺手简化"掉。
9. **`QSettings` 组织名 `deepin` / 应用名 `deepDolphin`**：迁 DConfig 时先读一次旧键再写新键，否则老用户丢配置。
10. **每次 `delete layout()` 重建的树**，颜色依赖 `setStyleSheet` 的都是"拍快照"，改主题时必须重算（M3-4 的根因）。

---

## 9. 执行进度看板（接手入口）

> 规则：任务 ID 唯一；`□` 未做 / `▶` 进行中 / `☑` 已完成并验证。接手的智能体：找到第一个 `□`，做完改 `☑`，在 §10 写一行日志，然后 commit（消息含任务 ID，如 `deepin(M3-4): 全局响应主题/字号变化`）。
> 「验证」列的命令必须**实际跑过**并把结果贴进 §10，未跑的不许打 `☑`。

### M0 真机可用性
- [ ] M0-1 重新检测引擎回灌 `setEngineBin`｜验证：桩引擎下重探测真出数据
- [ ] M0-2 `EngineLocator` 异步化 + 忙态｜验证：无引擎启动 <1s 可见面板，点击不冻结
- [ ] M0-3 `AiSettingsDialog` libsecret 读异步化｜验证：密钥环卡住不冻结
- [~] M0-4 `Settings` 不跨线程读写｜部分：libsecret 读已移出 GUI 线程（M0-3）；worker 侧配置快照未做
- [ ] M0-5 agent 引擎子进程可 kill + 文案诚实｜未做
- [ ] M0-6 批量闸门专用信号｜未做
- [ ] M0-7 CLI 健壮性（mock 强制 / 快照等数据 / 版本单源）｜验证：`--version` 与 CMake 一致
- [x] M0-8 系统 Qt6/DTK6 构建矩阵脚本 `scripts/build-system.sh`｜脚本已写；干净容器未实跑（本机只有 sysroot 工具链）
- [ ] M0-9 关键路径日志 + journal appender + 「打开日志目录」｜验证：日志文件有内容

### M1 DTK 原生化
- [~] M1a 控件替换表：**AI 设置页一行已完成**（DPasswordEdit + DLineEdit×3 + DComboBox×2 + DPushButton），其余未做
- [ ] M1-1 `QStandardPaths` → `DStandardPaths`
- [ ] M1-2 统一 `platform::icon()`（fallback 链 + 缺失告警 + DDciIcon 优先）
- [ ] M1-3 托盘迁移 SNI（`KStatusNotifierItem` 或最小 SNI 服务）
- [~] M1-4 通知 hint（desktop-entry/image-path）+ 分类 replaceId（失败/停滞同类别互相顶替，用户关闭后清归属）｜已做；`timeOut` 可配置未做
- [x] M1-5 自启模板补 OnlyShowIn=Deepin/X-GNOME-Autostart-*/X-Deepin-Autostart + Exec 策略（已安装用安装名、开发树拒绝自启并说明）
- [ ] M1-6 UOS AI `asyncCall` + `probe()` 加锁 + 接口 dump 进日志
- [ ] M1-7 `platform/Backend` 平台层
- [ ] M1-8 Wayland 分支（弹窗定位 / `requestActivate` / 失焦收起）
- [ ] M1-9 `--platform-probe` 夹具

### M2 DDE 生态
- [x] M2-1 `setDesktopFileName`（另有 M2-2/M2-3/M2-4 完成）
- [x] M2-2 desktop 字段补全 + `--scan`/`%f` 位置参数路由（selfcheck +3 例）+ `desktop-file-validate`（仅 1 条 Categories hint）
- [x] M2-3 DBus 服务（AppService: Ping/Activate/OpenProject/OpenPath）+ `DBusActivatable=true` + `.service` 安装｜真总线 `qdbus … Ping` 返回 ok
- [x] M2-4 appdata/metainfo（data/metainfo/cn.deepdolphin.app.metainfo.xml + CMake 安装）｜`appstream-util` 本机没有，硬门待 CI 环境
- [ ] M2-5 i18n（ts/qm/装载/安装）
- [ ] M2-6 图标集（hicolor 多尺寸 + symbolic + `dd-*.svg`）
- [ ] M2-7 deb 打包 + `scripts/build-deb.sh`
- [ ] M2-8 安装后零环境变量（`ldd` 断言）

### M3 审美
- [x] M3-1 表面三级接运行期调色板（Window/Base/Text/Mid + DPalette::PlaceholderText）+ 自洽判定与 `applicationPaletteFallback()`
- [x] M3-2 accent 接 `LightLively`（与 DTK 推荐按钮同色；不自洽时退回规范蓝）
- [~] M3-3 字号接 `DFontManager` 档位（T3–T8）+ MD_H* 改档位派生 + `DS::tagFont` 机制；老代码字号未全量登记
- [x] M3-4 全局响应 theme/font/强调色变化（4 信号 → 兜底 palette + `DS::repolish` 全树重算；28 处次级文字色已收编）
- [ ] M3-5 几何/metric 收口（Height/Radius/DStyle metric/按钮 padding）
- [ ] M3-6 `Card::kPadding` + 重复边距回收
- [ ] M3-7 `Thresholds`/`TrayGeometry` token
- [ ] M3b `SecondaryLabel`/`FlatButton`/`BusyRow`/`EmptyState`/`SegmentedButton`/KPI 骨架屏
- [ ] M3c 清第二套色板、两种红/两种蓝、图标名、动效、响应式、HiDPI、分隔线、托盘 busy 态

### M4 工程
- [~] M4a 拆分大文件｜顺手修掉一个 P0 段错误（M0-2 的 locateAsync 回调捕获 this → use-after-free，见 README 决策 65）；拆分未做
- [ ] M4b `scripts/ci.sh`（selfcheck + 截图矩阵 + validate + probe + deb + 系统矩阵）
- [~] M4c 崩溃 handler + journal appender｜journal appender 已注册（M0-9）；SIGSEGV handler 未做；本轮用 `DD_BISECT` 二分 + core dump 定位并修掉一个必现段错误（README 决策 65，二分脚手架已从 main 移除）

---

## 10. 执行日志（追加，勿改写）

> 格式：`日期 | 智能体 | 任务ID | 结果/命令输出摘要 | 遗留`

- `2026-10-03 | orchestrator | M0-1 | AppModel::setEngineResult 回灌 EngineCli::setEngineBin；新增 engineFoundChanged 并接入 PanelWindow::refreshChrome；engineMissing 按 engineBin().isEmpty() 分流「从未发现」与「运行中丢失」| build 通过、selfcheck 全绿、offscreen 快照正常`
- `2026-10-03 | orchestrator | M0-2 | EngineLocator::locateAsync（QThreadPool worker + QueuedConnection 回 GUI 线程）；Result 增 pending；AppModel::enginePending；SetupGuidePage::setBusy（DSpinner）；main 先 panel.show() 再异步探活、引擎找到才 model.start()；PanelWindow::setEngineResult 统一入口（启动/重探测共用）；refreshChrome 状态条加「正在检测引擎…」| 无引擎快照走 setup guide 终态；有引擎（桩）快照秒级出图`
- `2026-10-03 | orchestrator | M0-3 | AiSettingsDialog 构造只读身份，key 由 worker 读 libsecret 后回填；新增 m_keyPending，回填前禁用「保存」| 真机密钥环卡住场景待验`
- `2026-10-03 | orchestrator | M0-7 | --agent-selftest 恒强制 providerID=mock（不再打真 HTTP）；--snapshot 改轮询稳定态（数据落地/轮次收尾/未找到/pending，上限 15s 超时失败退出）+ 缺参 exit 2；--version 与 setApplicationVersion 改由 CMake configure_file(src/app/Version.h.in → build/app/Version.h) 单源 | --version=0.1.0 一致；缺参 exit=2；agent-selftest exit=0 走 mock`
- `2026-10-03 | orchestrator | M0-9 | registerJournalAppender；EngineCli::callJson 收尾打 dInfo/dWarning（命令名+退出码+耗时，不含参数/stdout）；SecretStore 失败打日志（不含 key）；AIChannel 失败打 host/status/脱敏；GeneralPane「日志」卡 + 打开日志目录（路径不可用时禁用）`
- `2026-10-04 | orchestrator | M1-4/M1-5/M2-4 | Notifier: hints 补 desktop-entry=cn.deepdolphin.app 与 image-path=deepdolphin，新增按类别的 replaceId（失败/停滞同类别顶替、关闭后清归属，QMap<QString,uint>）；AutostartManager: 自启模板补 OnlyShowIn=Deepin/X-GNOME-Autostart-enabled/phase=Desktop/X-Deepin-Autostart，Exec 策略改为已安装用安装名（不含绝对路径），并新增运行时 isDevTreeBuild()（路径含 /build/ 即开发树 → 拒绝自启并给出"请先安装"）；新增 appstream metainfo 并进 CMake install | build 通过、selfcheck 58/58、GUI 启动 10s 不崩 |
- `2026-10-03 | orchestrator | M2-3 | src/platform/AppService（Q_CLASSINFO D-Bus 接口，session bus 注册 cn.deepdolphin.app + /cn/deepdolphin/app，Ping/Activate/OpenProject/OpenPath）+ data/cn.deepdolphin.app.service + desktop DBusActivatable=true + main 接线（叫醒/直达项目/开目录）。**过程中发现并修掉一个 P0 段错误**：M0-2 的 LocateTask 把 this 捕获进 invokeMethod，QRunnable 自动删除 → use-after-free，GUI 启动路径进事件循环即崩（--snapshot 路径不复现）；改为 worker 内 swap 回调 + 值捕获投递（README 决策 65，DD_BISECT 二分定位）。修后 GUI 路径存活 10s+、qdbus Ping=ok |
- `2026-10-03 | orchestrator | 截图基线 | docs/snapshots/{light,dark}-{dashboard,board,milestones,setupguide}.png 8 张（本机 DDE 主题为深色；未强制 DEEPDOLPHIN_THEME 时跟随系统，证明接的是运行期调色板）。项目详情页基线缺：引擎注册表里没有项目（deepgit list 无输出），待真机有数据时补拍 |
- `2026-10-03 | orchestrator | M2-1/M2-2 | setDesktopFileName("cn.deepdolphin.app")；desktop 项补 Version/GenericName/Keywords[zh_CN]/SingleMainWindow/MimeType=inode/directory;/Actions(open,scan)；Route 增 --scan 与 %f 位置参数（目录→ScanDialog::presetPath）；selfcheck +3 例（55→58）；desktop-file-validate 仅 Categories hint；DBusActivatable 暂不开（无 .service）`
- `2026-10-03 | orchestrator | M1a(AI 设置页一行) | QLineEdit×4→DLineEdit、key→DPasswordEdit、QComboBox×2→DComboBox、测试连接→DPushButton（DLineEdit 非 QLineEdit 子类，clearButton/text/textChanged 全改其 API）`
- `2026-10-03 | orchestrator | M3-1/M3-2 | DS:: 表面/文字三级改读运行期调色板（Window/Base/Text/Mid + DPalette::PlaceholderText），accent 改读 DPalette::LightLively；新增 paletteIsThemeConsistent()/applicationPaletteFallback()（offscreen 探针实证 applicationPalette(DarkType) 仍返回浅色值 → 自洽失败即退回 deepin 规范值）；main 与 --snapshot 只在自洽失败时 setPalette | 四个主题×页面截图字节互不相同、dark 底 #252525`
- `2026-10-03 | orchestrator | M3-3 | DS::font() 改走 fontManager() 档位（metric=T4/sectionTitle=T5/cardTitle=T6/body·label=T7/badge=T8）；MD_H* 改 T3/T4/T5 派生`
- `2026-10-03 | orchestrator | M3-4 | 新增 DS::tagSecondaryStyle/tagFont + DS::repolish()；main 接 paletteTypeChanged/themeTypeChanged/applicationPaletteChanged/fontChanged → 兜底 palette + 全树重算；28 处 color:%1 收编`
- `2026-10-03 | orchestrator | M0-8/M-61 | scripts/build-system.sh + scripts/ci.sh + docs/snapshots 基线 7 张（light/dark × 3 页 + dark-setupguide）`
- （示例，可删）`2026-xx-xx | <agent> | M3-1 | 表面三级接 applicationPalette；--selfcheck 55/55 通过；截图基线 docs/snapshots/dark-dashboard.png 已更新 | AgentDialog 固定尺寸待 M3c 处理`

---

## 11. 环境与构建速查

```sh
# 开发容器（README「构建与运行」）：
cd ~/code/deepDolphin/deepin
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel 4
./build/deepDolphin --selfcheck          # 模型层 55 例（改契约/logic 必跑）
scripts/smoke.sh                         # 配置+构建+selfcheck；引擎在位时追加 contract-check

# 离屏运行/截图（sysroot 运行库）：
export LD_LIBRARY_PATH=~/.local/dd-sysroot/usr/lib/x86_64-linux-gnu
export QT_PLUGIN_PATH=~/.local/dd-sysroot/usr/lib/x86_64-linux-gnu/qt6/plugins
export QT_QPA_PLATFORM=offscreen
DEEPDOLPHIN_THEME=dark ./build/deepDolphin --snapshot /tmp/dark-dashboard.png --section dashboard

# 其他headless 夹具：
./build/deepDolphin --version
DEEPGIT_BIN=<桩引擎> ./build/deepDolphin --agent-selftest     # 必须走 mock 渠道（M0-7 后）
./build/deepDolphin --platform-probe                         # M1-9 后可用
```

引擎安装路径/自启/托盘真机验证：见 `deepin/README.md`「引擎安装前提」「系统级 AI」等章节。
引擎 CLI 契约唯一来源：`deepin/scripts/contract-check.sh` + 引擎仓库 `~/code/moongit`。

---

## 12. 交接须知与不变量

### 12.1 不变量（违反任何一条都算返工）
- `--selfcheck` 例数**不减**（只增）；`logic/`、`models/` 保持零 QWidget 依赖。
- 引擎 JSON 契约键名不变；能力矩阵 C1–C11 不减少；mac 1:1 语义不变。
- key 只进 libsecret；`ai.apiKey` 明文回退仅限 mock/无头自测；**不进 dconfig、不进日志**。
- 客户端零业务文件写入（C11）：除 `AutostartManager.cpp:83` 的自启 `.desktop` 外不得新增任何写项目文件路径。
- 一切降级必须"诚实"：AI/引擎失败必须给原因与下一步，不许静默、不许假装成功。

### 12.2 单点真相源（D2 的 CI grep 门）
```sh
# 只允许 DesignTokens.cpp / platform/* / logic/CommitTypeComposition.cpp 命中
grep -rnE "#[0-9A-Fa-f]{6}|setPixelSize|font-size: *[0-9]+px" deepin/src | grep -vE "DesignTokens|CommitTypeComposition|src/platform/"
```
新增命中 = 未完成，打回。

### 12.3 文档同步（R7）
每完成一个任务：在 `deepin/README.md`「取舍与已知边界」追加「决策 N（28 起）」：**为什么这么定 + 已知代价**；若涉及 CLI 或快捷键，同步「快捷键映射表」与「C1–C11 逐项实现位置」两表。

### 12.4 提交纪律
一个任务一次 commit；消息格式 `deepin(<任务ID>): <做了什么>`；`--selfcheck` 与截图矩阵（若有视觉改动）必须同 commit 内通过。

### 12.5 背景阅读索引（想深挖时再看）
- `PLATFORM-CHARTER.md`（能力基准）、`deepin/README.md`（决策 1–27 + 引擎安装 + 构建）
- 引擎契约：`deepin/scripts/contract-check.sh`、引擎仓库 `~/code/moongit` 的 `flow/*.cj`
- mac 基准：`macos/README.md`、`macos/` 源码（视觉/语义对位）
- DTK6 头文件与 API：`~/.local/dd-sysroot/usr/include/dtk6/{DGui,DWidget,DCore}`

---

## 13. 交付物清单
- `deepin/docs/DDE-INTEGRATION-PLAN.md`（本文档，随进度更新看板与日志）
- `deepin/src/ui/DesignTokens.{h,cpp}` 2.0 + `src/platform/Backend.{h,cpp}` + `src/logic/Thresholds.h` + `src/ui/common/*` 新组件
- `deepin/data/cn.deepdolphin.app.desktop`（含 Actions）、`data/cn.deepdolphin.app.service`、`metainfo/cn.deepdolphin.app.appdata.xml`、`data/icons/hicolor/*`、`translations/*.qm`
- `deepin/debian/` + `scripts/build-deb.sh` + `scripts/ci.sh` + `scripts/build-system.sh`
- `deepin/docs/snapshots/` 视觉基线 + 真机验证报告（附截图与结论）
