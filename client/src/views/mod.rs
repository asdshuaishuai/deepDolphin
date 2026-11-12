// views/mod.rs — 视图模块。

pub mod dashboard;
pub mod milestones;
pub mod project;
pub mod sidebar;

use crate::app::AppState;
use crate::models::Project;
use blenderui::prelude::*;

/// 状态点：读不出来=红（那是故障）、有未提交=橙、正常=绿。
/// 不猜「健康度」——只按引擎给的事实三档。
pub fn status_dot(p: &Project) -> (String, &'static str) {
    if p.error.is_some() {
        ("#FF6B81".to_string(), "读不出来")
    } else if p.user_dirty_count.unwrap_or(0) > 0 || p.untracked_count.unwrap_or(0) > 0 {
        ("#FFB454".to_string(), "有未提交改动")
    } else {
        ("#3FCF8E".to_string(), "干净")
    }
}

/// 顶部反馈 banner（成功灰绿/失败红）。`dismiss` 由点击关闭。
pub fn feedback_banner(state: &AppState) -> Div {
    let el = match &state.feedback {
        Some(f) => {
            let class = if f.ok { "banner ok" } else { "banner err" };
            div()
                .class(class)
                .id("feedback")
                .child(f.text.clone())
        }
        None => div().id("feedback"),
    };
    el
}

/// 数字统计小件（大数字 + 说明）。
pub fn metric(label: &str, value: String, hint: &str) -> Div {
    div()
        .class("card")
        .child(div().class("muted").child(label.to_string()))
        .child(div().class("metric").child(value))
        .child(div().class("dim").child(hint.to_string()))
}
