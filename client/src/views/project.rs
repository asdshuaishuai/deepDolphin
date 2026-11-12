// project.rs — 仓库面板：事实卡 + git 操作 + 选文件提示 + 图谱交付物入口。

use crate::app::{AppRoot, AppState};
use crate::views::{feedback_banner, status_dot};
use blenderui::prelude::*;

pub fn render(state: &AppState, name: &str, cx: &mut Context<AppRoot>) -> Div {
    let Some(p) = state.project(name).cloned() else {
        return div()
            .class("main")
            .child(
                div().class("main-head").child(div().class("main-title").child("仓库不存在")),
            )
            .child(div().class("main-scroll").child(div().class("banner warn").child(format!("注册表里没有「{name}」"))));
    };

    let (color, word) = status_dot(&p);

    let head = div()
        .class("main-head")
        .child(div().class("main-title").child(p.name.clone()))
        .child(div().class("dot").style(format!("background: {color};")))
        .child(div().class("main-sub").child(word))
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

    if let Some(err) = &p.error {
        body = body.child(div().class("banner err").child(format!("读不出来：{err}")));
    }
    if let Some(ws) = &p.warnings {
        for w in ws {
            body = body.child(div().class("banner warn").child(format!("⚠ {w}")));
        }
    }

    // 事实卡
    let commits = p.commit_count.unwrap_or(-1);
    let commits_text = if commits < 0 { "—".to_string() } else { format!("{commits}") };
    body = body.child(
        div()
            .class("card")
            .child(div().class("card-title").child("工程现状"))
            .child(
                div()
                    .class("row")
                    .child(kv("路径", &p.path))
                    .child(div().style("flex: 1;")),
            )
            .child(
                div()
                    .class("wrap")
                    .child(chip(format!("未提交 {}", p.user_dirty_count.unwrap_or(0))))
                    .child(chip(format!("未跟踪 {}", p.untracked_count.unwrap_or(0))))
                    .child(chip(format!("stash {}", p.stash_count.unwrap_or(0))))
                    .child(chip(format!("提交 {commits_text}")))
                    .child(chip(format!(
                        "最近提交 {}",
                        p.last_commit_ago.clone().unwrap_or_else(|| "—".into())
                    )))
                    .child(chip(format!(
                        "当前 {}",
                        p.current_branch.clone().unwrap_or_else(|| "—".into())
                    ))),
            ),
    );

    // git 操作（引擎白名单：commit/pull/push/fetch/stash/unstash）
    if p.is_git() {
        let mut ops = div().class("card").child(div().class("card-title").child("Git 操作（引擎白名单）"));
        let mut row = div().class("row");
        for (label, op, accent) in [
            ("拉取", "pull", false),
            ("推送", "push", false),
            ("抓取", "fetch", false),
            ("暂存", "stash", false),
            ("恢复", "unstash", false),
        ] {
            let project = p.name.clone();
            row = row.child(
                div()
                .class(if accent { "btn accent" } else { "btn" })
                    .id(format!("git-{op}"))
                    .child(label)
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.git_action(&project, op);
                        cx.notify();
                    })),
            );
        }
        ops = ops.child(row);

        // 提交：信息 + 按钮（引擎 commit 需要显式 --message）
        let project = p.name.clone();
        let draft = state.commit_draft.clone();
        ops = ops.child(
            div()
                .class("row")
                .child(
                    input()
                        .class("input")
                        .id("commit-msg")
                        .placeholder("提交信息（提交全部改动）")
                        .value(draft)
                        .on_change(cx.listener(|this, e: &blenderui::ChangeEvent, _, cx| {
                            this.state.commit_draft = e.value.clone();
                            cx.notify();
                        })),
                )
                .child(
                    div()
                .class("btn accent")
                        .id("git-commit")
                        .child("提交")
                        .on_click(cx.listener(move |this, _, _, cx| {
                            this.state.git_action(&project, "commit");
                            cx.notify();
                        })),
                ),
        );
        body = body.child(ops);
    }

    // 图谱交付物（产物探测 → 打开 / 生成指引）
    let mut graphs = div().class("grid2");
    for (artifact, title, desc) in [
        ("index", "代码图谱 · 置信度热力图", "列表/热力图双模式 · 关系连线 · 下钻"),
        ("arch", "技术架构图", "分层泳道 + 职责视图 · 违规/环治理信号"),
    ] {
        let path = state
            .artifacts
            .iter()
            .find(|((proj, art), _)| proj == name && art == artifact)
            .map(|(_, v)| v.clone());
        let ready = matches!(&path, Some(Some(_)));
        let project = p.name.clone();
        let mut card = div()
            .class(if ready { "card artifact ready" } else { "card artifact missing" })
            .id(format!("artifact-{artifact}"))
            .child(div().class("card-title").child(title))
            .child(div().class("dim").child(desc));
        if ready {
            card = card.child(
                div()
                    .class("row")
                    .child(div().class("dim").style("flex: 1;").child("产物已生成 · 系统浏览器渲染"))
                    .child(
                        div()
                .class("btn accent")
                            .child("打开 →")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.open_artifact(&project, artifact);
                                cx.notify();
                            })),
                    ),
            );
        } else {
            let project2 = p.name.clone();
            card = card.child(
                div()
                    .class("row")
                    .child(
                        div()
                            .class("dim")
                            .style("flex: 1;")
                            .child("尚未生成：用 AI agent 按 `moongit skill graph` 驱动引擎生成"),
                    )
                    .child(
                        div()
                .class("btn")
                            .child("检查")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                let _ = this.state.probe_artifact(&project2, artifact);
                                cx.notify();
                            })),
                    ),
            );
        }
        graphs = graphs.child(card);
    }
    body = body.child(div().class("card-title").style("padding-left: 2px;").child("图谱交付物"));
    body = body.child(graphs);

    div().class("main").child(head).child(body)
}

fn kv(k: &str, v: &str) -> Div {
    div()
        .class("kv")
        .child(div().class("k").child(format!("{k}：")))
        .child(div().class("v").child(v.to_string()))
}

fn chip(text: String) -> Div {
    div().class("chip").child(text)
}
