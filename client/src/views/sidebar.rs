// sidebar.rs — 侧栏：品牌头 / 固定视图 / 仓库列表 / 引擎状态脚。

use crate::app::{AppRoot, AppState, Route};
use crate::views::status_dot;
use blenderui::prelude::*;

pub fn render(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let projects = state.projects().to_vec();

    let mut list = div().class("sidebar-scroll");
    list = list.child(div().class("sect-label").child("视图"));
    list = list.child(nav_item("仪表盘", "▦", Route::Dashboard, state, cx));
    list = list.child(nav_item("里程碑", "⚑", Route::Milestones, state, cx));
    list = list.child(div().class("sect-label").child(format!("仓库（{}）", projects.len())));

    for p in &projects {
        let (color, _word) = status_dot(p);
        let on = matches!(&state.route, Route::Project(n) if n == &p.name);
        let name = p.name.clone();
        let dirty = p.user_dirty_count.unwrap_or(0) + p.untracked_count.unwrap_or(0);
        let mut item = div()
            .id(format!("proj-{}", p.name))
            .class(if on { "nav-item on" } else { "nav-item" })
            .child(div().class("dot").style(format!("background: {color};")))
            .child(div().style("flex: 1; overflow: hidden; white-space: nowrap;").child(p.name.clone()));
        if dirty > 0 {
            item = item.child(
                div()
                    .class("dim")
                    .style("font-size: 11px; color: #FFB454;")
                    .child(format!("●{dirty}")),
            );
        }
        list = list.child(item.on_click(cx.listener(move |this, _, _, cx| {
            this.state.select(Route::Project(name.clone()));
            cx.notify();
        })));
    }

    div()
        .class("sidebar")
        .child(
            div()
                .class("sidebar-head")
                .child(div().class("brand").child("deepDolphin"))
                .child(div().class("brand-sub").child("moonGit · 项目群进度引擎")),
        )
        .child(list)
        .child(
            div()
                .class("sidebar-foot")
                .child(div().class("row").child(div().class("dot").style("background: #3FCF8E;")).child(div().class("dim").child("引擎已就绪")))
                .child(div().class("dim").style("font-size: 10px; overflow: hidden; white-space: nowrap;").child(state.last_refresh_note.clone())),
        )
}

fn nav_item(label: &str, icon: &str, route: Route, state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let on = state.route == route;
    let r = route.clone();
    div()
        .id(format!("nav-{label}"))
        .class(if on { "nav-item on" } else { "nav-item" })
        .on_click(cx.listener(move |this, _, _, cx| {
            this.state.select(r.clone());
            cx.notify();
        }))
        .child(div().style("width: 16px; color: #7FA6E8;").child(icon.to_string()))
        .child(label.to_string())
}
