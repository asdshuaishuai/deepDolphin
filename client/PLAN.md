# deepDolphin CMP 客户端 · 全量能力复刻计划（执行手册）

> 分支：`next/cmp`（骨架已验证：Compose 真窗口 + 引擎探活 moonGit 0.2.0 实测通过）。
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

- 引擎：`~/code/moonGit/target/release/bin/main` 已构建；PATH 上有 moongit 0.2.0。
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

**终验（2026-11-23）**：
- 判据门禁绿：`scripts/build.sh --test` → `CMPTEST_SUMMARY passed=45 skipped=0 failed=0`。
- **真窗口冒烟：异常，未通过**——运行时观感（aurora/hover/WebView 排版）未可视核验；
  KCEF 首跑需联网从 GitHub 下载 JCEF 二进制（缓存里已有 kcef/jcef jar，二进制是运行时
  落盘），不可用时按设计回退纯文本并在界面标注原因。复跑排障后再收口。

**如实未落地 / 已知边界（截至 2026-11-23）**：
- AI 设置无 models-dev 目录选择器；C5 整合更新流无代码（见批 3 标注）。
- 通知/自启的界面开关未接线；SystemTray 未实现（见批 4 标注）。
- 看板 fixture 口径差异（`summary.branchCount=8` vs 分支行数 7、`repoBranchCount=2` 只返回
  1 条）按判据只在页头披露「引擎返回 M/N」，不代引擎重算总数；merged 列无 fixture 样本
  （口径取自 macos 基准 StatusColor），引擎新口径由「口径未知」列兜底。
- Markdown 渲染边界：下划线强调、图片、Setext 标题不支持（宁缺勿错，MarkdownHtml.kt
  头注释有边界声明）；KCEF 每进程只尝试装载一次，彻底重试需重启应用。
- Main.kt 侧栏底部「判据 11 条」是批 1 遗留陈旧文案（现 45），属代码改动，随下次代码批一并修。
- MilestonesView.kt:32 模态遮罩 `Color(0x88000000)` 是遗留内联色值（此前里程碑批产物，未动）。

## 红线（每批必守）

1. 引擎 JSON 键名是唯一耦合面——以 fixtures 与 archive/bui 的 models.rs 为准，不许发明键。
2. Linux 通用端：不引入 DDE/deepin 专属能力；集成一律 freedesktop 通用机制。
3. 失败诚实：给原因与下一步，不静默、不假装成功。
4. 判据只增不减；每批一个 commit（`feat(cmp): …`），编译+判据+真窗口截图同 commit。
5. 参考实现只抄能力语义，UI 按 Compose 地道写法（别把 Rust/Swift 的模式硬搬）。
