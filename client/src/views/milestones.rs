// milestones.rs — 里程碑页：全局列表 + 状态动作（达成/重开/放弃）。
//
// 诚实边界：unknown 状态渲染成「无法核验」并带原因——绝不塌进「进行中」。

use crate::app::{AppRoot, AppState};
use crate::views::feedback_banner;
use blenderui::prelude::*;

pub fn render(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let Some(list) = state.milestones.clone() else {
        return div().class("main").child(
            div().class("main-head").child(div().class("main-title").child("里程碑")),
        );
    };

    let head = div()
        .class("main-head")
        .child(div().class("main-title").child("里程碑"))
        .child(div().class("main-sub").child({
            let health: String = if list.store_health.as_deref().unwrap_or("ok") == "ok" {
                "无".to_string()
            } else {
                "有（看页脚）".to_string()
            };
            format!("{} 条 · 读不出来 {}", list.milestones.len(), health)
        }))
        .child(div().style("flex: 1;"))
        .child(
            div()
                .class("btn")
                .child("刷新")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.refresh();
                    cx.notify();
                })),
        );

    let mut body = div().class("main-scroll");
    body = body.child(feedback_banner(state));

    if list.milestones.is_empty() && list.orphaned.is_empty() {
        body = body.child(div().class("card").child(div().class("muted").child("暂无里程碑。在仓库的 README 托管区或引擎里程碑库中新建后出现在这里。")));
    }

    for m in &list.milestones {
        let project = m.project.clone().unwrap_or_default();
        let name = m.name.clone();
        let tone = match m.status.as_deref() {
            Some("done") => "#3FCF8E",
            Some("open") => "#4C8DFF",
            Some("dropped") => "#8B9BB4",
            _ => "#FFB454",
        };
        let mut card = div()
            .class("card")
            .id(format!("ms-{}-{}", project, m.name))
            .child(
                div()
                    .class("row")
                    .child(div().class("dot").style(format!("background: {tone};")))
                    .child(div().class("h2").child(m.name.clone()))
                    .child(div().class("chip").child(m.status_word()))
                    .child(div().style("flex: 1;"))
                    .child(div().class("dim").child(project.clone())),
            );
        if let Some(d) = &m.description {
            if !d.is_empty() {
                card = card.child(div().class("muted").child(d.clone()));
            }
        }
        if m.status.as_deref() != Some("done") && m.status.as_deref() != Some("dropped") {
            let p1 = project.clone();
            let n1 = name.clone();
            let p2 = project.clone();
            let n2 = name.clone();
            let p3 = project.clone();
            card = card.child(
                div()
                    .class("row")
                    .child(
                        div()
                .class("btn accent")
                            .child("达成")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.milestone_action(&p1, &n1, "done");
                                cx.notify();
                            })),
                    )
                    .child(
                        div()
                .class("btn")
                            .child("放弃")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.milestone_action(&p2, &n2, "drop");
                                cx.notify();
                            })),
                    )
                    .child(div().style("flex: 1;"))
                    .child(
                        div()
                .class("btn ghost")
                            .child("进入仓库 →")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.select(crate::app::Route::Project(p3.clone()));
                                cx.notify();
                            })),
                    ),
            );
        } else if m.status.as_deref() == Some("done") {
            let p1 = project.clone();
            let n1 = name.clone();
            card = card.child(
                div().class("row").child(
                    div()
                .class("btn")
                        .child("重开")
                        .on_click(cx.listener(move |this, _, _, cx| {
                            this.state.milestone_action(&p1, &n1, "reopen");
                            cx.notify();
                        })),
                ),
            );
        }
        body = body.child(card);
    }

    // 孤儿里程碑（所属项目已注销）：如实单列，绝不混进正常列表
    if !list.orphaned.is_empty() {
        body = body.child(div().class("card-title").style("padding-left: 2px;").child(format!("孤儿里程碑（{}）· 所属项目已注销", list.orphaned.len())));
        for m in &list.orphaned {
            body = body.child(
                div()
                    .class("card")
                    .child(
                        div()
                            .class("row")
                            .child(div().class("dot").style("background: #FFB454;"))
                            .child(div().class("muted").child(m.name.clone()))
                            .child(div().class("dim").child(m.project_id.clone().unwrap_or_default())),
                    ),
            );
        }
    }

    div().class("main").child(head).child(body)
}
