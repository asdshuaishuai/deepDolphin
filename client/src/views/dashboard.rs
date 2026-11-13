// dashboard.rs — 项目群仪表盘（Fluent 磁贴）：KPI / 筛选 / 项目磁贴 / 提交构成。
//
// 【事实来源】
//   · KPI 只用引擎 `status.summary` 的原值，**不在客户端重算**：
//     `listedProjects` / `dirtyProjects` / `activeProjects` / `staleProjects`。
//     客户端重算会造出第二套口径（例如 `pending_count` 把未跟踪与 stash 也算进
//     「待处理」，而 `summary.dirtyProjects` 只数 `userDirtyCount > 0`）——
//     两个数字并排时，读者无从知道该信哪个。
//   · 项目卡与提交构成来自 `status.projects` 的逐项事实；
//     提交类型样本的完整性由每个项目的 `commitTypesTruncated` 各自披露。
//
// 【筛选的分工】
//   · 时间窗（全部 / 30 天 / 7 天）作用于**项目卡**与**提交构成样本**；
//   · 提交类型只作用于**提交构成**，不改项目卡（与本页筛选条的说明一致）。
//   · KPI 恒为全量，不随筛选变化。
//   · 不用 `app::DashboardFilters::matches`：它把 `commit_type` 也压到项目卡上，
//     与本页约定相反。时间窗判定在本文件实现局部版本：
//     先按 `lastCommitAt` 精确判；日期读不出来时退回 `lastCommitAgo` 的相对描述。
//
// 【三种「没有」必须分开说】
//   · 真的没有项目：`.empty`「还没有注册项目」+ 扫描 / 添加入口；
//   · 读不出来：引擎报错 / 采集失败 / 时间读不出来 —— 红条或 unknown chip，
//     绝不渲染成 0；
//   · 筛选无结果：项目存在但被时间窗筛掉 —— `.empty` 点名「已隐藏 N 个」，
//     并给「清除筛选」。
//
// 【布局】`.main-head` + `.dash-hero` + `.dash-filters` 固定，内容在
// `.main-scroll`（id = `scroll-dashboard`）。玻璃面只有 hero/head 两处，
// 卡片与磁贴一律 rgba（滚动区不放 backdrop-filter）。

use crate::app::{
    Action, AppAction, AppRoot, AppState, Load, MenuItem, RangeFilter, RefreshScope, Route,
};
use crate::models::{self, Project, Reading, Summary, Tone};
use crate::views::{feedback_block, scroll_id};
use blenderui::prelude::*;
use std::collections::BTreeMap;

// ══════════════════════════════════════════════════════════════════════
// 纯判定：时间窗 / 提交构成（可单测；不碰 UI）
// ══════════════════════════════════════════════════════════════════════

/// 项目最近一次提交的**判定依据**。
///
/// `Exact` 来自 `lastCommitAt`（可解析的 ISO 时间）；
/// `Approx` 来自 `lastCommitAgo` 的相对描述（中文 / 英文两种单位）；
/// `Unknown` 两者都读不出来 —— 这时项目**保留**在时间窗里，
/// 并挂「时间读不出来」chip，而不是被静默筛掉。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TimeBasis {
    Exact(i64),
    Approx(i64),
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WindowGate {
    In,
    Out,
    Unknown,
}

fn time_basis(p: &Project) -> TimeBasis {
    match models::age_days(&p.last_commit_at) {
        Reading::Known(days) => TimeBasis::Exact(days),
        Reading::NotRead => {
            let ago = p.last_commit_ago.as_deref().unwrap_or("");
            match ago_days(ago) {
                Some(days) => TimeBasis::Approx(days),
                None => TimeBasis::Unknown,
            }
        }
    }
}

fn window_gate(p: &Project, range: RangeFilter) -> WindowGate {
    match range.days() {
        None => WindowGate::In,
        Some(limit) => match time_basis(p) {
            TimeBasis::Exact(days) | TimeBasis::Approx(days) => {
                if days <= limit {
                    WindowGate::In
                } else {
                    WindowGate::Out
                }
            }
            // 读不出来不等于「在窗口外」也不等于「在窗口内」：保留 + 披露。
            TimeBasis::Unknown => WindowGate::Unknown,
        },
    }
}

/// 解析引擎的 `lastCommitAgo`（`timeAgo` 的输出）为「多少天前」。
///
/// 引擎按自己的事实语言输出中文或英文：
///   `刚刚` / `N 分钟前` / `N 小时前` / `N 天前` / `N 个月前` / `N 年前`
///   `just now` / `Nm ago` / `Nh ago` / `Nd ago` / `Nmo ago` / `Ny ago`
///
/// 返回 `None` 的情况（= 读不出来，不是 0 天）：
///   · 空串 / `-`；
///   · 时间戳在未来且超过一天的「⚠ 时间异常」——不能把异常当成「刚刚」。
fn ago_days(s: &str) -> Option<i64> {
    let s = s.trim();
    if s.is_empty() || s == "-" || s.starts_with('⚠') {
        return None;
    }
    let lower = s.to_lowercase();
    if lower.starts_with("just now") || lower.starts_with("刚刚") {
        return Some(0);
    }
    let digits: String = lower.chars().take_while(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() {
        return None;
    }
    let n: i64 = digits.parse().ok()?;
    let rest = lower[digits.len()..].trim_start();
    if rest.contains("分钟") || rest.starts_with('m') && !rest.starts_with("mo") {
        return Some(0);
    }
    if rest.contains("小时") || rest.starts_with('h') {
        return Some(0);
    }
    // 天 / 月 / 年的顺序不能反：`个月前` 同时含「月」，`天前` 只含「天」。
    if rest.contains("天") || rest.starts_with('d') {
        return Some(n);
    }
    if rest.contains("月") || rest.starts_with("mo") {
        return Some(n * 30);
    }
    if rest.contains("年") || rest.starts_with('y') {
        return Some(n * 365);
    }
    None
}

/// 提交构成样本。每个计数都带「它到底数了什么」的边界。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct Composition {
    /// 类型 → 次数，按次数降序、同次数按名称升序。
    types: Vec<(String, i64)>,
    /// 类型计数之和（**不是**仓库提交总数；样本截断时是下界）。
    total: i64,
    /// 时间窗内的项目总数（含读不出来的）。
    window_projects: usize,
    /// 窗口内可读的项目数（= with_types + empty_types）。
    sample_projects: usize,
    /// 窗口内采集失败的项目数：未计入样本，绝不当作 0 次提交。
    unreadable: usize,
    /// 可读但时间读不出来、因此无法判定是否在窗口内（已保留）的项目数。
    unknown_time: usize,
    /// 可读但没有提交类型数据的项目数（非 git / 没有提交 / 类型全为 0）。
    empty_types: usize,
    /// `commitTypesTruncated == true` 的项目数：该项目的计数是下界。
    truncated: usize,
    /// 缺 `commitTypesTruncated` 键的项目数：完整性未披露，不许当成「没截断」。
    undisclosed: usize,
}

fn composition(projects: &[Project], range: RangeFilter) -> Composition {
    let mut out = Composition::default();
    let mut map: BTreeMap<String, i64> = BTreeMap::new();

    for p in projects {
        let gate = window_gate(p, range);
        if gate == WindowGate::Out {
            continue;
        }
        out.window_projects += 1;

        // 采集失败：保留在窗口计数里，但**不进样本**。它的提交数是未知，不是 0。
        if p.error.is_some() {
            out.unreadable += 1;
            continue;
        }
        if gate == WindowGate::Unknown {
            out.unknown_time += 1;
        }
        out.sample_projects += 1;

        let mut contributed = false;
        for t in &p.commit_types {
            let n = t.count.max(0);
            if n == 0 {
                continue;
            }
            *map.entry(t.type_.clone()).or_insert(0) += n;
            contributed = true;
        }
        if !contributed {
            out.empty_types += 1;
            continue;
        }

        match p.commit_types_truncated {
            Some(true) => out.truncated += 1,
            None => out.undisclosed += 1,
            Some(false) => {}
        }
    }

    out.total = map.values().sum();
    out.types = map.into_iter().collect();
    out.types
        .sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    out
}

/// 提交类型下拉的清单：**全量项目**（不受时间窗影响）的汇总，只列真实出现的类型。
fn all_type_totals(projects: &[Project]) -> Vec<(String, i64)> {
    let mut map: BTreeMap<String, i64> = BTreeMap::new();
    for p in projects {
        if p.error.is_some() {
            continue;
        }
        for t in &p.commit_types {
            if t.count > 0 {
                *map.entry(t.type_.clone()).or_insert(0) += t.count;
            }
        }
    }
    let mut out: Vec<(String, i64)> = map.into_iter().collect();
    out.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    out
}

const MAX_BAR_SEGMENTS: usize = 12;
const LEGEND_TOP: usize = 6;

/// 堆叠条的分段。类型筛选时只画「选中类型 + 其余」两段；
/// 选中类型在样本里为 0 时返回空（不画一根「全部是其他」的假条）。
fn composition_segments(c: &Composition, selected: Option<&str>) -> Vec<(String, i64)> {
    match selected {
        Some(t) => {
            let n = c
                .types
                .iter()
                .find(|(name, _)| name == t)
                .map(|(_, n)| *n)
                .unwrap_or(0);
            if n == 0 {
                return Vec::new();
            }
            let mut out = vec![(t.to_string(), n)];
            let rest = c.total - n;
            if rest > 0 {
                out.push(("其他类型".to_string(), rest));
            }
            out
        }
        None => {
            if c.types.len() <= MAX_BAR_SEGMENTS {
                c.types.clone()
            } else {
                let keep = MAX_BAR_SEGMENTS - 1;
                let mut out = c.types[..keep].to_vec();
                let rest: i64 = c.types[keep..].iter().map(|(_, n)| *n).sum();
                out.push(("其他类型".to_string(), rest));
                out
            }
        }
    }
}

/// 类型在**全局**排序里的颜色位（保证同一类型在条形与图例里同色）。
fn type_color_index(name: &str, all: &[(String, i64)]) -> Option<usize> {
    all.iter().position(|(t, _)| t == name).map(|i| i % 12)
}

fn pct(n: i64, total: i64) -> f32 {
    if total <= 0 {
        0.0
    } else {
        (n as f32 / total as f32) * 100.0
    }
}

fn pct_label(n: i64, total: i64) -> String {
    format!("{:.0}%", pct(n, total))
}

/// 单个项目的类型分段（全部分段，供迷你条与图例共用）。
fn project_types(p: &Project) -> Vec<(String, i64)> {
    let mut out: Vec<(String, i64)> = p
        .commit_types
        .iter()
        .filter(|t| t.count > 0)
        .map(|t| (t.type_.clone(), t.count))
        .collect();
    out.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    out
}

// ══════════════════════════════════════════════════════════════════════
// 页面
// ══════════════════════════════════════════════════════════════════════

pub fn render(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let head = render_head(state, cx);
    let hero = render_hero(state);
    let filters = render_filters(state, cx);
    let scroll = render_scroll(state, cx);

    div()
        .class("main")
        .child(head)
        .child(hero)
        .child(filters)
        .child(scroll)
}

fn render_head(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let sub = match &state.status {
        Some(env) if summary_blank(&env.summary) => format!(
            "项目群状态已读取，但 summary 缺键（计数不可用） · 引擎 {}",
            state.engine_short()
        ),
        Some(env) => {
            let data_time = if env.summary.generated_at.trim().is_empty() {
                "数据时间读不出来".to_string()
            } else {
                models::short_iso(&env.summary.generated_at)
            };
            format!(
                "{} 个项目在册 · {} · 引擎 {}",
                env.summary.listed_projects,
                data_time,
                state.engine_short()
            )
        }
        None => format!("项目群状态尚未读取 · 引擎 {}", state.engine_short()),
    };

    div()
        .class("main-head glass")
        .child(
            div()
                .class("main-head-main")
                .child(div().class("main-title").child("项目群脉搏"))
                .child(div().class("main-sub").id("dash-sub").child(sub)),
        )
        .child(div().class("spacer"))
        .child(
            div()
                .class("main-actions")
                .child(
                    div()
                        .class("btn btn-sm")
                        .id("dash-refresh")
                        .child("刷新")
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.state
                                .dispatch(Action::App(AppAction::Refresh(RefreshScope::All)));
                            cx.notify();
                        })),
                )
                .child(
                    // 更多菜单：写操作一律走确认（AskUpdate），并复用根节点的菜单浮层。
                    div()
                        .class("btn btn-sm btn-ghost")
                        .id("dash-more")
                        .child("更多 ▾")
                        .on_click(cx.listener(|this, e: &ClickEvent, _, cx| {
                            let items = vec![
                                MenuItem {
                                    label: "浅更新全部（重新索引）".to_string(),
                                    shortcut: None,
                                    danger: false,
                                    action: AppAction::AskUpdate {
                                        project: None,
                                        deep: false,
                                    },
                                },
                                MenuItem {
                                    label: "深更新全部".to_string(),
                                    shortcut: None,
                                    danger: false,
                                    action: AppAction::AskUpdate {
                                        project: None,
                                        deep: true,
                                    },
                                },
                                MenuItem {
                                    label: "扫描与添加项目".to_string(),
                                    shortcut: None,
                                    danger: false,
                                    action: AppAction::Navigate(Route::Scan),
                                },
                                MenuItem {
                                    label: "引擎诊断（doctor）".to_string(),
                                    shortcut: None,
                                    danger: false,
                                    action: AppAction::ShowDoctor,
                                },
                            ];
                            this.state.apply(AppAction::OpenMenu {
                                x: e.down.position.x.0,
                                y: e.down.position.y.0,
                                items,
                            });
                            cx.notify();
                        })),
                ),
        )
}

fn render_hero(state: &AppState) -> Div {
    let mut left = div().class("hero grow");
    let mut health = div().class("row-wrap fill");

    match &state.status {
        Some(env) if summary_blank(&env.summary) => {
            // summary 缺键时画 0 等于说「项目群是空的」。
            left = left
                .child(div().class("hero-metric").id("dash-hero-total").child("—"))
                .child(div().class("hero-title").child("项目群计数"))
                .child(
                    div()
                        .class("hero-sub")
                        .child("引擎 summary 缺键：KPI 无法计算（不是 0 个项目）"),
                );
            health = health.child(chip("summary 缺键".to_string(), Tone::Unknown));
        }
        Some(env) => {
            let s = &env.summary;
            left = left
                .child(
                    div()
                        .class("hero-metric")
                        .id("dash-hero-total")
                        .child(s.listed_projects.to_string()),
                )
                .child(div().class("hero-title").child("个项目在册"))
                .child(div().class("hero-sub").child(format!(
                    "采集成功 {} · 失败 {} · 进度库降级 {}",
                    s.project_count, s.failed_projects, s.degraded_stores
                )));

            // 全部是引擎 summary 原值；每个 chip 只在非 0 时出现。
            if s.failed_projects > 0 {
                health = health.child(chip(format!("采集失败 {}", s.failed_projects), Tone::Err));
            }
            if s.degraded_stores > 0 {
                health = health.child(chip(
                    format!("进度库降级 {}", s.degraded_stores),
                    Tone::Warn,
                ));
            }
            if s.branch_unknown_projects > 0 {
                health = health.child(chip(
                    format!("分支数读不出来 {}", s.branch_unknown_projects),
                    Tone::Unknown,
                ));
            }
            if s.branch_truncated_projects > 0 {
                health = health.child(chip(
                    format!("分支数被截断 {}", s.branch_truncated_projects),
                    Tone::Info,
                ));
            }
            if s.failed_projects == 0
                && s.degraded_stores == 0
                && s.branch_unknown_projects == 0
                && s.branch_truncated_projects == 0
            {
                // 「没有报告」是引擎能给出的最强事实，不是「一切正常」的保证。
                health = health.child(chip("summary 未报告失败或降级".to_string(), Tone::Ok));
            }
        }
        None => {
            left = left
                .child(div().class("hero-metric").id("dash-hero-total").child("—"))
                .child(div().class("hero-title").child("项目群状态"))
                .child(
                    div()
                        .class("hero-sub")
                        .child("还没有读到状态；这不是「没有项目」"),
                );
        }
    }

    let data_time = match &state.status {
        Some(env) if !env.summary.generated_at.trim().is_empty() => {
            models::short_iso(&env.summary.generated_at)
        }
        Some(_) => "数据时间读不出来".to_string(),
        None => "数据时间未知".to_string(),
    };
    let refreshed = state
        .last_refresh
        .map(models::human_ago)
        .unwrap_or_else(|| "本次会话尚未刷新".to_string());

    let mut right = div()
        .class("stack-sm right")
        .child(
            div()
                .class("t-caption")
                .child(format!("数据时间 {data_time}")),
        )
        .child(
            div()
                .class("t-caption")
                .child(format!("上次刷新 {refreshed}")),
        )
        .child(
            div()
                .class("t-caption")
                .child(format!("引擎 {}", state.engine_short())),
        );
    if state.last_refresh_failed {
        right = right.child(chip("上次刷新失败".to_string(), Tone::Err));
    }

    div()
        .class("dash-hero glass")
        .child(left)
        .child(div().class("divider-v"))
        .child(health)
        .child(div().class("spacer"))
        .child(right)
}

fn render_filters(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let filters = &state.ui.dashboard;
    let mut seg = div().class("seg").id("dash-range");
    for range in RangeFilter::all() {
        let on = filters.range == range;
        seg = seg.child(
            div()
                .class(if on { "seg-item on" } else { "seg-item" })
                .id(format!("dash-range-{}", range_key(range)))
                .child(range.label())
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state.apply(AppAction::SetDashboardRange(range));
                    cx.notify();
                })),
        );
    }

    let types = all_type_totals(state.projects());
    let picker = if state.status.is_none() {
        // 「还没读」与「读了但没有类型」是两件事，别合并成同一句话。
        div()
            .class("picker-btn is-disabled")
            .id("dash-type-picker")
            .child("提交类型：尚未读取")
            .child(div().class("t-caption").child("先读取项目群状态"))
    } else if types.is_empty() {
        // 没有可筛类型时说清原因；`.is-disabled` 只拦点击，不解释。
        div()
            .class("picker-btn is-disabled")
            .id("dash-type-picker")
            .child("提交类型：无数据")
            .child(
                div()
                    .class("t-caption")
                    .child("没有可筛的类型（都读不出来或都没有类型数据）"),
            )
    } else {
        let label = match &filters.commit_type {
            Some(t) => format!("提交类型：{t}"),
            None => "提交类型：全部".to_string(),
        };
        div()
            .class("picker-btn")
            .id("dash-type-picker")
            .child(label)
            .child("▾")
            .title("打开提交类型清单（按全量项目汇总，只影响提交构成）")
            .on_click(cx.listener(|this, e: &ClickEvent, _, cx| {
                let items = type_menu_items(&this.state);
                this.state.apply(AppAction::OpenMenu {
                    x: e.down.position.x.0,
                    y: e.down.position.y.0,
                    items,
                });
                cx.notify();
            }))
    };

    let mut row = div().class("dash-filters").child(seg).child(picker);

    if filters.range != RangeFilter::All || filters.commit_type.is_some() {
        row = row.child(
            div()
                .class("btn btn-sm btn-ghost")
                .id("dash-clear-filters")
                .child("清除筛选")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state
                        .apply(AppAction::SetDashboardRange(RangeFilter::All));
                    this.state.apply(AppAction::SetDashboardCommitType(None));
                    cx.notify();
                })),
        );
    }

    row.child(div().class("spacer")).child(
        div()
            .class("t-caption t-dim nowrap")
            .child("时间窗→项目卡+构成 · 类型→仅构成 · KPI 全量"),
    )
}

fn type_menu_items(state: &AppState) -> Vec<MenuItem> {
    let mut items = vec![MenuItem {
        label: "全部类型".to_string(),
        shortcut: None,
        danger: false,
        action: AppAction::SetDashboardCommitType(None),
    }];
    for (name, count) in all_type_totals(state.projects()) {
        items.push(MenuItem {
            label: format!("{name} · {count}"),
            shortcut: None,
            danger: false,
            action: AppAction::SetDashboardCommitType(Some(name)),
        });
    }
    items
}

fn render_scroll(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let mut scroll = div()
        .class("main-scroll")
        .id(scroll_id(state))
        .child(feedback_block(state, cx));

    // 上次刷新失败但还有旧数据：必须说清「这是旧数据」，不能装作当前。
    if state.status.is_some() {
        if let Some(err) = &state.error {
            let data_time = state
                .status
                .as_ref()
                .map(|e| models::short_iso(&e.summary.generated_at))
                .unwrap_or_default();
            let data_time = if data_time.is_empty() {
                "数据时间读不出来".to_string()
            } else {
                data_time
            };
            scroll = scroll.child(
                div()
                    .class("banner err")
                    .id("dash-refresh-error")
                    .child(div().class("banner-title").child("上次刷新失败"))
                    .child(div().class("banner-body").child(format!(
                        "下面是上次成功读取的数据（{data_time}），不是刚刚的现场。原因：{err}"
                    ))),
            );
        }
    }

    if !state.engine_warnings.is_empty() {
        let shown = state.engine_warnings.len().min(3);
        let tail = if state.engine_warnings.len() > shown {
            format!("；还有 {} 条", state.engine_warnings.len() - shown)
        } else {
            String::new()
        };
        let all_warnings = state.engine_warnings.join("\n");
        scroll = scroll.child(
            div()
                .class("banner warn")
                .id("dash-engine-warnings")
                .child(div().class("banner-title").child(format!(
                    "引擎告警（{}，读命令的 stderr，不是失败）",
                    state.engine_warnings.len()
                )))
                .child(div().class("banner-body").child(format!(
                    "{}{tail}",
                    state.engine_warnings[..shown].join("；")
                )))
                // 只显示 3 条时必须给出拿到全量的手段，否则截断就是死胡同。
                .child(
                    div().class("banner-action").child(
                        div()
                            .class("btn btn-sm btn-ghost")
                            .id("dash-warnings-copy")
                            .child(format!("复制全部 {} 条", state.engine_warnings.len()))
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.apply(AppAction::CopyText {
                                    text: all_warnings.clone(),
                                    label: "引擎告警".to_string(),
                                });
                                cx.notify();
                            })),
                    ),
                ),
        );
    }

    match &state.status {
        None => scroll.child(render_no_status(state, cx)),
        Some(env) => {
            let global_types = all_type_totals(&env.projects);
            // 只有「引擎确实读到了 0 个项目」才走极简空态；summary 缺键时
            // 0 不可信，必须走完整的「无法计算」披露。
            if env.projects.is_empty()
                && env.summary.listed_projects == 0
                && !summary_blank(&env.summary)
            {
                // 真的一个项目都没有：不要用四张 0 KPI 把「没有项目」说成
                // 「项目群全都很健康」。只留一个带扫描/添加入口的空态。
                scroll.child(render_projects(
                    state,
                    &env.summary,
                    &env.projects,
                    &global_types,
                    cx,
                ))
            } else {
                scroll
                    .child(render_kpis(state, &env.summary))
                    .child(render_composition(state, &env.projects, &global_types, cx))
                    .child(render_projects(
                        state,
                        &env.summary,
                        &env.projects,
                        &global_types,
                        cx,
                    ))
            }
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// KPI（引擎 summary 原值）
// ══════════════════════════════════════════════════════════════════════

fn render_kpis(state: &AppState, s: &Summary) -> Div {
    // 若 summary 是缺键兜底出来的全 0，不能把 0 当成真实统计 —— 那正是
    // 「失败被渲染成正常」的老毛病。这里显式区分。
    if summary_blank(s) {
        return div().class("banner unknown").id("dash-kpi-unknown").child(
            div()
                .class("banner-body")
                .child("引擎的 summary 里没有任何项目计数键：KPI 无法计算（不是 0 个项目）"),
        );
    }

    let active_line = match &state.dashboard {
        Load::Ready(d) => {
            // dashboard 与 status 是两条命令、两个时间点：把 dashboard 的
            // 数据时间写出来，避免把旧聚合当成刚刚的现场。
            let at = if d.fetched_at.trim().is_empty() {
                "时间读不出来".to_string()
            } else {
                models::short_iso(&d.fetched_at)
            };
            (
                format!(
                    "近 7 天有提交 {} · 近 30 天 {}（dashboard 口径 @{at}，按最近提交日期推算）",
                    d.projects.active7d, d.projects.active30d
                ),
                None,
            )
        }
        Load::Failed(e) => (
            format!(
                "近 7/30 天活跃读不出来（dashboard 失败：{}）",
                e.user_message()
            ),
            Some(Tone::Unknown),
        ),
        Load::Loading => ("近 7/30 天活跃读取中".to_string(), None),
        Load::Idle => ("近 7/30 天活跃尚未读取".to_string(), None),
    };

    let branch_line = if s.branch_unknown_projects > 0 {
        (
            format!(
                "{} 个项目分支数读不出来，未计入总数",
                s.branch_unknown_projects
            ),
            Some(Tone::Unknown),
        )
    } else if s.branch_truncated_projects > 0 {
        (
            format!(
                "{} 个项目的追踪数小于仓库真实分支数",
                s.branch_truncated_projects
            ),
            Some(Tone::Info),
        )
    } else {
        ("分支数全部可读".to_string(), None)
    };

    div()
        .class("tiles")
        .id("dash-kpis")
        .child(kpi_tile(
            "dash-kpi-total",
            "项目总数",
            s.listed_projects.to_string(),
            "含采集失败的项目，不含已停用项目；失败项目仍逐条列出".to_string(),
            kpi_foot(
                format!(
                    "采集成功 {} · 失败 {} · 进度库降级 {}",
                    s.project_count, s.failed_projects, s.degraded_stores
                ),
                None,
            ),
            None,
        ))
        .child(kpi_tile(
            "dash-kpi-pending",
            "待你动手",
            s.dirty_projects.to_string(),
            "有未提交改动的项目数（summary.dirtyProjects）".to_string(),
            kpi_foot(
                "口径只算未提交改动；未跟踪与 stash 不计入这个数字，见项目卡".to_string(),
                None,
            ),
            if s.dirty_projects > 0 {
                Some(Tone::Warn)
            } else {
                None
            },
        ))
        .child(kpi_tile(
            "dash-kpi-active",
            "活跃",
            s.active_projects.to_string(),
            "有 active 状态分支的项目（按分支 status，不是按提交日期）".to_string(),
            kpi_foot(active_line.0, active_line.1),
            None,
        ))
        .child(kpi_tile(
            "dash-kpi-stale",
            "停滞（逾期未动）",
            s.stale_projects.to_string(),
            "有 stale 状态分支的项目".to_string(),
            kpi_foot(branch_line.0, branch_line.1),
            if s.stale_projects > 0 {
                Some(Tone::Stale)
            } else {
                None
            },
        ))
}

fn kpi_tile(
    id: &str,
    label: &str,
    value: String,
    hint: String,
    foot: Div,
    value_tone: Option<Tone>,
) -> Div {
    let value_class = match value_tone {
        Some(t) => format!("kpi-value {}", t.class()),
        None => "kpi-value".to_string(),
    };
    div().class("tile span-3").child(
        div()
            .class("kpi")
            .id(id.to_string())
            .child(div().class("kpi-label").child(label.to_string()))
            .child(div().class(value_class).child(value))
            .child(div().class("kpi-hint").child(hint))
            .child(foot),
    )
}

fn kpi_foot(text: String, tone: Option<Tone>) -> Div {
    match tone {
        Some(t) => div().class(format!("kpi-foot {}", t.class())).child(text),
        None => div().class("kpi-foot").child(text),
    }
}

// ══════════════════════════════════════════════════════════════════════
// 提交构成
// ══════════════════════════════════════════════════════════════════════

fn render_composition(
    state: &AppState,
    projects: &[Project],
    global_types: &[(String, i64)],
    cx: &mut Context<AppRoot>,
) -> Div {
    let range = state.ui.dashboard.range;
    let selected = state.ui.dashboard.commit_type.clone();
    let c = composition(projects, range);
    let segments = composition_segments(&c, selected.as_deref());

    let mut head = div()
        .class("card-head")
        .child(div().class("card-title").child("提交构成"))
        .child(chip(range.label().to_string(), Tone::Idle));

    if let Some(t) = &selected {
        head = head.child(
            // 点按选中 chip 取消筛选：比让用户再打开一次下拉更直接。
            div()
                .class("chip chip-sm accent")
                .id("dash-composition-type-filter")
                .child(format!("类型：{t}"))
                .child(div().class("t-caption").child("×"))
                .title("点按清除类型筛选")
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state.apply(AppAction::SetDashboardCommitType(None));
                    cx.notify();
                })),
        );
    }

    let sample_note = if c.total > 0 {
        if c.truncated > 0 {
            format!("样本内至少 {} 次提交（有项目被截断）", c.total)
        } else {
            format!("样本内 {} 次提交（类型计数之和）", c.total)
        }
    } else {
        "样本内没有可用的类型计数".to_string()
    };
    head = head
        .child(div().class("spacer"))
        .child(div().class("card-sub").child(sample_note));

    let mut body = div().class("card-body").id("dash-composition");

    // ── 条形或对应的空/读不出来态 ──
    if projects.is_empty() {
        // 调用方只在「引擎说在册 N 个、却没有任何明细」时走到这里：
        // 这是读不出来，不是「时间窗内没有项目」。
        body = body.child(empty_block(
            "!",
            "项目明细读不出来",
            "引擎报告有项目在册，但没有返回任何项目明细；提交构成无法计算。".to_string(),
            vec![retry_btn("dash-composition-retry", cx)],
        ));
    } else if c.window_projects == 0 {
        body = body.child(empty_block(
            "▤",
            "时间窗内没有项目",
            format!(
                "「{}」窗内没有可统计的项目。换一个时间窗或清除筛选。",
                range.label()
            ),
            vec![clear_filters_btn("dash-composition-clear", cx)],
        ));
    } else if c.sample_projects == 0 {
        // 有项目但全部采集失败：这是读不出来，不是「没有提交」。
        body = body.child(
            div()
                .class("banner err")
                .child(div().class("banner-title").child("提交构成读不出来"))
                .child(div().class("banner-body").child(format!(
                    "时间窗内 {} 个项目全部采集失败，提交构成无法计算 —— 这不是「没有提交」。",
                    c.unreadable
                ))),
        );
    } else if c.types.is_empty() {
        body = body.child(empty_block(
            "◌",
            "样本内没有提交类型数据",
            format!(
                "{} 个可读项目都没有类型计数（可能是非 git 仓库或还没有提交）。",
                c.empty_types
            ),
            Vec::new(),
        ));
    } else if let Some(t) = &selected {
        let selected_count = c
            .types
            .iter()
            .find(|(name, _)| name == t)
            .map(|(_, n)| *n)
            .unwrap_or(0);
        if selected_count == 0 {
            let global = all_type_totals(projects)
                .iter()
                .find(|(name, _)| name == t)
                .map(|(_, n)| *n)
                .unwrap_or(0);
            body = body.child(
                div()
                    .class("banner info")
                    .child(div().class("banner-title").child(format!(
                        "当前时间窗内没有「{t}」类型的提交"
                    )))
                    .child(div().class("banner-body").child(format!(
                        "该类型在全部项目中出现过 {global} 次（不受时间窗限制）。要么换时间窗，要么清除类型筛选。"
                    )))
                    .child(
                        div()
                            .class("banner-action")
                            .child(clear_filters_btn("dash-composition-clear-type", cx)),
                    ),
            );
        } else {
            body = body
                .child(composition_bar(
                    &segments,
                    c.total,
                    global_types,
                    Some(t.as_str()),
                    cx,
                ))
                .child(composition_legend(&c, global_types, Some(t.as_str()), cx));
        }
    } else {
        body = body
            .child(composition_bar(&segments, c.total, global_types, None, cx))
            .child(composition_legend(&c, global_types, None, cx));
    }

    // ── 每一层截断/缺口的披露恒发（没有就不是省略，而是知道） ──
    body = body
        .child(div().class("divider"))
        .child(composition_disclosures(&c));

    div()
        .class("tile span-12")
        .child(div().class("card").child(head).child(body))
}

fn composition_bar(
    segments: &[(String, i64)],
    total: i64,
    global_types: &[(String, i64)],
    selected: Option<&str>,
    cx: &mut Context<AppRoot>,
) -> Div {
    let mut bar = div().class("stackbar").id("dash-composition-bar");
    for (name, count) in segments {
        let width = pct(*count, total);
        let mut seg = div()
            .class("stack-seg")
            .style(format!("width: {width:.2}%;"))
            .title(format!(
                "{name}：{count} 次（{}）",
                pct_label(*count, total)
            ));

        match type_color_index(name, global_types) {
            Some(i) => seg = seg.class(format!("s{}", i + 1)),
            // 「其他类型」是聚合段：用中性灰，不冒充某个真实类型。
            None => seg = seg.class("neutral-fill"),
        }

        // 点条段 = 只看这一类型；聚合段与当前选中类型不可点（避免无意义的同义动作）。
        if name != "其他类型" && selected != Some(name.as_str()) {
            let t = name.clone();
            seg = seg.on_click(cx.listener(move |this, _, _, cx| {
                this.state
                    .apply(AppAction::SetDashboardCommitType(Some(t.clone())));
                cx.notify();
            }));
        }
        bar = bar.child(seg);
    }
    bar
}

fn composition_legend(
    c: &Composition,
    global_types: &[(String, i64)],
    selected: Option<&str>,
    cx: &mut Context<AppRoot>,
) -> Div {
    let mut row = div().class("row-wrap").id("dash-composition-legend");

    match selected {
        Some(t) => {
            let n = c
                .types
                .iter()
                .find(|(name, _)| name == t)
                .map(|(_, n)| *n)
                .unwrap_or(0);
            if n > 0 {
                row = row.child(legend_chip(
                    t.to_string(),
                    n,
                    c.total,
                    type_color_index(t, global_types),
                    true,
                    Some(t.to_string()),
                    cx,
                ));
                let rest = c.total - n;
                if rest > 0 {
                    row = row.child(neutral_legend_chip("其他类型".to_string(), rest, c.total));
                }
            }
        }
        None => {
            for (name, count) in c.types.iter().take(LEGEND_TOP) {
                row = row.child(legend_chip(
                    name.clone(),
                    *count,
                    c.total,
                    type_color_index(name, global_types),
                    false,
                    Some(name.clone()),
                    cx,
                ));
            }
            if c.types.len() > LEGEND_TOP {
                let rest: i64 = c.types[LEGEND_TOP..].iter().map(|(_, n)| *n).sum();
                row = row.child(div().class("chip chip-sm idle").child(format!(
                    "还有 {} 类（合计 {}）",
                    c.types.len() - LEGEND_TOP,
                    rest
                )));
            }
        }
    }

    let mut stack = div().class("stack-sm").child(row);
    if selected.is_none() && c.types.len() > LEGEND_TOP {
        stack = stack.child(div().class("t-caption t-dim").child(format!(
            "图例只列前 {} 类（共 {} 类）；条形包含全部类型，颜色一一对应",
            LEGEND_TOP,
            c.types.len()
        )));
    }
    if selected.is_none() && c.types.len() > MAX_BAR_SEGMENTS {
        stack = stack.child(div().class("t-caption unknown").child(format!(
            "条形最多 {} 段：末尾 {} 类已合并为「其他类型」（计数未丢）",
            MAX_BAR_SEGMENTS,
            c.types.len() - (MAX_BAR_SEGMENTS - 1)
        )));
    }
    stack
}

fn legend_chip(
    name: String,
    count: i64,
    total: i64,
    color: Option<usize>,
    selected: bool,
    click_type: Option<String>,
    cx: &mut Context<AppRoot>,
) -> Div {
    // `.chip` 定义在 `.on` 之后，单用 `.on` 会被 `.chip` 的背景盖掉；
    // 选中态用 `.chip.accent`（复合选择器，且定义在 `.chip` 之后）。
    let mut chip_div = div().class(if selected {
        "chip chip-sm accent"
    } else {
        "chip chip-sm"
    });
    chip_div = match color {
        Some(i) => chip_div.child(div().class(format!("swatch s{}", i + 1))),
        None => chip_div.child(
            div()
                .class("swatch")
                .class("neutral-fill"),
        ),
    };
    chip_div = chip_div
        .child(format!("{name} {count} · {}", pct_label(count, total)))
        .title(format!("点按只看「{name}」的构成"));
    if let Some(t) = click_type {
        chip_div = chip_div.on_click(cx.listener(move |this, _, _, cx| {
            let next = if this.state.ui.dashboard.commit_type.as_deref() == Some(t.as_str()) {
                None
            } else {
                Some(t.clone())
            };
            this.state.apply(AppAction::SetDashboardCommitType(next));
            cx.notify();
        }));
    }
    chip_div
}

fn neutral_legend_chip(name: String, count: i64, total: i64) -> Div {
    div()
        .class("chip chip-sm idle")
        .child(
            div()
                .class("swatch")
                .class("neutral-fill"),
        )
        .child(format!("{name} {count} · {}", pct_label(count, total)))
        .title("聚合段：不是单一类型")
}

fn composition_disclosures(c: &Composition) -> Div {
    let mut stack = div().class("stack-sm").id("dash-composition-disclosures");

    stack = stack.child(div().class("t-caption t-dim").child(format!(
        "样本：窗口内 {} 个项目，其中可读 {} 个；类型计数之和不是仓库提交总数。",
        c.window_projects, c.sample_projects
    )));

    if c.truncated > 0 {
        stack = stack.child(
            div()
                .class("banner warn")
                .child(div().class("banner-body").child(format!(
                    "{} 个项目的提交类型样本被截断：上面的计数是下界，不是全量。",
                    c.truncated
                ))),
        );
    }
    if c.undisclosed > 0 {
        stack = stack.child(div().class("t-caption unknown").child(format!(
            "{} 个项目没披露样本是否被截断（缺 commitTypesTruncated 键）——不当作「没截断」。",
            c.undisclosed
        )));
    }
    if c.unreadable > 0 {
        stack = stack.child(div().class("t-caption err").child(format!(
            "{} 个项目读不出来，未计入样本（不是 0 次提交）。",
            c.unreadable
        )));
    }
    if c.empty_types > 0 {
        stack = stack.child(div().class("t-caption t-dim").child(format!(
            "{} 个可读项目没有提交类型数据（可能是非 git 仓库或还没有提交）。",
            c.empty_types
        )));
    }
    if c.unknown_time > 0 {
        stack = stack.child(div().class("t-caption unknown").child(format!(
            "{} 个项目最近提交时间读不出来：已保留并计入样本（无法判定是否在时间窗内）。",
            c.unknown_time
        )));
    }
    if c.window_projects > 0
        && c.truncated == 0
        && c.undisclosed == 0
        && c.unreadable == 0
        && c.empty_types == 0
        && c.unknown_time == 0
    {
        stack = stack.child(div().class("t-caption ok").child(format!(
            "样本完整：全部 {} 个项目都可读，引擎未报告截断。",
            c.sample_projects
        )));
    }
    stack
}

// ══════════════════════════════════════════════════════════════════════
// 项目磁贴
// ══════════════════════════════════════════════════════════════════════

fn render_projects(
    state: &AppState,
    summary: &Summary,
    projects: &[Project],
    global_types: &[(String, i64)],
    cx: &mut Context<AppRoot>,
) -> Div {
    let range = state.ui.dashboard.range;
    let mut visible: Vec<&Project> = Vec::new();
    let mut hidden = 0usize;
    let mut unknown_time = 0usize;
    for p in projects {
        match window_gate(p, range) {
            WindowGate::Out => hidden += 1,
            WindowGate::Unknown => {
                visible.push(p);
                // 采集失败的项目已经在卡上写「读不出来」；这里只统计
                // 「本来可读、只是时间读不出来」的项目，避免同一句话两种计数。
                if p.error.is_none() {
                    unknown_time += 1;
                }
            }
            WindowGate::In => visible.push(p),
        }
    }

    let mut head = div().class("row-between").id("dash-projects-head").child(
        div()
            .class("row-sm")
            .child(div().class("t-h3").child("项目磁贴"))
            .child(chip(range.label().to_string(), Tone::Idle))
            .child(div().class("t-caption t-dim").child(format!(
                "显示 {} / {} 个",
                visible.len(),
                projects.len()
            ))),
    );
    let mut notes = div().class("row-sm");
    if hidden > 0 {
        notes = notes.child(
            div()
                .class("t-caption t-dim")
                .child(format!("已隐藏 {} 个不在时间窗内的项目", hidden)),
        );
    }
    if unknown_time > 0 {
        notes = notes.child(chip(
            format!("时间读不出来 {unknown_time}（已保留）"),
            Tone::Unknown,
        ));
    }
    if state.ui.dashboard.commit_type.is_some() {
        notes = notes.child(
            div()
                .class("t-caption t-dim")
                .child("类型筛选不作用于项目磁贴"),
        );
    }
    // 两个数字来自同一份引擎输出，正常情况下应当相等。不相等就是契约漂移：
    // 说清「KPI 用 summary、卡片用明细」，而不是让读者自己猜该信哪个。
    if summary.listed_projects.max(0) as usize != projects.len() {
        notes = notes.child(chip(
            format!(
                "summary 在册 {} ≠ 明细 {}（KPI 用 summary，卡片用明细）",
                summary.listed_projects,
                projects.len()
            ),
            Tone::Warn,
        ));
    }
    head = head.child(notes);

    let mut out = div().class("stack").child(head);

    if projects.is_empty() {
        if summary.listed_projects > 0 {
            // 引擎说在册 N 个，却没有任何明细：结构异常 = 读不出来，不是空。
            out = out.child(empty_block(
                "!",
                "项目明细读不出来",
                format!(
                    "引擎报告 {} 个项目在册，但没有返回任何项目明细 —— 这不是「还没有注册项目」。",
                    summary.listed_projects
                ),
                vec![retry_btn("dash-projects-retry", cx)],
            ));
        } else if summary_blank(summary) {
            // 连 summary 的计数键都没有：无法判断是「没有项目」还是「读不出来」。
            out = out.child(empty_block(
                "!",
                "项目群状态不完整",
                "引擎既没有给出项目明细，也没有给出 summary 计数键 —— 无法判断是没有项目，还是这一次读取失败了。"
                    .to_string(),
                vec![retry_btn("dash-projects-retry-incomplete", cx)],
            ));
        } else {
            out = out.child(empty_block(
                "＋",
                "还没有注册项目",
                "仪表盘的 KPI 与提交构成需要至少一个项目。先扫描目录或手动添加。".to_string(),
                vec![
                    nav_btn("扫描目录", "dash-empty-scan", Route::Scan, cx),
                    nav_btn("添加项目", "dash-empty-add", Route::Scan, cx),
                ],
            ));
        }
        return out;
    }

    if visible.is_empty() {
        // 有项目、但被时间窗筛掉：与「没有项目」严格分开。
        out = out.child(empty_block(
            "▤",
            "当前筛选没有项目",
            format!(
                "时间窗「{}」隐藏了 {} 个项目；项目卡与提交构成样本都不含它们（KPI 仍是全量）。",
                range.label(),
                hidden
            ),
            vec![clear_filters_btn("dash-projects-clear", cx)],
        ));
        return out;
    }

    let mut grid = div().class("tiles").id("dash-project-tiles");
    for p in visible {
        // `.tiles` 是 12 列栅格：卡片本身没有 `span-*` 时只占 1 列（约 80px）。
        // 与骨架屏同宽（`.tile.span-4`），并在窄屏由 `.span-4 → span 6` 兜住。
        grid = grid.child(
            div()
                .class("tile span-4")
                .child(render_project_card(p, global_types, cx)),
        );
    }
    out.child(grid)
}

fn render_project_card(
    p: &Project,
    global_types: &[(String, i64)],
    cx: &mut Context<AppRoot>,
) -> Div {
    let name = if p.name.trim().is_empty() {
        "(未命名)".to_string()
    } else {
        p.name.clone()
    };
    let route_name = p.name.clone();
    let tone = models::status_tone(p);

    let head = div()
        .class("card-head")
        .child(div().class(format!("dot {}", tone.class())))
        .child(
            div()
                .class("card-title t-ellipsis")
                .title(name.clone())
                .child(name.clone()),
        )
        .child(branch_chip(p))
        .child(div().class("spacer"))
        .child(chip(models::status_word(p).to_string(), tone));

    let mut card = div()
        .class("card hoverable")
        .id(format!("dash-card-{}", p.name))
        .child(head)
        .child(render_headline(p))
        .child(render_project_facts(p));

    // 引擎的 warnings 是**用户必须看到**的事实（例如「非 git 仓库：进度基于
    // 文件活动时间，不含提交历史」）。数据里有不等于用户看得到。
    if let Some(ws) = &p.warnings {
        if !ws.is_empty() {
            let mut block = div().class("stack-sm").id(format!("dash-warn-{}", p.name));
            for line in ws.iter().take(2) {
                block = block.child(
                    div()
                        .class("t-caption warn t-clamp-2")
                        .title(line.clone())
                        .child(line.clone()),
                );
            }
            if ws.len() > 2 {
                block = block.child(
                    div()
                        .class("t-caption t-dim")
                        .child(format!("还有 {} 条引擎告警", ws.len() - 2)),
                );
            }
            card = card.child(block);
        }
    }

    card = card.child(recent_commit_line(p));

    // 项目级类型构成：与全局汇总同色（同一个类型在哪儿都是一个颜色）。
    card = card.child(render_project_types(p, global_types));

    card = card.child(
        div()
            .class("card-foot")
            .child(repo_branch_label(p))
            .child(div().class("spacer"))
            .child(
                div()
                    .class("t-caption t-accent")
                    .child("进入 →")
                    .title("打开项目概览"),
            ),
    );

    // 整卡可点：hover 抬升由 `.card.hoverable` 提供，按下态由按钮/分段控件承担。
    card.on_click(cx.listener(move |this, _, _, cx| {
        this.state.select(Route::Project(route_name.clone()));
        cx.notify();
    }))
}

fn render_headline(p: &Project) -> Div {
    if let Some(err) = &p.error {
        return div()
            .class("banner err")
            .child(div().class("banner-title").child("读不出来"))
            .child(
                div()
                    .class("banner-body t-clamp-2")
                    .title(err.clone())
                    .child(err.clone()),
            );
    }
    match &p.headline {
        Some(h) if !h.trim().is_empty() => div()
            .class("t-meta muted t-clamp-2")
            .title(h.clone())
            .child(h.clone()),
        _ => div().class("t-caption t-dim").child("暂无摘要"),
    }
}

fn render_project_facts(p: &Project) -> Div {
    let mut row = div().class("row-wrap");

    if p.error.is_some() {
        // 采集失败：所有计数由引擎写成 -1。不渲染 0，逐项说「读不出来」。
        row = row
            .child(chip("脏度读不出来".to_string(), Tone::Unknown))
            .child(chip("未跟踪读不出来".to_string(), Tone::Unknown))
            .child(chip("stash 读不出来".to_string(), Tone::Unknown));
    } else {
        let dirty = p.dirty_state();
        let untracked = if p.untracked_error.trim().is_empty() {
            models::read_opt_i64(p.untracked_count)
        } else {
            Reading::NotRead
        };
        let stash = models::read_opt_i64(p.stash_count);

        // 先按引用判「干净」，避免把 Reading 移走后再 match。
        let clean = match (&dirty, &untracked, &stash) {
            (Reading::Known(d), Reading::Known(0), Reading::Known(0)) => d.total == 0,
            _ => false,
        };
        if clean {
            row = row.child(chip("工作区干净".to_string(), Tone::Ok));
        } else {
            match dirty {
                Reading::Known(d) => {
                    let tone = if d.total > 0 { Tone::Warn } else { Tone::Idle };
                    let mut c = chip(format!("未提交 {}", d.total), tone);
                    if let Some(err) = &d.err {
                        c = c.title(format!("git status 部分失败：{err}"));
                    }
                    row = row.child(c);
                }
                Reading::NotRead => {
                    let mut c = chip("脏度读不出来".to_string(), Tone::Unknown);
                    if let Some(err) = p.dirty.as_ref().and_then(|d| d.err.clone()) {
                        c = c.title(err);
                    }
                    row = row.child(c);
                }
            }

            match untracked {
                Reading::Known(0) => {}
                Reading::Known(n) => {
                    row = row.child(chip(format!("未跟踪 {n}"), Tone::Warn));
                }
                Reading::NotRead => {
                    let mut c = chip("未跟踪读不出来".to_string(), Tone::Unknown);
                    if !p.untracked_error.trim().is_empty() {
                        c = c.title(p.untracked_error.clone());
                    }
                    row = row.child(c);
                }
            }

            match stash {
                Reading::Known(0) => {}
                Reading::Known(n) => {
                    row = row.child(chip(format!("stash {n}"), Tone::Info));
                }
                Reading::NotRead => {
                    row = row.child(chip("stash 读不出来".to_string(), Tone::Unknown));
                }
            }
        }
    }

    if p.store_health != "" && p.store_health != "ok" {
        row = row.child(chip(format!("进度库降级：{}", p.store_health), Tone::Err));
    }
    // 「非 git」由分支 chip 与引擎 warnings 两处表达，这里不再叠第三遍。

    row
}

fn branch_chip(p: &Project) -> Div {
    if p.error.is_some() {
        return chip("分支读不出来".to_string(), Tone::Unknown);
    }
    if !p.is_git() {
        // 非 git 项目没有分支概念；说「读不出来」会被误读成采集故障。
        return chip("非 git（无分支）".to_string(), Tone::Info);
    }
    match p.current_branch.as_deref().map(str::trim) {
        Some(b) if !b.is_empty() => chip(format!("⎇ {b}"), Tone::Info),
        _ => chip("分支读不出来".to_string(), Tone::Unknown),
    }
}

fn repo_branch_label(p: &Project) -> Div {
    match p.repo_branch_count {
        Some(n) if n >= 0 => div()
            .class("t-caption t-dim")
            .child(format!("仓库分支 {n}")),
        Some(_) => div().class("t-caption unknown").child("仓库分支数读不出来"),
        None => div().class("t-caption t-dim").child("仓库分支数未披露"),
    }
}

fn recent_commit_line(p: &Project) -> Div {
    match time_basis(p) {
        TimeBasis::Exact(days) => {
            let ago = p
                .last_commit_ago
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .unwrap_or_else(|| format!("{days} 天前"));
            let at = models::short_iso(&p.last_commit_at);
            let class = if days > 30 {
                "t-caption stale"
            } else {
                "t-caption t-dim"
            };
            div()
                .class(class)
                .child(format!("最近提交 {ago} · {at}"))
                .title(format!("lastCommitAt = {}", p.last_commit_at))
        }
        TimeBasis::Approx(days) => {
            let ago = p
                .last_commit_ago
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .unwrap_or_else(|| format!("{days} 天前"));
            div()
                .class("t-caption unknown")
                .child(format!("最近提交 {ago}（日期读不出来，按相对时间）"))
                .title("lastCommitAt 解析失败，时间窗按 lastCommitAgo 判定")
        }
        TimeBasis::Unknown => div()
            .class("t-caption unknown")
            .child("最近提交读不出来")
            .title("lastCommitAt 与 lastCommitAgo 都读不出来；时间窗不会把它筛掉"),
    }
}

fn render_project_types(p: &Project, global_types: &[(String, i64)]) -> Div {
    let block = div().class("stack-sm");

    if p.error.is_some() {
        return block.child(
            div()
                .class("t-caption unknown")
                .child("提交构成读不出来（项目采集失败）"),
        );
    }

    let types = project_types(p);
    if types.is_empty() {
        return block.child(
            div()
                .class("t-caption t-dim")
                .child("无提交类型数据（非 git 或没有提交）"),
        );
    }

    let total: i64 = types.iter().map(|(_, n)| *n).sum();
    let top: Vec<(String, i64)> = types.iter().take(3).cloned().collect();
    let rest = total - top.iter().map(|(_, n)| *n).sum::<i64>();

    let mut bar = div().class("stackbar");
    for (name, count) in &top {
        let idx = type_color_index(name, global_types).unwrap_or(0);
        bar = bar.child(
            div()
                .class(format!("stack-seg s{}", idx + 1))
                .style(format!("width: {:.2}%;", pct(*count, total)))
                .title(format!("{name}：{count} 次")),
        );
    }
    if rest > 0 {
        bar = bar.child(
            div()
                .class("stack-seg")
                .style(format!(
                    "width: {:.2}%; background: rgba(255,255,255,.16);",
                    pct(rest, total)
                ))
                .title(format!(
                    "其余 {} 类：合计 {} 次",
                    types.len() - top.len(),
                    rest
                )),
        );
    }

    let mut legend = top
        .iter()
        .map(|(name, count)| format!("{name} {count}"))
        .collect::<Vec<_>>()
        .join(" · ");
    if rest > 0 {
        legend.push_str(&format!(
            " · 还有 {} 类（合计 {}）",
            types.len() - top.len(),
            rest
        ));
    }

    let (legend_class, sample_note) = match p.commit_types_truncated {
        Some(true) => ("t-caption warn", " · 样本截断（计数是下界）".to_string()),
        None => ("t-caption unknown", " · 样本完整性未披露".to_string()),
        Some(false) => ("t-caption t-dim", String::new()),
    };

    block
        .child(
            div()
                .class("row-between")
                .child(div().class("t-caption t-dim").child("提交构成"))
                .child(
                    div()
                        .class("t-caption t-dim")
                        .child(format!("合计 {total}")),
                ),
        )
        .child(bar)
        .child(
            div()
                .class(legend_class)
                .child(format!("{legend}{sample_note}")),
        )
}

// ══════════════════════════════════════════════════════════════════════
// 未加载 / 读不出来
// ══════════════════════════════════════════════════════════════════════

fn render_no_status(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    if state.loading {
        return skeleton_grid();
    }

    // 读不出来：原因优先用引擎给的，其次明确说「引擎没给原因」。
    let reason = state
        .error
        .clone()
        .or_else(|| state.startup_error.as_ref().map(|e| e.user_message()))
        .unwrap_or_else(|| "引擎没有给出原因".to_string());
    if state.error.is_some() || state.startup_error.is_some() {
        return div().class("stack").child(empty_block(
            "!",
            "项目群状态读不出来",
            format!(
                "这不是「没有项目」：状态命令失败了（{reason}）。修复后重新读取；失败原因不会被渲染成 0。"
            ),
            vec![retry_btn("dash-retry", cx)],
        ));
    }

    empty_block(
        "◌",
        "还没有读取项目群状态",
        "本页需要先跑一次 status。点「重新读取」或稍候自动加载。".to_string(),
        vec![retry_btn("dash-retry-idle", cx)],
    )
}

fn skeleton_grid() -> Div {
    let mut out = div().class("stack");
    let mut kpis = div().class("tiles");
    for _ in 0..4 {
        kpis = kpis.child(
            div().class("tile span-3").child(
                div()
                    .class("kpi")
                    .child(div().class("skeleton skeleton-line"))
                    .child(div().class("skeleton skeleton-line"))
                    .child(div().class("skeleton skeleton-line")),
            ),
        );
    }
    out = out.child(kpis);
    let mut cards = div().class("tiles");
    for _ in 0..3 {
        cards = cards.child(
            div().class("tile span-4").child(
                div()
                    .class("card")
                    .child(div().class("skeleton skeleton-line"))
                    .child(div().class("skeleton skeleton-line"))
                    .child(div().class("skeleton skeleton-line"))
                    .child(div().class("skeleton skeleton-line")),
            ),
        );
    }
    out.child(cards)
}

// ══════════════════════════════════════════════════════════════════════
// 小件
// ══════════════════════════════════════════════════════════════════════

fn range_key(range: RangeFilter) -> &'static str {
    match range {
        RangeFilter::All => "all",
        RangeFilter::D30 => "30",
        RangeFilter::D7 => "7",
    }
}

fn chip(text: String, tone: Tone) -> Div {
    div()
        .class(format!("chip chip-sm {}", tone.class()))
        .child(text)
}

/// summary 是不是「缺键兜底出来的全 0」。
/// 引擎只要真的跑过，就会写 `generatedAt`；全 0 且没有时间戳 ⇒ 键没到，
/// 这时把 0 画成 KPI 就是在说「项目群是空的」。
fn summary_blank(s: &Summary) -> bool {
    s.project_count == 0
        && s.listed_projects == 0
        && s.failed_projects == 0
        && s.degraded_stores == 0
        && s.dirty_projects == 0
        && s.active_projects == 0
        && s.stale_projects == 0
        && s.branch_count == 0
        && s.repo_branch_total == 0
        && s.branch_truncated_projects == 0
        && s.branch_unknown_projects == 0
        && s.generated_at.trim().is_empty()
}

fn empty_block(icon: &str, title: &str, body: String, actions: Vec<Div>) -> Div {
    let mut block = div()
        .class("empty")
        .child(div().class("empty-icon").child(icon.to_string()))
        .child(div().class("empty-title").child(title.to_string()))
        .child(div().class("empty-body").child(body));
    if !actions.is_empty() {
        let mut row = div().class("row-sm");
        for a in actions {
            row = row.child(a);
        }
        block = block.child(row);
    }
    block
}

fn nav_btn(label: &str, id: &str, route: Route, cx: &mut Context<AppRoot>) -> Div {
    div()
        .class("btn btn-sm btn-accent")
        .id(id.to_string())
        .child(label.to_string())
        .on_click(cx.listener(move |this, _, _, cx| {
            this.state.select(route.clone());
            cx.notify();
        }))
}

fn retry_btn(id: &str, cx: &mut Context<AppRoot>) -> Div {
    div()
        .class("btn btn-sm btn-accent")
        .id(id.to_string())
        .child("重新读取")
        .on_click(cx.listener(|this, _, _, cx| {
            this.state
                .dispatch(Action::App(AppAction::Refresh(RefreshScope::All)));
            cx.notify();
        }))
}

fn clear_filters_btn(id: &str, cx: &mut Context<AppRoot>) -> Div {
    div()
        .class("btn btn-sm btn-ghost")
        .id(id.to_string())
        .child("清除筛选")
        .on_click(cx.listener(|this, _, _, cx| {
            this.state
                .apply(AppAction::SetDashboardRange(RangeFilter::All));
            this.state.apply(AppAction::SetDashboardCommitType(None));
            cx.notify();
        }))
}

// ══════════════════════════════════════════════════════════════════════
// 单测（纯判定；不构造 UI）
// ══════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::CommitTypeCount;

    fn project(name: &str, types: &[(&str, i64)], truncated: Option<bool>) -> Project {
        Project {
            name: name.to_string(),
            last_commit_at: "2026-11-01T00:00:00+08:00".to_string(),
            commit_types: types
                .iter()
                .map(|(t, n)| CommitTypeCount {
                    type_: t.to_string(),
                    count: *n,
                })
                .collect(),
            commit_types_truncated: truncated,
            ..Default::default()
        }
    }

    #[test]
    fn ago_days_reads_chinese_and_english_units() {
        assert_eq!(ago_days("刚刚"), Some(0));
        assert_eq!(ago_days("just now"), Some(0));
        assert_eq!(ago_days("3 分钟前"), Some(0));
        assert_eq!(ago_days("5 小时前"), Some(0));
        assert_eq!(ago_days("3 天前"), Some(3));
        assert_eq!(ago_days("2 个月前"), Some(60));
        assert_eq!(ago_days("1 年前"), Some(365));
        assert_eq!(ago_days("12m ago"), Some(0));
        assert_eq!(ago_days("3h ago"), Some(0));
        assert_eq!(ago_days("4d ago"), Some(4));
        assert_eq!(ago_days("2mo ago"), Some(60));
        assert_eq!(ago_days("1y ago"), Some(365));
    }

    #[test]
    fn unreadable_ago_is_not_zero_days() {
        assert_eq!(ago_days(""), None);
        assert_eq!(ago_days("-"), None);
        // 未来时间戳（>1 天）是时间异常，不能当「刚刚」。
        assert_eq!(ago_days("⚠ 时间异常（晚于当前 3 天）"), None);
        assert_eq!(ago_days("⚠ clock skew: 3d in the future"), None);
        assert_eq!(ago_days("很久以前"), None);
    }

    #[test]
    fn window_keeps_projects_with_unreadable_time() {
        let old = Project {
            last_commit_at: "2000-01-01T00:00:00+08:00".to_string(),
            ..Default::default()
        };
        assert_eq!(window_gate(&old, RangeFilter::D30), WindowGate::Out);
        assert_eq!(window_gate(&old, RangeFilter::D7), WindowGate::Out);
        assert_eq!(window_gate(&old, RangeFilter::All), WindowGate::In);

        let approx = Project {
            last_commit_at: String::new(),
            last_commit_ago: Some("3 天前".to_string()),
            ..Default::default()
        };
        assert_eq!(window_gate(&approx, RangeFilter::D7), WindowGate::In);
        assert_eq!(window_gate(&approx, RangeFilter::D30), WindowGate::In);

        let unknown = Project {
            last_commit_at: String::new(),
            last_commit_ago: None,
            ..Default::default()
        };
        // 读不出来：保留（Unknown），不是 Out。
        assert_eq!(window_gate(&unknown, RangeFilter::D7), WindowGate::Unknown);
    }

    #[test]
    fn composition_separates_unreadable_empty_and_truncated() {
        let a = project("a", &[("feat", 2), ("fix", 1)], Some(false));
        let b = project("b", &[], None); // 可读但没有类型数据
        let c = project("c", &[("feat", 3)], Some(true));
        let d = Project {
            name: "d".to_string(),
            error: Some("读不出来".to_string()),
            ..Default::default()
        };
        let projects = vec![a, b, c, d];

        let got = composition(&projects, RangeFilter::All);
        assert_eq!(
            got.types,
            vec![("feat".to_string(), 5), ("fix".to_string(), 1)]
        );
        assert_eq!(got.total, 6);
        assert_eq!(got.window_projects, 4);
        assert_eq!(got.sample_projects, 3);
        assert_eq!(got.unreadable, 1);
        assert_eq!(got.empty_types, 1);
        assert_eq!(got.truncated, 1);
        assert_eq!(got.undisclosed, 0);
        assert_eq!(got.unknown_time, 0);
    }

    #[test]
    fn undisclosed_truncation_is_not_treated_as_complete() {
        let a = project("a", &[("feat", 1)], None);
        let got = composition(&[a], RangeFilter::All);
        assert_eq!(got.undisclosed, 1);
        assert_eq!(got.truncated, 0);
    }

    #[test]
    fn selected_type_splits_into_selected_and_rest() {
        let a = project("a", &[("feat", 3), ("fix", 1)], Some(false));
        let got = composition(&[a], RangeFilter::All);
        assert_eq!(
            composition_segments(&got, Some("feat")),
            vec![("feat".to_string(), 3), ("其他类型".to_string(), 1)]
        );
        // 选中类型在样本里为 0：不画「全部是其他」的假条。
        assert!(composition_segments(&got, Some("docs")).is_empty());
    }

    #[test]
    fn all_type_totals_ignores_failed_projects() {
        let a = project("a", &[("feat", 2)], Some(false));
        let b = Project {
            name: "b".to_string(),
            error: Some("x".to_string()),
            commit_types: vec![CommitTypeCount {
                type_: "feat".to_string(),
                count: 9,
            }],
            ..Default::default()
        };
        assert_eq!(all_type_totals(&[a, b]), vec![("feat".to_string(), 2)]);
    }
}
