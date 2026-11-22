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

### 批 2 · 里程碑 + 详情 + git（C9/C3/C8）
- 里程碑 CRUD（tag 自动达成/date/desc）+ 列表页。
- 项目详情（脉搏/提交构成/分支/日志/文档四态，长文区 webview 或 Compose 渲染）。
- git 白名单六操作（pull/push/commit/stash/unstash/fetch）+ 结果输出区；破坏动作过确认。

### 批 3 · AI 全家桶（C7/C6/C5）
- C7 设置：provider/model 目录选择（models-dev 快照，assets/models/models-dev.json 注入）、
  key 存 libsecret（secret-tool 子进程）→ 0600 文件兜底、测试连通。
- C6 助手：agent 工具循环（≤4 轮，工具集与 mac/BUI 一致）、对话页（**webview 渲染 Markdown**，
  webview 能力在此落地）、停止按钮（真杀进程）。
- C5 整合更新：更新+AI 摘要、项目/群说明、定时更新（小时档）+ 简报通知。

### 批 4 · 系统集成 + 分发（C10/C11）
- C10：notify-send 通知、XDG 自启（Exec 绝对路径——吸取 run.sh 教训）、
  深链 --section/--project、SystemTray 常驻速览（java.awt.SystemTray，Linux 复核）。
- 分发：compose desktop nativeDistributions（jpackage，Linux deb/-appimage 任一）。
- 终验：全判据 + 真窗口截图全套（对位 archive/bui 的 docs/ui/after 口径）+ 打包安装冒烟。

## 红线（每批必守）

1. 引擎 JSON 键名是唯一耦合面——以 fixtures 与 archive/bui 的 models.rs 为准，不许发明键。
2. Linux 通用端：不引入 DDE/deepin 专属能力；集成一律 freedesktop 通用机制。
3. 失败诚实：给原因与下一步，不静默、不假装成功。
4. 判据只增不减；每批一个 commit（`feat(cmp): …`），编译+判据+真窗口截图同 commit。
5. 参考实现只抄能力语义，UI 按 Compose 地道写法（别把 Rust/Swift 的模式硬搬）。
