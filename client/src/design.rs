// design.rs — 设计系统：macOS 的克制留白 × Windows 11 的 Mica 层次。
//
// 【设计语言】深海（deep）为底，蓝作强调（macOS 蓝 + Fluent 蓝的中间值）。
//   · 表面层次（Win11）：Mica 式半透明面板 + 1px 顶部高光描边 + 12–14 圆角；
//     页面底 → 面板 → 卡片三级明度差，靠透明度而不是纯色块堆叠。
//   · 留白与字重（macOS）：8px 节奏网格、正文 13px、标题 20px/600，
//     弱化分割线（rgba 6–10%），让内容自己形成分组。
//   · 动效：按钮/卡片 hover 只改边框与底色（120ms 级别的观感），不做花哨位移。
//
// 字体：HarmonyOS Sans SC（内置，见 assets/fonts 与 LICENSE.txt）。
// BUI 没有逐字形回退，所以必须显式绑定到内置字体——中文才不会变豆腐块。

/// 全局样式表（`style()` 元素塞在根节点里）。类名是唯一注入点：
/// 视图侧只用 class 名，颜色/圆角/节奏只在这里改。
pub const SHEET: &str = r#"
* { box-sizing: border-box; }
.root {
  position: absolute; inset: 0;
  display: flex; flex-direction: row;
  background: #0B1220;
  color: #E8EEF8;
  font-family: HarmonyOS Sans SC;
}
/* ── 侧栏（Mica 面板）── */
.sidebar {
  width: 250px; min-width: 250px; height: 100%;
  display: flex; flex-direction: column;
  background: linear-gradient(180deg, #0E1728 0%, #0C1424 100%);
  border-right: 1px solid rgba(255,255,255,0.06);
}
.sidebar-head { padding: 18px 16px 10px 16px; display: flex; flex-direction: column; gap: 2px; }
.brand { font-size: 16px; font-weight: 600; letter-spacing: 0.2px; }
.brand-sub { font-size: 11px; color: #7C8CA6; }
.sidebar-scroll { flex: 1; overflow-y: scroll; padding: 6px 10px 12px 10px; display: flex; flex-direction: column; gap: 1px; }
.sidebar-foot { padding: 10px 14px; border-top: 1px solid rgba(255,255,255,0.06); display: flex; flex-direction: column; gap: 6px; }
.sect-label { font-size: 11px; color: #6D7E99; padding: 10px 8px 4px 8px; letter-spacing: 0.4px; }
.nav-item {
  display: flex; flex-direction: row; align-items: center; gap: 8px;
  padding: 7px 10px; border-radius: 8px; font-size: 13px; color: #B7C4DA;
  border: 1px solid transparent; cursor: pointer;
}
.nav-item:hover { background: rgba(255,255,255,0.06); color: #DDE7F5; }
.nav-item.on { background: rgba(76,141,255,0.15); border-color: rgba(76,141,255,0.30); color: #EAF1FF; }
/* ── 主区 ── */
.main { flex: 1; height: 100%; display: flex; flex-direction: column; }
.main-head {
  padding: 16px 24px; display: flex; flex-direction: row; align-items: center; gap: 12px;
  border-bottom: 1px solid rgba(255,255,255,0.06);
}
.main-title { font-size: 20px; font-weight: 600; letter-spacing: 0.2px; }
.main-sub { font-size: 12px; color: #7C8CA6; }
.main-scroll { flex: 1; overflow-y: scroll; padding: 20px 24px 28px 24px; display: flex; flex-direction: column; gap: 14px; }
/* ── 卡片（Win11 层次）── */
.card {
  background: rgba(255,255,255,0.035);
  border: 1px solid rgba(255,255,255,0.07);
  border-radius: 12px;
  padding: 16px;
  display: flex; flex-direction: column; gap: 10px;
}
.card:hover { border-color: rgba(124,166,255,0.28); }
.card-title { font-size: 13px; font-weight: 600; color: #DCE6F5; display: flex; flex-direction: row; align-items: center; gap: 8px; }
/* ── 按钮 ── */
.btn {
  display: inline-flex; flex-direction: row; align-items: center; gap: 6px;
  padding: 6px 12px; border-radius: 8px; font-size: 13px;
  border: 1px solid rgba(255,255,255,0.10); background: rgba(255,255,255,0.05);
  color: #E8EEF8; cursor: pointer;
}
.btn:hover { background: rgba(255,255,255,0.09); border-color: rgba(255,255,255,0.18); }
.btn.accent { background: #4C8DFF; border-color: #4C8DFF; color: #081120; font-weight: 600; }
.btn.accent:hover { background: #5E9BFF; border-color: #5E9BFF; }
.btn.ghost { background: transparent; }
.btn.danger { color: #FF8A9A; border-color: rgba(255,107,129,0.35); }
.btn:disabled { opacity: 0.45; cursor: default; }
/* ── 文本与杂件 ── */
.muted { color: #8B9BB4; }
.dim { color: #64748B; }
.h2 { font-size: 16px; font-weight: 600; }
.row { display: flex; flex-direction: row; align-items: center; gap: 8px; }
.wrap { display: flex; flex-direction: row; gap: 8px; flex-wrap: wrap; }
.chip {
  display: inline-flex; align-items: center; gap: 5px;
  padding: 3px 9px; border-radius: 999px; font-size: 12px;
  border: 1px solid rgba(255,255,255,0.09); color: #B7C4DA;
}
.dot { width: 8px; height: 8px; border-radius: 999px; }
/* 图谱产物卡：存在=可打开（蓝边），未生成=提示（虚线边） */
.artifact { border-style: solid; }
.artifact.ready { border-color: rgba(76,141,255,0.35); background: rgba(76,141,255,0.07); }
.artifact.missing { border-style: dashed; border-color: rgba(255,255,255,0.12); }
.input {
  padding: 7px 10px; border-radius: 8px; font-size: 13px;
  border: 1px solid rgba(255,255,255,0.12); background: rgba(0,0,0,0.25);
  color: #E8EEF8;
}
.input:focus { border-color: rgba(76,141,255,0.55); }
.divider { height: 1px; width: 100%; background: rgba(255,255,255,0.06); }
.kv { display: flex; flex-direction: row; align-items: baseline; gap: 6px; }
.kv .k { font-size: 12px; color: #7C8CA6; }
.kv .v { font-size: 13px; color: #DCE6F5; }
.metric { font-size: 26px; font-weight: 600; letter-spacing: -0.3px; }
.banner { padding: 10px 14px; border-radius: 10px; font-size: 12px; }
.banner.warn { background: rgba(255,180,84,0.10); color: #FFC97A; border: 1px solid rgba(255,180,84,0.25); }
.banner.err { background: rgba(255,107,129,0.10); color: #FF9AA8; border: 1px solid rgba(255,107,129,0.28); }
.banner.ok { background: rgba(63,207,142,0.10); color: #7FE3B8; border: 1px solid rgba(63,207,142,0.25); }
.grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
.grid3 { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 14px; }
"#;
