// 契约面：本阶段先冻结 API，页面的下一阶段消费者尚未落地；未使用不是缺陷。
#![allow(dead_code)]

// scan.rs — 扫描与添加（发现 → 遍历添加 → 刷新注册表）。
//
// 归属：sidebarscan 组。数据入口全部是 core 已有的：
//   `AppState.ui.scan: ScanForm`（path/name/roots/depth/git_only/last/busy）、
//   `AppAction::{SetScanPath, SetScanName, AddScanRoot, RemoveScanRoot,
//                SetScanDepth, SetScanGitOnly, RunScan, AddProject,
//                AskRemoveProject, CopyText}`、`AppState.registry`。
//
// 【三条诚实纪律】
//   1. 三轴覆盖度**分开**说：`truncated`（目录数上限）/ `depth_capped`（深度上限）/
//      `unreadable[]`（读不到）。三者永远各占一格，不合并成一句「结果可能不完整」；
//      `None`（引擎没披露）既不是 true 也不是 false。
//   2. 「没有候选」与「覆盖不完整所以没看到」是两种结论，空态文案必须分开。
//   3. 注册表读取失败不许渲染成「注册表为空」；`Load::Failed` 单独一条红条。
//
// 【已知取舍（不是缺陷，但必须让用户看到）】
//   · BUI 没有系统文件夹选择器（`Engine` 也没有暴露 pick_folder），所以不画
//     「浏览…」按钮 —— 不做一个点了没反应的假承诺。路径直接输入/粘贴。
//   · 引擎调用是同步的（core 还没有 UiSender/后台 Job），扫描/添加期间界面会阻塞；
//     页面上写明，而不是假装有进度条。
//   · core 的 `ScanForm` 只有一个 `path` 字段：候选的「命名…」会把它写进该字段，
//     因此根列表为空时「开始扫描」会扫这个候选目录。页面用「将扫描：…」把
//     实际生效的根**显示出来**，不让共享字段悄悄改变作用域。
//   · 候选的命名输入也只有一个来源（`ScanForm.name`），一次只能命名一个候选；
//     这是 core 表单的形状，不在视图里另造一份持久状态。

use crate::app::{AppAction, AppRoot, AppState, Load};
use crate::models::{RegistryEntry, ScanCandidate, ScanPayload};
use blenderui::prelude::*;

/// 页面临时状态。本组当前没有需要跨帧持久化的私有状态
/// （表单/结果都在 `AppState.ui.scan`，注册表在 `AppState.registry`）。
#[derive(Debug, Clone, Default)]
pub struct ScanUi {}

/// 扫描页的候选级动作（页面级动作仍走 core 的 `AppAction`）。
#[derive(Debug, Clone)]
pub enum ScanAction {
    /// 选中一个候选准备命名：路径写入共享字段，名称清空。
    PrepareCandidate { path: String },
    /// 命名输入框每次编辑：路径 + 名称一起写回共享字段。
    SetCandidateName { path: String, name: String },
    /// 用当前名称添加这个候选。
    AddCandidate { path: String, name: String },
    /// 不命名，直接用目录名添加这个候选。
    AddCandidateDefault { path: String },
    /// 放弃命名。只在共享路径仍是这个候选时才清空 —— 用户若已改成
    /// 别的路径，不能被「取消」顺手抹掉。
    CancelCandidate { path: String },
}

pub fn render(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let mut body = div().class("stack");
    body = body.child(boundary_banner());
    body = body.child(
        div()
            .class("scan-grid")
            .child(add_pane(state, cx))
            .child(scan_pane(state, cx)),
    );
    if let Some(last) = &state.ui.scan.last {
        body = body.child(result_pane(state, last, cx));
    }
    body = body.child(registry_pane(state, cx));
    crate::views::page_shell(
        state,
        "扫描与添加",
        "发现项目 → 逐个添加（可命名）→ 刷新注册表；三轴覆盖度分别披露",
        cx,
        body,
    )
}

// ══════════════════════════════════════════════════════════════════════
// 顶部边界说明
// ══════════════════════════════════════════════════════════════════════

fn boundary_banner() -> Div {
    div()
        .class("banner info")
        .child(div().class("banner-title").child("扫描会自动注册发现的项目"))
        .child(div().class("banner-body").child(
            "本页不提供 --purge（删除进度库不可恢复）；「移除」只取消注册，不删仓库文件。",
        ))
        .child(div().class("banner-body").child(
            "BUI 没有系统文件夹选择器：路径请直接输入/粘贴。扫描与添加都是同步执行，期间界面会阻塞。",
        ))
}

// ══════════════════════════════════════════════════════════════════════
// 单项目添加
// ══════════════════════════════════════════════════════════════════════

fn add_pane(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let path = state.ui.scan.path.clone();
    let name = state.ui.scan.name.clone();
    let registered = registered_name_in(&state.registry, &path);

    let path_hint = if path.trim().is_empty() {
        "先输入目录路径；引擎会校验它存在且是目录".to_string()
    } else if let Some(n) = &registered {
        format!("已注册为「{n}」；再次添加会被引擎拒绝")
    } else {
        "将执行 moongit add <路径> --json；成功后自动刷新注册表/状态/仪表盘".to_string()
    };

    let add_btn = if !path.trim().is_empty() && registered.is_none() {
        action_btn(cx, "btn btn-accent", "添加并注册", AppAction::AddProject)
    } else {
        disabled_btn("btn btn-accent", "添加并注册")
    };

    let root_btn = if path.trim().is_empty() {
        disabled_btn("btn btn-ghost", "作为扫描根加入")
    } else {
        action_btn(
            cx,
            "btn btn-ghost",
            "作为扫描根加入",
            AppAction::AddScanRoot,
        )
    };

    let mut body = div()
        .class("pane-body")
        .child(field(
            "路径（目录）",
            field_box(
                TextField()
                    .class("input")
                    .id("scan-path")
                    .placeholder("/absolute/path/to/repo")
                    .value(path.clone())
                    .on_input(cx.listener(|this, e: &blenderui::ChangeEvent, _, cx| {
                        this.state
                            .apply(AppAction::SetScanPath(e.value.clone()));
                        cx.notify();
                    })),
            ),
            path_hint,
        ))
        .child(field(
            "名称（可选）",
            field_box(
                TextField()
                    .class("input")
                    .id("scan-name")
                    .placeholder("blank = directory name")
                    .value(name)
                    .on_input(cx.listener(|this, e: &blenderui::ChangeEvent, _, cx| {
                        this.state
                            .apply(AppAction::SetScanName(e.value.clone()));
                        cx.notify();
                    })),
            ),
            "批量添加时它绑定「命名…」选中的候选；一次只能命名一个（core 表单只有一个名称字段）",
        ))
        .child(div().class("row").child(add_btn).child(root_btn));

    if let Some(n) = registered {
        let mut row = div()
            .class("row")
            .child(div().class("chip ok").child(format!("已注册：{n}")));
        if state.project(&n).is_some() {
            let target = n.clone();
            row = row.child(
                div()
                    .class("btn btn-sm btn-ghost")
                    .child("打开")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state
                            .apply(AppAction::Navigate(crate::app::Route::Project(
                                target.clone(),
                            )));
                        cx.notify();
                    })),
            );
        }
        body = body.child(row);
    }

    div()
        .class("pane")
        .child(pane_head("添加单个项目", None))
        .child(body)
}

// ══════════════════════════════════════════════════════════════════════
// 批量扫描
// ══════════════════════════════════════════════════════════════════════

fn scan_pane(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let roots = state.ui.scan.roots.clone();
    let depth = state.ui.scan.depth;
    let git_only = state.ui.scan.git_only;
    let effective = state.ui.scan.effective_roots();

    let mut roots_row = div().class("row-wrap");
    if roots.is_empty() {
        roots_row = roots_row
            .child(div().class("t-caption dim").child("还没有根目录：路径框里的路径会作为唯一根"));
    } else {
        for r in &roots {
            let target = r.clone();
            roots_row = roots_row.child(
                div()
                    .class("chip")
                    .child(r.clone())
                    .child(
                        div()
                            .class("search-clear")
                            .child("×")
                            .on_click(cx.listener(move |this, _, _, cx| {
                                this.state
                                    .apply(AppAction::RemoveScanRoot(target.clone()));
                                cx.notify();
                            })),
                    ),
            );
        }
    }

    let mut depth_seg = div().class("seg");
    for d in 1..=6u32 {
        let on = depth == d;
        depth_seg = depth_seg.child(
            div()
                .class(if on { "seg-item on" } else { "seg-item" })
                .child(d.to_string())
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state.apply(AppAction::SetScanDepth(d));
                    cx.notify();
                })),
        );
    }

    let will_scan = if effective.is_empty() {
        "将扫描：（没有根目录）".to_string()
    } else {
        format!("将扫描：{}", effective.join("、"))
    };
    let scan_btn = if !effective.is_empty() && !state.ui.scan.busy {
        action_btn(cx, "btn btn-accent", "开始扫描", AppAction::RunScan)
    } else {
        disabled_btn("btn btn-accent", "开始扫描")
    };

    div()
        .class("pane")
        .child(pane_head(
            "扫描目录（发现并自动注册）",
            Some(div().class("chip").child(format!("深度 {depth}"))),
        ))
        .child(
            div()
                .class("pane-body")
                .child(field(
                    "扫描根（可多个）",
                    roots_row,
                    "每个根是一条独立扫描；结果里的 unreadable 只属于本次扫描",
                ))
                .child(div().class("row").child(
                    div()
                        .class("btn btn-sm btn-ghost")
                        .child("把上面的路径加入根列表")
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.state.apply(AppAction::AddScanRoot);
                            cx.notify();
                        })),
                ))
                .child(
                    div()
                        .class("field")
                        .child(div().class("field-label").child("深度"))
                        .child(depth_seg)
                        .child(div().class("field-hint").child(
                            "1–6；撞到上限时结果会单独标注 depthCapped，而不是说「没有项目」",
                        )),
                )
                .child(
                    div()
                        .class("field")
                        .child(div().class("field-label").child("只扫描 git 仓库"))
                        .child(
                            div()
                                .class(if git_only { "switch on" } else { "switch" })
                                .on_click(cx.listener(move |this, _, _, cx| {
                                    this.state.apply(AppAction::SetScanGitOnly(!git_only));
                                    cx.notify();
                                }))
                                .child(div().class("switch-knob")),
                        )
                        .child(div().class("field-hint").child(
                            "关闭时也会识别仅含 manifest 的普通目录（kind=dir）",
                        )),
                )
                .child(
                    div()
                        .class("t-caption dim t-ellipsis")
                        .child(will_scan),
                ),
        )
        .child(
            div()
                .class("pane-foot")
                .child(scan_btn)
                .child(div().class("t-caption").child(if state.ui.scan.busy {
                    "扫描中…（同步执行）"
                } else {
                    "扫描是同步的：完成前界面不响应"
                })),
        )
}

// ══════════════════════════════════════════════════════════════════════
// 上次扫描结果
// ══════════════════════════════════════════════════════════════════════

fn result_pane(state: &AppState, p: &ScanPayload, cx: &mut Context<AppRoot>) -> Div {
    div()
        .class("pane")
        .child(pane_head(
            "上次扫描结果",
            Some(div().class("chip").child(format!("深度 {}", p.depth))),
        ))
        .child(
            div()
                .class("pane-body")
                .child(stats_row(p))
                .child(coverage_block(p, cx))
                .child(candidates_block(state, p, cx)),
        )
}

fn stats_row(p: &ScanPayload) -> Div {
    let mut row = div().class("row-wrap");
    for (label, value) in [
        ("发现", p.found),
        ("新增", p.added),
        ("已存在", p.existing),
        ("访问目录", p.dirs_visited),
    ] {
        row = row.child(
            div()
                .class("scan-stat")
                .child(div().class("scan-stat-value").child(value.to_string()))
                .child(div().class("scan-stat-label").child(label)),
        );
    }
    row
}

/// 三轴覆盖度。**永远**三格都在：`None`（未披露）有自己的一句话。
fn coverage_block(p: &ScanPayload, cx: &mut Context<AppRoot>) -> Div {
    let mut stack = div().class("stack-sm").child(
        div()
            .class("row-wrap")
            .child(axis_chip(
                "目录数",
                p.truncated,
                "未截断",
                "撞到引擎目录上限",
                "引擎未披露",
            ))
            .child(axis_chip(
                "深度",
                p.depth_capped,
                "未触底",
                "撞到 --depth 上限",
                "引擎未披露",
            ))
            .child(if p.unreadable.is_empty() {
                div().class("chip ok").child("读不到的目录：0")
            } else {
                div()
                    .class("chip err")
                    .child(format!("读不到的目录：{}", p.unreadable.len()))
            }),
    );

    if p.complete() {
        stack = stack.child(
            div()
                .class("banner ok")
                .child(div().class("banner-title").child("覆盖完整"))
                .child(div().class("banner-body").child(
                    "目录数、深度都没截断，也没有读不出来的目录。这只说明扫描范围完整，不代表范围内一定有项目。",
                )),
        );
        return stack;
    }

    let mut banner = div()
        .class("banner warn")
        .child(div().class("banner-title").child("本次扫描没有覆盖完整范围"));
    if p.truncated == Some(true) {
        banner = banner.child(div().class("banner-body").child(
            "目录数被截断：换更小的根目录，或分批扫描；目录上限不是深度上限。",
        ));
    }
    if p.depth_capped == Some(true) {
        banner = banner.child(div().class("banner-body").child(format!(
            "深度被截断：把深度从 {} 调到 {} 再扫一次。",
            p.depth,
            p.depth.saturating_add(1)
        )));
    }
    if p.truncated.is_none() || p.depth_capped.is_none() {
        banner = banner.child(div().class("banner-body").child(
            "引擎没有披露某个轴；客户端不替它推断「没截断」。",
        ));
    }
    if !p.unreadable.is_empty() {
        banner = banner.child(div().class("banner-body").child(format!(
            "{} 个目录读不出来（权限/占用）：这些地方的结果不完整，不是「那里没有项目」。",
            p.unreadable.len()
        )));
        let mut list = div().class("list");
        for path in &p.unreadable {
            list = list.child(path_row(path, cx));
        }
        banner = banner.child(list);
    }
    stack.child(banner)
}

fn axis_chip(
    label: &str,
    value: Option<bool>,
    ok: &str,
    warn: &str,
    unknown: &str,
) -> Div {
    match value {
        Some(false) => div().class("chip ok").child(format!("{label}：{ok}")),
        Some(true) => div().class("chip warn").child(format!("{label}：{warn}")),
        None => div().class("chip unknown").child(format!("{label}：{unknown}")),
    }
}

// ══════════════════════════════════════════════════════════════════════
// 候选列表（逐个添加，可命名）
// ══════════════════════════════════════════════════════════════════════

fn candidates_block(state: &AppState, p: &ScanPayload, cx: &mut Context<AppRoot>) -> Div {
    let stack = div()
        .class("stack-sm")
        .child(div().class("card-sub").child(format!("候选项目（{}）", p.candidates.len())))
        // 引擎的 scan 会自动注册发现的项目（`added` 就是它数出来的）。
        // 因此候选通常已经是「已注册」；「命名… / 添加」只在引擎没能注册
        // （同名冲突、注册表尚未刷新等）时才出现 —— 不给已注册的路径
        // 画一个注定被引擎拒绝的「添加」按钮。
        .child(div().class("t-caption dim").child(
            "引擎的 scan 会自动注册发现的项目：候选通常已注册；未注册的候选才显示「命名… / 添加」。要自定义名称：先在下方注册表移除，再回来「命名…」重加。",
        ));

    if p.candidates.is_empty() {
        let (title, body) = if p.complete() {
            (
                "没有发现候选项目",
                "扫描只认项目根：git 仓库，或含 manifest 的目录。",
            )
        } else {
            (
                "未发现项目（但覆盖不完整）",
                "上面有轴被截断或目录读不出来；这不等于范围内没有项目。",
            )
        };
        return stack.child(
            div()
                .class("empty")
                .child(div().class("empty-icon").child("○"))
                .child(div().class("empty-title").child(title))
                .child(div().class("empty-body").child(body)),
        );
    }

    let selected = norm_path(&state.ui.scan.path);
    let mut list = div().class("list");
    for c in &p.candidates {
        list = list.child(candidate_row(state, c, &selected, cx));
    }
    stack.child(list)
}

fn candidate_row(
    state: &AppState,
    c: &ScanCandidate,
    selected_path: &str,
    cx: &mut Context<AppRoot>,
) -> Div {
    let registered = registered_name_in(&state.registry, &c.path);
    let selected = !selected_path.is_empty() && selected_path == norm_path(&c.path);

    let mut main = div()
        .class("candidate-main")
        .child(
            div()
                .class("row-sm")
                .child(div().class("t-strong t-ellipsis").child(c.name.clone()))
                .child(
                    div()
                        .class(format!(
                            "chip chip-sm {}",
                            if c.kind == "git" { "info" } else { "idle" }
                        ))
                        .child(if c.kind.is_empty() {
                            "未知类型".to_string()
                        } else {
                            c.kind.clone()
                        }),
                ),
        )
        .child(path_row(&c.path, cx));
    if !c.remote.is_empty() {
        main = main.child(
            div()
                .class("t-caption dim t-ellipsis")
                .child(format!("remote：{}", c.remote)),
        );
    }

    let mut side = div().class("candidate-side");
    if let Some(name) = &registered {
        side = side.child(div().class("chip ok").child(format!("已注册：{name}")));
        if state.project(name).is_some() {
            let target = name.clone();
            side = side.child(
                div()
                    .class("btn btn-sm btn-ghost")
                    .child("打开")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state
                            .apply(AppAction::Navigate(crate::app::Route::Project(
                                target.clone(),
                            )));
                        cx.notify();
                    })),
            );
        }
    } else if selected {
        let cand_path = c.path.clone();
        side = side.child(field_box(
            TextField()
                .class("input")
                .id("candidate-name")
                .placeholder("Name (optional)")
                .value(state.ui.scan.name.clone())
                .on_input(cx.listener(move |this, e: &blenderui::ChangeEvent, _, cx| {
                    this.state.dispatch(crate::app::Action::Scan(
                        ScanAction::SetCandidateName {
                            path: cand_path.clone(),
                            name: e.value.clone(),
                        },
                    ));
                    cx.notify();
                })),
        ));
        side = side.child(scan_btn(
            cx,
            "btn btn-sm btn-accent",
            "添加",
            ScanAction::AddCandidate {
                path: c.path.clone(),
                name: state.ui.scan.name.clone(),
            },
        ));
        side = side.child(scan_btn(
            cx,
            "btn btn-sm btn-ghost",
            "取消",
            ScanAction::CancelCandidate {
                path: c.path.clone(),
            },
        ));
    } else {
        side = side.child(scan_btn(
            cx,
            "btn btn-sm btn-ghost",
            "命名…",
            ScanAction::PrepareCandidate {
                path: c.path.clone(),
            },
        ));
        side = side.child(scan_btn(
            cx,
            "btn btn-sm btn-accent",
            "添加",
            ScanAction::AddCandidateDefault {
                path: c.path.clone(),
            },
        ));
    }

    div()
        .class(if selected {
            "candidate list-item selected"
        } else {
            "candidate list-item"
        })
        .child(main)
        .child(side)
}

// ══════════════════════════════════════════════════════════════════════
// 已注册项目（注册表的只读镜像）
// ══════════════════════════════════════════════════════════════════════

fn registry_pane(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let count = match &state.registry {
        Load::Ready(list) => Some(list.len()),
        _ => None,
    };
    let mut right = div().class("row-sm");
    if let Some(n) = count {
        right = right.child(div().class("chip").child(format!("{n} 个")));
    } else {
        right = right.child(div().class("chip unknown").child("计数不可知"));
    }

    let body = match &state.registry {
        Load::Idle | Load::Loading => skeleton_lines(3),
        Load::Failed(e) => div()
            .class("banner err")
            .child(div().class("banner-title").child("注册表读不出来"))
            // 与「注册表为空」严格分开：读不到不等于没有。
            .child(div().class("banner-body").child(format!(
                "这不是「没有项目」：{}",
                e.user_message()
            ))),
        Load::Ready(list) if list.is_empty() => div()
            .class("empty")
            .child(div().class("empty-icon").child("◇"))
            .child(div().class("empty-title").child("注册表为空"))
            .child(div().class("empty-body").child("用上面的「添加」或「扫描」注册第一个项目。")),
        Load::Ready(list) => registry_list(state, list, cx),
    };

    div()
        .class("pane")
        .child(pane_head("已注册项目", Some(right)))
        .child(div().class("pane-body").child(body))
}

fn registry_list(state: &AppState, list: &[RegistryEntry], cx: &mut Context<AppRoot>) -> Div {
    let mut out = div().class("list");
    for e in list {
        let mut tags = div().class("row-sm");
        for t in e.tags.iter().take(3) {
            tags = tags.child(div().class("chip chip-sm").child(t.clone()));
        }
        if e.tags.len() > 3 {
            tags = tags.child(
                div()
                    .class("chip chip-sm")
                    .child(format!("+{}", e.tags.len() - 3)),
            );
        }

        let main = div()
            .class("list-main")
            .child(
                div()
                    .class("row-sm")
                    .child(div().class("t-strong").child(e.name.clone()))
                    .child(
                        div()
                            .class(format!(
                                "chip chip-sm {}",
                                if e.kind == "git" { "info" } else { "idle" }
                            ))
                            .child(if e.kind.is_empty() {
                                "未知类型".to_string()
                            } else {
                                e.kind.clone()
                            }),
                    )
                    .child(if e.disabled {
                        div().class("chip chip-sm warn").child("已停用")
                    } else {
                        div().class("chip chip-sm ok").child("启用")
                    })
                    .child(tags),
            )
            .child(div().class("path-text").child(e.path.clone()));

        let mut side = div().class("list-side");
        // 停用项目不在 status 里：只给「复制路径 / 移除」，不给一个必然失败的「打开」。
        if !e.disabled && state.project(&e.name).is_some() {
            let target = e.name.clone();
            side = side.child(
                div()
                    .class("btn btn-sm btn-ghost")
                    .child("打开")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state
                            .apply(AppAction::Navigate(crate::app::Route::Project(
                                target.clone(),
                            )));
                        cx.notify();
                    })),
            );
        }
        let copy = e.path.clone();
        side = side.child(
            div()
                .class("btn btn-sm btn-ghost")
                .child("复制路径")
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state.apply(AppAction::CopyText {
                        text: copy.clone(),
                        label: "项目路径".to_string(),
                    });
                    cx.notify();
                })),
        );
        let name = e.name.clone();
        side = side.child(
            div()
                .class("btn btn-sm btn-danger")
                .child("移除")
                .on_click(cx.listener(move |this, _, _, cx| {
                    // 核心的确认文案已写明「只取消注册，不删文件、进度库保留」。
                    this.state
                        .apply(AppAction::AskRemoveProject(name.clone()));
                    cx.notify();
                })),
        );

        out = out.child(
            div()
                .class("list-item")
                .child(main)
                .child(side),
        );
    }
    out
}

// ══════════════════════════════════════════════════════════════════════
// reduce / on_enter
// ══════════════════════════════════════════════════════════════════════

pub fn reduce(state: &mut AppState, action: ScanAction) {
    match action {
        ScanAction::PrepareCandidate { path } => {
            state.ui.scan.path = path;
            state.ui.scan.name.clear();
            // 选中候选不是失败：清掉上一条反馈，避免把旧错误当成这次的结果。
            state.feedback = None;
        }
        ScanAction::SetCandidateName { path, name } => {
            state.ui.scan.path = path;
            state.ui.scan.name = name;
        }
        ScanAction::AddCandidate { path, name } => {
            state.ui.scan.path = path;
            state.ui.scan.name = name;
            // 复用 core 的唯一添加路径（校验、回执、toast、刷新都在那里）。
            state.apply(AppAction::AddProject);
        }
        ScanAction::AddCandidateDefault { path } => {
            state.ui.scan.path = path;
            state.ui.scan.name.clear();
            state.apply(AppAction::AddProject);
        }
        ScanAction::CancelCandidate { path } => {
            // 选中态由共享 path 字段表达；不清 path 就退不出选中态。
            // 但只在它仍是这个候选时才清（用户可能已经改成别的路径）。
            if norm_path(&state.ui.scan.path) == norm_path(&path) {
                state.ui.scan.path.clear();
            }
            state.ui.scan.name.clear();
        }
    }
}

pub fn on_enter(state: &mut AppState) {
    state.ensure_status();
    if matches!(state.registry, Load::Idle) {
        state.load_registry();
    }
}

// ══════════════════════════════════════════════════════════════════════
// 小件与纯函数
// ══════════════════════════════════════════════════════════════════════

fn pane_head(title: &str, right: Option<Div>) -> Div {
    let mut head = div()
        .class("pane-head")
        .child(div().class("card-title").child(title.to_string()))
        .child(div().class("spacer"));
    if let Some(r) = right {
        head = head.child(r);
    }
    head
}

fn field(label: &str, control: Div, hint: impl Into<String>) -> Div {
    div()
        .class("field")
        .child(div().class("field-label").child(label.to_string()))
        .child(control)
        .child(div().class("field-hint").child(hint.into()))
}

fn field_box(control: impl IntoElement) -> Div {
    div().class("field-box").child(control)
}

fn action_btn(
    cx: &mut Context<AppRoot>,
    classes: &str,
    label: &str,
    action: AppAction,
) -> Div {
    div()
        .class(classes.to_string())
        .child(label.to_string())
        .on_click(cx.listener(move |this, _, _, cx| {
            this.state.apply(action.clone());
            cx.notify();
        }))
}

fn scan_btn(
    cx: &mut Context<AppRoot>,
    classes: &str,
    label: &str,
    action: ScanAction,
) -> Div {
    div()
        .class(classes.to_string())
        .child(label.to_string())
        .on_click(cx.listener(move |this, _, _, cx| {
            this.state
                .dispatch(crate::app::Action::Scan(action.clone()));
            cx.notify();
        }))
}

/// 禁用按钮：`.is-disabled` 只拦点击，不解释原因 —— 原因必须由相邻 hint 说。
fn disabled_btn(classes: &str, label: &str) -> Div {
    div()
        .class(format!("{classes} is-disabled"))
        .child(label.to_string())
}

fn skeleton_lines(n: usize) -> Div {
    let mut boxed = div().class("stack-sm");
    for _ in 0..n {
        boxed = boxed.child(div().class("skeleton skeleton-line"));
    }
    boxed
}

fn path_row(path: &str, cx: &mut Context<AppRoot>) -> Div {
    let text = path.to_string();
    div()
        .class("path")
        .child(div().class("path-text").child(path.to_string()))
        .child(
            div()
                .class("btn btn-sm btn-ghost")
                .child("复制")
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state.apply(AppAction::CopyText {
                        text: text.clone(),
                        label: "路径".to_string(),
                    });
                    cx.notify();
                })),
        )
}

/// 路径比较用的规范化：去掉尾随 `/`，但保留根路径 `/`。
/// 只做词法处理（不 canonicalize），所以符号链接与 `/private` 前缀差异不做假设。
fn norm_path(path: &str) -> String {
    let t = path.trim();
    if t == "/" {
        return t.to_string();
    }
    t.trim_end_matches('/').to_string()
}

/// 已注册匹配：返回注册表里的项目名（用于「已注册：X」与禁用重复添加）。
fn registered_name_in(registry: &Load<Vec<RegistryEntry>>, path: &str) -> Option<String> {
    let target = norm_path(path);
    if target.is_empty() {
        return None;
    }
    match registry {
        Load::Ready(list) => list
            .iter()
            .find(|e| norm_path(&e.path) == target)
            .map(|e| e.name.clone()),
        // 注册表没读到 ≠ 没注册：这里返回 None 只表示「无法确认」，
        // 按钮仍可点，引擎会给出权威结论。
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::RegistryEntry;

    fn entry(name: &str, path: &str) -> RegistryEntry {
        RegistryEntry {
            id: format!("p_{name}"),
            name: name.to_string(),
            path: path.to_string(),
            kind: "git".to_string(),
            ..Default::default()
        }
    }

    #[test]
    fn norm_path_keeps_root_and_strips_trailing_slash() {
        assert_eq!(norm_path("/"), "/");
        assert_eq!(norm_path("/tmp/a/"), "/tmp/a");
        assert_eq!(norm_path("  /tmp/a  "), "/tmp/a");
        assert_eq!(norm_path(""), "");
    }

    #[test]
    fn registered_match_ignores_trailing_slash() {
        let reg = Load::Ready(vec![entry("alpha", "/tmp/a/")]);
        assert_eq!(
            registered_name_in(&reg, "/tmp/a").as_deref(),
            Some("alpha")
        );
        assert_eq!(registered_name_in(&reg, "/tmp/b"), None);
        // 空路径不匹配任何条目（否则空串会被当成「已注册」）。
        assert_eq!(registered_name_in(&reg, ""), None);
    }

    #[test]
    fn unread_registry_is_not_empty_registry() {
        // 读不出来时不能返回一个「已注册」的假结论，也不能假装「没注册」是事实；
        // 这里只断言它不会误报。
        assert_eq!(
            registered_name_in(&Load::Failed(crate::engine::EngineError::Io(
                "boom".to_string()
            )), "/tmp/a"),
            None
        );
    }
}
