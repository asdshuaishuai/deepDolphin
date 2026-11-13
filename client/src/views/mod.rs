// views/mod.rs — 路由分发与页面共享小件。
//
// 【纪律】
//   · 每个页面只读 `&AppState`；动作通过 `Action` 回 `AppState::dispatch`。
//   · 主滚动容器的 id 统一是 `scroll-<Route::key()>`（项目页含 tab），
//     `navigate` 的 `pending_scroll` 靠它复位到顶部。
//   · 每个页面的 `.main-scroll` 第一项统一是 `feedback_block(state)`：
//     反馈（成功/失败）、深链说明、引擎不可用三块按固定顺序渲染。
//   · 视图不写颜色/圆角/间距 —— 只用 design.rs 的类名。

pub mod board;
pub mod confidence;
pub mod dashboard;
pub mod milestones;
pub mod patch;
pub mod project;
pub mod scan;
pub mod sidebar;

use crate::app::{AppRoot, AppState, Route};
use blenderui::prelude::*;

// ══════════════════════════════════════════════════════════════════════
// v0 兼容小件（旧页面直接调用；签名冻结）
// ══════════════════════════════════════════════════════════════════════

/// v0 顶部反馈条（旧页面调用）。新页面用 `feedback_block`。
pub fn feedback_banner(state: &AppState) -> Div {
    match &state.feedback {
        Some(f) => {
            let tone = if f.ok { "ok" } else { "err" };
            div()
                .class(format!("banner {tone}"))
                .id("feedback")
                .child(f.text.clone())
        }
        None => div().id("feedback"),
    }
}

/// v0 数字统计小件（旧仪表盘调用）。
pub fn metric(label: &str, value: String, hint: &str) -> Div {
    div()
        .class("card")
        .child(div().class("kpi-label").child(label.to_string()))
        .child(div().class("kpi-value").child(value))
        .child(div().class("kpi-hint").child(hint.to_string()))
}

// ══════════════════════════════════════════════════════════════════════
// 新页面共享件
// ══════════════════════════════════════════════════════════════════════

/// 等宽类选择：BUI 0.5 **没有逐字形回退**，而等宽字体（Menlo / DejaVu Mono）
/// 不含 CJK 字形。含中文的路径/分支直接套 `font-family: monospace` 会变豆腐块，
/// 所以按内容选类：纯 ASCII 用等宽（SHAs、porcelain xy、数字对齐），
/// 含 CJK 退回项目的中文字面。
pub fn mono_class(text: &str) -> &'static str {
    if text.chars().any(|c| (c as u32) >= 0x2E80) {
        "t-mono-cjk"
    } else {
        "t-mono"
    }
}

/// 用户主动停止的中性态。**不是失败**（不必惊慌），也不是「没有结果」的
/// 空态 —— 它只说明上一次运行被取消，重新运行即可。
pub fn stopped_card(what: &str) -> Div {
    div()
        .class("empty")
        .child(div().class("empty-icon").child("◼"))
        .child(div().class("empty-title").child(format!("{what}已停止")))
        .child(div().class("empty-body").child(
            "这是用户主动取消，不是分析失败，也不是「没有发现问题」。重新运行即可。",
        ))
}

/// 滚动容器 id：`scroll-<route key>`（项目页带 tab）。
pub fn scroll_id(state: &AppState) -> String {
    state.route.scroll_id(&state.project_tab)
}

/// 页面顶部的三块披露，顺序固定：
///   1. `feedback`（动作的成功/失败）；
///   2. `route_note`（深链/说明，info）；
///   3. `startup_error`（引擎不可用，err + 安装指引）。
/// 恒发容器（即使三块都空）—— 页面不需要自己判断「有没有内容」。
pub fn feedback_block(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let mut stack = div().class("stack-sm").id("feedback-block");

    if let Some(f) = &state.feedback {
        let tone = if f.ok { "ok" } else { "err" };
        let text = f.text.clone();
        stack = stack.child(
            div()
                .class(format!("banner {tone}"))
                .id("feedback")
                .child(
                    div()
                        .class("row-between")
                        .child(div().class("banner-body").child(text))
                        .child(div().class("banner-action").child(
                            div()
                                .class("btn btn-sm btn-ghost")
                                .child("关闭")
                                .id("feedback-dismiss")
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.state
                                        .dispatch(crate::app::Action::App(
                                            crate::app::AppAction::DismissFeedback,
                                        ));
                                    cx.notify();
                                })),
                        )),
                ),
        );
    }

    if let Some(note) = &state.route_note {
        stack = stack.child(
            div()
                .class("banner info")
                .child(div().class("banner-title").child("说明"))
                .child(div().class("banner-body").child(note.clone())),
        );
    }

    if let Some(err) = &state.startup_error {
        stack = stack.child(
            div()
                .class("banner err")
                .child(div().class("banner-title").child("引擎不可用"))
                .child(div().class("banner-body").child(err.user_message()))
                .child(
                    div()
                        .class("banner-body")
                        .child("安装 moonGit 后，把 MOONGIT_BIN 指向引擎可执行文件；或把 moongit 放到客户端同目录。"),
                ),
        );
    }

    stack
}

/// 页面外壳：`.main` + 标题栏 + 滚动区（id = `scroll-<key>`）+ `feedback_block`。
/// 新页面直接复用；旧页面（dashboard/project/milestones）保留自己的外壳。
pub fn page_shell(
    state: &AppState,
    title: impl Into<String>,
    sub: impl Into<String>,
    cx: &mut Context<AppRoot>,
    body: Div,
) -> Div {
    let sub = sub.into();
    let mut head = div()
        .class("main-head glass")
        .child(
            div()
                .class("main-head-main")
                .child(div().class("main-title").child(title.into()))
                .child(div().class("main-sub").child(sub)),
        )
        .child(div().class("spacer"));
    head = head.child(
        div()
            .class("btn btn-ghost")
            .id("page-refresh")
            .child("刷新")
            .on_click(cx.listener(|this, _, _, cx| {
                this.state
                    .dispatch(crate::app::Action::App(crate::app::AppAction::Refresh(
                        crate::app::RefreshScope::All,
                    )));
                cx.notify();
            })),
    );

    div()
        .class("main")
        .child(head)
        .child(
            div()
                .class("main-scroll")
                .id(scroll_id(state))
                .child(feedback_block(state, cx))
                // `.page` 是 1080px 的内容列（design.rs 的既有词表）。
                // 没有它时，宽窗口下正文会一直拉到视口边缘。
                .child(div().class("page").child(body)),
        )
}

/// P0 空桩页面：标题 + 一句「待实现」+ 空态说明。
/// 空桩必须能编译、能渲染、能刷新；它不假装自己有内容。
pub fn placeholder_page(
    state: &AppState,
    title: &'static str,
    sub: &'static str,
    cx: &mut Context<AppRoot>,
) -> Div {
    page_shell(
        state,
        title,
        sub,
        cx,
        div()
            .class("empty")
            .child(div().class("empty-icon").child("◌"))
            .child(div().class("empty-title").child("此页面的内容尚未实现"))
            .child(div().class("empty-body").child(sub)),
    )
}

// ══════════════════════════════════════════════════════════════════════
// 路由分发
// ══════════════════════════════════════════════════════════════════════

/// 渲染当前路由。四个 v0 页面保留自己的签名；新页面统一 `(state, cx)`。
pub fn render_route(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    match &state.route {
        Route::Dashboard => dashboard::render(state, cx),
        Route::Board => board::render(state, cx),
        Route::Milestones => milestones::render(state, cx),
        Route::Confidence => confidence::render(state, cx),
        Route::Patch => patch::render(state, cx),
        Route::Project(name) => project::render(state, name, cx),
        Route::Scan => scan::render(state, cx),
        Route::Settings(tab) => page_shell(
            state,
            format!("设置 · {}", tab.title()),
            "设置页由 core 在 P2 落地；当前是占位",
            cx,
            div()
                .class("page-narrow")
                .child(
                    div()
                        .class("empty")
                        .child(div().class("empty-icon").child("⚙"))
                        .child(div().class("empty-title").child("设置面板尚未实现"))
                        .child(div().class("empty-body").child("预期包含：通用 / AI / 自动化 / 关于")),
                ),
        ),
        Route::Agent => page_shell(
            state,
            "AI 助手",
            "AI 页由 core 在 P3 落地；当前是占位",
            cx,
            div()
                .class("page-narrow")
                .child(
                    div()
                        .class("empty")
                        .child(div().class("empty-icon").child("✦"))
                        .child(div().class("empty-title").child("AI 助手尚未接入"))
                        .child(div().class("empty-body").child("引擎已经 AI 无关；provider/agent 循环在客户端，属于 P3")),
                ),
        ),
    }
}

/// 进入路由时的一次性加载（幂等）。
///
/// 只在这里发「首次加载」，不放在 `render` 里 —— render 不得改状态。
pub fn on_enter_route(state: &mut AppState, route: &Route) {
    match route {
        Route::Dashboard => {
            state.ensure_status();
            if matches!(state.dashboard, crate::app::Load::Idle) {
                state.load_dashboard();
            }
        }
        Route::Board => state.ensure_status(),
        Route::Milestones => {
            state.ensure_status();
            if state.milestones.is_none() {
                state.load_milestones();
            }
        }
        Route::Confidence | Route::Patch | Route::Scan => state.ensure_status(),
        Route::Project(name) => {
            state.ensure_status();
            // 注册表里没有这个项目时不要打 3 条必然失败的引擎命令；
            // 页面本身会渲染「仓库不存在」。
            if state.project(name).is_some() {
                // 先强制重探产物（产物可能在上次访问之后才生成），
                // 再加载详情 —— 详情的 artifacts 读同一份新鲜缓存。
                state.probe_all_artifacts(name);
                state.load_project_detail(name, false);
            }
        }
        Route::Settings(_) | Route::Agent => {}
    }
}
