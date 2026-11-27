# Canopy CMP 客户端 · 全量能力复刻计划（执行手册）

> 分支：`next/cmp`（骨架已验证：Compose 真窗口 + 引擎探活 Cambium 0.2.0 实测通过）。
> 基准：`archive/bui` 标签的 BUI 客户端（Rust 版 v1，含 tests/fixtures 真实引擎 JSON）
> 与 `macos/`（SwiftUI 基准）；能力口径 = PLATFORM-CHARTER.md C1–C11，**能力必须一致、
> 交互 UI 自由**。本端技术栈：Kotlin + Compose Multiplatform（桌面 JVM）+ webview
>（compose-webview-multiplatform / JCEF，Markdown 与富文本渲染用）。

## 环境速查（本机已就绪，无 root）

```sh
export JAVA_HOME="$(ls -d ~/.local/jdk/jdk-21* | sort -V | tail -1)"
export PATH="$JAVA_HOME/bin:$HOME/.local/gradle/gradle-8.10.2/bin:$PATH"
cd client
scripts/build.sh            # 编译；--test 跑全量判据
scripts/run.sh              # 真窗口（DISPLAY=:0）
```

- 引擎：`~/code/Cambium/target/release/bin/main` 已构建；PATH 上有 cambium 0.2.0。
- 依赖仓库：Maven Central + Google + JitPack + **jogamp.org**（kcef 的 gluegen/jogl 只在此）。
- 已知坑：①KMP 的 JVM 源码目录是 `src/jvmMain/kotlin`（不是 src/main/kotlin）；②`cc` 指向
  dd-sysroot gcc-13 真 C 驱动（~/.local/bin/cc，g++ 驱动过不了 cmake ABI 探测）——C 部分构建用。

## 分批计划（每批 = 一次可运行验证 + 一个 commit）

### 批 1 · 设计系统 + 引擎层 + 仪表盘（C1/C2/C3-仪表盘）
- Fluent 深色设计系统（对位 archive/bui 的 design.rs：磁贴/圆角/色板/字号七档/对比度闸门）。
- 引擎层完整化：status/dashboard/docs/journal/milestone/git/update/deep 全命令封装
  （kotlinx.serialization；fixtures 对位 = `git show archive/bui:client/tests/fixtures/`）。
- C2 周期轮询（5 分钟）+ 手动刷新；仪表盘页（KPI 磁贴/语言分布/里程碑/活跃 + 范围/类型筛选）。
- 判据：契约解析 fixtures 全量回归（缺键=契约过旧的口径不变）。

> ✅ 已落地 · 2026-11-23 核对（commit `133fa2c`）。

### 批 2 · 里程碑 + 详情 + git（C9/C3/C8）
- 里程碑 CRUD（tag 自动达成/date/desc）+ 列表页。
- 项目详情（脉搏/提交构成/分支/日志/文档四态，长文区 webview 或 Compose 渲染）。
- git 白名单六操作（pull/push/commit/stash/unstash/fetch）+ 结果输出区；破坏动作过确认。

> ✅ 已落地 · 2026-11-23 核对（commit `ddcf6ed`）。

### 批 3 · AI 全家桶（C7/C6/C5）
- C7 设置：provider/model 目录选择（models-dev 快照，assets/models/models-dev.json 注入）、
  key 存 libsecret（secret-tool 子进程）→ 0600 文件兜底、测试连通。
- C6 助手：agent 工具循环（≤4 轮，工具集与 mac/BUI 一致）、对话页（**webview 渲染 Markdown**，
  webview 能力在此落地）、停止按钮（真杀进程）。
- C5 整合更新：更新+AI 摘要、项目/群说明、定时更新（小时档）+ 简报通知。

> ✅ 大部落地 · 2026-11-23 核对（commit `c53f655`；**webview 渲染 Markdown** 由批后收尾
> 补齐 `748dde9`，见下节）。如实未落地：models-dev 目录选择器——AI 设置现为固定四渠道
> （deepseek/anthropic/ollama/mock）+ 模型/Base URL 手填（AiViews.kt）；key 的 0600
> 兜底文件（libsecret 缺席时的回退）未实现（AiViews.kt 头注释自记「批 4 补」，至今未补）；
> C5 整合更新流（更新+AI 摘要 / 定时更新小时档 / 简报通知）无代码。

### 批 4 · 系统集成 + 分发（C10/C11）
- C10：notify-send 通知、XDG 自启（Exec 绝对路径——吸取 run.sh 教训）、
  深链 --section/--project、SystemTray 常驻速览（java.awt.SystemTray，Linux 复核）。
- 分发：compose desktop nativeDistributions（jpackage，Linux deb/-appimage 任一）。
- 终验：全判据 + 真窗口截图全套（对位 archive/bui 的 docs/ui/after 口径）+ 打包安装冒烟。

> ✅ 大部落地 · 2026-11-23 核对（commit `9227a04`）。深链已接线（Main.kt →
> SysInt.parseDeepLink）；notify-send 封装与 XDG autostart 写盘在 sysint/SysInt.kt
> （判据覆盖）但**界面开关未接线**（代码无 UI 调用点）；SystemTray 常驻速览未实现；
> jpackage deb/AppImage 已配置（build.gradle.kts），打包安装冒烟未跑。

## 批后收尾批 + 落地终验（2026-11-23 核对）

四批骨架之后的三个收尾批（判据只增不减，commit 与门禁数字如下）：

| 收尾批 | commit | 判据增量 | 门禁 |
|---|---|---|---|
| 看板页真实现：stub → 引擎分支状态分列（active/stale/idle/merged），读不出单列，分支不全/无分支如实披露 | `b1abfb7` | +6（BoardContractTest） | 28 绿 |
| AI 助手 Markdown 渲染：最新一条助手消息走 KCEF/JCEF WebView 排版，缺席/失败回退纯文本并如实标注；markdown→html 纯函数（MarkdownHtml.kt / MarkdownWebView.kt） | `748dde9` | +8（MarkdownHtmlTest） | 36 绿 |
| 仪表盘与详情页精修：aurora 渐变斑块层（对位 design.rs）+ 项目总数 0 空态扫描/添加 CTA（接引擎 scan/add）+ 磁贴描边/hover + 详情页 SectionCard 节奏（色值上收 Design.kt） | `0cb2a46` | +9（DesignRefinementTest） | 45 绿 |
| 图谱两页：HtmlWebView 通用件（JCEF 单浏览器复用/reloadToken/看门狗/降级槽；MarkdownWebView 改为复用）+ CodeGraphPage/ArchPage 接 `render index --confidence`/`render arch` 文本回执（receiptLine/extractHtmlPath/renderReused 纯函数，fixture 真机落盘；产物缓存秒开旧图、复用不重载）+ Dialog 近全屏形态 + AppModel 开合流挂载；JCEF 缺席整页降级「WebView 不可用 + 产物路径」 | `72376da` | +10（GraphParseTest） | 61 绿 |
| 详情页接图谱两页 + 扫描单 + 提交单：动作条「代码图谱/架构图」busy 生成→成功即开页（本机引擎无 render check，按 mac 降级先例不做两态按钮；复用=毫秒级秒开）；仪表盘 hero「添加/扫描」开扫描单（mac ScanSheet 对位：路径三态判定 + 逐项目新增/已在册——归属由扫描前在册集对照推导，聚合行以引擎口径为准 + ScanCoverage 三种「没扫完」分开说）；ScanPayload 镜像按真机修正（candidates/unreadable 原为凭空 Long，真跑必炸）+ fixture 真机落盘；git 提交区补类型前缀选择（引擎 COMMIT_TYPE_ORDER 词表）+ 引擎 ok/output 结果反馈（失败信息留住） | `f75c255` | +17（ScanSheetLogicTest 10 + CommitFormTest 5 + ContractTest 2） | 80 绿 |
| 置信度 + 补丁体检两页：侧栏「视图」组里程碑后两入口（mac PanelView.swift:143-145 对位）；置信度页 `graph confidence --json` 六维度总分 + 权重降序 findings 披露式行（默认只给位置、≥8 红档、点击展开引擎证据+实码）+ 只看高权重开关 + 复制 LLM 复核提示词（--llm 纯文本 → AWT 剪贴板，stdout/stderr 分流防迁移提示混入）；补丁体检页 diff 粘贴 → Layer1 S1..S10 信号 chip（null=分母0 降档披露）→ uncertain 三态人工裁决 → --merge 终稿；契约三份镜像以真机实测锚定 | `1d5dae0` | +15（ContractTest +5 / ConfidencePagesTest +10） | 95 绿 |
| 交互层补齐：侧栏搜索（SearchFilter 纯函数：项目名+分支名大小写不敏感、emptyReason 两态、resultSummary、Ctrl+F 聚焦）；ShortcutMap 纯对象键位（Ctrl+1/2/3 视图、Ctrl+, 设置、Ctrl+R 刷新、Ctrl+F 搜索）挂窗口根 onPreviewKeyEvent 隧道相位；设置第四 tab「自动化」（间隔档 0/1/3/6/12/24 + 轨道浅/深，update.* 独立节，改完立即生效）+ AppModel 定时器；托盘速览（SystemTray 圆点 + 摘要行/打开/退出，X11 简版，isSupported false 静默降级）；hero 双轨按钮（浅/深更新带范围、待记录徽章 >0 才现、深更新动哪些文档写进副行） | `023f675` | +38（SearchFilterTest 11 / ShortcutMapTest 8 / AutoUpdateSettingsTest 9 / HeroUpdateScopeTest 6 / TrayQuickViewTest 4） | 133 绿 |
| L10n 四语言 + 四文档（对位 mac L10n.swift / DocsPages.swift / GeneralTab 语言 Picker）：`scripts/gen_l10n.py` 从 mac 基准生成 L10nTables.kt（504 键 × zh-CN/en/zh-TW/ja 照搬不改写 + 16 份文档，--check 守门）；L10n 单例（t(key) 回退链 当前→en→key、%@/%d/%1$d 占位、语言=Compose 状态换语言即时全界面、app.language conf 独立节、未配置跟随系统语言认不出缺省 zh）；全部视图/engine 错误/AppModel 反馈/托盘文案收编 L10n.t（147 处脚本自动 + 逐文件手工；CMP 特有键 300 个以 zh 为源补四语言收进 L10nCmpKeys.kt，cmp. 前缀不与 mac 键撞名）；设置-通用加语言选择器（即时生效）；关于 tab 挂四文档子 tab（MarkdownWebView 单实例渲染，性能取舍） | 本批 | +13（L10nTest） | 202 绿 |

**终验（2026-11-24，真机 DISPLAY=:0 全项过）**：
- 判据门禁：随本批后由门禁脚本复跑（PLAN 记账口径 133 绿，`023f675` 时点）。
- 真窗口八项逐一验证 + 截图落 `docs/ui-cmp/`：a/b 图谱两页（详情页动作条点按 → 引擎 render →
  Dialog 打开 WebView 装载产物，底部回执 `✓ …/projects/vtest/render/index.html · 首版（第 0 版）`、
  arch 同形态）`graph-index-page.png`/`graph-arch-page.png`；c 置信度页六维度数据
  （vtest 总分 40、六维度行、疑点 9 条、AST 降级披露）`conf-confidence.png`；d 补丁体检跑真 diff
  （选 vtest → 粘贴 diff → Layer1 总分 62、S1..S10 chip、三态裁决、低置信度实体、合并钮翻可用）
  `conf-patchcheck.png`；e 侧栏搜索（Ctrl+F 聚焦 → 输入「2」→ 仅剩 vtest2、仓库组 1/2、
  匹配行出现；× 清除复原 2/2）`interact-search-filter.png`；f Ctrl+1/2/3 三键切视图各一图
  `interact-ctrl1-dashboard.png`/`interact-ctrl2-board.png`/`interact-ctrl3-milestones.png`
  （首次 Ctrl+2 未生效——窗口尚未获得键盘焦点，点按窗口后三键均验）；g 设置-自动化 tab
  （定时更新卡：档位 关闭/1/3/6/12/24 小时 + 轨道浅/深）`interact-settings-auto.png`；
  h hero 双轨按钮（浅更新 · 全部 / 深更新 · 全部，副行「深更新动 README/AGENTS/CLAUDE」）
  `interact-hero-dualtrack.png`——**待记录徽章未现**：vtest 当前分支 pendingCommits=0（如实）。
- JCEF 150.0.14 本机缓存装载成功（~/.cache/canopy/kcef，547M 既有缓存，无首跑下载）。

**终验（2026-11-23）**：
- 判据门禁绿：`scripts/build.sh --test` → `CMPTEST_SUMMARY passed=45 skipped=0 failed=0`。
- **真窗口冒烟：异常，未通过**——运行时观感（aurora/hover/WebView 排版）未可视核验；
  KCEF 首跑需联网从 GitHub 下载 JCEF 二进制（缓存里已有 kcef/jcef jar，二进制是运行时
  落盘），不可用时按设计回退纯文本并在界面标注原因。复跑排障后再收口。

**如实未落地 / 已知边界（截至 2026-11-24 终验后核对）**：
- AI 设置无 models-dev 目录选择器；C5 整合更新流中的一键 **项目群/项目说明入口已落地**
  （仪表盘 hero「项目群说明」+ 详情页动作条「项目说明」→ openAgent 固定问题预填，
  mac GroupBriefButton/ProjectBriefButton 对位；任务串纯函数 briefTask +3 判据 BriefTaskTest）。
- ~定时更新小时档仍无代码~ **已落地**（`023f675`：设置「自动化」tab + AppModel 定时器；
  与 mac 差异如实：CMP 无守护进程，协程随应用存活、退出即停；mac 的系统通知/AI 简报未接）。
- ~SystemTray 未实现~ **已落地**（`023f675`：X11 简版圆点托盘 + 摘要行/打开/退出，
  isSupported false 静默降级；mac 的弹窗项目行/迷你进度条不做）。
- notify-send 的界面开关仍未接线（封装与判据在 sysint/SysInt.kt）；自启动开关已接线
  （设置「通用」tab，仅打包安装态可开——gradle run 无客户端入口）。
- 看板 fixture 口径差异（`summary.branchCount=8` vs 分支行数 7、`repoBranchCount=2` 只返回
  1 条）按判据只在页头披露「引擎返回 M/N」，不代引擎重算总数；merged 列无 fixture 样本
  （口径取自 macos 基准 StatusColor），引擎新口径由「口径未知」列兜底。
- Markdown 渲染边界：下划线强调、图片、Setext 标题不支持（宁缺勿错，MarkdownHtml.kt
  头注释有边界声明）；KCEF 每进程只尝试装载一次，彻底重试需重启应用。
- 图谱两页（`72376da`）：详情页入口**已接线**（本批）——动作条「代码图谱/架构图」→
  AppModel.renderGraphArtifact：本机引擎没有 `render check`（实测报用法错），按 mac 降级
  先例（GraphChrome.swift:185-187 探测失败=未生成）不做「打开/生成」两态按钮，点按统一
  busy 态跑 render；产物已在时引擎复用判定毫秒级返回即秒开，不在时这一发就是首次生成。
  mac 头部的「AI 生成」（GraphAgentTask 播种 agent、关窗回读产物）与「外部打开」
  （xdg-open）如实缺位——AgentSheet 尚无关窗回调，不造假按钮。渲染通道用文本回执
  （mac 同形态），路径提取对真机「黏全角冒号」形状适配为正则 token（mac 空格分词会漏提）。
  Dialog 近全屏为 92% 宽高的近似（Compose 无独立 NSWindow 最大化）。
- 扫描单（本批，对位 mac ScanSheet + PanelView.swift:92-94 挂 sheet）：逐项目「新增/已在册」
  是客户端拿 candidates 对照**扫描前**在册集推导的（引擎 payload 只有聚合数，candidates
  不带归属标记，真机 fixture 锚定）；推导数与引擎聚合分叉时以引擎为准并披露。mac 的
  「选择…」目录面板与拖放回填不做（Compose Desktop 目录选择走 AWT FileDialog，本批收在
  纯表单口径）。
- 提交单（本批，对位 mac CommitSheetView）：**stage 级（逐文件）勾选不做**——本机引擎
  `git commit` 是 add -A 全量（kernel/git.cj:1848-1850 实测，无 --paths），子集提交没有
  引擎语义。类型选择对位到**提交信息前缀**（引擎 COMMIT_TYPE_ORDER 词表去 other，别名
  同认不双前缀）——有真实效果：新提交被引擎归入「提交构成」对应类型桶（真机实测
  `docs:` 前缀落 commit subject）。改动构成行只报 dirty 四类计数（已暂存/修改/未跟踪/
  冲突）；mac 类型集的 added/deleted/renamed 是 per-file XY 归一词，本机引擎没有
  `git status` 子命令（实测白名单 pull/push/commit/stash/unstash/fetch）、dirty.files
  不带 kind——如实不造。
- ~Main.kt 侧栏底部「判据 11 条」陈旧文案~ 已修（AiViews 关于 tab 11→61，随图谱批 `72376da`）。
- MilestonesView.kt:32 模态遮罩 `Color(0x88000000)` 是遗留内联色值（此前里程碑批产物，未动）。

## 多语言边界（L10n 批，2026-11-24）

- **AI 层不本地化**（mac AIClient.swift 0 处 L10n 同口径）：ai/Engines.kt、ai/AgentCore.kt、
  ai/AiModels.kt 的错误与提示词、briefTask 任务串、连通性测试提示保持中文——它们是对话内
  诊断/AI 指令，不是界面 chrome。
- **引擎输出匹配词不本地化**：GraphPages `renderReused` 匹配引擎回执里的「复用/reused」
  （引擎契约词）；ScanSheet 聚合计数匹配用 `cmp.scan.addedLabel/existing`（与聚合行同键
  生成/同键解析，语言自洽）。
- **托盘 AWT 菜单标签启动时定格**：SystemTray 菜单在 install 时构建，换语言不重建
  （摘要行走 updateSummary 随语言实时）——重启后生效，如实不装作即时。
- **.desktop GenericName 不本地化**：系统文件元数据（freedesktop 有自己的 l10n 机制，
  不在本批范围）。
- **CMP 特有键**（mac 没有的文案，以 zh 为源补 en/zh-TW/ja）：`cmp.*` 共 300 键，全部在
  ui/L10nCmpKeys.kt，四语言键集一致性由 L10nTest 守（缺键即红）。
- **事实层双语**（mac usesEnglishFacts 同口径）：SearchFilter 空态/匹配行只有 zh/en 两套，
  繁中共用简中、日文回落英文。

## 引擎子命令能力清单（诊断批 `cambium --help` 实测 rc=0；只记录，不实现页面）

通用：list/add/remove/scan/status/track/update（浅更新 `--docs --dry-run`）/deep（`--scope`）/
journal（`--branch`）/git pull|push|commit|stash|unstash|fetch/hook/milestone add|list|done|drop|remove|reopen/
dashboard/context（`--budget`）/docs/tools/mcp（MCP 服务器，stdio JSON-RPC）/skill print|install/
report（`--out`）/config/verify/doctor。重点四类（均实测存在）：

- **置信度类**：`confidence <gen|query>`（confidence.json；索引过期自动重建；`--db` 额外写
  confidence.db）；`confidence db`（findings/dimensions/罚分表写入单文件 SQLite）。
- **补丁检查类**：`graph patchconf`（补丁级置信度三层架构：`--patch` 分析 / `--skill` 取 Agent
  任务 / `--merge` 合并终稿）。
- **代码图谱类**：`graph [overview|tree|symbol|impact|arch|confidence|patchconf]`、`graph db`
  （符号级索引写 SQLite nodes/edges，含 tier 确信度）、`index <gen|overview|update|query>`
  （持久化代码索引，query 支持符号/`--file`）。
- **架构图类**：`graph arch`（`--format html|mermaid|dot|json|scene`，html 为 Canvas 交互图）、
  `arch <gen|update|query>`（arch.json 含布局坐标、探针增量 `--force`、query [模块]
  `--violations`）、`render <arch|index>`（`render index --confidence` 可叠加置信度）。

## 红线（每批必守）

1. 引擎 JSON 键名是唯一耦合面——以 fixtures 与 archive/bui 的 models.rs 为准，不许发明键。
2. Linux 通用端：不引入 DDE/deepin 专属能力；集成一律 freedesktop 通用机制。
3. 失败诚实：给原因与下一步，不静默、不假装成功。
4. 判据只增不减；每批一个 commit（`feat(cmp): …`），编译+判据+真窗口截图同 commit。
5. 参考实现只抄能力语义，UI 按 Compose 地道写法（别把 Rust/Swift 的模式硬搬）。

## 收官批：Fluent 美学 + 性能（2026-11-24）

- Fluent 视觉：Design.kt 全量换 Fluent 暗色令牌（Mica 底 #1F1F1F/白 alpha 分层/白三级文字/accent #60CDFF 配近黑文字/圆角 4-8/字阶 12-28/动效 150-300ms）；导航选中 accent pill 指示条 + 150ms 渐变；GlassCard hover reveal（去 mac 抬升）；hero 安静头（分层微渐变 + accent 顶 hairline，去多色渐变）；七个浮层加 elevation + hairline；accent 按钮近黑文字。DesignRefinementTest 判据重锚 Fluent 纪律。
- 性能：设置页静态说明与四文档改纯 Text（不再拉起 JCEF——启动全程零 CEF）；引擎 DTO 全量 @Immutable；STARTUP_MS 启动打点（真机实测 755ms 冷启动到首帧）。
- 边界（如实）：页面级 LazyColumn 化未做——长列表都在页面级 verticalScroll 内，嵌套滚动需整页重构，收益/风险比不划算，留专项批；MarkdownHtmlTest 令牌断言改动态取值（单点真相源语义不变）。
- 终验：204 判据 0 failed；真机逐页实拍 fluent-final-* 五张入库。

## 补差批：菜单条等价物 + Lazy 化收尾 + deb 冒烟（2026-11-24）

- 窗口内菜单条（MenuBar.kt）：mac 原生菜单栏命令的 Linux 等价物——「操作」菜单（全部浅/深更新走 requestBulkUpdate 同一确认链、刷新、停止更新）+「帮助」菜单（帮助文档深开设置-关于-帮助子 tab、GitHub Canopy/Cambium 双链接）。停止更新=EngineLocator 进程登记表 destroyForcibly（mac stopUpdate 杀引擎子进程本体的对位；run/runMerged/runSplit 三入口全登记），结果如实回写操作行。
- 页面级 Lazy 化收尾：详情页整页 LazyColumn（页头/结果行/六段卡片逐段 item+稳定 key）、看板列区列粒度 item、置信度 findings 行级 items（kind#file#line#symbol 键）。
- deb 打包安装冒烟：packageDeb（fakeroot 用户态 wrapper）→ 69.5MB deb → dpkg-deb -x 提取校验（control/desktop/启动器齐全）→ 打包态真启动 STARTUP_MS=734ms、45s 存活、菜单条实拍（deb-live-menubar/menu-operations-open 两张入库）。
- 门禁：204 passed / 0 failed。
- 边界：desktop-file-validate 本机不可用（未装 desktop-file-utils），desktop 文件内容人工核对（Exec/Icon/Categories/MimeType 字段齐）；真 dpkg -i 安装需 root 未做（提取+启动器冒烟为无 root 等价物）。

## 二次验证修复 + 图谱落地 + 页面化 + Fluent 精修批（2026-11-25）

起因：「已完成复刻」的结论经不起二次验证。四路只读审计结论一致——零差距不成立；
按「找茬」姿态把 BUG 级问题逐个修掉，再由用户两轮追加定稿（图谱页不弹窗、UI 美化、引擎补强）。

### 二次验证抓到并修掉的（BUG 级）

- **图谱页一直空白，三层根因**（此前「验证通过」的截图本身是空白页，在本机从未显示过内容）：
  ① `WebRuntime.state` 是没加 `by` 的 MutableState 对象，`when` 的三个分支永不匹配——既不就绪、
  也不失败、连降级文案都不出；② 缺 JOGL 本地库（`natives-linux-amd64`），一组合就
  `UnsatisfiedLinkError`；③ KCEF 默认下载追 JetBrainsRuntime「最新」release，与 Maven 上的定版
  Java 绑定不配套（原生找 `CefRequestContextSettings`，旧绑定没有 → 加载真实 URL 必崩）。
  → 状态委托；显式声明本地库；原生包钉版到与绑定同源的 `jbr-21.0.4+8-631.2`、从 JetBrains CDN 下（ui/JcefBundle.kt）。
- **WebView 装载的三条硬教训**（真窗口诊断得出）：库只在创建 browser 时读一次初始内容，
  之后给 `state.content` 赋值不触发任何装载，必须走 `navigator`；browser 在组合时就创建，
  此时还没布局——产物初始化按视口取景（架构图 `fit()`），所以**量到真实尺寸再装载**；
  `loadHtml` 走的内部映射在本机恒 `ERR_FILE_NOT_FOUND`，只有真实 `file://` 直载可靠。
- **引擎镜像漂移**（`ignoreUnknownKeys=true` 会静默吞掉引擎发的键）：`commitTypes.type→kind`、
  journal 条目、仪表盘、里程碑 8 个键、分支 2 个键、`milestone add` 回执的 milestone 是对象……
  全部按真机/契约修正，并由 `EngineMirrorDriftTest` 三档（fixtures 正向 / 真机正向 / 真机反向）把关。
- **失败被报成成功**：引擎 exit≠0 仍按回执解码 → `Engine.call` rc≠0 即失败（`EngineStoppedException`）；
  stderr 全丢、超时失效 → EngineLocator 重写（双泵线程、超时强杀即返回、停止更新先 SIGTERM 后强杀且只动更新类）。
- 其它：置信度页打开即崩（LazyColumn 嵌在滚动 Column 里）、深链不生效、快捷键触发两次、
  侧栏不可滚动、定时更新绕过 busy、刷新被丢弃、帮助菜单落错 tab、Markdown 显示源码、L10n 四表键不一致。

### 图谱两页页面化（用户定稿 2026-11-25）

- 不弹窗、专门一页、跟着仓库走、入口在各仓库详情里：`Route.GRAPH / ARCH` + `selectedProject`；
  侧栏高亮所属仓库、工作条范围收敛到它、页头「返回仓库」。mac 是独立最大化窗口，此处不追 mac。
- 渲染口径统一在 `AppModel.renderGraph`（详情入口 / 深链 `--section graph --project X` / 页内刷新共用）。
- 架构图产物按 `prefers-color-scheme` 选明暗，而 CEF 在 Linux 只认 GTK 的暗色开关、命令行开关实测无效
  → 产物 + 垫片落成缓存目录里的副本再直载（`withHeadScript` / `DARK_SCHEME_SHIM`）；不加 `<base>`
  （产物用 `history.pushState` 写 `#module=…`，基准 URL 一变即 SecurityError）。
- 回执条固定占位：WebView 落位后不再被状态变化挤动尺寸（实测抓到过一次 JOGL 绘制线程在
  「上下文销毁」与「设为当前」之间撞车后整页不再重绘；修后二十余次开关 + 12 次连续改窗口尺寸未复现）。

### 外壳与精修

- **快捷键在 AWT 层统一接管**（`ShortcutMap.AppShortcuts`）：原先挂在 Compose 焦点链上，
  刚启动什么都没点、被点的控件随即消失（清空搜索框的 ×）、WebView 持有焦点时全哑。
- **退出兜底**：浏览器状态异常时 CEF 的关闭钩子会一直等（实测进程收 SIGTERM 四分钟不退，窗口留在屏幕上）
  → 关闭钩子 4s 不退就 `halt`；应用内退出与外部 SIGTERM 同一出口。
- Fluent 组件体系：Fluent System Icons 真图标（字体随包，字形按像素渲染缓存）替代散落的 Unicode 字形；
  Material3 `Button` / `OutlinedTextField` / `DropdownMenu(Item)` 的**同签名替身**（32 高控件、描边浮出菜单）；
  三处自绘的「原地撑开」假下拉换成真正的下拉选择框；设置页改 Fluent Pivot；全应用可滚动区加滚动条；
  看板去掉卡片套卡片。设计纪律：**三级文字合成到每一种底色上都 ≥ 4.5:1**（DesignRefinementTest 按对比度公式钉，不记魔数）。

### 验证与判据

- 门禁 **256 passed / 0 failed**（禁用缓存 `--rerun-tasks --no-build-cache`；门禁脚本读 XML 会读到陈旧结果）。
- deb 打包冒烟（本机已有 fakeroot/dpkg-deb）：packageDeb → 71.3MB → `dpkg-deb -x` 提取校验
  （启动器/运行时/应用 jar 含图标字体与许可/JOGL 本地库/Ktor/desktop 文件/--add-opens 齐全）→
  打包态真启动 `STARTUP_MS=864ms`、图谱两页可渲染、SIGTERM 正常退出。真 `dpkg -i` 需 root 未做。
- `docs/ui-cmp/` 换成打包态实拍 12 张 + 逐张说明；此前 48 张旧图退役（至少 9 张截到的是 IDE）。

### 边界（如实）

- 首跑要下 217MB 的 JCEF 原生包，这台机器走 IPv4 到 CloudFront 约 200KB/s（要十几分钟）；
  原生包随 deb 内置可免掉下载但包体 +217MB——取舍待定。
- desktop 文件没有 `StartupWMClass`：Compose Gradle 插件 1.7.3 的 Linux DSL 不暴露该属性，
  窗口类名（`canopy-MainKt`）与 desktop 文件名不一致，任务栏归组未验证。
- 那次 JOGL 绘制线程空指针只出现过一次，修掉最可疑的触发点后未能再复现——不能证明绝迹。
- 剩余差距（来自四路审计，未修）：系统通知零接线、引擎缺席时外壳消失、关窗即退出（托盘不常驻）、
  「更多」菜单与扫描目录选择器缺、AI 设置关闭即保存未做、agent 工具只实现 10/28（图谱工具全缺）、
  提交单无「只提交勾选文件」（本机引擎 `git commit` 是 add -A 全量）、看板不吃时间窗筛选、
  补丁体检不能自动取 `git diff HEAD`、置信度实码只读一行（mac 为 ±3 行高亮）等。
- 过程记录：一次点击序列写反，误触了 vtest 详情页的「深更新」，对测试仓库 `/tmp/vtest` 跑了一次
  深度更新（README 被引擎重写进度区块）——已还原到提交状态。

## 引擎协同补丁：热力图快照过期自愈（2026-11-25）

引擎侧（cambium 0.3.0）加了渲染过期校验：置信度快照依据的索引版本与当前不一致时，不再把旧快照叠到
新索引上（旧行为是悄悄叠一张可能错位的热力图），回执里如实写「置信度快照过期……先 moongit confidence gen」。
连带问题落在客户端：每个仓库每会话只强制重绘一次，之后源码变了、索引被自动重建，图谱页就没有热力图，
而「刷新」按钮救不回来（本会话已强制过，不会再生成快照）。

- 修法：`AppModel.renderGraph` 读到过期回执就补生成一次快照再重绘（前台与后台核验都生效）；
  生成失败则保留过期回执（结构图照常可看），原因写进结果行，不吞；协程取消原样上抛。
- 判据：`renderStaleConfidence` / `needsConfidenceRefresh`（纯函数）；fixture 两份取自引擎真跑
  （`fixtures/render/index_stale_confidence{,_en}.txt`：生成快照后改源码，索引被自动重建成第 1 版）。
- 门禁 **259 passed / 0 failed**（禁用缓存；比上一批多 3 条）。

同一批的引擎协同（疑点挂符号键，引擎提交 4451c92）：每条疑点新增 `id` / `qual` / `dim` / `label`
四个键。仓库里的镜像漂移判据会把它没接住的键判红——做法是补镜像而不是豁免：
`ConfFinding` 增这四个字段；置信度页的疑点行右侧显示「证据名 @ 挂靠符号的限定名」
（`findingLocationText`：幻觉调用挂在调用它的函数上，`symbol` 是「谁有问题」、`qual` 是「问题发生在哪」）；
`fixtures/confidence/confidence.json` 用新引擎真跑重取（vtest 播种 suspect.py，分数 51 / 4 条疑点不变，
每条多了四个键）；门禁对着新引擎构建跑（`CAMBIUM_BIN` 指向它），真机两档都实跑通过：**260 / 0**。

- 真机联调（打包态 + 引擎 0.3.0 的构建，`DEEPGIT_HOME` 指向沙箱）：改了测试仓库的源码后点「刷新」，引擎调用
  序列是 `render index --confidence` → `confidence gen` → `render index --confidence --force`，页面上的热力图是
  新一版的（跑了两次）。
- 同一轮实拍还抓到并修掉一个引擎侧的升级问题：旧构建留下的索引数据（函数节点没有列号 / 签名）被新引擎当成
  「新鲜」复用，定位串没有列号。引擎的新鲜度判定补了「数据形状」这一条（store_meta 的 `payload_shape`），
  装上新引擎后点一次刷新就自动重建——客户端的自愈正好把随后的快照过期也接住了。
- 热力图定位区（引擎侧实现）：定位串 `suspect.py:34:5`、符号 ID、模块路径三次点击都从 X11 剪贴板原样读回
  （`file://` 页面没有剪贴板权限，走隐藏 textarea 兜底）。实拍见 `docs/ui-cmp/13-heat-map-locator.png`。
- 门禁对着**已安装**的引擎（`~/.local/bin/cambium`，0.3.0）跑：**260 / 0**，镜像漂移的真机两档实跑通过。
- 边界：过期判定认的是回执文字里的固定措辞（引擎 `confidenceStaleNote` 唯一构造，中英各认一处锚），
  不读 `--json`（文本回执同时供状态条显示，对位 mac 的做法）。
  macOS 客户端没有同步这两批（它是否也有同样的缺口未核对）。

## 图谱两页按页面完整适配（2026-11-26）

用户反馈：「两个图的页面你得完整适配页面，现在是直接嵌套的，有些不美观」。摸底后是一组结构性重复：
引擎产物自带页头 60 + 工具条 54 + 图头 44 + 面包屑 34 + 技术状态条 25，与客户端自己的页头、回执条叠成
六条横杠；两套标题、两套状态条、两套项目名；外面还套了一层「卡片里再套卡片」的双描边；1270×830 的
窗口里画布只剩约 330px。配色（深蓝底、星点光斑、13px 圆角）也和 Fluent 主题不是一套。

- **适配放在引擎产物里，客户端只声明要什么**：引擎给两份产物加了「嵌入模式」——宿主在产物任何脚本之前
  声明 `window.CAMBIUM_EMBED = { chrome: "page", vars: {…CSS 变量…}, canvas: {…画布颜色…} }`，产物自己收拢外壳
  （一条命令条 + 画布 + 一条面包屑条）、改走宿主的主题；画在 canvas 上的颜色与圆角也跟宿主令牌走。
  不拿 CSS 去盖产物的类名：那等于客户端替引擎维护第二份样式，产物一改就静默失效。
- **客户端这一侧**（`ui/GraphEmbed.kt`）：把 `Design.kt` 的 Palette 翻译成那份声明（底色、描边、文字、
  强调色、语义色、圆角、字体栈），令牌改了图谱跟着变；经 `HtmlWebView` 的 `headScript` 注入（架构图仍垫暗色，
  给不认识声明的老引擎产物留的）。老引擎产物不认识声明，按独立版渲染，不会坏。
- **页面**：WebView 直接铺满页头与回执条之间，不套卡片、不留左右边距；命令条左右留白与页头对齐（20px）。
- **回执条**：成功回执去掉产物的内部绝对路径（`已重绘：/home/…/render/index.html · 第 2 版` →
  `已重绘 · 第 2 版`），失败回执原文照录；要路径时有去处（页头的「在浏览器中打开」、WebView 没就位时的降级视图）。
- **「在浏览器中打开」**：mac GraphHeaderView 有、CMP 之前缺的一个动作，补上（独立打开是完整版的图谱）。
- **引擎侧顺带堵的升级漏洞**：渲染产物的复用判定比对模板版本——否则换了引擎后旧页面会被当成「输入没变」
  一直复用，用户看不到新外壳（本机真实进度库上实测：装上新引擎后第一次「已重绘」，之后「已复用」）。
- **实拍抓到并修掉的**：主区域漏了跨列声明被放进第一列；`false` 被当成「没设置」导致画布上的氛围光斑没关掉；
  装载那一刻量到的容器尺寸不是最终尺寸（嵌入模式下 ResizeObserver 盯容器，变了就重新取景）；
  窄窗口下工具条被挤没；架构图左下角图例与提示条重叠；按钮里的字符图标（⇢ ✦ ↗）在页面里不显示。
- **结果**：画布约 557px 高（占窗口 67%，原 40%）；窄窗口（1000×700）与宽窗口（1680×980）都实拍过。
  见 `docs/ui-cmp/09 / 10 / 13 / 14`。
- 判据：客户端 `embedHeadScriptDeclaresPageChromeWithClientTokens` / `colorToCssKeepsLocaleAndTrimsAlpha` /
  `receiptSummaryDropsArtifactPathAndKeepsTheRest`；引擎 `testIndexHtmlEmbedModeHooks` / `testArchHtmlEmbedModeHooks`。
  客户端门禁 **263 / 0**；引擎 725 项、722 过（红的仍是那 3 条已知环境用例）。
- 边界：产物里的画布卡片文字仍是等宽字体、独立版的字号偏小（画在 canvas 上，只换了颜色与圆角）；
  窗口窄于约 640px（WebView 宽）时图谱改成上下排。macOS 客户端没有同步这一批（它没有嵌入声明，仍是原样内嵌）。

## 平台决定（用户 2026-11-26 定，勿再逐次询问）

**全平台的客户端就是 CMP（Compose Desktop）这一份**——macOS / Linux / Windows 都跑它；
**不再做任何平台的原生（专属）开发**。含义：macos/Sources 的 Swift 版功能冻结（不再作为
功能对齐目标与移植参照），新能力只进 CMP；`/goal` 里「与 mac Swift 版零差距」的目标自本条起
由「CMP 即唯一客户端」取代。仓库里 macos/ 目录暂不删除（历史参照），但不投入新工作。

## 皮肤批：namethatui.com/styles 全风格主题（2026-11-26）

用户指定两件事：① namethatui.com/styles 里的主题除 flat design 外全部实现一遍；② 组件与姿态
按 namethatui.com 的元素目录优化。

- **皮肤系统**（`ui/Skin.kt`）：`Skin` 数据（30+ 令牌槽：表面 / 文字三级 / 语义色 / 渐变端点 /
  圆角三档 / 描边宽度 / 阴影形态 / 光泽 / 背景装饰），`Skins.apply` 写入全部全局令牌
  （`Palette` / `Type` / `Radius` 已是 mutableStateOf 状态，一换全界面重组，与切语言同机制）；
  组件形态差异走 `Material` 令牌（描边宽度、阴影形态枚举、光泽开关与强度、背景装饰种类），
  绘制代码按令牌渲染，调用点不 if 皮肤。
- **14 套皮肤**：Fluent 暗色（默认）+ 站上 13 个——玻璃拟态（深紫壁纸光斑 + 白 15% 磨砂卡 + 白描边）、
  液态玻璃（深蓝壁纸 + 白玻璃卡 + 有色光晕 + 顶部高光）、新拟态（浅灰蓝同色凸起 + 双向软阴影）、
  黏土拟态（淡紫 + 胖圆角 + 大模糊浮起）、新粗野主义（奶油底 + 2px 黑描边 + 硬偏移阴影 + 黄 accent）、
  网页粗野主义（90 年代原始网页：白底灰表框蓝链接）、Y2K（深底霓虹粉描边光晕 + 铬银网格壁纸）、
  Frutiger Aero（天空草地渐变 + 白玻璃卡 + 光泽 + 气泡）、拟物皮革（深棕皮革 + 缝线 + 黄铜 accent）、
  远古网页（Geocities 深蓝 + 星星贴纸 + 绿/品红）、Aqua（银蓝灰 + 蓝色糖果按钮 + 强顶部高光 + 胶囊控件）、
  Windows Aero（蓝极光壁纸 + 白 24% 透玻璃卡 + 光晕）、极简主义（纯白 + 黑 accent + 无阴影）。
- **组件姿态**（namethatui 元素目录的 posture 纪律）：按钮有 hover / 按下 / 禁用三态
  （硬偏移阴影的皮肤按下时按钮位移进阴影里——Neobrutalism 的标准姿态）；卡片走皮肤阴影与光泽；
  容器给定的底色上前景色自适应深浅（`readableOn`）——浅色皮肤下不再硬编码深底假设。
- **设置 · 外观**（`cmp.settings.appearance`）：14 个 chips（名称 + 底/卡片/强调三色预览点），
  即点即换；`settings.conf` 的 `app.skin` 键持久化（启动恢复；只动自己的键，L10nTest 键前缀纪律照守）。
- **守卫**（`SkinTest`）：14 套齐全（对照站点清单）；**所有颜色必须 8 位 ARGB**——Y2K / Aero 的
  textSecondary 用了 6 位 hex（alpha 0）导致整页文字隐身，实拍抓到后钉死；app.skin 合并不串键。
- **门禁 266 passed / 0 failed**（禁用缓存）；14 套皮肤全部在打包态真窗口逐个点击实拍
  （`/tmp/ui/skin-*.png` 过程稿；定稿见 `docs/ui-cmp/15-appearance-themes.png`）。
- 边界：flat design 按用户要求未做（站上的「In research」条目——Swiss / Bauhaus / Art Deco /
  Art Nouveau / Memphis / Vaporwave / Internet Ugly——站点尚未正式发布，未列入）。
  当时记的另两条——「图谱两页的引擎产物不受皮肤影响，配色走自己的嵌入契约」「浅色皮肤下对比度偏弱，
  后续按页微调」——已由后续两批解决：嵌入尺寸融合批让产物配色跟客户端令牌，皮肤对比度批把令牌与文字的
  冲突整体量了一遍并修掉（见文末）。

## UI 姿态批：namethatui 元素目录对照第二轮（2026-11-26，工作流施工 + 编排者复核）

上一轮遗留的「组件与姿态按 namethatui.com 优化」由一个动态工作流施工（7 个子代理：姿态审计 →
原语工匠 → 三个区域并行接线 → 全量门禁 → 换人复审），编排者复核后修掉两条低危项。

- **公共姿态原语**（Design.kt）：`SkeletonLine` / `SkeletonCard`（微光扫过占位，`Motion.animate=false` 退化静态、
  粗野皮肤 radius=0 自动变方块）；`focusRing`（键盘焦点环：accent 色 2dp 环画在界外不挤布局，
  **指针会话抑制**——按下与取焦同在半秒内视为鼠标取焦不出环，Tab 导航出环）。
- **接线**（31 项）：仪表盘（提交构成卡骨架加载、筛后空态加恢复入口）、里程碑（行骨架、空态引导）、
  看板（列表骨架、项目卡悬停抬升）、工作条（pill 统一）、按钮/图标钮/Pivot/ChoicePill（焦点环）、
  表单卡与托盘速览（浅色皮肤浮层描边）。
- **编排者复核修掉两条复审低危项**：① `focusRing` 原用 `hasFocus`（含后代）——容器挂环 + 行内控件挂环时
  Tab 到内层会两道环同亮，改为只认 `isFocused`；② 删除无调用点的 `SkeletonList`（仓库不留死代码）。
- **门禁**：266 passed / 0 failed（`--rerun-tasks --no-build-cache` 禁用缓存实跑）。
- **边界（如实）**：打包态逐皮肤实拍未做——凌晨锁屏挡住屏幕，无法截图（下批开工前补）；
  复审另有 4 条低危记录未修：Pivot 相邻页签焦点环被右侧底色盖 1-2dp、看板卡按压反馈因去 ripple 变弱、
  黏土/新拟态下 pill hover 提亮幅度小（令牌既有值）、仪表盘筛后空态复用「全部」文案略含糊。

## 嵌入尺寸融合批：图谱两页按拿到的视口排、与外壳同尺（2026-11-26）

用户看完嵌入模式第一版后的原话：「继续推进，尤其是嵌入的那几个页面的大小尺寸的融合」。
锁屏期间改用**按应用窗口取图**（X11 `import -window`，不经桌面合成、不发键鼠；导航全走启动参数深链），
在打包态真窗口里量出四处不融合：架构图缩窄窗口后不重新取景（卡片被窗口右缘裁掉）；两张图的布局形状
都不看可用区域（4 个模块缩到 0.69 倍、卡上元信息 6px）；热力图色带铺满「布局那一刻的画布宽」被裁；
底部叠三条横杠。引擎侧的做法见引擎仓库 AGENTS.md 不变量 156，客户端这边：

- **页面框架**（GraphPages.kt）：页头（标题 + **回执胶囊** + 三个按钮）之下整页都是产物。回执从页面
  底部的一条挪进页头——胶囊定高 32、单行、可关闭，页头高度不随回执有无而变（WebView 不被挤动；
  原来「回执条出现把 WebView 压矮 → JOGL 空指针」的教训仍然成立，只是不再需要那条固定高度的空条）。
  画布因此多出 70dp（图例 42 + 回执条 28）：1270×830 的窗口里 514px → 584px。
- **尺寸契约**（GraphEmbed.kt）：嵌入配置新增 `--e-ctl-h` / `--e-foot-h`（`ControlHeight`）、
  `--e-r-ctl` / `--e-r-card`（`Radius.control` / `Radius.card`）——嵌入页的输入框、按钮、卡片与外壳
  同高同圆角，换成直角皮肤跟着变方角。产物那边每个变量都有回退值，老产物 / 不传都不坏。
- **窗口最小尺寸 960×640**（Main.kt `MinimumWindowSize`）：Compose 1.7 的 `Window` 没有这个参数、
  也不经组合局部暴露窗口对象，从 AWT 的窗口清单里认主窗口（进程里唯一一个 showing 的 `Frame`）。
  两处真窗口才抓得到：① 第一版「找到就 return」，设值那行只有没找到才执行——最小尺寸根本没设上；
  ② AWT 的最小尺寸含窗框，960×640 的客户区口径要把标题栏加回去（实际卡在 960×600）。
- **缩放核对**（HtmlWebView.kt `HtmlWebEvent.Scale`）：装载完成后读页面的 `devicePixelRatio`，与外壳的
  density 对账；偏差超过 8% 在页头如实提示（本机 1.0 / 1.0，不出提示）。
  **不悄悄缩放任何一边**——怎么对齐要在开了显示缩放的真机上定（KCEF 的 builder 能传 Chromium 启动参数，
  但离屏渲染下输入坐标映射是否跟着变，这台机器上验不了）。
- **实拍**（打包态 deb 提取运行 + 沙箱引擎，itest 两页 × 1270×830 / 1680×980 / 960×640；
  定稿 `docs/ui-cmp/16`–`19`）：热力图卡片 162×93（0.69 倍、元信息 6px）→ 245×141（1.3 倍、10.5px）；
  架构图四个模块从一行 0.77 倍折成 2×2 的 1.35 倍。已安装引擎 + 真实注册表（vtest）复拍：旧 `arch.json`
  被自动重建成新形状（回执「架构已过期——先自动重建」）。
- **门禁**：269 passed / 0 failed（禁用缓存；新增 3 条：尺寸令牌随皮肤圆角变、`cssPx`、缩放核对的判据）。
- **边界（如实）**：HiDPI 下的缩放对齐未做（需真机）；大图（模块级 188 个节点）仍落在取景下限 0.22、
  整体铺开 + 小地图，是既有行为；逐皮肤打包态实拍仍未补。

## 品牌升级批：Sylva · Cambium · Canopy · Dendro（2026-11-26）

用户定的新品牌：引擎 moongit → **Cambium**，客户端 deepDolphin → **Canopy**，置信度模块 → **Dendro**
（从 git 引擎里剥离成独立的小模块，不是独立仓库），整体 → **Sylva**；「相关命令同步更新，文档同步更新」；
两个远端仓库继续分开。

- **机械改名**（脚本，大小写分条）：显示名 `deepDolphin → Canopy`、包 / 路径 / 包名 `deepdolphin → canopy`、
  显示名 `moonGit → Cambium`、命令 `moongit → cambium`、环境变量 `MOONGIT_BIN → CAMBIUM_BIN`、
  嵌入声明 `MOONGIT_EMBED → CAMBIUM_EMBED`。71 个包声明、145 个 import、目录 `kotlin/deepdolphin → kotlin/canopy`、
  图标资产 `deepdolphin.* → canopy.*`。`「」`里的原话、schema 串、仓库链接、兼容兜底的旧环境变量名不动。
  冻结的兄弟端（`macos/`、`deepin/`、`linux/`、`windows/`、`harmonyos/`）不在范围内——它们还带旧名。
- **引擎调用改教新写法**（Engine.kt 五处）：`confidence gen → dendro gen`、`graph confidence → dendro check`、
  `graph patchconf → dendro patch|merge`；`--confidence` 旗标不动（功能词）。
  ⚠️ 差点把 `graph confidence` 并进 `dendro query`：前者现算报告（`--llm` 出复核提示词、不落盘），
  后者只读快照——写引擎对照表时才发现，正名定为 `dendro check`。
- **引擎发现**（EngineLocator）：`CAMBIUM_BIN` → `MOONGIT_BIN` / `DEEPGIT_BIN`（旧名兜底，用户 shell 里
  export 过的照样认）→ 仓内构建（同层目录名 `cambium` / `moongit` / `moonGit` 都试——克隆下来的目录可能还叫旧名）
  → PATH（`cambium` / `moongit` / `deepgit`）。
- **已装机器的迁移**（新文件 `sysint/LegacyPaths.kt`）：
  - 目录：`migratedDir(parent, "canopy")`——新目录不存在、旧目录在 → 整目录改名；搬不动（跨分区 / 权限）→
    继续用旧目录；两边都在 → 用新的、不删旧的。用在配置目录（`~/.config`）与缓存目录（`~/.cache`，WebView 原生包 400MB）。
  - 钥匙串：先按新属性 `application=canopy service=canopy-ai` 找，找不到按旧属性 `deepdolphin` / `deepdolphin-ai` 兜底；清除时新旧两条都清。
  - 自启：启动时 `migrateLegacyAutostart` 把 `deepdolphin.desktop` 换成指向当前客户端的 `canopy.desktop` 并删旧条目
    （旧条目的 Exec 指向旧安装路径，留着要么坏掉、要么与新的重复自启）；开发态入口不可用时不动它；
    设置里开关一动也会清旧条目。开关的初始状态把旧条目算作「开着」——它确实会在开机时拉起程序。
  - 实测：本机 `~/.config/deepDolphin`、`~/.cache/deepDolphin`（440M）都整体迁移，应用首启没有重新下载原生包，
    皮肤 / 语言设置原样生效。
- **字符串表是生成物**：`L10nTables.kt` 由 `gen_l10n.py` 从冻结的 mac 目录生成——手改会被下次生成覆盖。
  在生成器里加了品牌映射步骤（输入不变、输出用新名；`--check` 通过）。
- **引擎侧按「改名字，不改身份」**：数据目录 `~/.deepgit`、`DEEPGIT_*`、托管标记、`deepgit://`、库的 generator 值、
  schema 串都不动（上一轮改名定下的硬边界）。本仓第一版替换脚本把它们也改了（测试期望、根 README），
  发现后逐处改回；合并 fixture 里「deepDolphin 人工裁决」是改名前采集的样本，期望值跟样本走。
- **门禁**：277 passed / 0 failed（禁用缓存；新增 8 条迁移判据）。两份「置信度快照过期」回执 fixture 用新引擎重采。
- **边界（如实）**：旧包 `deepdolphin` 不会自动卸载（需手动 `apt remove deepdolphin`）；GitHub 两个仓库的库名与
  本地克隆目录名没改（仍是 `deepDolphin` / `moongit`，链接有效；改不改由维护者定）；macOS / Windows 上的
  迁移与打包未实跑（本机只有 Linux）；钥匙串兜底只有代码路径，没有在真钥匙串上实拍。

## 皮肤对比度批：主题令牌 × 文字颜色（2026-11-26）

用户在 Aqua 上实拍到标题与按钮文字读不出来：「注意 主题令牌和文字颜色之间的色彩冲突哦」。

- **先量再改**（`jvmTest` 里的 `SkinContrastAudit`，给了 `CANOPY_SKIN_AUDIT` 才跑，普通门禁不依赖显示器）：
  每套皮肤 × 7 个页面离屏渲染（不建窗口），按语义树取每段文字的位置，量**实际像素**的前景 / 背景对比度
  （前景取离背景最远的那一撮，节点外圈一圈不参与；禁用控件不量）。基线：14 套、5,700 多段文字里 **917 处冲突**（< 3:1）——aero 131、neo 125、aqua 120、
  clay 120、frutiger 116、minimal 99、liquid 91……**默认的 Fluent 也有 17 处**：主按钮是白字压亮蓝（1.7:1），
  「浅更新 / 深更新」是白字压浅绿 / 浅紫（2.0–2.1:1）。不只是浅色皮肤的事。
- **六类根因**（按发现的顺序，每一类都是先量出来 / 拍出来才找到的）：
  1. **粉彩当墨**：语义色身兼「容器填充」与「墨」两职，为暗色皮肤挑的粉彩在浅色皮肤上当文字只有 1–3:1。
  2. **排版档自带颜色**（根因里的根因）：`FluentTypography` 每一档都写了 `color = Palette.TextPrimary`，
     而 Material3 的 `Text` 取色顺序是「显式参数 → 样式里的颜色 → 容器给的内容色」——实心按钮给的
     `contentColor` 永远轮不到；而且这个对象是启动时建一次的常量，颜色**冻在默认皮肤的白字上**。
     Fluent 的主按钮白字压亮蓝、Aqua 的按钮白字压白底，是同一个 bug。`FluentButton` 的标签用
     `Type.body.copy(...)` 也会把主文字色带回来。
     ⚠️ 第一轮只改了调用点传的颜色，自以为修了；复测发现 Fluent 的 17 处**一处没动**，才追到这里。
  3. **代码覆写令牌的透明度**：`Palette.Card.copy(alpha = 0.55f)` 把「15% 的白」改成「55% 的白」，
     glass 的披露条成了一块亮灰板上放浅色字（2.1:1）。5 处。
  4. **画出来的表面 ≠ 算出来的表面**：按「底色 + 卡片透明度」算对比度，画面上其实还有——卡片顶部的光泽
     （aero 42% 的白）、背景材质的光斑、画在卡片底下又从半透明卡片里透上来的光晕（liquid：算出来亮度 0.08、
     画出来 0.16）、半透明卡片套卡片（aero 的筛选行三层，选中片白字 3.8:1）、半透明卡片的皮肤里半透明的
     菜单与弹窗。
  5. **图谱嵌入调色板写死暗色**：节点底 `#2e2e2e`、25% 的白描边……浅色皮肤的深色文字压在深色节点上。
  6. **菜单条画在皮肤材质之外**：菜单条的底是 `Palette.Sidebar`，玻璃 / Aero 的皮肤里它是半透明的一层，身后却是
     窗口默认的白底——整条是白的，「Canopy / 操作 / Cambium 帮助」白字压白底。皮肤批留下的，真窗口实拍才看到：
     离屏体检原先多包了一层 `SkinBackdrop`，正好把它盖住。现在材质由 `App` 根铺满整个窗口，体检与真窗口同构。
- **令牌层**（`Skin.kt`，换肤时一次算完；调用点不 if 皮肤）：
  - **文字级语义色** `Palette.AccentText / ShallowText / DeepText / AiText / YellowText / AmberText / RedText`：
    同色相、在全部静置面上 ≥ 4.5；暗色皮肤本来就达标，等于基色。共享原语的绘制点（图标、动作文字、胶囊）
    走 `ink(基色)`，调用方照旧传基色。
  - **表面模型** `textSurfaces`，四层、逐层放宽：静置面（底 / 侧栏 / 卡 / 凹槽 / hero / 菜单）三级文字按 AAA
    （主 7、次级 5.5、三级 4.5——次日收尾时提到 7 / 6 / 5，见「皮肤对比度批 · 收尾」）；光泽顶部与悬停 / 按下上主次级 ≥ 4.5、三级与语义墨 ≥ 3.0；悬停 + 光泽
    叠加处只保主 ≥ 4.5（这里要次级也 4.5 的话它得推成纯白，层级就塌了——liquid 实测主 13.2 / 次 13.2）。
    底取 `backdropBases`：背景材质的数据（`BackdropPaint`）画法与模型共用一份，够不着侧栏的光斑不算。
  - **光泽预算** `glossBudget`：光泽是装饰——不许把次级文字拉到 4.5 以下、不许把容器上的前景拉出保证值，
    预算不够就削弱光泽，不动文字。浅色皮肤（y2k / frutiger / aqua）全额保留；liquid 0.24 → 0.12、aero 0.22 → 0.10。
  - **新令牌**：`Well`（卡内凹槽：底色以 45% 盖在卡上）、`Inlay`（卡内容器：不透明皮肤 = 卡片色，
    半透明皮肤 = 透明、只留 hairline 描边）、`Popover / PopoverRaised`（浮层必须不透明：半透明皮肤取
    「卡片落在底色上的样子」）、`Material.hoverBrighten`（悬停的加法提亮量：半透明皮肤只加「卡 → 悬停卡」
    多出来的那一点）。
  - **前景与填充的保底**：`readableOn` 的分界亮度 0.55 → 0.19，并把光泽顶部算进去；实心按钮与 accent 按钮的
    悬停色朝**远离文字**的方向推（原来一律朝白推：深底白字的按钮一悬停就掉，skeuo 的红 4.5 → 3.7；neo / clay /
    aqua 的 accent 悬停色比 accent 还深，深字 5.4 → 4.1）；`solidReadable` 把落在「白字、深字都到不了 4.5」
    窄带里的语义色推一点（neo 的深更新 4.4 → 4.5）；`Composition12`（提交构成 12 色）对底 / 侧栏 / 卡 ≥ 3:1。
  - **绘制修正**：有色光晕只画卡片**之外**的一圈（`Path.op` 扣掉卡片自身）——不透明皮肤外观不变。
- **皮肤数据只动了读不出来的那几项**（都是守卫逼出来的）：aero 卡片 24% → 13% 的白（落在极光最亮处白字 5.4 → 7.5）、
  悬停 35% → 19%；glass / liquid 的悬停卡 +9~10% → +4~5% 的白。
- **守卫**（`SkinTest`，14 套逐套，失败一次报全）：四层下限；层级不塌（卡面上次级 ≤ 主 × 0.9、三级 ≤ 次级 × 0.9）；
  accent 与每个语义容器的本体 / 光泽顶部 / 悬停色上的前景；提交构成色 ≥ 3:1；Fluent 的文字级语义色等于基色、
  次级文字保持半透明；中段色保底只推一点点。
- **体检结果**（禁缓存重编；`/tmp/ui/skin-audit.sh`）：14 套 × 7 页、5,785 段文字 **0 冲突**（基线 917）；
  偏弱（3.0–4.5）合计 127 处，都是贴着 4.5 下限的三级小字（图例、时间戳、侧栏计数）——细笔画反锯齿后，
  量出来的前景总比真值淡一点。菜单条现在也在体检范围内，各皮肤最弱 4.8 以上。
  前后对比见 `docs/ui-cmp/21-skin-contrast-before-after.png`。
- **门禁**：282 passed / 0 failed / 1 skipped（禁用缓存；跳过的那一条就是体检本身）。
- **边界（如实）**：
  - 体检只量**静置态**；悬停 / 焦点 / 按下 / 弹层靠守卫里的表面模型，没有像素证据。
    （悬停与按下次日补了状态遍，见「皮肤对比度批 · 收尾」；焦点与弹层仍是模型。）
  - 体检画不到 WebView（图谱两页）：调色板已全部由令牌派生，真窗口实拍核对过 Aqua 与 Fluent 的代码图谱页
    （整页跟皮肤走，节点与右侧报告面板都读得出）。
  - 体检本身也错过一次：菜单条那一层就是它盖住的（见根因 6）——离屏渲染只能证明「画出来的东西」，
    证明不了「和真窗口是同一棵树」。
  - **外观有变化的皮肤**：liquid / aero 的光泽被预算削弱；glass / liquid / aero 的卡片不再被光晕与套叠冲亮
    （卡面更暗、字更清楚），卡内不再叠卡片、菜单与弹窗改为不透明；aero 的卡片明显变暗。这些是修冲突的代价，
    不是重设计——皮肤数据只在守卫不过时才动。
  - 光泽顶部与「悬停 + 光泽」叠加处，次级 / 三级文字的保底放宽到 3.0（见上）。
  - macOS / Windows 未实跑（本机只有 Linux）。

## 皮肤对比度批 · 收尾（2026-11-27）

用户：「把剩余的搞定，deepgit 不需要动」。

- **留下的决定，逐条落定**：
  - `~/.deepgit` 不动（用户定）。
  - GitHub 两个仓库与本地目录**不改名**：两个仓库都开着 GitHub Pages（`asdshuaishuai.github.io/deepDolphin/`、
    `…/moongit/`），GitHub 对仓库地址会跳转、对 **Pages 地址不跳转**——改名等于让已发布的文档站 404。
    命令名、包名、品牌都已和仓库名解耦（引擎发现 `cambium` / `moongit` / `moonGit` 都认），仓库名只是地址。
    本地目录名同理，不改。
  - 旧包 `deepdolphin`：本机**从未装过**（dpkg 里没有 `canopy` 也没有 `deepdolphin`，`/opt` 下都没有）——
    此前跑的都是解到 `/tmp` 的打包态。无事可做。
  - 系统级 deb 装不了（本机无 root，`sudo` 要密码）→ 新增免 root 安装（见下）。
- **三级文字下限 4.5 → 5.0，次级 5.5 → 6.0**：上一批把三级文字的静置面下限放在 4.5，浅色皮肤里整片三级小字
  贴着线，体检读出来 127 处偏弱。项目最早的口径是「三级文字在底 / 卡片 / 侧栏三种底色上都 ≥ 5:1」
  （`Design.kt` 的令牌注释），提回去；次级跟着到 6.0，保住层级阶梯（三级 ≤ 次级 × 0.9）。
  变化很小：Fluent 的三级文字仍是 53% 的白——最不利的面是 hero 顶部（4.98，差 0.02），推的是**透明度**而不是
  换成实色（`ensureContrast` 对半透明前景只把不透明度往上带，这是本轮新加的）；skeuo / vernacular 的三级
  4.5 → 5.0，neo / skeuo 的次级 +0.1；aqua 没动。
- **体检加状态遍，抓到第 7 类根因**（`CANOPY_SKIN_AUDIT_HOVER=1` / `CANOPY_SKIN_AUDIT_PRESSED=1`）：指针依次落到
  每个可点节点上（嵌套的一起进入悬停态），只量「被状态改变了对比度的文字」，每段留最差的一态；按下态按住不松手时量，
  再拖出界松开（不触发点击）。一上来就抓到：**Aqua 看板页悬停项目卡，整张卡的字被冲淡到 2.1–2.4**。
  `hoverLift` 的「整体提亮」是在内容**之后**叠一层加法混合，连文字一起加了 35% 的近白色；注释里写的
  「深色字微亮，两侧都不破」并不成立——暗色皮肤里白字被钳在纯白，所以一直没暴露，而用户用的正是浅色皮肤。
  改成卡片自己在 background 里做 Card → CardHover（与 GlassCard 一致，也在表面模型的抬升面里），
  `hoverLift` 不再提亮，上一批为此加的 `Material.hoverBrighten` 一并删掉。
  ⚠️ 过程里的两个坑：体检脚本写死了 15 分钟超时，状态遍全量要更久，第一次跑被掐掉、没出报告；状态切换的等待
  从固定 600ms 改成 `waitForIdle()`（测试时钟跟着真实时间走，动画在跑就不闲置）之后，每个目标 1 秒 → 0.2 秒。
- **免 root 安装**（`scripts/install-user.sh`）：把打好的 deb 装进用户目录——应用镜像 `~/.local/opt/canopy`
  （deb 里的 `/opt/canopy` 整个目录，jpackage 镜像可搬）、启动器 `~/.local/bin/canopy`（系统级有 `/opt/canopy`
  就走那份）、应用菜单项 `~/.local/share/applications/canopy.desktop`。和引擎在本机的装法（`~/.local/bin/cambium`）
  是一套路；配置、缓存、引擎发现与系统级安装完全一样，开机自启照常可用（入口是绝对路径的可执行文件）。
  `--uninstall` 只卸这三样。不碰 `/opt`、不跑 sudo、不动 `~/.config` 与 `~/.cache`。
- **结果**（禁缓存重编）：
  - 静置态：14 套 × 7 页、5,809 段文字 **0 冲突**；偏弱 65（上一批 127）——都是细笔画小字量出来偏淡，模型值 ≥ 5。
  - 状态遍（悬停 + 按下，每套 187 个悬停目标）：**14 套 0 冲突**。vernacular 一度报 6 处：是悬停弹出的提示条盖住了
    「深更新」按钮，量到的是露出来的按钮底色（品红）——像素采样确认提示条自己的字是 `#cccccc` 压 `#3434b4`（5.7）。
    量法补上「浮层出现时页面文字跳过、浮层里的文字单独量」后复核为 0。
  - 浮层（提示条，`PopoverRaised` 底 + 次级文字）：14 套各量 4 段，最弱 5.0（skeuo）。
  - 守卫补了两条显式的：菜单底上的主文字 ≥ 7、提示条底上的次级文字 ≥ 4.5。
  - 门禁 282 passed / 0 failed / 1 skipped（跳过的仍是体检本身）。已安装的构建经 `canopy` 启动器启动、aqua 仪表盘
    真窗口实拍正常。
- **边界（如实）**：
  - 状态遍里的「偏弱」合计 226 处，几乎都在**按下态**（按住不松手的一瞬），且是三级小字；悬停态本身没有冲突。
  - 弹出**菜单**仍只有模型（`Popover` 不透明 + 主文字 ≥ 7 的守卫），没有像素证据——打开菜单需要真实的点击，
    本轮桌面处于锁屏，没有发键鼠。另外这台机器的锁屏检测脚本（认 dde-lock 的窗口）在 KWin 会话里不准，
    以后一律按窗口取图、不从屏幕合成结果取。
  - 引擎仓库本轮没动（用户：「deepgit 不需要动」）：`feat/embed-fit`、`feat/sylva-brand` 仍未并入主线，
    v0.3.0 没有打标发版。

## 文字极性规则（2026-11-27）

用户：「文字颜色继续修正，正常情况下文字应该是黑色的；看主题色，主题色是浅色采用深色文字，反之」。

- **主文字不再取皮肤数据**：极性看**主题色**（页面底色 `bgBase`）——浅色主题纯黑 `#000000`，深色主题纯白 `#ffffff`
  （`Skin.kt` 的 `normalizeContrast`：`readableOn(skin.bgBase)` 再过静置面 AAA 保底）。皮肤数据里的 `textPrimary`
  是藏青 `#1a2433`、奶白 `#f2e8d8` 这类带色相的深 / 浅色，此前原样沿用。次级 / 三级文字不变（仍是各皮肤的弱化档）。
- **容器上的前景只有纯黑、纯白两种**（`readableOn`，原先是近黑 `#111111`）：两者对比度相等的分界亮度 ≈ 0.179，
  在这条线上都是 4.58——所以**任何容器色都配得出 ≥ 4.58 的前景**。近黑做前景时有一小段「两种都到不了 4.5」的中段，
  上一批为此加的 `solidReadable`（把中段色推一点）连同它的测试一并删除。
- **守卫**（`SkinTest`）：逐套断言主文字 = 纯黑或纯白且极性与底色一致（两边都有人，规则不是空转）；灰阶 0–255
  逐级 + 每套皮肤的语义色，容器前景 ≥ 4.5 且只能是纯黑 / 纯白。
- **结果**：浅色皮肤的主文字在卡面上的对比度普遍升到 17–21（neo 10.2 → 17.1、clay 9.9 → 19.0、frutiger 11.9 → 19.5、
  aqua 13.8 → 18.5）。体检：14 套 × 7 页 5,803 段文字 0 冲突，偏弱 65 → 32；门禁 283 passed / 0 failed / 1 skipped。

## 并入最新基线（2026-11-27）

用户：「从当前改名后为最新基线，两个仓库的分支全部并入最新分支」。客户端仓库的最新分支是 `next/cmp`。
逐个远端分支核对（`git rev-list --left-right --count next/cmp...<分支>`）：

| 远端分支 | 相对 next/cmp | 处置 |
|---|---|---|
| `main`、`dev`、`next/bui` | 已全部包含 | 无需操作 |
| `docs/agents-md-bootstrap` | 多 1 个提交（根 AGENTS.md 初稿 + .zcodeignore） | 干净并入（`7572233`） |
| `feat/deepin-engine-capabilities` | 多 222 个提交 | 并入（`bf6336c`） |
| `gh-pages` | 多 1 个提交（「deploy deepDolphin website」，532 个生成文件） | **不并**：GitHub Pages 的部署产物 |

- **根 AGENTS.md 重写成当前事实**（`178a613`）：docs 分支带进来的那份写于多平台并行时期（deepDolphin 是 moonGit 的多平台
  客户端、macos 是功能基准、引擎命令 `moongit`），与平台决定、品牌都对不上。保留它的章节结构（仓库形状 / Setup /
  Code style / Testing / 协作规约 / PR & commit / Security），内容按现状重写。
- **deepin 分支**：那是冻结的 deepin 端最后一次没并进主线的工作（EJ 系列修复、引擎能力对接）。并入后 `deepin/**`
  跟到该分支的最后一版（197 个文件），`linux/` 的 4 处小改（脚本与一处注释乱码修正）与 `.gitignore` 新增的 core 转储忽略一并收下。
  冲突只有两个 macOS 的 Swift 文件（`ArchPage` / `CodeGraphPage`）：该分支在更早时并过一次主线，带的是旧一版的图谱页；
  主线的 macOS 目录更新。**`macos/**` 整体保持 `next/cmp` 的原样**——该分支在 macos 下新增的三个无人引用的文件也不收
  （没有调用方、测试也没随迁）。`client/`（CMP）与 `docs/` 一个字节没动。
- **基线**：`next/cmp`。`main` 与 `dev` 没动（落后 284 / 318 个提交）——它们都是 `next/cmp` 的祖先，要跟上只需快进。
- 引擎仓库同步做了并入（`feat/sylva-brand` 并入 `origin/dev`），本机引擎二进制随之更新到合并后的构建
  （旧版备份 `~/.local/libexec/cambium/cambium.bin.bak-20261127-pre-merge`）。
- 验证：客户端门禁对着合并后的引擎跑，283 passed / 0 failed / 1 skipped。

## 置信度准确性批 · 客户端对齐（2026-11-27）

**背景**：引擎在同一日做了置信度准确性批（Cambium `feat/sylva-brand` @ `1ce5f44`，`AGENTS.md` 不变量 160）：
分数与各聚合表改在截断之前算——`findings` 最多列 400 条只限制清单，`score` / `byKind` / `penaltyByFile` 吃全部检出的条目；
四个 JSON 出口恒发 `findingsTotal` / `penaltyTotal` / `coverage`。本仓是契约的消费端，跟着对齐。

**取舍**
- **清单标题不再拿列出的条数冒充总数**：`findingsTotal > findings.size` 时写「疑点共 N 条 · 列出 M 条」；
  没截断照旧「疑点 N 条」；总量未知（旧引擎 / 旧快照，键缺失）维持「N 条」——不编数字，由既有的限流披露
  （`cmp.conf.capped*`）说明是子集。判定抽成纯函数 `findingsHeadline(total, shown)`，Composable 只渲染。
- **缺字段是 null 不是 0**（规约 6）：`findingsTotal` / `penaltyTotal` / `coverage` 在镜像里都是可空，旧 fixture
  （准确性批之前的引擎产出）照常解码。
- **`coverage` 只镜像、不另起一块**：它的内容与 `astNote` 是同一条信息的结构化版，页面上 `astNote` 已经原样展示在
  披露框里——同一句话说两遍是噪声。键先进镜像（客户端不必解析散文就能拿到覆盖面），单独的呈现等有真实需要再加。
- **不碰生成物**：新文案 `cmp.conf.findingsTotalN` 加在手写的 `L10nCmpKeys.kt`（四语言键集一致由 `L10nTest` 守），
  不动 `gen_l10n.py` 的产物。

**判据**（门禁禁缓存：`passed=286 skipped=1 failed=0`）
- `ContractTest.confidenceReportCarriesTotalsAndCoverage`：新 fixture `fixtures/confidence/confidence_totals.json`
  由本机引擎 `dendro check --json` 真跑落盘（隔离的 `DEEPGIT_HOME`，一个 3 函数的 Python 文件，ast-grep 在位）：
  总量 = 列出数、罚分 = 逐条权重之和、分数 = 100·20 / (20 + 52 / 1)、`coverage` 七键、全部文件走成语法树时
  `kindsUnavailable` 为空、`unresolved-call` 权重 3 与标签「未解析调用」。
- `ContractTest.confidenceReportWithoutTotalsDecodesWithNulls`：旧 fixture 解码得出来，三个新键是 null。
- `ConfidencePagesTest.findingsHeadlineDistinguishesTotalFromListed`：三种情形的标题文案。
- 负控（改坏 → 红 → 原样恢复）：摘掉 `findingsHeadline` 的截断判定 → `ConfidencePagesTest` 1 红；
  把 `coverage` 的序列化名改掉 → `ContractTest` 1 红。

**边界（如实）**
- `EngineMirrorDriftTest` 的真机两向对账跑的是**本机已安装**的引擎（本批装的是 `1ce5f44` 之后的构建）；
  用户机器上的引擎若仍是旧版，三个新键缺失 → 页面退回「疑点 N 条」+ 限流披露，不报错。
- 图谱两页内嵌的引擎产物（热力图的「置信度分析报告」侧栏）仍是引擎 HTML 自己的布局，本批没动；
  它的「共多少条」由产物自己从 `confidence` 块里读。

## 图谱两页的嵌入：占位跟着窗口走（2026-11-27）

**用户口径**：「两张并入客户端的图，右侧的 tab 需要进一步优化，太大了占位，需要让整张图和窗口大小进行动态调整」。
右侧带 tab 的那一栏（「置信度分析报告」）是引擎产物自己的布局——主体在引擎仓
（Cambium `6e5e428`，`AGENTS.md` 不变量 161）；本仓改的是页头与给产物的调色板。

**实拍先量**（已安装客户端 + 隔离的引擎数据目录，按窗口取图，1270×830 / 960×640 / 1680×980）：
- 产物：面板定宽 340、最小窗口下仍占 280（画布只剩一半）；架构图卡片里三行字叠在一起、命令条折成三行；
  泳道标签用填充色当文字色，浅色皮肤下读不出来；项目级疑点数写的是列出的 400 条，不是 849。
- 本仓页头：最小窗口下标题竖排成「架 / 构 / 图」——标题列是页头里唯一带 weight 的一列，
  回执胶囊（最宽 360）与三个按钮先把宽度占满。

**取舍**
- **标题按内容宽、永远单行**；会伸缩的是回执胶囊（`weight(1f, fill = false)`，最窄 52 = 图标 + 关闭），
  其次是副标题（内容区窄于 860dp 不显示）。回执胶囊原先固定宽度占位，现在吃剩余空间。
  页头高度仍不随回执有无而变（单行、胶囊定高）——WebView 不被状态变化挤动的约束不动。
- 紧凑阈值落在纯函数 `graphHeaderCompact(内容区宽)`：最小窗口 960 − 侧栏 230 = 730 进紧凑，默认窗口 1280 不进。
- 给产物的画布调色板加一份**文字级**的层色（`canvas.textCols` = AccentText / DeepText / ShallowText /
  YellowText / TextTertiary），`cols` 照旧给填充用；泳道标签在产物里改读 `textCols`。全部由令牌派生。
- 产物的面板收起 / 抽屉、卡片文字缩放、命令条收行都在引擎里做（同一份 HTML 也给独立打开与其它宿主用），
  本仓不注入第二套布局 CSS——两处各写一份必然漂移。

**判据**
- `GraphHeaderLayoutTest`（离屏 Compose 场景，量的是真的布局结果）：730dp 带回执——标题宽 ≥ 48dp 且副标题节点
  不存在；730dp 无回执——三个按钮都在（回执块的花括号曾把按钮吞进去：`status` 为 null 时按钮整排消失）；
  1040dp——副标题存在。
- `GraphParseTest.graphHeaderGoesCompactBelowTheThreshold`：阈值本身不进紧凑。
- `GraphParseTest.archCanvasPaletteCarriesTextLevelLaneColors`：嵌入脚本带 `textCols`，`cols` 照旧。
- 真窗口实拍归档 `docs/ui-cmp/22–24`（按窗口取图；已安装客户端 + 隔离的 `DEEPGIT_HOME`，不写用户的引擎数据）。

**边界（如实）**
- 实拍用的客户端是打出来的包解在临时目录（`/tmp/deb-canopy`）里跑的，不是 `~/.local/opt/canopy`——
  装机版在本批提交后才重装（`scripts/install-user.sh`）。
- 产物里「收起 / 抽屉 / 点节点展开」的交互态没法在真窗口里不发键鼠地验证：在浏览器里加载客户端缓存的
  那份已注入嵌入脚本的产物，按内容区尺寸设视口逐项核对（引擎仓 `AGENTS.md` 不变量 161 记了方法）。

## ui-ux-pro-max 细节打磨批（2026-11-27）

**用户口径**：「在 home 目录下找到 ui-ux-pro 这个 skill，载入它，继续进行 ui/ux 的细节，布局，交互以及各组件文字的
尺寸大小，颜色，排列嵌套的方式，阴影，动画效果等」。
skill 位置 `/home/superShuai/code/NaN/.agents/skills/ui-ux-pro-max/`（`SKILL.md` + `data/*.csv` + `references/`），
不在 Skill 工具的可用列表里——按文件载入，走它的 `scripts/search.py`。

**检索结果如实记**：`--design-system` 两次（"developer tool project dashboard desktop dense" /
"productivity project management desktop app"）返回的 pattern 都是落地页（FAQ / Product Demo）、style 是
Dark Mode (OLED) / Flat Design——**没对上产品类型**（Canopy 是带 14 套皮肤的 Fluent 桌面工具，视觉风格是用户定的，
不由 skill 另起一套）。按 skill 自己的规则：两次都对不上就明说「没有验证过的匹配」，只采用内置的优先级表与
`references/quick-reference.md` 的 119 条规则做审计清单。`--domain ux` 的逐条检索与规则集一致（active-state /
reduced-motion / hover / empty-states / line-height / number-tabular 等）。

**审计**（六个页面真窗口实拍 1270×830：仪表盘 / 看板 / 里程碑 / 代码置信度 / 补丁体检 / 设置，Aqua 皮肤；按十个类别过）

| 类别（skill 优先级） | 看到了什么 | 处置 |
|---|---|---|
| 1 无障碍 · CRITICAL | 文字对比度由离屏体检守卫（本轮新组件再量一遍：三页 × 三皮肤，静置 + 悬停 0 冲突）；键盘焦点环既有 | 量，无新问题 |
| 2 触控与交互 | 桌面鼠标场景；最小命中区 = 控件高（28–32） | 不动 |
| 4 风格 · `primary-action` / `elevation-consistent` | 每页右上「浅更新 / 深更新」是语义色实心按钮（绿 / 紫），与各页的主按钮并存 | **不动**：mac 基准的全局动作，语义色（浅 = 绿、深 = 紫）是既有契约 |
| 5 布局 · `progressive-disclosure` / `line-length` / `whitespace-balance` | 置信度页：分数与清单之间铺着四段小字（≈150px），「语义边界」一句横跨 1000px；看板三个空列各占 ≈92px | **改**：见下 |
| 6 排版 · `readable-font-size`（正文不小于 12px）/ `number-tabular` | `Type.micro` 是 11sp + 第三级文字色，低于档位注释自己写的 Fluent ramp（caption 12）；KPI 数字是比例数字 | **改**：micro → 12sp；display 档开 tnum |
| 6 颜色 · `color-semantic` / `color-not-only` | 全部走令牌；状态都是「色点 + 文字」 | 既有纪律，无新问题 |
| 7 动效 · `state-transition` / `motion-consistency` | `Motion.normal = 150ms / slow = 300ms`，在规则区间内；新加的 chip 悬停走同一节奏 | 既有纪律 |
| 8 表单与反馈 · `empty-states` | 看板空列、里程碑空态都有「说明 + 下一步」 | 看板空列收紧（下）；里程碑空态里的「全部」链接位置略怪，**没动**（它是筛选行，语义正确） |
| 9 导航 · `nav-state-active` / `nav-label-icon` | 侧栏激活项有色条 + 底色，图标 + 文字 | 既有纪律 |
| 10 图表 · `number-tabular` / `legend-visible` | 图例都在卡片内；语言分布数值右对齐 | display 档 tnum 覆盖 |

**改了什么**
- **置信度页重排**（`ConfidencePages.kt`）：
  - 「覆盖与口径」摘要一行常驻：图标 + `coverage` 的几段（语法树 N 文件 · 词法 N 文件 · 批失败 N / N · 缺 N 类信号）
    + 限流提示；打了折的覆盖（没用上语法树 / 批失败 / 缺类别）用警示色。点开才看引擎说明全文与语义边界（限高 220px、
    内部滚动；行宽收到 720dp）。**披露没有静默**：摘要本身就是披露，全文一字不改。旧引擎没有 `coverage` 时写
    「覆盖面未披露（旧版引擎）」，缺键写「?」。
  - **按类别筛**：清单是引擎的全序（权重↓ → 文件↑ → 行↑），一类几百条连成一片；加一行可换行的 chip
    （「全部 N」+ 每类的标签与全量计数），单选，再点一次回到全部；换了报告之后选中的类别不存在了自动回全部。
  - 疑点行的类别显示引擎给的本地化标签（「孤儿符号」），不再显示 `orphan`。
- **看板空列**（`BoardView.kt`）：判据与「没有项目落在这列」并成一行（micro，最多两行）。判据仍常驻。
- **字号档**（`Design.kt`）：`Type.micro` 11 → 12sp（行高 14 → 15）；`Type.display` 开 `fontFeatureSettings = "tnum"`。

**判据**
- `ConfidencePagesTest` 五条：覆盖面各段与「?」、打折与否的六种情形、按类筛保留引擎全序、类别消失回全部、标签回退。
- `TypeScaleTest` 两条：最小字号 ≥ 12sp；display 档是等宽数字。
- 负控两项真红：`effectiveKindFilter` 恒返回原值 → 1 红；`coverageIsDegraded` 忽略缺失类别 → 1 红。
- 离屏体检（`CANOPY_SKIN_AUDIT_PAGES=confidence,board,dashboard`，Aqua / Fluent / Neo，静置 + 悬停）：
  每套 225 段文字 0 冲突；悬停遍偏弱的几段都是既有的（Fluent 仪表盘卡片悬停 4.2–4.3、Neo 的「进入管控 →」、
  Aqua 看板计数胶囊），没有一段来自新组件。
- 真窗口实拍 `docs/ui-cmp/25–26`。

**没动的（如实）**：顶栏三个实心按钮并存（全局动作，mac 基准）；里程碑空态里的「全部」链接；卡片阴影是皮肤定的
（Aqua 的投影偏重）；补丁体检页的项目下拉没有可见标签（占位文字「选择项目」）——这几项要么是既有契约、要么改动面
大，留给下一轮按用户意见定。

## 架构图铺开批（2026-11-27，改动全在引擎，本仓零代码改动）

**用户口径**：「图可以其实在分散一些，我看现在架构图很都堆叠在一起了，分散是指可以扩散一些为止」。

**实拍先量**（已安装客户端 + 隔离的引擎数据目录，按窗口取图，1270×830 / 960×640 / 1680×980）：
- 泳道按定稿宽度（标签列 + 列数 × 卡槽 = 682 单位）居中一列：1680×980 的画布有 1446px 宽，图只占 625px；
  卡片贴着标签列左对齐；连线从卡片侧面中点进出，dendro→flow 这类跨层线压在 cli、flow 卡片后面。
- 根因在引擎产物的嵌入布局，不在本仓的容器、页头或调色板。

**取舍**
- 主体在引擎仓做（Cambium `298a3bd`，引擎 `AGENTS.md` 不变量 162）：泳道横向铺到可用宽度（纵向是瓶颈时铺开，
  最宽到卡槽名义宽的 1.6 倍）；卡片在泳道里对称分布，偶数张时正中留出连线的水道；连线从卡片底 / 顶边进出、
  跨行时沿卡片之间的空档绕行；架构级与职责视图同一套；独立打开的画面不变。
- 本仓不注入第二套布局 CSS，也不在 WebView 外面再排一次卡片：同一份 HTML 也给独立打开与其它宿主用，
  产物自己按视口取景，容器尺寸与 `graphEmbedCanvas()` 都不用动。
- 验证照旧分三层：真窗口实拍（按窗口取图，证明和真窗口是同一棵树）；浏览器里加载已注入嵌入脚本的产物看观感、
  试参数；把**真实产物**的驱动脚本放进 Node 沙箱量几何（两个样例仓库 × 两个视图 × 五个尺寸）：
  卡片都在泳道内且互不重叠、阅读序不变、每条连线 60 个采样点落在卡片内的个数 = 0、走廊离卡片 ≥ 18。

**判据**：全在引擎仓——结构断言 3 条、负控 6 项真红、全量 779 条 776 过（3 条已知 Linux 环境红）。
本仓没有代码改动，门禁沿用上一批的 `passed=298 skipped=1 failed=0`（未重跑）。

**实拍结果**（`docs/ui-cmp/27–29`，上：改动前，下：改动后）
- 1270×830（画布 1036×672）：泳道铺满画布宽度，卡片 160×52 → 172×56px；15 条连线里 8 条跨行的全部绕开了卡片。
- 1680×980：卡片 207×68 → 220×72px，泳道仍占满 1390px。
- 960×640（最小窗口）：同样铺开、连线不再压卡片，但卡片只有 112×37px（只显示模块名）——五层泳道挤在
  355px 高的可用区域里，是画布尺寸决定的。铺开解决的是「挤成一团 + 线压卡片」，不是「画布太小」。

**边界（如实）**
- 引擎升级后，已登记项目的架构图要自愈一次才有新布局：旧引擎写的 `arch.json` 没有 `geo.emb*`，
  `render arch` 会先重建再渲染（引擎侧 `archPayloadShapeCurrent`）。隔离库里登记过的仓库实测走通了这条自愈。
- 职责视图的泳道标签在浅色皮肤下对比度不足（量过：1.44–2.20:1，文字要 4.5:1）——标签用的是产物自带的暗色系
  角色色，本仓只给产物覆盖了层配色（`cols` / `textCols`），没有角色文字色可覆盖。已在引擎仓 `docs/ROADMAP.md`
  I.18 记下；修法是本仓按令牌再给一份角色文字色（与 `textCols` 同法），留待下一批。
- 本批的一个失误：查 `render arch` 的参数时直接调用了已安装的引擎（没带隔离的 `DEEPGIT_HOME`），它按真实的
  `~/.deepgit` 重绘了一次 `engine` 项目的架构图缓存（`store/p_f80de38f6095/render/arch.html`——只是渲染缓存，
  由当时的引擎重新生成；registry 与 arch.json 没有变，不涉及文档 / 进度数据）。之后所有引擎调用都走
  `/tmp/ui/dg/eng.sh`（强制隔离数据目录）。

## 职责视图标签的对比度（2026-11-28）

**用户口径**：上一批收尾时报了「职责视图的泳道标签在浅色皮肤下对比度 1.44–2.20:1」，用户：「直接修复了」。

**根因**：角色名直接拿产物自带的 `ROLEPAL.dark` 角色色当文字色。嵌入时页面以暗色为基座、只覆盖宿主给的键，
客户端只给了层配色（`cols` / `textCols`），没有角色色可覆盖——独立打开没问题，嵌进浅色皮肤的客户端才读不出来。

**取舍**
- **角色色改由客户端令牌给，分两份**：`canvas.roleCols`（填充级：泳道底、卡片侧条、连线渐变）与
  `canvas.roleTextCols`（文字级：标签）。按引擎角色色相的次序换成令牌：品红→Red、蓝→Accent、绿→Shallow、
  琥珀→Yellow、紫→Deep；剩下两档引擎是深浅两种灰，令牌里没有能分两档的同色相中性色——「支撑」用
  还没出场的 Amber，「其他」用中性灰。不用 Ai（青在产品里是 AI 通道的专色）。
- 引擎驱动 `roleColor()` / `roleText()` 有宿主值就用、没有回落自带色板——独立打开与老宿主不变（引擎 `cd4e3c1`）。
- **标签的墨按它真正落的那块面保底**（`laneInk`）：换肤保底只认皮肤自己的表面与 0.16 的同色 chip，
  不认这块带色的画布——量下来 14 套皮肤 × 12 条泳道里有 2 条差一点点（新拟态的基础层 4.47、极简的一条 4.49）。
  做法 = 同一色相的文字级（`ink`）+ 以自己那条泳道（画布渐变两端压上 0.07 / 0.10 的本色）为表面保底 4.5，
  已达标就原样返回。层标签与角色标签走同一个函数，不是各调各的。

**判据**
- `GraphParseTest.laneLabelsStayReadableOnTheirOwnLaneAcrossSkins`：14 套皮肤逐套换，断言嵌入配置里两份颜色
  = 现读的令牌（不是换肤前冻住的），每条泳道标签压在自己泳道上 ≥ 4.5:1，且颜色确实是从文字级派生
  （本来就达标的不许被改动）。负控：去掉按泳道保底 → 新拟态基础层 4.47 红；角色标签直接用填充色 → 红。
- 门禁（禁缓存）：`passed=299 skipped=1 failed=0`。
- 引擎侧：结构断言进 `testArchEmbedSpreadsLanesAndRoutesEdges`，负控 2 项红（角色名改回填充色 / 角色色不读宿主）；
  全量 779 条里 775 过 + 1 条负载假红单跑即绿，剩 3 条是已知的 Linux 环境红。`RENDER_TEMPLATE` 6 → 7。

**实拍与量测**
- 真窗口（`docs/ui-cmp/31`，已安装的客户端 + 已安装的引擎，隔离的引擎数据目录）：职责视图四个标签都是深墨色。
  职责视图没有深链参数，真窗口里又不能发键鼠——做法是往**隔离库**里那份 `render/arch.html` 的 `<body>` 后面
  插一行 `location.hash = "#view=role"`（产物驱动启动时读这个 hash），截完把隔离库的产物恢复原样。
- 浏览器里加载客户端缓存的那份已注入嵌入脚本的产物（`docs/ui-cmp/30`，上：去掉两个角色键 = 改动前，下：改动后），
  从 canvas 像素上量：标签框里最深的像素对泳道底是 5.43 / 5.03 / 5.02 / 4.87:1（抗锯齿会把字色冲淡，
  这是不低于真实值的下界）。

**边界（如实）**
- 深链进入职责视图时，命令条上的「分层总览」chip 仍显示为选中（chip 的选中态只跟点击走，不跟启动时的 hash）。
  这是产物既有的小毛病，正常点 chip 进入时不出现；没在这批里改。
- 角色色里的 Amber / Yellow 是相近的暖色（「支撑」与「数据」），在泳道顺序上隔着「存储」，实际看能分开；
  没有再做色觉缺陷的区分度验证。

## 应用图标：「森林谱系」（2026-11-28）

**用户口径**：「给他制作一个 icon，别用 Kotlin 的那个，根据新的项目名称去制作，就是这个森林谱系」。

**现状先量**：图标流水线（`assets/icon/`：一张母版 → `make-icons.py` 导出全平台产物 →
`check-icon.sh` 判据「全平台同一套」）2026-10 就建好了，母版却还是旧品牌的鲨鱼标记；
CMP 客户端 `Window(...)` 根本没传 `icon` ——窗口 / 任务栏一直是 Compose 自带的 Kotlin 图标，
安装器桌面项指向的 512 图也是打包器从旧产物拷的。「别用 Kotlin 那个」没兑现的原因不在资产，
在**接线**。

**设计（森林谱系）**：`mark.svg`（矢量真相源，1024 满幅圆角方底）——地面一根主干分两枝（第一代），
两枝再各向上分出一棵、并向顶冠汇合（第二代）；五个圆是树冠也是节点，整体是一棵树、拆开是一张图。
方底四圈淡环从主干根扩散（谱系 / 年轮），顶冠上方一团光。只用渐变 / 透明度 / 叠加，不用滤镜——
librsvg 与 cairosvg 对滤镜支持不同，母版要在两台机器上渲染出同一张图。`mark-small.svg`（≤32px 档）：
五个圆冠缩到 32px 以下粘成一团，简化成三圆冠、线加粗；方底 / 配色 / 圆角与主母版一致。

**取舍**
- **接线补齐，资产不复制**：`build.gradle.kts` 把 `out/png/256.png` 在 `jvmProcessResources`
  并进资源（`Window(icon = painterResource("icon/canopy.png"))`），`nativeDistributions`
  三平台 `iconFile` 全部指向 `out/`；`client/src` 里不许出现图标拷贝（判据 + `IconAssetTest`）。
- **生成器跟上**：SVG 母版栅格化按 cairosvg → rsvg-convert → ImageMagick 找；≤32px 档自动换
  小母版；`.icns` 没有 iconutil 就按容器格式直接写（PNG 载荷十档，两平台产出同一组档位）——
  以前非 macOS 直接跳过，`out/macos/AppIcon.icns` 永远是上一台 Mac 留下的旧图，「同一套」
  在这一份上破了。`--check` 从「只查尺寸」升级为「逐档与母版合成实底后逐像素比」。
- **deepin 冻结**：生成器默认不再生成 / 校验 `deepin/data/icons`（`--with-deepin` 显式开），
  那里保留仓内已入库的旧品牌文件——冻结目录不投入新工作。

**判据**：`check-icon.sh` 重写（第 1–7 步判红：无第二份拷贝 / 母版满幅 / 产物逐像素跟母版 /
窗口 icon 传了 / 资源与包图标取自 out/ / 桌面项指向打包器拷贝 / 生成器不手绘；第 8 步冻结端只报不判红）；
`IconAssetTest` 3 条（资源与 out/ 同一份字节、256px 上钉住「森林谱系」的几何与配色、资源目录无拷贝）。
负控 5 项真红（窗口 icon 摘掉 / 资源源文件改错 / 256 档换成旧图 / 小尺寸不认小母版 / icns 档位按位置配对写错——
最后这条是实打实的 bug，`--check` 的逐档比对当场抓的）。门禁（禁缓存）`passed=302 skipped=1 failed=0`。

**实证**：deb 里 `lib/canopy.png` 与 `out/png/512.png` 像素相同；装机版桌面项指向它；
真窗口 `_NET_WM_ICON`（96px，AWT 缩放）与母版 LANCZOS 缩放平均差 1.8/255（噪声级）——
任务栏上已是「森林谱系」。实拍与对照归档 `docs/ui-cmp/32`。

