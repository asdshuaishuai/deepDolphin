// project.rs — 项目工作区（六个标签）。
//
// 标签：概览 / 分支 / 日志 / 文档 / 里程碑 / 图谱。
// 页面只读 `&AppState`；动作一律经 `AppState` 的方法或 `AppAction` 回灌，
// 视图里不 spawn 进程、不解析 JSON、不写文件。
//
// 【诚实边界（本页的判据）】
//   · `-1`、缺键、`dirty:{}`、`overall:{}` 都渲染成「读不出来」，不是 0 / 干净；
//   · `branches: []` **不等于**「没有分支」——必须与 currentBranch / repoBranchCount
//     交叉说明（实测 deepGit：repoBranchCount=1、branches=[]）；
//   · journal `commitCount` 的口径随条目（new / repoTotal / 未知），绿色只给真增量；
//   · 里程碑 `unknown` 单列「无法核验」，绝不塌成「进行中」；
//   · 文档的「缺失」「读不出来」「还没建」是三种状态，不合并；
//   · 产物探测失败 ≠ 未生成（`Load::Failed` 与 `Ready{exists:false}` 分开）。
//
// 【commit_sheet 的挂载】`views/mod.rs` 由 core 冻结，未声明 commit_sheet 模块；
// 这里用 `#[path]` 把它作为 project 的子模块挂上（文件仍是
// `src/views/commit_sheet.rs`），不改 mod.rs。

#[path = "commit_sheet.rs"]
mod commit_sheet;

use crate::app::{
    AppAction, AppRoot, AppState, Confirm, Load, OpenTarget, PendingAction, ProjectTab, Reading,
    RefreshScope, Route, Tone,
};
use crate::engine::{redact_url, Artifact, GitOp, MilestoneOp};
use crate::models::{
    read_i64, read_opt_i64, short_iso, status_tone, status_word, Branch, JournalEntry, Milestone,
    Project, RenderCheck,
};
use crate::views::{feedback_block, scroll_id};
use blenderui::prelude::*;
use std::collections::BTreeMap;

/// 引擎**默认**的托管文档名单（`kernel/config.cj:32-33` 的
/// `docs` ∪ `agentDocCandidates`，与 `kernel/render.cj:42` 的
/// `DEEPGIT_MANAGED_DOCS` 同集合）。
///
/// ⚠️ 这是客户端**推断缺失项**用的名字，不是引擎发来的事实：
/// `status.docs` 只列**已存在**的文档（`flow/status.cj:180-186`），
/// `docs` 命令也只返回读得到的文件；引擎没有「托管名单」出口。
/// 因此这里的「缺失」只在项目使用默认名单时成立 —— UI 必须把这句话说出来。
const DEFAULT_MANAGED_DOCS: [&str; 4] = ["README.md", "AGENTS.md", "AGENT.md", "CLAUDE.md"];

// ══════════════════════════════════════════════════════════════════════
// 入口
// ══════════════════════════════════════════════════════════════════════

pub fn render(state: &AppState, name: &str, cx: &mut Context<AppRoot>) -> Div {
    let Some(p) = state.project(name) else {
        // status 不含这个项目有三种原因：真的没注册、注册了但被停用、
        // 注册了但这次采集/列表没返回。注册表能区分前两种，别一律说「不存在」。
        let registry_note = match &state.registry {
            Load::Ready(list) => match list.iter().find(|e| e.name == name) {
                Some(e) if e.disabled => format!(
                    "「{name}」已在注册表里，但被标记为停用（disabled）；status 不会列出停用项目。"
                ),
                Some(_) => format!(
                    "「{name}」在注册表里，但 status 没有返回它 —— 可能采集失败或列表被截断；这不是「仓库不存在」。"
                ),
                None => format!(
                    "注册表里没有「{name}」。它可能已被移除，或引擎还没读到注册表。"
                ),
            },
            Load::Failed(e) => format!(
                "注册表读不出来（{}）—— 无法判断「{name}」是没注册、被停用，还是 status 没返回。",
                e.user_message()
            ),
            Load::Idle | Load::Loading => format!(
                "注册表还没加载完 —— 无法判断「{name}」是没注册还是状态列表没返回。"
            ),
        };
        return div()
            .class("main")
            .child(
                div()
                    .class("main-head glass")
                    .child(
                        div()
                            .class("main-head-main")
                            .child(div().class("main-title").child("项目不在状态列表里"))
                            .child(
                                div()
                                    .class("main-sub")
                                    .child(format!("status 里没有「{name}」")),
                            ),
                    ),
            )
            .child(
                div()
                    .class("main-scroll")
                    .id(scroll_id(state))
                    .child(feedback_block(state, cx))
                    .child(tone_banner(Tone::Err, "没有可展示的项目状态", registry_note))
                    .child(
                        div()
                            .class("row-wrap")
                            .child(
                                div()
                                    .class("btn")
                                    .id("proj-back")
                                    .child("返回仪表盘")
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.state.navigate(Route::Dashboard);
                                        cx.notify();
                                    })),
                            )
                            .child(
                                div()
                                    .class("btn btn-ghost")
                                    .id("proj-refresh-registry")
                                    .child("刷新全部")
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.state.refresh_scope(RefreshScope::All);
                                        cx.notify();
                                    })),
                            ),
                    ),
            );
    };

    let head = header(p, cx);
    let tabs = tab_bar(state, p, cx);
    let body = match state.project_tab {
        ProjectTab::Overview => overview(state, p, cx),
        ProjectTab::Branches => branches_tab(state, p, cx),
        ProjectTab::Journal => journal_tab(state, p, cx),
        ProjectTab::Docs => docs_tab(state, p, cx),
        ProjectTab::Milestones => milestones_tab(state, p, cx),
        ProjectTab::Graph => graph_tab(state, p, cx),
    };
    let scroll = div()
        .class("main-scroll")
        .id(scroll_id(state))
        .child(feedback_block(state, cx))
        .child(body);

    let mut root = div().class("main").child(head).child(tabs).child(scroll);

    // 提交弹层挂在本页（project 组负责）。它是全应用唯一一份：
    // 根视图里曾经还有一份 v0 副本，两份 overlay 叠在同一份 `commit_sheet` 上。
    let sheet_is_this_project = state
        .commit_sheet
        .as_ref()
        .map(|s| s.project == name)
        .unwrap_or(false);
    if sheet_is_this_project {
        if let Some(sheet) = commit_sheet::render(state, cx) {
            root = root.child(sheet);
        }
    }
    root
}

// ══════════════════════════════════════════════════════════════════════
// 页头与标签
// ══════════════════════════════════════════════════════════════════════

fn header(p: &Project, cx: &mut Context<AppRoot>) -> Div {
    let tone = status_tone(p);
    let word = status_word(p);
    let kind = if p.kind.trim().is_empty() {
        "类型未知".to_string()
    } else {
        p.kind.clone()
    };
    let path_title = p.path.clone();
    let path_short = if p.path.trim().is_empty() {
        "路径读不出来".to_string()
    } else {
        p.path.clone()
    };

    let mut actions = div().class("main-actions");

    let project = p.name.clone();
    actions = actions.child(
        div()
            .class("btn btn-ghost btn-sm")
            .id("proj-refresh")
            .child("刷新")
            .on_click(cx.listener(move |this, _, _, cx| {
                this.state
                    .refresh_scope(RefreshScope::Project(project.clone()));
                // 里程碑是全局列表，项目页的刷新也应带上它。
                this.state.load_milestones();
                this.state.toast(Tone::Ok, "已刷新", project.clone());
                cx.notify();
            })),
    );

    let disabled = p.error.is_some();
    let project_shallow = p.name.clone();
    let shallow = div()
        .class(if disabled {
            "btn btn-sm is-disabled"
        } else {
            "btn btn-sm"
        })
        .id("proj-update-shallow")
        .child("浅更新");
    actions = actions.child(if disabled {
        shallow.title("项目读不出来：更新大概率也会失败")
    } else {
        shallow.on_click(cx.listener(move |this, _, _, cx| {
            this.state
                .ask_update(Some(project_shallow.clone()), false);
            cx.notify();
        }))
    });

    let project_deep = p.name.clone();
    let deep = div()
        .class(if disabled {
            "btn btn-sm is-disabled"
        } else {
            "btn btn-sm"
        })
        .id("proj-update-deep")
        .child("深更新");
    actions = actions.child(if disabled {
        deep.title("项目读不出来：更新大概率也会失败")
    } else {
        deep.on_click(cx.listener(move |this, _, _, cx| {
            this.state.ask_update(Some(project_deep.clone()), true);
            cx.notify();
        }))
    });

    // 提交是仓库页最高频的写操作，放在页头；弹层本身在 commit_sheet.rs。
    let project_commit = p.name.clone();
    let commit_enabled = p.is_git() && !disabled;
    let commit_btn = div()
        .class(if commit_enabled {
            "btn btn-sm btn-accent"
        } else {
            "btn btn-sm btn-accent is-disabled"
        })
        .id("proj-header-commit")
        .child("提交…");
    actions = actions.child(if commit_enabled {
        commit_btn.on_click(cx.listener(move |this, _, _, cx| {
            this.state.open_commit_sheet(&project_commit);
            cx.notify();
        }))
    } else {
        commit_btn.title(if p.is_git() {
            "项目读不出来：提交弹层仍会显示 git status 的真实失败原因"
        } else {
            "非 git 仓库：没有可提交的改动"
        })
    });

    let path_copy = p.path.clone();
    actions = actions.child(
        div()
            .class("btn btn-ghost btn-sm")
            .id("proj-copy-path")
            .child("复制路径")
            .on_click(cx.listener(move |this, _, _, cx| {
                this.state.copy(&path_copy, "项目路径");
                cx.notify();
            })),
    );

    if !p.path.trim().is_empty() {
        let path_open = p.path.clone();
        actions = actions.child(
            div()
                .class("btn btn-ghost btn-sm")
                .id("proj-reveal")
                .child("打开目录")
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state
                        .apply(AppAction::Open(OpenTarget::Reveal(path_open.clone())));
                    cx.notify();
                })),
        );
    }

    if !p.remote.trim().is_empty() {
        let remote = p.remote.clone();
        actions = actions.child(
            div()
                .class("btn btn-ghost btn-sm")
                .id("proj-open-remote")
                .title(format!("远端：{}", redact_url(&p.remote)))
                .child("远端 ↗")
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state
                        .apply(AppAction::Open(OpenTarget::Url(remote.clone())));
                    cx.notify();
                })),
        );
    }

    div()
        .class("main-head glass")
        .child(
            div()
                .class("main-head-main")
                .child(
                    div()
                        .class("row-sm")
                        .child(div().class(format!("dot {}", tone.class())))
                        .child(div().class("crumb").child("项目群"))
                        .child(div().class("crumb-sep").child("/"))
                        .child(div().class("main-title").child(p.name.clone())),
                )
                .child(
                    div()
                        .class("main-sub t-ellipsis")
                        .title(path_title)
                        .child(format!("{word} · {kind} · {path_short}")),
                ),
        )
        .child(div().class("spacer"))
        .child(actions)
}

fn tab_bar(state: &AppState, p: &Project, cx: &mut Context<AppRoot>) -> Div {
    let mut bar = div().class("tabs");
    for tab in ProjectTab::all() {
        let on = state.project_tab == tab;
        let count = tab_count(state, p, tab);
        let mut item = div()
            .class(if on { "tab on" } else { "tab" })
            .id(format!("proj-tab-{}", tab.key()))
            .child(tab.title().to_string());
        if let Some(n) = count {
            item = item.child(div().class("tab-badge").child(n.to_string()));
        }
        item = item.on_click(cx.listener(move |this, _, _, cx| {
            this.state.set_project_tab(tab);
            cx.notify();
        }));
        bar = bar.child(item);
    }
    bar
}

fn tab_count(state: &AppState, p: &Project, tab: ProjectTab) -> Option<usize> {
    match tab {
        ProjectTab::Branches => {
            if p.branches.is_empty() {
                None
            } else {
                Some(p.branches.len())
            }
        }
        ProjectTab::Journal => match state.project_detail(&p.name).map(|d| &d.journal) {
            Some(Load::Ready(j)) => Some(j.entries.len()),
            _ => None,
        },
        ProjectTab::Docs => p
            .docs
            .as_ref()
            .map(|list| list.iter().filter(|d| d.exists).count()),
        ProjectTab::Milestones => state.milestones.as_ref().map(|list| {
            list.milestones
                .iter()
                .filter(|m| milestone_belongs_to(m, p))
                .count()
        }),
        _ => None,
    }
}

fn milestone_belongs_to(m: &Milestone, p: &Project) -> bool {
    m.project.as_deref() == Some(p.name.as_str())
        || (!p.id.is_empty() && m.project_id == p.id)
}

// ══════════════════════════════════════════════════════════════════════
// 概览
// ══════════════════════════════════════════════════════════════════════

fn overview(state: &AppState, p: &Project, cx: &mut Context<AppRoot>) -> Div {
    div()
        .class("stack")
        .child(summary_card(p))
        .child(current_state_card(p, cx))
        .child(composition_card(p))
        .child(git_ops_card(state, p, cx))
}

fn summary_card(p: &Project) -> Div {
    let mut card = section_card(
        "概况",
        Some(if p.path.trim().is_empty() {
            "路径读不出来".to_string()
        } else {
            p.path.clone()
        }),
    );

    let headline = p
        .headline
        .clone()
        .filter(|s| !s.trim().is_empty());
    card = card.child(div().class("t-body").child(match (headline, p.error.is_some()) {
        (_, true) => "采集失败：下面的摘要与数字都不可信".to_string(),
        (Some(h), false) => h,
        (None, false) => "暂无摘要（headline 为空）".to_string(),
    }));

    let warnings = p.warnings.clone().unwrap_or_default();
    match p.overall_state() {
        Reading::Known(o) => {
            if !o.summary.trim().is_empty() {
                card = card.child(div().class("muted").child(o.summary.clone()));
            }
            for w in &warnings {
                card = card.child(tone_banner(Tone::Warn, "引擎告警", w.clone()));
            }
            for note in &o.notes {
                if warnings.iter().any(|w| w == note) {
                    continue;
                }
                card = card.child(div().class("t-caption dim").child(format!("· {note}")));
            }
        }
        Reading::NotRead => {
            card = card.child(tone_banner(
                Tone::Unknown,
                "总体摘要读不出来",
                "引擎没有给出 overall 摘要。这不是「没有问题」——采集失败时 dirty/overall 都是空对象。",
            ));
        }
    }
    if p.warnings.is_none() {
        card = card.child(
            div()
                .class("t-caption dim")
                .child("引擎未披露 warnings 字段（不等于没有告警）"),
        );
    }
    card
}

fn current_state_card(p: &Project, cx: &mut Context<AppRoot>) -> Div {
    let mut card = section_card(
        "工程现状",
        Some("计数按引擎原值；-1 / 缺键一律「读不出来」，不当成 0".to_string()),
    );

    // ── 结构化脏度 + 各计数 ──────────────────────────────────────
    let mut chips = div().class("row-wrap");
    match p.dirty_state() {
        Reading::Known(d) => {
            let tone = if d.total > 0 { Tone::Warn } else { Tone::Ok };
            chips = chips.child(tone_chip(
                format!("未提交（含托管文档） {}", d.total),
                tone,
            ));
            if d.clean {
                chips = chips.child(tone_chip("工作区干净", Tone::Ok));
            }
            if d.staged > 0 {
                chips = chips.child(plain_chip(format!("暂存 {}", d.staged)));
            }
            if d.modified > 0 {
                chips = chips.child(plain_chip(format!("已修改 {}", d.modified)));
            }
            if d.untracked > 0 {
                chips = chips.child(plain_chip(format!("未跟踪 {}", d.untracked)));
            }
            if d.conflicts > 0 {
                chips = chips.child(tone_chip(format!("冲突 {}", d.conflicts), Tone::Err));
            }
        }
        Reading::NotRead => {
            chips = chips.child(tone_chip("结构化脏度：读不出来", Tone::Unknown));
        }
    }
    // 引擎的 userDirtyCount 与 dirty.total 口径不同（前者不含托管文档）。
    // 两个数字都显示，但各自带口径，避免读者以为它们应相等。
    chips = chips.child(count_chip("你的改动（不含托管文档）", p.user_dirty_count));
    chips = chips.child(count_chip("未跟踪文件", p.untracked_count));
    chips = chips.child(count_chip("stash", p.stash_count));
    chips = chips.child(count_chip("worktree", p.worktree_count));
    if p.is_git() {
        chips = chips.child(match read_opt_i64(p.commit_count) {
            Reading::Known(n) => plain_chip(format!("仓库提交总数 {n}")),
            Reading::NotRead => tone_chip("仓库提交总数 读不出来", Tone::Unknown),
        });
    } else {
        chips = chips.child(tone_chip("提交总数：非 git 不适用", Tone::Idle));
    }
    card = card.child(chips);

    if let Reading::NotRead = p.dirty_state() {
        if let Some(err) = p.dirty.as_ref().and_then(|d| d.err.clone()) {
            card = card.child(tone_banner(Tone::Err, "git 脏度采集失败", err));
        }
    }
    if !p.untracked_error.trim().is_empty() {
        card = card.child(tone_banner(
            Tone::Err,
            "未跟踪文件采集失败",
            format!(
                "{}（此时「0 个未跟踪文件」不代表没有）",
                p.untracked_error
            ),
        ));
    }

    // ── 最近提交 / 最近文件活动 ──────────────────────────────────
    let mut facts = div().class("stack-sm");
    let ago = p
        .last_commit_ago
        .clone()
        .filter(|s| !s.trim().is_empty());
    if p.is_git() {
        let at = if p.last_commit_at.trim().is_empty() {
            String::new()
        } else {
            short_iso(&p.last_commit_at)
        };
        let value = match (ago, at.is_empty()) {
            (Some(a), false) => format!("{a} · {at}"),
            (Some(a), true) => a,
            (None, _) => "读不出来（lastCommitAgo 缺失）".to_string(),
        };
        facts = facts.child(kv_row("最近提交", value));
    } else {
        let value = match ago {
            Some(a) => format!("{a}（非 git：这是文件活动时间，不是提交时间）"),
            None => "读不出来".to_string(),
        };
        facts = facts.child(kv_row("最近文件活动", value));
    }

    // ── 当前分支 / HEAD ─────────────────────────────────────────
    if p.is_git() {
        let mut branch_row = div().class("row-wrap");
        match p
            .current_branch
            .clone()
            .filter(|s| !s.trim().is_empty())
        {
            Some(b) => {
                branch_row = branch_row.child(tone_chip(format!("当前分支 {b}"), Tone::Accent));
            }
            None => {
                branch_row =
                    branch_row.child(tone_chip("当前分支：读不出来", Tone::Unknown));
            }
        }
        if let Some(d) = p
            .default_branch
            .clone()
            .filter(|s| !s.trim().is_empty())
        {
            if p.current_branch.as_deref() != Some(d.as_str()) {
                branch_row = branch_row.child(plain_chip(format!("默认分支 {d}")));
            }
        }
        facts = facts.child(branch_row);
        match p.current_branch_entry() {
            Some(b) if !b.head_short.trim().is_empty() => {
                let subject = if b.head_subject.trim().is_empty() {
                    "（提交标题为空）".to_string()
                } else {
                    b.head_subject.clone()
                };
                facts = facts.child(kv_row(
                    "HEAD",
                    format!("{} · {subject}", b.head_short),
                ));
            }
            Some(_) => {
                facts = facts.child(kv_row(
                    "HEAD",
                    "读不出来（当前分支没有 headShort）".to_string(),
                ));
            }
            None => {
                facts = facts.child(kv_row(
                    "HEAD",
                    "读不出来（分支明细里没有当前分支）".to_string(),
                ));
            }
        }
    } else {
        facts = facts.child(tone_chip("非 git 仓库：没有分支 / HEAD", Tone::Idle));
    }
    card = card.child(facts);

    // ── 未提交文件清单 ──────────────────────────────────────────
    if let Reading::Known(d) = p.dirty_state() {
        if d.files.is_empty() {
            if d.total > 0 {
                card = card.child(tone_banner(
                    Tone::Warn,
                    "文件清单读不出来",
                    format!(
                        "引擎报告 {} 个未提交文件，但 dirty.files 为空 —— 这不等于没有改动。",
                        d.total
                    ),
                ));
            } else {
                card = card.child(
                    div()
                        .class("t-caption dim")
                        .child("无未提交文件（dirty.files 为空且 total=0）"),
                );
            }
        } else {
            card = card.child(
                div()
                    .class("t-caption dim")
                    .child(format!("未提交文件（{}）：点击路径复制", d.files.len())),
            );
            let mut list = div().class("list");
            for f in d.files.iter().take(20) {
                list = list.child(copy_row(cx, f.clone(), "文件路径"));
            }
            card = card.child(list);
            if d.files.len() > 20 {
                card = card.child(
                    div()
                        .class("t-caption dim")
                        .child(format!("只显示前 20 个，还有 {} 个", d.files.len() - 20)),
                );
            }
        }
    }

    // ── 标签 / 清单 / 托管文档存在性 / 进度库 ───────────────────
    card = card.child(chip_list("标签", &p.tags));
    card = card.child(chip_list("清单", &p.manifests));

    let mut docs_row = div().class("row-wrap");
    docs_row = docs_row.child(div().class("t-caption dim").child("托管文档："));
    match &p.docs {
        Some(_) if p.error.is_some() => {
            docs_row = docs_row.child(tone_chip(
                "读不出来（项目采集失败）",
                Tone::Unknown,
            ));
        }
        Some(list) => {
            for d in list {
                docs_row = docs_row.child(if d.exists {
                    tone_chip(format!("{} 已建", d.file), Tone::Ok)
                } else {
                    tone_chip(format!("{} 未建", d.file), Tone::Idle)
                });
            }
            // status.docs 只报「已存在」；未建项按默认名单推断（与 docs tab 同源）。
            for f in DEFAULT_MANAGED_DOCS {
                if !list.iter().any(|d| d.file == f) {
                    docs_row = docs_row.child(tone_chip(format!("{f} 未建（推断）"), Tone::Idle));
                }
            }
        }
        None => {
            docs_row = docs_row.child(tone_chip(
                "引擎未给出托管文档清单（不是「没有」）",
                Tone::Unknown,
            ));
        }
    }
    card = card.child(docs_row);
    if p.error.is_none() && p.docs.is_some() {
        card = card.child(
            div()
                .class("t-caption dim")
                .child("未建项按引擎默认名单推断（status.docs 只报已存在；自定义 update.docs 的项目可能不准）"),
        );
    }

    let mut progress = div().class("row-wrap");
    progress = progress.child(div().class("t-caption dim").child("进度库："));
    if p.progress.last_update_at.trim().is_empty() {
        progress = progress.child(
            div()
                .class("t-caption")
                .child("没有更新记录（lastUpdateAt 为空）"),
        );
    } else {
        progress = progress.child(plain_chip(format!(
            "上次更新 {}",
            short_iso(&p.progress.last_update_at)
        )));
    }
    match read_i64(p.progress.entry_count) {
        Reading::Known(n) => {
            progress = progress.child(plain_chip(format!("进度条目 {n}")));
            if p.progress.entry_count_truncated == Some(true) {
                progress = progress.child(tone_chip(
                    format!("只保留最近 {} 条", p.progress.entries_kept),
                    Tone::Warn,
                ));
            } else if p.progress.entry_count_truncated.is_none() {
                progress = progress.child(tone_chip(
                    "引擎未披露进度条目是否截断",
                    Tone::Unknown,
                ));
            }
        }
        Reading::NotRead => {
            progress = progress.child(tone_chip("进度条目数：读不出来", Tone::Unknown));
        }
    }
    card = card.child(progress);
    card
}

fn composition_card(p: &Project) -> Div {
    let mut card = section_card(
        "提交构成",
        Some("计数来自引擎 commitTypes；样本是否截断由 commitTypesTruncated 披露".to_string()),
    );

    if p.error.is_some() {
        card = card.child(tone_banner(
            Tone::Err,
            "提交构成读不出来",
            "项目采集失败：空数组不代表没有提交。",
        ));
        return card;
    }
    if !p.is_git() {
        card = card.child(empty_state(
            "◌",
            "非 git 仓库",
            "没有提交历史，因此没有提交构成。".to_string(),
        ));
        return card;
    }

    let types = &p.commit_types;
    let total: i64 = types.iter().map(|t| t.count.max(0)).sum();
    if types.is_empty() {
        let body = match read_opt_i64(p.commit_count) {
            Reading::Known(0) => "仓库还没有提交（commitCount=0）。".to_string(),
            Reading::Known(n) => format!(
                "引擎给出空 commitTypes，但 commitCount={n} —— 类型明细读不出来（空数组 ≠ 没有提交）。"
            ),
            Reading::NotRead => {
                "提交总数读不出来，类型明细也是空数组 —— 两者都不能当成「没有提交」。".to_string()
            }
        };
        card = card.child(tone_banner(Tone::Unknown, "没有可用的提交类型", body));
        return card;
    }
    if total <= 0 {
        card = card.child(tone_banner(
            Tone::Unknown,
            "类型计数全为 0",
            "引擎给了类型列表但计数都是 0 —— 这可能是读不出来，不当成「没有提交」。",
        ));
        return card;
    }

    // 引擎上限是 12 类；界面颜色也只有 12 个系列色。超过就自报截断。
    let shown = types.len().min(12);
    let hidden = types.len().saturating_sub(shown);

    let mut bar = div().class("stackbar");
    for (i, t) in types.iter().take(shown).enumerate() {
        let n = t.count.max(0);
        if n == 0 {
            continue;
        }
        bar = bar.child(
            div()
                .class(format!("stack-seg s{}", (i % 12) + 1))
                .style(format!("flex: {n};")),
        );
    }
    card = card.child(bar);

    let mut legend = div().class("legend");
    for (i, t) in types.iter().take(shown).enumerate() {
        let n = t.count.max(0);
        let pct = (n as f32) * 100.0 / (total as f32);
        let label = format!("{} ×{} · {:.0}%", commit_type_label(&t.type_), n, pct);
        legend = legend.child(
            div()
                .class("legend-item")
                .child(div().class(format!("swatch s{}", (i % 12) + 1)))
                .child(div().class(crate::views::mono_class(&label)).child(label)),
        );
    }
    card = card.child(legend);
    if hidden > 0 {
        card = card.child(tone_chip(
            format!("图例只显示前 {shown} 类（界面颜色上限），还有 {hidden} 类未显示"),
            Tone::Warn,
        ));
    }

    card = card.child(div().class("t-caption dim").child(format!(
        "样本 {total} 条提交（各类型计数之和）"
    )));
    if let Some(true) = p.commit_types_truncated {
        card = card.child(tone_banner(
            Tone::Warn,
            "提交类型采样被截断",
            format!("样本窗口只覆盖了最近 {total} 条提交；更早的提交没有计入这张图。"),
        ));
    } else if p.commit_types_truncated.is_none() {
        card = card.child(tone_banner(
            Tone::Unknown,
            "引擎未披露采样是否截断",
            "commitTypesTruncated 键缺失：上面的比例不能当成全量。",
        ));
    } else {
        card = card.child(
            div()
                .class("t-caption dim")
                .child("引擎确认采样窗口没有被截断（commitTypesTruncated=false）"),
        );
    }
    card
}

fn commit_type_label(raw: &str) -> String {
    match raw {
        "feat" => "新增".to_string(),
        "fix" => "修复".to_string(),
        "perf" => "性能".to_string(),
        "refactor" => "重构".to_string(),
        "docs" => "文档".to_string(),
        "test" => "测试".to_string(),
        "build" => "构建/依赖".to_string(),
        "ci" => "CI".to_string(),
        "style" => "样式".to_string(),
        "chore" => "杂项".to_string(),
        "revert" => "回退".to_string(),
        "other" => "其他".to_string(),
        "" => "类型读不出来".to_string(),
        other => other.to_string(),
    }
}

fn git_ops_card(state: &AppState, p: &Project, cx: &mut Context<AppRoot>) -> Div {
    let mut card = section_card(
        "Git 操作",
        Some(
            "引擎白名单：pull（--ff-only）/ push / fetch / stash / unstash / commit。没有 reset / clean / force-push"
                .to_string(),
        ),
    );
    if p.error.is_some() {
        card = card.child(tone_banner(
            Tone::Err,
            "项目读不出来",
            "引擎采集失败；git 操作大概率也会失败，原因会显示在反馈条里。",
        ));
    }
    if !p.is_git() {
        card = card.child(empty_state(
            "◌",
            "非 git 仓库",
            "git 操作不适用。".to_string(),
        ));
        return card;
    }

    // git status 现状：读不出来 ≠ 干净。
    let load = state.project_detail(&p.name).map(|d| &d.git_status);
    let (tone, text) = match load {
        None => (Tone::Unknown, "git status：详情尚未加载".to_string()),
        Some(Load::Idle) => (Tone::Idle, "git status：未查询".to_string()),
        Some(Load::Loading) => (Tone::Idle, "git status：查询中…".to_string()),
        Some(Load::Failed(e)) => (
            Tone::Err,
            format!("git status 读不出来（不是「干净」）：{}", e.user_message()),
        ),
        Some(Load::Ready(g)) if !g.ok => (
            Tone::Err,
            format!(
                "git status 失败：{}",
                g.err
                    .clone()
                    .unwrap_or_else(|| "引擎没有给出原因".to_string())
            ),
        ),
        Some(Load::Ready(g)) if g.entries.is_empty() => {
            (Tone::Ok, "git status：干净（0 个未提交文件）".to_string())
        }
        Some(Load::Ready(g)) => (
            Tone::Warn,
            format!("git status：{} 个未提交文件（可打开提交弹层勾选）", g.entries.len()),
        ),
    };
    card = card.child(tone_chip(text, tone));

    let mut row = div().class("row-wrap");
    for op in [
        GitOp::Pull,
        GitOp::Push,
        GitOp::Fetch,
        GitOp::Stash,
        GitOp::Unstash,
    ] {
        let project = p.name.clone();
        let label = op.label();
        let mut b = div()
            .class("btn btn-sm btn-ghost")
            .id(format!("git-op-{}", op.as_str()))
            .child(label);
        if op.is_write() {
            b = b.on_click(cx.listener(move |this, _, _, cx| {
                this.state.ask_confirm(Confirm {
                    title: format!("{label}？"),
                    body: format!(
                        "将对「{project}」执行 {label}。引擎只做快进/普通操作，不会 force；失败原因会显示在反馈条里。"
                    ),
                    confirm_label: label.to_string(),
                    danger: false,
                    action: PendingAction::GitOp {
                        project: project.clone(),
                        op,
                    },
                });
                cx.notify();
            }));
        } else {
            b = b.on_click(cx.listener(move |this, _, _, cx| {
                this.state
                    .git_action_full(&project, GitOp::Fetch, None, &[]);
                cx.notify();
            }));
        }
        row = row.child(b);
    }

    let project_commit = p.name.clone();
    let commit_enabled = p.error.is_none();
    let commit = div()
        .class(if commit_enabled {
            "btn btn-sm btn-accent"
        } else {
            "btn btn-sm btn-accent is-disabled"
        })
        .id("proj-open-commit")
        .child("提交…");
    row = row.child(if commit_enabled {
        commit.on_click(cx.listener(move |this, _, _, cx| {
            this.state.open_commit_sheet(&project_commit);
            cx.notify();
        }))
    } else {
        commit.title("项目读不出来：提交弹层仍会显示 git status 的真实失败原因")
    });
    card = card.child(row);
    card
}

// ══════════════════════════════════════════════════════════════════════
// 分支
// ══════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, PartialEq, Eq)]
struct BranchCoverage {
    tone: Tone,
    text: String,
}

/// `branches: []` 有四种完全不同的含义：
///   · 非 git 仓库（没有分支这个概念）；
///   · 项目采集失败；
///   · 仓库真的没有分支（空仓库）；
///   · 分支明细读不出来（repoBranchCount 说还有）。
/// 只有最后一种必须说「空列表 ≠ 没有分支」。
fn branch_coverage(
    is_git: bool,
    has_error: bool,
    repo_count: Option<i64>,
    listed: usize,
) -> BranchCoverage {
    // 采集失败优先于「非 git」：失败项目的 kind 也可能是 dir，
    // 但真相是「读不出来」而不是「没有分支这个概念」。
    if has_error {
        return BranchCoverage {
            tone: Tone::Err,
            text: "项目采集失败：分支列表与分支总数都不可信".to_string(),
        };
    }
    if !is_git {
        return BranchCoverage {
            tone: Tone::Idle,
            text: "非 git 仓库：没有分支（不是「读不出来」）".to_string(),
        };
    }
    match read_opt_i64(repo_count) {
        Reading::NotRead => {
            if listed == 0 {
                BranchCoverage {
                    tone: Tone::Unknown,
                    text: "分支总数与分支明细都读不出来 —— 不能据此说「没有分支」".to_string(),
                }
            } else {
                BranchCoverage {
                    tone: Tone::Unknown,
                    text: format!("分支总数读不出来；引擎给了 {listed} 条分支明细（不完整）"),
                }
            }
        }
        Reading::Known(n) if n == 0 => {
            if listed == 0 {
                BranchCoverage {
                    tone: Tone::Idle,
                    text: "仓库没有分支（repoBranchCount=0；空仓库或尚未提交）".to_string(),
                }
            } else {
                BranchCoverage {
                    tone: Tone::Unknown,
                    text: format!(
                        "repoBranchCount=0，但引擎给了 {listed} 条分支明细 —— 两个数字不一致"
                    ),
                }
            }
        }
        Reading::Known(n) if listed == 0 => BranchCoverage {
            tone: Tone::Err,
            text: format!(
                "引擎没有列出任何分支，但仓库共有 {n} 个分支 —— 空列表不等于没有分支（分支明细读不出来）"
            ),
        },
        Reading::Known(n) if listed < n as usize => BranchCoverage {
            tone: Tone::Warn,
            text: format!("仓库共 {n} 个分支，本次展示 {listed} 个（引擎上限；明细是下界）"),
        },
        Reading::Known(n) if listed == n as usize => BranchCoverage {
            tone: Tone::Ok,
            text: format!("仓库 {n} 个分支全部展示"),
        },
        Reading::Known(n) => BranchCoverage {
            tone: Tone::Unknown,
            text: format!(
                "引擎给了 {listed} 条分支明细，但 repoBranchCount={n} —— 两个数字不一致"
            ),
        },
    }
}

fn branches_tab(state: &AppState, p: &Project, cx: &mut Context<AppRoot>) -> Div {
    let mut stack = div().class("stack");
    let cov = branch_coverage(
        p.is_git(),
        p.error.is_some(),
        p.repo_branch_count,
        p.branches.len(),
    );
    stack = stack.child(tone_banner(cov.tone, "分支明细覆盖", cov.text.clone()));

    if p.error.is_some() || !p.is_git() {
        return stack;
    }

    stack = stack.child(
        div()
            .class("t-caption dim")
            .child("引擎的 branch 记录只有 aheadOfDefault，没有 behind 字段：本页显示「领先」，落后数标为「未提供」——不把缺失当成 0。"),
    );
    if let Some(s) = &state.status {
        if s.summary.branch_unknown_projects > 0 || s.summary.branch_truncated_projects > 0 {
            stack = stack.child(
                div()
                    .class("t-caption dim")
                    .child(format!(
                        "全群口径：{} 个项目的分支数读不出来 · {} 个项目的分支明细被截断（与本源计数无关，仅作对照）",
                        s.summary.branch_unknown_projects,
                        s.summary.branch_truncated_projects
                    )),
            );
        }
    }

    if p.branches.is_empty() {
        stack = stack.child(empty_state(
            "⑂",
            "没有可展示的分支明细",
            cov.text.clone(),
        ));
        return stack;
    }

    for b in &p.branches {
        stack = stack.child(branch_card(b, cx));
    }
    stack
}

fn branch_tone(b: &Branch) -> Tone {
    match b.status.as_str() {
        "merged" | "active" => Tone::Ok,
        "idle" => Tone::Idle,
        "stale" => Tone::Stale,
        _ => Tone::Unknown,
    }
}

fn branch_status_word(b: &Branch) -> String {
    if !b.status_label.trim().is_empty() {
        b.status_label.clone()
    } else {
        match b.status.as_str() {
            "merged" => "已合入".to_string(),
            "active" => "活跃".to_string(),
            "idle" => "空闲".to_string(),
            "stale" => "停滞".to_string(),
            "" => "状态读不出来".to_string(),
            other => other.to_string(),
        }
    }
}

fn branch_card(b: &Branch, cx: &mut Context<AppRoot>) -> Div {
    let tone = branch_tone(b);
    let mut card = div()
        .class("card")
        .id(format!("branch-{}", b.name));

    let mut head = div()
        .class("row-sm")
        .child(div().class(format!("dot {}", tone.class())))
        .child(div().class("card-title").child(b.name.clone()))
        .child(tone_chip(branch_status_word(b), tone));
    if b.is_current {
        head = head.child(tone_chip("当前", Tone::Accent));
    }
    if b.is_default {
        head = head.child(tone_chip("默认", Tone::Info));
    }
    if !b.provider.trim().is_empty() && b.provider != "rules" {
        head = head.child(tone_chip(format!("provider {}", b.provider), Tone::Info));
    }
    card = card.child(head);

    // ahead / behind / merged / 待记录 / 停滞
    let mut facts = div().class("row-wrap");
    if b.is_default {
        if b.ahead_of_default != 0 {
            facts = facts.child(tone_chip(
                format!(
                    "默认分支：aheadOfDefault={}（该字段对默认分支不适用）",
                    b.ahead_of_default
                ),
                Tone::Unknown,
            ));
        } else {
            facts = facts.child(tone_chip("默认分支：ahead/behind 不适用", Tone::Idle));
        }
    } else {
        if b.ahead_of_default > 0 {
            facts = facts.child(tone_chip(
                format!("领先默认分支 {} 个提交", b.ahead_of_default),
                Tone::Accent,
            ));
        } else if b.ahead_of_default == 0 {
            facts = facts.child(tone_chip("领先默认分支 0 个提交", Tone::Idle));
        } else {
            facts = facts.child(tone_chip(
                format!("aheadOfDefault 异常：{}", b.ahead_of_default),
                Tone::Unknown,
            ));
        }
        facts = facts.child(tone_chip("落后数：引擎未提供（不当 0）", Tone::Unknown));
        if b.merged {
            facts = facts.child(tone_chip("已合入默认分支", Tone::Ok));
        } else {
            facts = facts.child(tone_chip("未合入默认分支", Tone::Warn));
        }
    }
    if b.baseline_reset {
        facts = facts.child(tone_chip(b.pending_label(), Tone::Unknown));
    } else if b.pending_commits > 0 {
        facts = facts.child(tone_chip(b.pending_label(), Tone::Warn));
    } else {
        facts = facts.child(plain_chip(b.pending_label()));
    }
    match b.stale_days_reading() {
        Reading::Known(n) => {
            facts = facts.child(if n > 30 {
                tone_chip(format!("{n} 天未更新"), Tone::Stale)
            } else {
                plain_chip(format!("{n} 天未更新"))
            });
        }
        Reading::NotRead => {
            facts = facts.child(tone_chip("停滞天数读不出来", Tone::Unknown));
        }
    }
    card = card.child(facts);

    // HEAD
    if b.head_short.trim().is_empty() {
        card = card.child(tone_chip(
            "HEAD 读不出来（headShort 为空）",
            Tone::Unknown,
        ));
    } else {
        card = card.child(
            div()
                .class("row-sm")
                .child(div().class("code").child(b.head_short.clone()))
                .child(
                    div()
                        .class("t-caption dim t-ellipsis")
                        .child(if b.head_subject.trim().is_empty() {
                            "（提交标题为空）".to_string()
                        } else {
                            b.head_subject.clone()
                        }),
                )
                .child(div().class("t-caption dim").child(b.head_ago.clone())),
        );
    }

    if b.summary.trim().is_empty() {
        card = card.child(
            div()
                .class("t-caption dim")
                .child("暂无摘要（引擎没有为这个分支生成叙述）"),
        );
    } else {
        card = card.child(div().class("t-body").child(b.summary.clone()));
    }

    if !b.highlights.is_empty() {
        let mut hl = div().class("stack-sm");
        for h in b.highlights.iter().take(3) {
            hl = hl.child(div().class("t-caption").child(format!("· {h}")));
        }
        if b.highlights.len() > 3 {
            hl = hl.child(
                div()
                    .class("t-caption dim")
                    .child(format!("还有 {} 条高亮", b.highlights.len() - 3)),
            );
        }
        card = card.child(hl);
    }

    if !b.next_steps.is_empty() {
        let mut steps = div().class("stack-sm");
        steps = steps.child(div().class("t-caption dim").child("下一步："));
        for s in b.next_steps.iter().take(3) {
            steps = steps.child(div().class("t-caption").child(format!("· {s}")));
        }
        if b.next_steps.len() > 3 {
            steps = steps.child(
                div()
                    .class("t-caption dim")
                    .child(format!("还有 {} 条", b.next_steps.len() - 3)),
            );
        }
        card = card.child(steps);
    }

    // 让每张分支卡也可以直接复制分支名（右键菜单之外的轻量入口）。
    let name = b.name.clone();
    card = card.child(
        div()
            .class("btn btn-sm btn-ghost")
            .child("复制分支名")
            .on_click(cx.listener(move |this, _, _, cx| {
                this.state.copy(&name, "分支名");
                cx.notify();
            })),
    );
    card
}

// ══════════════════════════════════════════════════════════════════════
// 日志
// ══════════════════════════════════════════════════════════════════════

fn journal_tab(state: &AppState, p: &Project, cx: &mut Context<AppRoot>) -> Div {
    let mut stack = div().class("stack");
    if p.error.is_some() {
        stack = stack.child(tone_banner(
            Tone::Err,
            "项目采集失败",
            format!(
                "{}。日志窗口仍会尝试读取；下面的空列表不代表「没有日志」。",
                p.error.clone().unwrap_or_default()
            ),
        ));
    }
    let selected = state.ui.project.journal_branch.clone();

    // 可选分支：status 的分支明细 + 当前分支；若当前筛选来自别的项目，
    // 也把它列出来（并单独警告），否则用户看不到自己正筛着一个不存在的分支。
    let selected_known = selected
        .as_ref()
        .map(|s| {
            p.branches.iter().any(|b| &b.name == s)
                || p.current_branch.as_deref() == Some(s.as_str())
        })
        .unwrap_or(true);
    let mut branches: Vec<String> = p
        .branches
        .iter()
        .map(|b| b.name.clone())
        .filter(|n| !n.trim().is_empty())
        .collect();
    if let Some(cb) = p
        .current_branch
        .clone()
        .filter(|s| !s.trim().is_empty())
    {
        if !branches.contains(&cb) {
            branches.push(cb);
        }
    }
    if let Some(sel) = &selected {
        if !branches.contains(sel) {
            branches.push(sel.clone());
        }
    }

    // 分支可能很多（实测 deepOrca 仓库 20 个）；`.seg` 是 inline-flex 不换行，
    // 用 `.row-wrap` + `.seg-item` 才能换行而不横向溢出。
    let mut seg = div().class("row-wrap");
    let project_all = p.name.clone();
    seg = seg.child(
        div()
            .class(if selected.is_none() {
                "seg-item on"
            } else {
                "seg-item"
            })
            .id("journal-branch-all")
            .child("全部")
            .on_click(cx.listener(move |this, _, _, cx| {
                this.state.set_journal_branch(&project_all, None);
                cx.notify();
            })),
    );
    for b in &branches {
        let on = selected.as_deref() == Some(b.as_str());
        let project = p.name.clone();
        let branch = b.clone();
        seg = seg.child(
            div()
                .class(if on { "seg-item on" } else { "seg-item" })
                .id(format!("journal-branch-{b}"))
                .child(b.clone())
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state
                        .set_journal_branch(&project, Some(branch.clone()));
                    cx.notify();
                })),
        );
    }
    stack = stack.child(seg);

    if !selected_known {
        if let Some(sel) = &selected {
            let project = p.name.clone();
            stack = stack.child(tone_banner(
                Tone::Warn,
                "筛选分支不属于本项目",
                format!(
                    "当前日志筛选是「{sel}」，但它不在本项目分支列表里（可能是上一个项目留下的筛选）。"
                ),
            ));
            stack = stack.child(
                div()
                    .class("btn btn-sm")
                    .id("journal-branch-clear")
                    .child("清除筛选")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.set_journal_branch(&project, None);
                        cx.notify();
                    })),
            );
        }
    }

    let detail = state.project_detail(&p.name);
    match detail.map(|d| &d.journal) {
        None => {
            let project = p.name.clone();
            stack = stack.child(empty_state(
                "▤",
                "项目详情尚未加载",
                "日志需要从引擎读取；点下面按钮加载。".to_string(),
            ));
            stack = stack.child(
                div()
                    .class("btn")
                    .id("journal-load")
                    .child("加载详情")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.load_project_detail(&project, true);
                        cx.notify();
                    })),
            );
        }
        Some(load) => match load {
            Load::Idle => {
                stack = stack.child(
                    div()
                        .class("t-caption dim")
                        .child("日志尚未加载"),
                );
            }
            Load::Loading => {
                stack = stack.child(div().class("skeleton skeleton-line"));
            }
            Load::Failed(e) => {
                stack = stack.child(tone_banner(
                    Tone::Err,
                    "日志读不出来（不是「没有日志」）",
                    e.user_message(),
                ));
            }
            Load::Ready(payload) => {
                // 顶部事实与「加载更多」
                let mut head = div().class("row-wrap");
                head = head.child(
                    div()
                        .class("t-body")
                        .child(format!("最近 {} 条日志", payload.entries.len())),
                );
                head = head.child(plain_chip(format!("窗口 limit {}", payload.limit)));
                if payload.branches != "*" && !payload.branches.trim().is_empty() {
                    head = head.child(plain_chip(format!("分支 {}", payload.branches)));
                }
                head = head.child(div().class("spacer"));
                if payload.window_exhausted != Some(false)
                    || payload.entries.len() >= payload.limit.max(0) as usize
                {
                    let project = p.name.clone();
                    head = head.child(
                        div()
                            .class("btn btn-sm")
                            .id("journal-more")
                            .child("加载更多（窗口翻倍）")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.load_more_journal(&project);
                                cx.notify();
                            })),
                    );
                }
                stack = stack.child(head);

                // 每一层截断各自披露
                if let Some(note) = payload.window_note() {
                    stack = stack.child(tone_banner(Tone::Info, "日志窗口", note));
                }
                if let Some(sel) = &selected {
                    if let Some(note) = payload.branch_window_note(sel) {
                        stack = stack.child(tone_banner(
                            Tone::Warn,
                            format!("分支「{sel}」的窗口"),
                            note,
                        ));
                    }
                }
                if let Some(note) = payload.unparsable_note() {
                    stack = stack.child(tone_banner(
                        if payload.unparsable_lines < 0 {
                            Tone::Unknown
                        } else {
                            Tone::Warn
                        },
                        "日志坏行",
                        note,
                    ));
                }
                if payload.window_exhausted == Some(false) {
                    stack = stack.child(
                        div()
                            .class("t-caption dim")
                            .child("引擎确认窗口外没有更早记录（windowExhausted=false）"),
                    );
                }
                if !payload.entries.is_empty() {
                    // 一条全局说明，胜过每条日志重复一句「未披露」：
                    // 缺键就是不知道，但不必逐条刷屏（第 40 条不变量：别过度披露）。
                    stack = stack.child(div().class("t-caption dim").child(
                        "条目缺少 commitCountTruncated / branchCountTruncated 键时，引擎没有披露该层是否被截断；本页不把缺键当成「未截断」。",
                    ));
                }

                if payload.entries.is_empty() {
                    let body = if let Some(sel) = &selected {
                        format!("分支「{sel}」在这个窗口里没有记录。")
                    } else if payload.window_exhausted == Some(true) {
                        "引擎报告窗口已满但返回 0 条 —— 数据不一致，不能当成「没有日志」。"
                            .to_string()
                    } else if payload.window_exhausted.is_none() {
                        "窗口内没有条目；引擎未披露更早是否还有记录。".to_string()
                    } else {
                        "该项目还没有日志记录（窗口未耗尽）。".to_string()
                    };
                    stack = stack.child(empty_state("▤", "窗口内没有日志", body));
                } else {
                    let mut list = div().class("list");
                    for e in &payload.entries {
                        list = list.child(journal_entry_row(e));
                    }
                    stack = stack.child(list);
                }
            }
        },
    }
    stack
}

fn journal_entry_row(e: &JournalEntry) -> Div {
    let at = if e.at.trim().is_empty() {
        "时间读不出来".to_string()
    } else {
        short_iso(&e.at)
    };
    let summary = if e.summary.trim().is_empty() {
        "（没有摘要）".to_string()
    } else {
        e.summary.clone()
    };
    let scope = e.scope_badge();

    let mut main = div().class("list-main");
    main = main.child(
        div()
            .class("row-sm")
            .child(div().class("t-body").child(summary))
            .child(tone_chip(scope.label(), scope.tone())),
    );

    let mut meta = div().class("row-wrap");
    if !e.branch.trim().is_empty() {
        meta = meta.child(plain_chip(format!("分支 {}", e.branch)));
    }
    if !e.provider_label.trim().is_empty() {
        meta = meta.child(plain_chip(e.provider_label.clone()));
    }
    if !e.source.trim().is_empty() {
        meta = meta.child(div().class("t-caption dim").child(format!("来源 {}", e.source)));
    }
    if let Some(n) = e.repo_branch_count {
        meta = meta.child(plain_chip(format!("仓库分支 {n}")));
    }
    main = main.child(meta);

    // 同名不同义的数字：提交数口径与截断必须各自披露。
    if let Some(true) = e.commit_count_truncated {
        main = main.child(tone_chip("提交数是下界（引擎截断）", Tone::Warn));
    }
    if let Some(true) = e.branch_count_truncated {
        main = main.child(tone_chip("分支数是下界（引擎截断）", Tone::Warn));
    }

    if !e.highlights.is_empty() {
        let mut hl = div().class("stack-sm");
        for h in e.highlights.iter().take(3) {
            hl = hl.child(div().class("t-caption").child(format!("· {h}")));
        }
        if e.highlights.len() > 3 {
            hl = hl.child(
                div()
                    .class("t-caption dim")
                    .child(format!("还有 {} 条高亮", e.highlights.len() - 3)),
            );
        }
        main = main.child(hl);
    }
    if !e.next_steps.is_empty() {
        let mut steps = div().class("stack-sm");
        steps = steps.child(div().class("t-caption dim").child("下一步："));
        for s in e.next_steps.iter().take(3) {
            steps = steps.child(div().class("t-caption").child(format!("· {s}")));
        }
        main = main.child(steps);
    }
    if !e.notes.is_empty() {
        let mut notes = div().class("stack-sm");
        for n in e.notes.iter().take(3) {
            notes = notes.child(div().class("t-caption dim").child(format!("注：{n}")));
        }
        main = main.child(notes);
    }
    // docs 只有 deep 路径会写；浅更新缺席 ⇒ 不显示「没改文档」。
    match &e.docs {
        Some(docs) if docs.is_empty() => {
            main = main.child(
                div()
                    .class("t-caption dim")
                    .child("docs 键存在但为空：本次没有涉及托管文档"),
            );
        }
        Some(docs) => {
            main = main.child(
                div()
                    .class("t-caption dim")
                    .child(format!("涉及文档：{}", docs.join("、"))),
            );
        }
        None => {}
    }

    div()
        .class("list-item")
        .child(
            div()
                .class("stack-sm")
                .child(div().class(crate::views::mono_class(&at)).child(at))
                .child(mode_chip(e)),
        )
        .child(main)
}

fn mode_chip(e: &JournalEntry) -> Div {
    let (label, tone) = match e.mode.as_str() {
        "deep" => ("深更新", Tone::Accent),
        "shallow" => ("浅更新", Tone::Idle),
        "track" => ("记录", Tone::Info),
        "" => ("类型读不出来", Tone::Unknown),
        other => (other, Tone::Unknown),
    };
    tone_chip(label, tone)
}

// ══════════════════════════════════════════════════════════════════════
// 文档
// ══════════════════════════════════════════════════════════════════════

fn docs_tab(state: &AppState, p: &Project, cx: &mut Context<AppRoot>) -> Div {
    let mut stack = div().class("stack");

    let project_reload = p.name.clone();
    stack = stack.child(
        div()
            .class("row-wrap")
            .child(div().class("t-caption dim").child(
                "托管文档：docs 命令给内容，status.docs 给存在性；读失败单列，不并进「缺失」。",
            ))
            .child(div().class("spacer"))
            .child(
                div()
                    .class("btn btn-sm")
                    .id("docs-reload")
                    .child("刷新文档")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.load_project_detail(&project_reload, true);
                        cx.notify();
                    })),
            ),
    );
    stack = stack.child(div().class("t-caption dim").child(
        "引擎的 status.docs 只报告「已存在」的文档；下面的「未建」是按引擎默认名单（README.md / AGENTS.md / AGENT.md / CLAUDE.md）推断的 —— 项目若自定义过 update.docs，缺失判断可能不完整。",
    ));

    if p.error.is_some() {
        stack = stack.child(tone_banner(
            Tone::Err,
            "项目采集失败",
            format!(
                "{}。下面的「缺失」判断要打折：status 读不出来时 docs 列表也可能是空的。",
                p.error.clone().unwrap_or_default()
            ),
        ));
    }

    let detail = state.project_detail(&p.name);
    match detail.map(|d| &d.docs) {
        None => {
            let project = p.name.clone();
            stack = stack.child(empty_state(
                "▤",
                "文档尚未加载",
                "需要从引擎读取托管文档内容。".to_string(),
            ));
            stack = stack.child(
                div()
                    .class("btn")
                    .id("docs-load")
                    .child("加载文档")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.load_project_detail(&project, true);
                        cx.notify();
                    })),
            );
        }
        Some(load) => match load {
            Load::Idle => {
                stack = stack.child(div().class("t-caption dim").child("文档尚未加载"));
            }
            Load::Loading => {
                stack = stack.child(div().class("skeleton skeleton-line"));
            }
            Load::Failed(e) => {
                stack = stack.child(tone_banner(
                    Tone::Err,
                    "文档读不出来（不是「没有文档」）",
                    e.user_message(),
                ));
            }
            Load::Ready(payload) => {
                // 读失败的文件：单列，且不参与「缺失」判断。
                let mut unreadable: BTreeMap<String, ()> = BTreeMap::new();
                for u in &payload.unreadable {
                    if !u.project.is_empty() && u.project != p.name {
                        continue;
                    }
                    for f in u.files() {
                        unreadable.insert(f, ());
                    }
                }

                let mut contents: BTreeMap<String, String> = BTreeMap::new();
                for d in &payload.docs {
                    if !d.project.is_empty() && d.project != p.name {
                        continue;
                    }
                    contents.insert(d.file.clone(), d.content.clone());
                }

                let mut exists: BTreeMap<String, bool> = BTreeMap::new();
                if let Some(list) = &p.docs {
                    for d in list {
                        exists.insert(d.file.clone(), d.exists);
                    }
                }
                for f in contents.keys() {
                    exists.insert(f.clone(), true);
                }
                for f in unreadable.keys() {
                    exists.entry(f.clone()).or_insert(true);
                }

                // 引擎只报「已存在」，所以缺失项只能按默认名单推断。
                // 采集失败时不做推断：那时「缺失」和「读不出来」分不开。
                let inferred_missing = p.error.is_none() && p.docs.is_some();
                if inferred_missing {
                    for f in DEFAULT_MANAGED_DOCS {
                        exists.entry(f.to_string()).or_insert(false);
                    }
                }

                let mut files: Vec<String> = exists.keys().cloned().collect();
                files.sort();
                files.dedup();

                let mut n_existing = 0usize;
                let mut n_missing = 0usize;
                for f in &files {
                    if unreadable.contains_key(f) {
                        continue;
                    }
                    if *exists.get(f).unwrap_or(&false) {
                        n_existing += 1;
                    } else {
                        n_missing += 1;
                    }
                }

                if files.is_empty() && unreadable.is_empty() {
                    let body = if p.error.is_some() {
                        "项目采集失败，且 docs 命令没有返回任何文档 —— 无法判断是否有托管文档。"
                            .to_string()
                    } else if p.docs.is_none() {
                        "引擎未给出托管文档清单（status.docs 缺键），docs 命令也没有内容 —— 不知道有哪些文档。"
                            .to_string()
                    } else {
                        "引擎的托管文档清单为空，docs 也没有内容 —— 没有托管文档。".to_string()
                    };
                    stack = stack.child(empty_state("▤", "没有可显示的文档", body));
                    return stack;
                }

                stack = stack.child(
                    div()
                        .class("row-wrap")
                        .child(tone_chip(
                            format!("已建 {n_existing}"),
                            if n_existing > 0 { Tone::Ok } else { Tone::Idle },
                        ))
                        .child(tone_chip(
                            format!("缺失 {n_missing}"),
                            if n_missing > 0 { Tone::Warn } else { Tone::Idle },
                        ))
                        .child(tone_chip(
                            format!("读不出来 {}", unreadable.len()),
                            if unreadable.is_empty() {
                                Tone::Idle
                            } else {
                                Tone::Err
                            },
                        )),
                );

                // 读不出来：最显眼，且带「不是不存在」的说明。
                for f in unreadable.keys() {
                    stack = stack.child(tone_banner(
                        Tone::Err,
                        format!("{f} 读不出来"),
                        "文件可能存在，但内容读取失败；这不是「文件不存在」。",
                    ));
                }

                let mut existing = div().class("stack");
                let mut missing = div().class("stack");
                for f in &files {
                    if unreadable.contains_key(f) {
                        continue;
                    }
                    if *exists.get(f).unwrap_or(&false) {
                        existing = existing.child(doc_card(
                            f,
                            contents.get(f),
                            state.ui.project.expanded_docs,
                            cx,
                        ));
                    } else {
                        missing = missing.child(missing_doc_row(f));
                    }
                }
                if n_existing > 0 {
                    stack = stack.child(div().class("card-title").child("已存在的托管文档"));
                    stack = stack.child(existing);
                }
                if n_missing > 0 {
                    stack = stack.child(div().class("card-title").child("清单里但还没建"));
                    stack = stack.child(missing);
                }
            }
        },
    }
    stack
}

// ══════════════════════════════════════════════════════════════════════
// Markdown（文档页）
// ══════════════════════════════════════════════════════════════════════
//
// 只用 design.rs 的 `md-*` 词表，不引入第三方解析器。范围是「README/AGENTS
// 这类托管文档常见语法」：标题、段落、列表、引用、围栏代码、表格、分隔线，
// 行内强调/代码/链接。原始 HTML 不执行（当文本）。
//
// 纯 ASCII 的 `md-pre`/`md-code` 用 CJK 字面（等宽字体没有中文字形）；
// 代码块里出现中文也不会变豆腐块。

#[derive(Debug, Clone, PartialEq)]
enum Inline {
    Text(String),
    Strong(String),
    Em(String),
    Code(String),
    Link { label: String, url: String },
}

#[derive(Debug, Clone, PartialEq)]
enum MdBlock {
    Heading(u8, String),
    Paragraph(String),
    Quote(String),
    Code(String),
    ListItem { marker: String, text: String },
    Table { header: Vec<String>, rows: Vec<Vec<String>> },
    Rule,
}

fn markdown_blocks(text: &str) -> Vec<MdBlock> {
    let lines: Vec<&str> = text.lines().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < lines.len() {
        let trimmed = lines[i].trim();
        if trimmed.is_empty() {
            i += 1;
            continue;
        }
        // 围栏代码：``` / ~~~ 都认，语言标记忽略。
        if trimmed.starts_with("```") || trimmed.starts_with("~~~") {
            let fence = &trimmed[..3];
            i += 1;
            let mut code = String::new();
            while i < lines.len() && !lines[i].trim().starts_with(fence) {
                code.push_str(lines[i]);
                code.push('\n');
                i += 1;
            }
            if i < lines.len() {
                i += 1;
            }
            out.push(MdBlock::Code(code.trim_end_matches('\n').to_string()));
            continue;
        }
        // ATX 标题
        let hashes = trimmed.chars().take_while(|c| *c == '#').count();
        if (1..=6).contains(&hashes) && trimmed.as_bytes().get(hashes) == Some(&b' ') {
            out.push(MdBlock::Heading(
                hashes as u8,
                trimmed[hashes + 1..].trim().to_string(),
            ));
            i += 1;
            continue;
        }
        if is_md_rule(trimmed) {
            out.push(MdBlock::Rule);
            i += 1;
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("> ") {
            let mut quote = String::from(rest);
            i += 1;
            while i < lines.len() {
                let l = lines[i].trim();
                if let Some(r) = l.strip_prefix("> ") {
                    quote.push('\n');
                    quote.push_str(r);
                    i += 1;
                } else {
                    break;
                }
            }
            out.push(MdBlock::Quote(quote));
            continue;
        }
        if let Some((marker, rest)) = md_list_marker(trimmed) {
            out.push(MdBlock::ListItem {
                marker,
                text: rest.to_string(),
            });
            i += 1;
            continue;
        }
        if trimmed.starts_with('|')
            && i + 1 < lines.len()
            && is_md_table_sep(lines[i + 1].trim())
        {
            let header = md_table_cells(trimmed);
            i += 2;
            let mut rows = Vec::new();
            while i < lines.len() && lines[i].trim().starts_with('|') {
                rows.push(md_table_cells(lines[i].trim()));
                i += 1;
            }
            out.push(MdBlock::Table { header, rows });
            continue;
        }
        // 段落：连续非空行合并（软换行变空格）。
        let mut para = String::from(trimmed);
        i += 1;
        while i < lines.len() {
            let l = lines[i].trim();
            if l.is_empty() || starts_md_block(l, lines.get(i + 1).map(|s| s.trim())) {
                break;
            }
            para.push(' ');
            para.push_str(l);
            i += 1;
        }
        out.push(MdBlock::Paragraph(para));
    }
    out
}

fn starts_md_block(line: &str, next: Option<&str>) -> bool {
    let hashes = line.chars().take_while(|c| *c == '#').count();
    if (1..=6).contains(&hashes) && line.as_bytes().get(hashes) == Some(&b' ') {
        return true;
    }
    line.starts_with("```")
        || line.starts_with("~~~")
        || line.starts_with("> ")
        || is_md_rule(line)
        || md_list_marker(line).is_some()
        || (line.starts_with('|') && next.is_some_and(is_md_table_sep))
}

fn is_md_rule(line: &str) -> bool {
    let t: String = line.chars().filter(|c| !c.is_whitespace()).collect();
    t.len() >= 3
        && (t.chars().all(|c| c == '-')
            || t.chars().all(|c| c == '*')
            || t.chars().all(|c| c == '_'))
}

fn md_list_marker(line: &str) -> Option<(String, &str)> {
    for p in ["- ", "* ", "+ "] {
        if let Some(rest) = line.strip_prefix(p) {
            return Some(("•".to_string(), rest));
        }
    }
    let digits: String = line.chars().take_while(|c| c.is_ascii_digit()).collect();
    if !digits.is_empty() {
        let rest = &line[digits.len()..];
        if let Some(r) = rest.strip_prefix(". ") {
            return Some((format!("{digits}."), r));
        }
    }
    None
}

fn md_table_cells(line: &str) -> Vec<String> {
    line.trim()
        .trim_matches('|')
        .split('|')
        .map(|c| c.trim().to_string())
        .collect()
}

fn is_md_table_sep(line: &str) -> bool {
    let cells = md_table_cells(line);
    !cells.is_empty()
        && cells.iter().all(|c| {
            let core = c.trim_matches(':');
            core.len() >= 3 && core.chars().all(|x| x == '-')
        })
}

fn inline_spans(s: &str) -> Vec<Inline> {
    let mut out = Vec::new();
    let mut text = String::new();
    let mut rest = s;
    while !rest.is_empty() {
        if let Some(after) = rest.strip_prefix("**") {
            if let Some(pos) = after.find("**") {
                flush_inline(&mut text, &mut out);
                out.push(Inline::Strong(after[..pos].to_string()));
                rest = &after[pos + 2..];
                continue;
            }
        }
        if let Some(after) = rest.strip_prefix('`') {
            if let Some(pos) = after.find('`') {
                flush_inline(&mut text, &mut out);
                out.push(Inline::Code(after[..pos].to_string()));
                rest = &after[pos + 1..];
                continue;
            }
        }
        if let Some(after) = rest.strip_prefix('[') {
            if let Some(close) = after.find("](") {
                let after_url = &after[close + 2..];
                if let Some(end) = after_url.find(')') {
                    flush_inline(&mut text, &mut out);
                    out.push(Inline::Link {
                        label: after[..close].to_string(),
                        url: after_url[..end].to_string(),
                    });
                    rest = &after_url[end + 1..];
                    continue;
                }
            }
        }
        // 只认 `*` / `**`：`_` 在技术文档里大量出现在 snake_case 标识符中，
        // 当成斜体会把 `snake_case_name` 渲染成 `snakecasename`。
        if rest.starts_with('*') {
            let after = &rest[1..];
            if let Some(pos) = after.find('*') {
                if pos > 0 {
                    flush_inline(&mut text, &mut out);
                    out.push(Inline::Em(after[..pos].to_string()));
                    rest = &after[pos + 1..];
                    continue;
                }
            }
        }
        let ch = rest.chars().next().unwrap_or(' ');
        text.push(ch);
        rest = &rest[ch.len_utf8()..];
    }
    flush_inline(&mut text, &mut out);
    out
}

fn flush_inline(text: &mut String, out: &mut Vec<Inline>) {
    if !text.is_empty() {
        out.push(Inline::Text(std::mem::take(text)));
    }
}

fn has_cjk(s: &str) -> bool {
    s.chars().any(|c| (c as u32) >= 0x2E80)
}

fn render_markdown(text: &str, cx: &mut Context<AppRoot>) -> Div {
    let mut out = div().class("md");
    for block in markdown_blocks(text) {
        out = match block {
            MdBlock::Heading(level, t) => {
                let cls = match level {
                    1 => "md-h1",
                    2 => "md-h2",
                    3 => "md-h3",
                    4 => "md-h4",
                    5 => "md-h5",
                    _ => "md-h6",
                };
                out.child(div().class(cls).child(t))
            }
            MdBlock::Paragraph(t) => out.child(render_inline_block(&t, cx)),
            MdBlock::Quote(t) => out.child(
                div()
                    .class("md-quote")
                    .child(render_inline_block(&t, cx)),
            ),
            MdBlock::Code(t) => {
                // 等宽字体不含 CJK 字形：纯 ASCII 代码块才用 monospace。
                let cls = if has_cjk(&t) { "md-pre" } else { "md-pre pre-mono" };
                out.child(div().class(cls).child(t))
            }
            MdBlock::ListItem { marker, text } => out.child(
                div()
                    .class("md-li")
                    .child(div().class("md-bullet").child(marker))
                    .child(render_inline_block(&text, cx)),
            ),
            MdBlock::Table { header, rows } => {
                let mut table = div().class("md-table");
                if !header.is_empty() {
                    let mut row = div().class("md-tr");
                    for cell in header {
                        row = row.child(div().class("md-td md-th").child(cell));
                    }
                    table = table.child(row);
                }
                for cells in rows {
                    let mut row = div().class("md-tr");
                    for cell in cells {
                        row = row.child(div().class("md-td").child(cell));
                    }
                    table = table.child(row);
                }
                out.child(table)
            }
            MdBlock::Rule => out.child(div().class("md-hr")),
        };
    }
    out
}

/// 段落只在**真的有行内语法**时拆成多个 span；纯文本段落用单个块，
/// 让换行按整段正常折行（flex 项之间的空白不会被当成可折行处）。
fn render_inline_block(text: &str, cx: &mut Context<AppRoot>) -> Div {
    let spans = inline_spans(text);
    if spans.iter().all(|s| matches!(s, Inline::Text(_))) {
        let joined: String = spans
            .into_iter()
            .map(|s| match s {
                Inline::Text(t) => t,
                _ => String::new(),
            })
            .collect();
        return div().class("md-p").child(joined);
    }
    let mut row = div().class("row-wrap md-p");
    for span in spans {
        row = match span {
            Inline::Text(t) => row.child(div().child(t)),
            Inline::Strong(t) => row.child(div().class("md-strong").child(t)),
            Inline::Em(t) => row.child(div().class("md-em").child(t)),
            Inline::Code(t) => {
                let cls = if has_cjk(&t) { "md-code" } else { "md-code pre-mono" };
                row.child(div().class(cls).child(t))
            }
            Inline::Link { label, url } => row.child(
                div()
                    .class("md-link")
                    .title(url.clone())
                    .child(label)
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state
                            .apply(AppAction::Open(OpenTarget::Url(url.clone())));
                        cx.notify();
                    })),
            ),
        };
    }
    row
}

fn doc_card(
    file: &str,
    content: Option<&String>,
    expanded: bool,
    cx: &mut Context<AppRoot>,
) -> Div {    let mut card = div().class("card").id(format!("doc-{file}"));

    let file_copy = file.to_string();
    let head = div()
        .class("row-sm")
        .child(div().class("card-title").child(file.to_string()))
        .child(tone_chip("已存在", Tone::Ok))
        .child(div().class("spacer"))
        .child(
            div()
                .class("btn btn-sm btn-ghost")
                .child("复制文件名")
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state.copy(&file_copy, "文档文件名");
                    cx.notify();
                })),
        );
    card = card.child(head);
    card = card.child(
        div()
            .class("t-caption dim")
            .child(format!("项目内相对路径：{file}")),
    );

    match content {
        None => {
            card = card.child(tone_banner(
                Tone::Unknown,
                "内容读不出来",
                "status 说这个文件存在，但 docs 命令没有返回内容（也没有列进 unreadable）。",
            ));
        }
        Some(text) if text.trim().is_empty() => {
            card = card.child(
                div()
                    .class("t-caption")
                    .child("文件存在但为空（0 字符）"),
            );
        }
        Some(text) => {
            let total_chars = text.chars().count();
            let (shown, truncated) = preview_text(text, expanded);
            card = card.child(render_markdown(&shown, cx));
            if truncated {
                let toggle = if expanded { "收起" } else { "展开全文" };
                card = card.child(
                    div()
                        .class("row-sm")
                        .child(
                            div()
                                .class("t-caption dim")
                                .child(format!(
                                    "只渲染前 2400 字符（Markdown）；共 {total_chars} 字符"
                                )),
                        )
                        .child(div().class("spacer"))
                        .child(
                            div()
                                .class("btn btn-sm")
                                .id(format!("doc-expand-{file}"))
                                .child(toggle)
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.state.ui.project.expanded_docs =
                                        !this.state.ui.project.expanded_docs;
                                    cx.notify();
                                })),
                        ),
                );
            } else {
                card = card.child(
                    div()
                        .class("t-caption dim")
                        .child(format!("共 {total_chars} 字符 · Markdown 渲染")),
                );
            }
        }
    }
    card
}

fn missing_doc_row(file: &str) -> Div {
    // 引擎的 update 只**自动创建 README.md**；agent 文档（AGENTS/AGENT/CLAUDE）
    // 只在已存在时更新托管区（flow/update.cj 的 docsToWrite）。
    // 所以「未建」的处置建议必须按文件区分，不能统一写「跑一次 update 会创建」。
    let hint = if file.eq_ignore_ascii_case("README.md") {
        "运行一次浅/深更新会创建"
    } else {
        "引擎不会自动创建；只有它已存在时才更新托管区"
    };
    div()
        .class("list-item")
        .child(div().class("dot idle"))
        .child(
            div()
                .class("list-main")
                .child(div().class(crate::views::mono_class(file)).child(file.to_string())),
        )
        .child(tone_chip("未建", Tone::Idle))
        .child(div().class("t-caption dim").child(hint))
}

/// 按字符（不是字节）截断：中文不会切在 UTF-8 中间。
fn preview_text(text: &str, expanded: bool) -> (String, bool) {
    let total = text.chars().count();
    if expanded || total <= 2400 {
        (text.to_string(), false)
    } else {
        (text.chars().take(2400).collect(), true)
    }
}

// ══════════════════════════════════════════════════════════════════════
// 里程碑
// ══════════════════════════════════════════════════════════════════════

fn milestones_tab(state: &AppState, p: &Project, cx: &mut Context<AppRoot>) -> Div {
    let mut stack = div().class("stack");

    let project_new = p.name.clone();
    stack = stack.child(
        div()
            .class("row-wrap")
            .child(div().class("t-caption dim").child(
                "来自全局 milestone list，按 projectName 过滤到本项目；unknown 单列，不并入进行中。",
            ))
            .child(div().class("spacer"))
            .child(
                div()
                    .class("btn btn-sm btn-accent")
                    .id("ms-new")
                    .child("新建里程碑")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.open_milestone_sheet(&project_new);
                        cx.notify();
                    })),
            ),
    );

    let list = match &state.milestones {
        Some(list) => list,
        None => {
            let (tone, body) = match &state.milestones_error {
                Some(e) => (
                    Tone::Err,
                    format!("里程碑存储读不出来（不是「没有里程碑」）：{}", e.user_message()),
                ),
                None => (
                    Tone::Unknown,
                    "里程碑还没有加载。".to_string(),
                ),
            };
            let mut s = stack.child(tone_banner(tone, "里程碑不可用", body));
            s = s.child(
                div()
                    .class("btn")
                    .id("ms-reload")
                    .child("重新加载里程碑")
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.state.load_milestones();
                        cx.notify();
                    })),
            );
            return s;
        }
    };

    let mine: Vec<&Milestone> = list
        .milestones
        .iter()
        .filter(|m| milestone_belongs_to(m, p))
        .collect();

    let mut open = 0usize;
    let mut done = 0usize;
    let mut dropped = 0usize;
    let mut unknown = 0usize;
    for m in &mine {
        match m.status.as_deref() {
            Some("open") => open += 1,
            Some("done") => done += 1,
            Some("dropped") => dropped += 1,
            _ => unknown += 1,
        }
    }

    let read_count = read_i64(list.read_count);
    stack = stack.child(
        div()
            .class("row-wrap")
            .child(tone_chip(
                format!("进行中 {open}"),
                if open > 0 { Tone::Accent } else { Tone::Idle },
            ))
            .child(tone_chip(
                format!("已达成 {done}"),
                if done > 0 { Tone::Ok } else { Tone::Idle },
            ))
            .child(tone_chip(
                format!("已放弃 {dropped}"),
                if dropped > 0 { Tone::Idle } else { Tone::Idle },
            ))
            // unknown 单列：它既不是进行中也不是达成。
            .child(tone_chip(
                format!("无法核验 {unknown}"),
                if unknown > 0 { Tone::Unknown } else { Tone::Idle },
            ))
            .child(match read_count {
                Reading::Known(n) => plain_chip(format!("全局读到 {n}")),
                Reading::NotRead => tone_chip("全局条数读不出来", Tone::Unknown),
            })
            .child(plain_chip(format!("本项目 {}", mine.len()))),
    );

    match list.store_health.as_deref() {
        Some("ok") => {}
        Some(other) => {
            stack = stack.child(tone_banner(
                Tone::Warn,
                "里程碑存储降级",
                format!(
                    "storeHealth = {other}。明细可能不完整；0 不是「没有」。"
                ),
            ));
        }
        None => {
            stack = stack.child(tone_banner(
                Tone::Unknown,
                "引擎未披露存储健康",
                "storeHealth 键缺失：把下面的列表当成可能不完整。",
            ));
        }
    }
    if let Some(t) = crate::models::milestone_lower_bound(list) {
        stack = stack.child(tone_banner(Tone::Warn, "明细只是下界", t.note));
    }
    if list.excluded_disabled > 0 {
        stack = stack.child(
            div()
                .class("t-caption dim")
                .child(format!("{} 条里程碑属于已停用项目，未列入。", list.excluded_disabled)),
        );
    }

    if mine.is_empty() {
        let degraded = list.degraded();
        let count_text = match &read_count {
            Reading::Known(n) => format!("{n} 条"),
            Reading::NotRead => "读不出来".to_string(),
        };
        let body = match (read_count.clone(), degraded) {
            (Reading::Known(n), false) if n <= 0 => {
                "引擎读到 0 条里程碑 —— 存储健康时这才是真的没有。".to_string()
            }
            (Reading::NotRead, _) => format!(
                "全局条数读不出来（storeHealth={}）—— 不能据此说「本项目没有里程碑」。",
                list.health_label()
            ),
            (_, true) => format!(
                "存储降级（{}），全局读到 {} —— 0 或缺失都不代表「本项目没有里程碑」。",
                list.health_label(),
                count_text
            ),
            (Reading::Known(n), false) => {
                let orphan_note = if list.orphaned.is_empty() {
                    String::new()
                } else {
                    format!("（另有 {} 条孤儿里程碑，所属项目已注销）", list.orphaned.len())
                };
                format!("引擎全局读到 {n} 条，但没有一条属于本项目{orphan_note}。")
            }
        };
        stack = stack.child(empty_state("◇", "本项目暂无里程碑", body));
    } else {
        let mut rows = div().class("stack");
        for m in &mine {
            rows = rows.child(milestone_row(p, m, cx));
        }
        stack = stack.child(rows);
    }

    if !list.orphaned.is_empty() {
        stack = stack.child(
            div()
                .class("t-caption dim")
                .child(format!(
                    "另有 {} 条孤儿里程碑（所属项目已注销），不在本项目列表里。",
                    list.orphaned.len()
                )),
        );
    }
    stack
}

fn milestone_row(p: &Project, m: &Milestone, cx: &mut Context<AppRoot>) -> Div {
    let tone = m.status_tone();
    let mut card = div()
        .class("card")
        .id(format!("ms-{}-{}", p.name, m.name));

    let mut head = div()
        .class("row-sm")
        .child(div().class(format!("dot {}", tone.class())))
        .child(div().class("card-title").child(m.name.clone()))
        .child(tone_chip(m.status_word(), tone));

    if m.tag_name.trim().is_empty() {
        head = head.child(tone_chip("未绑定 tag", Tone::Idle));
    } else {
        head = head.child(match m.tag_reached {
            Some(true) => tone_chip(format!("tag {} · 已到达", m.tag_name), Tone::Ok),
            Some(false) => tone_chip(format!("tag {} · 未到达", m.tag_name), Tone::Idle),
            None => tone_chip(
                format!("tag {} · 到达状态读不出来", m.tag_name),
                Tone::Unknown,
            ),
        });
    }
    head = head.child(div().class("spacer"));
    head = head.child(
        div()
            .class("t-caption dim")
            .child(m.project_label()),
    );
    card = card.child(head);

    if !m.tag.trim().is_empty() && m.tag != m.tag_name {
        card = card.child(
            div()
                .class("t-caption dim")
                .child(format!("绑定 tag：{}；生效 tagName：{}", m.tag, m.tag_name)),
        );
    }

    let mut facts = div().class("row-wrap");
    facts = facts.child(plain_chip(m.target_label()));
    match m.commits_since_reading() {
        Reading::Known(n) => {
            facts = facts.child(plain_chip(format!("自基线以来 {n} 个提交")));
        }
        Reading::NotRead => {
            facts = facts.child(tone_chip("提交数读不出来", Tone::Unknown));
        }
    }
    match m.git_readable {
        Some(false) => {
            facts = facts.child(tone_chip("仓库读不出来：无法核验", Tone::Err));
        }
        None => {
            facts = facts.child(tone_chip("引擎未披露仓库可读性", Tone::Unknown));
        }
        Some(true) => {}
    }
    if !m.created_at.trim().is_empty() {
        facts = facts.child(
            div()
                .class("t-caption dim")
                .child(format!("创建 {}", short_iso(&m.created_at))),
        );
    }
    if !m.completed_at.trim().is_empty() {
        facts = facts.child(
            div()
                .class("t-caption dim")
                .child(format!("完成 {}", short_iso(&m.completed_at))),
        );
    }
    card = card.child(facts);

    let known_status = matches!(
        m.status.as_deref(),
        Some("open") | Some("done") | Some("dropped")
    );
    if !known_status && !m.unverified_reason.trim().is_empty() {
        card = card.child(tone_banner(
            Tone::Unknown,
            "无法核验的原因",
            m.unverified_reason.clone(),
        ));
    }

    let desc = m.description_text();
    if desc.is_empty() {
        card = card.child(div().class("t-caption dim").child("无描述"));
    } else {
        card = card.child(div().class("t-body t-clamp-2").child(desc));
    }

    let mut actions = div().class("row-wrap");
    let id_name = m.name.clone();
    match m.status.as_deref() {
        Some("open") => {
            let project = p.name.clone();
            let name = m.name.clone();
            actions = actions.child(
                div()
                    .class("btn btn-sm btn-accent")
                    .id(format!("ms-done-{id_name}"))
                    .child("达成")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.milestone_action_typed(
                            &project,
                            &name,
                            MilestoneOp::Done,
                        );
                        cx.notify();
                    })),
            );
            let project = p.name.clone();
            let name = m.name.clone();
            actions = actions.child(
                div()
                    .class("btn btn-sm danger")
                    .id(format!("ms-drop-{id_name}"))
                    .child("放弃")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.ask_milestone_drop(&project, &name);
                        cx.notify();
                    })),
            );
        }
        Some("done") | Some("dropped") => {
            let project = p.name.clone();
            let name = m.name.clone();
            let label = if m.status.as_deref() == Some("done") {
                "重开"
            } else {
                "重新打开"
            };
            actions = actions.child(
                div()
                    .class("btn btn-sm")
                    .id(format!("ms-reopen-{id_name}"))
                    .child(label)
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.milestone_action_typed(
                            &project,
                            &name,
                            MilestoneOp::Reopen,
                        );
                        cx.notify();
                    })),
            );
        }
        _ => {
            actions = actions.child(tone_chip(
                "无法核验：不提供达成/重开",
                Tone::Unknown,
            ));
        }
    }
    let project = p.name.clone();
    let name = m.name.clone();
    actions = actions.child(
        div()
            .class("btn btn-sm danger")
            .id(format!("ms-remove-{id_name}"))
            .child("删除")
            .on_click(cx.listener(move |this, _, _, cx| {
                this.state.ask_milestone_remove(&project, &name);
                cx.notify();
            })),
    );
    card = card.child(actions);
    card
}

// ══════════════════════════════════════════════════════════════════════
// 图谱
// ══════════════════════════════════════════════════════════════════════

fn graph_tab(state: &AppState, p: &Project, cx: &mut Context<AppRoot>) -> Div {
    let mut stack = div().class("stack");
    stack = stack.child(
        div()
            .class("t-caption dim")
            .child("产物由引擎 render check 探测；BUI 没有内嵌 webview，HTML 交付物交给系统浏览器。"),
    );

    let detail = state.project_detail(&p.name);
    for art in Artifact::all() {
        let key = (p.name.clone(), art);
        // 优先读实时缓存：点「检查」成功后 `artifact_states` 立刻更新，
        // 而 `detail.artifacts` 是上次加载项目时的快照，用它会把成功的检查
        // 显示回旧的「未生成」。失败不写缓存，于是回落到 detail 里的
        // Failed 记录（探测失败与「未生成」是两种状态）。
        let load = state
            .artifact_states
            .get(&key)
            .or_else(|| detail.and_then(|d| d.artifacts.get(&art)));
        stack = stack.child(artifact_card(p, art, load, cx));
    }

    stack = stack.child(graph_facts_card(p));
    stack = stack.child(graph_entries_card(p, cx));
    stack
}

fn artifact_card(
    p: &Project,
    art: Artifact,
    load: Option<&Load<RenderCheck>>,
    cx: &mut Context<AppRoot>,
) -> Div {
    let mut card = div().class("card");
    match load {
        Some(load) => match load {
            Load::Idle => {
                card = card.class("art-missing");
                card = card.child(artifact_head(art));
                card = card.child(tone_banner(
                    Tone::Unknown,
                    "尚未探测",
                    "还没有执行 render check；点「检查」探测产物是否存在。",
                ));
                card = card.child(artifact_check_button(p, art, cx));
            }
            Load::Loading => {
                card = card.child(artifact_head(art));
                card = card.child(div().class("skeleton skeleton-line"));
            }
            Load::Failed(e) => {
                card = card.class("art-missing");
                card = card.child(artifact_head(art));
                card = card.child(tone_banner(
                    Tone::Err,
                    "探测失败（不是「未生成」）",
                    e.user_message(),
                ));
                card = card.child(artifact_check_button(p, art, cx));
            }
            Load::Ready(rc) if rc.exists => {
                card = card.class("art-ready");
                card = card.child(artifact_head(art));
                if rc.path.trim().is_empty() {
                    card = card.child(tone_banner(
                        Tone::Warn,
                        "引擎说产物存在，但路径为空",
                        "没有路径就无法打开；点「检查」重试。",
                    ));
                } else {
                    card = card.child(copy_row(cx, rc.path.clone(), "产物路径"));
                }
                let mut row = div().class("row-wrap");
                if !rc.path.trim().is_empty() {
                    let project = p.name.clone();
                    row = row.child(
                        div()
                            .class("btn btn-sm btn-accent")
                            .id(format!("art-open-{}", art.as_str()))
                            .child("打开 →")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state.apply(AppAction::OpenArtifact {
                                    project: project.clone(),
                                    artifact: art,
                                });
                                cx.notify();
                            })),
                    );
                }
                row = row.child(artifact_check_button(p, art, cx));
                row = row.child(
                    div()
                        .class("t-caption dim")
                        .child("产物已生成 · 系统浏览器渲染"),
                );
                card = card.child(row);
            }
            Load::Ready(_) => {
                card = card.class("art-missing");
                card = card.child(artifact_head(art));
                card = card.child(tone_banner(
                    Tone::Warn,
                    "尚未生成",
                    "render check 成功且 exists=false —— 这是「没有产物」，不是「查失败」。用 `moongit skill graph` 的工作流生成。",
                ));
                let mut row = div().class("row-wrap");
                row = row.child(artifact_check_button(p, art, cx));
                row = row.child(
                    div()
                        .class("btn btn-sm")
                        .id(format!("art-skill-{}", art.as_str()))
                        .child("复制生成工作流")
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.state.copy("moongit skill graph", "生成任务");
                            cx.notify();
                        })),
                );
                row = row.child(
                    div()
                        .class("btn btn-sm btn-ghost")
                        .child("去 AI 助手")
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.state.navigate(Route::Agent);
                            cx.notify();
                        })),
                );
                card = card.child(row);
            },
        },
        None => {
            card = card.class("art-missing");
            card = card.child(artifact_head(art));
            card = card.child(tone_banner(
                Tone::Unknown,
                "尚未探测",
                "还没有 render check 的结果；点「检查」探测。",
            ));
            card = card.child(artifact_check_button(p, art, cx));
        }
    }
    card
}

fn artifact_head(art: Artifact) -> Div {
    div()
        .class("stack-sm")
        .child(div().class("card-title").child(art.label()))
        .child(div().class("card-sub").child(art.description()))
}

fn artifact_check_button(p: &Project, art: Artifact, cx: &mut Context<AppRoot>) -> Div {
    let project = p.name.clone();
    div()
        .class("btn btn-sm btn-ghost")
        .id(format!("art-check-{}", art.as_str()))
        .child("检查")
        .on_click(cx.listener(move |this, _, _, cx| {
            // 「检查」必须强制重查（不能读缓存）；失败要当场说出来 ——
            // 只 dispatch `CheckArtifact` 会丢掉 Failed，界面看不出「查失败」。
            match this.state.refresh_artifact(&project, art) {
                Load::Failed(e) => {
                    this.state.feedback = Some(crate::app::Feedback::failure(format!(
                        "产物探测失败（不是「未生成」）：{}",
                        e.user_message()
                    )));
                }
                Load::Ready(rc) if !rc.exists => {
                    this.state.feedback = Some(crate::app::Feedback::success(format!(
                        "{} 尚未生成（render check 成功，exists=false）",
                        art.label()
                    )));
                }
                Load::Ready(_) => {
                    this.state.feedback = Some(crate::app::Feedback::success(format!(
                        "{} 已生成",
                        art.label()
                    )));
                }
                _ => {}
            }
            cx.notify();
        }))
}

fn graph_facts_card(p: &Project) -> Div {
    let mut card = section_card(
        "为什么图会过期",
        Some("产物是某次生成时的快照；下面的数字是当前状态".to_string()),
    );
    let mut facts = div().class("row-wrap");
    facts = facts.child(match read_opt_i64(p.repo_branch_count) {
        Reading::Known(n) => plain_chip(format!("仓库分支 {n}")),
        Reading::NotRead => tone_chip("分支数读不出来", Tone::Unknown),
    });
    facts = facts.child(match read_opt_i64(p.commit_count) {
        Reading::Known(n) => plain_chip(format!("提交总数 {n}")),
        Reading::NotRead => tone_chip("提交总数读不出来", Tone::Unknown),
    });
    if p.progress.last_update_at.trim().is_empty() {
        facts = facts.child(tone_chip("从未更新过进度库", Tone::Idle));
    } else {
        facts = facts.child(plain_chip(format!(
            "上次更新 {}",
            short_iso(&p.progress.last_update_at)
        )));
    }
    if let Some(b) = p.current_branch_entry() {
        if b.stale_days >= 0 {
            facts = facts.child(plain_chip(format!("当前分支 {} 天未更新", b.stale_days)));
        } else {
            facts = facts.child(tone_chip("当前分支停滞天数读不出来", Tone::Unknown));
        }
    }
    card = card.child(facts);
    card
}

fn graph_entries_card(p: &Project, cx: &mut Context<AppRoot>) -> Div {
    let mut card = section_card(
        "相关体检",
        Some("图谱之外的两个入口：代码置信度 / 补丁体检".to_string()),
    );
    let project = p.name.clone();
    let project2 = p.name.clone();
    card = card.child(
        div()
            .class("row-wrap")
            .child(
                div()
                    .class("btn")
                    .child("代码置信度 →")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.ui.confidence.project = Some(project.clone());
                        this.state.navigate(Route::Confidence);
                        cx.notify();
                    })),
            )
            .child(
                div()
                    .class("btn btn-ghost")
                    .child("补丁体检 →")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.ui.patch.project = Some(project2.clone());
                        this.state.navigate(Route::Patch);
                        cx.notify();
                    })),
            ),
    );
    card
}

// ══════════════════════════════════════════════════════════════════════
// 小件
// ══════════════════════════════════════════════════════════════════════

fn section_card(title: &str, sub: Option<String>) -> Div {
    let mut card = div()
        .class("card")
        .child(div().class("card-title").child(title.to_string()));
    if let Some(s) = sub {
        card = card.child(div().class("card-sub t-ellipsis").child(s));
    }
    card
}

fn tone_chip(text: impl Into<String>, tone: Tone) -> Div {
    div()
        .class(format!("chip {}", tone.class()))
        .child(text.into())
}

fn plain_chip(text: impl Into<String>) -> Div {
    div().class("chip").child(text.into())
}

fn count_chip(label: &str, value: Option<i64>) -> Div {
    match read_opt_i64(value) {
        Reading::Known(n) => plain_chip(format!("{label} {n}")),
        Reading::NotRead => tone_chip(format!("{label} 读不出来"), Tone::Unknown),
    }
}

fn tone_banner(tone: Tone, title: impl Into<String>, body: impl Into<String>) -> Div {
    div()
        .class(format!("banner {}", tone.class()))
        .child(div().class("banner-title").child(title.into()))
        .child(div().class("banner-body").child(body.into()))
}

fn empty_state(icon: &str, title: &str, body: String) -> Div {
    div()
        .class("empty")
        .child(div().class("empty-icon").child(icon.to_string()))
        .child(div().class("empty-title").child(title.to_string()))
        .child(div().class("empty-body").child(body))
}

fn kv_row(key: &str, value: String) -> Div {
    div()
        .class("kv")
        .child(div().class("kv-k").child(format!("{key}：")))
        .child(div().class("kv-v").child(value))
}

fn chip_list(label: &str, items: &[String]) -> Div {
    let mut row = div().class("row-wrap");
    row = row.child(div().class("t-caption dim").child(format!("{label}：")));
    if items.is_empty() {
        row = row.child(div().class("t-caption").child("无"));
    }
    for item in items.iter().take(8) {
        row = row.child(plain_chip(item.clone()));
    }
    if items.len() > 8 {
        row = row.child(
            div()
                .class("t-caption dim")
                .child(format!("还有 {} 个", items.len() - 8)),
        );
    }
    row
}

fn copy_row(cx: &mut Context<AppRoot>, text: String, label: &'static str) -> Div {
    let text_for_click = text.clone();
    div()
        .class("list-item")
        .child(
            div()
                .class("path")
                .child(div().class("path-text").title(text.clone()).child(text)),
        )
        .on_click(cx.listener(move |this, _, _, cx| {
            this.state.copy(&text_for_click, label);
            cx.notify();
        }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_branch_list_is_not_no_branches() {
        // 实测 deepGit：repoBranchCount=1、branches=[]。
        let c = branch_coverage(true, false, Some(1), 0);
        assert_eq!(c.tone, Tone::Err);
        assert!(c.text.contains("空列表不等于没有分支"));

        // 没有分支明细但仓库有 20 个分支（实测 deepOrca 展示 7/20 之外的极端）。
        let c2 = branch_coverage(true, false, Some(20), 7);
        assert_eq!(c2.tone, Tone::Warn);
        assert!(c2.text.contains("共 20 个分支"));

        // 非 git 不是「读不出来」。
        let c3 = branch_coverage(false, false, Some(0), 0);
        assert_eq!(c3.tone, Tone::Idle);
        assert!(c3.text.contains("非 git"));
    }

    #[test]
    fn unknown_branch_count_is_not_zero() {
        let c = branch_coverage(true, false, None, 0);
        assert_eq!(c.tone, Tone::Unknown);
        // 文案可以提到「没有分支」—— 但必须以「不能据此说」的否定形式出现。
        assert!(c.text.contains("不能据此说"));
        assert!(!c.text.starts_with("仓库没有分支"));
    }

    #[test]
    fn commit_type_labels_keep_unknown_raw() {
        assert_eq!(commit_type_label("feat"), "新增");
        assert_eq!(commit_type_label("mystery"), "mystery");
        assert_eq!(commit_type_label(""), "类型读不出来");
    }

    #[test]
    fn preview_text_cuts_on_char_boundaries() {
        let text = "汉".repeat(3000);
        let (shown, truncated) = preview_text(&text, false);
        assert!(truncated);
        assert_eq!(shown.chars().count(), 2400);
        // 展开时不截断。
        let (full, truncated2) = preview_text(&text, true);
        assert!(!truncated2);
        assert_eq!(full.chars().count(), 3000);
    }

    #[test]
    fn milestone_belongs_by_name_or_id() {
        let p = Project {
            id: "p_1".to_string(),
            name: "alpha".to_string(),
            ..Default::default()
        };
        let by_name = Milestone {
            project: Some("alpha".to_string()),
            ..Default::default()
        };
        let by_id = Milestone {
            project: None,
            project_id: "p_1".to_string(),
            ..Default::default()
        };
        let other = Milestone {
            project: Some("beta".to_string()),
            project_id: "p_2".to_string(),
            ..Default::default()
        };
        assert!(milestone_belongs_to(&by_name, &p));
        assert!(milestone_belongs_to(&by_id, &p));
        assert!(!milestone_belongs_to(&other, &p));
    }

    #[test]
    fn markdown_blocks_cover_the_doc_vocabulary() {
        let text = "# 标题\n\n段落 **加粗** 与 `code`。\n\n- 一\n- 二\n\n> 引用\n\n```sh\ncargo run\n```\n\n| 列 | 值 |\n|---|---|\n| a | 1 |\n";
        let blocks = markdown_blocks(text);
        assert!(matches!(&blocks[0], MdBlock::Heading(1, t) if t == "标题"));
        assert!(blocks.iter().any(|b| matches!(b, MdBlock::ListItem { text, .. } if text == "一")));
        assert!(blocks.iter().any(|b| matches!(b, MdBlock::Quote(t) if t == "引用")));
        assert!(blocks.iter().any(|b| matches!(b, MdBlock::Code(t) if t == "cargo run")));
        assert!(blocks.iter().any(|b| matches!(b, MdBlock::Table { header, rows } if header.len() == 2 && rows.len() == 1)));
        assert!(blocks.iter().any(|b| matches!(b, MdBlock::Paragraph(t) if t.contains("加粗"))));
    }

    #[test]
    fn inline_spans_do_not_lose_text() {
        let spans = inline_spans("前 **粗** 中 `码` [链](https://example.com) 后");
        let joined: String = spans
            .iter()
            .map(|s| match s {
                Inline::Text(t)
                | Inline::Strong(t)
                | Inline::Em(t)
                | Inline::Code(t) => t.clone(),
                Inline::Link { label, .. } => label.clone(),
            })
            .collect();
        for needle in ["前 ", "粗", " 中 ", "码", "链", " 后"] {
            assert!(joined.contains(needle), "missing {needle:?} in {joined:?}");
        }
        assert!(spans.iter().any(|s| matches!(s, Inline::Link { url, .. } if url == "https://example.com")));
        // 下划线不当中文斜体标记：技术文档里的 snake_case 必须原样保留。
        assert!(inline_spans("snake_case_name")
            .iter()
            .all(|s| matches!(s, Inline::Text(_))));
    }
}
