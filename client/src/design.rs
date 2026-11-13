// 契约面：本阶段先冻结 API，页面的下一阶段消费者尚未落地；未使用不是缺陷。
#![allow(dead_code)]

// design.rs — 设计系统：macOS 的克制留白 × Windows 11 的 Fluent/Mica 层次。
//
// 【唯一注入点】本文件是全客户端唯一的样式来源：
//   · `SHEET`        —— 全局 CSS（`design::SHEET` 塞进根节点 `<style>`）；
//   · `CLASS_TOKENS` —— 全部合法 class token（debug 构建下 `ui` 层会校验）。
// 视图只写类名，不写颜色/圆角/间距；要改观感只改这里。
//
// 【设计语言】
//   · 深海底色（--bg）+ 蓝色强调（--accent）；正文 13px、标题 20px/600。
//   · Fluent 磁贴：12 列栅格（gap 12）、`span-*` 跨列、`minmax(0,1fr)` 防止内容把列撑破。
//   · Mica 分层：页面底 → 侧栏/标题栏（玻璃）→ 卡片（rgba 纯透明）三级明度差。
//   · 玻璃面**最多 4 个**：`.sidebar` / `.main-head` / `.dash-hero` / `.modal`。
//     滚动区里的元素一律 rgba，不带 backdrop-filter（每帧重算，滚动会掉帧）。
//   · 动效只改背景/描边/位移 2px：`translateY` 不进 layer，不会破坏子级玻璃采样。
//
// 【BUI 0.5 硬边界（写样式前必读）】
//   · 表单控件是 kit 原生节点，CSS 外观无效 —— `<input>/<textarea>` 只设几何类，
//     外观由外层 `.field-box` 承担；按钮/分段/开关/复选全是 div + 类。
//   · 未知属性/取值运行期静默丢弃，所以这里只用已知安全的写法：
//     linear-gradient（不支持 radial 的 center/shape）、单层渐变、不做 sticky、
//     也不使用 `::backdrop`/`::selection`/`::-webkit-scrollbar`。
//   · 祖先若有 transform/clip-path/mask/mix-blend-mode 会切断子级 backdrop 采样：
//     玻璃元素的祖先链上不许出现这些属性（`.card.hoverable:hover` 只动 translateY）。
//   · `1fr` 的最小值被映射成 auto ⇒ 所有等宽列写 `minmax(0, 1fr)`。
//   · `position: sticky` = static ⇒ 吸顶条一律放在滚动容器之外（本 SHEET 不写 sticky）。
//   · `opacity` 只作用于自身盒子 ⇒ 整组变淡用 rgba 颜色；只有 `.skeleton` 用 opacity 动画。
//
// 字体：HarmonyOS Sans SC（内置，见 assets/fonts 与 LICENSE.txt）。
// BUI 没有逐字形回退，必须显式绑定到内置字体 —— 中文才不会变豆腐块。

/// 全部合法 class token。`ui::cls` 在 debug 构建里逐 token 比对；
/// 视图里出现未登记的类 = 拼写错误（运行期会被 CSS 静默丢弃，肉眼极难发现）。
///
/// 分组与 PLAN §5.2 的类表一一对应；末尾单列 **v0 兼容别名**
/// （`views/{sidebar,dashboard,project,milestones}.rs` 尚未重写，仍在使用）。
///
/// ⚠️ 这张表是**类名契约**，不是「已实现页面」的清单。`chat-*` / `msg-*` /
/// `settings-*` / `about-*` / `graph-preview-*` / `diff-*` 等属于尚未落地的
/// P2/P3 页面（设置、AI 助手、图谱预览）；给它们定义样式不等于宣称功能存在。
/// 判断「有没有消费方」必须按页面是否存在分开看 —— 否则会把预留词表
/// 读成「设计系统已完整落地」。已落地页面用的 token（page / glass / md-* /
/// mono 族）在 views 里都有真实消费点。
pub const CLASS_TOKENS: &[&str] = &[
    // ── 布局与壳 ──
    "app",
    "app-bg",
    "aurora",
    "aurora-a",
    "aurora-b",
    "aurora-c",
    "sidebar",
    "sidebar-head",
    "sidebar-brand",
    "sidebar-brand-sub",
    "sidebar-scroll",
    "sidebar-group",
    "sidebar-group-head",
    "sidebar-group-toggle",
    "sidebar-foot",
    "sidebar-status",
    "main",
    "main-head",
    "main-head-main",
    "main-title",
    "main-sub",
    "main-actions",
    "main-scroll",
    "main-scroll-flush",
    "dash-hero",
    "dash-filters",
    "page",
    "page-narrow",
    "stack",
    "stack-sm",
    "row",
    "row-sm",
    "row-wrap",
    "row-between",
    "spacer",
    "fill",
    "grow",
    "nowrap",
    "center",
    "right",
    "hidden",
    "divider",
    "divider-v",
    "tiles",
    "tile",
    "tile-hero",
    "span-2",
    "span-3",
    "span-4",
    "span-6",
    "span-8",
    "span-9",
    "span-12",
    "form-grid",
    "pane",
    "pane-head",
    "pane-body",
    "pane-foot",
    // ── 表面与文本 ──
    "glass",
    "glass-strong",
    "card",
    "hoverable",
    "selected",
    "flat",
    "card-head",
    "card-title",
    "card-sub",
    "card-body",
    "card-foot",
    "hero",
    "hero-title",
    "hero-sub",
    "hero-metric",
    "kpi",
    "kpi-label",
    "kpi-value",
    "kpi-hint",
    "kpi-foot",
    "stat",
    "stat-value",
    "stat-label",
    "art",
    "art-ready",
    "art-missing",
    "t-h1",
    "t-h2",
    "t-h3",
    "t-title",
    "t-body",
    "t-meta",
    "t-caption",
    "t-dim",
    "t-strong",
    "t-mono",
    "t-mono-cjk",
    "t-num",
    "t-accent",
    "t-ellipsis",
    "t-clamp-2",
    "t-clamp-3",
    "mono",
    "num",
    "muted",
    "dim",
    "ok",
    "warn",
    "stale",
    "err",
    "info",
    "unknown",
    "accent",
    "idle",
    // ── 控件 ──
    "btn",
    "btn-sm",
    "btn-lg",
    "btn-accent",
    "btn-ghost",
    "btn-danger",
    "ghost",
    "danger",
    "btn-icon",
    "btn-pill",
    "btn-block",
    "btn-busy",
    "is-disabled",
    "spinner",
    "btn-group",
    "seg",
    "seg-item",
    "on",
    "kbd",
    "field",
    "field-label",
    "field-hint",
    "field-error",
    "field-box",
    "input",
    "textarea",
    "check",
    "check-box",
    "check-mark",
    "switch",
    "switch-knob",
    "link",
    "picker-btn",
    // ── 导航与浮层 ──
    "nav-item",
    "nav-icon",
    "nav-label",
    "nav-badge",
    "nav-badge-warn",
    "nav-badge-dim",
    "sect-label",
    "tabs",
    "tab",
    "tab-badge",
    "crumb",
    "crumb-sep",
    "overlay",
    "overlay-top",
    "overlay-clear",
    "modal",
    "modal-sm",
    "modal-md",
    "modal-lg",
    "modal-xl",
    "modal-head",
    "modal-title",
    "modal-sub",
    "modal-body",
    "modal-foot",
    "modal-close",
    "confirm-icon",
    "menu",
    "menu-head",
    "menu-item",
    "menu-sep",
    "menu-danger",
    "menu-shortcut",
    "toast-wrap",
    "toast",
    "toast-title",
    "toast-body",
    "banner",
    "banner-title",
    "banner-body",
    "banner-action",
    "palette",
    "palette-input",
    "palette-list",
    "palette-item",
    "palette-item-on",
    "palette-kind",
    "palette-empty",
    // ── 状态与数据 ──
    "dot",
    "chip",
    "chip-sm",
    "badge",
    "badge-sm",
    "table",
    "thead",
    "tbody",
    "tr",
    "th",
    "td",
    "td-num",
    "kv",
    "kv-k",
    "kv-v",
    "bar",
    "bar-sm",
    "bar-fill",
    "stackbar",
    "stack-seg",
    "s1",
    "s2",
    "s3",
    "s4",
    "s5",
    "s6",
    "s7",
    "s8",
    "s9",
    "s10",
    "s11",
    "s12",
    "legend",
    "legend-item",
    "swatch",
    "neutral-fill",
    "spark",
    "list",
    "list-item",
    "list-main",
    "list-side",
    "empty",
    "empty-icon",
    "empty-title",
    "empty-body",
    "disclosure",
    "disclosure-head",
    "disclosure-body",
    "code",
    "pre",
    "pre-mono",
    "diff",
    "diff-add",
    "diff-del",
    "diff-hunk",
    // Markdown
    "md",
    "md-h1",
    "md-h2",
    "md-h3",
    "md-h4",
    "md-h5",
    "md-h6",
    "md-p",
    "md-li",
    "md-bullet",
    "md-quote",
    "md-pre",
    "md-code",
    "md-strong",
    "md-em",
    "md-link",
    "md-table",
    "md-tr",
    "md-td",
    "md-th",
    "md-hr",
    "md-img-alt",
    "skeleton",
    "skeleton-line",
    // ── 业务组件 ──
    "board",
    "board-col",
    "board-col-head",
    "board-col-count",
    "board-col-criteria",
    "board-card",
    "score",
    "score-value",
    "score-label",
    "dims",
    "dim-row",
    "dim-name",
    "dim-bar",
    "dim-val",
    "finding",
    "finding-head",
    "finding-body",
    "finding-meta",
    "signal-grid",
    "signal",
    "signal-name",
    "signal-value",
    "signal-null",
    "alert",
    "alert-high",
    "alert-medium",
    "alert-low",
    "graph-preview",
    "graph-preview-index",
    "graph-preview-arch",
    "artifact-actions",
    "chat",
    "chat-scroll",
    "msg",
    "msg-user",
    "msg-assistant",
    "msg-tool",
    "msg-error",
    "msg-head",
    "msg-body",
    "msg-time",
    "msg-actions",
    "composer",
    "composer-input",
    "composer-actions",
    "suggest",
    "suggest-item",
    "thinking",
    "tool-event",
    "tool-event-ok",
    "tool-event-err",
    "search",
    "search-box",
    "search-input",
    "search-clear",
    "scan-grid",
    "scan-drop",
    "scan-drop-icon",
    "scan-result",
    "scan-stat",
    "scan-stat-value",
    "scan-stat-label",
    "candidate",
    "candidate-main",
    "candidate-side",
    "path",
    "path-text",
    "settings",
    "settings-nav",
    "settings-nav-item",
    "settings-pane",
    "setting-row",
    "setting-label",
    "setting-desc",
    "setting-control",
    "about-hero",
    "about-logo",
    "about-links",
    "link-row",
    "secret-note",
    // ── v0 兼容别名 ──
    // 这四个页面由后续开发者重写；在重写落地前，旧文件仍用这些类。
    // 它们只是别名，不引入第二套设计语言。
    "root",
    "brand",
    "brand-sub",
    "h2",
    "wrap",
    "metric",
    "grid2",
    "grid3",
    "artifact",
    "ready",
    "missing",
    "k",
    "v",
];

/// 全局样式表。根节点（`.app`）持有全部 CSS 变量；其余全部从这里派生。
pub const SHEET: &str = r#"
* { box-sizing: border-box; }

/* ══════════════════════════════════════════════════════════════════════
   设计令牌（PLAN §4.1）—— 只挂一次，全部写在 .app 上
   ══════════════════════════════════════════════════════════════════════ */
.app {
  --bg: #0A0F1A;
  --bg-2: #0C1424;
  --surface: rgba(255,255,255,.035);
  --surface-2: rgba(255,255,255,.06);
  --glass: rgba(16,24,40,.86);
  --glass-2: rgba(12,19,32,.94);
  --stroke: rgba(255,255,255,.08);
  --stroke-2: rgba(255,255,255,.14);
  --text: #E9EEF7;
  --text-2: #A9B6CC;
  --text-3: #6F7D95;
  --accent: #4C8DFF;
  --accent-2: #6BA1FF;
  --accent-3: #3B78E6;
  --ok: #3FCF8E;
  --warn: #F2B25C;
  --stale: #FF9A62;
  --err: #FF6B81;
  --info: #63B3ED;
  --unknown: #B08CFF;
  --series-1: #4C8DFF;
  --series-2: #3FCF8E;
  --series-3: #F2B25C;
  --series-4: #FF6B81;
  --series-5: #B08CFF;
  --series-6: #63B3ED;
  --series-7: #F78FB3;
  --series-8: #7FE3B8;
  --series-9: #FFC97A;
  --series-10: #9AA8FF;
  --series-11: #5ED0C6;
  --series-12: #D6A2FF;
  --shadow-1: 0 8px 24px rgba(0,0,0,.28);
  --shadow-2: 0 24px 64px rgba(0,0,0,.5);
  --dur: 120ms;
  --dur-2: 160ms;
  --ease: ease-out;

  position: absolute; inset: 0;
  display: flex; flex-direction: row;
  background: linear-gradient(180deg, #0A0F1A 0%, #0C1424 100%);
  color: var(--text);
  font-family: HarmonyOS Sans SC;
  font-size: 13px;
  line-height: 1.5;
}
/* v0 兼容：旧根类名 */
.root {
  position: absolute; inset: 0;
  display: flex; flex-direction: row;
  background: linear-gradient(180deg, #0A0F1A 0%, #0C1424 100%);
  color: var(--text);
  font-family: HarmonyOS Sans SC;
  font-size: 13px;
  line-height: 1.5;
}

/* 装饰背景：给三块玻璃面提供**非均匀**的采样内容。
   只有 `.app` 的纯渐变时，backdrop-filter 的结果与平涂几乎一样，
   Mica 分层只是名义上的。指针事件必须穿透（它不是内容）。 */
.app-bg { position: absolute; inset: 0; overflow: hidden; pointer-events: none; }
.aurora { position: absolute; width: 720px; height: 720px; border-radius: 999px; opacity: .10; }
.aurora-a { left: -220px; top: -280px; background: linear-gradient(135deg, #4C8DFF 0%, rgba(76,141,255,0) 72%); }
.aurora-b { right: -240px; top: 90px; background: linear-gradient(135deg, #B08CFF 0%, rgba(176,140,255,0) 72%); }
.aurora-c { left: 28%; bottom: -360px; background: linear-gradient(135deg, #3FCF8E 0%, rgba(63,207,142,0) 72%); }

/* 键盘焦点：BUI 的 `:focus-visible` 与 `:focus` 共用同一套状态（按下即聚焦），
   所以只给**可交互控件**画环。全局 `:focus-visible` 会让点空白处也给整窗描边。 */
.btn:focus-visible, .btn-icon:focus-visible, .seg-item:focus-visible,
.menu-item:focus-visible, .palette-item:focus-visible, .list-item:focus-visible,
.sidebar-item:focus-visible, .nav-item:focus-visible {
  outline: 2px solid rgba(76,141,255,.85);
  outline-offset: 2px;
}

/* ══════════════════════════════════════════════════════════════════════
   壳：侧栏 / 主区 / 标题栏
   ══════════════════════════════════════════════════════════════════════ */
.sidebar {
  width: 260px; min-width: 260px; height: 100%;
  display: flex; flex-direction: column;
  border-right: 1px solid var(--stroke);
  border-bottom: none; border-left: none;
}
.sidebar-head { padding: 16px 16px 10px 16px; display: flex; flex-direction: column; gap: 2px; }
.sidebar-brand { font-size: 16px; font-weight: 600; letter-spacing: .2px; color: #F2F6FF; }
.sidebar-brand-sub { font-size: 11px; color: var(--text-3); }
.brand { font-size: 16px; font-weight: 600; letter-spacing: .2px; color: #F2F6FF; }
.brand-sub { font-size: 11px; color: var(--text-3); }
.sidebar-scroll {
  flex: 1; min-height: 0; overflow-y: scroll; scrollbar-width: thin;
  padding: 6px 10px 12px 10px;
  display: flex; flex-direction: column; gap: 1px;
}
.sidebar-group { display: flex; flex-direction: column; gap: 1px; }
.sidebar-group-head {
  display: flex; flex-direction: row; align-items: center; gap: 6px;
  padding: 8px 8px 2px 8px; font-size: 11px; letter-spacing: .4px; color: var(--text-3);
  cursor: pointer;
}
.sidebar-group-toggle { font-size: 10px; color: var(--text-3); }
.sidebar-foot {
  padding: 10px 14px; border-top: 1px solid var(--stroke);
  display: flex; flex-direction: column; gap: 6px;
}
.sidebar-status { display: flex; flex-direction: row; align-items: center; gap: 6px; font-size: 11px; color: var(--text-3); }

.main { flex: 1; min-width: 0; height: 100%; display: flex; flex-direction: column; }
.main-head {
  height: 56px; min-height: 56px;
  display: flex; flex-direction: row; align-items: center; gap: 12px;
  padding: 0 24px;
  border-bottom: 1px solid var(--stroke);
  border-left: none; border-right: none;
}
.main-head-main { display: flex; flex-direction: column; gap: 1px; min-width: 0; }
.main-title { font-size: 20px; font-weight: 600; letter-spacing: .1px; color: #F2F6FF; }
.main-sub { font-size: 12px; color: var(--text-2); }
.main-actions { display: flex; flex-direction: row; align-items: center; gap: 8px; }
.main-scroll {
  flex: 1; min-height: 0; overflow-y: scroll; scrollbar-width: thin;
  padding: 22px 26px 32px 26px;
  display: flex; flex-direction: column; gap: 18px;
}
.main-scroll-flush { flex: 1; min-height: 0; overflow-y: scroll; scrollbar-width: thin; display: flex; flex-direction: column; gap: 0; }
.dash-hero {
  display: flex; flex-direction: row; align-items: center; gap: 20px;
  padding: 16px 20px; min-height: 104px;
  border-bottom: 1px solid var(--stroke);
  border-left: none; border-right: none;
}
.dash-filters {
  display: flex; flex-direction: row; align-items: center; gap: 8px;
  padding: 8px 24px; border-bottom: 1px solid var(--stroke);
}
.page { width: 100%; max-width: 1080px; margin: 0 auto; display: flex; flex-direction: column; gap: 14px; }
.page-narrow { width: 100%; max-width: 760px; margin: 0 auto; display: flex; flex-direction: column; gap: 14px; }

/* ── 布局工具 ── */
.stack { display: flex; flex-direction: column; gap: 14px; }
.stack-sm { display: flex; flex-direction: column; gap: 8px; }
.row { display: flex; flex-direction: row; align-items: center; gap: 8px; }
.row-sm { display: flex; flex-direction: row; align-items: center; gap: 6px; }
.row-wrap { display: flex; flex-direction: row; align-items: center; gap: 8px; flex-wrap: wrap; }
.wrap { display: flex; flex-direction: row; align-items: center; gap: 8px; flex-wrap: wrap; }
.row-between { display: flex; flex-direction: row; align-items: center; justify-content: space-between; gap: 8px; }
.spacer { flex: 1; }
.fill { flex: 1; min-width: 0; }
.grow { flex: 1; min-width: 0; }
.nowrap { white-space: nowrap; }
.center { display: flex; align-items: center; justify-content: center; }
.right { text-align: right; }
.hidden { display: none; }
.divider { height: 1px; width: 100%; background: var(--stroke); }
.divider-v { width: 1px; align-self: stretch; background: var(--stroke); }

/* ── 12 列磁贴 ── */
.tiles {
  display: grid; grid-template-columns: repeat(12, minmax(0, 1fr));
  gap: 14px; grid-auto-flow: dense; width: 100%;
}
.tile { min-width: 0; display: flex; flex-direction: column; }
.tile-hero { min-width: 0; min-height: 200px; display: flex; flex-direction: column; }
.span-2 { grid-column: span 2; }
.span-3 { grid-column: span 3; }
.span-4 { grid-column: span 4; }
.span-6 { grid-column: span 6; }
.span-8 { grid-column: span 8; }
.span-9 { grid-column: span 9; }
.span-12 { grid-column: span 12; }

.form-grid { display: grid; grid-template-columns: 120px minmax(0, 1fr); gap: 10px 12px; align-items: center; }
.pane { display: flex; flex-direction: column; border: 1px solid var(--stroke); border-radius: 12px; background: var(--surface); }
.pane-head { padding: 12px 14px; border-bottom: 1px solid var(--stroke); display: flex; flex-direction: row; align-items: center; gap: 8px; }
.pane-body { padding: 14px; display: flex; flex-direction: column; gap: 10px; }
.pane-foot { padding: 10px 14px; border-top: 1px solid var(--stroke); display: flex; flex-direction: row; align-items: center; gap: 8px; }

/* ══════════════════════════════════════════════════════════════════════
   表面：玻璃 / 卡片 / 磁贴内容
   ══════════════════════════════════════════════════════════════════════ */
.glass {
  background: var(--glass);
  border: 1px solid var(--stroke-2);
  border-top-color: rgba(255,255,255,.20);
  /* ⚠️ 不用 backdrop-filter：BUI 0.5 的 Cocoa 宿主上带它会**整窗不呈现**
     （实测：带=14s 仍是灰块，去=4s 完整渲染）。Fluent 观感改用
     「近不透明玻璃底 + 顶部内高光 + 细描边」，不依赖背景采样。 */
  box-shadow: inset 0 1px 0 rgba(255,255,255,.10), var(--shadow-1);
}
/* 只给模态用：第 4 个玻璃面 */
.glass-strong {
  background: var(--glass-2);
  border: 1px solid var(--stroke-2);
  border-top-color: rgba(255,255,255,.20);
  box-shadow: inset 0 1px 0 rgba(255,255,255,.12), var(--shadow-2);
}
.card {
  background: var(--surface);
  border: 1px solid var(--stroke);
  border-radius: 14px;
  padding: 18px;
  display: flex; flex-direction: column; gap: 12px;
  min-width: 0;
}
.card.hoverable { transition: background-color var(--dur) var(--ease), border-color var(--dur) var(--ease), transform var(--dur) var(--ease); cursor: pointer; }
.card.hoverable:hover { background: var(--surface-2); border-color: rgba(124,166,255,.30); transform: translateY(-2px); }
.selected { background: rgba(76,141,255,.15); border-color: rgba(76,141,255,.30); }
.flat { background: transparent; border-color: transparent; padding: 0; }
.card-head { display: flex; flex-direction: row; align-items: center; gap: 8px; }
.card-title { font-size: 13px; font-weight: 600; color: #DCE6F5; display: flex; flex-direction: row; align-items: center; gap: 8px; }
.card-sub { font-size: 11px; color: var(--text-3); }
.card-body { display: flex; flex-direction: column; gap: 8px; min-width: 0; }
.card-foot { display: flex; flex-direction: row; align-items: center; gap: 8px; flex-wrap: wrap; border-top: 1px solid var(--stroke); padding-top: 10px; }

.hero { display: flex; flex-direction: column; gap: 4px; min-width: 0; }
.hero-title { font-size: 12px; color: var(--text-2); }
.hero-sub { font-size: 12px; color: var(--text-3); }
.hero-metric { font-size: 28px; font-weight: 600; letter-spacing: -.4px; color: #F4F8FF; }

.kpi {
  display: flex; flex-direction: column; gap: 5px;
  background: linear-gradient(180deg, rgba(255,255,255,.055) 0%, rgba(255,255,255,.022) 100%);
  border: 1px solid var(--stroke); border-top-color: rgba(255,255,255,.14);
  border-radius: 14px; padding: 16px 18px; min-width: 0;
  box-shadow: inset 0 1px 0 rgba(255,255,255,.06);
  transition: border-color var(--dur) var(--ease), box-shadow var(--dur) var(--ease), transform var(--dur) var(--ease);
}
.kpi:hover {
  border-color: rgba(124,166,255,.36);
  box-shadow: inset 0 1px 0 rgba(255,255,255,.10), 0 10px 28px rgba(0,0,0,.34);
  transform: translateY(-2px);
}
.kpi-label { font-size: 12px; color: var(--text-2); }
.kpi-value { font-size: 32px; font-weight: 600; letter-spacing: -.4px; color: #F4F8FF; }
.kpi-hint { font-size: 11px; line-height: 1.55; color: var(--text-3); }
.kpi-foot { border-top: 1px solid var(--stroke); padding-top: 6px; margin-top: 2px; font-size: 11px; color: var(--text-3); }
.stat { display: flex; flex-direction: column; gap: 1px; }
.stat-value { font-size: 15px; font-weight: 600; color: #E6EDF9; }
.stat-label { font-size: 11px; color: var(--text-3); }
.metric { font-size: 26px; font-weight: 600; letter-spacing: -.3px; color: #F4F8FF; }

.art { border-style: solid; }
.art-ready { border-color: rgba(76,141,255,.35); background: rgba(76,141,255,.07); }
.art-missing { border-style: dashed; border-color: rgba(255,255,255,.12); }
/* v0 兼容：旧文件用 .artifact.ready / .artifact.missing */
.artifact { border-style: solid; }
.artifact.ready { border-color: rgba(76,141,255,.35); background: rgba(76,141,255,.07); }
.artifact.missing { border-style: dashed; border-color: rgba(255,255,255,.12); }

/* ══════════════════════════════════════════════════════════════════════
   文本
   ══════════════════════════════════════════════════════════════════════ */
.t-h1 { font-size: 20px; font-weight: 600; line-height: 1.25; color: #F2F6FF; }
.t-h2 { font-size: 15px; font-weight: 600; line-height: 1.25; color: #EDF3FC; }
.t-h3 { font-size: 13px; font-weight: 600; line-height: 1.25; color: #E6EDF9; }
.t-title { font-size: 13px; font-weight: 600; line-height: 1.25; color: #E6EDF9; }
.t-body { font-size: 13px; color: var(--text); }
.t-meta { font-size: 12px; color: var(--text-2); }
.t-caption { font-size: 11px; color: var(--text-3); }
.t-dim { color: var(--text-3); }
.t-strong { font-weight: 600; }
.t-mono { font-family: monospace; letter-spacing: .2px; }
/* BUI 没有逐字形回退：等宽字体不含 CJK 字形，含中文的路径/分支沿用 CJK 字面。 */
.t-mono-cjk { font-family: HarmonyOS Sans SC; letter-spacing: .2px; }
.t-num { font-family: monospace; }
.t-accent { color: var(--accent-2); }
.t-ellipsis { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.t-clamp-2 { overflow: hidden; max-height: 36px; }
.t-clamp-3 { overflow: hidden; max-height: 4.35em; }
.mono { font-family: monospace; letter-spacing: .2px; }
.num { font-family: monospace; }
.muted { color: var(--text-2); }
.dim { color: var(--text-3); }
.h2 { font-size: 15px; font-weight: 600; color: #EDF3FC; }

/* 色调 token：文字色；dot/chip/badge/bar-fill/toast 另有组合规则 */
.ok { color: var(--ok); }
.warn { color: var(--warn); }
.stale { color: var(--stale); }
.err { color: var(--err); }
.info { color: var(--info); }
.unknown { color: var(--unknown); }
.accent { color: var(--accent-2); }
.idle { color: var(--text-3); }

/* ══════════════════════════════════════════════════════════════════════
   控件（div 按钮；原生控件只设几何）
   ══════════════════════════════════════════════════════════════════════ */
.btn {
  white-space: nowrap;
  flex-shrink: 0;
  height: 28px;
  display: inline-flex; flex-direction: row; align-items: center; justify-content: center; gap: 6px;
  padding: 6px 12px; border-radius: 8px; font-size: 13px;
  border: 1px solid rgba(255,255,255,.10); background: rgba(255,255,255,.05);
  color: var(--text); cursor: pointer;
  transition: background-color var(--dur) var(--ease), border-color var(--dur) var(--ease), transform var(--dur) var(--ease);
}
.btn:hover { background: rgba(255,255,255,.09); border-color: rgba(255,255,255,.18); }
.btn:active { transform: translateY(1px); }
.btn-sm { padding: 4px 10px; font-size: 12px; }
.btn-lg { padding: 8px 14px; font-size: 14px; }
.btn-accent { background: var(--accent); border-color: var(--accent); color: #081120; font-weight: 600; }
.btn-accent:hover { background: var(--accent-2); border-color: var(--accent-2); }
.btn-accent:active { background: var(--accent-3); }
.btn-ghost { background: transparent; border-color: transparent; color: var(--text-2); }
.btn-ghost:hover { background: rgba(255,255,255,.06); border-color: transparent; color: var(--text); }
.btn-danger { background: rgba(255,107,129,.08); border-color: rgba(255,107,129,.35); color: #FF9AA8; }
.btn-danger:hover { background: rgba(255,107,129,.16); }
/* v0 兼容：旧页面用 `.btn.accent` / `.btn.ghost` / `.btn.danger`（点号组合），
   新代码用连字符变体。两套名字指向同一组观感，不是第二套设计。 */
.btn.accent { background: var(--accent); border-color: var(--accent); color: #081120; font-weight: 600; }
.btn.accent:hover { background: var(--accent-2); border-color: var(--accent-2); }
.btn.ghost { background: transparent; border-color: transparent; color: var(--text-2); }
.btn.ghost:hover { background: rgba(255,255,255,.06); border-color: transparent; color: var(--text); }
.btn.danger { background: rgba(255,107,129,.08); border-color: rgba(255,107,129,.35); color: #FF9AA8; }
.btn.danger:hover { background: rgba(255,107,129,.16); }
.btn-icon { width: 28px; height: 28px; padding: 0; }
.btn-pill { border-radius: 999px; }
.btn-block { width: 100%; }
.btn-busy { color: var(--text-3); pointer-events: none; }
.is-disabled { color: rgba(233,238,247,.45); pointer-events: none; border-color: rgba(255,255,255,.06); }
.spinner {
  width: 8px; height: 8px; border-radius: 999px;
  border: 1.5px solid rgba(255,255,255,.25); border-top-color: transparent;
  animation: spin 900ms linear infinite;
}
@keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
.btn-group { display: inline-flex; flex-direction: row; align-items: center; }
.btn-group .btn { border-radius: 0; margin-left: -1px; }
.btn-group .btn:first-child { border-radius: 8px 0 0 8px; margin-left: 0; }
.btn-group .btn:last-child { border-radius: 0 8px 8px 0; }

.seg {
  display: inline-flex; flex-direction: row; align-items: center; gap: 2px;
  padding: 2px; border-radius: 10px; border: 1px solid var(--stroke);
  background: rgba(0,0,0,.18);
}
.seg-item {
  padding: 4px 10px; border-radius: 8px; font-size: 12px; color: var(--text-2);
  cursor: pointer; border: 1px solid transparent;
  transition: background-color var(--dur) var(--ease), color var(--dur) var(--ease);
}
.seg-item:hover { background: rgba(255,255,255,.06); color: var(--text); }
.seg-item.on { background: rgba(76,141,255,.15); border-color: rgba(76,141,255,.30); color: #EAF1FF; }
.on { background: rgba(76,141,255,.15); border-color: rgba(76,141,255,.30); color: #EAF1FF; }

.kbd {
  font-size: 11px; font-family: HarmonyOS Sans SC; color: var(--text-2);
  padding: 1px 6px; border-radius: 6px; border: 1px solid var(--stroke);
  border-bottom-color: rgba(255,255,255,.20); background: rgba(0,0,0,.18);
}
.field { display: flex; flex-direction: column; gap: 3px; min-width: 0; }
.field-label { font-size: 12px; color: var(--text-2); }
.field-hint { font-size: 11px; color: var(--text-3); }
.field-error { font-size: 11px; color: var(--err); }
.field-box {
  display: flex; flex-direction: row; align-items: center; gap: 6px;
  border: 1px solid rgba(255,255,255,.12); border-radius: 8px;
  padding: 2px; background: rgba(0,0,0,.20);
}
.field-box:focus-within { border-color: rgba(76,141,255,.55); }
/* 原生控件只设几何；背景/圆角由宿主绘制（BUI 事实） */
.input { width: 100%; height: 32px; padding: 7px 10px; font-size: 13px; }
.textarea { width: 100%; height: 88px; padding: 7px 10px; font-size: 13px; }

.check { display: inline-flex; flex-direction: row; align-items: center; gap: 6px; cursor: pointer; }
.check-box {
  width: 16px; height: 16px; border-radius: 5px; border: 1px solid rgba(255,255,255,.20);
  display: flex; align-items: center; justify-content: center;
  font-size: 11px; color: #081120; background: transparent;
}
.check-box.on { background: var(--accent); border-color: var(--accent); }
.check-mark { font-size: 10px; color: #081120; }
.switch {
  width: 36px; height: 20px; border-radius: 999px; padding: 2px;
  background: rgba(255,255,255,.10); border: 1px solid var(--stroke);
  display: flex; flex-direction: row; align-items: center; cursor: pointer;
  transition: background-color var(--dur) var(--ease);
}
.switch.on { background: var(--accent); border-color: var(--accent); }
.switch-knob { width: 16px; height: 16px; border-radius: 999px; background: #E9EEF7; }
.switch.on .switch-knob { margin-left: 16px; }
.link { color: var(--accent-2); cursor: pointer; }
.link:hover { color: #A9C7FF; }
.picker-btn {
  display: inline-flex; flex-direction: row; align-items: center; gap: 8px;
  padding: 5px 10px; border-radius: 8px; font-size: 12px;
  border: 1px solid var(--stroke); background: rgba(255,255,255,.04); cursor: pointer;
  max-width: 260px; overflow: hidden; white-space: nowrap;
}
.picker-btn:hover { border-color: rgba(124,166,255,.30); }

/* ══════════════════════════════════════════════════════════════════════
   导航 / 标签 / 面包屑
   ══════════════════════════════════════════════════════════════════════ */
.nav-item {
  display: flex; flex-direction: row; align-items: center; gap: 8px;
  padding: 7px 10px; border-radius: 8px; font-size: 13px; color: #B7C4DA;
  border: 1px solid transparent; cursor: pointer;
  transition: background-color var(--dur) var(--ease), color var(--dur) var(--ease);
}
.nav-item:hover { background: rgba(255,255,255,.06); color: #DDE7F5; }
.nav-item.on {
  background: rgba(76,141,255,.15); border-color: rgba(76,141,255,.30);
  color: #EAF1FF; box-shadow: inset 2px 0 0 var(--accent);
}
.nav-icon { width: 16px; color: #7FA6E8; font-size: 13px; text-align: center; }
.nav-label { flex: 1; min-width: 0; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.nav-badge { font-size: 11px; color: var(--text-3); min-width: 16px; text-align: right; }
.nav-badge-warn { font-size: 11px; color: var(--warn); }
.nav-badge-dim { font-size: 11px; color: var(--text-3); }
.sect-label { font-size: 11px; color: var(--text-3); padding: 10px 8px 4px 8px; letter-spacing: .4px; }

.tabs { display: flex; flex-direction: row; align-items: center; gap: 2px; border-bottom: 1px solid var(--stroke); padding: 0 24px; }
.tab {
  padding: 10px 12px; font-size: 13px; color: var(--text-2); cursor: pointer;
  border-bottom: 2px solid transparent; display: inline-flex; flex-direction: row; align-items: center; gap: 6px;
}
.tab:hover { color: var(--text); }
.tab.on { color: var(--accent-2); border-bottom-color: var(--accent); }
.tab-badge { font-size: 11px; color: var(--text-3); }
.crumb { font-size: 12px; color: var(--text-3); }
.crumb-sep { font-size: 12px; color: var(--text-3); padding: 0 4px; }

/* ══════════════════════════════════════════════════════════════════════
   浮层：overlay / modal / menu / toast / palette
   全部挂在 .app 根节点（fixed + z-index 100/110）
   ══════════════════════════════════════════════════════════════════════ */
.overlay {
  position: fixed; inset: 0; z-index: 100;
  background: rgba(4,8,16,.55);
  display: flex; align-items: center; justify-content: center;
}
.overlay-top { position: fixed; inset: 0; z-index: 100; background: rgba(4,8,16,.55); display: flex; align-items: flex-start; justify-content: center; padding-top: 12vh; }
.overlay-clear { position: fixed; inset: 0; z-index: 100; background: transparent; }
.modal {
  display: flex; flex-direction: column;
  width: 560px; max-width: 96%; max-height: 90%;
  border-radius: 14px;
  overflow: hidden;
}
.modal-sm { width: 420px; }
.modal-md { width: 560px; }
.modal-lg { width: 720px; }
.modal-xl { width: 920px; }
.modal-head { padding: 16px 18px 10px 18px; display: flex; flex-direction: column; gap: 3px; position: relative; }
.modal-title { font-size: 15px; font-weight: 600; color: #F2F6FF; }
.modal-sub { font-size: 11px; color: var(--text-3); }
.modal-body { padding: 4px 18px 14px 18px; overflow-y: scroll; scrollbar-width: thin; display: flex; flex-direction: column; gap: 10px; min-height: 0; }
.modal-foot { padding: 12px 18px; border-top: 1px solid var(--stroke); display: flex; flex-direction: row; align-items: center; justify-content: flex-end; gap: 8px; }
.modal-close { position: absolute; right: 10px; top: 10px; width: 24px; height: 24px; border-radius: 6px; display: flex; align-items: center; justify-content: center; color: var(--text-3); cursor: pointer; }
.modal-close:hover { background: rgba(255,255,255,.08); color: var(--text); }
.confirm-icon {
  width: 40px; height: 40px; border-radius: 999px; display: flex; align-items: center; justify-content: center;
  background: rgba(76,141,255,.15); color: var(--accent-2); font-size: 18px; margin: 4px auto 8px auto;
}
.confirm-icon.danger { background: rgba(255,107,129,.15); color: var(--err); }

/* 菜单：不用 backdrop-filter（玻璃面预算 4 个），用高不透明度代替 */
.menu {
  position: fixed; z-index: 100; width: 200px; padding: 4px;
  background: rgba(14,22,38,.94);
  border: 1px solid var(--stroke-2); border-radius: 8px;
  box-shadow: var(--shadow-2);
  display: flex; flex-direction: column; gap: 1px;
}
.menu-head { padding: 5px 8px 6px 8px; font-size: 11px; color: var(--text-3); }
.menu-item { padding: 6px 8px; border-radius: 6px; font-size: 12px; color: var(--text); cursor: pointer; display: flex; flex-direction: row; align-items: center; gap: 8px; }
.menu-item:hover { background: rgba(255,255,255,.07); }
.menu-sep { height: 1px; background: var(--stroke); margin: 3px 4px; }
.menu-danger { color: var(--err); }
.menu-shortcut { margin-left: auto; font-size: 11px; color: var(--text-3); }
.toast-wrap { position: fixed; right: 20px; bottom: 20px; z-index: 110; display: flex; flex-direction: column; gap: 8px; }
.toast {
  min-width: 260px; max-width: 420px; padding: 10px 12px 10px 14px;
  border-radius: 12px; background: rgba(14,22,38,.96);
  border: 1px solid var(--stroke-2); box-shadow: var(--shadow-2);
  border-left: 3px solid var(--accent);
  display: flex; flex-direction: column; gap: 2px;
  animation: toast-in var(--dur-2) var(--ease);
}
@keyframes toast-in { from { transform: translateY(8px); } to { transform: translateY(0); } }
.toast.ok { border-left-color: var(--ok); }
.toast.warn { border-left-color: var(--warn); }
.toast.err { border-left-color: var(--err); }
.toast.info { border-left-color: var(--info); }
.toast.unknown { border-left-color: var(--unknown); }
.toast-title { font-size: 12px; font-weight: 600; color: #EDF3FC; }
.toast-body { font-size: 12px; color: var(--text-2); }

.banner { padding: 10px 14px; border-radius: 10px; font-size: 12px; display: flex; flex-direction: column; gap: 4px; border: 1px solid var(--stroke); background: var(--surface); }
.banner-title { font-size: 12px; font-weight: 600; }
.banner-body { font-size: 12px; color: var(--text-2); }
.banner-action { margin-top: 2px; display: flex; flex-direction: row; gap: 8px; }
.banner.ok { background: rgba(63,207,142,.10); color: #7FE3B8; border-color: rgba(63,207,142,.25); }
.banner.warn { background: rgba(242,178,92,.10); color: #FFC97A; border-color: rgba(242,178,92,.25); }
.banner.err { background: rgba(255,107,129,.10); color: #FF9AA8; border-color: rgba(255,107,129,.28); }
.banner.info { background: rgba(99,179,237,.09); color: #9BD0F5; border-color: rgba(99,179,237,.24); }
.banner.unknown { background: rgba(176,140,255,.10); color: #CBB3FF; border-color: rgba(176,140,255,.28); }
.banner.stale { background: rgba(255,154,98,.10); color: #FFB894; border-color: rgba(255,154,98,.26); }
.banner.accent { background: rgba(76,141,255,.10); color: #A9C7FF; border-color: rgba(76,141,255,.26); }
.banner.idle { background: rgba(255,255,255,.035); color: var(--text-2); }

/* 命令面板 */
.palette {
  width: 560px; max-width: 92%; max-height: 70%;
  display: flex; flex-direction: column;
  background: rgba(14,22,38,.96);
  border: 1px solid var(--stroke-2); border-radius: 14px;
  box-shadow: var(--shadow-2); overflow: hidden;
}
.palette-input { padding: 12px 14px; border-bottom: 1px solid var(--stroke); }
.palette-list { padding: 6px; overflow-y: scroll; scrollbar-width: thin; display: flex; flex-direction: column; gap: 1px; }
.palette-item { padding: 8px 10px; border-radius: 8px; font-size: 13px; display: flex; flex-direction: row; align-items: center; gap: 8px; cursor: pointer; }
.palette-item:hover { background: rgba(255,255,255,.06); }
.palette-item-on { background: rgba(76,141,255,.15); }
.palette-kind { margin-left: auto; font-size: 11px; color: var(--text-3); }
.palette-empty { padding: 18px; text-align: center; font-size: 12px; color: var(--text-3); }

/* ══════════════════════════════════════════════════════════════════════
   状态与数据
   ══════════════════════════════════════════════════════════════════════ */
.dot { width: 8px; height: 8px; min-width: 8px; border-radius: 999px; background: var(--text-3); }
.dot.ok { background: var(--ok); }
.dot.warn { background: var(--warn); }
.dot.stale { background: var(--stale); }
.dot.err { background: var(--err); }
.dot.info { background: var(--info); }
.dot.unknown { background: var(--unknown); }
.dot.accent { background: var(--accent); }
.dot.idle { background: var(--text-3); }

.chip {
  display: inline-flex; flex-direction: row; align-items: center; gap: 5px;
  padding: 3px 9px; border-radius: 999px; font-size: 12px;
  border: 1px solid rgba(255,255,255,.09); color: #B7C4DA;
  background: rgba(255,255,255,.02); white-space: nowrap;
}
.chip-sm { padding: 1px 7px; font-size: 11px; }
.chip.ok { color: #7FE3B8; border-color: rgba(63,207,142,.25); background: rgba(63,207,142,.08); }
.chip.warn { color: #FFC97A; border-color: rgba(242,178,92,.25); background: rgba(242,178,92,.08); }
.chip.stale { color: #FFB894; border-color: rgba(255,154,98,.26); background: rgba(255,154,98,.08); }
.chip.err { color: #FF9AA8; border-color: rgba(255,107,129,.28); background: rgba(255,107,129,.08); }
.chip.info { color: #9BD0F5; border-color: rgba(99,179,237,.24); background: rgba(99,179,237,.07); }
.chip.unknown { color: #CBB3FF; border-color: rgba(176,140,255,.28); background: rgba(176,140,255,.08); }
.chip.accent { color: #A9C7FF; border-color: rgba(76,141,255,.26); background: rgba(76,141,255,.10); }
.chip.idle { color: var(--text-2); }

.badge {
  display: inline-flex; align-items: center; justify-content: center;
  min-width: 18px; height: 18px; padding: 0 5px; border-radius: 8px;
  font-size: 11px; border: 1px solid var(--stroke); color: var(--text-2);
}
.badge-sm { min-width: 14px; height: 14px; font-size: 10px; border-radius: 6px; }
.badge.ok { color: #7FE3B8; border-color: rgba(63,207,142,.3); background: rgba(63,207,142,.10); }
.badge.warn { color: #FFC97A; border-color: rgba(242,178,92,.3); background: rgba(242,178,92,.10); }
.badge.err { color: #FF9AA8; border-color: rgba(255,107,129,.3); background: rgba(255,107,129,.10); }
.badge.accent { color: #A9C7FF; border-color: rgba(76,141,255,.3); background: rgba(76,141,255,.10); }
.badge.muted { color: var(--text-3); }

.table { width: 100%; display: flex; flex-direction: column; }
.thead { display: flex; flex-direction: row; align-items: center; gap: 8px; padding: 6px 8px; border-bottom: 1px solid var(--stroke); }
.tbody { display: flex; flex-direction: column; }
.tr { display: flex; flex-direction: row; align-items: center; gap: 8px; padding: 6px 8px; border-bottom: 1px solid rgba(255,255,255,.04); }
.tr:hover { background: rgba(255,255,255,.04); }
.th { font-size: 11px; color: var(--text-3); flex: 1; min-width: 0; }
.td { font-size: 13px; color: var(--text); flex: 1; min-width: 0; }
.td-num { font-size: 13px; color: var(--text); text-align: right; min-width: 56px; }

.kv { display: flex; flex-direction: row; align-items: baseline; gap: 6px; min-width: 0; }
.kv-k { font-size: 12px; color: var(--text-3); }
.kv-v { font-size: 13px; color: #DCE6F5; min-width: 0; }
.k { font-size: 12px; color: var(--text-3); }
.v { font-size: 13px; color: #DCE6F5; }

.bar { width: 100%; height: 6px; border-radius: 999px; background: rgba(255,255,255,.06); overflow: hidden; }
.bar-sm { height: 4px; }
.bar-fill { height: 100%; border-radius: 999px; background: var(--accent); }
.bar-fill.ok { background: var(--ok); }
.bar-fill.warn { background: var(--warn); }
.bar-fill.stale { background: var(--stale); }
.bar-fill.err { background: var(--err); }
.bar-fill.unknown { background: var(--unknown); }
.bar-fill.info { background: var(--info); }
.bar-fill.accent { background: var(--accent); }

.stackbar { width: 100%; height: 8px; display: flex; flex-direction: row; border-radius: 999px; overflow: hidden; background: rgba(255,255,255,.05); }
.stack-seg { height: 100%; min-width: 2px; }
.s1 { background: var(--series-1); }
.s2 { background: var(--series-2); }
.s3 { background: var(--series-3); }
.s4 { background: var(--series-4); }
.s5 { background: var(--series-5); }
.s6 { background: var(--series-6); }
.s7 { background: var(--series-7); }
.s8 { background: var(--series-8); }
.s9 { background: var(--series-9); }
.s10 { background: var(--series-10); }
.s11 { background: var(--series-11); }
.s12 { background: var(--series-12); }
.legend { display: flex; flex-direction: row; align-items: center; gap: 10px; flex-wrap: wrap; }
.legend-item { display: inline-flex; flex-direction: row; align-items: center; gap: 5px; font-size: 11px; color: var(--text-2); }
.swatch { width: 8px; height: 8px; border-radius: 2px; }
/* 聚合段/中性色块：「不是单一类型」的中性填充，视图不写颜色。 */
.neutral-fill { background: rgba(255,255,255,.16); }
.spark { width: 100%; height: 40px; }

.list { display: flex; flex-direction: column; width: 100%; }
.list-item { display: flex; flex-direction: row; align-items: center; gap: 8px; padding: 8px 10px; border-radius: 8px; }
.list-item:hover { background: rgba(255,255,255,.04); }
.list-main { flex: 1; min-width: 0; }
.list-side { margin-left: auto; display: flex; flex-direction: row; align-items: center; gap: 6px; }

.empty { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 6px; padding: 32px 16px; text-align: center; }
.empty-icon { font-size: 28px; color: var(--text-3); }
.empty-title { font-size: 15px; font-weight: 600; color: var(--text-2); }
.empty-body { font-size: 12px; color: var(--text-3); max-width: 420px; }

.disclosure { border: 1px solid var(--stroke); border-radius: 8px; padding: 6px 10px; background: rgba(255,255,255,.02); }
.disclosure-head { font-size: 12px; color: var(--text-2); cursor: pointer; }
.disclosure-body { font-size: 12px; color: var(--text-3); padding-top: 6px; }

.code { font-family: monospace; font-size: 12px; color: #DCE6F5; background: rgba(0,0,0,.22); padding: 1px 5px; border-radius: 5px; }
.pre { font-family: HarmonyOS Sans SC; font-size: 12px; line-height: 1.5; color: #DCE6F5; background: rgba(0,0,0,.22); border: 1px solid var(--stroke); border-radius: 8px; padding: 10px 12px; overflow-x: scroll; white-space: pre; }
/* 只给纯 ASCII 正文用；含中文的 .pre 必须留 CJK 字面（否则豆腐块）。 */
.pre-mono { font-family: monospace; }

.diff { display: flex; flex-direction: column; font-family: monospace; font-size: 12px; line-height: 1.5; border: 1px solid var(--stroke); border-radius: 8px; overflow: hidden; }
.diff-add { background: rgba(63,207,142,.10); color: #A8F0CE; padding: 0 8px; white-space: pre; }
.diff-del { background: rgba(255,107,129,.10); color: #FFB3BE; padding: 0 8px; white-space: pre; }
.diff-hunk { color: #9BD0F5; background: rgba(99,179,237,.07); padding: 0 8px; white-space: pre; }

/* Markdown */
.md { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.md-h1 { font-size: 20px; font-weight: 600; color: #F2F6FF; }
.md-h2 { font-size: 15px; font-weight: 600; color: #EDF3FC; }
.md-h3 { font-size: 13px; font-weight: 600; color: #E6EDF9; }
.md-h4 { font-size: 13px; font-weight: 600; color: #E6EDF9; }
.md-h5 { font-size: 12px; font-weight: 600; color: var(--text-2); }
.md-h6 { font-size: 11px; font-weight: 600; color: var(--text-3); }
.md-p { font-size: 13px; color: var(--text); }
.md-li { font-size: 13px; color: var(--text); padding-left: 18px; display: flex; flex-direction: row; gap: 6px; }
.md-bullet { color: var(--text-3); min-width: 10px; }
.md-quote { border-left: 2px solid var(--stroke-2); padding-left: 10px; color: var(--text-2); font-size: 13px; }
.md-pre { font-family: HarmonyOS Sans SC; font-size: 12px; line-height: 1.5; background: rgba(0,0,0,.24); border: 1px solid var(--stroke); border-radius: 8px; padding: 10px 12px; overflow-x: scroll; white-space: pre; color: #DCE6F5; }
.md-code { font-family: HarmonyOS Sans SC; font-size: 12px; background: rgba(0,0,0,.22); padding: 1px 5px; border-radius: 5px; color: #DCE6F5; }
.md-strong { font-weight: 600; color: #EDF3FC; }
.md-em { color: var(--text-2); }
.md-link { color: var(--accent-2); }
.md-table { display: flex; flex-direction: column; border: 1px solid var(--stroke); border-radius: 8px; }
.md-tr { display: flex; flex-direction: row; border-bottom: 1px solid var(--stroke); }
.md-td { flex: 1; min-width: 0; padding: 6px 10px; font-size: 12px; color: var(--text); }
.md-th { font-weight: 600; color: var(--text-2); background: rgba(255,255,255,.03); }
.md-hr { height: 1px; background: var(--stroke); width: 100%; }
.md-img-alt { font-size: 11px; color: var(--text-3); }

.skeleton { background: rgba(255,255,255,.04); border-radius: 10px; animation: pulse 1.4s ease-in-out infinite; }
.skeleton-line { height: 10px; border-radius: 999px; background: rgba(255,255,255,.05); animation: pulse 1.4s ease-in-out infinite; }
@keyframes pulse { 0% { background-color: rgba(255,255,255,.04); } 50% { background-color: rgba(255,255,255,.09); } 100% { background-color: rgba(255,255,255,.04); } }

/* ══════════════════════════════════════════════════════════════════════
   业务组件
   ══════════════════════════════════════════════════════════════════════ */
.board { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; width: 100%; padding: 14px 20px 24px 20px; }
.board-col { display: flex; flex-direction: column; gap: 8px; min-width: 0; overflow: hidden; background: rgba(255,255,255,.02); border: 1px solid var(--stroke); border-radius: 12px; padding: 10px; }
.board-col-head { display: flex; flex-direction: row; align-items: center; gap: 8px; }
.board-col-count { margin-left: auto; font-size: 11px; color: var(--text-3); }
.board-col-criteria { font-size: 11px; color: var(--text-3); }
.board-card { background: var(--surface); border: 1px solid var(--stroke); border-radius: 10px; padding: 10px 12px; display: flex; flex-direction: column; gap: 6px; min-width: 0; max-width: 100%; cursor: pointer; }
.board-card:hover { background: var(--surface-2); border-color: rgba(124,166,255,.28); }

.score { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; }
.score-value { font-size: 28px; font-weight: 600; color: #F4F8FF; }
.score-label { font-size: 11px; color: var(--text-3); }
.dims { display: flex; flex-direction: column; gap: 8px; }
.dim-row { display: flex; flex-direction: row; align-items: center; gap: 8px; }
.dim-name { width: 120px; font-size: 12px; color: var(--text-2); }
.dim-bar { flex: 1; min-width: 0; }
.dim-val { width: 52px; text-align: right; font-size: 12px; color: var(--text); }
.finding { border: 1px solid var(--stroke); border-radius: 8px; padding: 6px 10px; background: rgba(255,255,255,.02); display: flex; flex-direction: column; gap: 4px; }
.finding-head { display: flex; flex-direction: row; align-items: center; gap: 8px; font-size: 12px; cursor: pointer; }
.finding-body { font-size: 12px; color: var(--text-2); }
.finding-meta { margin-left: auto; font-size: 11px; color: var(--text-3); }
.signal-grid { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 6px; }
.signal { display: flex; flex-direction: column; gap: 2px; padding: 6px 8px; border: 1px solid var(--stroke); border-radius: 8px; min-width: 0; }
.signal-name { font-size: 11px; color: var(--text-3); }
.signal-value { font-size: 13px; color: var(--text); }
.signal-null { font-size: 13px; color: var(--text-3); }
.alert { display: flex; flex-direction: row; align-items: flex-start; gap: 8px; padding: 8px 10px; border-radius: 8px; font-size: 12px; border: 1px solid var(--stroke); }
.alert-high { background: rgba(255,107,129,.10); border-color: rgba(255,107,129,.28); color: #FF9AA8; }
.alert-medium { background: rgba(242,178,92,.10); border-color: rgba(242,178,92,.26); color: #FFC97A; }
.alert-low { background: rgba(99,179,237,.08); border-color: rgba(99,179,237,.22); color: #9BD0F5; }

.graph-preview { width: 100%; height: 64px; border-radius: 8px; border: 1px solid var(--stroke); }
.graph-preview-index { background: linear-gradient(90deg, rgba(76,141,255,.28) 0%, rgba(63,207,142,.18) 100%); }
.graph-preview-arch { background: linear-gradient(180deg, rgba(176,140,255,.26) 0%, rgba(76,141,255,.12) 100%); }
.artifact-actions { display: flex; flex-direction: row; align-items: center; gap: 8px; }

.chat { flex: 1; min-height: 0; display: flex; flex-direction: column; }
.chat-scroll { flex: 1; min-height: 0; overflow-y: scroll; scrollbar-width: thin; padding: 16px 24px; display: flex; flex-direction: column; gap: 10px; }
.msg { max-width: 78%; padding: 8px 12px; border-radius: 12px; font-size: 13px; display: flex; flex-direction: column; gap: 4px; }
.msg-user { align-self: flex-end; background: rgba(76,141,255,.16); border: 1px solid rgba(76,141,255,.26); }
.msg-assistant { align-self: flex-start; background: rgba(255,255,255,.04); border: 1px solid var(--stroke); }
.msg-tool { align-self: flex-start; background: rgba(255,255,255,.02); border: 1px dashed var(--stroke-2); font-size: 12px; color: var(--text-2); }
.msg-error { align-self: flex-start; background: rgba(255,107,129,.08); border: 1px solid rgba(255,107,129,.30); }
.msg-head { display: flex; flex-direction: row; align-items: center; gap: 6px; font-size: 11px; color: var(--text-3); }
.msg-body { font-size: 13px; color: var(--text); }
.msg-time { font-size: 10px; color: var(--text-3); }
.msg-actions { display: flex; flex-direction: row; gap: 6px; }
.composer { border-top: 1px solid var(--stroke); padding: 10px 24px 14px 24px; display: flex; flex-direction: column; gap: 8px; }
.composer-input { display: flex; flex-direction: row; align-items: flex-end; gap: 8px; }
.composer-actions { display: flex; flex-direction: row; align-items: center; gap: 8px; }
.suggest { display: flex; flex-direction: row; flex-wrap: wrap; gap: 6px; }
.suggest-item { font-size: 12px; color: var(--text-2); border: 1px solid var(--stroke); border-radius: 999px; padding: 4px 10px; cursor: pointer; }
.suggest-item:hover { background: rgba(255,255,255,.05); color: var(--text); }
.thinking { display: flex; flex-direction: row; align-items: center; gap: 4px; font-size: 12px; color: var(--text-3); }
.tool-event { font-size: 11px; color: var(--text-3); }
.tool-event-ok { color: #7FE3B8; }
.tool-event-err { color: #FF9AA8; }

.search { display: flex; flex-direction: row; align-items: center; gap: 6px; padding: 6px 10px; }
.search-box { flex: 1; min-width: 0; display: flex; flex-direction: row; align-items: center; gap: 6px; border: 1px solid var(--stroke); border-radius: 8px; padding: 2px; background: rgba(0,0,0,.16); }
.search-box:focus-within { border-color: rgba(76,141,255,.55); }
.search-input { width: 100%; height: 26px; padding: 4px 8px; font-size: 12px;
  background: transparent; color: var(--text); border: none; font-family: HarmonyOS Sans SC; }
.search-clear { width: 20px; height: 20px; border-radius: 5px; display: flex; align-items: center; justify-content: center; color: var(--text-3); cursor: pointer; }
.search-clear:hover { background: rgba(255,255,255,.08); color: var(--text); }

.scan-grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 14px; }
.scan-drop { border: 1px dashed rgba(255,255,255,.16); border-radius: 12px; padding: 18px; display: flex; flex-direction: column; align-items: center; gap: 6px; }
.scan-drop-icon { font-size: 24px; color: var(--text-3); }
.scan-result { display: flex; flex-direction: column; gap: 10px; }
.scan-stat { display: flex; flex-direction: column; gap: 1px; min-width: 72px; }
.scan-stat-value { font-size: 20px; font-weight: 600; color: #F4F8FF; }
.scan-stat-label { font-size: 11px; color: var(--text-3); }
.candidate { display: flex; flex-direction: row; align-items: center; gap: 8px; padding: 7px 10px; border-bottom: 1px solid rgba(255,255,255,.04); }
.candidate-main { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 1px; }
.candidate-side { margin-left: auto; display: flex; flex-direction: row; align-items: center; gap: 6px; }
.path { display: flex; flex-direction: row; align-items: center; gap: 6px; min-width: 0; cursor: pointer; }
.path-text { font-family: HarmonyOS Sans SC; font-size: 12px; color: var(--text-2); overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }

.settings { display: flex; flex-direction: row; gap: 16px; width: 100%; min-height: 0; }
.settings-nav { width: 180px; min-width: 180px; display: flex; flex-direction: column; gap: 2px; }
.settings-nav-item { padding: 7px 10px; border-radius: 8px; font-size: 13px; color: var(--text-2); cursor: pointer; }
.settings-nav-item:hover { background: rgba(255,255,255,.05); color: var(--text); }
.settings-nav-item.on { background: rgba(76,141,255,.15); color: #EAF1FF; }
.settings-pane { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 12px; }
.setting-row { display: flex; flex-direction: row; align-items: center; gap: 14px; padding: 10px 0; border-bottom: 1px solid var(--stroke); }
.setting-label { width: 200px; min-width: 200px; display: flex; flex-direction: column; gap: 2px; }
.setting-desc { font-size: 11px; color: var(--text-3); }
.setting-control { flex: 1; min-width: 0; display: flex; flex-direction: row; align-items: center; gap: 8px; }

.about-hero { display: flex; flex-direction: row; align-items: center; gap: 14px; padding: 8px 0 14px 0; }
.about-logo { width: 48px; height: 48px; border-radius: 12px; background: linear-gradient(135deg, rgba(76,141,255,.55) 0%, rgba(176,140,255,.35) 100%); border: 1px solid rgba(255,255,255,.16); display: flex; align-items: center; justify-content: center; font-size: 20px; }
.about-links { display: flex; flex-direction: column; gap: 6px; }
.link-row { display: flex; flex-direction: row; align-items: center; gap: 8px; font-size: 12px; color: var(--text-2); }
.secret-note { font-size: 11px; color: var(--warn); background: rgba(242,178,92,.08); border: 1px solid rgba(242,178,92,.22); border-radius: 8px; padding: 6px 10px; }

/* v0 兼容网格 */
.grid2 { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
.grid3 { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px; }

/* ══════════════════════════════════════════════════════════════════════
   窄窗（窗口最小 1040，所以只覆盖 1180）
   ══════════════════════════════════════════════════════════════════════ */
@media (max-width: 1239px) {
  .span-3 { grid-column: span 6; }
  .span-4 { grid-column: span 6; }
  .span-8 { grid-column: span 12; }
  .span-9 { grid-column: span 12; }
  .board { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .scan-grid { grid-template-columns: minmax(0, 1fr); }
  .settings-nav { width: 150px; min-width: 150px; }
  .signal-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); }
}

@media (prefers-reduced-motion: reduce) {
  .btn, .card.hoverable, .nav-item, .tab, .seg-item { transition: none; }
  .skeleton, .skeleton-line { animation: none; }
  .toast { animation: none; }
}
"#;
