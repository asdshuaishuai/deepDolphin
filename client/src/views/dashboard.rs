// dashboard.rs — 项目群仪表盘：引擎 summary 事实 + 项目卡点入详情。

use crate::app::{AppRoot, AppState, Route};
use crate::views::{feedback_banner, metric, status_dot};
use blenderui::prelude::*;

pub fn render(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let s = state.status.as_ref().map(|x| x.summary.clone()).unwrap_or_default();
    let projects = state.projects().to_vec();

    let head = div()
        .class("main-head")
        .child(div().class("main-title").child("项目群脉搏"))
        .child(div().class("main-sub").child(format!("{} 个已注册项目", s.listed_projects)))
        .child(div().style("flex: 1;"))
        .child(
            div()
                .class("btn")
                .child("刷新")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.refresh();
                    this.state.feedback = Some(crate::app::Feedback { ok: true, text: "已刷新".into() });
                    cx.notify();
                })),
        );

    let mut body = div().class("main-scroll");
    body = body.child(feedback_banner(state));
    if let Some(err) = &state.error {
        body = body.child(div().class("banner err").child(err.clone()));
    }

    // KPI 四卡（引擎 summary 原值，不在客户端重算）
    body = body.child(
        div()
            .class("grid3")
            .child(metric("项目总数", format!("{}", s.listed_projects), &format!("采集失败 {} · 降级 {} 库", s.failed_projects, s.stale_projects)))
            .child(metric("待你动手", format!("{}", s.dirty_projects), "有未提交改动的项目"))
            .child(metric("活跃项目", format!("{}", s.active_projects), "近 7 天有新进展")),
    );

    // 项目卡网格
    let mut grid = div().class("grid2");
    for p in &projects {
        let (color, word) = status_dot(p);
        let name = p.name.clone();
        let headline = p
            .headline
            .clone()
            .unwrap_or_else(|| if p.error.is_some() { "读不出来".into() } else { "暂无摘要".into() });
        let branch = p.current_branch.clone().unwrap_or_else(|| "—".into());
        let dirty = p.user_dirty_count.unwrap_or(0);
        let commits = p.commit_count.unwrap_or(-1);
        let commits_text = if commits < 0 { "—".to_string() } else { format!("{commits} 个提交") };
        grid = grid.child(
            div()
                .class("card")
                .id(format!("card-{}", p.name))
                .child(
                    div()
                        .class("row")
                        .child(div().class("dot").style(format!("background: {color};")))
                        .child(div().class("h2").child(p.name.clone()))
                        .child(div().class("dim").style("font-size: 11px;").child(word))
                        .child(div().style("flex: 1;"))
                        .child(div().class("chip").child(format!("⎇ {branch}"))),
                )
                .child(div().class("muted").child(headline))
                .child(
                    div()
                        .class("row")
                        .child(div().class("dim").child(commits_text))
                        .child(div().class("dim").child(format!("未提交 {dirty}")))
                        .child(div().style("flex: 1;"))
                        .child(
                            div()
                .class("btn ghost")
                                .child("进入管控 →")
                                .on_click(cx.listener(move |this, _, _, cx| {
                                    this.state.select(Route::Project(name.clone()));
                                    cx.notify();
                                })),
                        ),
                ),
        );
    }
    body = body.child(grid);

    div().class("main").child(head).child(body)
}
