// patch.rs — 补丁体检：Layer-1 算法层 / Layer-2 外部 AI 裁决 / Layer-3 规则合并。
//
// 归属：boardconf 组。数据入口：
//   `graph patchconf <项目> --patch <diff> --json` → `AppState.patch: Load<PatchReport>`
//   `graph patchconf <项目> --patch <diff> --skill` → 纯文本任务书（core 负责弹模态）
//   `graph patchconf --merge <a.json> <b.json> --json` → `AppState.patch_merged: Load<MergedReport>`
//
// 【本页最重要的一句话】
//   **Layer-1 算法层不是终审。** S1–S10 是词法级/语法树级信号，uncertain 是
//   「词法层拿不准」的清单；AI 裁决层在**外部 agent** 完成（本页不调用 AI、
//   不读模型、不替你裁决）；Layer-3 合并只是按规则把两份 JSON 记账，
//   也不产生新的判断。三层都要在界面上标清楚，任何一层都不能被渲染成「真值」。
//
// 【三种「没有」】
//   · 没有 diff        —— 工作区干净 / 用户没给路径；是输入问题，不是「补丁没问题」；
//   · 分析失败         —— 引擎/命令失败；原因原样显示；
//   · 分析成功但结果空 —— `signals` 空 / `uncertain` 空 / `entities` 空，各自有不同含义，
//     必须分开说（见各小节空态）。
//
// 【状态存储的局部折中】
//   core 的 `PatchForm` 没有「结果归属」「展开项」字段（app.rs 冻结，不能改），
//   因此这些 UI 状态编码进 `PatchForm.expanded` 的带前缀键：
//     `result:<项目名>`     —— 最近一次**成功**分析归属的项目；
//     `entity:<idx>:<id>`   —— 展开的实体；
//     `entities:show-low`   —— 展开 confidence < 0.75 的实体；
//     `merged:show-all`     —— 合并终稿实体表显示全部（默认前 50）。
//   前缀保证互不冲突。已作为交付说明里的注意点列出。
//
// 【代码片段】
//   PLAN 9.7 提到「点击展开读取文件 ±5 行」。本阶段 core 没有 `read_snippet`
//   这类 helper，视图层也不应直接 std::fs（PLAN §7.9），因此本页**不读文件**，
//   只显示引擎给的 file:line 并提供复制。真实代码片段留给后续 core helper，
//   不在这里假装能展开。

#![allow(dead_code)]

use crate::app::{Action, AppAction, AppRoot, AppState, Load, RefreshScope};
use crate::models::{
    Alert, MergedEntity, MergedReport, PatchEntity, PatchReport, Ref, Tone, Uncertain,
};
use blenderui::prelude::*;

const ENTITY_PREFIX: &str = "entity:";
const RESULT_PREFIX: &str = "result:";
const SHOW_LOW: &str = "entities:show-low";
const MERGED_SHOW_ALL: &str = "merged:show-all";
/// 合并终稿实体表的展示上限（界面自己砍的那一层，必须披露）。
const MERGED_PAGE: usize = 50;
/// 低置信度实体的折叠门槛（PLAN §9.7）。
const LOW_CONFIDENCE: f64 = 0.75;

/// 补丁页的临时 UI 状态（本阶段字段都在 core 的 `PatchForm`；
/// 本结构保留给后续「输入区折叠」这类本页私有状态）。
#[derive(Debug, Clone, Default)]
pub struct PatchUi {}

#[derive(Debug, Clone)]
pub enum PatchAction {
    /// 分析：显式 diff 路径优先；留空则读工作区 `git diff HEAD`（core 写临时文件）。
    Run,
    /// 取 Layer-2 Agent 任务书（纯文本，模态展示）。
    Skill,
    /// Layer-3 合并（需要 algorithm.json + agent.json/粘贴 JSON）。
    Merge,
    /// 只校验粘贴的 agent JSON（不合并）。
    ValidateAgentJson,
    /// 显式选择项目。
    SetProject(String),
    /// 表单输入（转发给 core 的 setter，保持单一实现）。
    SetDiffPath(String),
    SetAlgorithmPath(String),
    SetAgentPath(String),
    SetAgentJson(String),
    /// 清空 diff 路径 = 改为读取工作区。
    ClearDiffPath,
    /// 展开/收起一个实体。
    ToggleEntity(String),
    /// 展开/收起低置信度实体。
    ToggleShowLowEntities,
    /// 合并终稿实体表「前 50 / 全部」切换。
    ToggleShowAllMerged,
    /// 复制一段文本（定位 / 实体 / 诊断）。
    CopyText { text: String, label: String },
}

pub fn reduce(state: &mut AppState, action: PatchAction) {
    match action {
        PatchAction::Run => {
            let Some(project) = effective_project(state, &state.ui.patch.project) else {
                state.feedback = Some(crate::app::Feedback::failure(
                    "先选择一个项目（补丁体检按项目分析）；当前项目清单为空或不可读",
                ));
                return;
            };
            state.ui.patch.project = Some(project.clone());
            clear_result_project(state);
            // 新的 Layer-1 分析让旧的合并结果失去输入依据（合并用的 diff/报告
            // 可能已经变了）。宁可清掉，也不让用户把旧合并看成这次分析的终稿。
            state.patch_merged = Load::Idle;
            state.dispatch(Action::App(AppAction::RunPatch));
            if matches!(&state.patch, Load::Ready(_)) {
                mark_result_project(state, &project);
            }
        }
        PatchAction::Skill => {
            let Some(project) = effective_project(state, &state.ui.patch.project) else {
                state.feedback = Some(crate::app::Feedback::failure("先选择一个项目"));
                return;
            };
            state.ui.patch.project = Some(project);
            state.dispatch(Action::App(AppAction::RunPatchSkill));
        }
        PatchAction::Merge => {
            state.dispatch(Action::App(AppAction::RunPatchMerge));
        }
        PatchAction::ValidateAgentJson => {
            let empty = state.ui.patch.agent_json.trim().is_empty();
            if state.validate_agent_json() {
                if empty {
                    state.toast(
                        Tone::Warn,
                        "还没有 agent JSON",
                        "粘贴外部 agent 的输出后再校验；合并时也可以改用文件路径",
                    );
                } else {
                    state.toast(Tone::Ok, "JSON 合法", "粘贴的 agent JSON 可以被解析");
                }
            }
        }
        PatchAction::SetProject(name) => {
            state.ui.patch.project = Some(name);
        }
        PatchAction::SetDiffPath(p) => {
            state.dispatch(Action::App(AppAction::SetPatchDiffPath(p)));
        }
        PatchAction::SetAlgorithmPath(p) => {
            state.dispatch(Action::App(AppAction::SetPatchAlgorithmPath(p)));
        }
        PatchAction::SetAgentPath(p) => {
            state.dispatch(Action::App(AppAction::SetPatchAgentPath(p)));
        }
        PatchAction::SetAgentJson(j) => {
            state.dispatch(Action::App(AppAction::SetAgentJson(j)));
        }
        PatchAction::ClearDiffPath => {
            state.dispatch(Action::App(AppAction::SetPatchDiffPath(String::new())));
        }
        PatchAction::ToggleEntity(key) => {
            if !state.ui.patch.expanded.remove(&key) {
                state.ui.patch.expanded.insert(key);
            }
        }
        PatchAction::ToggleShowLowEntities => {
            if !state.ui.patch.expanded.remove(SHOW_LOW) {
                state.ui.patch.expanded.insert(SHOW_LOW.to_string());
            }
        }
        PatchAction::ToggleShowAllMerged => {
            if !state.ui.patch.expanded.remove(MERGED_SHOW_ALL) {
                state.ui.patch.expanded.insert(MERGED_SHOW_ALL.to_string());
            }
        }
        PatchAction::CopyText { text, label } => {
            state.copy(&text, &label);
        }
    }
}

pub fn on_enter(state: &mut AppState) {
    // 幂等兜底；core 当前还没有调用页面 on_enter（见 views/mod.rs 的 Route::Patch）。
    state.ensure_status();
    if state.ui.patch.project.is_none() {
        if let Some(p) = effective_project(state, &None) {
            state.ui.patch.project = Some(p);
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// 默认项目 / 前缀键 / 结果归属
// ══════════════════════════════════════════════════════════════════════

fn effective_project(state: &AppState, explicit: &Option<String>) -> Option<String> {
    let explicit = explicit.clone().filter(|n| !n.trim().is_empty());
    state
        .chosen_project(&explicit)
        .or_else(|| state.projects().first().map(|p| p.name.clone()))
}

pub(crate) fn clear_result_project(state: &mut AppState) {
    state
        .ui
        .patch
        .expanded
        .retain(|k| !k.starts_with(RESULT_PREFIX));
}

pub(crate) fn mark_result_project(state: &mut AppState, project: &str) {
    clear_result_project(state);
    state
        .ui
        .patch
        .expanded
        .insert(format!("{RESULT_PREFIX}{project}"));
}

fn recorded_result_project(state: &AppState) -> Option<String> {
    state
        .ui
        .patch
        .expanded
        .iter()
        .find_map(|k| k.strip_prefix(RESULT_PREFIX).map(str::to_string))
}

// ══════════════════════════════════════════════════════════════════════
// 渲染
// ══════════════════════════════════════════════════════════════════════

pub fn render(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let total = state.projects().len();
    let selected = effective_project(state, &state.ui.patch.project);
    let sub = if state.status.is_none() {
        if state.error.is_some() {
            "项目清单读不出来；补丁体检需要项目清单".to_string()
        } else {
            "正在读取项目清单…".to_string()
        }
    } else {
        format!("Layer-1 算法 · S1–S10 · uncertain（不是终审） · {total} 个项目可选")
    };

    let mut body = div().class("stack");

    if let Some(err) = &state.error {
        let text = if total == 0 {
            format!("项目清单读不出来：{err}")
        } else {
            format!("项目清单刷新失败；下面仍可能显示上一次读到的 {total} 个项目：{err}")
        };
        body = body.child(
            div()
                .class("banner err")
                .child(div().class("banner-title").child("读取失败（不是「没有项目」）"))
                .child(div().class("banner-body").child(text))
                .child(div().class("banner-action").child(btn_action(
                    "重试读取",
                    "btn btn-sm btn-accent",
                    "patch-retry-status",
                    Action::App(AppAction::Refresh(RefreshScope::All)),
                    cx,
                ))),
        );
    }

    if total == 0 && state.error.is_none() && state.status.is_some() {
        body = body.child(
            div()
                .class("empty")
                .child(div().class("empty-icon").child("⌗"))
                .child(div().class("empty-title").child("还没有可体检的项目"))
                .child(div().class("empty-body").child(
                    "补丁体检按项目分析。先到「扫描与添加」注册一个项目，再回来运行。",
                )),
        );
    }

    body = body.child(subject_card(state, selected.as_deref(), cx));
    body = body.child(layer_card());
    body = body.child(inputs_card(state, selected.as_deref(), cx));

    body = body.child(match &state.patch {
        Load::Idle => idle_card(),
        Load::Loading => loading_card(),
        Load::Failed(e) if e.is_cancelled() => {
            crate::views::stopped_card("补丁分析")
        }
        Load::Failed(e) => failed_card(e.user_message(), cx),
        Load::Ready(r) => report_view(state, r, selected.as_deref(), cx),
    });

    body = body.child(merge_card(state, selected.as_deref(), cx));

    crate::views::page_shell(state, "补丁体检", sub, cx, body)
}

fn subject_card(state: &AppState, selected: Option<&str>, cx: &mut Context<AppRoot>) -> Div {
    let mut card = div()
        .class("card")
        .child(
            div()
                .class("card-head")
                .child(div().class("card-title").child("分析对象"))
                .child(div().class("spacer"))
                .child(div().class("chip chip-sm info").child("按项目")),
        );

    if state.projects().is_empty() {
        let text = if state.status.is_none() && state.error.is_none() {
            "项目清单尚未读取（不是「没有项目」）。"
        } else if state.error.is_some() {
            "没有可选项目：项目清单读取失败（先修好上一条错误）。"
        } else {
            "项目清单为空：先到「扫描与添加」注册项目。"
        };
        card = card.child(div().class("t-caption").child(text));
    } else {
        let mut picker = div().class("row-wrap");
        picker = picker.child(div().class("t-caption").child("项目"));
        for p in state.projects() {
            let on = selected == Some(p.name.as_str());
            picker = picker.child(seg_item(
                p.name.clone(),
                on,
                format!("patch-project-{}", p.name),
                Action::Patch(PatchAction::SetProject(p.name.clone())),
                cx,
            ));
        }
        card = card.child(picker);
        let explicit = state
            .ui
            .patch
            .project
            .as_deref()
            .filter(|s| !s.trim().is_empty());
        let note = match (selected, explicit) {
            (Some(s), None) => format!(
                "未显式选择：默认使用「{s}」（当前路由项目，或第一个项目）。点项目名可固定选择。"
            ),
            (Some(s), Some(_)) => format!("当前选择：「{s}」"),
            (None, _) => "项目清单为空或不可读：先修好项目清单".to_string(),
        };
        card = card.child(div().class("t-caption").child(note));
    }
    card
}

/// 三层说明：这一块**恒发**，不随结果出现/消失。
/// 「AI 裁决层在外部 agent 完成」必须写死在这里，避免被误读成本页调用了 AI。
fn layer_card() -> Div {
    let mut list = div().class("list");
    list = list.child(layer_item(
        "Layer-1",
        "算法层（本页）",
        "S1–S10 是词法级/语法树级信号；uncertain 是词法层拿不准的引用。结论是线索汇总，不是终审。",
        Tone::Info,
    ));
    list = list.child(layer_item(
        "Layer-2",
        "AI 裁决层（在外部 agent 完成）",
        "本页不调用 AI、不读模型、不替你裁决。点「取 Agent 任务书」把 --skill 文本交给外部 agent，由它产出 agent.json。",
        Tone::Accent,
    ));
    list = list.child(layer_item(
        "Layer-3",
        "合并层（本页 --merge）",
        "只按规则合并两份 JSON：resolved 打折、ambiguous 固定 0.5、unresolved 进告警。它不产生新的判断。",
        Tone::Unknown,
    ));
    div()
        .class("card")
        .child(div().class("card-title").child("三层置信度：谁在判断"))
        .child(list)
        .child(div().class("t-caption").child(
            "算法层说「看起来像」；AI 裁决层说「我查到了什么」（在外部）；合并层只是把两者记账。没有任何一层是正确性证明。",
        ))
}

fn layer_item(layer: &str, title: &str, body: &str, tone: Tone) -> Div {
    div()
        .class("list-item")
        .child(div().class(format!("chip chip-sm {}", tone.class())).child(layer.to_string()))
        .child(
            div()
                .class("list-main")
                .child(div().class("t-body").child(title.to_string()))
                .child(div().class("t-caption").child(body.to_string())),
        )
}

fn inputs_card(state: &AppState, selected: Option<&str>, cx: &mut Context<AppRoot>) -> Div {
    let form = &state.ui.patch;
    let mut card = div()
        .class("card")
        .child(
            div()
                .class("card-head")
                .child(div().class("card-title").child("输入与动作"))
                .child(div().class("spacer"))
                .child(div().class("chip chip-sm idle").child("工作区 diff → 临时文件")),
        );

    // ── diff 输入 ──
    let mut diff_field = div().class("field");
    diff_field = diff_field.child(div().class("field-label").child("diff 路径"));
    diff_field = diff_field.child(
        div().class("field-box").child(
            TextField()
                .class("input")
                .id("patch-diff-path")
                .placeholder("blank = git diff HEAD")
                .value(form.diff_path.clone())
                .on_input(cx.listener(|this, e: &blenderui::ChangeEvent, _, cx| {
                    this.state.dispatch(Action::Patch(PatchAction::SetDiffPath(
                        e.value.clone(),
                    )));
                    cx.notify();
                })),
        ),
    );
    diff_field = diff_field.child(div().class("field-hint").child(
        "显式路径必须是已存在的文件。留空时客户端执行 git -C <项目路径> diff HEAD（这是标准 git，不是引擎命令），并把输出写到临时文件。",
    ));
    card = card.child(diff_field);

    // 上次实际使用的 diff 路径：core 写进 `last_diff_path`，不是用户输入值。
    if !form.last_diff_path.trim().is_empty() {
        let path = form.last_diff_path.clone();
        card = card.child(
            div()
                .class("row-wrap")
                .child(div().class("t-caption").child(format!(
                    "上次分析用的 diff：{}",
                    form.last_diff_path
                )))
                .child(btn_action(
                    "复制路径",
                    "btn btn-sm btn-ghost",
                    "patch-copy-diff",
                    Action::Patch(PatchAction::CopyText {
                        text: path,
                        label: "diff 路径".to_string(),
                    }),
                    cx,
                )),
        );
    }

    let running = state.patch.is_loading();
    let mut actions = div().class("row-wrap");
    if selected.is_none() {
        actions = actions.child(div().class("btn btn-accent is-disabled").child("分析"));
        actions = actions.child(div().class("t-caption").child("先选择项目"));
    } else if running {
        actions = actions.child(
            div()
                .class("btn btn-accent btn-busy")
                .child(spinner())
                .child("分析中…"),
        );
        actions = actions.child(
            div()
                .class("btn btn-sm danger")
                .id("patch-stop")
                .child("停止")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.stop_patch();
                    cx.notify();
                })),
        );
    } else {
        actions = actions.child(btn_action(
            "分析",
            "btn btn-accent",
            "patch-run",
            Action::Patch(PatchAction::Run),
            cx,
        ));
    }

    if selected.is_some() && !running {
        actions = actions.child(btn_action(
            "取 Agent 任务书",
            "btn",
            "patch-skill",
            Action::Patch(PatchAction::Skill),
            cx,
        ));
    } else {
        actions = actions.child(div().class("btn btn-ghost is-disabled").child("取 Agent 任务书"));
    }

    if !form.diff_path.trim().is_empty() {
        actions = actions.child(btn_action(
            "清空路径（改读工作区）",
            "btn btn-sm btn-ghost",
            "patch-clear-diff",
            Action::Patch(PatchAction::ClearDiffPath),
            cx,
        ));
    }
    card = card.child(actions);
    card = card.child(div().class("t-caption").child(
        "「分析」在**后台线程**执行（读 diff 180s / 引擎 300s），窗口保持响应，可点「停止」终止引擎进程；停止不是超时，不会报成「分析失败」。「取 Agent 任务书」仍是同步执行（结果直接开模态，不受「停止」控制）。",
    ));

    // ── Layer-3 合并输入 ──
    card = card.child(div().class("divider"));
    card = card.child(
        div()
            .class("row-sm")
            .child(div().class("t-h3").child("合并终稿（Layer-3）"))
            .child(div().class("chip chip-sm unknown").child("需要两份 JSON")),
    );
    card = card.child(merge_input(
        "algorithm.json（Layer-1 输出）",
        "patch-algorithm-path",
        &form.algorithm_path,
        "分析成功后客户端会把引擎的原始 stdout 写到这里（临时文件）；也可以手动换成已有路径",
        |v| Action::Patch(PatchAction::SetAlgorithmPath(v)),
        cx,
    ));

    // 自动落盘失败（或想重跑）时的外部命令。正常路径不需要用户复制它。
    let cmd_project = selected.unwrap_or("<项目名>");
    let cmd_diff = if form.last_diff_path.trim().is_empty() {
        "<diff 文件>"
    } else {
        form.last_diff_path.trim()
    };
    let layer1_cmd = format!(
        "moongit graph patchconf {cmd_project} --patch {cmd_diff} --json > algorithm.json"
    );
    card = card.child(
        div()
            .class("row-wrap")
            .child(div().class("t-caption").child(format!(
                "需要手动重存 Layer-1 时：{layer1_cmd}"
            )))
            .child(btn_action(
                "复制 Layer-1 命令",
                "btn btn-sm btn-ghost",
                "patch-copy-layer1-cmd",
                Action::Patch(PatchAction::CopyText {
                    text: layer1_cmd,
                    label: "Layer-1 命令".to_string(),
                }),
                cx,
            )),
    );

    card = card.child(merge_input(
        "agent.json 路径（Layer-2 输出）",
        "patch-agent-path",
        &form.agent_path,
        "外部 agent 产出的文件；与下面的粘贴 JSON 二选一，文件优先",
        |v| Action::Patch(PatchAction::SetAgentPath(v)),
        cx,
    ));

    let mut json_field = div().class("field");
    json_field = json_field.child(div().class("field-label").child("或粘贴 agent JSON"));
    json_field = json_field.child(
        div().class("field-box").child(
            textarea()
                .class("textarea")
                .id("patch-agent-json")
                .placeholder("{\"task\":\"layer2_review\",\"items\":[...]}")
                .value(form.agent_json.clone())
                .on_input(cx.listener(|this, e: &blenderui::ChangeEvent, _, cx| {
                    this.state.dispatch(Action::Patch(PatchAction::SetAgentJson(
                        e.value.clone(),
                    )));
                    cx.notify();
                })),
        ),
    );
    json_field = json_field.child(div().class("field-hint").child(
        "合并前会校验 JSON（不合法会拒绝并说明原因）；空串表示不用粘贴内容。",
    ));
    card = card.child(json_field);

    let merge_ready = !form.algorithm_path.trim().is_empty()
        && (!form.agent_path.trim().is_empty() || !form.agent_json.trim().is_empty());
    let mut merge_actions = div().class("row-wrap");
    merge_actions = merge_actions.child(btn_action(
        "校验 agent JSON",
        "btn btn-sm",
        "patch-validate-json",
        Action::Patch(PatchAction::ValidateAgentJson),
        cx,
    ));
    if merge_ready {
        merge_actions = merge_actions.child(btn_action(
            "合并终稿",
            "btn btn-sm btn-accent",
            "patch-merge",
            Action::Patch(PatchAction::Merge),
            cx,
        ));
    } else {
        merge_actions = merge_actions.child(div().class("btn btn-sm btn-accent is-disabled").child("合并终稿"));
        merge_actions = merge_actions.child(div().class("t-caption").child(if form.algorithm_path.trim().is_empty() {
            "先指定 algorithm.json 路径"
        } else {
            "再给 agent.json 路径，或粘贴 agent JSON"
        }));
    }
    card = card.child(merge_actions);
    card.child(div().class("t-caption").child(
        "合并需要两份报告：算法层 JSON 与外部 agent JSON。Layer-1 报告由分析成功后自动写入上面的临时路径；两份齐了就能在本页合并。",
    ))
}

fn merge_input(
    label: &str,
    id: &str,
    value: &str,
    hint: &str,
    make: impl Fn(String) -> Action + 'static,
    cx: &mut Context<AppRoot>,
) -> Div {
    div()
        .class("field")
        .child(div().class("field-label").child(label.to_string()))
        .child(
            div().class("field-box").child(
                TextField()
                    .class("input")
                    .id(id.to_string())
                    .value(value.to_string())
                    .on_input(cx.listener(move |this, e: &blenderui::ChangeEvent, _, cx| {
                        this.state.dispatch(make(e.value.clone()));
                        cx.notify();
                    })),
            ),
        )
        .child(div().class("field-hint").child(hint.to_string()))
}

// ══════════════════════════════════════════════════════════════════════
// 四态
// ══════════════════════════════════════════════════════════════════════

fn idle_card() -> Div {
    div()
        .class("empty")
        .child(div().class("empty-icon").child("⌗"))
        .child(div().class("empty-title").child("还没有分析补丁"))
        .child(div().class("empty-body").child(
            "点「分析」：留空 diff 路径会读取工作区 git diff HEAD；也可以填一个已有的 diff 文件。\
             工作区没有未提交改动时，客户端会明确报「没有可分析的 diff」，而不是给你一份 0 信号报告。",
        ))
}

fn loading_card() -> Div {
    div()
        .class("card")
        .child(
            div()
                .class("row")
                .child(spinner())
                .child(div().class("card-title").child("正在读 diff / 分析补丁…")),
        )
        .child(div().class("t-caption").child(
            "后台线程执行；窗口保持响应，可点上方「停止」取消。",
        ))
        .child(div().class("skeleton-line"))
        .child(div().class("skeleton-line"))
}

fn failed_card(message: String, cx: &mut Context<AppRoot>) -> Div {
    let copy = message.clone();
    div()
        .class("banner err")
        .child(div().class("banner-title").child("补丁分析失败（不是「没有疑点」）"))
        .child(div().class("banner-body").child(message))
        .child(
            div()
                .class("banner-action")
                .child(btn_action(
                    "重试",
                    "btn btn-sm btn-accent",
                    "patch-retry",
                    Action::Patch(PatchAction::Run),
                    cx,
                ))
                .child(btn_action(
                    "复制错误",
                    "btn btn-sm btn-ghost",
                    "patch-copy-error",
                    Action::Patch(PatchAction::CopyText {
                        text: copy,
                        label: "补丁体检错误".to_string(),
                    }),
                    cx,
                )),
        )
}

// ══════════════════════════════════════════════════════════════════════
// Layer-1 报告
// ══════════════════════════════════════════════════════════════════════

fn report_view(
    state: &AppState,
    r: &PatchReport,
    selected: Option<&str>,
    cx: &mut Context<AppRoot>,
) -> Div {
    let mut out = div().class("stack");

    match (recorded_result_project(state), selected) {
        (Some(o), Some(s)) if o != s => {
            out = out.child(
                div()
                    .class("banner warn")
                    .child(div().class("banner-title").child("这份结果不是当前选择项目的"))
                    .child(div().class("banner-body").child(format!(
                        "结果显示的是「{o}」的补丁体检；你现在选的是「{s}」。点「分析」才会重新读取 {s} 的 diff。"
                    ))),
            );
        }
        (Some(o), None) => {
            out = out.child(
                div()
                    .class("banner warn")
                    .child(div().class("banner-title").child("结果有归属，但当前没有可选项目"))
                    .child(div().class("banner-body").child(format!(
                        "结果显示的是「{o}」的补丁体检；当前项目清单为空或不可读，无法确认 {o} 还在注册表里。"
                    ))),
            );
        }
        (None, _) => {
            out = out.child(
                div()
                    .class("banner unknown")
                    .child(div().class("banner-title").child("结果归属无法核验"))
                    .child(div().class("banner-body").child(
                        "引擎的 PatchReport 里没有项目名或 root，本页也没有记录到这次分析的归属；不要假定它属于当前选择的项目。若你刚刚运行过分析，它可能失败并保留了上一次的报告。",
                    )),
            );
        }
        _ => {}
    }

    out = out.child(summary_card(r));
    out = out.child(signals_card(r));
    out = out.child(uncertain_card(r, cx));
    out = out.child(entities_card(state, r, cx));
    out = out.child(diagnostics_card(r));
    out
}

fn summary_card(r: &PatchReport) -> Div {
    let valid = r.signals.values().filter(|v| v.is_some()).count();
    let nulls = null_signal_keys(r);
    let tone = ratio_tone(r.overall);

    let overall_text = if valid == 0 {
        "—".to_string()
    } else {
        fmt_ratio(r.overall)
    };
    let overall_note = if valid == 0 {
        "没有有效信号：overall 显示 —（载荷里的 0 是默认值，不是「质量 0」）"
    } else {
        "overall = 有效信号的算术平均（0–1，引擎原值）；null 信号不进均值。"
    };

    div()
        .class("card")
        .child(
            div()
                .class("card-head")
                .child(div().class("card-title").child("Layer-1 算法层结论"))
                .child(div().class("spacer"))
                .child(div().class("chip chip-sm idle").child(if r.schema.trim().is_empty() {
                    "schema 未给出".to_string()
                } else {
                    r.schema.clone()
                }))
                .child(div().class("chip chip-sm warn").child("不是终审")),
        )
        .child(
            div()
                .class("row")
                .child(
                    div()
                        .class("stat")
                        .child(div().class("stat-value").child(overall_text))
                        .child(div().class("stat-label").child("overall（0–1）")),
                )
                .child(div().class("divider-v"))
                .child(
                    div()
                        .class("stack-sm grow")
                        .child(ratio_bar(r.overall, tone))
                        .child(div().class("t-caption").child(overall_note))
                        .child(div().class("t-caption").child(format!(
                            "有效信号 {} 条 · null {} 条 · 实体 {} · 关系 {} · 补丁文件 {} · 新增行 {}",
                            valid,
                            nulls.len(),
                            r.diagnostics.total_entities,
                            r.diagnostics.total_relations,
                            r.diagnostics.patch_files,
                            r.diagnostics.added_lines
                        ))),
                ),
        )
        .child(div().class("t-caption").child(
            "S1–S10 与 uncertain 只覆盖词法/语法树能看见的结构；AI 裁决层在外部 agent 完成，合并层只是规则记账。",
        ))
}

fn signals_card(r: &PatchReport) -> Div {
    let nulls = null_signal_keys(r);
    let mut card = div()
        .class("card")
        .child(
            div()
                .class("card-head")
                .child(div().class("card-title").child("S1–S10 信号"))
                .child(div().class("spacer"))
                .child(div().class("chip chip-sm idle").child(format!(
                    "{} 条 · null {} 条",
                    r.signals.len(),
                    nulls.len()
                ))),
        )
        .child(div().class("t-caption").child(
            "按引擎原值显示（0–1），不做百分比换算。null = 词法层算不出来；缺失 = 载荷里没有这个键（两者不同）。信号短名是本页按引擎计算变量翻译的（引擎不提供 label），数值才是引擎原值。",
        ));

    if r.signals.is_empty() {
        card = card.child(
            div()
                .class("banner unknown")
                .child(div().class("banner-title").child("引擎没有返回任何信号"))
                .child(div().class("banner-body").child(
                    "这不是「全部为 0」：没有信号时 overall 可能只是载荷默认值 0。先检查补丁是否被解析（diagnostics.patchFiles）。",
                )),
        );
    }

    let mut grid = div().class("signal-grid");
    for i in 1..=10u32 {
        let key = format!("S{i}");
        grid = grid.child(signal_cell(&key, signal_label(i), r.signals.get(&key)));
    }
    // 引擎将来若增加 S11+，不静默丢掉：未知键原样追加并标注。
    for (key, value) in r.signals.iter() {
        if !known_signal(key) {
            grid = grid.child(signal_cell(key, "未知信号（本页未定义含义）", Some(value)));
        }
    }
    card = card.child(grid);

    // null 披露：清单与载荷不一致时，以载荷为准并说明不一致。
    if !nulls.is_empty() {
        let engine_list = &r.diagnostics.null_signals;
        let mut text = format!("null 信号（词法层无法可靠计算）：{}", nulls.join(" · "));
        if engine_list.is_empty() {
            text.push_str(
                "；引擎的 null_signals 清单为空，但载荷里确实有 null —— 本页以载荷为准。",
            );
        }
        card = card.child(
            div()
                .class("banner info")
                .child(div().class("banner-title").child("哪些信号算不出来"))
                .child(div().class("banner-body").child(text))
                .child(div().class("banner-body").child(
                    if r.diagnostics.null_signals_note.trim().is_empty() {
                        "引擎没有给出 null_signals_note（null 原因未说明）。".to_string()
                    } else {
                        format!("引擎原文：{}", r.diagnostics.null_signals_note)
                    },
                )),
        );
    }

    // 引擎清单说 null、载荷却给了数值：这是矛盾，必须说出来。
    let contradictions: Vec<String> = r
        .diagnostics
        .null_signals
        .iter()
        .filter(|k| matches!(r.signals.get(*k), Some(Some(_))))
        .cloned()
        .collect();
    if !contradictions.is_empty() {
        card = card.child(
            div()
                .class("banner warn")
                .child(div().class("banner-title").child("引擎清单与载荷不一致"))
                .child(div().class("banner-body").child(format!(
                    "null_signals 声称这些信号为 null，但载荷给了数值：{}。本页按载荷显示数值；这个不一致本身值得复查。",
                    contradictions.join(" · ")
                ))),
        );
    }

    card
}

fn signal_cell(key: &str, label: &str, value: Option<&Option<f64>>) -> Div {
    let (text, class, title) = match value {
        Some(Some(v)) => (
            fmt_ratio(*v),
            "signal-value",
            format!("{key} = {v}（引擎原值）"),
        ),
        Some(None) => (
            "—".to_string(),
            "signal-null",
            format!("{key} = null（词法层算不出来）"),
        ),
        None => (
            "缺失".to_string(),
            "signal-null",
            format!("{key} 在载荷里不存在（与 null 不同）"),
        ),
    };
    div()
        .class("signal")
        .title(title)
        .child(div().class("signal-name").child(format!("{key} · {label}")))
        .child(div().class(class).child(text))
}

/// 信号短名。**引擎没有提供 signal 的 label**，这里的文字是从
/// `moonGit/src/graph/patchconf.cj` 的计算变量翻译的展示近似：
///   478 S1  resolvedRefs/totalRefs          引用可解析率
///   481 S2  anotDecls/totalDecls            带类型注解的声明占比
///   484 S3  callScore/totalCalls            调用解析得分
///   487 S4  resolvedImports/totalImports    导入可解析率
///   494 S5  1 - useBeforeDef/totalRefs      无 use-before-def 率
///   496 S6  花括号配平（0/1）               花括号配平
///   497 S7  词法层恒 null                    契约一致率（需接口实现对照）
///   499 S8  compatCalls/totalCrossCalls     跨模块调用兼容率
///   509 S9  结构正常率（环/违规扣减）        结构正常率
///   514 S10 与 S1 同口径                    patch 内自洽
fn signal_label(i: u32) -> &'static str {
    match i {
        1 => "引用可解析率",
        2 => "带类型注解的声明占比",
        3 => "调用解析得分",
        4 => "导入可解析率",
        5 => "无 use-before-def 率",
        6 => "花括号配平",
        7 => "契约一致率（词法层不计算）",
        8 => "跨模块调用兼容率",
        9 => "结构正常率",
        10 => "patch 内自洽（同 S1 口径）",
        _ => "未知信号",
    }
}

fn known_signal(key: &str) -> bool {
    matches!(
        key,
        "S1" | "S2" | "S3" | "S4" | "S5" | "S6" | "S7" | "S8" | "S9" | "S10"
    )
}

fn null_signal_keys(r: &PatchReport) -> Vec<String> {
    r.signals
        .iter()
        .filter(|(_, v)| v.is_none())
        .map(|(k, _)| k.clone())
        .collect()
}

fn uncertain_card(r: &PatchReport, cx: &mut Context<AppRoot>) -> Div {
    let mut card = div()
        .class("card")
        .child(
            div()
                .class("card-head")
                .child(div().class("card-title").child("uncertain（词法层拿不准的引用）"))
                .child(div().class("spacer"))
                .child(div().class("chip chip-sm idle").child(format!(
                    "{} 条",
                    r.uncertain.len()
                ))),
        )
        .child(div().class("t-caption").child(
            "这不是错误清单，而是交给外部 agent 复核的输入；agent 的裁决发生在 Layer-2（本页之外）。",
        ));

    if r.uncertain.is_empty() {
        return card.child(div().class("empty").child(
            div().class("empty-body").child(
                "引擎没有列出 uncertain。这不等于补丁没有问题：词法层只报它无法解析的引用，\
                 S7 等信号在词法层恒为 null。",
            ),
        ));
    }

    for (idx, u) in r.uncertain.iter().enumerate() {
        card = card.child(uncertain_item(idx, u, cx));
    }
    card
}

fn uncertain_item(idx: usize, u: &Uncertain, cx: &mut Context<AppRoot>) -> Div {
    let loc = ref_line(&u.context_ref);
    let issue = if u.issue.trim().is_empty() {
        "issue 未给出".to_string()
    } else {
        u.issue.clone()
    };
    let detail = if u.detail.trim().is_empty() {
        "引擎没有给出 detail（不是「没有疑问」）".to_string()
    } else {
        u.detail.clone()
    };
    let mut body = div()
        .class("finding")
        .child(
            div()
                .class("finding-head")
                .child(div().class("chip chip-sm warn").child(issue.clone()))
                .child(
                    div()
                        .class("mono t-ellipsis")
                        .title(u.id.clone())
                        .child(if u.id.trim().is_empty() {
                            "id 未给出".to_string()
                        } else {
                            u.id.clone()
                        }),
                )
                .child(div().class("spacer"))
                .child(div().class("finding-meta mono").child(loc.clone())),
        )
        .child(div().class("finding-body").child(detail));

    // 空候选不是「没有候选」：它是「词法层没找到，需要 agent 去查」。
    let candidates = if u.candidates.is_empty() {
        "候选：无（词法层没有找到；需要外部 agent 用 grep/read 补证据 —— 不是「没有候选」）"
            .to_string()
    } else {
        format!("候选：{}", u.candidates.join(" · "))
    };
    body = body.child(div().class("t-caption").child(candidates));

    let copy = format!(
        "{} · {} · {}\n{}",
        u.id,
        issue,
        loc,
        if u.detail.trim().is_empty() {
            "(detail 未给出)"
        } else {
            u.detail.as_str()
        }
    );
    body.child(div().class("row-sm").child(btn_action(
        "复制这条",
        "btn btn-sm btn-ghost",
        format!("patch-copy-uncertain-{idx}"),
        Action::Patch(PatchAction::CopyText {
            text: copy,
            label: "uncertain 条目".to_string(),
        }),
        cx,
    )))
}

fn entities_card(state: &AppState, r: &PatchReport, cx: &mut Context<AppRoot>) -> Div {
    let low: Vec<usize> = r
        .entities
        .iter()
        .enumerate()
        .filter(|(_, e)| e.confidence < LOW_CONFIDENCE)
        .map(|(i, _)| i)
        .collect();
    let show_low = state.ui.patch.expanded.contains(SHOW_LOW);

    let mut card = div()
        .class("card")
        .child(
            div()
                .class("card-head")
                .child(div().class("card-title").child("entities（算法层解析出的声明）"))
                .child(div().class("spacer"))
                .child(div().class("chip chip-sm idle").child(format!(
                    "{} 条",
                    r.entities.len()
                ))),
        );

    if r.entities.is_empty() {
        return card.child(div().class("empty").child(
            div().class("empty-body").child(
                "引擎没有解析出实体。可能是补丁没有新增声明，或语言不受支持；\
                 这是「没解析到」，不是「补丁没有改动」。",
            ),
        ));
    }

    if !low.is_empty() {
        let mut row = div().class("row-wrap");
        row = row.child(div().class("t-caption").child(format!(
            "{} 条 confidence < {:.2} 默认折叠（不是隐藏错误，只是先看高置信度的）。",
            low.len(),
            LOW_CONFIDENCE
        )));
        row = row.child(btn_action(
            if show_low {
                "收起低置信度".to_string()
            } else {
                format!("展开 {} 条低置信度", low.len())
            },
            "btn btn-sm btn-ghost",
            "patch-toggle-low",
            Action::Patch(PatchAction::ToggleShowLowEntities),
            cx,
        ));
        card = card.child(row);
    }

    for (idx, e) in r.entities.iter().enumerate() {
        if e.confidence < LOW_CONFIDENCE && !show_low {
            continue;
        }
        card = card.child(entity_item(state, idx, e, cx));
    }
    card
}

fn entity_item(state: &AppState, idx: usize, e: &PatchEntity, cx: &mut Context<AppRoot>) -> Div {
    let key = format!("{ENTITY_PREFIX}{idx}:{}", e.id);
    let open = state.ui.patch.expanded.contains(&key);
    let loc = file_line(&e.file, e.line);
    let kind = if e.kind.trim().is_empty() {
        "kind 未给出".to_string()
    } else {
        e.kind.clone()
    };
    let low = e.confidence < LOW_CONFIDENCE;

    let head = div()
        .class("finding-head")
        .child(div().class(format!("chip chip-sm {}", if low { "warn" } else { "info" })).child(kind))
        .child(
            div()
                .class("mono t-ellipsis")
                .title(loc.clone())
                .child(loc.clone()),
        )
        .child(div().class("spacer"))
        .child(div().class("finding-meta").child(format!(
            "conf {:.2} · 关系 {} · {}",
            e.confidence,
            e.relations.len(),
            if open { "收起 ▴" } else { "展开 ▾" }
        )));

    let mut item = div()
        .class("finding")
        .child(head)
        .on_click(cx.listener({
            let key = key.clone();
            move |this, _, _window, cx| {
                cx.stop_propagation();
                this.state
                    .dispatch(Action::Patch(PatchAction::ToggleEntity(key.clone())));
                cx.notify();
            }
        }));

    if open {
        item = item.child(
            div()
                .class("t-caption")
                .child(if e.id.trim().is_empty() {
                    "id 未给出".to_string()
                } else {
                    format!("id：{}", e.id)
                }),
        );
        if e.relations.is_empty() {
            item = item.child(div().class("t-caption").child(
                "引擎没有记录关系 —— 这是「没解析到」，不是「没有依赖」。",
            ));
        } else {
            let mut rels = div().class("list");
            for rel in &e.relations {
                rels = rels.child(
                    div()
                        .class("list-item")
                        .child(div().class("chip chip-sm idle").child(if rel.type_.trim().is_empty() {
                            "type 未给出".to_string()
                        } else {
                            rel.type_.clone()
                        }))
                        .child(
                            div()
                                .class("list-main mono t-ellipsis")
                                .title(rel.target.clone())
                                .child(if rel.target.trim().is_empty() {
                                    "target 未给出".to_string()
                                } else {
                                    rel.target.clone()
                                }),
                        )
                        .child(div().class("list-side t-num").child(format!("{:.2}", rel.confidence))),
                );
            }
            item = item.child(rels);
        }
        let copy = format!(
            "{} · {} · conf {:.2}\n{}",
            e.id,
            loc,
            e.confidence,
            e.relations
                .iter()
                .map(|r| format!("{} -> {} ({:.2})", r.type_, r.target, r.confidence))
                .collect::<Vec<_>>()
                .join("\n")
        );
        item = item.child(div().class("row-sm").child(btn_action(
            "复制实体",
            "btn btn-sm btn-ghost",
            format!("patch-copy-entity-{idx}"),
            Action::Patch(PatchAction::CopyText {
                text: copy,
                label: "补丁实体".to_string(),
            }),
            cx,
        )));
    }
    item
}

fn diagnostics_card(r: &PatchReport) -> Div {
    let d = &r.diagnostics;
    let mut card = div()
        .class("card")
        .child(div().class("card-title").child("诊断（引擎解析到的补丁事实）"));

    let mut kvs = div().class("row-wrap");
    for (k, v) in [
        ("实体", d.total_entities),
        ("关系", d.total_relations),
        ("解析错误", d.parse_errors),
        ("补丁文件", d.patch_files),
        ("新增行", d.added_lines),
    ] {
        kvs = kvs.child(
            div()
                .class("kv")
                .child(div().class("kv-k").child(k.to_string()))
                .child(div().class("kv-v t-num").child(v.to_string())),
        );
    }
    card = card.child(kvs);

    if d.parse_errors > 0 {
        card = card.child(
            div()
                .class("banner warn")
                .child(div().class("banner-title").child(format!(
                    "{} 个解析错误",
                    d.parse_errors
                )))
                .child(div().class("banner-body").child(
                    "补丁里可能有不被支持的语法；S1–S10 的覆盖面因此不完整，不要把低分/高分当成完整结论。",
                )),
        );
    }
    if d.patch_files == 0 {
        card = card.child(
            div()
                .class("banner warn")
                .child(div().class("banner-title").child("解析到 0 个补丁文件"))
                .child(div().class("banner-body").child(
                    "diff 可能为空，或格式不被接受；S1–S10 的分母为 0，null/缺失信号不能当「没有问题」。",
                )),
        );
    }
    card.child(div().class("t-caption").child(
        "这些数字描述引擎解析到的补丁，不是仓库规模。",
    ))
}

// ══════════════════════════════════════════════════════════════════════
// Layer-3 合并
// ══════════════════════════════════════════════════════════════════════

fn merge_card(state: &AppState, selected: Option<&str>, cx: &mut Context<AppRoot>) -> Div {
    let mut card = div()
        .class("card")
        .child(
            div()
                .class("card-head")
                .child(div().class("card-title").child("Layer-3 合并终稿"))
                .child(div().class("spacer"))
                .child(div().class("chip chip-sm unknown").child("规则合并，不是真值")),
        );

    match &state.patch_merged {
        Load::Idle => {
            card = card.child(div().class("t-caption").child(
                "尚未合并。合并需要 algorithm.json（Layer-1）与 agent.json（Layer-2，外部 agent 产出）；\
                 上面的输入区填写路径或粘贴 JSON。",
            ));
        }
        Load::Loading => {
            card = card.child(
                div()
                    .class("row")
                    .child(spinner())
                    .child(div().class("t-caption").child("合并中…（同步执行）")),
            );
        }
        Load::Failed(e) => {
            let copy = e.user_message();
            card = card.child(
                div()
                    .class("banner err")
                    .child(div().class("banner-title").child("合并失败（不是「没有问题」）"))
                    .child(div().class("banner-body").child(copy.clone()))
                    .child(div().class("banner-action").child(btn_action(
                        "复制错误",
                        "btn btn-sm btn-ghost",
                        "patch-copy-merge-error",
                        Action::Patch(PatchAction::CopyText {
                            text: copy,
                            label: "合并错误".to_string(),
                        }),
                        cx,
                    ))),
            );
        }
        Load::Ready(m) => {
            card = card.child(merged_view(state, m, selected, cx));
        }
    }
    card
}

fn merged_view(
    state: &AppState,
    m: &MergedReport,
    selected: Option<&str>,
    cx: &mut Context<AppRoot>,
) -> Div {
    let mut out = div().class("stack");

    // 归属：合并结果本身没有项目名；用本次会话记住的 Layer-1 归属做提示。
    if let (Some(o), Some(s)) = (recorded_result_project(state), selected) {
        if o != s {
            out = out.child(
                div()
                    .class("banner warn")
                    .child(div().class("banner-title").child("合并结果可能不是当前项目的"))
                    .child(div().class("banner-body").child(format!(
                        "本次会话最近一次 Layer-1 分析属于「{o}」，而你现在选的是「{s}」。\
                         合并器只认两份 JSON 文件，不核对项目；请确认文件来源。"
                    ))),
            );
        }
    }

    if !m.sources.agent {
        out = out.child(
            div()
                .class("banner warn")
                .child(
                    div()
                        .class("banner-title")
                        .child("agent 来源缺失（sources.agent=false）"),
                )
                .child(div().class("banner-body").child(
                    "这份合并里没有任何条目来自 agent 裁决；算法层条目仍只是算法层。\
                     不要把它读成「AI 认为没有问题」。",
                )),
        );
    }
    if !m.sources.algorithm {
        out = out.child(
            div()
                .class("banner warn")
                .child(
                    div()
                        .class("banner-title")
                        .child("算法来源缺失（sources.algorithm=false）"),
                )
                .child(div().class("banner-body").child(
                    "合并器没有读到算法层实体；这通常是输入文件不对，而不是「补丁没有结构」。",
                )),
        );
    }
    if m.diagnostics.deferred > 0 {
        out = out.child(
            div()
                .class("banner warn")
                .child(div().class("banner-title").child(format!(
                    "{} 条疑点未被 agent 裁决（deferred）",
                    m.diagnostics.deferred
                )))
                .child(div().class("banner-body").child(
                    "它们按原样保留在合并结果里，不是「已解决」，也不是「没有疑问」。",
                )),
        );
    }

    let alg_overall = state.patch.ready().map(|r| r.overall);
    let valid = m.signals.values().filter(|v| v.is_some()).count();
    let overall_text = if valid == 0 {
        "—".to_string()
    } else {
        fmt_ratio(m.overall)
    };
    let delta = alg_overall.map(|a| m.overall - a);
    let delta_text = match delta {
        Some(d) => format!(
            "算法层 {} → 合并 {}（{}{:.3}）。差值来自合并规则（resolved 打折、ambiguous 固定 0.5 等），不是重新测量。",
            fmt_ratio(alg_overall.unwrap_or(0.0)),
            fmt_ratio(m.overall),
            if d >= 0.0 { "+" } else { "" },
            d
        ),
        None => "本次会话没有可比的算法层结果；合并 overall 只反映合并器的输入。".to_string(),
    };

    out = out.child(
        div()
            .class("row")
            .child(
                div()
                    .class("stat")
                    .child(div().class("stat-value").child(overall_text))
                    .child(div().class("stat-label").child("合并 overall（0–1）")),
            )
            .child(div().class("divider-v"))
            .child(
                div()
                    .class("stack-sm grow")
                    .child(ratio_bar(m.overall, ratio_tone(m.overall)))
                    .child(div().class("t-caption").child(delta_text)),
            ),
    );

    let mut facts = div().class("row-wrap");
    facts = facts.child(source_chip("algorithm", m.sources.algorithm));
    facts = facts.child(source_chip("agent", m.sources.agent));
    facts = facts.child(div().class("chip chip-sm idle").child(format!(
        "确定自算法 {} · agent 复核 {} · deferred {}",
        m.diagnostics.certain_from_algorithm,
        m.diagnostics.reviewed_by_agent,
        m.diagnostics.deferred
    )));
    facts = facts.child(div().class("chip chip-sm idle").child(if m.schema.trim().is_empty() {
        "schema 未给出".to_string()
    } else {
        m.schema.clone()
    }));
    out = out.child(facts);

    // alerts
    let mut alerts = div().class("stack-sm");
    if m.alerts.is_empty() {
        alerts = alerts.child(div().class("t-caption").child(
            "没有告警。这只表示合并规则没有触发告警，不是「已核实无误」。",
        ));
    } else {
        for a in &m.alerts {
            alerts = alerts.child(alert_row(a));
        }
    }
    out = out.child(alerts);

    // entities
    let show_all = state.ui.patch.expanded.contains(MERGED_SHOW_ALL);
    let shown_n = if show_all {
        m.entities.len()
    } else {
        m.entities.len().min(MERGED_PAGE)
    };
    let mut list = div().class("list");
    if m.entities.is_empty() {
        list = list.child(div().class("empty").child(div().class("empty-body").child(
            "合并结果没有实体。不是「没有问题」：检查两份输入是否都真的被读到了。",
        )));
    } else {
        for (idx, e) in m.entities.iter().take(shown_n).enumerate() {
            list = list.child(merged_entity(idx, e, cx));
        }
    }
    out = out.child(
        div()
            .class("stack-sm")
            .child(
                div()
                    .class("row-between")
                    .child(div().class("t-h3").child("合并后的条目"))
                    .child(div().class("t-caption").child(format!(
                        "显示 {shown_n} / 共 {}",
                        m.entities.len()
                    ))),
            )
            .child(list),
    );
    if m.entities.len() > MERGED_PAGE {
        let mut foot = div().class("row-wrap");
        if show_all {
            foot = foot.child(div().class("t-caption").child(format!(
                "已显示全部 {} 条；界面默认只显示前 {MERGED_PAGE} 条。",
                m.entities.len()
            )));
            foot = foot.child(btn_action(
                format!("只显示前 {MERGED_PAGE} 条"),
                "btn btn-sm btn-ghost",
                "patch-merged-show-less",
                Action::Patch(PatchAction::ToggleShowAllMerged),
                cx,
            ));
        } else {
            foot = foot.child(div().class("t-caption").child(format!(
                "界面只显示前 {MERGED_PAGE} 条 / 共 {} 条。",
                m.entities.len()
            )));
            foot = foot.child(btn_action(
                format!("显示全部（{} 条）", m.entities.len()),
                "btn btn-sm",
                "patch-merged-show-all",
                Action::Patch(PatchAction::ToggleShowAllMerged),
                cx,
            ));
        }
        out = out.child(foot);
    }

    out = out.child(div().class("t-caption").child(
        "合并层只按规则记账：它没有重新读代码、没有重新判断，也没有执行 AI。",
    ));
    out
}

fn source_chip(name: &str, on: bool) -> Div {
    let tone = if on { Tone::Ok } else { Tone::Warn };
    div()
        .class(format!("chip chip-sm {}", tone.class()))
        .child(format!(
            "{name} 来源：{}",
            if on { "有" } else { "无（缺失）" }
        ))
}

fn alert_row(a: &Alert) -> Div {
    let level = if a.level.trim().is_empty() {
        "level 未给出".to_string()
    } else {
        a.level.clone()
    };
    div()
        .class(format!("alert {}", a.level_class()))
        .child(div().class("chip chip-sm").child(level))
        .child(
            div()
                .class("grow")
                .child(div().class("t-body").child(if a.type_.trim().is_empty() {
                    "type 未给出".to_string()
                } else {
                    a.type_.clone()
                }))
                .child(div().class("t-caption").child(if a.detail.trim().is_empty() {
                    "引擎没有给出 detail".to_string()
                } else {
                    a.detail.clone()
                })),
        )
}

fn merged_entity(idx: usize, e: &MergedEntity, cx: &mut Context<AppRoot>) -> Div {
    let source_tone = match e.source.as_str() {
        "algorithm" => Tone::Info,
        "agent" => Tone::Accent,
        "deferred" => Tone::Warn,
        _ => Tone::Idle,
    };
    let mut item = div()
        .class("finding")
        .child(
            div()
                .class("finding-head")
                .child(div().class(format!("chip chip-sm {}", source_tone.class())).child(
                    if e.source.trim().is_empty() {
                        "source 未给出".to_string()
                    } else {
                        e.source.clone()
                    },
                ))
                .child(
                    div()
                        .class("t-body t-ellipsis")
                        .title(e.id.clone())
                        .child(e.label()),
                )
                .child(div().class("spacer"))
                .child(div().class("finding-meta t-num").child(format!("{:.2}", e.confidence))),
        )
        .child(div().class("t-caption mono t-ellipsis").child(e.location()));

    // agent 条目必须带裁决证据；缺了要明说，不能让它看起来像“已核实”。
    if e.source == "agent" {
        let mut facts = div().class("row-wrap");
        facts = facts.child(div().class("chip chip-sm idle").child(format!(
            "verdict：{}",
            e.verdict.clone().unwrap_or_else(|| "未给出".to_string())
        )));
        if let Some(reason) = e.reason.as_ref().filter(|r| !r.trim().is_empty()) {
            facts = facts.child(div().class("t-caption").child(format!("理由：{reason}")));
        } else {
            facts = facts.child(div().class("t-caption warn").child(
                "agent 没有给理由 —— 不是「无问题」，是这条裁决无法复核。",
            ));
        }
        match e.evidence_refs.as_ref() {
            Some(refs) if !refs.is_empty() => {
                facts = facts.child(div().class("t-caption").child(format!(
                    "证据引用：{}",
                    refs.join(" · ")
                )));
            }
            _ => {
                facts = facts.child(div().class("t-caption warn").child(
                    "agent 没有给 evidence_refs —— 按任务书要求应给；没有证据的裁决不能当已核实。",
                ));
            }
        }
        item = item.child(facts);
    } else if e.source == "algorithm" {
        item = item.child(div().class("t-caption").child(
            "算法层条目（未经 agent 复核）；它出现在合并结果里不等于被确认。",
        ));
    }

    let copy = format!(
        "{} · {} · source={} · conf={:.2}",
        e.id,
        e.location(),
        e.source,
        e.confidence
    );
    item.child(btn_action(
        "复制",
        "btn btn-sm btn-ghost",
        format!("patch-copy-merged-{idx}"),
        Action::Patch(PatchAction::CopyText {
            text: copy,
            label: "合并条目".to_string(),
        }),
        cx,
    ))
}

// ══════════════════════════════════════════════════════════════════════
// 小件
// ══════════════════════════════════════════════════════════════════════

fn file_line(file: &str, line: i64) -> String {
    let file = file.trim();
    if file.is_empty() {
        "位置未给出".to_string()
    } else if line > 0 {
        format!("{file}:{line}")
    } else {
        file.to_string()
    }
}

fn ref_line(r: &Ref) -> String {
    file_line(&r.file, r.line)
}

fn fmt_ratio(v: f64) -> String {
    if !v.is_finite() {
        return "非有限值".to_string();
    }
    let s = format!("{v:.3}");
    let trimmed = s.trim_end_matches('0').trim_end_matches('.');
    if trimmed.is_empty() || trimmed == "-0" {
        "0".to_string()
    } else {
        trimmed.to_string()
    }
}

fn ratio_tone(v: f64) -> Tone {
    if v >= 0.8 {
        Tone::Ok
    } else if v >= 0.6 {
        Tone::Info
    } else if v >= 0.4 {
        Tone::Warn
    } else {
        Tone::Err
    }
}

/// 动态几何：core 没有 `ui::bar`；只在这里用 inline style 表达宽度。
fn ratio_bar(fraction: f64, tone: Tone) -> Div {
    let pct = (fraction.clamp(0.0, 1.0) * 100.0) as f32;
    div().class("bar").child(
        div()
            .class(format!("bar-fill {}", tone.class()))
            .style(format!("width: {pct:.2}%;")),
    )
}

fn spinner() -> Div {
    div().class("spinner")
}

fn seg_item(
    label: String,
    on: bool,
    id: impl Into<SharedString>,
    action: Action,
    cx: &mut Context<AppRoot>,
) -> Div {
    div()
        .class(if on { "seg-item on" } else { "seg-item" })
        .id(id)
        .child(label)
        .on_click(cx.listener(move |this, _, _window, cx| {
            cx.stop_propagation();
            this.state.dispatch(action.clone());
            cx.notify();
        }))
}

fn btn_action(
    label: impl Into<String>,
    classes: &str,
    id: impl Into<SharedString>,
    action: Action,
    cx: &mut Context<AppRoot>,
) -> Div {
    div()
        .class(classes.to_string())
        .id(id)
        .child(label.into())
        .on_click(cx.listener(move |this, _, _window, cx| {
            cx.stop_propagation();
            this.state.dispatch(action.clone());
            cx.notify();
        }))
}
