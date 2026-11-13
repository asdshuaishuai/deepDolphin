// commit_sheet.rs — 选文件提交弹层（项目页调用）。
//
// 【职责】把「提交」这件事的四个闸门摆在按钮旁边，而不是等引擎报错：
//   ① git status 读不出来 / ok=false  ≠ 干净；
//   ② 没有可提交文件（成功且为空）     ≠ 读失败；
//   ③ 提交信息为空                    ≠ 可以提交；
//   ④ 一个文件都没勾                  ≠ 提交全部；
//      另外：`--paths` 是逗号分隔的，**局部选择**里含逗号的路径无法单独提交
//      （引擎会按逗号切错），全选走「不传 --paths」的提交全部路径。
//
// 【为什么不全选也传 --paths】引擎 `git commit --paths` 为空 = 提交全部；
// 已全选时传空数组既少一次字符串拼接，也避免「全选」与「不传」两条路径给出
// 不同结果。只有局部选择才逐条传。
//
// 【挂载点】只有一份：项目页在 `Route::Project` 命中本 sheet 的 project 时挂载。
// core 的 `app.rs` 里那份 v0 根级副本已删除（两份 overlay 会叠在同一份 state 上）。

use crate::app::{AppAction, AppRoot, AppState, Load, Tone};
use crate::models::GitEntry;
use blenderui::prelude::*;

/// 提交闸门。顺序即优先级：先说「读不出来」，再说「没填/没选」。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CommitBlock {
    None,
    StatusUnavailable,
    NoFiles,
    NoMessage,
    NoSelection,
    CommaPath,
}

impl CommitBlock {
    fn hint(self) -> &'static str {
        match self {
            CommitBlock::None => "",
            CommitBlock::StatusUnavailable => {
                "git status 不可用：先修复读取（失败或读不出来都不等于「干净」）"
            }
            CommitBlock::NoFiles => "没有可提交的文件：git status 成功且为空",
            CommitBlock::NoMessage => "提交信息必填；客户端不会替你编一条",
            CommitBlock::NoSelection => "至少勾选一个文件",
            CommitBlock::CommaPath => {
                "选中的路径含逗号，无法用 --paths 单独提交；请「全选」或取消该文件"
            }
        }
    }
}

/// 纯判定：不读 UI、不碰引擎，只回答「现在能不能点提交、不能的话卡在哪」。
fn commit_block(
    status_ok: bool,
    entry_count: usize,
    selected_count: usize,
    all_selected: bool,
    comma_selected: bool,
    message_empty: bool,
) -> CommitBlock {
    if !status_ok {
        return CommitBlock::StatusUnavailable;
    }
    if entry_count == 0 {
        return CommitBlock::NoFiles;
    }
    if message_empty {
        return CommitBlock::NoMessage;
    }
    if selected_count == 0 {
        return CommitBlock::NoSelection;
    }
    // 全选 = 提交全部（不传 --paths），含逗号的路径不成问题；
    // 只有局部选择才会把路径交给逗号分隔的 --paths。
    if !all_selected && comma_selected {
        return CommitBlock::CommaPath;
    }
    CommitBlock::None
}

/// porcelain 的 xy 是「暂存列 + 工作区列」，前导空格有语义。
/// HTML 会折叠连续空格，所以把空格显示成 `·`（并在行尾说明），
/// 否则 `" M"` 与 `"M "` 在界面上长得一模一样。
fn xy_visible(xy: &str) -> String {
    xy.replace(' ', "·")
}

pub fn render(state: &AppState, cx: &mut Context<AppRoot>) -> Option<Div> {
    let sheet = state.commit_sheet.as_ref()?;

    // ── 状态四态：读不出来与「干净」必须分开 ────────────────────────
    let (status_ok, entries, status_view): (bool, Vec<GitEntry>, Div) = match &sheet.status {
        Load::Idle => (
            false,
            Vec::new(),
            div()
                .class("t-caption dim")
                .child("尚未读取 git status"),
        ),
        Load::Loading => (
            false,
            Vec::new(),
            div().class("skeleton skeleton-line"),
        ),
        Load::Failed(e) => (
            false,
            Vec::new(),
            tone_banner(
                Tone::Err,
                "git status 读不出来（不是「干净」）",
                e.user_message(),
            ),
        ),
        Load::Ready(p) if !p.ok => (
            false,
            Vec::new(),
            tone_banner(
                Tone::Err,
                "git status 失败",
                p.err
                    .clone()
                    .unwrap_or_else(|| "引擎没有给出原因".to_string()),
            ),
        ),
        Load::Ready(p) => {
            let total_note = match p.total {
                Some(n) if n >= 0 && n as usize != p.entries.len() => tone_banner(
                    Tone::Warn,
                    "条目数与引擎的 total 不一致",
                    format!(
                        "引擎报告 total={}，但只返回 {} 条条目 —— 列表只是下界，不能当成全部。",
                        n,
                        p.entries.len()
                    ),
                ),
                _ => div(),
            };
            (true, p.entries.clone(), total_note)
        }
    };

    let selected_count = sheet.selected.len();
    let all_selected = !entries.is_empty()
        && entries
            .iter()
            .all(|e| sheet.selected.contains(&e.file));
    let comma_selected = entries
        .iter()
        .any(|e| sheet.selected.contains(&e.file) && e.has_comma());
    let block = commit_block(
        status_ok,
        entries.len(),
        selected_count,
        all_selected,
        comma_selected,
        sheet.message.trim().is_empty(),
    );
    let can_commit = block == CommitBlock::None && !sheet.busy;

    // ── 头部 ─────────────────────────────────────────────────────
    let head = div()
        .class("modal-head")
        .child(
            div()
                .class("modal-title")
                .child(format!("提交 · {}", sheet.project)),
        )
        .child(div().class("modal-sub").child(
            "局部选择走 --paths；全选走引擎 add -A（提交全部当前改动，可能多于列表里的快照）。含逗号的路径不能局部提交。",
        ))
        .child(
            div()
                .class("modal-close")
                .child("×")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.apply(AppAction::CloseCommitSheet);
                    cx.notify();
                })),
        );

    // ── 正文 ─────────────────────────────────────────────────────
    let mut body = div().class("modal-body");
    body = body.child(status_view);

    let mut msg_field = div()
        .class("field")
        .child(div().class("field-label").child("提交信息（必填）"))
        .child(
            div().class("field-box").child(
                input()
                    .class("input")
                    .id("commit-sheet-message")
                    .placeholder("一句话说明这次改了什么")
                    .value(sheet.message.clone())
                    .on_input(
                        cx.listener(|this, e: &blenderui::ChangeEvent, _, cx| {
                            this.state.apply(AppAction::SetCommitMessage(e.value.clone()));
                            cx.notify();
                        }),
                    ),
            ),
        );
    if sheet.message.trim().is_empty() {
        msg_field = msg_field.child(
            div()
                .class("field-hint")
                .child("客户端不会替你编一条提交信息"),
        );
    }
    body = body.child(msg_field);

    if !entries.is_empty() {
        let files_invert: Vec<String> = entries.iter().map(|e| e.file.clone()).collect();
        let toolbar = div()
            .class("row-wrap")
            .child(div().class("t-caption dim").child(format!(
                "{} 个文件 · 已选 {}",
                entries.len(),
                selected_count
            )))
            .child(div().class("spacer"))
            .child(
                div()
                    .class("btn btn-sm")
                    .id("commit-select-all")
                    .child("全选")
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.state.apply(AppAction::SelectAllPaths);
                        cx.notify();
                    })),
            )
            .child(
                div()
                    .class("btn btn-sm")
                    .id("commit-invert")
                    .child("反选")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        // 反选 = 对每个条目 toggle 一次；用同一份状态动作，
                        // 不另造一份「选中集合」。
                        for f in &files_invert {
                            this.state.toggle_commit_path(f);
                        }
                        cx.notify();
                    })),
            )
            .child(
                div()
                    .class("btn btn-sm btn-ghost")
                    .id("commit-clear")
                    .child("清空")
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.state.apply(AppAction::ClearSelection);
                        cx.notify();
                    })),
            );
        body = body.child(toolbar);

        let mut list = div().class("list");
        for entry in &entries {
            let on = sheet.selected.contains(&entry.file);
            let file_for_click = entry.file.clone();
            let file_text = entry.file.clone();
            let file_id = entry.file.clone();
            let xy = entry.xy.clone();
            let kind = entry.kind.clone();
            let comma = entry.has_comma();
            let mut row = div()
                .class(if on {
                    "list-item selected"
                } else {
                    "list-item"
                })
                .id(format!("commit-file-{file_id}"))
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state.toggle_commit_path(&file_for_click);
                    cx.notify();
                }))
                .child(
                    div()
                        .class(if on { "check-box on" } else { "check-box" })
                        .child(if on {
                            div().class("check-mark").child("✓")
                        } else {
                            div()
                        }),
                )
                .child(
                    div()
                        .class("code")
                        .title(format!("porcelain xy = '{xy}'"))
                        .child(xy_visible(&xy)),
                )
                .child(
                    div()
                        .class("list-main")
                        .child(
                            div()
                                .class("t-mono t-ellipsis")
                                .title(entry.file.clone())
                                .child(file_text),
                        ),
                )
                .child(div().class("chip chip-sm").child(kind));
            if comma {
                row = row.child(
                    div()
                        .class("chip chip-sm warn")
                        .child("含逗号：无法单独提交"),
                );
            }
            list = list.child(row);
        }
        body = body.child(list);
        body = body.child(div().class("t-caption dim").child(
            "xy 里的 · 代表空格（porcelain 两列：暂存 / 工作区）；kind 是引擎给的文件类型。",
        ));
    } else if status_ok {
        body = body.child(
            div()
                .class("empty")
                .child(div().class("empty-icon").child("✓"))
                .child(div().class("empty-title").child("没有未提交改动"))
                .child(
                    div()
                        .class("empty-body")
                        .child("git status 成功且条目为空 —— 这是「干净」，不是「读不出来」。"),
                ),
        );
    }

    // ── 闸门提示：按钮旁边说清为什么不能点 ───────────────────────
    let hint = if sheet.busy {
        "提交中…".to_string()
    } else if block != CommitBlock::None {
        block.hint().to_string()
    } else if all_selected {
        // 全选不是「只提交这 N 个」：引擎在没有 --paths 时执行 `git add -A`，
        // 会提交此刻的全部改动（列表只是 status 的快照）。
        format!(
            "将提交全部当前改动（引擎 add -A，不传 --paths）；列表里的 {} 条只是快照",
            entries.len()
        )
    } else {
        format!(
            "将只提交勾选的 {} / {} 个文件（--paths）",
            selected_count,
            entries.len()
        )
    };
    body = body.child(tone_chip(
        hint,
        if block == CommitBlock::None {
            Tone::Ok
        } else {
            Tone::Warn
        },
    ));

    // ── 底部 ─────────────────────────────────────────────────────
    let submit_label = if sheet.busy {
        "提交中…".to_string()
    } else if all_selected {
        "提交全部改动".to_string()
    } else {
        format!("提交选中 {} 个文件", selected_count)
    };
    let foot = div()
        .class("modal-foot")
        .child(
            div()
                .class("btn btn-ghost")
                .id("commit-sheet-cancel")
                .child("取消")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.apply(AppAction::CloseCommitSheet);
                    cx.notify();
                })),
        )
        .child(div().class("spacer"))
        .child(
            div()
                .class(if can_commit {
                    "btn btn-accent"
                } else {
                    "btn btn-accent is-disabled"
                })
                .id("commit-sheet-submit")
                .child(submit_label)
                .on_click(cx.listener(|this, _, _, cx| {
                    // 即便按钮被 `.is-disabled` 拦住，AppState::submit_commit
                    // 仍会再判一次空信息/空选择/空 status —— 闸门不靠 UI 单点。
                    this.state.apply(AppAction::SubmitCommit);
                    cx.notify();
                })),
        );

    let modal = div()
        .class("modal modal-lg glass-strong")
        .on_click(cx.listener(|_, _, _, cx| {
            cx.stop_propagation();
        }))
        .child(head)
        .child(body)
        .child(foot);

    Some(
        div()
            .class("overlay")
            .on_click(cx.listener(|this, _, _, cx| {
                this.state.apply(AppAction::CloseCommitSheet);
                cx.notify();
            }))
            .child(modal),
    )
}

fn tone_chip(text: impl Into<String>, tone: Tone) -> Div {
    div()
        .class(format!("chip {}", tone.class()))
        .child(text.into())
}

fn tone_banner(tone: Tone, title: impl Into<String>, body: impl Into<String>) -> Div {
    div()
        .class(format!("banner {}", tone.class()))
        .child(div().class("banner-title").child(title.into()))
        .child(div().class("banner-body").child(body.into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gates_are_ordered_and_never_let_empty_through() {
        assert_eq!(
            commit_block(false, 0, 0, false, false, true),
            CommitBlock::StatusUnavailable
        );
        assert_eq!(
            commit_block(true, 0, 0, false, false, false),
            CommitBlock::NoFiles
        );
        assert_eq!(
            commit_block(true, 2, 2, true, false, true),
            CommitBlock::NoMessage
        );
        assert_eq!(
            commit_block(true, 2, 0, false, false, false),
            CommitBlock::NoSelection
        );
    }

    #[test]
    fn comma_path_only_blocks_partial_selection() {
        // 局部选择含逗号：--paths 会被引擎按逗号切错 ⇒ 拦住。
        assert_eq!(
            commit_block(true, 2, 1, false, true, false),
            CommitBlock::CommaPath
        );
        // 全选 = 提交全部（不传 --paths）⇒ 允许。
        assert_eq!(
            commit_block(true, 2, 2, true, true, false),
            CommitBlock::None
        );
    }

    #[test]
    fn porcelain_spaces_are_visible() {
        assert_eq!(xy_visible(" M"), "·M");
        assert_eq!(xy_visible("M "), "M·");
        assert_eq!(xy_visible("??"), "??");
        assert_eq!(xy_visible("RM"), "RM");
    }
}
