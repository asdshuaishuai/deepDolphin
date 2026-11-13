// board.rs — 看板：按**客户端推导**的四列分组渲染项目卡。
//
// 归属：boardconf 组。数据源只有一个：`AppState.projects()`（`status --json`），
// 不在本页重算引擎已经给出的数字，也不另打一条引擎命令。
//
// 【四列与判据（顺序即优先级）】
//   1. 待你动手   —— `models::board_column` 给出 Pending（有未提交 / 未跟踪 / stash）；
//   2. 读不出来   —— 项目采集失败（`error`）或进度库降级（`storeHealth != "ok"`）；
//   3. 活跃       —— `board_column` 给出 Active（最近 7 天内有提交）；
//   4. 闲置       —— 其余（`board_column` 的 Stale / Other：>30 天、时间读不出来、非 git）。
//
// ⚠️ 「读不出来」为什么单独一列，而不是并进「闲置」：
//   采集失败的项目 **不是** 「很久没动」的项目。把它们并进闲置会让看板说一句
//   「这个项目很闲」——而真相是「这个项目根本没被读出来」。两者混在一列时，
//   列计数也会把「未知」算成「闲置」，正好违反 AGENTS 里「读不出来 ≠ 没有」。
//   这里**只**在 Pending/Active 之前插一档「不可读」；Pending/Active/Stale 的判定
//   仍然全部委托给 `models::board_column`，没有在页面里重写第二份判据。
//   字段级读不出来（`dirty` 缺键、`untracked = -1`）**不**把项目挪列，
//   而是在卡片上带「读不出来」chip —— 不能因为一个字段没读到就把整张卡搬走。
//
// 【计数】列头计数与列内行数来自**同一个 Vec**（`rows.len()`），不存在两套口径。
//   搜索会先筛再分组，因此列计数是「筛选后」的；页头另发全局 `pending_count`，
//   并在筛选时明确写出「筛选后 X / 共 Y」，避免读者把筛选后的 0 当成全局 0。
//
// 【交互】卡片 hover / 整卡点击进入项目；卡内按钮 `stop_propagation`，避免
//   「点浅更新却跳进了项目页」。空列不写「暂无」，而是写这一列的判据。
//   本阶段没有后台线程：批量更新会同步阻塞窗口，按钮旁如实说明。

#![allow(dead_code)]

use crate::app::{Action, AppAction, AppRoot, AppState, RefreshScope, Route};
use crate::models::{self, BoardColumn, Project, Reading, Tone};
use blenderui::prelude::*;

/// 看板页的临时 UI 状态。本阶段筛选/搜索状态由 core 的 `AppState.ui.board`
/// （`BoardFilters`）持有；本结构保留给后续「列折叠/拖拽」这类本页私有状态。
#[derive(Debug, Clone, Default)]
pub struct BoardUi {}

#[derive(Debug, Clone)]
pub enum BoardAction {
    /// 重新读取 status（与其他页的「刷新」同源）。
    Refresh,
    /// 清空搜索（空查询 = 显示全部）。
    ClearQuery,
    /// 整卡点击：进入项目工作区。
    OpenProject(String),
    /// 浅/深更新（一律先走 core 的确认弹层，不在这里直接写）。
    AskUpdate { project: Option<String>, deep: bool },
    /// 复制项目路径（路径对 agent / 终端有用）。
    CopyPath(String),
}

pub fn reduce(state: &mut AppState, action: BoardAction) {
    match action {
        BoardAction::Refresh => {
            state.dispatch(Action::App(AppAction::Refresh(RefreshScope::All)));
        }
        BoardAction::ClearQuery => {
            state.dispatch(Action::App(AppAction::SetBoardQuery(String::new())));
        }
        BoardAction::OpenProject(name) => {
            // 只改路由；项目详情由 core 的 `on_enter_route` 负责加载。
            state.navigate(Route::Project(name));
        }
        BoardAction::AskUpdate { project, deep } => {
            // 写操作必须确认；core 的确认弹层会点名项目并说明会改写托管文档。
            state.dispatch(Action::App(AppAction::AskUpdate { project, deep }));
        }
        BoardAction::CopyPath(path) => {
            state.copy(&path, "项目路径");
        }
    }
}

pub fn on_enter(state: &mut AppState) {
    // 看板只需要 status；不额外打引擎。
    // ⚠️ 本阶段 core 的 `on_enter_route` 还没有调用各页面的 `on_enter`
    // （见 views/mod.rs 的 Route::Board 分支），所以看板首屏依赖 bootstrap
    // 已经预取到的 status；这里保留幂等的兜底，供后续接入。
    state.ensure_status();
}

// ══════════════════════════════════════════════════════════════════════
// 渲染
// ══════════════════════════════════════════════════════════════════════

/// 客户端的看板分组。与 `models::BoardColumn` 的区别只有一条：
/// **不可读先于 Pending**（见文件头注释），其余分支原样委托。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Group {
    Pending,
    Unreadable,
    Active,
    Idle,
}

fn group_of(p: &Project) -> Group {
    if !p.is_readable() || (!p.store_health.is_empty() && p.store_health != "ok") {
        return Group::Unreadable;
    }
    match models::board_column(p) {
        BoardColumn::Pending => Group::Pending,
        BoardColumn::Active => Group::Active,
        // Stale（>30 天）与 Other（时间读不出来/非 git）都落在「闲置」，
        // 但卡片上会分别带「久未更新 N 天」/「时间读不出来」chip，
        // 不允许把两者悄悄合并成同一种「闲着」。
        BoardColumn::Stale | BoardColumn::Other => Group::Idle,
    }
}

/// 看板卡的状态点颜色。**按看板自己的分组取色**，不直接用 `status_tone`：
/// 一个只有未跟踪文件的项目在 core 的 `status_tone` 里是 Ok（它只看 dirty.total），
/// 却会被 `is_pending` 放进「待你动手」—— 绿点 + 待处理列是自相矛盾的。
/// 颜色只是展示层，不是第二份判据：分组仍由 `group_of`（即 `board_column`）决定。
fn group_tone(p: &Project) -> Tone {
    match group_of(p) {
        Group::Pending => Tone::Warn,
        Group::Unreadable => Tone::Err,
        Group::Active => Tone::Ok,
        Group::Idle => {
            if p.stale_days_now() > 30 {
                Tone::Stale
            } else {
                Tone::Idle
            }
        }
    }
}

pub fn render(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let all: Vec<Project> = state.projects().to_vec();
    let total = all.len();
    let pending_all = models::pending_count(&all);
    let query = state.ui.board.query.trim().to_string();

    let filtered: Vec<Project> = all
        .iter()
        .filter(|p| state.ui.board.matches(p))
        .cloned()
        .collect();

    let mut pending: Vec<&Project> = Vec::new();
    let mut unreadable: Vec<&Project> = Vec::new();
    let mut active: Vec<&Project> = Vec::new();
    let mut idle: Vec<&Project> = Vec::new();
    for p in &filtered {
        match group_of(p) {
            Group::Pending => pending.push(p),
            Group::Unreadable => unreadable.push(p),
            Group::Active => active.push(p),
            Group::Idle => idle.push(p),
        }
    }

    // 「还没读到」与「读不出来」与「真的没有」是三种状态，页头先分开说。
    let sub = if state.status.is_none() {
        if state.error.is_some() {
            "项目清单读不出来".to_string()
        } else {
            "正在读取项目清单…".to_string()
        }
    } else if query.is_empty() {
        format!(
            "{total} 个项目 · 待你动手 {pending_all}（未提交 / 未跟踪 / stash）"
        )
    } else {
        format!(
            "筛选「{query}」：{}/{} 个项目 · 待你动手 {pending_all}（全局，不受筛选影响）",
            filtered.len(),
            total
        )
    };

    let mut body = div().class("stack");

    // 读取失败 / 刷新失败：两种状态分开说。
    // status 还在时，页面显示的是**上一次读到的数据**，不能把刷新失败说成「没有项目」。
    if let Some(err) = &state.error {
        let text = if total == 0 {
            format!("项目清单读不出来：{err}")
        } else {
            format!(
                "刷新失败；下面显示的是上一次读到的 {total} 个项目，可能已经过期：{err}"
            )
        };
        body = body.child(read_error_banner(text, cx));
    }

    // 无项目：这是「真的没有」，不是「读不出来」（后者上面那条 banner 已经说了）。
    if total == 0 && state.error.is_none() && state.status.is_some() {
        body = body.child(
            div()
                .class("empty")
                .child(div().class("empty-icon").child("▦"))
                .child(div().class("empty-title").child("还没有注册任何项目"))
                .child(div().class("empty-body").child(
                    "看板只显示已注册项目。先去「扫描与添加」注册一个目录，或检查引擎是否已读取注册表。",
                ))
                .child(
                    div()
                        .class("row-sm")
                        .child(board_btn(
                            "去扫描与添加 →",
                            "btn btn-sm btn-accent",
                            "board-empty-scan",
                            Action::App(AppAction::Navigate(Route::Scan)),
                            cx,
                        )),
                ),
        );
    }

    if total == 0 && state.status.is_none() && state.error.is_none() {
        body = body.child(
            div()
                .class("card")
                .child(div().class("card-title").child("正在读取项目清单…"))
                .child(div().class("skeleton-line"))
                .child(div().class("skeleton-line")),
        );
    }

    body = body.child(filter_card(&query, filtered.len(), total, cx));

    // 顶部动作 + 口径说明。
    let mut actions = div().class("row-wrap");
    actions = actions.child(board_btn(
        "全部浅更新…",
        "btn btn-accent",
        "board-update-all",
        Action::Board(BoardAction::AskUpdate {
            project: None,
            deep: false,
        }),
        cx,
    ));
    actions = actions.child(board_btn(
        "刷新",
        "btn",
        "board-refresh",
        Action::Board(BoardAction::Refresh),
        cx,
    ));
    actions = actions.child(div().class("spacer"));
    actions = actions.child(div().class("t-caption").child(
        "计数 = 本列行数（同一份筛选结果）；「待你动手」按客户端判据计算，不读引擎的 dirty 汇总。",
    ));
    body = body.child(actions);

    body = body.child(div().class("t-caption").child(
        "本阶段没有后台线程：浅/深更新会同步阻塞窗口直到引擎返回；更新会改写托管文档（引擎会留备份），所以一律先确认。",
    ));

    body = body.child(
        div()
            .class("board")
            .child(board_column_view(
                "pending",
                "待你动手",
                "有未提交、未跟踪文件或 stash。读不出来的脏度不算「有改动」。",
                Tone::Warn,
                &pending,
                cx,
            ))
            .child(board_column_view(
                "unreadable",
                "读不出来",
                "项目采集失败（error）或进度库降级（storeHealth≠ok）。这不是「闲置」，是「没读到」。字段级失败仍留在原列并带 chip。",
                Tone::Err,
                &unreadable,
                cx,
            ))
            .child(board_column_view(
                "active",
                "活跃",
                "最近 7 天内有提交（引擎的 staleDays 0–7）。",
                Tone::Ok,
                &active,
                cx,
            ))
            .child(board_column_view(
                "idle",
                "闲置",
                "其余：8–30 天无提交、>30 天未更新（卡上标出天数）、提交时间读不出来、非 git 项目。",
                Tone::Idle,
                &idle,
                cx,
            )),
    );

    crate::views::page_shell(state, "看板", sub, cx, body)
}

// ══════════════════════════════════════════════════════════════════════
// 搜索 / 列 / 卡片
// ══════════════════════════════════════════════════════════════════════

fn filter_card(query: &str, shown: usize, total: usize, cx: &mut Context<AppRoot>) -> Div {
    let mut field = div().class("field grow");
    field = field.child(div().class("field-label").child("搜索项目"));
    let mut boxed = div().class("field-box").child(
        input()
            .class("input")
            // 稳定 id：否则每帧重建会丢焦点/光标（PLAN §1.2 第 13 条）。
            .id("board-search")
            .placeholder("项目名或摘要")
            .value(query.to_string())
            .on_input(cx.listener(|this, e: &blenderui::ChangeEvent, _, cx| {
                this.state
                    .dispatch(Action::App(AppAction::SetBoardQuery(e.value.clone())));
                cx.notify();
            })),
    );
    if !query.is_empty() {
        boxed = boxed.child(board_btn(
            "清除",
            "btn btn-sm btn-ghost",
            "board-clear-query",
            Action::Board(BoardAction::ClearQuery),
            cx,
        ));
    }
    field = field.child(boxed);
    field = field.child(div().class("field-hint").child(
        "匹配项目名或摘要；空查询显示全部。搜索只影响看板列，不改顶部「待你动手」的总数。",
    ));

    let mut row = div().class("row-wrap").child(field);
    if !query.is_empty() {
        row = row.child(div().class("chip chip-sm accent").child(format!(
            "筛选后 {shown} / {total}"
        )));
    }
    div().class("card").child(row)
}

fn board_column_view(
    key: &'static str,
    title: &'static str,
    criteria: &'static str,
    tone: Tone,
    rows: &[&Project],
    cx: &mut Context<AppRoot>,
) -> Div {
    // 计数与行数同源：都来自 rows。
    let mut col = div()
        .class("board-col")
        .id(format!("board-col-{key}"))
        .child(
            div()
                .class("board-col-head")
                .child(div().class(format!("dot {}", tone.class())))
                .child(div().class("t-h3").child(title))
                .child(
                    div()
                        .class("board-col-count")
                        .child(format!("{}", rows.len())),
                ),
        )
        .child(div().class("board-col-criteria").child(criteria));

    if rows.is_empty() {
        // 空列写**判据**，不写「暂无」：读者需要知道「为什么这里会空」。
        col = col.child(
            div()
                .class("empty")
                .child(div().class("empty-icon").child("○"))
                .child(div().class("empty-title").child("没有项目落在这一列"))
                .child(
                    div()
                        .class("empty-body")
                        .child(format!("判据：{criteria}")),
                ),
        );
    } else {
        for p in rows {
            col = col.child(board_card(p, cx));
        }
    }
    col
}

fn board_card(p: &Project, cx: &mut Context<AppRoot>) -> Div {
    let tone = group_tone(p);
    let name = p.name.clone();
    let route_name = name.clone();

    // 卡片头只放点 + 名称 + 分支。**不渲染 `status_word`**：
    // 它对「只有未跟踪文件」的项目会说「干净」，而看板把它放在「待你动手」列，
    // 并排出现就是自相矛盾。具体事实由下面的 chips 逐条说明。
    let mut head = div()
        .class("row-sm")
        .child(div().class(format!("dot {}", tone.class())))
        .child(
            div()
                .class("t-title t-ellipsis grow")
                .title(name.clone())
                .child(name.clone()),
        );
    if let Some(branch) = p.current_branch.as_ref().filter(|b| !b.trim().is_empty()) {
        head = head.child(
            div()
                .class("chip chip-sm idle t-ellipsis")
                .title(branch.to_string())
                .child(format!("⎇ {branch}")),
        );
    } else if p.is_git() {
        // 缺键不是「没有分支」；对一个 git 项目说「分支未知」比留空诚实。
        head = head.child(div().class("chip chip-sm unknown").child("分支未知"));
    }

    let headline = p
        .headline
        .clone()
        .filter(|h| !h.trim().is_empty())
        .unwrap_or_else(|| {
            if p.error.is_some() {
                "读不出来".to_string()
            } else {
                "暂无摘要".to_string()
            }
        });

    let mut card = div()
        .class("board-card")
        .id(format!("board-card-{name}"))
        .child(head)
        .child(div().class("t-body t-clamp-2").child(headline));

    // 采集失败原因原样显示；空白的「读不出来」等于什么都没说。
    if let Some(err) = &p.error {
        card = card.child(
            div()
                .class("banner err")
                .child(div().class("banner-body").child(format!("读不出来：{err}"))),
        );
    }

    card = card.child(chip_row(p));

    // 脏文件清单：Known 才报；NotRead 明说「不是没有改动」。
    card = card.child(dirty_files_line(p));

    // 披露（warnings）只取第一条 + 计数，避免卡片被长文本撑开。
    if let Some(ws) = p.warnings.as_ref().filter(|w| !w.is_empty()) {
        let mut text = format!("引擎披露：{}", ws[0]);
        if ws.len() > 1 {
            text.push_str(&format!("（还有 {} 条）", ws.len() - 1));
        }
        card = card.child(
            div()
                .class("t-caption unknown")
                .title(ws.join("\n"))
                .child(text),
        );
    }

    // 路径：等宽、可点击复制。嵌套点击必须 stop_propagation，
    // 否则复制路径会同时把整张卡点进项目页。
    let path = p.path.clone();
    if !path.is_empty() {
        card = card.child(
            div()
                .class("path")
                .child(div().class("path-text").title(path.clone()).child(path.clone()))
                .on_click(cx.listener(move |this, _, _window, cx| {
                    cx.stop_propagation();
                    this.state
                        .dispatch(Action::Board(BoardAction::CopyPath(path.clone())));
                    cx.notify();
                })),
        );
    }

    let mut foot = div().class("card-foot");
    foot = foot.child(board_btn(
        "浅更新…",
        "btn btn-sm",
        format!("board-update-{name}"),
        Action::Board(BoardAction::AskUpdate {
            project: Some(name.clone()),
            deep: false,
        }),
        cx,
    ));
    if p.is_git() {
        foot = foot.child(board_btn(
            "深更新…",
            "btn btn-sm btn-ghost",
            format!("board-deep-{name}"),
            Action::Board(BoardAction::AskUpdate {
                project: Some(name.clone()),
                deep: true,
            }),
            cx,
        ));
    }
    foot = foot.child(div().class("spacer"));
    foot = foot.child(board_btn(
        "详情 →",
        "btn btn-sm btn-accent",
        format!("board-open-{name}"),
        Action::Board(BoardAction::OpenProject(name.clone())),
        cx,
    ));
    card = card.child(foot);

    // 整卡点击：进入项目概览。卡内按钮已 stop_propagation。
    card.on_click(cx.listener(move |this, _, _, cx| {
        this.state
            .dispatch(Action::Board(BoardAction::OpenProject(route_name.clone())));
        cx.notify();
    }))
}

/// 卡片上的事实 chips。每条只回答一个问题，读不出来就不报 0。
fn chip_row(p: &Project) -> Div {
    let mut row = div().class("row-wrap");

    // 结构化脏度
    match p.dirty_state() {
        Reading::Known(d) if d.total > 0 => {
            row = row.child(chip_text(format!("未提交 {}", d.total), Tone::Warn));
        }
        Reading::Known(_) => {}
        Reading::NotRead => {
            row = row.child(chip_text("脏度读不出来".to_string(), Tone::Unknown));
        }
    }

    if p.is_git() {
        match models::read_opt_i64(p.untracked_count) {
            Reading::Known(n) if n > 0 => {
                row = row.child(chip_text(format!("未跟踪 {n}"), Tone::Warn));
            }
            Reading::Known(_) => {}
            Reading::NotRead => {
                let text = if p.untracked_error.trim().is_empty() {
                    "未跟踪数读不出来".to_string()
                } else {
                    format!("未跟踪数读不出来：{}", p.untracked_error)
                };
                row = row.child(chip_text(text, Tone::Unknown));
            }
        }
        match models::read_opt_i64(p.stash_count) {
            Reading::Known(n) if n > 0 => {
                row = row.child(chip_text(format!("stash {n}"), Tone::Info));
            }
            Reading::Known(_) => {}
            Reading::NotRead => {
                row = row.child(chip_text("stash 数读不出来".to_string(), Tone::Unknown));
            }
        }
        match models::read_opt_i64(p.worktree_count) {
            Reading::Known(n) if n > 0 => {
                row = row.child(chip_text(format!("worktree {n}"), Tone::Info));
            }
            Reading::Known(_) => {}
            Reading::NotRead => {
                row = row.child(chip_text(
                    "worktree 数读不出来".to_string(),
                    Tone::Unknown,
                ));
            }
        }
        match models::read_opt_i64(p.commit_count) {
            Reading::Known(n) => {
                row = row.child(chip_text(format!("提交 {n}"), Tone::Idle));
            }
            Reading::NotRead => {
                row = row.child(chip_text("提交数读不出来".to_string(), Tone::Unknown));
            }
        }
    }

    // 待记录提交：基线重置后数字没有意义，只报「已重置」。
    if let Some(b) = p.current_branch_entry() {
        if b.baseline_reset {
            row = row.child(chip_text("基线已重置".to_string(), Tone::Info));
        } else {
            match models::read_i64(b.pending_commits) {
                Reading::Known(n) if n > 0 => {
                    row = row.child(chip_text(format!("待记录 {n}"), Tone::Info));
                }
                Reading::Known(_) => {}
                Reading::NotRead => {
                    row = row.child(chip_text(
                        "待记录数读不出来".to_string(),
                        Tone::Unknown,
                    ));
                }
            }
        }
    }

    // 停滞 / 时间读不出来：这是「闲置」列内部的两种不同事实。
    let days = p.stale_days_now();
    if days > 30 {
        row = row.child(chip_text(format!("久未更新 {days} 天"), Tone::Stale));
    } else if days < 0 {
        row = row.child(chip_text("提交时间读不出来".to_string(), Tone::Unknown));
    }

    if !p.is_git() {
        row = row.child(chip_text("非 git".to_string(), Tone::Idle));
    }
    if !p.store_health.is_empty() && p.store_health != "ok" {
        row = row.child(chip_text(
            format!("进度库降级：{}", p.store_health),
            Tone::Err,
        ));
    }
    row
}

fn dirty_files_line(p: &Project) -> Div {
    match p.dirty_state() {
        Reading::Known(d) if !d.files.is_empty() => {
            let shown: Vec<String> = d.files.iter().take(3).cloned().collect();
            let mut text = format!("改动：{}", shown.join(" · "));
            if d.files.len() > shown.len() {
                text.push_str(&format!("（还有 {} 个）", d.files.len() - shown.len()));
            }
            div()
                .class("t-caption mono t-ellipsis")
                .title(d.files.join("\n"))
                .child(text)
        }
        Reading::Known(_) => div().class("t-caption").child("无未提交文件"),
        Reading::NotRead => div()
            .class("t-caption unknown")
            .child("改动清单读不出来（不是「没有改动」）"),
    }
}

// ══════════════════════════════════════════════════════════════════════
// 小件
// ══════════════════════════════════════════════════════════════════════

fn chip_text(text: String, tone: Tone) -> Div {
    div()
        .class(format!("chip chip-sm {}", tone.class()))
        .child(text)
}

fn read_error_banner(text: String, cx: &mut Context<AppRoot>) -> Div {
    div()
        .class("banner err")
        .child(div().class("banner-title").child("读取失败（不是「没有项目」）"))
        .child(div().class("banner-body").child(text))
        .child(
            div().class("banner-action").child(board_btn(
                "重试",
                "btn btn-sm btn-accent",
                "board-retry",
                Action::Board(BoardAction::Refresh),
                cx,
            )),
        )
}

fn board_btn(
    label: &str,
    classes: &str,
    id: impl Into<SharedString>,
    action: Action,
    cx: &mut Context<AppRoot>,
) -> Div {
    div()
        .class(classes.to_string())
        .id(id)
        .child(label.to_string())
        .on_click(cx.listener(move |this, _, _window, cx| {
            // 卡内按钮：别把点击冒泡给整卡（否则「浅更新」会顺带跳进项目页）。
            cx.stop_propagation();
            this.state.dispatch(action.clone());
            cx.notify();
        }))
}
