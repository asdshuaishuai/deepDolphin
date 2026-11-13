# deepDolphin BUI 客户端 · v1 实现方案

> 目标：在 `deepDolphin/client` 现有 v0 骨架上，做一版**能一次落地**的完整客户端：
> 原 macOS 客户端的核心能力 + Fluent 风格 + 磁贴式布局 + 毛玻璃质感 + 更强的交互。
> 四个功能开发者（dashboard / project / boardconf / sidebarscan）在 core 冻结 API 后并行开工，
> 文件组互不重叠；core 负责设计系统、契约、线程/取消、AI 与最终集成。

---

## 0. 一句话结论

**用「单窗口 + 12 列磁贴 + 4 处亚克力玻璃 + 后台 Job（真杀进程的取消）+ 统一的只读模型/错误载荷」重写客户端。**
所有引擎访问仍然只有一条路：`moongit <命令> --json` 子进程。没有 HTTP、没有 FFI、没有第二份事实来源。

---

## 1. 事实基线（本次实跑，2026-11-12）

### 1.1 已跑命令（引擎 = `moonGit/target/release/bin/main`）

| 命令 | 结果 |
|---|---|
| `status --json --quiet` | rc=0，17 个项目，顶层 `projects/summary/language`；单项目同 envelope |
| `dashboard --json` | rc=0，顶层 `projects/work/languages/languagesTruncated/languagesTopCut/languagesFailed/languagesFailedReasons/milestones/activeProjects/fetchedAt` |
| `milestone list --json` | rc=0，顶层 `milestones/storeHealth/readCount/orphaned/excludedDisabled`；条目 17 键 |
| `docs deeporca-site --json` | rc=0，`project/docs[{project,file,content}]/unreadable[]` |
| `journal deeporca-site --json` | rc=0，`entries/limit/branches/projects/unparsableLines/windowExhausted/branchWindowExhausted` |
| `git status deeporca-site --json` | rc=0，`{op,ok,output:"<内层 JSON 字符串>",project}`；内层 `{ok,entries[{xy,file,kind}],total}` |
| `git commit alpha --message … --paths a.txt --json`（沙箱） | rc=0，`{op,ok,output:"[main …] …",project}` |
| `render check index/arch <p> --json` | rc=0，`{ok,artifact,exists,path}`；arch 不存在时 `exists:false,path:""` |
| `scan <tmp> --depth 3 --json`（沙箱） | rc=0，`candidates/found/added/existing/dirsVisited/truncated/depthCapped/unreadable/depth` |
| `add <tmp> --name betaX --json`（沙箱） | rc=0，返回注册表条目 `id/name/path/kind/remote/addedAt/tags/disabled` |
| `remove betaX --json`（沙箱） | rc=0，返回被移除条目；第二次 rc=1，stderr 人话 |
| `update betaX --json --quiet`（沙箱） | rc=0，`ok/mode/projectId/project/provider/providerLabel/branchCount/repoBranchCount/branchCountTruncated/commitCount/docs[{file,changed,created,backup}]/journalEntry/at` |
| `deep betaX --json --quiet`（沙箱） | rc=0，同上但 `mode:"deep"`，另有 `highlights`，无顶层 `branchCount/commitCount` |
| `milestone add/done/reopen/drop/remove`（沙箱） | add：`{project,milestone,created}`；动作：`{project,milestone,requested,status,applied}`；remove：`{project,milestone,removed}` |
| `graph confidence d2note --json` | rc=0，`root/score/dimensions/penaltyByFile/findings/astUsed/astNote/byKind/cappedKind/cappedTotal/filesAnalyzed/semantics` |
| `graph patchconf d2note --patch <diff> --json` | rc=0，`schema/overall/signals{S1..S10,可 null}/entities/uncertain/diagnostics` |
| `graph patchconf --merge <a.json> <b.json> --json` | rc=0，`schema/overall/signals/entities/alerts/sources/diagnostics` |
| `graph patchconf <p> --patch <diff> --skill` | rc=0，纯文本 Skill 定义 |
| `context --budget 400 --json` | rc=0，`{scope,budget,context}`；预算被夹到最小 500 |
| `tools --json` | rc=0，`{tools:[{name,description,params}],note}` |
| `list --json` | rc=0，**裸数组**（不是 envelope） |
| `config get language --json` | rc=0，**裸 JSON 字符串** `"zh"`；`config set` 是文本回执 |
| `doctor` | 文本表格（非 JSON） |
| `cargo build`（现有 v0 客户端） | 成功（0.43s，已是最新） |

### 1.2 会改变实现的实测发现

1. **失败项目仍是完整形状**：`error` 存在，但 `dirty:{}`、`overall:{}`、`commitCount:-1`、`repoBranchCount:-1`、
   `stashCount:-1`、`worktreeCount:-1`、`journalUnparsableLines:-1`。所以模型必须把 `-1/{}` 读成「读不出来」，不是 0。
2. **里程碑只读条目没有 `id`**，项目名键是 `projectName`（不是 `project`）；`tag` 是存储绑定值、`tagName` 是实际生效值；
   `status` 可能是 `"unknown"`；非 git 项目会带 `gitReadable:false`、`commitsSince:-1`、`unverifiedReason`。
   现有 v0 的 `Milestone.project` 字段是错的（永远解不到项目名）。
3. **`milestone list` 在存储降级时 rc=1，但 stdout 是合法 payload**。客户端必须「载荷优先于退出码」。
4. **`git status` 的条目在 `output` 字符串里**，要二次解码；`output` 也可能是纯文本（失败时）。
5. **`git commit` 缺 message：rc=1 且 stdout 是 `{op,ok:false,output:"需要提交信息（--message）"}`**；
   它不是 `code/error` 形状。判失败要「rc + per-command 的 ok」两条都看，不能只套一个全局规则。
6. **`update` 的 docs 回执三态**：`changed:true,created:true,backup:""`（新建，无备份）、
   `changed:true,created:false,backup:"…"`（真改，有备份）、`changed:false,created:false,backup:""`（报了但没变）。
   「有备份才提备份」必须按 `backup` 是否为空，不许自己拼路径。
7. **`reopen` 可能 `applied:false`**：沙箱非 git 项目实测返回 `status:"unknown",applied:false`。
   动作回执要显示「实际生效的状态」，不能显示「请求的状态」。
8. **`scan` 的覆盖度是三轴**：`truncated`（目录上限）、`depthCapped`（深度上限）、`unreadable[]`（读不到）。
   三者要分别说，不能合并成一句「结果可能不完整」。
9. **上下文预算最小 500**：传 400 得到 500。UI 不要假设「我传多少就是多少」。
10. **`list --json` 是裸数组**，`config get --json` 是裸字符串；不要给它们套 envelope 解码。
11. **引擎的 `--quiet` 不会吞 `warn`**：stderr 可能带告警（非 0 退出之外）。读命令的 stderr 要作为「引擎告警」收集，不能当失败。
12. **BUI 的 Command 映射为 `control`**（Cocoa 宿主 `mods_of` 把 Command 并进 `BK_CTRL`），
    所以快捷键统一判断 `keystroke.modifiers.control`；UI 文案在 macOS 显示 `⌘`，其他平台显示 `Ctrl`。
13. **BUI 的 `on_input` 与 `on_change` 共用 CHANGE 事件**；文本输入统一用 `.on_input`，并给稳定 `.id()`，
    否则每帧重建会丢焦点/光标。
14. **BUI 没有系统托盘/MenuBarExtra、没有 webview、没有系统通知、没有 OS 拖放、Cocoa 宿主没有 IME**。
    这些是硬边界，见第 13 节；不要在设计里假装有。

### 1.3 本次没有运行

- 没有构建/运行新方案（PLAN 尚未落地），没有跑 `contract-check`/`client-check`/`agent-check`；
- 没有跑 BUI 的 `UiSender` 冒烟（上游 examples/tests 也没有用过，见第 6.3 的 gate）；
- 没有做 Windows/Linux 构建与运行验证；本方案以 macOS 为主，跨平台只保证代码路径与命令可用。

### 1.4 BUI 源码依据（本轮实读 / 引用的勘察材料）

- 实读：`BUI/src/{lib,window,element,events,paint,effects,selector,html,vars,color}.rs`、
  `BUI/Cargo.toml`，以及 `blenderui-sys/csrc/kit/intern/kit_window_cocoa.m` 的键位/修饰键段。
- 关键核对：
  - `UiSender` / `App::ui_sender` / `on_wake`：`window.rs:371-399`、`482-489`；
  - `Window::write_clipboard` / `focus_id` / `set_scroll_offset`：`window.rs:1056-1093`；
  - `canvas(|bounds, painter| …)`：`element.rs:434-436`；`Painter::{fill,quad,arc,text}`：`paint.rs:327-370`；
  - Command → `control`：`kit_window_cocoa.m:242-254`；`Modifiers` 只有 shift/control/alt：`events.rs:14-24`；
  - `set_theme` / `set_tailwind`：`lib.rs:140-210`；
  - 原生控件只同步值/尺寸，不接 CSS：`widgets.rs:444-522`，`paint.rs` 无 `Content::Widget` 分支。
- **引用勘察材料、未重复实读**：Cocoa 无 IME / 无 `NSVisualEffectView`、Win32 整窗 alpha、
  `::backdrop` 不生成、sticky 不生效、渐变单层等宿主级事实（详见本轮「BUI 可行性勘察」）。

---

## 2. 目标与非目标

### 2.1 目标（v1 必须闭环）

- 原客户端核心能力：仪表盘、看板、里程碑、项目详情、git 白名单操作、选文件提交、
  图谱入口、代码置信度、补丁体检、扫描/添加、设置、AI 对话与一次性说明。
- Fluent 风格：亚克力层次、12 列磁贴、圆角/描边/高光、pivot 标签、命令栏、设置左导航。
- 更强的交互：后台任务 + 进度 + **真取消**（杀子进程）、刷新合并、命令面板、右键菜单、
  toast、骨架屏、空态、确认弹层、复制、快捷键、hover/active/focus 动效。
- 每个页面只依赖 core 的契约；四个功能组的文件互不重叠。

### 2.2 非目标（v1 不做，见第 13 节）

- 不做窗口级真毛玻璃/透桌面（BUI 宿主不支持）。
- 不做内嵌 WebView 图谱（BUI 没有 webview）。
- 不做系统托盘/菜单栏常驻、系统通知、OS 拖放、系统钥匙串、开机自启。
- 不做流式 AI 输出、语法高亮、Markdown 图片加载。
- 不新增第三方 crate；不引入 HTTP 客户端库（AI 走系统 `curl` 子进程）。

---

## 3. BUI 0.5 硬边界 → 设计约束（四组都必须遵守）

| 边界（源码事实） | 约束 |
|---|---|
| 表单控件是 kit 原生节点，CSS 外观无效（`widgets.rs:444-522`；`paint.rs` 无 `Content::Widget` 分支） | `<input>/<textarea>` 只用于**文本输入**，外观由外层 `.field-box` 承担；**禁止** `<button>/<select>/<progress>/<meter>` 做 UI；所有按钮/分段/开关/复选/进度条用 `div` + 类 |
| 未知 CSS 属性/取值运行期静默丢弃（`style.rs:586-614`） | 只有一个样式源 `design::SHEET`；视图只能经由 `ui::el(classes)` / `ui::cls(&[...])` 使用契约类；`tests/class_contract.rs` 扫源码 |
| 祖先有 `filter/backdrop 之外的 transform/clip-path/mask/mix-blend-mode` 会把子树画进新 Painter，子级 `backdrop-filter` 采到空背景（`effects.rs:204-208`、`paint.rs:776-777`） | 玻璃元素（sidebar/main-head/hero/modal）的任何祖先都不得有这些属性；hover 抬升只用纯 `translateY`（`style.rs:2410-2426` 不进 layer） |
| `backdrop-filter` 只采「先画」的内容、每帧重算、无缓存（`paint.rs:871-895`） | 玻璃面**最多 4 个**：侧栏、主区标题栏、仪表盘 hero、模态卡；磁贴/列表/聊天一律 rgba 纯透明 |
| `position: sticky` = static（taffy 0.15 不应用 inset） | 吸顶表头/工具条一律放在滚动容器**之外**；不做 sticky |
| `overflow:hidden` 的裁剪是矩形，不认圆角；图片内容也不圆角 | 需要圆角裁切整棵子树时用 `clip-path: inset(0 round Npx)`；**带玻璃的子元素不要放进 clip-path 祖先**；v1 不加载图片 |
| 渐变只有单层，radial 无 center/shape/size | 只用 `linear-gradient`；不要写 `radial-gradient(... at 30% 30%)` 这种会被忽略的写法 |
| `opacity` 只作用于自身盒子，不是组透明度 | 整组变淡一律用 rgba 颜色；不要给容器设 `opacity`（骨架屏除外，它没有子元素） |
| 字体没有逐字形回退，一个元素只用第一个可用 family | 继续内嵌 HarmonyOS Sans SC（Regular/Medium）；不依赖系统 CJK 回退 |
| `::backdrop`/`::selection`/`::-webkit-scrollbar` 只解析不生成 | 模态用真 `.overlay` div；滚动条只能 `scrollbar-width: thin`；选区配色不可定制 |
| `1fr` 的最小值被映射成 `auto`（`style.rs:1085`） | 所有等宽列写 `minmax(0, 1fr)`；磁贴项加 `min-width: 0` |
| `subgrid`/`masonry` 被当成 `none` | 不做瀑布流；固定 12 列 + 显式 span |
| disabled 只影响 `:disabled` 匹配，不拦点击；`pointer-events:none` 才拦（`layout.rs:2562`） | div 按钮的禁用用 `.is-disabled { pointer-events:none; }` + 文案说明原因；不用 `disabled` 属性 |
| hover 监听不冒泡；CSS `:hover` 命中整条祖先链 | 卡片 hover 用 CSS `.card.hoverable:hover`，不要靠子元素 `on_hover` 冒泡 |
| 文本控件吃掉按键；没有 Enter 提交事件 | 所有输入旁必须有按钮；快捷键在输入框聚焦时不可用（文档写明） |
| macOS 宿主没有 NSTextInputClient / IME | 中文输入法无法在 BUI 文本框内组合；用「粘贴 + 按钮 + 预设/文件选择器」兜底（第 13 节） |
| 一帧只要有 effects 就整帧切慢路径（`paint.rs:627-642`） | 玻璃、滤镜、非 translate 动画都要克制；列表滚动区不要放 effects |
| `z-index` 是全局扁平排序（`layout.rs:2587-2597`） | 浮层挂在 `.app` 根节点，用 z-index 100/110；不要靠 z-index 把元素挪到 backdrop 采样范围外 |
| `fixed` 仍受祖先 overflow 裁剪 | 所有 overlay/menu/toast 都是 `.app` 的直接子节点，不塞进 `.main-scroll` |

---

## 4. 设计语言

### 4.1 设计令牌（唯一定义在 `design.rs`，CSS 变量挂 `.app`）

| 令牌 | 值 | 用途 |
|---|---|---|
| `--bg` | `#0A0F1A` | 窗口底 |
| `--bg-2` | `#0C1424` | 侧栏/次级底 |
| `--surface` | `rgba(255,255,255,.035)` | 卡片底 |
| `--surface-2` | `rgba(255,255,255,.06)` | hover/选中底 |
| `--glass` | `rgba(255,255,255,.06)` | 玻璃底 |
| `--glass-2` | `rgba(14,22,38,.78)` | 模态玻璃底 |
| `--stroke` | `rgba(255,255,255,.08)` | 1px 分隔 |
| `--stroke-2` | `rgba(255,255,255,.14)` | 玻璃高光边 |
| `--text` | `#E9EEF7` | 正文 |
| `--text-2` | `#A9B6CC` | 次级 |
| `--text-3` | `#6F7D95` | 弱化/说明 |
| `--accent` | `#4C8DFF` | 强调/主按钮/选中 |
| `--accent-2` | `#6BA1FF` | hover |
| `--accent-3` | `#3B78E6` | press |
| `--ok` | `#3FCF8E` | 干净/成功/增量 |
| `--warn` | `#F2B25C` | 未提交/告警 |
| `--stale` | `#FF9A62` | 停滞 |
| `--err` | `#FF6B81` | 读不出来/失败/删除 |
| `--info` | `#63B3ED` | 信息/深链说明 |
| `--unknown` | `#B08CFF` | 无法核验/口径未知 |
| `--series-1..12` | `#4C8DFF #3FCF8E #F2B25C #FF6B81 #B08CFF #63B3ED #F78FB3 #7FE3B8 #FFC97A #9AA8FF #5ED0C6 #D6A2FF` | 提交类型/语言 12 色，容量足够引擎上限 |
| 间距 | 2 / 4 / 6 / 8 / 12 / 16 / 20 / 24 / 32 | 8px 节奏 |
| 圆角 | 6 / 8 / 12 / 16 / 999 | 控件 8、卡片 12、模态 14、chip 999 |
| 字号 | 11 / 12 / 13 / 15 / 20 / 28 | caption/meta/body/subtitle/title/metric |
| 行高 | 1.25 / 1.5 | 标题/正文 |
| 阴影 | `--shadow-1: 0 8px 24px rgba(0,0,0,.28)`；`--shadow-2: 0 24px 64px rgba(0,0,0,.5)` | 卡片/模态 |
| 动效 | 120ms / 160ms `ease-out` | hover/press/展开 |
| 层级 | content 1 / head 10 / overlay 100 / toast 110 | 不要更多层 |
| 栅格 | 12 列，gap 12px，磁贴最小 260px | 仪表盘/看板 |

### 4.2 布局与磁贴

- 根：`.app` 绝对铺满，`display:flex; flex-direction:row`；左侧 `.sidebar`（260px，玻璃），右侧 `.main`（flex:1）。
- `.main` 内部三段：`.main-head`（56px，玻璃，标题 + 副标题 + 动作）、内容、可选状态条。
- 仪表盘：`.main-head` + `.dash-hero`（玻璃，固定）+ `.dash-filters`（固定）+ `.main-scroll`（磁贴滚动）。
- 磁贴：`.tiles { display:grid; grid-template-columns:repeat(12, minmax(0,1fr)); gap:12px; grid-auto-flow:dense; }`
  - KPI `span-3` ×4；hero `span-8` + 健康构成 `span-4`；项目卡 `span-4`；语言 `span-6`；里程碑 `span-6`；活跃项目 `span-12`。
  - `@media (max-width: 1180px)`：`span-3 → span-6`、`span-4 → span-6`；`@media (max-width: 980px)` 不适用（窗口最小 1040）。
- 项目页：`.main-head` + `.tabs`（pivot）+ `.main-scroll`。
- 看板：`.main-head` + `.main-scroll` 内 `.board`（`repeat(4, minmax(0,1fr))`；<1180 时 2×2）。
- 设置：`.main-scroll` 内 `.settings`（左 `.settings-nav` 180px + 右 `.settings-pane`）。
- AI：`.main-head` + `.chat`（`flex:1; display:flex; flex-direction:column`），`.chat-scroll` 滚动，`.composer` 固定在底部。

### 4.3 玻璃配方与性能预算

```css
.glass {
  background: rgba(255,255,255,.06);
  border: 1px solid rgba(255,255,255,.14);
  border-top-color: rgba(255,255,255,.20);
  backdrop-filter: blur(18px) saturate(1.2);
  box-shadow: 0 8px 24px rgba(0,0,0,.28);
}
.glass-strong { background: rgba(14,22,38,.78); backdrop-filter: blur(24px) saturate(1.15); }
```

- 只允许 4 个玻璃面：`.sidebar`、`.main-head`、`.dash-hero`、`.modal`。
- 玻璃面内可以放普通 rgba 卡片；**不要再嵌套第二个 backdrop-filter**。
- 滚动区（`.main-scroll`、`.chat-scroll`）里的元素一律 `background: rgba(...)`，不用 `backdrop-filter`。
- 验收：在 17 个项目、语言/里程碑全展开时滚动仪表盘；若明显掉帧，先把 `blur(18px)` 降到 `blur(12px)`，
  再把 hero 改成非玻璃（sidebar/head/modal 保留）。

### 4.4 动效

```css
.btn, .card.hoverable, .nav-item, .tab, .seg-item {
  transition: background-color 120ms ease, border-color 120ms ease,
              box-shadow 120ms ease, transform 120ms ease;
}
.card.hoverable:hover { transform: translateY(-2px); border-color: rgba(124,166,255,.30); }
.btn:active { transform: translateY(1px); }
@keyframes pulse { 0%,100% { background-color: rgba(255,255,255,.04); } 50% { background-color: rgba(255,255,255,.09); } }
.skeleton { animation: pulse 1.4s ease-in-out infinite; }
@keyframes toast-in { from { transform: translateY(8px); } to { transform: translateY(0); } }
.toast { animation: toast-in 160ms ease-out; }
```

- **不要**用 `scale()`/`rotate()` 做 hover：它们会进 layer，破坏子级玻璃。
- `@media (prefers-reduced-motion: reduce)` 下把 `transition/animation` 设为 `none`（BUI 支持该 media）。

---

## 5. 类名契约

### 5.1 使用规则（强制）

1. 视图文件（`src/views/**`，**包括** core 自己的 `settings.rs`/`agent.rs`）**禁止**直接 `.class("...")`、
   **禁止** `.style("...")`。一律用：
   - `ui::el(&["card", "hoverable"])`；
   - `ui::cls(&["nav-item", if on { "on" } else { "" }])`；
   - `ui::text(&["t-meta", "dim"], s)`；
   - 语义组件 `ui::btn/chip/dot/bar/tile/kpi/section/empty/banner/modal/toast`。
2. `ui::cls` 在 debug 构建里把每个 token 与 `design::CLASS_TOKENS` 比对；未知类直接 panic（开发期立刻发现拼写错误）。
3. `tests/class_contract.rs` 扫 `src/views/**/*.rs`：出现 `.class("` 或 `.style(` 即失败；
   同时断言 `design::CLASS_TOKENS` 非空、`ui::cls` 的校验分支还在（防退化成恒等函数）。
4. 原生控件只允许 `input()` / `textarea()`；它们只设几何类 `.input` / `.textarea`，外观由 `.field-box` 承担。
5. 动态几何（进度条宽度、菜单坐标、分数环）只允许在 core 的 `ui::bar/stackbar/score_ring/menu_at` 里用 inline style/canvas；
   视图不得自己拼 style。

### 5.2 完整类表

> 记号：`a / b / c` 表示三个独立 class token；`a.b` 表示同一元素上的两个 token。
> 所有 token 都必须出现在 `design::CLASS_TOKENS`。

#### 布局与壳

| 类 | 用途 / 关键属性 |
|---|---|
| `app` | 根容器：absolute inset 0、flex row、背景渐变、CSS 变量、字体 |
| `sidebar` | 左栏 260px、玻璃、右 1px 描边、纵向 flex |
| `sidebar-head` / `sidebar-brand` / `sidebar-brand-sub` | 品牌区：16px/600 + 11px 弱化 |
| `sidebar-scroll` | 中间滚动区，padding 6/10，gap 1 |
| `sidebar-group` / `sidebar-group-head` / `sidebar-group-toggle` | 分组（视图/仓库）；head 可点击折叠 |
| `sidebar-foot` / `sidebar-status` | 底部状态条：忙碌点、上次刷新、引擎短名 |
| `main` | 右区 flex column、height 100% |
| `main-head` | 56px、玻璃、横向、padding 16/24、下 1px 描边 |
| `main-head-main` / `main-title` / `main-sub` / `main-actions` | 标题 20px/600、副标题 12px、右侧动作 |
| `main-scroll` | flex 1、overflow-y scroll、padding 20/24/28、纵向 gap 14 |
| `main-scroll-flush` | 同上但 padding 0（看板/文档长列表用） |
| `dash-hero` | 仪表盘固定 hero 条：玻璃、横向、padding 16/20、min-height 104 |
| `dash-filters` | 仪表盘固定筛选条：横向、gap 8、padding 8/24、下 1px 描边 |
| `page` / `page-narrow` | 内容最大宽 1080 / 760，居中 |
| `stack` / `stack-sm` | 纵向 flex，gap 14 / 8 |
| `row` / `row-sm` / `row-wrap` / `row-between` | 横向 flex，gap 8 / 6 / wrap / space-between |
| `spacer` / `fill` / `grow` / `nowrap` / `center` / `right` / `hidden` | 工具类 |
| `divider` / `divider-v` | 1px 横/竖分隔（rgba 6%） |
| `tiles` / `tile` / `tile-hero` | 12 列磁贴容器 / 磁贴项（min-width:0）/ hero 磁贴（min-height 200） |
| `span-2` `span-3` `span-4` `span-6` `span-8` `span-9` `span-12` | 磁贴跨列；窄窗由 media 覆盖 |
| `form-grid` | 两列表单（label 120px + control 1fr） |
| `pane` / `pane-head` / `pane-body` / `pane-foot` | 带描边的分区（设置/扫描） |

#### 表面与文本

| 类 | 用途 |
|---|---|
| `glass` / `glass-strong` | 亚克力面（见 4.3） |
| `card` | `rgba(255,255,255,.035)` + 1px 描边 + 12 圆角 + padding 16 + 纵向 gap 10 |
| `hoverable` | 卡片 hover 抬升/描边（只与 `.card` 组合） |
| `selected` | 选中态：accent 15% 底 + accent 30% 边 |
| `flat` | 无背景无描边（嵌套卡） |
| `card-head` / `card-title` / `card-sub` / `card-body` / `card-foot` | 卡内结构；title 13px/600 |
| `hero` / `hero-title` / `hero-sub` / `hero-metric` | 仪表盘 hero：28px 大数字、12px 副标题 |
| `kpi` / `kpi-label` / `kpi-value` / `kpi-hint` / `kpi-foot` | KPI 磁贴：12px label、28px value、11px hint、底部分隔 |
| `stat` / `stat-value` / `stat-label` | 小统计件 |
| `art` / `art-ready` / `art-missing` | 图谱产物卡：ready 蓝边/蓝底，missing 虚线边 |
| `t-h1` / `t-h2` / `t-h3` / `t-title` / `t-body` / `t-meta` / `t-caption` | 20/15/13/13/13/12/11 |
| `t-dim` / `t-strong` / `t-mono` / `t-num` / `t-accent` | 弱化/600/等宽/表格数字/强调色 |
| `t-ellipsis` / `t-clamp-2` / `t-clamp-3` | 单行省略 / 两行/三行 max-height 裁剪 |
| `mono` / `num` | 等宽字体 / `font-variant-numeric` 替代（用等宽对齐） |
| `muted` / `dim` | 次级/弱化文字色 |
| `ok` / `warn` / `stale` / `err` / `info` / `unknown` / `accent` / `idle` | 色调 token；与 `dot/chip/badge/bar-fill/banner/toast` 组合 |

#### 控件

| 类 | 用途 |
|---|---|
| `btn` | div 按钮：inline-flex、padding 6/12、8 圆角、1px 描边、hover/active |
| `btn-sm` / `btn-lg` | 4/10、8/14 padding |
| `btn-accent` / `btn-ghost` / `btn-danger` | 主按钮（accent 底、深色字）/ 透明底 / 红字红边 |
| `btn-icon` / `btn-pill` / `btn-block` | 方形图标 / 999 圆角 / 占满宽 |
| `btn-busy` / `is-disabled` | 忙碌（右侧 8px 转圈用 `.spinner`）/ 禁用（pointer-events:none + 0.45 色） |
| `spinner` | 8px 圆环，`border-top-color: transparent` + `@keyframes spin` |
| `btn-group` | 横向紧贴的按钮组（首尾圆角） |
| `seg` / `seg-item` / `on` | 分段控件：容器 2px 内边距，item 8 圆角，`.on` accent 15% 底 |
| `kbd` | 快捷键小件：11px 等宽、1px 底边 |
| `field` / `field-label` / `field-hint` / `field-error` | 表单行：label 12px、hint 11px 弱化、error 11px 红 |
| `field-box` | 原生输入的容器：1px 描边、8 圆角、padding 2、focus-within accent 边 |
| `input` / `textarea` | 只设几何：width 100%、height 32/88、padding 7/10；**不指望背景/圆角生效** |
| `check` / `check-box` / `check-mark` | 自定义复选：16px 方框、`.on` 时 accent 底 + `✓` |
| `switch` / `switch-knob` | 自定义开关：36×20 轨道、16px 圆点；`.on` 时 accent 底并右移 |
| `link` | accent 色、cursor pointer、hover 下划线（`text-decoration` 若支持；不支持就改色） |
| `picker-btn` | 打开项目选择器的按钮（左图标 + 名称 + ▾） |

#### 导航与浮层

| 类 | 用途 |
|---|---|
| `nav-item` | 侧栏行：flex、padding 7/10、8 圆角、hover 6% 底 |
| `on` | 选中态：accent 15% 底 + accent 30% 边 + 左侧 2px accent（用 `box-shadow: inset 2px 0 0`） |
| `nav-icon` / `nav-label` / `nav-badge` | 16px 图标 / flex 1 省略 / 右侧计数 |
| `nav-badge-warn` / `nav-badge-dim` | 橙色/弱化计数 |
| `sect-label` | 分组标题：11px、字距 .4、弱化 |
| `tabs` / `tab` / `tab-badge` | pivot 标签条（下 1px 描边）；tab 选中时 accent 文字 + 2px 下边 |
| `crumb` / `crumb-sep` | 面包屑（项目页头） |
| `overlay` | fixed inset 0、rgba(4,8,16,.55)、z 100、flex 居中 |
| `overlay-top` | 同上但 `align-items:flex-start; padding-top:12vh`（命令面板） |
| `overlay-clear` | 透明遮罩（右键菜单的点击外部关闭） |
| `modal` / `modal-sm` / `modal-md` / `modal-lg` / `modal-xl` | 玻璃卡：宽 420/560/720/920、max 96%、max-height 90%、纵向 flex |
| `modal-head` / `modal-title` / `modal-sub` / `modal-body` / `modal-foot` / `modal-close` | 结构；body `overflow-y:scroll`；close 右上角 |
| `confirm-icon` | 确认框顶部 40px 圆形图标（危险红/普通蓝） |
| `menu` | fixed 绝对定位菜单：200px、玻璃底、8 圆角、阴影、z 100 |
| `menu-head` / `menu-item` / `menu-sep` / `menu-danger` / `menu-shortcut` | 菜单结构；danger 红字 |
| `toast-wrap` | fixed right 20 bottom 20、z 110、纵向 gap 8 |
| `toast` / `toast-title` / `toast-body` | 最小 260、最大 420、12 圆角、阴影、左 3px 色调条 |
| `banner` / `banner-title` / `banner-body` / `banner-action` | 信息条：10/14 padding、10 圆角、色调底/边 |
| `palette` / `palette-input` / `palette-list` / `palette-item` / `palette-item-on` / `palette-kind` / `palette-empty` | 命令面板：560px、输入行、列表、选中行 accent 底、右侧 kind 小字 |

#### 状态与数据

| 类 | 用途 |
|---|---|
| `dot` | 8px 圆点；`ok/warn/stale/err/info/unknown/idle` 决定背景 |
| `chip` / `chip-sm` | 999 圆角小标签：3/9 padding、1px 描边 |
| `badge` / `badge-sm` | 8 圆角数字徽标；accent/ok/warn/err/muted 组合 |
| `table` / `thead` / `tbody` / `tr` / `th` / `td` / `td-num` | 数据表；th 11px 弱化、td 13px、行 hover 4% 底 |
| `kv` / `kv-k` / `kv-v` | 键值对：k 12px 弱化、v 13px |
| `bar` / `bar-sm` / `bar-fill` | 进度条：6/4px 高、999 圆角、底 6% 白；fill 用 tone 色 |
| `stackbar` / `stack-seg` | 堆叠条：8px 高、圆角 999、子段 flex；颜色 `.s1..s12` |
| `s1` … `s12` | 12 个系列色背景（提交类型/语言） |
| `legend` / `legend-item` / `swatch` | 图例：swatch 8px 方点；item 11px |
| `spark` | canvas 容器（固定高 40） |
| `list` / `list-item` / `list-main` / `list-side` | 行列表；item padding 8/10、hover 4% 底 |
| `empty` / `empty-icon` / `empty-title` / `empty-body` | 空态：居中、图标 28px、标题 15px、说明 12px |
| `disclosure` / `disclosure-head` / `disclosure-body` | `<details>` 的类；head 12px、body 12px 弱化 |
| `code` / `pre` | 行内/块级等宽；pre 12px、1.5 行高、overflow-x scroll |
| `diff` / `diff-add` / `diff-del` / `diff-hunk` | 补丁片段：add 绿底、del 红底、hunk 蓝字 |
| `md` + `md-h1` `md-h2` `md-h3` `md-h4` `md-h5` `md-h6` `md-p` `md-li` `md-bullet` `md-quote` `md-pre` `md-code` `md-strong` `md-em` `md-link` `md-table` `md-hr` `md-img-alt` | Markdown 渲染 |
| `skeleton` / `skeleton-line` | 骨架屏：pulse 动画；line 高 10、圆角 999 |

#### 业务组件

| 类 | 用途 |
|---|---|
| `board` / `board-col` / `board-col-head` / `board-col-count` / `board-col-criteria` / `board-card` | 看板四列/卡片 |
| `score` / `score-value` / `score-label` | 置信度总分：canvas 环 + 中心大字 |
| `dims` / `dim-row` / `dim-name` / `dim-bar` / `dim-val` | 六维度/引擎维度行 |
| `finding` / `finding-head` / `finding-body` / `finding-meta` | findings 折叠行 |
| `signal-grid` / `signal` / `signal-name` / `signal-value` / `signal-null` | S1–S10 信号格；null 用 `—` + 弱化 |
| `alert` / `alert-high` / `alert-medium` / `alert-low` | 合并告警三级 |
| `graph-preview` / `graph-preview-index` / `graph-preview-arch` / `artifact-actions` | 图谱卡缩略渐变（不加载 HTML） |
| `chat` / `chat-scroll` / `msg` / `msg-user` / `msg-assistant` / `msg-tool` / `msg-error` | AI 对话 |
| `msg-head` / `msg-body` / `msg-time` / `msg-actions` | 消息头/正文/时间/重试 |
| `composer` / `composer-input` / `composer-actions` | 输入区（textarea + 发送/停止/清空） |
| `suggest` / `suggest-item` | 建议问题 |
| `thinking` | 思考中（三点 pulse） |
| `tool-event` / `tool-event-ok` / `tool-event-err` | 工具过程事件（默认折叠） |
| `search` / `search-box` / `search-input` / `search-clear` | 搜索框：icon + 原生 input + 清除 |
| `scan-grid` / `scan-drop` / `scan-drop-icon` / `scan-result` / `scan-stat` / `scan-stat-value` / `scan-stat-label` | 扫描页 |
| `candidate` / `candidate-main` / `candidate-side` | 扫描候选行 |
| `path` / `path-text` | 路径行：等宽、省略、可点击复制 |
| `settings` / `settings-nav` / `settings-nav-item` / `settings-pane` | 设置左右布局 |
| `setting-row` / `setting-label` / `setting-desc` / `setting-control` | 设置行：label 13px、desc 11px、右侧控件 |
| `about-hero` / `about-logo` / `about-links` / `link-row` | 关于页 |
| `secret-note` | 密钥存储说明（11px 弱化 + 警告色） |

> 完整 token 列表以 `design::CLASS_TOKENS` 为准；本表与它必须一一对应（测试会查使用侧，人工评审查定义侧）。

---

## 6. 架构

### 6.1 模块与依赖

```
src/lib.rs（库目标：pub mod app/actions/state/jobs/design/engine/models/l10n/settings/
           sysopen/derive/ui/ai/views；tests/ 与 main.rs 都从这里 import）
  └─ main.rs（薄二进制：use deepdolphin_client::…；字体/主题/args/窗口）
       └─ app.rs（AppRoot / AppState / dispatch / refresh）
       ├─ actions.rs（Route / Action / AppAction / Confirm / Menu）
       ├─ state.rs（AppState 字段、Load / Reading / UiState 容器）
       ├─ jobs.rs（JobId / JobCtx / CancelToken / 后台线程）
       ├─ engine.rs（CLI 子进程 + 超时 + 取消 + 错误载荷）
       ├─ models.rs（引擎 JSON 的只读镜像）
       ├─ design.rs（令牌 + 唯一 SHEET + CLASS_TOKENS）
       ├─ l10n.rs（Lang + tr! 宏）
       ├─ settings.rs（settings.json / secrets.json / 目录）
       ├─ sysopen.rs（Finder/Terminal/URL/文件夹选择器）
       ├─ ui/（cls、el、text、btn、chip、dot、bar、tile、kpi、modal、toast、md）
       ├─ ai/（provider、agent、tools、prompt）
       └─ views/
            ├─ mod.rs（路由分发；core）
            ├─ sidebar.rs / scan.rs / palette.rs        （sidebarscan）
            ├─ dashboard.rs + dashboard/*               （dashboard）
            ├─ project.rs + project/* + milestones.rs   （project）
            ├─ board.rs / confidence.rs / patch.rs      （boardconf）
            └─ settings.rs / agent.rs                   （core）
```

依赖方向：`views/* → ui/models/actions/state → engine`；`engine` 只依赖 std。
视图**不直接** `Command::new`、不直接解析 JSON、不直接读写文件（README 文档内容除外：docs 读取走 engine）。

### 6.2 数据流

```
启动：parse_args → Settings::load → Engine::discover
      → 同步预取 status / dashboard / milestone list / registry（开窗前）
      → 开窗（首屏即数据）

动作：view listener → state.dispatch(Action) → module::reduce
      → 读：spawn_job(label, work=|ctx| engine.status()) 
             done=|r| Action::Dashboard(DashboardAction::Loaded(parse(r)))
      → 写：spawn_job(cancellable=true, work=|ctx| engine.update(..., &ctx))
             → 完成后先 jobs.finish(id)，再 dispatch(done)
      → 所有 job 完成都走 Entity::update + cx.notify()

刷新：Refresh(All|Light|Project)
      - 正在跑：refresh_queued = true（合并，不丢）
      - 跑完：若 queued，再跑一次
      - status 失败：不再跑 dashboard/milestones（旧客户端同纪律）
```

### 6.3 线程与取消（UiSender gate）

- `AppState.sender: Option<UiSender>`：在 `AppRoot::render` 第一帧取 `cx.ui_sender()` 存入；
  取不到（headless/异常）时 `spawn_job` 退化为**同步执行**，API 不变。
- 工作线程只拿 `UiSender + Entity<AppRoot> + Engine`；**绝不**碰 `Window`、**绝不**写 hooks 的 Signal
  （BUI 的 signal store 是 per-thread，后台写会静默丢失）。
- 取消：`CancelToken(Arc<AtomicBool>)`；`Engine::run_job` 每 50ms `try_wait`，
  取消/超时就 `child.kill()` + `wait()`，再 join 两个读管道线程。
  **只 `Task.cancel` 不杀进程是假停止**——BUI 没有 Task，这里对应「只置 flag 不 kill」。
- 用户停止 → `JobResult{cancelled:true}` → 文案「已停止（用户取消）」，**不报失败**；
  超时 → `timed_out:true` → 「引擎超时（>Ns），已终止」。两者分开。
- **gate（Phase 0 必做）**：`--selftest-ui-sender` 开一个测试窗，后台线程 sleep 200ms 后
  `sender.send` 改一个计数并 `cx.notify()`；2s 内计数变 1 打印 `UI_SENDER_OK` 退出 0，否则 `UI_SENDER_FAIL` 退出 1。
  gate 不通过 → 自动化/定时刷新关闭，所有 job 同步执行（功能仍在，UI 会阻塞），设置页显示原因。
- 同一时刻只允许一个 job（`jobs.active`）。写操作遇到 busy → toast「已有任务在运行」；读/刷新 → 合并。

---

## 7. API 契约（Phase 0 必须先落地）

> 以下签名是四组并行开发的**唯一接口**。core 在 Phase 0 冻结；需要改契约必须在 PLAN 里加一条并通知四组。

### 7.1 Route / ProjectTab / SettingsTab

```rust
pub enum Route {
    Dashboard,
    Board,
    Milestones,
    Confidence,
    Patch,
    Project { name: String, tab: ProjectTab },
    Scan,
    Settings(SettingsTab),
    Agent,
}
pub enum ProjectTab { Overview, Branches, Journal, Docs, Milestones, Graph }
pub enum SettingsTab { General, Ai, Automation, About }

impl Route {
    pub fn key(&self) -> String;        // 用于滚动容器 id：scroll-<key>
    pub fn title(&self, lang: Lang) -> &'static str;
}
```

### 7.2 AppAction / Action / 各模块 Action

```rust
pub enum Action {
    App(AppAction),
    Dashboard(views::dashboard::DashboardAction),
    Project(views::project::ProjectAction),
    Board(views::board::BoardAction),
    Milestones(views::milestones::MilestonesAction),
    Confidence(views::confidence::ConfidenceAction),
    Patch(views::patch::PatchAction),
    Sidebar(views::sidebar::SidebarAction),
    Scan(views::scan::ScanAction),
    Settings(views::settings::SettingsAction),
    Agent(views::agent::AgentAction),
    Progress { id: JobId, line: String },
}
```

`Action` 必须 `Clone + Send + 'static`（菜单项/确认框会存它，工作线程会把它送回 UI 线程）。

```rust
pub enum AppAction {
    Navigate(Route),
    Refresh(RefreshScope),                 // All | Light | Project(String)
    Tick,                                  // 30s ticker
    RedetectEngine,
    SetEngineBin(String),
    SetLanguage(Lang),
    DismissFeedback,
    DismissToast(u64),
    CancelActiveJob,
    AskConfirm(Confirm),
    ConfirmYes,
    ConfirmNo,
    OpenMenu { x: f32, y: f32, items: Vec<MenuItem> },
    CloseMenu,
    TogglePalette,
    OpenExternal(OpenTarget),              // Url(String) | Reveal(String) | Terminal(String)
    CopyText { text: String, label: String },
    RouteNote(String),                     // 深链说明，独立于 last_error
    Quit,
}
pub struct Confirm {
    pub title: String,
    pub body: String,
    pub confirm_label: String,             // 动词，不是「确定」
    pub danger: bool,
    pub action: PendingAction,             // 见 7.2.1
}
pub enum PendingAction {
    MilestoneRemove { project: String, name: String },
    MilestoneDrop   { project: String, name: String },
    UpdateAll       { deep: bool },
    UpdateProject   { project: String, deep: bool },
    RemoveProject   { name: String },
}
pub struct MenuItem { pub label: String, pub shortcut: Option<String>, pub danger: bool, pub action: Action }
```

#### 7.2.1 模块契约（四个功能组各自实现，core 只做路由）

每个视图模块必须暴露：

```rust
pub struct XxxUi: Default + Clone;          // 该页所有临时 UI 状态；字段由该组自己加
pub enum XxxAction { ... }                  // 该页所有动作；变体由该组自己加
pub fn render(state: &AppState, cx: &mut Context<AppRoot>) -> Div;
pub fn reduce(state: &mut AppState, action: XxxAction, cx: &mut Context<AppRoot>);
pub fn on_enter(state: &mut AppState, cx: &mut Context<AppRoot>);   // 可空实现；进入路由时按需发 Load
```

- core 的 `navigate` 在改完 `route` 后调用路由对应模块的 `on_enter`（只调一次），
  这样「首次加载」不发生在 `render` 里。`on_enter` 必须幂等（`Load::Idle` 才发）。

- `XxxUi` 放在该模块自己的文件里，core 的 `UiState` 只持有类型（`pub dashboard: views::dashboard::DashboardUi`）。
  这样功能组加字段**不需要改 core**。
- `reduce` 里可以调用 `state.spawn_job` / `state.toast` / `state.ask_confirm` / `state.engine`（只读 clone）/
  `state.ui.*` / `state.status` 等 core 公共字段；**不得**直接 `Command::new`。
- `render` 只读 `&AppState`，不得改状态（避免渲染期副作用）；需要首次加载时，在进入路由的 `reduce` 里发 `Load`。
- **`palette.rs` 例外**：它是根级浮层，不是路由页，暴露
  `pub struct PaletteUi: Default + Clone`、`pub fn toggle(&mut PaletteUi)`、
  `pub fn handle_key(state: &mut AppState, e: &KeyDownEvent) -> bool`、
  `pub fn render_overlay(state: &AppState, cx: &mut Context<AppRoot>) -> Option<Div>`；
  不要求 `PaletteAction`/`reduce`。`AppRoot` 在根 key listener 里先调 `handle_key`，再走 core 快捷键。

### 7.3 AppState / UiState

```rust
pub struct AppState {
    pub engine: Engine,                        // Clone（只有 bin 字符串）
    pub sender: Option<UiSender>,
    pub lang: Lang,
    pub settings: Settings,
    pub route: Route,
    pub status: Load<StatusEnvelope>,
    pub dashboard: Load<DashboardData>,
    pub milestones: Load<MilestoneList>,
    pub registry: Load<Vec<RegistryEntry>>,
    pub project_cache: HashMap<String, views::project::ProjectDetail>,
    pub jobs: JobRegistry,
    pub feedback: Option<Feedback>,            // 顶部错误/成功条
    pub route_note: Option<String>,            // 深链说明（banner.info）
    pub engine_warnings: Vec<String>,          // 读命令 stderr 的告警（非失败）
    pub toast: Vec<Toast>,
    pub confirm: Option<Confirm>,
    pub menu: Option<MenuState>,
    pub pending_copy: Option<PendingCopy>,     // reduce 里没有 Window：render 开头 flush
    pub pending_scroll: Option<String>,        // 同上：scroll-<route.key()>
    pub ai_result: Option<AiResultState>,
    pub graph_task: Option<GraphTaskState>,
    pub last_refresh: Option<Instant>,
    pub last_refresh_failed: bool,
    pub refresh_queued: bool,
    pub startup_error: Option<EngineError>,
    pub ui: UiState,
    pub ai: AiState,
}

pub struct UiState {
    pub dashboard: views::dashboard::DashboardUi,
    pub project: views::project::ProjectUi,
    pub board: views::board::BoardUi,
    pub milestones: views::milestones::MilestonesUi,
    pub confidence: views::confidence::ConfidenceUi,
    pub patch: views::patch::PatchUi,
    pub scan: views::scan::ScanUi,
    pub sidebar: views::sidebar::SidebarUi,
    pub settings: views::settings::SettingsUi,
    pub agent: views::agent::AgentUi,
    pub palette: views::palette::PaletteUi,
}
```

```rust
pub enum Load<T> { Idle, Loading, Ready(T), Failed(EngineError) }
pub enum Reading<T> { Known(T), NotRead }
pub enum Tone { Ok, Warn, Stale, Err, Info, Unknown, Accent, Idle }
pub enum RefreshScope { All, Light, Project(String) }
pub struct Feedback { pub tone: Tone, pub text: String }
pub struct Toast { pub id: u64, pub tone: Tone, pub title: String, pub body: String,
                   pub action: Option<Action>, pub expires: Instant }
pub struct MenuState { pub x: f32, pub y: f32, pub items: Vec<MenuItem> }
pub struct AiResultState { pub title: String, pub raw: Load<String>,
                           pub blocks: Vec<crate::ui::md::MdBlock>,
                           pub retry: Option<Action>, pub truncated: Option<Truncation> }
pub struct GraphTaskState { pub project: String, pub prompt: String }
pub struct Startup { pub route: Route, pub engine_bin: Option<String> }
pub enum OpenTarget { Url(String), Reveal(String), Terminal(String) }
pub struct AiState { pub tools: Load<Vec<McpTool>>, pub manifest: Load<ToolsManifest>,
                     pub conversation: Vec<ChatMessage>,
                     pub input: String, pub running: bool, pub last_user: Option<String>,
                     pub scope: Option<AiScope>, pub suggestions: Vec<String>,
                     pub history_omitted: Option<usize>, pub error: Option<String> }
pub enum AiScope { Group, Project(String) }
pub struct MilestoneAddReq { pub project: String, pub name: String,
                             pub tag: String, pub date: String, pub desc: String }
pub struct PendingCopy { pub text: String, pub label: String }
pub struct JobInfo { pub id: JobId, pub label: String, pub cancellable: bool,
                     pub started: Instant, pub cancel: CancelToken }
pub enum BoardColumn { Pending, Stale, Active, Other }
pub enum ScopeBadge { New(i64), RepoTotal(i64), UnknownScope(i64), NotRead }
pub enum ModalWidth { Sm, Md, Lg, Xl }
pub struct ProjectDetail { pub journal: Load<JournalPayload>, pub docs: Load<DocsPayload>,
                           pub git_status: Load<GitStatusPayload>,
                           pub artifacts: BTreeMap<Artifact, Load<RenderCheck>>,
                           pub doc_blocks: HashMap<String, Vec<crate::ui::md::MdBlock>>,
                           pub journal_branch: Option<String>, pub loaded_at: Option<Instant> }
// 实际定义在 views/project.rs；字段由 project 组维护，core 只持有 HashMap 值类型。
pub struct DashboardData {
    pub projects: DashProjects, pub work: DashWork,
    pub languages: Vec<LangCount>,
    pub languages_truncated: bool, pub languages_top_cut: bool,
    pub languages_failed: i64, pub languages_failed_reasons: Vec<String>,
    pub milestones: DashMilestones, pub active_projects: Vec<ActiveProject>,
    pub fetched_at: String,
}
pub struct DashProjects { pub total: i64, pub listed: i64, pub registered: i64,
                          pub excluded_disabled: i64, pub failed: i64, pub dirty: i64,
                          pub active7d: i64, pub active30d: i64 }
pub struct DashWork { pub branches: i64, pub merge_candidates: i64,
                      pub untracked_files: i64, pub untracked_failed: i64,
                      pub untracked_failed_reasons: Vec<String>, pub stashes: i64 }
pub struct LangCount { pub language: String, pub count: i64 }
pub struct DashMilestones { pub counts: MilestoneCounts, pub items: Vec<Milestone> }
pub struct MilestoneCounts { pub open: i64, pub done: i64, pub dropped: i64,
                             pub unknown: i64, pub other: i64,
                             pub store_health: String, pub degraded: bool,
                             pub read_count: i64, pub excluded_disabled: i64,
                             pub orphaned: i64 }
pub struct ActiveProject { pub name: String, pub last_commit_ago: String, pub headline: String }
```

公共方法（core 实现）：

```rust
impl AppState {
    pub fn bootstrap(start: Startup) -> Self;
    pub fn dispatch(&mut self, action: Action, cx: &mut Context<AppRoot>);
    pub fn navigate(&mut self, route: Route, cx: &mut Context<AppRoot>);   // 改 route 后调用对应模块 on_enter；同时设 pending_scroll
    pub fn projects(&self) -> &[Project];
    pub fn project(&self, name: &str) -> Option<&Project>;
    pub fn project_detail(&self, name: &str) -> Option<&views::project::ProjectDetail>;
    pub fn spawn_job<W, D>(&mut self, cx: &mut Context<AppRoot>, label: impl Into<String>,
                           cancellable: bool, work: W, done: D) -> Option<JobId>
        where W: FnOnce(JobCtx) -> JobResult + Send + 'static,
              D: FnOnce(JobResult) -> Action + Send + 'static;
    pub fn toast(&mut self, tone: Tone, title: impl Into<String>, body: impl Into<String>);
    pub fn fail(&mut self, err: EngineError);
    pub fn ask_confirm(&mut self, c: Confirm);
    pub fn copy(&mut self, text: &str, label: &str);           // 只设 pending_copy；AppRoot::render 用 Window 落剪贴板
    pub fn t(&self) -> Lang;
    pub fn engine_short(&self) -> String;
    pub fn refresh(&mut self, scope: RefreshScope, cx: &mut Context<AppRoot>);
}
```

`AppRoot::render(&mut self, window, cx)` 开头统一 flush：

```rust
if let Some(p) = self.state.pending_copy.take() {
    window.write_clipboard(&p.text);
    self.state.toast(Tone::Ok, "已复制", p.label);
}
if let Some(id) = self.state.pending_scroll.take() {
    window.set_scroll_offset(&id, 0.0, 0.0);
}
```

> 这样 `dispatch/reduce` 不需要 `&mut Window`；复制/滚动复位都由根视图在下一帧执行。
> `CopyText` / `Navigate` 只写 pending，不直接碰 Window。

`UiState::default()` 调用各模块的 `Default`；各模块字段自己初始化。

### 7.4 Job

```rust
pub struct JobId(pub u64);
pub struct CancelToken(Arc<AtomicBool>);
impl CancelToken { pub fn cancel(&self); pub fn is_cancelled(&self) -> bool; }

pub struct JobResult {
    pub ok: bool,
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
    pub cancelled: bool,
    pub timed_out: bool,
    pub duration_ms: u64,
}
pub struct JobCtx {
    pub cancel: CancelToken,
    pub timeout: Duration,
    pub progress: Box<dyn Fn(String) + Send>,
}
pub struct JobRegistry {
    pub active: Option<JobInfo>,
    next_id: u64,
}
impl JobRegistry {
    pub fn begin(&mut self, label: String, cancellable: bool) -> (JobId, CancelToken);
    pub fn finish(&mut self, id: JobId);
    pub fn cancel_active(&mut self);
    pub fn progress(&mut self, id: JobId, line: String);
}
```

### 7.5 Engine

```rust
#[derive(Clone)]
pub struct Engine { pub bin: String }

impl Engine {
    pub fn new() -> Self;                          // 发现顺序：settings.engine_bin > MOONGIT_BIN/DEEPGIT_BIN
                                                   // > exe 旁 moongit/deepgit > PATH moongit > PATH deepgit
    pub fn exists(&self) -> bool;
    pub fn run(&self, args: &[&str]) -> Result<JobResult, EngineError>;        // 同步，读命令用
    pub fn run_job(&self, args: &[&str], ctx: &JobCtx) -> JobResult;          // 可取消，写命令用
    pub fn mcp_tools(&self) -> Result<Vec<McpTool>, EngineError>;             // 一次性 mcp initialize+tools/list（stdio，无 HTTP）

    // 读（typed；内部 run + parse<T>）
    pub fn status(&self, project: Option<&str>) -> Result<StatusEnvelope, EngineError>;
    pub fn dashboard(&self) -> Result<DashboardData, EngineError>;
    pub fn milestone_list(&self, project: Option<&str>) -> Result<MilestoneList, EngineError>;
    pub fn docs(&self, project: &str) -> Result<DocsPayload, EngineError>;
    pub fn journal(&self, project: &str, branch: Option<&str>, limit: Option<u32>) -> Result<JournalPayload, EngineError>;
    pub fn tools(&self) -> Result<ToolsManifest, EngineError>;
    pub fn context(&self, project: Option<&str>, budget: u32) -> Result<ContextPayload, EngineError>;
    pub fn list_registry(&self) -> Result<Vec<RegistryEntry>, EngineError>;   // 裸数组
    pub fn render_check(&self, artifact: Artifact, project: &str) -> Result<RenderCheck, EngineError>;
    pub fn config_get_language(&self) -> Result<String, EngineError>;         // 裸 JSON 字符串
    pub fn config_set_language(&self, code: &str) -> Result<JobResult, EngineError>;
    pub fn doctor(&self) -> Result<String, EngineError>;                       // 文本

    // 写（返回 JobResult，由调用方 parse）
    pub fn update(&self, project: Option<&str>, deep: bool, ctx: &JobCtx) -> JobResult;
    pub fn git(&self, project: &str, op: GitOp, message: Option<&str>, paths: &[String], ctx: &JobCtx) -> JobResult;
    pub fn milestone_action(&self, project: &str, name: &str, action: MilestoneOp, ctx: &JobCtx) -> JobResult;
    pub fn milestone_add(&self, req: &MilestoneAddReq, ctx: &JobCtx) -> JobResult;
    pub fn scan(&self, roots: &[String], depth: u32, git_only: bool, ctx: &JobCtx) -> JobResult;
    pub fn add_project(&self, path: &str, name: Option<&str>, ctx: &JobCtx) -> JobResult;
    pub fn remove_project(&self, name: &str, ctx: &JobCtx) -> JobResult;
    pub fn confidence(&self, project: &str, llm: bool, ctx: &JobCtx) -> JobResult;
    pub fn patchconf(&self, project: &str, patch: &Path, skill: bool, ctx: &JobCtx) -> JobResult;
    pub fn patchconf_merge(&self, algorithm: &Path, agent: &Path, ctx: &JobCtx) -> JobResult;

    // 非引擎的本机命令（注释写明不是引擎通道）
    pub fn git_diff_head(&self, repo: &Path, ctx: &JobCtx) -> JobResult;      // git -C <path> diff HEAD
}

pub enum GitOp { Pull, Push, Fetch, Stash, Unstash, Commit }
pub enum MilestoneOp { Done, Reopen, Drop, Remove }
pub enum Artifact { Index, Arch }
```

**错误判据（唯一实现，所有组都必须走它）**

```rust
pub fn parse<T: DeserializeOwned>(cmd: &str, r: &JobResult) -> Result<T, EngineError>;
pub fn parse_or_payload(cmd: &str, r: &JobResult) -> Result<serde_json::Value, EngineError>;
```

- 先看 stdout：能解析 JSON 就**优先用载荷**（`milestone list` 降级时 rc=1 但载荷合法）。
- 若载荷是 `{error:true,...}` / `{code,...}` / `{message,...}` → `EngineError::Exit`，message 取 `message`。
- 若载荷是 git 的 `{op,ok,...}`：`ok=false` 由调用方判失败（`output` 是原因），**不**按 `code/error` 判。
- 若载荷是 `{results,count,failed,succeeded}`：`failed>0` 由调用方决定是否报错；逐条解析。
- stdout 不是 JSON：用 stderr（非空）→ stdout → `引擎退出码 N`；并保留 stderr 供「引擎告警」展示。
- 退出码不是原因；**载荷优先**，但退出码仍是「这条命令是否失败」的入口。

```rust
pub enum EngineError {
    NotFound { bin: String },
    Spawn { bin: String, message: String },
    Exit { code: i32, message: String, details: Option<String>, stderr: String },
    Json { command: String, message: String, raw: String },
    Cancelled,
    Timeout { secs: u64 },
    Io(String),
}
impl EngineError {
    pub fn user_message(&self) -> String;   // 中文、可执行、host-only 脱敏
    pub fn is_cancelled(&self) -> bool;
}
```

### 7.6 模型（`models.rs` 只读镜像；`Option` 只给语义上真可缺席的键）

> 仪表盘聚合类型（`DashboardData` / `DashProjects` / `DashWork` / `LangCount` /
> `DashMilestones` / `MilestoneCounts` / `ActiveProject`）与 `McpTool` 也定义在本文件；
> 结构见 §7.3 的类型契约块，下面不再重复。

```rust
pub struct StatusEnvelope { projects: Vec<Project>, summary: Summary, language: String }
pub struct Summary {
    project_count, degraded_stores, listed_projects, failed_projects, active_projects,
    stale_projects, dirty_projects, branch_count, repo_branch_total,
    branch_truncated_projects, branch_unknown_projects: i64,
    generated_at: String,
}
pub struct Project {
    store_health: String, id: String, name: String, path: String, kind: String, remote: String,
    error: Option<String>, headline: String,
    current_branch: String, default_branch: String,
    user_dirty_count: i64, untracked_count: i64, untracked_error: String,
    stash_count: i64, worktree_count: i64,
    last_commit_ago: String, last_commit_at: String,
    commit_types: Vec<CommitTypeCount>, commit_types_truncated: bool,
    branches: Vec<Branch>, repo_branch_count: i64,
    journal: Vec<JournalEntry>, journal_truncated: bool, journal_limit: i64,
    journal_unparsable_lines: i64,
    warnings: Vec<String>, tags: Vec<String>, manifests: Vec<String>,
    dirty: Option<Dirty>, commit_count: i64, overall: Option<Overall>, docs: Vec<DocEntry>,
    progress: Progress, fetched_at: String,
}
// dirty/overall 用 Option：失败项目实测是 {}，不是完整对象。
// 严格模型 + 缺键报错会把整个 status 解挂；加 default 又会把「读不出来」
// 渲染成 ok=false/0 files 的「假干净」。Option 是第三种状态。
impl Project {
    pub fn dirty_state(&self) -> Reading<&Dirty>;    // None 或 ok=false => NotRead
    pub fn overall_state(&self) -> Reading<&Overall>; // None 或 summary/notes 全空（失败项目的 {}）=> NotRead
}
pub struct Dirty { ok: bool, clean: bool, staged: i64, modified: i64,
                   untracked: i64, conflicts: i64, total: i64, files: Vec<String>,
                   err: Option<String> }                       // ok=false => 读不出来
pub struct Overall { summary: String, notes: Vec<String> }
pub struct Progress { updated_at, last_update_at, last_track_at, last_deep_at: String,
                      entry_count: i64, entry_count_truncated: bool,
                      entries_kept: i64, run_count: i64 }
pub struct DocEntry { file: String, exists: bool }
pub struct Branch {
    name, status, status_label, head, head_short, head_date, head_ago, head_subject,
    summary: String, highlights: Vec<String>, next_steps: Vec<String>,
    ahead_of_default: i64, merged: bool, pending_commits: i64, baseline_reset: bool,
    provider: String, is_current: bool, is_default: bool, updated_at: String, stale_days: i64,
}
pub struct JournalEntry {
    id, at, project, project_id, branch, mode, source, provider, provider_label, summary: String,
    commit_count: i64, commit_count_scope: Option<String>,
    commit_count_truncated: Option<bool>, repo_branch_count: Option<i64>,
    branch_count_truncated: Option<bool>,
    highlights: Vec<String>, next_steps: Vec<String>, notes: Vec<String>,
    docs: Option<Vec<String>>,                                  // 浅更新不写 → None
}
pub struct CommitTypeCount { type_: String /* rename "type" */, count: i64 }
pub struct MilestoneList { milestones: Vec<Milestone>, store_health: String, read_count: i64,
                           orphaned: Vec<OrphanedMilestone>, excluded_disabled: i64 }
pub struct Milestone {
    // 只读出口 17 键；没有 id、没有 orphaned
    project_id: String, name: String, description: String, target_date: String,
    tag: String, status: String, created_at: String, completed_at: String,
    project_name: String, tag_name: String, tag_reached: bool,
    commits_since: i64, commits_since_readable: bool, days_to_target: i64,
    overdue: bool, git_readable: bool, unverified_reason: String,
}
// 孤儿条目是**另一种形状**（实测 7 键），不能塞进 Milestone：
// {id, projectId, name, description, targetDate, status, orphaned}
pub struct OrphanedMilestone { id: String, project_id: String, name: String,
                               description: String, target_date: String,
                               status: String, orphaned: bool }
// `milestone add` 回执里是**存储形状**（实测 9 键），也不是只读 17 键：
// {id, projectId, name, description, targetDate, tag, status, createdAt, completedAt}
pub struct StoredMilestone { id: String, project_id: String, name: String,
                             description: String, target_date: String, tag: String,
                             status: String, created_at: String, completed_at: String }
pub struct DocsPayload { project: Option<String>, docs: Vec<DocContent>, unreadable: Vec<UnreadableDocs> }
pub struct DocContent { project: String, file: String, content: String }
pub struct UnreadableDocs { project: String, unreadable: String }   // 逗号分隔
pub struct JournalPayload { entries: Vec<JournalEntry>, limit: i64, branches: String,
                            projects: i64, unparsable_lines: i64, window_exhausted: bool,
                            branch_window_exhausted: BTreeMap<String, String> }
pub struct GitOpResponse { op: String, ok: bool, output: String, project: String }
pub struct GitStatusPayload { ok: bool, err: Option<String>, entries: Vec<GitEntry>, total: i64 }
pub struct GitEntry { xy: String, file: String, kind: String }
pub struct UpdateReceipt {
    ok: bool, mode: String, project_id: String, project: String,
    provider: String, provider_label: String,
    branch_count: Option<i64>, repo_branch_count: Option<i64>, branch_count_truncated: Option<bool>,
    commit_count: Option<i64>, docs: Option<Vec<DocChange>>,
    journal_entry: Option<JournalEntry>, highlights: Option<Vec<String>>, at: Option<String>,
}
pub struct DocChange { file: String, changed: bool, created: bool, backup: String }
pub struct MultiResults { results: Vec<serde_json::Value>, count: i64, failed: i64, succeeded: i64 }
pub struct ScanPayload { candidates: Vec<ScanCandidate>, found, added, existing, dirs_visited: i64,
                         truncated: bool, depth_capped: bool, unreadable: Vec<String>, depth: i64 }
pub struct ScanCandidate { name: String, path: String, kind: String, remote: String }
pub struct RegistryEntry { id, name, path, kind, remote, added_at: String,
                           tags: Vec<String>, disabled: bool }
pub struct RenderCheck { ok: bool, artifact: String, exists: bool, path: String }
pub struct MilestoneActionReceipt { project: String, milestone: String, requested: String,
                                   status: String, applied: bool }
pub struct MilestoneRemoveReceipt { project: String, milestone: String, removed: bool }
pub struct MilestoneAddReceipt { project: String, milestone: StoredMilestone, created: bool }
pub struct ConfidenceReport {
    root: String, score: i64, dimensions: Vec<Dimension>, penalty_by_file: Vec<FilePenalty>,
    findings: Vec<Finding>, ast_used: bool, ast_note: String,
    by_kind: Vec<KindCount>, capped_kind: bool, capped_total: bool,
    files_analyzed: i64, semantics: String,
}
pub struct Dimension { id, label: String, penalty: i64, findings: i64, score: i64 }
pub struct FilePenalty { file: String, penalty: i64 }
pub struct Finding { kind, file, symbol, evidence: String, line: i64, weight: i64 }
pub struct KindCount { kind, label: String, count: i64, weight: i64 }
pub struct PatchReport { schema: String, overall: f64,
                         signals: BTreeMap<String, Option<f64>>,
                         entities: Vec<PatchEntity>, uncertain: Vec<Uncertain>, diagnostics: PatchDiag }
pub struct PatchEntity { id, kind, file: String, confidence: f64, line: i64,
                         relations: Vec<PatchRelation> }
pub struct PatchRelation { type_, target: String, confidence: f64 }
pub struct Uncertain { id, issue, detail: String, candidates: Vec<String>, context_ref: Ref }
pub struct Ref { file: String, line: i64 }
pub struct PatchDiag { total_entities, total_relations, parse_errors, patch_files, added_lines: i64,
                       null_signals: Vec<String>, null_signals_note: String }
pub struct MergedReport { schema: String, overall: f64,
                          signals: BTreeMap<String, Option<f64>>,
                          entities: Vec<MergedEntity>, alerts: Vec<Alert>,
                          sources: Sources, diagnostics: MergeDiag }
pub struct MergedEntity { id, kind, file: String, confidence: f64, line: i64,
                          relations: Vec<PatchRelation>, source: String,
                          verdict: Option<String>, reason: Option<String>,
                          evidence_refs: Option<Vec<String>> }
pub struct Alert { level, type_, detail: String }
pub struct Sources { algorithm: bool, agent: bool }
pub struct MergeDiag { certain_from_algorithm, reviewed_by_agent, deferred: i64 }
pub struct ContextPayload { scope: String, budget: i64, context: String }
pub struct ToolsManifest { tools: Vec<ToolDef>, note: Option<String> }
pub struct ToolDef { name, description, params: String }       // params 逗号分隔；required = 全部
```

**读不出来的统一表示**：

```rust
pub enum Reading<T> { Known(T), NotRead }
pub fn read_i64(v: i64) -> Reading<i64>;     // v < 0 => NotRead
pub fn read_opt_i64(v: Option<i64>) -> Reading<i64>;
```

**四态**：`Load<T> { Idle, Loading, Ready(T), Failed(EngineError) }`。
**未知**：`Milestone.status == "unknown"`、`git_readable == false`、`stale_days == -1`、
`dirty_state() == NotRead`（`dirty:{}` 或 `ok:false`）
一律渲染成「无法核验/读不出来」，绝不并入 0/进行中/干净。

### 7.7 UI 原语（core 实现；视图只用这些）

```rust
pub fn cls(parts: &[&str]) -> String;                    // debug 校验 CLASS_TOKENS
pub fn el(classes: &[&str]) -> Div;
pub fn text(classes: &[&str], s: impl Into<SharedString>) -> Div;
pub fn btn(classes: &[&str], label: impl Into<String>) -> Div;
pub fn chip(text: String, tone: Tone) -> Div;
pub fn dot(tone: Tone) -> Div;
pub fn badge(text: String, tone: Tone) -> Div;
pub fn bar(fraction: f32, tone: Tone) -> Div;                            // 内部 inline width
pub fn stackbar(segments: &[(String, f32, usize)]) -> Div;               // 内部 s1..s12
pub fn score_ring(score: i64, max: i64) -> Div;                          // canvas
pub fn tile(span: u8, child: impl IntoElement) -> Div;                   // span-2..12
pub fn kpi(label, value, hint, foot: String) -> Div;
pub fn section(title, sub: Option<String>, body: impl IntoElement) -> Div;
pub fn empty(icon: &str, title, body: String, actions: Vec<Div>) -> Div;
pub fn banner(tone: Tone, title: String, body: String, action: Option<Div>) -> Div;
pub fn feedback_block(state: &AppState) -> Div;                          // feedback + route_note + startup_error
pub fn truncation(items: &[Truncation]) -> Div;                          // 「谁砍的、砍了多少」
pub fn modal(title: String, body: Div, foot: Div, width: ModalWidth) -> Div;
pub fn toast_view(t: &Toast) -> Div;
pub fn menu_at(x: f32, y: f32, items: &[MenuItem]) -> Div;
pub fn spinner() -> Div;
pub fn markdown(blocks: &[MdBlock]) -> Div;

pub enum Tone { Ok, Warn, Stale, Err, Info, Unknown, Accent, Idle }
pub struct Truncation { pub layer: &'static str, pub shown: usize, pub total: Option<usize>, pub note: String }
```

### 7.8 派生纯函数（core；四组共用，禁止各写一份）

```rust
pub fn status_tone(p: &Project) -> Tone;                 // err > stale > warn > ok
pub fn status_word(p: &Project) -> &'static str;         // 干净/有未提交/停滞/读不出来
pub fn is_pending(p: &Project) -> bool;                  // dirty_state().Known(d).total>0 || untracked>0 || stash>0（读不出来不算）
pub fn board_column(p: &Project) -> BoardColumn;         // Pending > Stale > Active > Other（顺序是判据）
pub fn pending_count(ps: &[Project]) -> usize;
pub fn milestone_rate(c: &MilestoneCounts) -> Option<f32>;   // done / (done+open)；分母 0 → None
pub fn milestone_lower_bound(list: &MilestoneList) -> Option<Truncation>;
    // visible = milestones.len() + orphaned.len() + excludedDisabled；< readCount 才算下界
pub fn age_days(iso: &str) -> Reading<i64>;               // 解析 YYYY-MM-DD；失败 → NotRead
pub fn journal_scope_badge(e: &JournalEntry) -> ScopeBadge;  // New / RepoTotal / Unknown / NotRead
pub fn language_disclosures(d: &DashboardData, shown: usize) -> Vec<Truncation>;
pub fn dirty_label(v: i64) -> String;                    // -1 → 读不出来
pub fn commit_count_label(v: i64, scope: Option<&str>) -> String;
pub fn short_iso(s: &str) -> String;                      // 2026-10-01T00:05:35… → 10-01 00:05
pub fn human_ago(t: Instant) -> String;                   // 刚刚/N 秒前/N 分钟前
pub fn redact_url(s: &str) -> String;                     // 只保留 scheme://host:port/…
```

`BoardColumn`：`Pending / Stale / Active / Other`。
`board_column` 必须先判 Pending，再判 Stale，再 Active，最后 Other——否则「又脏又停滞」的项目会丢掉更紧急的状态。

### 7.9 设置 / 语言 / 系统

```rust
pub struct Settings { pub lang: Lang, pub ai: AiConfig, pub automation: AutomationConfig,
                      pub engine_bin: Option<String> }
pub struct AiConfig { pub preset: String, pub base_url: String, pub model: String,
                      pub allow_write: bool }
pub struct AutomationConfig { pub interval_hours: u32, pub shallow: bool }   // 0 = off
pub enum Lang { ZhCn, En, ZhTw, Ja }
impl Lang { pub fn engine_code(&self) -> &'static str; }   // zh -> "zh"；tw -> "zh"；en/ja -> "en"

pub fn config_dir() -> PathBuf;                            // macOS Application Support / Win APPDATA / Linux XDG
pub fn load_settings() -> (Settings, Vec<String>);         // 第二个返回值 = 需要向用户披露的问题
pub fn save_settings(s: &Settings) -> Result<(), String>;  // 原子写；settings.json 0600（Win 依赖用户目录 ACL）
pub fn load_secret() -> Option<String>;
pub fn save_secret(key: &str) -> Result<(), String>;       // 空串 = 删除；secrets.json 0600（Win 同上）

#[macro_export] macro_rules! tr { ($lang:expr, $zh:literal, $en:literal, $tw:literal, $ja:literal) => { ... } }
```

`sysopen`：

```rust
pub fn reveal(path: &str);          // macOS: open -R；Win: explorer /select,；Linux: xdg-open dir
pub fn terminal(path: &str);        // macOS: open -a Terminal；Win: cmd /K cd /d；Linux: x-terminal-emulator
pub fn url(u: &str);
pub fn pick_folder() -> Option<String>;   // macOS osascript choose folder；Win PowerShell FolderBrowserDialog；Linux zenity
pub fn write_temp(prefix: &str, text: &str) -> Result<PathBuf, String>;  // 配置目录下 tmp/，启动时清理 >1 天
pub fn read_text(path: &Path) -> Result<String, String>;
pub fn read_snippet(path: &str, line: i64, radius: usize) -> Result<Vec<String>, String>;  // 补丁体检的代码片段
```

> 视图不得直接 `std::fs`；补丁页的 diff/agent.json 写入与代码片段读取都走上面三个 core helper。

### 7.10 AI 契约

```rust
pub struct ChatMessage { pub role: Role, pub content: String,
                         pub tool_calls: Vec<ToolCall>, pub tool_call_id: Option<String>,
                         pub is_error: bool }             // is_error 只给 UI，不发给模型
pub enum Role { System, User, Assistant, Tool }
pub struct ToolCall { pub id: String, pub name: String, pub arguments: String }
pub struct ChatResponse { pub content: String, pub tool_calls: Vec<ToolCall>,
                          pub finish_reason: String, pub usage: Option<Usage> }
pub struct Usage { pub prompt_tokens: i64, pub completion_tokens: i64 }
pub enum AiError { NotConfigured, CurlMissing, Http { status: i64, message: String },
                   Network { host: String, message: String }, Cancelled, Timeout, Json(String) }
pub enum ToolError { Unknown(String), Denied { name: String }, BadArgs(String), Engine(String) }

// 引擎 tools --json 的清单类型（28 个，params 是逗号串，**没有类型/可选性**）：
pub struct ToolDef { name, description, params: String }
// AI 真正用的 schema：唯一来源是 `moongit mcp` 的 tools/list（33 个，inputSchema 有 type/required）。
// ⚠️ McpTool 定义在 models.rs（engine 不能反向依赖 ai）；AiTool 定义在 ai/tools.rs。
pub struct McpTool { pub name: String, pub description: String,
                     pub input_schema: serde_json::Value }
pub struct AiTool { pub name: String, pub description: String,
                    pub parameters: serde_json::Value }   // OpenAI function.parameters
pub fn definitions(tools: &[McpTool]) -> Vec<AiTool>;     // 原样转 inputSchema，不手写 required
pub fn decode_args(raw: &str) -> Result<serde_json::Value, String>;
pub fn missing_required(args: &serde_json::Value, required: &[String]) -> Vec<String>;
pub fn chat(cfg: &AiConfig, key: &str, msgs: &[ChatMessage], tools: &[AiTool],
            cancel: &CancelToken) -> Result<ChatResponse, AiError>;
pub fn test_connection(cfg: &AiConfig, key: &str) -> Result<String, AiError>;

pub fn execute(tool: &AiTool, args: &str, engine: &Engine, allow_write: bool,
               ctx: &JobCtx) -> Result<String, ToolError>;
pub fn outcome_finish(text: &str, executed_tools: usize, max_rounds: bool) -> AgentOutcome;
pub fn trim_history(msgs: &mut Vec<ChatMessage>, max_chars: usize) -> Option<usize>;  // 返回被省略条数

pub fn run(cfg: &AiConfig, key: &str, engine: &Engine, scope: AiScope,
           history: &[ChatMessage], question: &str, allow_write: bool, ctx: &JobCtx)
           -> Result<AgentRun, AiError>;
pub struct AgentRun { pub messages: Vec<ChatMessage>, pub outcome: AgentOutcome,
                      pub tool_events: Vec<ToolEvent>, pub omitted: Option<usize> }
pub struct ToolEvent { pub name: String, pub args: String, pub ok: bool, pub text: String }

pub enum AgentOutcome { Text(String), ToolsOnly(String), Failed(String) }
```

- `execute` 的映射表覆盖**全部 33 个 MCP 工具**（实测 `tools/list`）：`get_project_status`→`status <name> --json`、
  `git_op`→`git <op> <name>`、`milestone_action`→`milestone <action>`、`codegraph_*`→`graph *`、
  `codegraph_patch_confidence`→`graph patchconf --patch`、`codegraph_patch_merge`→`graph patchconf --merge`、
  `arch_*`/`index_*`/`confidence_*`/`render`→同名 CLI 子命令。表里没有的名字**不执行**，回 `ToolError::Unknown`。
- 工具 schema 的唯一来源是 `moongit mcp` 的 `tools/list`（33 个，`inputSchema` 自带 type/properties/required），
  不是 `tools --json` 的 `params` 逗号串。`Engine::mcp_tools()` 一次性 spawn `moongit mcp`、发
  `initialize` + `tools/list`、读完两行就关 stdin（不常驻、无 HTTP）；超时 10s。
  `tools --json` 只用于能力清单展示/交叉校验，**不参与 required 判定**。
  实测 `arch_query`/`confidence_query`/`render` 的 required 只有 `name`，其余是可选参数；
  「全部 required」会让模型给可选参数发垃圾值，也会让 execute 拒绝合法省略。
- `execute(tool, args, ...)` 用 `tool.parameters.required` 校验；`decode_args` 先拦畸形 JSON，
  缺必填**不执行**、只回报让模型重试。另配 `tests/` 断言「MCP 清单里的每个工具都有 execute 实现」
  +「execute 不认识的工具不执行」+「可选参数省略能通过」。
- 工具返回给模型前做二次截断（16000 字符），截断必须自报「客户端截断，原文 N 字符」。
- `outcome_finish`：有文本 → Text；文本空但执行过工具 → ToolsOnly（「已执行完并且生效了：X，不要重复执行」）；
  两者皆空 → Failed。**已产生副作用的动作绝不能报失败**。
- 写工具（update/deep/track/git_op 的 pull|push|commit|stash|unstash/milestone_add/milestone_action/add_project/
  arch_gen/arch_update/index_gen/index_update/confidence_gen/render）默认拒绝执行；
  `git_op` 的 `status`/`fetch` 视为读，其余视为写。设置里 `allow_write=true` 才执行写工具。
  拒绝也要作为工具结果回给模型，让它解释，而不是静默失败。

---

## 8. 引擎命令映射（UI 动作 → 命令 → 解析）

| UI 动作 | 命令 | 解析 / 备注 |
|---|---|---|
| 启动/刷新（全量） | `status --json --quiet` | `StatusEnvelope`；失败项目逐条展示 `error` |
| 轻刷新 | `status --json --quiet` | 只刷 status；不动 dashboard/milestones |
| 仪表盘 | `dashboard --json` | `DashboardData` |
| 里程碑页 | `milestone list --json` | `MilestoneList`；**rc=1 时也要解析载荷**，storeHealth≠ok 另挂降级说明 |
| 项目日志 | `journal <p> --json [--branch B] [--limit N]` | `JournalPayload`；`windowExhausted`/`branchWindowExhausted`/`unparsableLines` 全披露 |
| 项目文档 | `docs <p> --json` | `DocsPayload`；`unreadable[]` 逐名披露 |
| 提交弹层 | `git status <p> --json` | `GitOpResponse` → 内层 `output` 二次解码为 `GitStatusPayload` |
| pull/push/fetch/stash/unstash | `git <op> <p> --json` | `GitOpResponse.ok`；失败时 `output` 是原因 |
| 提交 | `git commit <p> --message M --paths a,b --json` | 同上；`--paths` 逗号分隔，含逗号的路径无法单独提交（见 13） |
| 浅更新（单项目） | `update <p> --json --quiet` | `UpdateReceipt`；docs 三态 |
| 深更新（单项目） | `deep <p> --json --quiet` | `UpdateReceipt`（mode=deep） |
| 更新全部 | `update --json --quiet` / `deep --json --quiet` | `MultiResults`；`failed>0` 也解析载荷并逐项展示 |
| 里程碑动作 | `milestone done|reopen|drop <p> <name> --json` | `MilestoneActionReceipt`；显示 `status/applied`，不是 `requested` |
| 删除里程碑 | `milestone remove <p> <name> --json` | `MilestoneRemoveReceipt` |
| 新建里程碑 | `milestone add <p> <name> [--tag] [--date] [--desc] --json` | `MilestoneAddReceipt`（`milestone` 是 **StoredMilestone 9 键**：id/projectId/name/description/targetDate/tag/status/createdAt/completedAt）；`created=false` 是「已存在」不是失败 |
| 扫描 | `scan <roots...> --depth N [--git-only] --json` | `ScanPayload`；三轴覆盖度 |
| 添加 | `add <path> [--name N] --json` | `RegistryEntry` |
| 移除 | `remove <p> --json` | `RegistryEntry`；第二次 rc=1 + stderr |
| 产物探测 | `render check <index|arch> <p> --json` | `RenderCheck`；rc≠0 是 `CheckFailed`，不是 `Missing` |
| 代码置信度 | `graph confidence <p> --json` / `--llm` | `ConfidenceReport` / 纯文本 prompt |
| 补丁体检 | `graph patchconf <p> --patch <f> --json` | `PatchReport` |
| 取 Agent 任务 | `graph patchconf <p> --patch <f> --skill` | 纯文本（注意：**必须同时给 `--patch`**） |
| 合并终稿 | `graph patchconf --merge <a.json> <b.json> --json` | `MergedReport` |
| AI 上下文 | `context [p] --budget 12000 --json` | `ContextPayload`；只喂 `.context`，不喂信封 |
| AI 工具清单（schema） | `moongit mcp` 的 `initialize` + `tools/list`（一次性 stdio） | `McpTool`（inputSchema 带 type/required）；**AI 的定义只认这份** |
| AI 能力清单（展示/校验） | `tools --json` | `ToolsManifest`；只用于展示与交叉校验，不参与 required |
| 注册表 | `list --json` | **裸数组** `Vec<RegistryEntry>` |
| 引擎诊断 | `doctor` | 文本表格；模态里等宽显示 |
| 语言 | `config get language --json` / `config set language zh|en` | 裸字符串 / 文本回执 |
| 读工作区 diff | `git -C <p> diff HEAD`（**非引擎**） | 写临时文件，喂 `graph patchconf --patch` |

**超时**：读 90s；写 1800s；git 180s；scan 600s；confidence/patch 300s。超时 = kill + `EngineError::Timeout`。

---

## 9. 页面规格

> 所有页面只读 `&AppState`；按钮 listener 里 `cx.stop_propagation()` 再 `state.dispatch(...)`，
> 防止点卡片内按钮同时触发卡片跳转。
>
> 每个页面的 `.main-scroll` **第一项**统一是 `ui::feedback_block(state)`：渲染 `feedback`（成功/失败）、
> `route_note`（深链说明，info）、`startup_error`（引擎不可用）三块，顺序固定；页面自己不再各写一份。
> 主滚动容器的 id 必须是 `scroll-<Route::key()>`（`Route::key()` 含项目名/tab），`navigate` 的
> `pending_scroll` 靠它复位到顶部。

### 9.1 侧栏（sidebarscan）

- 结构：品牌头（deepDolphin / moonGit 项目群进度引擎）→ 搜索框 → `.sidebar-scroll`
  （视图组 + 仓库组 + 添加项目）→ `.sidebar-foot`。
- 搜索：`.search-box` + 原生 `input.id("sidebar-search")` + `.search-clear`；
  `on_input` 更新 `SidebarUi.query`；匹配 name 或 currentBranch（ASCII 不区分大小写）。
  空态：有查询无匹配 → 「无匹配项目」；无项目 → 「还没有项目」+「添加/扫描」按钮。
- 视图组（带计数，计数为 `None` 时不显示 0）：
  - 仪表盘 `listedProjects`
  - 看板 `pending_count(status.projects)`（与看板列、仪表盘 KPI 同源）
  - 里程碑 `dashboard.milestones.counts.open`（与仪表盘同一口径，不从 `milestones[]` 自己重算）；
    `counts.unknown>0` 时右侧再加一个小 `unknown` 点
  - 代码置信度 / 补丁体检（无计数）
  - AI 助手
- 仓库组：行 = 状态点 + 名称 + 脏度徽标（`Reading`；未知显示 `?`，不是 0）。
  状态点：`error/storeHealth!=ok` → err；`stale`（last commit >30d）→ stale；
  `dirty/untracked/stash>0` → warn；否则 ok。`kind!="git"` 在 tooltip 里写「非 git 仓库」。
- 底部：忙碌/空闲点 + `human_ago(last_refresh)` + 「未刷新」说明；引擎短名；
  若 `engine_warnings` 非空，显示 `! N` 徽标，点开模态逐条列出（这些是读命令 stderr 的告警，不是失败）；
  语言菜单（中/EN/繁/日，选中即 `SetLanguage`）；设置齿轮。
- 组头可折叠（`SidebarUi.collapsed_views/collapsed_repos`）；折叠只影响显示，不影响搜索匹配。

### 9.2 仪表盘（dashboard）

固定区：

1. `.main-head`：标题「项目群脉搏」；副标题 `listedProjects 个项目 · 数据时间 <generatedAt 短> · 引擎 <短名>`；
   右侧动作：刷新（⌘R）、重新索引（浅更新全部，确认）、AI 简报、更多菜单（深更新全部/诊断）。
2. `.dash-hero`（glass，固定）：28px `listedProjects`；一行总体状态；
   健康构成条（ok/warn/stale/err 四段，按项目数，canvas 或 `.stackbar`）+
   图例；右侧「失败 N · 分支读不出来 M」；`overall` 不可读时显示「读不出来」。
3. `.dash-filters`（固定）：时间跨度 `.seg`（全量/30天/7天）、提交类型 chips（只列真实出现的类型）、
   清除筛选、右侧「筛选只影响项目卡，不改 KPI」说明。

滚动区 `.main-scroll`：

4. KPI 四磁贴（`span-3`）：
   - **项目总数**：`dashboard.projects.listed`（不是 total）；副说明「可读 R · 失败 F · 7d 活跃 A7 · 30d 活跃 A30」。
   - **里程碑完成率**：`done/(done+open)`；分母 0 → `—` +「暂无进行中或已达成」；
     副说明 `done D · open O · unknown U（单列）· dropped X`。
   - **待处理**：`pending_count(status.projects)`（项目数）；副说明「未提交 · 未跟踪 · stash」；
     与侧栏徽标/看板列同源；若 engine `dashboard.projects.dirty` 不同，不显示第二个数字，避免两套口径。
   - **仓库分支数**：`summary.repo_branch_total`；副说明「已跟踪 branch_count · 分支数读不出来 N 个项目 · 截断 M 个项目」。
5. 项目磁贴网格（`span-4` 每个；整卡可点 → `Project{name, Overview}`）：
   - 头：状态点、名称（`t-ellipsis` + title）、状态词、当前分支 chip。
   - headline：`headline` 为空 → 「暂无摘要」；`error` → 红字原因（不是空白）。
   - 里程碑：进度条 + `done/total`；unknown 单列「U 无法核验」。
   - 提交构成：`.stackbar`（top 5 类型）+ `.legend`；>5 类 → 「还有 N 类（合计 M）」+
     `commitTypesTruncated` 时「样本 N 条提交」（N=counts 之和）。
   - 底：HEAD 短 SHA + 标题（`headShort` 从当前分支取；没有 → 「读不出来」）、
     脏度 chips（未知显示 `?`）、待记录徽标（`pending_commits`，baselineReset 时不显示数字）、「进入 →」。
   - 时间筛选：`age_days(lastCommitAt)`；NotRead 的项目**保留**并加 chip「时间读不出来」。
6. 语言分布磁贴（`span-6`）：
   - 前 8 条 `.bar` + 百分比；「展开全部」显示到引擎上限 12 条；
   - 三条披露：`languagesTruncated`（文件采样被截断）、`languagesTopCut`（语言条数被引擎截断）、
     `shown < languages.len()`（界面自己显示前 8）；
   - `languagesFailed>0` → 列原因（最多 3 条 + 还有 N 条），空态分「暂无数据」/「未采集到语言数据」。
7. 里程碑概览磁贴（`span-6`）：counts 四态 + 前 5 条（项目/名称/状态点/tag）；
   `storeHealth!=ok` 时红色披露「存储读不出来，0 不是没有」；「查看全部」→ 里程碑页。
8. 活跃项目磁贴（`span-12`）：`activeProjects` 行（名称/headline/lastCommitAgo）；空态说明。
9. 空态：无项目 → `.empty` +「添加项目 / 扫描目录」；加载中 → 骨架磁贴；失败 → banner + 重试。

### 9.3 看板（boardconf）

- 四列：待处理 / 活跃中 / 久未更新 / 其他；`.board` 4 列（<1180 时 2×2）。
- 每列头：标题 + 计数 + 判据小字。**计数必须等于实际行数**（同一份 `Vec` 派生）。
- 判据（`board_column`，顺序即优先级）：
  1. Pending：`is_pending`（dirty.total>0 || untracked>0 || stash>0；读不出来不算）；
  2. Stale：`age_days(lastCommitAt) > 30`（或当前分支 `staleDays>30`）；
  3. Active：`age_days <= 7`；
  4. Other：其余 + 时间读不出来（加 chip「时间读不出来」）。
- 空列：`.empty` 写这一列的判据（不是「暂无」两个字）。
- 卡片：名称、headline、chips（dirty/untracked/stash/pending/branch）、lastCommitAgo；
  快捷动作「浅更新」（确认，单项目）、「AI 简报」；整卡点击 → 项目概览。
- 顶部动作：刷新、全部浅更新、AI 看板简报；说明「待处理 = 项目数，与侧栏徽标同源」。

### 9.4 里程碑（project 组，全局页）

- 页头：标题 + 统计 chips（open/done/dropped/unknown 单列）+ 新建按钮。
- 降级：
  - `storeHealth != "ok"` 且 `readCount == 0` → **failed 态**：「里程碑存储读不出来（已留 .corrupt 副本）；
    这不是『还没有里程碑』」，给「打开数据目录」。
  - `storeHealth != "ok"` 且 `readCount > 0` → loaded + 降级 banner。
  - **明细下界用对账，不用 `items.len() < readCount`**：引擎的 readCount =
    `open+done+dropped+unknown+other+excludedDisabled+orphaned`（`flow/dashboard.cj:500-502`）。
    真实库实测 `readCount=1, milestones=[], orphaned=[1]`——按 items 比会误报。
    正确判据：`visible = milestones.len() + orphaned.len() + excludedDisabled`；
    `visible < readCount` 才提示「明细只是下界：引擎读到 R 条，当前可对账 V 条」。
    抽成 `derive::milestone_lower_bound(&MilestoneList) -> Option<Truncation>`。
  - `excludedDisabled > 0` → 「N 条属于已停用项目，未列入」。
  - `orphaned` → 独立小节「孤儿里程碑（项目已注销）」，绝不混进正常列表。
    **孤儿只读**：它的 `projectId` 已不在注册表，`milestone <action>` 收的是项目名，解析不出来；
    不给达成/重开/放弃/删除，只显示名称/描述/目标日期/状态 + 复制名称。
- 筛选：搜索（名称/描述/项目）+ 项目 chips（全部 + 有里程碑的项目，带计数）+ 状态 seg（全部/open/done/dropped/unknown）。
- 分组：按项目；组头项目名 + 计数；组内按状态（open → unknown → done → dropped）排序。
- 行（`milestone_row`，项目 tab 复用）：
  - 活条目用 `render_row(&Milestone)`（17 键）；孤儿用 `render_orphan(&OrphanedMilestone)`（7 键）。
    **不要**给孤儿套 `Milestone`——它没有 projectName/tagName/commitsSince 等 10 个键。
  - 状态点/词；名称；项目（活条目 `projectName`，孤儿 `projectId`）；tag chip（`tagName`，`tagReached` 绿/灰）；
    `commitsSince`（`commitsSinceReadable` 才显示数字，否则「提交数读不出来」）；
    `daysToTarget`（「还剩 N 天 / 已逾期 N 天」）；描述（`t-clamp-2`）。
  - 动作：open→达成/放弃；done→重开；unknown→**不给重开**（可删除）；
    任意→删除；右键菜单含全部动作 + 打开项目 + 复制名称。
  - 动作后按回执显示 `status/applied`：`applied=false` → 「未生效：<原因>」（如仓库读不出来），
    不要显示「已达成/已重开」。
- 新建 sheet（overlay）：项目 picker、名称（`id("ms-name")`，打开后 `window.focus_id`）、
  tag、日期（YYYY-MM-DD 文本 + 客户端校验）、描述；提交按钮在 project+name 非空前 `.is-disabled` 并显示原因；
  `created=false` → 信息条「已存在」，不是失败。
  成功后**不把回执里的 `StoredMilestone` 当活条目渲染**（它没有 projectName/tagName/commitsSince）；
  关 sheet、刷新 milestone list/dashboard，让只读 17 键条目重新出现。
- 确认：删除/放弃必须确认；达成/重开不确认。确认文案点名对象、说清「不可撤销/可重开/不删 git tag」；
  按钮用动词（「删除里程碑」「放弃里程碑」），只有删除/放弃染红。

### 9.5 项目工作区（project）

页头：面包屑（项目群 / 名称）、状态点/词、非 git chip、路径（点击复制）；
动作：刷新、更新菜单（浅/深/更新并生成摘要）、Git 菜单、打开菜单（Finder/Terminal/远端/复制路径）、更多（诊断）。

标签：概览 / 分支 / 日志 / 文档 / 里程碑 / 图谱。

#### 概览

- Hero 卡：headline、`overall_state()` 的 summary、warnings 逐条 `.banner.warn`、
  `overall_state()` 的 notes（去重 warnings 后）逐条；`overall_state()==NotRead` → 「总体摘要读不出来」。
  `headline` 空 → 「暂无摘要」；`error` → 红 banner「读不出来：<原因>」。
- 工程脉搏卡：
  - mergeHint：有 `!merged && name != default` 的分支 → 「N 个分支未合入默认分支」+ 前 5 个名字。
  - chips：dirty/untracked/stash/worktree；`-1` → 「读不出来」；`dirty_state()==NotRead` → 红条「结构化脏度读不出来」。
  - 脏文件清单：`dirty_state()` 为 Known 时前 20 个 `.path-text`；>20 → 「还有 N 个」；files 空且 ok → 「无未提交文件」。
  - tags/manifests：前 8 个 chip；>8 → 「还有 N 个」；空 → 「无」。
  - docs 存在性：每个 `docs[].file` 一个 chip（已建/未建）。
  - 提交类型行：top 5 + 「还有 N 类」；`commitTypesTruncated` → 「样本 N 条提交，不是全量」。
  - 最近提交：`headShort` + `headSubject`（当前分支）；缺失 → 「读不出来」。
  - 当前/默认分支 chips。
- 提交构成卡：`.stackbar` 全量（最多 12 类）+ 图例（类型/数量/百分比）+
  披露（样本 N 条；`commitTypesTruncated`）；空态「暂无提交类型数据」。
- Git 操作卡：pull/push/fetch/stash/unstash +「提交…」（打开弹层）；每个结果 toast（成功/失败原因）。
- 图谱卡：index/arch 两个 `.art`；状态 `Unknown/Missing/Ready/CheckFailed`；
  按钮「检查」「打开」（系统浏览器）「生成任务」（模态：`moongit skill graph` 工作流说明 + 复制 + 去 AI 助手）；
  文案说明「BUI 没有内嵌 webview，交付物由系统浏览器渲染」。

#### 分支

- 顶部披露：`repoBranchCount` vs `branches.len()`；`branchUnknownProjects` 在 status summary 里；
  「仓库共 N 个分支，本次展示 M 个（引擎上限）」。
- 分支卡：状态点/词、当前/默认 chip、名称；`provider != "rules"` 时 provider 徽章；
  `pendingCommits`（`baselineReset` 时不报数，写「基线已重置」）；`aheadOfDefault`（0=同步，>0=领先 N）；
  summary；HEAD 短 SHA + headSubject；highlights；`staleDays=-1` → 「停滞天数读不出来」，否则「N 天未更新」；
  nextSteps。

#### 日志

- 分支过滤 chips（全部 + status 里的分支）；切换时重新 `journal --branch`（不是客户端筛已加载窗口）。
- 每条：mode 标签、branch、`short_iso(at)`、summary；
  `commitCount` 徽章：scope `new` → 绿「+N 本轮新增」；`repoTotal` → 中性「累计 N」；
  scope 缺失 → 「口径未知 N」；`-1` → 「提交数读不出来」。
  `commitCountTruncated`/`branchCountTruncated`/`repoBranchCount` 各自披露；
  highlights/nextSteps/notes；deep 条目的 docs 列表（浅更新 `docs` 缺失 → 不显示「没改文档」）。
- 窗口披露：`windowExhausted` → 「只显示最近 limit 条，更早未加载」+「加载更多」（limit ×2）；
  `branchWindowExhausted[branch]`：
  - `"none-in-window"` → 「该分支的记录都在窗口之外，增大 limit 再查」；
  - `"window-full"` → 「窗口已满，更早还有记录」。
- `unparsableLines > 0` → 「N 行日志无法解析，已跳过」；`-1` → 「坏行数读不出来」。

#### 文档

- 加载中/失败/空/有内容四态分开；`unreadable[]` 逐名红条。
- 每份文档卡：文件名 + 路径；`exists=false` → 「引擎管着但还没建（运行一次 update 会创建）」；
  content 空 → 「文件存在但为空」；有内容 → Markdown（前 250 块 + 「显示全部（共 N 块）」披露）。
- Markdown：标题/段落/列表/引用/代码块/表格/行内粗斜体/行内代码/链接；
  图片只显示「图片：alt（v1 不加载图片）」；HTML 按文本显示。
- 「刷新文档」按钮。

#### 里程碑

- 过滤到当前项目的全局里程碑列表（复用 `milestone_row`）；新建时项目预选当前项目。

#### 图谱

- index/arch 两卡 + 置信度/补丁体检入口；产物说明 + 生成任务。
- 同时展示 `repoBranchCount`/最近一次 `progress.last_update_at` 等「为什么图会过期」的事实。

### 9.6 代码置信度（boardconf）

- 顶部：项目 picker（搜索模态）、运行、只看高权重（≥8）开关、复制 `--llm` 复核提示词。
- 结果：
  - 总分环（canvas）+ `semantics` 说明；`filesAnalyzed`。
  - dimensions（引擎给几条就画几条，可能 2 或 6）：label + 进度条 + score + findings。
  - `astUsed=false` 时把 `astNote` **原样**展示（降级/覆盖披露）。
  - `byKind` chips（kind/label/count/weight）；`cappedKind`/`cappedTotal` 时披露「类型明细被截断」。
  - findings：默认只显示 kind/file:line/symbol/weight；点击展开 evidence（`.finding-body`）；
    顶部「显示前 40 条 / 共 N 条」披露；「复制 --llm 提示词」用 `window.write_clipboard`。
- 空/失败/未选项目三态分开；运行中 spinner + 可停止。

### 9.7 补丁体检（boardconf）

- 顶部：项目 picker、「读取工作区 diff」（`git -C <p> diff HEAD`，非引擎）、
  或输入已有 diff 路径；「分析」；「取 Agent 任务」；「合并终稿」。
- 结果：
  - overall + signals（S1–S10）：数值显示 0–100 或 0–1（按引擎原值，不换算）；`null` → `—` + `.signal-null`，
    并显示 `null_signals_note`。
  - uncertain 列表：id/issue/detail/candidates/context_ref。
  - entities：confidence < 0.75 默认折叠；显示 file:line + 分数；点击展开代码片段
    （客户端读文件 ±5 行，读失败显示原因）；**不显示 diff 语法高亮**（纯等宽）。
  - diagnostics：total_entities/relations/parse_errors/patch_files/added_lines。
- Agent 任务：`graph patchconf <p> --patch <f> --skill` 文本模态（复制）。
- 合并：把 algorithm.json 写到临时文件；agent.json 支持「选择文件」或粘贴 JSON（客户端先校验 JSON）；
  `--merge` 后显示 final overall / alerts（high/medium/low）/ sources / diagnostics。
- 无 diff、diff 读取失败、分析失败、merge 失败四种状态分开。

### 9.8 扫描添加（sidebarscan）

- 单项目：
  - 路径（原生 input + `.field-box` + 「浏览…」+ 「添加」）；名称可选；客户端即时校验
    （路径存在且是目录；已知路径 → 「已注册为 X」+ 打开）。
  - 添加成功后刷新 registry/status/dashboard；toast「已注册 X」。
- 批量：
  - 根目录列表（输入/浏览/移除 chips）；深度 seg 1–6；`--git-only` switch；「扫描」。
  - 结果：found/added/existing/dirsVisited 四数字；候选列表（name/path/kind/remote）；
    三轴覆盖度：`truncated`（目录上限）、`depthCapped`（深度上限，下面可能还有）、`unreadable[]`（读不到，结果不完整）。
    每种给不同的处置建议（增大深度 / 换根 / 检查权限）。
- 已注册列表：名称、路径、kind、tags、disabled；「移除」确认（只取消注册，不删文件；进度库保留）。
- 说明：扫描会自动注册发现的项目；本页不提供 `--purge`（危险，延期）。
- 拖放：BUI 没有 OS 拖放，不画「拖到这里」的假承诺；只提供「浏览…」与手输。

### 9.9 设置（core）

- 左导航：通用 / AI / 自动化 / 关于；右 pane 滚动。
- 通用：
  - 界面语言 4 选 1（即时生效；同时尝试 `config set language`，失败要显示「界面已切换，引擎事实语言未更新」）。
  - 引擎事实语言（只读，来自 `status.language`）+ 「同步为当前界面语言」。
  - 引擎路径（只读 + 重新检测 + 选择引擎…）。
- AI：
  - 预设（OpenAI 兼容：OpenAI / DeepSeek / Moonshot / 自定义）+ base URL + model。
  - Key：遮罩显示 + 「编辑」；保存到 `secrets.json`（0600）；`.secret-note` 说明「未使用系统钥匙串」。
  - 「允许 AI 执行写操作」switch（默认关）。
  - 「测试连接」→ `GET <base>/models`；成功显示状态码；失败显示 host-only 的可执行错误。
  - 保存失败必须在页内可见（`.field-error`），**不许吞掉返回值**（修复原客户端的缺陷）。
- 自动化：
  - 定时更新：关 / 1 / 3 / 6 / 12 / 24 小时；浅/深；说明会改写托管文档、有备份。
  - 5 分钟轻刷新（status only）。
  - UiSender gate 未通过时：开关禁用 + 说明「BUI 后台唤醒不可用，自动任务已停用」。
- 关于：
  - 版本（CARGO_PKG_VERSION）、引擎路径、`doctor` 摘要（按钮打开模态）、仓库链接、日志/配置目录、许可证（GPL-3.0-or-later + 字体许可）。

### 9.10 AI 助手（core）

- 头部：范围 chip（整个项目群 / 项目 X；跟随当前路由或手动选）、模型名、设置按钮。
- 未配置：`.empty`「未配置 AI」+「去设置」，不报错。
- 对话：用户右侧气泡、助手左侧、工具事件 `<details>`（默认折叠）、错误气泡（红边 + 重试）。
- Composer：textarea + 发送/停止/清空；未配置/运行中/空输入三种禁用原因要显示。
- 建议问题（空态）：项目群最近变化 / 最需要处理的项目 / 总结某项目。
- 发送：
  - 取 `context`（scope 对应）→ 只取 `.context`；取 `moongit mcp` 的 `tools/list` schema（不是 `tools --json` 的 params 串）；
  - `trim_history`（最近 12 条 / 24000 字符）；被裁剪时在 UI 显示「本次只发送最近 N 条」；
  - 非流式请求（curl 子进程）；工具循环最多 4 轮；每轮工具事件实时显示；
  - 停止 → kill curl + 引擎子进程；消息保留为「已停止」，可重试；
  - 失败 → 错误气泡 + 保留用户提问 + 重试按钮（不丢历史）。
- 一次性结果（`ai_result` 模态）：Markdown + 复制 + 重新生成 + 关闭（Esc）；四处复用：
  项目说明、项目群说明、看板简报、更新后摘要。
- 更新后摘要：更新事实永远由代码生成（逐项目结果表）；AI 摘要单独一节，带「AI 生成」标签；
  AI 失败时更新仍算成功，摘要区显示原因。
- 中文输入提示：composer 下方一行 `.t-caption`「macOS 上 BUI 不支持输入法组合；可先在其他应用写好再粘贴」。

### 9.11 命令面板 / 菜单 / Toast / 确认（sidebarscan + core）

- 命令面板（⌘K）：`.overlay-top` + `.palette`；输入行是 **div 捕获键盘**（不是原生 input），
  支持字符、Backspace、↑/↓、Enter、Esc；条目 = 视图 + 项目 + 动作；
  每项右侧 kind（视图/项目/动作）与快捷键；无匹配空态。
- 右键菜单：`on_mouse_down(Right)` 取 `position` → `state.menu = Some(MenuState{x,y,items})`；
  菜单挂在 `.app` 根；透明 `.overlay-clear` 接外部点击；Esc 关闭；菜单项 `stop_propagation`。
- Toast：右下角，最多 3 条；`Action` 可带「重试/打开」；4s 后由后台线程发 `DismissToast`（sender 不可用则常驻）。
- 确认：`.overlay` + `.modal`；标题、正文（点名对象）、取消/确认；确认按钮动词、危险染红；
  Esc/点遮罩 = 取消；确认后执行 `PendingAction`。

---

## 10. 诚实披露规则（每条都要有 UI 落点）

1. **读不出来 ≠ 0**：`-1`、`dirty:{}`/`overall:{}`、`unknown`、`gitReadable=false`、`dirty_state()==NotRead`、`staleDays=-1`、
   `journalUnparsableLines=-1` 全部走 `Reading/NotRead`，显示「读不出来/无法核验」，不是 0/干净/进行中。
2. **每一层截断各自披露**：`Truncation { layer, shown, total, note }`。
   - journal 窗口（`windowExhausted` + limit）、坏行数；
   - 提交类型采样（`commitTypesTruncated` + 样本 N 条）与 UI top-5（「还有 N 类」）；
   - 语言三轴（文件截断 / 条数截断 / 界面前 8）；
   - 里程碑明细下界（visible = milestones + orphaned + excludedDisabled，与 readCount 对账）；
   - findings 前 40 条；
   - docs/Markdown 前 250 块；
   - 分支数（repoBranchCount vs 展示条数）；
   - 脏文件/tags/manifests 前 N 个。
3. **同名不同义的数字自带口径**：journal `commitCount` 的 `new/repoTotal/未知`；
   分支数「已跟踪/仓库总数」；待处理「项目数」。
4. **不知道不渲染成确定态**：`unknown` 里程碑、`unverifiedReason`、`null` 信号 `—`、
   `applied=false` 的动作回执。
5. **披露恒发**：空数组/空值也要有对应说明；不能 `if size>0` 才显示整节。
6. **失败原因来自载荷**：先 message，再 error/output，再 stderr，最后退出码；不许只报「退出码 1」。
7. **报错不泄凭据**：URL 只保留 `scheme://host:port/…`；key 永不进日志/错误/通知。
8. **已产生副作用的动作不报失败**：AI 摘要失败、后续刷新失败，都不能把已完成的更新/提交报成失败。

---

## 11. 文件组与并行计划

### 11.1 文件所有权（互不重叠）

| 组 | 文件 | 职责 |
|---|---|---|
| **core** | `src/lib.rs` `src/main.rs` `src/app.rs` `src/actions.rs` `src/state.rs` `src/jobs.rs` `src/derive.rs` `src/design.rs` `src/engine.rs` `src/models.rs` `src/l10n.rs` `src/settings.rs` `src/sysopen.rs` `src/ui/mod.rs` `src/ui/md.rs` `src/ui/icons.rs` `src/ai/mod.rs` `src/ai/provider.rs` `src/ai/agent.rs` `src/ai/tools.rs` `src/ai/prompt.rs` `src/views/mod.rs` `src/views/settings.rs` `src/views/agent.rs` `tests/class_contract.rs` `tests/models_decode.rs` | 设计系统、契约、引擎桥、Job/取消、模型、派生纯函数、设置、系统打开、Markdown、AI、设置页、AI 页、空桩与集成 |
| **dashboard** | `src/views/dashboard.rs` `src/views/dashboard/filters.rs` `src/views/dashboard/kpi.rs` `src/views/dashboard/tiles.rs` `src/views/dashboard/lang.rs` | 仪表盘：筛选、KPI 口径、项目磁贴、提交构成、语言/里程碑/活跃三节 |
| **project** | `src/views/project.rs` `src/views/project/overview.rs` `src/views/project/pulse.rs` `src/views/project/composition.rs` `src/views/project/branches.rs` `src/views/project/journal.rs` `src/views/project/docs.rs` `src/views/project/milestones.rs` `src/views/project/graph.rs` `src/views/project/commit_sheet.rs` `src/views/milestones.rs` `src/views/milestone_row.rs` | 项目六 tab、工程脉搏、分支、日志、文档、里程碑（含全局页）、提交弹层、图谱卡 |
| **boardconf** | `src/views/board.rs` `src/views/confidence.rs` `src/views/patch.rs` | 看板四列、代码置信度、补丁体检（含 skill/merge） |
| **sidebarscan** | `src/views/sidebar.rs` `src/views/scan.rs` `src/views/palette.rs` | 侧栏（搜索/计数/语言菜单/状态条）、扫描添加、命令面板 |

> **P0 空桩清单（必须全部建出来，否则 `views/mod.rs`/`AppRoot` 调不到函数、首轮 build 红）**：
> - `src/lib.rs`：声明所有 `pub mod`；`main.rs` 改为 `use deepdolphin_client::…`（tests 才能 import）。
> - 路由页（每个）：`XxxUi: Default + Clone`、`XxxAction { Noop }`、`render(state,cx)`、
>   `reduce(state,action,cx)`、`on_enter(state,cx)`。列表：dashboard / project / board /
>   milestones / confidence / patch / sidebar / scan / settings / agent。
> - `project.rs` 还要定义 `ProjectDetail`（§7.3 的字段 + `Default`），因为 `AppState` 引用它。
> - `palette.rs`：`PaletteUi`、`toggle`、`handle_key`、`render_overlay`（不走 Action）。
> - `milestone_row.rs`：`pub fn render_row(state, &Milestone, cx) -> Div` +
>   `pub fn render_orphan(state, &OrphanedMilestone, cx) -> Div`（project 组实现；P0 先返回 `.empty`）。
> - `views/mod.rs`：`pub fn render_route(state,cx)->Div`、`pub fn on_enter_route(state,cx)`，
>   match 所有 Route；`AppRoot` 只调这两个 + `sidebar::render` + `palette::render_overlay`。
> - `design.rs` 的 `SHEET`/`CLASS_TOKENS`、`ui::cls`、`models.rs` 全部 struct、`engine.rs` 的
>   `mcp_tools`/`parse`、`jobs.rs` 的 `spawn_job` 必须**先于**空桩存在（空桩会引用它们）。
>
> 之后 core 不再修改功能文件；功能组拿到即接管。空桩让 `cargo build` 在整个并行期保持可绿。

### 11.2 相位

| 相位 | 谁 | 交付 | 出口条件 |
|---|---|---|---|
| P0 契约与骨架 | core | `src/lib.rs`（tests 可 import）、令牌/类表/SHEET、models（含 DashboardData/MilestoneCounts/StoredMilestone/OrphanedMilestone）、`derive.rs`（status/board/milestone 下界等纯函数）、engine+错误+mcp_tools、Job、AppState/Action、ui 原语、l10n、settings、**全部路由页/ProjectDetail/palette/milestone_row 空桩**、class_contract/models_decode 测试 | `cargo build` + `cargo test` 绿；应用能开窗、侧栏可点、空页可渲染；`--selftest-ui-sender` gate 有结论 |
| P1 四组并行 | dashboard/project/boardconf/sidebarscan | 各自页面 + 纯函数单测 | 每组独立 `cargo build` 绿；不新增 core 文件；不改 core 契约 |
| P2 核心页与浮层 | core | 设置页（四 tab、保存失败可见）、`sysopen`/文件夹选择器、AppRoot 的 overlay 框架（confirm/menu/toast/ai_result 的渲染）、引擎诊断 | 保存失败可见；菜单/确认/Toast 可用；扫描页与 sidebarscan 联调通过 |
| P3 AI | core | provider（curl）、tools、agent 循环、settings AI tab、agent 页、AI 结果模态 | 未配置有引导；配置后多轮/工具/停止可用；写工具默认拒绝；`--agent-selftest` 绿 |
| P4 打磨与验收 | core + 四组 | 玻璃性能、空态/错误态、快捷键、README、跨平台构建说明 | 第 12 节清单全过 |

### 11.3 集成接缝与冲突避免

1. **core 只冻结一次**：P1 开始后，`actions.rs/state.rs/ui/*/models.rs/engine.rs` 的公共签名不再改；
   功能组需要新字段 → 加到自己模块的 `XxxUi`；需要新动作 → 加到自己模块的 `XxxAction`。
2. **四个功能组不互相 import**：跨页面跳转只通过 `Action::App(Navigate(Route))`；
   共享的展示逻辑（里程碑行、命令面板）由所属组提供 `pub fn render_row(...)`，其他组不复制。
3. **所有引擎访问只经 `Engine`**：视图里出现 `Command::new` 视为违规（class_contract 可扩展扫描）。
4. **测试文件不重叠**：功能组只在自己文件底部写 `#[cfg(test)] mod tests`；core 只写 `tests/` 下两个文件。
5. **每日集成**：`cargo build` + `cargo test`；任何人改契约必须在 PLAN 追加一条「契约变更」并通知四组。

---

## 12. 测试与验收

### 12.1 自动检查（必须跑）

| 检查 | 命令 | 断言 |
|---|---|---|
| 库目标 | `cargo build --lib` | `src/lib.rs` 存在且 `pub mod` 全部模块；`tests/` 可 `use deepdolphin_client::…`（二进制 crate 不能给集成测试 import） |
| 构建 | `cargo build` | 每个相位绿 |
| 单测 | `cargo test` | 下表的纯函数/契约测试 |
| 类契约 | `tests/class_contract.rs` | 视图无 `.class("`/`.style(`；无 `Command::new`/`std::fs::`；`CLASS_TOKENS` 非空；`ui::cls` 校验分支存在 |
| 模型解码 | `tests/models_decode.rs` | 真实引擎夹具：status（含失败项目 `dirty:{}`/`overall:{}`）、dashboard（projects/work/counts 全字段）、milestone 只读 17 键、**orphan 7 键**、**add 回执 9 键 StoredMilestone**、docs、journal、git status 内层、update/deep 回执、scan、remove、confidence、patchconf、merge |
| 看板判据 | `board::tests` | Pending > Stale > Active > Other；计数 == 行数；空列有判据 |
| KPI | `dashboard::tests` | 分母只 done+open；unknown 单列；listed 不是 total；待处理同源 |
| 里程碑 | `project::tests` | 分母、unknown、lower-bound、storeHealth 两态、applied 回执 |
| 日志口径 | `project::tests` | new/repoTotal/未知/-1 四态；window/branch 两种耗尽 |
| 提交弹层 | `project::tests` | 全选/半选/空选；干净 vs 读失败；逗号路径警示 |
| AI | `ai::tests` | outcome_finish 三态；decode_args/missing_required；trim_history；写工具拒绝；MCP schema 清单 ↔ execute 实现一一对应 |
| 语言 | `l10n::tests` | 四语言 key 无空串；`engine_code` 映射 |
| 设置 | `settings::tests` | 原子写；损坏文件保留 .bad；保存失败返回 Err |

### 12.2 手动冒烟（本次未运行，实施后必须跑）

```sh
cd deepDolphin/client
MOONGIT_BIN=/…/moonGit/target/release/bin/main cargo run
MOONGIT_BIN=… cargo run -- --project deeporca-site
MOONGIT_BIN=… cargo run -- --section milestones
MOONGIT_BIN=… cargo run -- --open-settings
MOONGIT_BIN=… cargo run -- --selftest-ui-sender
MOONGIT_BIN=… cargo run -- --agent-selftest
```

验收点：
- 引擎不可用时是安装引导页，不是崩溃/空白；
- 17 个项目全部出现；失败项目显示原因和 `-1` 的「读不出来」；
- 仪表盘筛选只影响项目卡，KPI 不变；
- 看板四列计数与行数一致；
- 里程碑 unknown 不当进行中；删除/放弃有确认；
- 项目六 tab 都能打开；文档四态正确；提交弹层默认全选、失败不关窗；
- 更新全部显示逐项目结果；停止真的杀掉子进程（看 `ps`），且提示是「已停止」不是「失败」；
- 玻璃滚动不卡（4 个面）；命令面板 ⌘K、⌘F、⌘R、Esc 可用（输入框聚焦时快捷键不可用要接受）；
- 设置保存失败可见；AI 未配置有引导；配置后对话/工具/停止可用。

### 12.3 本次已跑 / 未跑

- 已跑：现有 v0 的 `cargo build`（成功，0.43s）；第 1.1 节全部引擎命令（在真实库与 `/tmp` 沙箱）。
- 未跑：新方案代码、`cargo test`、class/models 测试、`--selftest-ui-sender`、`--agent-selftest`、app 启动、Windows/Linux 构建。

---

## 13. 明确延期与已知边界（逐条理由）

1. **菜单栏/系统托盘常驻**：BUI 0.5 没有 tray/status-item API（全仓 grep 无命中），也没有原生菜单栏。
   v1 用单窗口 + 侧栏；菜单栏形态延期。
2. **系统通知（Notification Center / 可操作通知）**：BUI 没有通知 API；用应用内 toast + 侧栏状态条。
3. **内嵌 WebView 渲染图谱**：BUI 的 iframe/embed 是灰块占位，没有 webview/JS 引擎。
   引擎的交互 HTML 交付物继续交给系统浏览器（与 v0 一致）。
4. **真·窗口级毛玻璃 / Mica / 透桌面**：Cocoa 宿主不 `setOpaque:NO`、不用 `NSVisualEffectView`，
   Win32 只有整窗 alpha。只能做「窗口内多级半透明 + 模糊自己画的内容」。
5. **macOS 中文输入法组合输入**：Cocoa 宿主没有 `NSTextInputClient`/`setMarkedText`，IME 候选窗不出现。
   影响所有文本输入（搜索、提交信息、AI 提问、路径）。兜底：粘贴、文件选择器、预设、按钮；
   长文本建议在其他应用写好再粘贴。这是 BUI 上游限制，不是本客户端能修的。
6. **OS 文件拖放**：BUI 没有宿主拖放事件；扫描/添加用「浏览…」平台文件夹选择器 + 手输。
   不画「拖到这里」的假承诺。
7. **系统钥匙串存 AI Key**：没有跨平台 API 且不新增依赖；v1 用 `secrets.json`（0600）+ 页面明示
   「未使用系统钥匙串」。macOS 可后续用 `security` CLI 接入。
8. **开机自启**：需要 LaunchAgent / 注册表 / .desktop，平台分支与权限提示都不小；v1 延期。
9. **AI 流式输出**：BUI 每帧重建整窗，per-token 刷新代价高；v1 非流式（请求中 spinner，完成后整段出现）。
   后续可用 30–60ms 合并 + `UiSender` 做伪流式。
10. **语法高亮 / 富 diff**：v1 用等宽纯文本；不引入高亮库。
11. **Markdown 图片/附件**：不加载本地/远程图片（安全与圆角裁剪限制）；只显示 alt 文本。
12. **多窗口设置/关于**：v1 用应用内路由/模态；BUI 虽可 `open_window`，但跨窗口共享 `Entity` 状态要额外设计。
13. **`remove --purge` 删除进度数据**：破坏性且不可恢复；v1 只做「取消注册」，不暴露 purge。
14. **事实层四语言**：引擎只支持 `zh`/`en`；界面四语言，但 KPI 标题/状态词/范围标签等事实层
   跟随引擎。ja 回落到英文事实，zh-TW 用中文事实（与原客户端一致）。
15. **历史趋势图/迷你折线**：引擎没有逐项目时间序列；不画假趋势。仪表盘只画当前构成。
16. **全局快捷键（应用未聚焦时）**：BUI 没有 OS 热键注册；只在窗口内生效，且输入框聚焦时被控件吃掉。
17. **跨平台实测**：本方案在 macOS 上验证；Windows/Linux 只保证代码路径、`CREATE_NO_WINDOW`、
    `cmd /C start`/`explorer`/`xdg-open` 分支齐全，未做实机验证。

---

## 14. 风险清单（按优先级）

| 风险 | 影响 | 缓解 |
|---|---|---|
| `UiSender` 上游未被 examples/tests 覆盖 | 后台任务/停止/AI 全部依赖它 | P0 gate `--selftest-ui-sender`；失败则全部同步执行，功能不丢，UI 阻塞 |
| macOS IME 缺失 | 中文输入不可用 | 粘贴/文件选择器/预设；设置页与 AI 页明示；不承诺「可打字」 |
| 玻璃性能 | 滚动掉帧 | 4 面上限、滚动区无 effects、blur 18→12 的降级方案 |
| BUI CSS 静默丢弃 | 样式「写了没效果」 | 单一样式源 + `ui::cls` debug 校验 + 类契约测试 |
| 引擎契约漂移 | 解码失败/空白 | 严格模型 + 真实夹具 + 载荷优先错误 + 缺键报错而非填 0 |
| `milestone list` rc=1 | 被误判为失败 | `parse` 先解析载荷；storeHealth 单独披露 |
| 长文档渲染 | 首帧卡顿 | 250 块上限 + 展开；解析在加载时做一次，渲染 AST |
| 更新跑很久 | 用户以为卡死 | 后台 Job + 进度 + 真取消 + 超时分开 |
| 逗号路径无法 `--paths` | 选文件提交失败 | 检测逗号，警示并建议「提交全部」；写进已知限制 |
| 四组并行冲突 | 编译互相踩 | 文件所有权表 + core 冻结契约 + 功能组只加自己模块字段/动作 |

---

## 15. 交付定义（Definition of Done）

- `cargo build` / `cargo test` 绿；类契约与模型夹具测试在 CI 里跑。
- 四个功能组各自页面在真实引擎上可用；core 的 settings/agent 页可用。
- 第 12.2 节手动冒烟全过（在 macOS 实机；Windows/Linux 至少 `cargo build` 通过）。
- 所有「读不出来/截断/口径/失败」都有 UI 落点（第 10 节）。
- 破坏性动作有确认；确认按钮是动词；只有删除/放弃染红。
- 设置保存失败可见；AI 未配置不阻塞其余功能；停止不报失败。
- PLAN 与实际代码的契约一致；任何契约变更都在 PLAN 里有记录。
