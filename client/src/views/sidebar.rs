// sidebar.rs — 侧栏 v2：品牌 / 搜索 / 视图导航 / 仓库列表 / 引擎状态脚。
//
// 【数据口径（只读，全部来自 AppState 的既有字段）】
//   · 项目集合 = `state.projects()`（status 的只读镜像）。status 读不出来时
//     渲染「读不出来」+ 重试，绝不渲染成「还没有项目」。
//   · 计数只有一个来源：仪表盘计数取 dashboard.projects.listed（没有就退回
//     status.summary.listedProjects）；看板计数取 `models::pending_count`
//     （与看板列、仪表盘 KPI 同源）；里程碑取 dashboard.milestones.counts.open。
//     不让侧栏自己从里程碑数组重算——那会造出第二套口径。
//   · 脏度以 `Project::dirty_state()`（结构化 dirty.total）为准。**不要**
//     用 `userDirtyCount` 代替：实测同一项目 `dirty.total=2` 而
//     `userDirtyCount=0`，两者不同义。`NotRead` 渲染成 `?`，不是 0。
//   · 搜索只匹配「项目名 + 分支名」（ASCII 不区分大小写），与 PLAN §9.1 一致。
//
// 【毛玻璃】整个侧栏只有 `.sidebar` 一个玻璃面（PLAN §4.3 的四面预算之一）。
// 这里**不再**给搜索框/页脚套 backdrop-filter：嵌套玻璃会踩 BUI 的
// 「每帧重采样、祖先 transform 断采样」两条边界。
//
// 【诚实边界】搜索、计数、状态点都不改状态；点击只发 `AppAction`。
// 侧栏不提供折叠：`SidebarUi.collapsed_*` 在 core 里没有对应动作，
// 视图不允许自己改状态，所以本版不画一个「点了没反应」的组头。

use crate::app::{AppAction, AppRoot, AppState, Lang, Load, ModalState, Route, SettingsTab};
use crate::models::{self, Project, Reading};
use blenderui::prelude::*;

pub fn render(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let query = state.ui.sidebar.search.trim().to_string();
    let all = state.projects();
    let filtered: Vec<&Project> = all
        .iter()
        .filter(|p| project_matches(p, &query))
        .collect();

    div()
        .class("sidebar glass")
        .child(brand())
        .child(search_box(state, &query, cx))
        .child(scroll(state, &query, &filtered, all.len(), cx))
        .child(foot(state, cx))
}

// ══════════════════════════════════════════════════════════════════════
// 品牌 / 搜索
// ══════════════════════════════════════════════════════════════════════

fn brand() -> Div {
    div()
        .class("sidebar-head")
        .child(div().class("sidebar-brand").child("deepDolphin"))
        .child(div().class("sidebar-brand-sub").child("moonGit · 项目群进度引擎"))
}

fn search_box(state: &AppState, query: &str, cx: &mut Context<AppRoot>) -> Div {
    let mut boxed = div()
        .class("search-box")
        .child(div().class("nav-icon").child("○"))
        .child(
            input()
                .class("search-input")
                // 稳定 id：否则每帧重建会丢焦点/光标（PLAN §1.2 第 13 条）。
                .id("sidebar-search")
                .placeholder("搜索项目名 / 分支名")
                .value(state.ui.sidebar.search.clone())
                .on_input(cx.listener(|this, e: &blenderui::ChangeEvent, _, cx| {
                    this.state
                        .apply(AppAction::SetSidebarSearch(e.value.clone()));
                    cx.notify();
                })),
        );
    if !query.is_empty() {
        boxed = boxed.child(
            div()
                .class("search-clear")
                .id("sidebar-search-clear")
                .child("×")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state
                        .apply(AppAction::SetSidebarSearch(String::new()));
                    cx.notify();
                })),
        );
    }
    div().class("search").child(boxed)
}

// ══════════════════════════════════════════════════════════════════════
// 滚动区：视图组 + 仓库组 + 添加入口
// ══════════════════════════════════════════════════════════════════════

fn scroll(
    state: &AppState,
    query: &str,
    filtered: &[&Project],
    total: usize,
    cx: &mut Context<AppRoot>,
) -> Div {
    let (listed, ms_open, ms_unknown) = view_counts(state);
    // 看板计数与看板列、仪表盘 KPI 用同一个纯函数；status 没读到就不显示数字。
    let pending = if state.status.is_some() {
        Some(models::pending_count(state.projects()) as i64)
    } else {
        None
    };

    let mut list = div().class("sidebar-scroll");
    list = list.child(sect("视图"));
    list = list.child(nav_view(
        state,
        "仪表盘",
        "◆",
        Route::Dashboard,
        listed,
        0,
        cx,
    ));
    list = list.child(nav_view(
        state,
        "看板",
        "■",
        Route::Board,
        pending,
        0,
        cx,
    ));
    list = list.child(nav_view(
        state,
        "里程碑",
        "★",
        Route::Milestones,
        ms_open,
        ms_unknown,
        cx,
    ));
    list = list.child(nav_view(
        state,
        "代码置信度",
        "◎",
        Route::Confidence,
        None,
        0,
        cx,
    ));
    list = list.child(nav_view(
        state,
        "补丁体检",
        "◇",
        Route::Patch,
        None,
        0,
        cx,
    ));
    list = list.child(nav_view(
        state,
        "AI 助手",
        "☆",
        Route::Agent,
        None,
        0,
        cx,
    ));

    list = list.child(repo_head(state, query, filtered, total));
    list = list.child(repo_body(state, query, filtered, cx));
    list = list.child(scan_entry(state, cx));
    list
}

/// 三处视图计数。`None` = 不可知（不渲染 0）。
fn view_counts(state: &AppState) -> (Option<i64>, Option<i64>, i64) {
    let listed = match &state.dashboard {
        Load::Ready(d) => Some(d.projects.listed),
        _ => state.status.as_ref().map(|s| s.summary.listed_projects),
    };
    let (open, unknown) = match &state.dashboard {
        Load::Ready(d) => (Some(d.milestones.counts.open), d.milestones.counts.unknown),
        _ => (None, 0),
    };
    (listed, open, unknown)
}

fn sect(label: &str) -> Div {
    div().class("sect-label").child(label.to_string())
}

fn nav_view(
    state: &AppState,
    label: &str,
    icon: &str,
    route: Route,
    count: Option<i64>,
    unknown: i64,
    cx: &mut Context<AppRoot>,
) -> Div {
    let on = state.route == route;
    let target = route.clone();
    let mut row = div()
        .class(if on { "nav-item on" } else { "nav-item" })
        .id(format!("nav-{}", route.key()))
        .on_click(cx.listener(move |this, _, _, cx| {
            this.state.apply(AppAction::Navigate(target.clone()));
            cx.notify();
        }))
        .child(div().class("nav-icon").child(icon.to_string()))
        .child(div().class("nav-label").child(label.to_string()));
    if let Some(n) = count {
        row = row.child(div().class("nav-badge").child(n.to_string()));
    }
    if unknown > 0 {
        // unknown 单列（PLAN §9.1）：它不是 open，也不是 done。
        row = row.child(div().class("dot unknown"));
    }
    row
}

/// 仓库组头：仓库计数 + 脏计数摘要。搜索时显示「匹配/总数」。
///
/// status 读不出来时计数显示 `?` —— 0 会读成「没有仓库」，那是另一件事。
fn repo_head(state: &AppState, query: &str, filtered: &[&Project], total: usize) -> Div {
    let known = state.status.is_some();
    let dirty = if known {
        filtered
            .iter()
            .filter(|p| matches!(dirty_reading(p), Reading::Known(n) if n > 0))
            .count()
    } else {
        0
    };
    let unknown = if known {
        filtered
            .iter()
            .filter(|p| p.is_git() && matches!(dirty_reading(p), Reading::NotRead))
            .count()
    } else {
        0
    };
    let count_text = if !known {
        "?".to_string()
    } else if query.is_empty() {
        total.to_string()
    } else {
        format!("{}/{}", filtered.len(), total)
    };

    let mut badges = div().class("row-sm").child(div().class(if known {
        "nav-badge"
    } else {
        "nav-badge unknown"
    })
    .child(count_text));
    if unknown > 0 {
        badges = badges.child(
            div()
                .class("nav-badge unknown")
                .child(format!("?{unknown}")),
        );
    }

    let mut wrap = div().class("stack-sm").child(
        div()
            .class("row-between")
            .child(sect("仓库"))
            .child(badges),
    );
    if known && (dirty > 0 || unknown > 0 || !query.is_empty()) {
        let mut parts: Vec<String> = Vec::new();
        if !query.is_empty() {
            parts.push(format!("匹配 {}/{}", filtered.len(), total));
        }
        if dirty > 0 {
            parts.push(format!("{dirty} 个待处理"));
        }
        if unknown > 0 {
            parts.push(format!("{unknown} 个脏度读不出来"));
        }
        wrap = wrap.child(div().class("t-caption dim").child(parts.join(" · ")));
    }
    if known && state.error.is_some() {
        // 列表是上次成功的数据：说清楚「陈旧」，别让读者把它当成当前事实。
        wrap = wrap.child(
            div()
                .class("t-caption warn")
                .child("上次刷新失败：下面是上次成功读取的列表"),
        );
    }
    wrap
}

/// 仓库列表本体：三种「空」分开——读不出来 / 真的没有 / 搜索无匹配。
fn repo_body(
    state: &AppState,
    query: &str,
    filtered: &[&Project],
    cx: &mut Context<AppRoot>,
) -> Div {
    if state.status.is_none() {
        return status_missing(state, cx);
    }
    if state.projects().is_empty() {
        return no_projects(cx);
    }
    if filtered.is_empty() {
        return div()
            .class("empty")
            .child(div().class("empty-icon").child("○"))
            .child(div().class("empty-title").child("无匹配项目"))
            .child(
                div()
                    .class("empty-body")
                    .child("搜索只匹配项目名与分支名（ASCII 不区分大小写）"),
            )
            .child(
                div()
                    .class("row")
                    .child(
                        div()
                            .class("btn btn-sm btn-ghost")
                            .child("清除搜索")
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.state
                                    .apply(AppAction::SetSidebarSearch(String::new()));
                                cx.notify();
                            })),
                    ),
            );
    }

    let mut list = div().class("sidebar-group");
    for p in filtered {
        list = list.child(project_row(state, p, query, cx));
    }
    list
}

/// status 还没读到：区分「正在读」与「读不出来」。
fn status_missing(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    if state.loading {
        let mut boxed = div().class("stack-sm");
        for _ in 0..4 {
            boxed = boxed.child(div().class("skeleton skeleton-line"));
        }
        return boxed;
    }
    let mut banner = div()
        .class("banner err")
        .child(div().class("banner-title").child("项目列表读不出来"))
        .child(div().class("banner-body").child(match &state.error {
            Some(e) => e.clone(),
            None => "status 尚未返回，且没有给出原因".to_string(),
        }))
        .child(div().class("banner-body").child(
            "这是「没读到」，不是「没有项目」；重试不会丢任何数据。",
        ));
    banner = banner.child(
        div().class("banner-action").child(
            div()
                .class("btn btn-sm btn-accent")
                .child("重试")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state
                        .apply(AppAction::Refresh(crate::app::RefreshScope::All));
                    cx.notify();
                })),
        ),
    );
    banner
}

fn no_projects(cx: &mut Context<AppRoot>) -> Div {
    div()
        .class("empty")
        .child(div().class("empty-icon").child("◇"))
        .child(div().class("empty-title").child("还没有项目"))
        .child(
            div()
                .class("empty-body")
                .child("注册一个已有仓库，或扫描目录自动发现项目。"),
        )
        .child(
            div()
                .class("row")
                .child(
                    div()
                        .class("btn btn-sm btn-accent")
                        .child("扫描目录")
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.state.apply(AppAction::Navigate(Route::Scan));
                            cx.notify();
                        })),
                )
                .child(
                    div()
                        .class("btn btn-sm btn-ghost")
                        .child("添加项目")
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.state.apply(AppAction::Navigate(Route::Scan));
                            cx.notify();
                        })),
                ),
        )
}

fn project_row(
    state: &AppState,
    p: &Project,
    query: &str,
    cx: &mut Context<AppRoot>,
) -> Div {
    let on = state.route.project_name() == Some(p.name.as_str());
    let tone = models::status_tone(p);
    let dirty = dirty_reading(p);
    let word = row_word(p, &dirty);
    let sub = if let Some(err) = &p.error {
        format!("读不出来：{}", shorten(err, 40))
    } else if !p.is_git() {
        format!("非 git 仓库 · {word}")
    } else if let Some(b) = display_branch(p, query) {
        format!("分支 {b} · {word}")
    } else {
        format!("分支读不出来 · {word}")
    };
    let error = p.error.is_some();

    let name = p.name.clone();
    let mut row = div()
        .class(if on { "nav-item on" } else { "nav-item" })
        .id(format!("proj-{}", p.name))
        .on_click(cx.listener(move |this, _, _, cx| {
            this.state
                .apply(AppAction::Navigate(Route::Project(name.clone())));
            cx.notify();
        }))
        .child(div().class(format!("dot {}", tone.class())))
        .child(
            div()
                .class("nav-label")
                .child(div().class("t-ellipsis").child(p.name.clone()))
                .child(
                    div()
                        .class(if error {
                            "t-caption err t-ellipsis"
                        } else {
                            "t-caption dim t-ellipsis"
                        })
                        .child(sub),
                ),
        );

    match dirty {
        Reading::Known(n) if n > 0 => {
            row = row.child(div().class("nav-badge-warn").child(format!("●{n}")))
        }
        // 只对 git 项目渲染 `?`：非 git 仓库没有「结构化脏度」这个概念。
        Reading::NotRead if p.is_git() => {
            row = row.child(div().class("nav-badge unknown").child("?"))
        }
        _ => {}
    }
    row
}

fn scan_entry(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let on = state.route == Route::Scan;
    div()
        .class(if on { "nav-item on" } else { "nav-item" })
        .id("nav-scan")
        .on_click(cx.listener(|this, _, _, cx| {
            this.state.apply(AppAction::Navigate(Route::Scan));
            cx.notify();
        }))
        .child(div().class("nav-icon").child("+"))
        .child(div().class("nav-label").child("添加 / 扫描项目"))
}

// ══════════════════════════════════════════════════════════════════════
// 页脚：引擎状态 / 告警 / 语言 / 设置
// ══════════════════════════════════════════════════════════════════════

fn foot(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let (tone, text) = if state.startup_error.is_some() {
        ("err", "引擎不可用")
    } else if state.loading {
        ("idle", "正在刷新…")
    } else if state.last_refresh_failed {
        ("err", "上次刷新失败")
    } else if state.status.is_none() {
        ("idle", "尚未刷新")
    } else {
        ("ok", "空闲")
    };

    let mut status = div()
        .class("sidebar-status")
        .child(div().class(format!("dot {tone}")))
        .child(div().child(text.to_string()));
    if !state.engine_warnings.is_empty() {
        status = status
            .child(div().class("spacer"))
            .child(
                div()
                    .class("btn btn-sm btn-ghost")
                    .id("sidebar-warnings")
                    .child(format!("告警 {}", state.engine_warnings.len()))
                    .on_click(cx.listener(|this, _, _, cx| {
                        // 读命令 stderr 的告警不是失败：单独成文，不塞进 feedback。
                        let body = this.state.engine_warnings.join("\n");
                        this.state.modal = Some(ModalState::Text {
                            title: "引擎告警（不是失败）".to_string(),
                            body: if body.is_empty() {
                                "告警缓冲已经空了".to_string()
                            } else {
                                format!(
                                    "这些是读命令 stderr 的告警，命令本身成功。\n\n{body}"
                                )
                            },
                        });
                        cx.notify();
                    })),
            );
    }

    let refresh_line = match state.last_refresh {
        Some(t) => format!("上次刷新：{}", models::human_ago(t)),
        None => "尚未刷新".to_string(),
    };

    let mut foot = div()
        .class("sidebar-foot")
        .child(status)
        .child(div().class("sidebar-status").child(refresh_line))
        .child(
            div()
                .class("sidebar-status")
                .child(format!("引擎：{}", state.engine_short())),
        );

    if let Some(line) = state
        .error
        .clone()
        .or_else(|| state.startup_error.as_ref().map(|e| e.user_message()))
    {
        // stderr/错误原文可能很长：一行截断，完整内容仍在顶部反馈条/诊断里。
        foot = foot.child(div().class("sidebar-status err").child(shorten(&line, 46)));
    }

    foot.child(language_row(state, cx)).child(
        div()
            .class("btn btn-ghost btn-sm btn-block")
            .id("sidebar-settings")
            .child("设置")
            .on_click(cx.listener(|this, _, _, cx| {
                this.state
                    .apply(AppAction::Navigate(Route::Settings(SettingsTab::General)));
                cx.notify();
            })),
    )
}

fn language_row(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let mut seg = div().class("seg");
    for lang in Lang::all() {
        let on = state.lang == lang;
        seg = seg.child(
            div()
                .class(if on { "seg-item on" } else { "seg-item" })
                .id(format!("lang-{}", lang.label()))
                .title("切换引擎事实语言；界面文案目前只有中文")
                .child(lang.label())
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state.apply(AppAction::SetLanguage(lang));
                    cx.notify();
                })),
        );
    }
    // 这个控件不是「界面语言」：全仓没有按 `lang` 分支的字符串。
    // 不写清楚，用户会以为点了「EN」界面就会变英文。
    div()
        .class("stack-sm")
        .child(div().class("t-caption dim").child("引擎事实语言 · 界面仅中文"))
        .child(seg)
}

// ══════════════════════════════════════════════════════════════════════
// 纯函数（可单测；页面不要各写一份）
// ══════════════════════════════════════════════════════════════════════

/// 搜索匹配：项目名 **或** 任一分支名（含当前分支）。ASCII 不区分大小写。
fn project_matches(p: &Project, query: &str) -> bool {
    if query.is_empty() {
        return true;
    }
    if crate::app::matches_query(&p.name, query) {
        return true;
    }
    if let Some(b) = &p.current_branch {
        if crate::app::matches_query(b, query) {
            return true;
        }
    }
    p.branches
        .iter()
        .any(|b| crate::app::matches_query(&b.name, query))
}

/// 行上显示哪个分支：搜索命中哪个就显示哪个，否则当前分支/第一个分支。
fn display_branch(p: &Project, query: &str) -> Option<String> {
    if !query.is_empty() {
        if let Some(b) = &p.current_branch {
            if crate::app::matches_query(b, query) {
                return Some(b.clone());
            }
        }
        if let Some(b) = p
            .branches
            .iter()
            .find(|b| crate::app::matches_query(&b.name, query))
        {
            return Some(b.name.clone());
        }
    }
    p.current_branch
        .clone()
        .or_else(|| p.branches.first().map(|b| b.name.clone()))
}

/// 项目脏度：结构化 `dirty.total` 优先；退回 `userDirtyCount + untrackedCount`
/// 只在两者都读得到时才成立。任一缺失/`-1` ⇒ `NotRead`（不是 0）。
fn dirty_reading(p: &Project) -> Reading<i64> {
    if let Reading::Known(d) = p.dirty_state() {
        return Reading::Known(d.total);
    }
    match (p.user_dirty_count, p.untracked_count) {
        (Some(a), Some(b)) if a >= 0 && b >= 0 => Reading::Known(a + b),
        _ => Reading::NotRead,
    }
}

/// 行上的状态词。`status_word` 的「干净」只表示「没有已知脏度」；
/// 脏度读不出来时那个词会变成一句没有依据的保证 —— 这一种情况单独说出来。
/// 其余优先级（读不出来 / 停滞 / 有未提交）原样保留。
fn row_word(p: &Project, dirty: &Reading<i64>) -> &'static str {
    let word = models::status_word(p);
    if p.is_git() && !dirty.is_known() && word == "干净" {
        "脏度读不出来"
    } else {
        word
    }
}

/// 按**字符**截断（中文按字节切会 panic，见 AGENTS 的 safeSlice 纪律）。
fn shorten(s: &str, max: usize) -> String {
    let trimmed = s.trim();
    if trimmed.chars().count() <= max {
        return trimmed.to_string();
    }
    let head: String = trimmed.chars().take(max).collect();
    format!("{head}…")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::Branch;

    fn project(name: &str, branch: &str) -> Project {
        Project {
            name: name.to_string(),
            current_branch: Some(branch.to_string()),
            branches: vec![Branch {
                name: branch.to_string(),
                is_current: true,
                ..Default::default()
            }],
            kind: "git".to_string(),
            ..Default::default()
        }
    }

    #[test]
    fn search_matches_name_and_branch_case_insensitively() {
        let p = project("MoonGit", "feature/Sidebar");
        assert!(project_matches(&p, "moongit"));
        assert!(project_matches(&p, "sidebar"));
        assert!(project_matches(&p, "FEATURE"));
        assert!(!project_matches(&p, "confidence"));
        // 空查询 = 全部显示。
        assert!(project_matches(&p, ""));
    }

    #[test]
    fn search_matches_non_current_branch_too() {
        let mut p = project("alpha", "main");
        p.branches.push(Branch {
            name: "release/2.0".to_string(),
            ..Default::default()
        });
        assert!(project_matches(&p, "release"));
        // 命中非当前分支时，行上显示的是**命中的那个**分支。
        assert_eq!(display_branch(&p, "release").as_deref(), Some("release/2.0"));
        assert_eq!(display_branch(&p, "").as_deref(), Some("main"));
    }

    #[test]
    fn structured_dirty_wins_over_user_dirty_count() {
        // 实测：deeporca-site 的 userDirtyCount=0 而 dirty.total=2。
        let mut p = project("a", "main");
        p.user_dirty_count = Some(0);
        p.untracked_count = Some(0);
        p.dirty = Some(models::Dirty {
            ok: true,
            total: 2,
            ..Default::default()
        });
        assert_eq!(dirty_reading(&p), Reading::Known(2));
    }

    #[test]
    fn unreadable_dirty_is_not_zero() {
        let mut p = project("a", "main");
        p.error = Some("读不出来".to_string());
        p.user_dirty_count = Some(-1);
        p.untracked_count = Some(-1);
        assert_eq!(dirty_reading(&p), Reading::NotRead);
    }

    #[test]
    fn unknown_dirty_is_not_worded_as_clean() {
        // git 项目、脏度读不出来、没有采集错误 ⇒ 不许说「干净」。
        // `status_tone` 现在把这种项目判成 Unknown，所以词是「无法核验」；
        // 重点是它**不是**「干净」（旧行为是绿点 + 干净）。
        let mut p = project("a", "main");
        p.user_dirty_count = Some(-1);
        p.untracked_count = Some(-1);
        let word = row_word(&p, &Reading::NotRead);
        assert_ne!(word, "干净");
        assert_eq!(word, "无法核验");

        // 已知 0 ⇒ 仍然是「干净」。
        p.dirty = Some(models::Dirty {
            ok: true,
            total: 0,
            ..Default::default()
        });
        assert_eq!(row_word(&p, &Reading::Known(0)), "干净");

        // 非 git 仓库没有结构化脏度：不硬塞「读不出来」。
        let mut dir = project("dir", "main");
        dir.kind = "dir".to_string();
        dir.current_branch = None;
        assert_eq!(row_word(&dir, &Reading::NotRead), "干净");
    }

    #[test]
    fn shorten_never_splits_a_multibyte_char() {
        let s = "线性代数与概率统计";
        let out = shorten(s, 4);
        assert_eq!(out, "线性代数…");
    }
}
