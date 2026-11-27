# Canopy — Compose Multiplatform 客户端

> Cambium 引擎的桌面客户端（Kotlin + Compose Multiplatform，桌面 JVM），承接 `archive/bui`
> （Rust 版 BUI 客户端）的能力口径，交互基准对位 [macos/](../macos/README.md)。
> 能力面按 [PLATFORM-CHARTER.md](../PLATFORM-CHARTER.md) C1–C11 对齐——能力必须一致、交互 UI 自由。
> 引擎访问唯一通路：`cambium <命令> --json` CLI 子进程，**没有 HTTP、没有 FFI**。
> 分批执行手册（计划/红线/判据纪律）见 [PLAN.md](PLAN.md)。

## 状态（2026-11-26）

- 判据门禁绿：`scripts/build.sh --test` → **282 判据 0 failed**（1 skipped = 只手动触发的皮肤对比度体检；禁用缓存复跑
  `gradle jvmTest --rerun-tasks --no-build-cache` 同数）。门禁脚本读的是 test-results XML，
  增量构建下会读到陈旧结果——当证据用的数字必须来自禁用缓存的那次。
- 本机引擎是 **Cambium**（0.3.0 的开发构建，取自引擎仓库 `feat/sylva-brand`）：启动器 `~/.local/bin/cambium`，
  真实二进制 `~/.local/libexec/cambium/cambium.bin`；`~/.local/bin/moongit`、`~/.local/bin/deepgit` 是指向
  `cambium` 的兼容软链（已装进用户仓库的 git 钩子里写的是旧命令名）。
  回滚：改名前的最后一版（嵌入尺寸融合）备份为 `~/.local/libexec/cambium/cambium.bin.bak-20261126-pre-brand`，
  更早的备份仍在旧布局 `~/.local/libexec/deepdolphin/moongit.bin.bak-*`（pre-fit / pre-embed / pre030）。
  回滚 = 把对应备份拷回 `cambium.bin`：启动器按绝对路径 exec，旧二进制照样能跑（它不认 `cambium` 这个
  裸命令名，但经启动器调用不受影响）。引擎尚未正式发版。
- **品牌升级（2026-11-26）**：整个项目 **Sylva**；客户端 **Canopy**（包名 `canopy`、deb `canopy_0.1.0_amd64.deb`、
  安装路径 `/opt/canopy`）；引擎 **Cambium**；置信度 **Dendro**（引擎内的独立包）。客户端这边：
  Kotlin 包 `canopy.*`、窗口标题 / 侧栏 / 托盘 / 菜单 / 通知身份、图标资产名 `canopy.*` 全部跟上；
  引擎调用改教新写法（`cambium dendro gen|check|patch|merge`，旧写法引擎仍认）；引擎发现
  `CAMBIUM_BIN` → `MOONGIT_BIN` / `DEEPGIT_BIN`（旧名兜底）→ 仓内构建 → PATH（`cambium` / `moongit` / `deepgit`）；
  嵌入声明改注入 `window.CAMBIUM_EMBED`（产物两个名字都读）。
  **已装机器的自动迁移**（`sysint/LegacyPaths.kt`，判据见 `LegacyPathsTest`）：`~/.config/deepDolphin →
  ~/.config/canopy`、`~/.cache/deepDolphin → ~/.cache/canopy`（WebView 原生包 400MB 在里面，不搬就得重下）——
  整目录改名、搬不动就继续用旧的；钥匙串的 key 先按新属性找、找不到按旧属性兜底；自启条目
  `deepdolphin.desktop` 在启动时换成指向当前客户端的 `canopy.desktop`（开发态入口不可用时不动）。
  ⚠️ 旧包 `deepdolphin` 不会自动卸载：装新包后请 `sudo apt remove deepdolphin`（或等价的包管理器操作）。
  （本机从没装过 deb——`dpkg` 里没有 `canopy` 也没有 `deepdolphin`；本机的客户端是免 root 的用户级安装，
  见「构建与运行 · 免 root 安装」。）
- 图谱两页的**嵌入尺寸融合**（2026-11-26）：产物按拿到的视口排布（引擎侧：架构图泳道折行、热力图按区域选列），
  外壳这边把回执挪进页头、底部不再压条、把控件高 / 圆角令牌递给产物、窗口最小 960×640。详见 PLAN.md。
  客户端退回没有尺寸令牌的写法也不坏——产物那边每个变量都有回退值。
- 界面外观：设置 · 通用 ·「外观」内置 **14 套皮肤**（namethatui.com/styles 全风格，flat design 除外）——
  玻璃拟态 / 液态玻璃 / 新拟态 / 黏土拟态 / 新粗野主义 / Y2K / Frutiger Aero / 拟物皮革 / 远古网页 /
  Aqua / Windows Aero / 极简主义等，即点即换、settings.conf 持久化（`app.skin`）。
  文字与表面的对比度在换肤时保底（`ui/Skin.kt`：文字级语义色、四层表面模型、光泽预算；静置面三级文字
  7 / 6 / 5）；主文字的极性看主题色——浅色主题纯黑、深色主题纯白，容器上的前景只有纯黑 / 纯白两种，`SkinTest` 逐套守卫；另有只手动触发的离屏体检——`CANOPY_SKIN_AUDIT=<目录> gradle jvmTest
  --rerun-tasks --tests '*SkinContrastAudit*'`（需要显示器；再加 `CANOPY_SKIN_AUDIT_HOVER=1`、
  `CANOPY_SKIN_AUDIT_PRESSED=1` 会把每个可点节点的悬停 / 按下态也量一遍）——按语义树量每段文字的实际像素
  对比度：14 套 0 冲突，悬停 / 按下与提示条也是 0 冲突。
  **仓库与本地目录不改名**（2026-11-27 定）：两个仓库都开着 GitHub Pages，改名后 Pages 地址不跳转；
  `~/.deepgit` 也不动（用户定）。
- 图谱两页依赖引擎产物的嵌入模式（0.3.0 开发构建）：引擎退回 0.2.x 时图谱照常出图，但是原样内嵌的样子。
- **真窗口实拍（2026-11-25，DISPLAY=:0，打包后的 deb 提取运行）**：截图与逐张说明见
  [`docs/ui-cmp/README.md`](../docs/ui-cmp/README.md)。此前入库的 48 张旧图已退役——其中
  至少 9 张截到的是 IDE 而不是本应用，还有「图谱页验证通过」的图其实是空白页。
- 图谱两页**首次真正显示**（2026-11-25 之前在本机从未渲染出内容，三层根因见 PLAN.md）。
- 引擎发现顺序与各端一致（EngineLocator.kt）：`CAMBIUM_BIN` → `DEEPGIT_BIN` →
  仓内构建 `../Cambium/target/release/bin/main` → PATH（`cambium`/`cambium`）。

## 构建与运行

```sh
cd client
scripts/build.sh            # 编译（gradle build）
scripts/build.sh --test     # 编译 + 全量判据（jvmTest），末行 CMPTEST_SUMMARY，failed≠0 即失败
scripts/build.sh --run      # 编译后真窗口启动（需 DISPLAY）
scripts/run.sh              # 同上（gradle run）

gradle packageDeb           # jpackage 打 deb（或 packageAppImage）
scripts/install-user.sh     # 免 root 装到用户目录（见下）；--uninstall 卸掉
```

依赖：JDK 21 + Gradle（本机装在 `~/.local/jdk`、`~/.local/gradle`，build.sh 自动定位）。
KCEF/JCEF 在 JDK17+ 完成反射初始化所需的两条 `--add-opens` 已进 jpackage `--java-options`
与本地 `run` 任务（build.gradle.kts）。**门禁证据必须禁用缓存**（见上）。

**免 root 安装**（`scripts/install-user.sh`，不需要 sudo）：系统级安装是 deb（`/opt/canopy`）；没有 root
或不想动系统的机器，用这个把打好的 deb 装进用户目录——应用镜像 `~/.local/opt/canopy`、启动器
`~/.local/bin/canopy`、应用菜单项 `~/.local/share/applications/canopy.desktop`（只对当前用户）。
配置、缓存、引擎发现与系统级安装完全一样；以后装了 deb，启动器自动改走 `/opt/canopy`；
`--uninstall` 只卸这三样，不碰配置和缓存。

`CAMBIUM_BIN` / `DEEPGIT_BIN` 指向别的引擎构建时注意：`~/.cache/canopy/kcef/` 下的原生包
按引擎无关的固定版本安装（见 ui/JcefBundle.kt），与引擎版本无关。

## 功能面（侧栏导航 + 搜索框 + 仓库行；路由七页 + 跟仓库走的图谱两页）

| 页 | 内容 |
|---|---|
| **仪表盘** | hero 双轨更新按钮（浅/深更新带范围「· 全部 / · 项目名」，待记录徽章 >0 才现，副行明示深更新动哪些托管文档）+「添加/扫描」开扫描单（路径三态判定 + 逐项目新增/已在册推导 + 三种「没扫完」分开说）；KPI 磁贴 / 语言分布 / 里程碑 / 活跃项目 + 筛选；Fluent 分层底 + hover reveal |
| **看板** | 按引擎 `branch.status` 原值分列（active/stale/idle/merged），不重算引擎已给的结论；采集失败单独「读不出」列；分支返回不全在页头披露「引擎返回 M/N」；列头计数与行数同源 |
| **里程碑** | 列表 + 新建（tag 自动达成/date/desc）+ 行内动作达成/重开/放弃/删除；删除/放弃必过确认框 |
| **代码置信度** | `graph confidence --json`：六维度总分 + 权重降序疑点清单（默认只给位置、≥8 红档、点击展开引擎证据 + 实码读不出如实说）+ 只看高权重（≥8）开关 + 复制 LLM 复核提示词（--llm 纯文本 → 剪贴板，stdout/stderr 分流防引擎杂音混入） |
| **补丁体检** | diff 多行粘贴 → Layer1 算法层（S1..S10 信号 chip，null=分母 0 降档披露）→ uncertain 三态人工裁决（确认/未解决/不确定）→ Layer3 合并终稿（复核计数 + 警示行） |
| **项目详情** | 单项目三源（`status <名>` / docs / journal，失败不短路、逐源披露）+ git 白名单六操作（commit 带类型前缀选择 + ok/output 结果反馈，失败信息留住）+ 浅/深更新；入口按钮「代码图谱/架构图」busy 生成→成功即进对应页面 |
| **设置** | 四 tab：**通用（语言选择器 + 自启动）**/ AI（渠道+key）/ **自动化**（定时更新：间隔档 0/1/3/6/12/24 小时 + 浅/深轨道，写 settings.conf `update.*` 独立节、改完立即生效）/ **关于（四文档子 tab：关于/帮助/开源感谢/更新日志，四语言内容对位 mac DocsPages）** |

**代码图谱（热力图）/ 架构图**是跟着仓库走的独立页面（`Route.GRAPH` / `Route.ARCH`，
入口在各仓库详情页，不弹窗——用户定稿 2026-11-25；mac 是独立最大化窗口，此处不追 mac）：
引擎 `render index --confidence` / `render arch` 的交互 HTML 产物经 JCEF WebView 直载
（客户端不原生绘制，这是全应用仅有的两处 WebView）；侧栏高亮所属仓库，页头「返回仓库」，
底部回执条给版本/复用判定；产物路径进程内缓存，再次进页先秒出旧图再后台核验（复用就不重载）。
渲染口径统一在 `AppModel.renderGraph`（详情页入口 / 深链 / 页内刷新共用：热力图先出置信度
快照，每仓库每会话首次强制重绘）。

- C2 周期轮询 5 分钟 + 手动刷新（AppModel.startPolling；refreshAll 逐源失败不短路）。
- 定时更新（自动化 tab）：AppModel 协程定时器，首轮延迟 10 分钟防启动即全量更新；与 mac
  差异如实：无守护进程，随应用存活、退出即停；系统通知/AI 简报未接。
- 侧栏搜索：项目名 + 分支名大小写不敏感子串过滤，空结果两态分开说（本来就没有 ≠ 没匹配上），
  匹配时给「匹配 N / M 个仓库」行；Ctrl+F 聚焦搜索框。
- 窗口级快捷键（ShortcutMap 单点声明，与 mac 全表一一对应、⌘→Ctrl）：视图 Ctrl+1/2/3/7/8、
  当前仓库 Ctrl+4、设置 Ctrl+,、刷新 Ctrl+R、浅更新 Ctrl+Shift+U、深更新 Ctrl+Shift+Alt+D、
  停止更新 Ctrl+.、查找 Ctrl+F。**在 AWT 层统一接管**（ShortcutMap.AppShortcuts）：焦点在主画布、
  输入框、弹出的菜单还是图谱页的 WebView 里都一致生效——原先挂在 Compose 焦点链上，
  刚启动什么都没点、或被点的控件随即消失时快捷键全哑。
- 写操作纪律：每次写都留一行结果（✓/✗ 带原因），引擎调用全在协程 IO。
- 深链启动参数（C10 已接线）：`--section dashboard|board|milestones|confidence|patchcheck|project|graph|arch|settings`、
  `--project <名称>`（section 与 project 一次落地）；非法 section 宽容落 dashboard，不崩。
- **多语言（L10n）**：四语言 zh-CN / en / zh-TW / ja，键值表从 mac `L10n.swift` 脚本搬运
  （`client/scripts/gen_l10n.py`，504 键照搬不改写）+ CMP 特有键以 zh 为源补齐四语言
  （`ui/L10nCmpKeys.kt`，`cmp.` 前缀）；全部视图文案走 `L10n.t(key)`（语言是 Compose 状态，
  设置-通用切语言即时全界面生效）；语言存 settings.conf `app.language` 独立节，未配置时跟随
  系统语言、认不出缺省 zh-CN。已知边界如实：AI 层错误/提示词不本地化（mac AIClient 同口径，
  中文为诊断语言）；托盘 AWT 菜单标签在启动时定格（换语言重启后生效）。

## AI 层（客户端 AI，引擎 AI 无关）

- **双协议引擎**（ai/Engines.kt）：OpenAI 兼容 + Anthropic 原生 `tool_calls`/`tool_use` 线格式；
  URL 只放行 `https://` 与 `http://127.0.0.1`/`http://localhost`（防投毒端点骗取 apiKey）；
  网络失败给中文原因与下一步。
- **key 纪律**：key 只进 libsecret（secret-tool 子进程，AiViews.kt SecretStore）；
  `~/.config/canopy/settings.conf` 只存 `ai.providerID/model/baseURL`，保存时只合并
  `ai.*` 键、不动其他行；key 不回填明文。libsecret 缺席时的 0600 兜底文件未实现。
- **agent 循环**（ai/AgentCore.kt）：引擎 `tools --json` 是工具清单唯一来源，必填参数只从
  「已发给模型的那份」定义取；≤4 轮；停止逐轮检查 + 工具执行中切片响应。
- **Markdown 渲染**：原生渲染（ui/Markdown.kt，mac MarkdownParser.swift 的块级文法对位：
  标题/段落/列表/引用/围栏代码/分隔线/表格 + 粗体/等宽/链接）。AI 回答、帮助与关于文档、
  托管文档正文都走它——**WebView 只用于代码图谱与架构图两页**（用户定稿）。
- **未落地**：models.dev 目录选择器（现固定四渠道 + 手填）、更新后 AI 摘要 / 简报通知。
  ~定时更新小时档~ 已落地（设置「自动化」tab，`update.*` 独立键节）。

## 系统集成（C10，Linux 通用 freedesktop 机制，无 DDE 专属）

- 深链 `--section`/`--project` 已接线（Main.kt → SysInt.parseDeepLink）。
- XDG autostart 写盘（Exec 绝对路径整参数转义）在 sysint/SysInt.kt，界面开关已接线
  （设置「通用」tab，仅打包安装态可开）；notify-send 封装（缺席如实降级）有判据覆盖，
  界面开关未接线。
- SystemTray 常驻速览：已实现（X11 简版——AWT SystemTray 圆点图标 + 摘要行/打开面板/退出，
  摘要随 status 流推送，`dirty=null` 是读不出 ≠ 0；isSupported false 静默降级。
  mac MenuBarExtra 的弹窗项目行/迷你进度条不做，头注释标注形态差异）。

## 分发

- jpackage：deb / AppImage（build.gradle.kts nativeDistributions；Linux 菜单项 + 快捷方式）。
- JCEF 原生包**不随包分发**（约 217 MB）：首次打开代码图谱/架构图时下载到
  `~/.cache/canopy/kcef/jbr-21.0.4+8-631.2/`，只此一次；界面按阶段如实显示（定位/下载 xx%/
  解压/安装/启动），连续 30s（解压安装阶段 180s）无进度才判停滞，后台装完自动切上。
  不可用时页面如实给原因 + 引擎产物路径（可手动打开）。
- **原生包钉死版本、从 JetBrains CDN 下载**（ui/JcefBundle.kt）：KCEF 的默认下载追
  JetBrainsRuntime 的「最新」release，而 Maven 上的 Java 绑定是定版的——实测 2026-11-23
  下到 Chromium 150 的 JBR 25，原生按名字找 `CefRequestContextSettings`，旧绑定里没有，
  加载真实 URL 必崩（ClassNotFoundException → SIGSEGV）。钉的是与绑定同源的
  `jbr_jcef-21.0.4-linux-x64-b631.2`（222 个公共 org.cef 类逐类比过成员签名，native 全同）；
  GitHub 上旧 release 的二进制已被清掉，所以走长期保留的 cache-redirector CDN。
  目前只钉了 linux-x64；其它平台退回 KCEF 默认下载（未验证）。
- 已知代价：这台机器走 IPv4 到 CloudFront 只有约 200 KB/s（IPv6 通时 12 MB/s），首跑下载
  十几分钟；原生包随 deb 内置可免掉这次下载，但包体 +217 MB——取舍待定。

## 代码结构（按磁盘）

```
src/jvmMain/kotlin/canopy/
  Main.kt                 入口：窗口 + 引擎探活 + 侧栏外壳（七路由 + 图谱两路由 + 搜索框）+ 深链接线
                          + 退出兜底（关闭钩子 4s 不退就 halt——CEF 钩子在浏览器异常时会一直等）
  engine/Engine.kt        引擎命令封装：读（status/dashboard/milestone list/docs/journal/tools/
                          graph confidence/patchconf）写（milestone、git 六操作、update/deep/
                          全部、scan/add/remove、render index/arch、patchconf merge）
  engine/EngineLocator.kt 引擎发现 + 探活（version）+ 子进程执行（超时强杀；runMerged/runSplit）
  engine/Models.kt        --json 契约模型（kotlinx.serialization；缺键=契约过旧的口径）
  engine/EngineStub.kt    判据用引擎桩（必填校验在引擎调用之前）
  ai/AiModels.kt          协议形状（ChatMessage/ToolDef/GenerateRequest；ai.* conf 合并纪律）
  ai/Engines.kt           双协议引擎 + 工厂（URL 白名单；失败中文原因）
  ai/AgentCore.kt         agent 工具循环（≤4 轮；工具清单唯一来源；取消真杀子进程）
  sysint/SysInt.kt        notify-send 封装 + XDG autostart + 深链解析（纯函数可测）
  sysint/TrayQuickView.kt SystemTray 托盘速览（X11 简版；isSupported false 静默降级）
  ui/Design.kt            设计系统（Fluent 暗色令牌 Palette/Type/Space/Radius/Motion + 滚动条容器）
  ui/Icons.kt             Fluent System Icons 图标体系（字体随包，字形按像素渲染成位图缓存）
  ui/Buttons.kt           Fluent 按钮体系（Material3 Button 的同签名替身、FluentButton/IconButton/Pivot）
  ui/Controls.kt          Fluent 输入控件（文本框/菜单/菜单项的 Material3 同签名替身、下拉选择框）
  ui/Markdown.kt          原生 Markdown（块级文法对位 mac MarkdownParser）
  ui/AppModel.kt          数据编排（每源一份 LoadState；路由；写操作留结果；C2 轮询；定时更新）
  ui/DashboardView.kt     仪表盘（hero 双轨更新 + KPI/语言/里程碑/活跃 + 扫描单入口 + 时间窗筛选）
  ui/BoardView.kt         看板（引擎状态分列；读不出单列；分支不全如实披露）
  ui/MilestonesView.kt    里程碑（CRUD + 破坏动作确认）
  ui/ConfidencePages.kt   代码置信度 + 补丁体检两页（披露式行/三态裁决/合并终稿）
  ui/GraphPages.kt        代码图谱/架构图两页（跟仓库走的路由页；render 回执解析 + 产物缓存）
  ui/HtmlWebView.kt       JCEF 装载状态机 + WebView 组件（量到真实尺寸再装载；经 navigator）
  ui/JcefBundle.kt        JCEF 原生包钉版（版本/下载源/平台表）
  ui/DashScope.kt         仪表盘派生文案纯函数（KPI/筛选/里程碑卡）
  ui/ProjectDetailView.kt 项目详情（三源 + git 六操作 + 图谱入口 + 更新）
  ui/ScanSheet.kt         扫描单（路径三态 + 逐项目新增/已在册推导 + 覆盖披露）
  ui/Automation.kt        定时更新配置（settings.conf update.* 独立节读写）
  ui/SearchFilter.kt      侧栏搜索纯函数（过滤/两态空因/resultSummary）
  ui/ShortcutMap.kt       窗口级快捷键单点声明 + AWT 层统一接管 + 动作执行唯一出口 runShortcut
  ui/AiViews.kt           AI 设置页 + 对话页 + 设置四 tab（通用含语言选择器/关于含四文档）
  ui/L10n.kt              多语言单例（t(key)/语言状态/回退链 当前→en→key/settings.conf 读写）
  ui/L10nTables.kt        四语言表 + 四文档（GENERATED：gen_l10n.py 从 mac 基准生成，勿手改）
  ui/L10nCmpKeys.kt       CMP 特有键四语言（cmp. 前缀；以 zh 为源补 en/zh-TW/ja）
src/jvmTest/kotlin/
  engine/ContractTest.kt        fixtures 契约回归（真实引擎输出，缺必知键=契约过旧）
  ui/ConfidencePagesTest.kt     置信度/补丁体检判据（10 条）
  ui/GraphParseTest.kt          render 回执/路径提取判据（10 条）
  ui/ScanSheetLogicTest.kt      扫描单判定判据（10 条）
  ui/CommitFormTest.kt          提交类型前缀判据（5 条）
  ui/SearchFilterTest.kt        侧栏搜索判据（11 条）
  ui/ShortcutMapTest.kt         快捷键声明判据（8 条）
  ui/AutoUpdateSettingsTest.kt  自动化配置判据（9 条）
  ui/HeroUpdateScopeTest.kt     hero 双轨范围判据（6 条）
  sysint/TrayQuickViewTest.kt   托盘摘要行判据（4 条）
  ui/L10nTest.kt          多语言判据（13 条：键集四语言对齐缺键即红/占位符一致/回退链/切换读写/四文档分发）
  ui/BoardContractTest.kt       看板列分配与披露判据（6 条）
  ui/DesignRefinementTest.kt    设计令牌判据（含「三级文字在每种底色上 ≥ 4.5:1」）
  engine/EngineMirrorDriftTest.kt  引擎 JSON 镜像双向漂移（fixtures/真机正向/真机反向）
  engine/EngineExecTest.kt       引擎子进程执行（stdout 纯净/超时/分流）
  engine/WriteOutcomeTest.kt     写操作回执（失败不得报成成功）
  ui/MarkdownTest.kt            原生 Markdown 解析与行内样式
  ui/DashScopeTest.kt / ui/CommitCountScopeTest.kt / ui/AiConfigTest.kt  纯函数判据
  ai/AiTest.kt                  mock 通道工具循环 / URL 门 / conf 合并 / 必填校验
  sysint/SysIntTest.kt          Exec 转义 / 自启写盘 / 深链解析
  resources/fixtures/           status/dashboard/milestones/docs/journal/confidence/render
                          真实引擎 JSON/文本（fixtures 全部真跑落盘）
```

判据纪律：判据只增不减；`scripts/build.sh --test` 跨套件求和，`failed=0` 才算过。
