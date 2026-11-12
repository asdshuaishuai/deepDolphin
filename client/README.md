# deepDolphin · cross-platform client (BUI)

moonGit 引擎的**跨平台桌面客户端**（macOS / Windows / Linux）。
本目录是客户端重置后的唯一实现——旧的 macOS SwiftUI 客户端留在本分支之外
（`macos/` 等目录在旧分支上，历史不丢）。

## 技术栈

| 层 | 选型 | 理由 |
|---|---|---|
| UI 运行时 | [BUI](https://github.com/ppmpreetham/BUI)（Blender UI 解耦版，Rust 绑定） | 原生窗口（Win32 / Cocoa / X11）+ **HTML + CSS 直接绘制**（flex/grid/渐变/圆角/hover），一套代码三平台；idle 0% CPU 的 damage rendering |
| 语言 | Rust 1.88+ | 静态二进制、进程管理、跨平台 |
| 引擎通道 | `moongit <命令> --json` 子进程 | 引擎既有传输层纪律：只在本机进程之间通信，无 HTTP |

> ⚠️ **BUI 是 GPL-3.0-or-later**：本客户端随之采用 GPL-3.0-or-later。
> 引擎（moonGit）是独立进程，不受影响。

## 设计语言：macOS × Windows 11

深海底色 + 蓝色强调，两套桌面哲学的融合：

- **macOS 的克制**：8px 节奏网格、13px 正文 / 20px 标题、弱分割线
  （rgba 6–10%），分组靠留白而不是边框。
- **Windows 11 的层次（Mica 式）**：页面底 → 侧栏 → 卡片三级明度差，
  半透明表面 + 1px 高光描边 + 12–14px 圆角；hover 只改边框与底色，不做花哨位移。
- 调色板与组件类全在 `src/design.rs` 的单一注入点（`.card` / `.btn` /
  `.chip` / `.badge` …）；视图里只用类名。
- 字体：**HarmonyOS Sans SC** 编进二进制（`add_font`）——BUI 没有逐字形
  回退，必须显式绑定含 CJK 的字面，中文才不会变豆腐块。

## 构建与运行

```sh
cd client
cargo build                 # 需要 CMake + C 编译器（BUI 的 C kit 用 cmake 构建）

# 引擎发现顺序：MOONGIT_BIN / DEEPGIT_BIN → 可执行文件旁的 moongit/deepgit
#                → PATH 上的 moongit → deepgit
MOONGIT_BIN=/path/to/moonGit/target/release/bin/main cargo run

# 深链（与旧客户端同形）
cargo run -- --project d2note
cargo run -- --section milestones
```

跨平台构建：

- **Windows**：Rust 默认 MSVC 工具链 + Visual Studio Build Tools + CMake；
  子进程已带 `CREATE_NO_WINDOW`（GUI 应用不弹控制台）。
- **macOS**：Cocoa 宿主（BUI 官方标注：新宿主，需主线程）。
- **Linux**：BUI 需要 X11 开发头（`libx11-dev`）。

发布形态（后续）：把 `moongit` 可执行文件放在客户端同目录（或
`MOONGIT_BIN` 指向它），客户端自动发现。

## 目录

```
client/
  src/main.rs            入口：字体注册 / 首屏预取 / 窗口 / 深链
  src/app.rs             状态（AppState）与根视图；同步动作与反馈
  src/engine.rs          引擎桥：可执行文件发现 + CLI 调用 + 产物探测 + 外部打开
  src/models.rs          引擎 JSON 契约的只读镜像（缺键一律 Option，不编默认值）
  src/design.rs          设计系统：全局样式表（唯一注入点）+ 设计语言说明
  src/views/             sidebar / dashboard / project / milestones
  assets/fonts/          HarmonyOS Sans SC（Regular/Medium）+ 字体许可
```

## 已知边界（v0 显式取舍）

1. **同步引擎调用**：BUI 0.5 没有 spawn/定时器，动作在 UI 线程阻塞完成
   （首屏数据在开窗前预取，进去即有）。单命令实测 100ms–1.3s；后续
   BUI 提供异步入口后改后台执行。
2. **图谱交付物用系统浏览器打开**：BUI 没有 JS 引擎/webview，而引擎的
   图谱正身是零依赖单文件交互 HTML——`render check` 探测存在性后交给
   系统浏览器渲染；未生成时卡片给出 `moongit skill graph` 的生成指引
   （生成由 AI agent 驱动，符合引擎的 LLM 编排纪律）。
3. **表单控件是 Blender 原生绘制**（输入框等）：BUI 的 form controls
   由 Blender 控件库画，与自定义 CSS 主题存在观感差；BUI 上游在演进，
   换肤能力跟上后统一。
4. **无无障碍/输入法**：BUI 上游已知限制（README「known limitations」）。
5. 里程碑/图谱等页面按需迭代；本 v0 已覆盖仪表盘 / 仓库管控 / 里程碑 /
   git 白名单操作 / 图谱入口的完整闭环。

## 许可

- 本客户端：GPL-3.0-or-later（因 BUI）。
- **HarmonyOS Sans Fonts**：随包嵌入（`assets/fonts/`），依 HarmonyOS Sans
  Fonts License Agreement 使用——*HarmonyOS Sans Fonts are used in this
  product. Copyright 2021 Huawei Device Co., Ltd.* 许可全文见
  `assets/fonts/LICENSE.txt`（分发时不得删除）。
