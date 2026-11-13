// milestones.rs — 全局里程碑页：列表 + 筛选 + 状态动作（达成/重开/放弃）。
//
// 【诚实边界（本页的判据）】
//   · 读取失败 ≠ 空列表：`milestones_error` 必须渲染成错误页（带原因 + 重试），
//     不许只剩一个标题；
//   · `storeHealth` 缺键 / 非 ok 是**降级**：此时「0 条」不是「没有」；
//   · `unknown` 状态渲染成「无法核验」并带原因——绝不塌进「进行中」，也不提供
//     达成/放弃动作（项目页同一条纪律）；
//   · `readCount` 是引擎读到的条数，列表只是它的**下界**；两者不一致时明说；
//   · 孤儿里程碑只读：动作收项目名，而所属项目已注销。
//
// 颜色一律走 `Tone::class()`（design.rs 的调色板），视图不写十六进制色值。

use crate::app::{AppAction, AppRoot, AppState};
use crate::models::{milestone_lower_bound, Milestone, MilestoneList, OrphanedMilestone, Tone};
use crate::views::{feedback_banner, scroll_id};
use blenderui::prelude::*;

pub fn render(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let Some(list) = state.milestones.clone() else {
        return unread_page(state, cx);
    };

    let mut sub = format!(
        "列表 {} 条 · 孤儿 {} 条 · {} · 存储 {}",
        list.milestones.len(),
        list.orphaned.len(),
        read_count_text(&list),
        list.health_label()
    );
    if list.excluded_disabled > 0 {
        sub.push_str(&format!(
            " · 停用项目 {} 条未列入",
            list.excluded_disabled
        ));
    }

    let head = div()
        .class("main-head glass")
        .child(div().class("main-title").child("里程碑"))
        .child(div().class("main-sub").child(sub))
        .child(div().class("spacer"))
        .child(
            div()
                .class("btn")
                .id("ms-refresh")
                .child("刷新")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.refresh();
                    cx.notify();
                })),
        );

    let mut body = div().class("main-scroll").id(scroll_id(state));
    body = body.child(feedback_banner(state));

    // 有旧列表但最近一次读失败：数据可能过期，必须说出来（不能假装是新鲜的）。
    if let Some(e) = &state.milestones_error {
        body = body.child(tone_banner(
            Tone::Err,
            "最近一次读取失败",
            format!(
                "{}；下面是上次成功读取的列表，可能已经过期。",
                e.user_message()
            ),
        ));
    }

    // 降级披露：`storeHealth` 缺键也是降级（「不知道」不是「正常」）。
    match list.store_health.as_deref() {
        Some("ok") => {}
        Some(other) => {
            body = body.child(tone_banner(
                Tone::Warn,
                format!("里程碑存储降级（{other}）"),
                "明细可能不完整：下面的 0 条不是「没有里程碑」，读不出来 ≠ 没有。",
            ));
        }
        None => {
            body = body.child(tone_banner(
                Tone::Unknown,
                "引擎未披露存储健康",
                "storeHealth 键缺失：把下面的列表当成可能不完整；0 条不是「没有」。",
            ));
        }
    }
    if let Some(t) = milestone_lower_bound(&list) {
        body = body.child(tone_banner(Tone::Warn, "明细只是下界", t.note));
    }
    if list.excluded_disabled > 0 {
        body = body.child(div().class("t-caption dim").child(format!(
            "{} 条里程碑属于已停用项目，未列入本页。",
            list.excluded_disabled
        )));
    }

    body = body.child(filter_bar(state, &list, cx));

    let filter = &state.ui.milestones;
    let filtered: Vec<&Milestone> = list
        .milestones
        .iter()
        .filter(|m| filter.matches(m))
        .collect();

    if filtered.is_empty() {
        body = body.child(if list.milestones.is_empty() {
            empty_storage_state(&list)
        } else {
            div()
                .class("card")
                .child(div().class("empty-title").child("没有匹配的里程碑"))
                .child(div().class("muted").child(format!(
                    "共 {} 条；当前搜索/筛选把它们全挡住了。",
                    list.milestones.len()
                )))
                .child(
                    div()
                        .class("btn btn-sm")
                        .id("ms-clear-filters-empty")
                        .child("清除筛选")
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.state.apply(AppAction::SetMilestoneSearch(String::new()));
                            this.state.apply(AppAction::SetMilestoneProject(None));
                            this.state.apply(AppAction::SetMilestoneStatus(None));
                            cx.notify();
                        })),
                )
        });
    } else {
        for m in filtered {
            body = body.child(milestone_card(m, cx));
        }
    }

    // 孤儿里程碑（所属项目已注销）：如实单列，绝不混进正常列表，也不假装能操作。
    if !list.orphaned.is_empty() {
        body = body.child(
            div().class("card-title").child(format!(
                "孤儿里程碑（{}）· 所属项目已注销",
                list.orphaned.len()
            )),
        );
        for m in &list.orphaned {
            body = body.child(orphan_card(m));
        }
    }

    div().class("main").child(head).child(body)
}

/// `state.milestones` 为 None：读取中或读取失败。两种都不能渲染成空白页。
fn unread_page(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let (tone, title, text) = match &state.milestones_error {
        Some(e) => (
            Tone::Err,
            "里程碑读不出来".to_string(),
            format!(
                "引擎没有给出可用的里程碑载荷：{}。这不是「没有里程碑」。",
                e.user_message()
            ),
        ),
        None => (
            Tone::Unknown,
            "正在读取里程碑".to_string(),
            "还没有拿到 milestone list；点「重试」再读一次。".to_string(),
        ),
    };
    let head = div()
        .class("main-head glass")
        .child(div().class("main-title").child("里程碑"))
        .child(div().class("main-sub").child(title.clone()));
    let body = div()
        .class("main-scroll")
        .id(scroll_id(state))
        .child(feedback_banner(state))
        .child(tone_banner(tone, title, text))
        .child(
            div()
                .class("btn btn-accent")
                .id("ms-retry")
                .child("重试")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.load_milestones();
                    cx.notify();
                })),
        );
    div().class("main").child(head).child(body)
}

fn read_count_text(list: &MilestoneList) -> String {
    if list.read_count >= 0 {
        format!("引擎读到 {} 条", list.read_count)
    } else {
        "引擎条数未披露".to_string()
    }
}

/// 存储健康时的真·空态；降级时绝不说「暂无里程碑」。
fn empty_storage_state(list: &MilestoneList) -> Div {
    let orphan_note = if list.orphaned.is_empty() {
        String::new()
    } else {
        format!(
            "另有 {} 条孤儿里程碑（所属项目已注销），见下方单独列表。",
            list.orphaned.len()
        )
    };
    if list.degraded() {
        return div()
            .class("card")
            .child(div().class("empty-title").child("里程碑读不出来"))
            .child(div().class("muted").child(format!(
                "存储处于降级/未披露状态（{}），引擎读到 {} 条 —— 不能据此说「没有里程碑」。{}",
                list.health_label(),
                if list.read_count >= 0 {
                    list.read_count.to_string()
                } else {
                    "未知".to_string()
                },
                orphan_note
            )));
    }
    let body = if list.read_count < 0 {
        format!(
            "引擎没有披露读到多少条；当前列表为空 —— 不能据此说「没有里程碑」。{}",
            orphan_note
        )
    } else if list.read_count > 0 {
        format!(
            "引擎读到 {} 条，但当前列表为空：它们可能属于已停用项目（本页未列入 {} 条）或孤儿。{}",
            list.read_count, list.excluded_disabled, orphan_note
        )
    } else {
        format!(
            "引擎读到 0 条里程碑，存储健康 —— 这才是真的没有。在仓库的 README 托管区或里程碑库里新建后出现在这里。{orphan_note}"
        )
    };
    let title = if list.read_count < 0 {
        "列表为空（条数未披露）"
    } else if list.read_count > 0 {
        "已注册项目暂无里程碑"
    } else {
        "暂无里程碑"
    };
    div()
        .class("card")
        .child(div().class("empty-title").child(title))
        .child(div().class("muted").child(body))
}

fn filter_bar(state: &AppState, list: &MilestoneList, cx: &mut Context<AppRoot>) -> Div {
    let f = &state.ui.milestones;
    let mut card = div().class("card").id("ms-filters");

    card = card.child(
        div()
            .class("row-sm")
            .child(div().class("t-caption").child("搜索"))
            .child(
                div().class("field-box grow").child(
                    input()
                        .class("input")
                        .id("ms-search")
                        .placeholder("名称 / 描述 / 项目")
                        .value(f.search.clone())
                        .on_input(cx.listener(|this, e: &blenderui::ChangeEvent, _, cx| {
                            this.state.apply(AppAction::SetMilestoneSearch(e.value.clone()));
                            cx.notify();
                        })),
                ),
            ),
    );

    // 状态：None 之外，`unknown` 必须可单独筛（它既不是 open 也不是 done）。
    let mut seg = div().class("seg");
    for (value, label) in [
        (None, "全部状态"),
        (Some("open"), "进行中"),
        (Some("done"), "已达成"),
        (Some("dropped"), "已放弃"),
        (Some("unknown"), "无法核验"),
    ] {
        let on = f.status.as_deref() == value;
        seg = seg.child(
            div()
                .class(if on { "seg-item on" } else { "seg-item" })
                .id(format!("ms-status-{}", value.unwrap_or("all")))
                .child(label)
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state
                        .apply(AppAction::SetMilestoneStatus(value.map(str::to_string)));
                    cx.notify();
                })),
        );
    }
    card = card.child(div().class("row-wrap").child(seg));

    // 项目 chips：用 `project_label()`（缺 projectName 时退回 projectId），
    // 与 `MilestoneFilters::matches` 同一口径。
    let mut projects: Vec<String> = list
        .milestones
        .iter()
        .map(|m| m.project_label())
        .filter(|s| !s.trim().is_empty())
        .collect();
    projects.sort();
    projects.dedup();
    if projects.len() > 1 || f.project.is_some() {
        let mut chips = div().class("row-wrap");
        chips = chips.child(div().class("t-caption").child("项目"));
        chips = chips.child(
            div()
                .class(if f.project.is_none() {
                    "chip chip-sm accent"
                } else {
                    "chip chip-sm"
                })
                .id("ms-project-all")
                .child("全部")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.apply(AppAction::SetMilestoneProject(None));
                    cx.notify();
                })),
        );
        for p in projects {
            let on = f.project.as_deref() == Some(p.as_str());
            let value = p.clone();
            chips = chips.child(
                div()
                    .class(if on { "chip chip-sm accent" } else { "chip chip-sm" })
                    .id(format!("ms-project-{p}"))
                    .child(p)
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state
                            .apply(AppAction::SetMilestoneProject(Some(value.clone())));
                        cx.notify();
                    })),
            );
        }
        card = card.child(chips);
    }

    let active = !f.search.trim().is_empty() || f.project.is_some() || f.status.is_some();
    if active {
        card = card.child(
            div()
                .class("btn btn-sm btn-ghost")
                .id("ms-clear-filters")
                .child("清除筛选")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.apply(AppAction::SetMilestoneSearch(String::new()));
                    this.state.apply(AppAction::SetMilestoneProject(None));
                    this.state.apply(AppAction::SetMilestoneStatus(None));
                    cx.notify();
                })),
        );
    }
    card
}

fn milestone_card(m: &Milestone, cx: &mut Context<AppRoot>) -> Div {
    let tone = m.status_tone();
    let project_known = m
        .project
        .as_deref()
        .map(|s| !s.trim().is_empty())
        .unwrap_or(false);
    let project = m.project.clone().unwrap_or_default();
    let name = m.name.clone();

    let mut card = div()
        .class("card")
        .id(format!("ms-{}-{}", m.project_label(), m.name))
        .child(
            div()
                .class("row")
                .child(div().class(format!("dot {}", tone.class())))
                .child(div().class("h2").child(m.name.clone()))
                .child(tone_chip(m.status_word(), tone))
                .child(div().class("spacer"))
                .child(div().class("dim").child(m.project_label())),
        );

    let desc = m.description_text();
    if !desc.is_empty() {
        card = card.child(div().class("muted").child(desc));
    }
    card = card.child(
        div()
            .class("row-wrap")
            .child(div().class("t-caption dim").child(m.target_label())),
    );

    if !matches!(
        m.status.as_deref(),
        Some("open") | Some("done") | Some("dropped")
    ) && !m.unverified_reason.trim().is_empty()
    {
        card = card.child(tone_banner(
            Tone::Unknown,
            "无法核验的原因",
            m.unverified_reason.clone(),
        ));
    }

    let mut actions = div().class("row-wrap");
    if !project_known {
        // 不带空项目名去调引擎：`milestone_action` 收项目名，空串只会换来
        // 「未找到项目」，而且界面上那张卡连项目都显示不出来。
        actions = actions.child(tone_chip(
            format!(
                "项目名缺失，无法执行动作（projectId={}）",
                if m.project_id.trim().is_empty() {
                    "未披露"
                } else {
                    m.project_id.as_str()
                }
            ),
            Tone::Unknown,
        ));
    } else {
        match m.status.as_deref() {
            Some("open") => {
                let p1 = project.clone();
                let n1 = name.clone();
                let p2 = project.clone();
                let n2 = name.clone();
                let p3 = project.clone();
                actions = actions
                    .child(
                        div()
                            .class("btn btn-accent")
                            .id(format!("ms-done-{}", m.name))
                            .child("达成")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.milestone_action(&p1, &n1, "done");
                                cx.notify();
                            })),
                    )
                    .child(
                        div()
                            .class("btn danger")
                            .id(format!("ms-drop-{}", m.name))
                            .child("放弃")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                // 破坏性动作与项目页同一道确认闸门。
                                this.state.ask_milestone_drop(&p2, &n2);
                                cx.notify();
                            })),
                    )
                    .child(div().class("spacer"))
                    .child(
                        div()
                            .class("btn ghost")
                            .child("进入仓库 →")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.select(crate::app::Route::Project(p3.clone()));
                                cx.notify();
                            })),
                    );
            }
            Some("done") => {
                let p1 = project.clone();
                let n1 = name.clone();
                let p2 = project.clone();
                actions = actions
                    .child(
                        div()
                            .class("btn")
                            .id(format!("ms-reopen-{}", m.name))
                            .child("重开")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.milestone_action(&p1, &n1, "reopen");
                                cx.notify();
                            })),
                    )
                    .child(div().class("spacer"))
                    .child(
                        div()
                            .class("btn ghost")
                            .child("进入仓库 →")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.select(crate::app::Route::Project(p2.clone()));
                                cx.notify();
                            })),
                    );
            }
            Some("dropped") => {
                let p1 = project.clone();
                let n1 = name.clone();
                let p2 = project.clone();
                actions = actions
                    .child(
                        div()
                            .class("btn")
                            .id(format!("ms-reopen-{}", m.name))
                            .child("重新打开")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.milestone_action(&p1, &n1, "reopen");
                                cx.notify();
                            })),
                    )
                    .child(div().class("spacer"))
                    .child(
                        div()
                            .class("btn ghost")
                            .child("进入仓库 →")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.select(crate::app::Route::Project(p2.clone()));
                                cx.notify();
                            })),
                    );
            }
            _ => {
                // unknown / 缺键：不提供任何状态动作（与项目页一致）。
                actions = actions.child(tone_chip("无法核验：不提供达成/重开", Tone::Unknown));
            }
        }
    }
    card = card.child(actions);
    card
}

fn orphan_card(m: &OrphanedMilestone) -> Div {
    let tone = orphan_tone(&m.status);
    let mut card = div()
        .class("card")
        .id(format!("ms-orphan-{}", m.name))
        .child(
            div()
                .class("row")
                .child(div().class(format!("dot {}", tone.class())))
                .child(div().class("card-title").child(m.name.clone()))
                .child(tone_chip(m.status_word(), tone))
                .child(div().class("spacer"))
                .child(
                    div()
                        .class("dim")
                        .child(format!("projectId={}", if m.project_id.as_deref().unwrap_or("").trim().is_empty() { "未披露" } else { m.project_id.as_deref().unwrap_or("") })),
                ),
        );

    if !m.description.trim().is_empty() {
        card = card.child(div().class("muted").child(m.description.clone()));
    }
    if !m.target_date.trim().is_empty() {
        card = card.child(
            div()
                .class("t-caption dim")
                .child(format!("目标日期 {}", m.target_date)),
        );
    }
    if !matches!(m.status.as_str(), "open" | "done" | "dropped") {
        card = card.child(tone_banner(
            Tone::Unknown,
            "无法核验",
            "孤儿条目的状态缺键 / 不是 open|done|dropped；它既不是进行中也不是达成。",
        ));
    }
    card = card.child(div().class("t-caption dim").child(
        "孤儿是只读的：里程碑动作收项目名，而所属项目已注销。",
    ));
    card
}

fn orphan_tone(status: &str) -> Tone {
    match status {
        "done" => Tone::Ok,
        "open" => Tone::Accent,
        "dropped" => Tone::Idle,
        _ => Tone::Unknown,
    }
}

fn tone_chip(text: impl Into<String>, tone: Tone) -> Div {
    div()
        .class(format!("chip chip-sm {}", tone.class()))
        .child(text.into())
}

fn tone_banner(tone: Tone, title: impl Into<String>, body: impl Into<String>) -> Div {
    div()
        .class(format!("banner {}", tone.class()))
        .child(div().class("banner-title").child(title.into()))
        .child(div().class("banner-body").child(body.into()))
}
