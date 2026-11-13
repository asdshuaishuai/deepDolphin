// confidence.rs — 代码置信度：单项目结构疑点汇总。
//
// 归属：boardconf 组。数据入口：
//   `graph confidence <项目> --json` → `AppState.confidence: Load<ConfidenceReport>`。
//
// 【这一页说的是什么】
//   引擎给的 `score` 是**结构性疑点的汇总**（0..100），不是正确性证明。
//   `semantics` 原文必须显示；`astUsed=false` 时必须把 `astNote` 原样显示 ——
//   那意味着本次是**词法级近似**，函数粒度信号由长度/嵌套/魔法数/空体等启发式
//   顶替，吞错与重复体仍缺失。把词法近似渲染成「语法树已分析」是本页最严重的谎报。
//
// 【三个「没有」必须分开】
//   · `Load::Idle`        —— 还没运行；不是「0 条疑点」；
//   · `Load::Ready(空)`   —— 引擎跑过了，返回 0 条；这也不是「代码没问题」；
//   · `Load::Failed`      —— 分析失败；原因原样显示，不是「没有疑点」。
//   · `Load::Failed(Cancelled)` —— 用户主动停止：中性态，不报「失败」。
//
// 【筛选状态放在哪】
//   本阶段 core 的 `UiState` 只有 `ConfidenceForm { project, min_weight, expanded }`
//   （app.rs 冻结，不能改）。所以 kind 筛选与「结果属于哪个项目」的标记
//   编码进 `expanded` 的带前缀键里：
//     `kind:<kind>`      —— 当前类型筛选（同一时刻只有一个）；
//     `result:<项目名>`  —— 最近一次**成功**分析归属的项目；
//     `findings:show-all`—— 疑点表已展开到全部（默认只显示前 40 条）。
//   前缀保证与疑点展开键（`finding:…`）不冲突。这是局部折中，已在交付说明里注明。
//
// 【结果过期】
//   选中的项目一变，旧结果仍留在 `AppState.confidence` 里。页面必须指出
//   「现在显示的是 A 的结果，而你选的是 B」，而不是让用户以为已经分析了 B。
//
// 【本阶段边界】
//   `graph confidence` 在**后台线程**执行（根视图的 `start_pending_job`），
//   窗口不再冻结；「停止」置取消旗标，`engine.rs` 会 kill 子进程并返回
//   `EngineError::Cancelled`（与超时分开，不报成「分析失败」）。

#![allow(dead_code)]

use crate::app::{Action, AppAction, AppRoot, AppState, Load, RefreshScope};
use crate::models::{ConfidenceReport, Dimension, Finding, Tone};
use blenderui::prelude::*;
use std::collections::BTreeMap;

const KIND_PREFIX: &str = "kind:";
const RESULT_PREFIX: &str = "result:";
const SHOW_ALL: &str = "findings:show-all";
/// 引擎上限内的展示上限：超过时明确披露「显示前 40 / 共 N」。
const FINDINGS_PAGE: usize = 40;
/// 「高权重」的门槛：与 PLAN §9.6 一致。
const HIGH_WEIGHT: i64 = 8;

/// 置信度页的临时 UI 状态（本阶段字段都在 core 的 `ConfidenceForm`；
/// 本结构保留给后续「筛选面板折叠/搜索」这类本页私有状态）。
#[derive(Debug, Clone, Default)]
pub struct ConfidenceUi {}

#[derive(Debug, Clone)]
pub enum ConfidenceAction {
    /// 对当前项目运行 `graph confidence`。
    Run,
    /// 显式选择项目（空清单时无效果）。
    SetProject(String),
    /// 设置权重门槛（0 = 全部，8 = 只看高权重）。
    SetMinWeight(i64),
    /// 按 kind 过滤（None = 全部）。
    SetKind(Option<String>),
    /// 一次清掉类型与权重两个筛选。
    ClearFindingFilters,
    /// 展开/收起一条疑点的证据。
    ToggleFinding(String),
    /// 疑点表在「前 40 条 / 全部」之间切换。
    ToggleShowAll,
    /// 复制 `--llm` 复核任务书（取回的是纯文本，不是 JSON）。
    CopyLlmPrompt,
    /// 复制一段文本（证据 / 根路径）。
    CopyText { text: String, label: String },
}

pub fn reduce(state: &mut AppState, action: ConfidenceAction) {
    match action {
        ConfidenceAction::Run => {
            let Some(project) = effective_project(state, &state.ui.confidence.project) else {
                state.feedback = Some(crate::app::Feedback::failure(
                    "先选择一个项目（置信度是单项目分析）；当前项目清单为空或不可读",
                ));
                return;
            };
            state.ui.confidence.project = Some(project.clone());
            clear_result_project(state);
            state.dispatch(Action::App(AppAction::RunConfidence));
            // 只有真的拿到报告才记归属：失败时记「结果属于 X」会让下一次
            // 渲染把一条错误说成「X 的结果」。
            if matches!(&state.confidence, Load::Ready(_)) {
                mark_result_project(state, &project);
            }
        }
        ConfidenceAction::SetProject(name) => {
            state.ui.confidence.project = Some(name);
        }
        ConfidenceAction::SetMinWeight(w) => {
            // 只接受两档：0 与 8。其它值（例如手改配置）按「不是高权重」处理。
            state.ui.confidence.min_weight = if w >= HIGH_WEIGHT { HIGH_WEIGHT } else { 0 };
        }
        ConfidenceAction::SetKind(kind) => set_kind(state, kind),
        ConfidenceAction::ClearFindingFilters => {
            set_kind(state, None);
            state.ui.confidence.min_weight = 0;
        }
        ConfidenceAction::ToggleFinding(key) => {
            if !state.ui.confidence.expanded.remove(&key) {
                state.ui.confidence.expanded.insert(key);
            }
        }
        ConfidenceAction::ToggleShowAll => {
            if !state.ui.confidence.expanded.remove(SHOW_ALL) {
                state.ui.confidence.expanded.insert(SHOW_ALL.to_string());
            }
        }
        ConfidenceAction::CopyLlmPrompt => {
            let Some(project) = effective_project(state, &state.ui.confidence.project) else {
                state.feedback = Some(crate::app::Feedback::failure("先选择一个项目"));
                return;
            };
            state.ui.confidence.project = Some(project);
            state.dispatch(Action::App(AppAction::RunConfidenceLlmPrompt));
        }
        ConfidenceAction::CopyText { text, label } => {
            state.copy(&text, &label);
        }
    }
}

pub fn on_enter(state: &mut AppState) {
    // 幂等兜底：没有显式选择时，落到「当前路由项目 → 第一个项目」。
    // ⚠️ 本阶段 core 的 `on_enter_route` 还没有调用各页面的 `on_enter`
    // （views/mod.rs 的 Route::Confidence 只做了 ensure_status）；
    // 因此渲染侧与运行按钮都各自再做一次同样的默认推导，见 `effective_project`。
    state.ensure_status();
    if state.ui.confidence.project.is_none() {
        if let Some(p) = effective_project(state, &None) {
            state.ui.confidence.project = Some(p);
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// 默认项目 / 前缀键
// ══════════════════════════════════════════════════════════════════════

/// 当前生效的项目：显式选择优先；否则当前路由项目；再否则第一个项目。
///
/// 显式选择即使已不在项目清单里也**原样返回**：静默换成第一个项目会让用户
/// 以为分析的是他选的那个。让引擎报「未找到项目」比悄悄换对象诚实。
fn effective_project(state: &AppState, explicit: &Option<String>) -> Option<String> {
    let explicit = explicit.clone().filter(|n| !n.trim().is_empty());
    state
        .chosen_project(&explicit)
        .or_else(|| state.projects().first().map(|p| p.name.clone()))
}

fn selected_kind(state: &AppState) -> Option<String> {
    state
        .ui
        .confidence
        .expanded
        .iter()
        .find_map(|k| k.strip_prefix(KIND_PREFIX).map(str::to_string))
}

fn set_kind(state: &mut AppState, kind: Option<String>) {
    let keep: Vec<String> = state
        .ui
        .confidence
        .expanded
        .iter()
        .filter(|k| !k.starts_with(KIND_PREFIX))
        .cloned()
        .collect();
    state.ui.confidence.expanded = keep.into_iter().collect();
    if let Some(k) = kind.filter(|k| !k.trim().is_empty()) {
        state
            .ui
            .confidence
            .expanded
            .insert(format!("{KIND_PREFIX}{k}"));
    }
}

pub(crate) fn clear_result_project(state: &mut AppState) {
    state
        .ui
        .confidence
        .expanded
        .retain(|k| !k.starts_with(RESULT_PREFIX));
}

pub(crate) fn mark_result_project(state: &mut AppState, project: &str) {
    clear_result_project(state);
    state
        .ui
        .confidence
        .expanded
        .insert(format!("{RESULT_PREFIX}{project}"));
}

fn recorded_result_project(state: &AppState) -> Option<String> {
    state
        .ui
        .confidence
        .expanded
        .iter()
        .find_map(|k| k.strip_prefix(RESULT_PREFIX).map(str::to_string))
}

/// 结果归属：优先本页记录；旧结果（没有记录）退回 `root` 与项目路径的精确比对。
/// 两者都拿不到 ⇒ None，页面显示 root 原文并说「归属无法核验」。
fn result_owner(state: &AppState, r: &ConfidenceReport) -> Option<String> {
    recorded_result_project(state).or_else(|| {
        state
            .projects()
            .iter()
            .find(|p| !p.path.is_empty() && p.path == r.root)
            .map(|p| p.name.clone())
    })
}

// ══════════════════════════════════════════════════════════════════════
// 渲染
// ══════════════════════════════════════════════════════════════════════

pub fn render(state: &AppState, cx: &mut Context<AppRoot>) -> Div {
    let total = state.projects().len();
    let selected = effective_project(state, &state.ui.confidence.project);
    let sub = if state.status.is_none() {
        if state.error.is_some() {
            "项目清单读不出来；置信度需要项目清单".to_string()
        } else {
            "正在读取项目清单…".to_string()
        }
    } else {
        format!("单项目 · 结构置信度（不是正确性证明） · {total} 个项目可选")
    };

    let mut body = div().class("stack");

    // status 读取失败：先把它说清楚。置信度页没有项目清单就没有可分析对象。
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
                    "conf-retry-status",
                    Action::App(AppAction::Refresh(RefreshScope::All)),
                    cx,
                ))),
        );
    }

    if total == 0 && state.error.is_none() && state.status.is_some() {
        body = body.child(
            div()
                .class("empty")
                .child(div().class("empty-icon").child("◎"))
                .child(div().class("empty-title").child("还没有可分析的项目"))
                .child(div().class("empty-body").child(
                    "置信度是单项目分析。先到「扫描与添加」注册一个项目，再回来运行。",
                )),
        );
    }

    body = body.child(controls(state, selected.as_deref(), cx));

    body = body.child(match &state.confidence {
        Load::Idle => idle_card(),
        Load::Loading => loading_card(),
        Load::Failed(e) if e.is_cancelled() => {
            crate::views::stopped_card("置信度分析")
        }
        Load::Failed(e) => failed_card(e.user_message(), cx),
        Load::Ready(r) => results(state, r, selected.as_deref(), cx),
    });

    crate::views::page_shell(state, "代码置信度", sub, cx, body)
}

fn controls(state: &AppState, selected: Option<&str>, cx: &mut Context<AppRoot>) -> Div {
    let mut card = div()
        .class("card")
        .child(
            div()
                .class("card-head")
                .child(div().class("card-title").child("分析对象"))
                .child(div().class("spacer"))
                .child(div().class("chip chip-sm info").child("单项目")),
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
                format!("conf-project-{}", p.name),
                Action::Confidence(ConfidenceAction::SetProject(p.name.clone())),
                cx,
            ));
        }
        card = card.child(picker);
        // 空串不算「显式选择」：否则下面会显示一句「当前选择：「」」。
        let explicit = state
            .ui
            .confidence
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

    let running = state.confidence.is_loading();
    let mut row = div().class("row-wrap");
    if selected.is_none() {
        row = row.child(div().class("btn btn-accent is-disabled").child("运行分析"));
        row = row.child(div().class("t-caption").child("先选择项目"));
    } else if running {
        row = row.child(
            div()
                .class("btn btn-accent btn-busy")
                .child(spinner())
                .child("分析中…"),
        );
        row = row.child(
            div()
                .class("btn btn-sm danger")
                .id("conf-stop")
                .child("停止")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.stop_confidence();
                    cx.notify();
                })),
        );
    } else {
        row = row.child(btn_action(
            "运行分析",
            "btn btn-accent",
            "conf-run",
            Action::Confidence(ConfidenceAction::Run),
            cx,
        ));
    }

    if selected.is_some() && !running {
        row = row.child(btn_action(
            "复制 –llm 复核提示词",
            "btn",
            "conf-llm",
            Action::Confidence(ConfidenceAction::CopyLlmPrompt),
            cx,
        ));
    } else {
        row = row.child(div().class("btn btn-ghost is-disabled").child("复制 –llm 复核提示词"));
    }

    // 权重门槛：两档，不是一个没有尽头的滑杆。
    let high = state.ui.confidence.min_weight >= HIGH_WEIGHT;
    row = row.child(
        div()
            .class("seg")
            .child(seg_item(
                "全部权重".to_string(),
                !high,
                "conf-weight-all",
                Action::Confidence(ConfidenceAction::SetMinWeight(0)),
                cx,
            ))
            .child(seg_item(
                format!("只看高权重（≥{HIGH_WEIGHT}）"),
                high,
                "conf-weight-high",
                Action::Confidence(ConfidenceAction::SetMinWeight(HIGH_WEIGHT)),
                cx,
            )),
    );
    card = card.child(row);

    card = card.child(div().class("t-caption").child(
        "「运行分析」在后台线程执行（`graph confidence` 超时 300s）：窗口不再冻结，可点「停止」终止引擎进程；停止不是超时，不会报成「分析失败」。`--llm` 复核提示词仍是同步执行。",
    ));
    card
}

// ══════════════════════════════════════════════════════════════════════
// 四态
// ══════════════════════════════════════════════════════════════════════

fn idle_card() -> Div {
    div()
        .class("empty")
        .child(div().class("empty-icon").child("◎"))
        .child(div().class("empty-title").child("尚未运行置信度分析"))
        .child(div().class("empty-body").child(
            "点上方「运行分析」。引擎会返回 dimensions / findings / byKind；本页不预设疑点种类。\
             结果是结构性线索的汇总，不是正确性证明。",
        ))
}

fn loading_card() -> Div {
    div()
        .class("card")
        .child(
            div()
                .class("row")
                .child(spinner())
                .child(div().class("card-title").child("分析中…")),
        )
        .child(div().class("t-caption").child(
            "词法级扫描可能需要几秒到更久；分析在后台线程执行，窗口保持响应，可点上方「停止」取消。",
        ))
        .child(div().class("skeleton-line"))
        .child(div().class("skeleton-line"))
        .child(div().class("skeleton-line"))
}

fn failed_card(message: String, cx: &mut Context<AppRoot>) -> Div {
    let copy = message.clone();
    div()
        .class("banner err")
        .child(div().class("banner-title").child("分析失败（不是「没有疑点」）"))
        .child(div().class("banner-body").child(message))
        .child(
            div()
                .class("banner-action")
                .child(btn_action(
                    "重试",
                    "btn btn-sm btn-accent",
                    "conf-retry",
                    Action::Confidence(ConfidenceAction::Run),
                    cx,
                ))
                .child(btn_action(
                    "复制错误",
                    "btn btn-sm btn-ghost",
                    "conf-copy-error",
                    Action::Confidence(ConfidenceAction::CopyText {
                        text: copy,
                        label: "置信度错误".to_string(),
                    }),
                    cx,
                )),
        )
}

// ══════════════════════════════════════════════════════════════════════
// 结果
// ══════════════════════════════════════════════════════════════════════

fn results(
    state: &AppState,
    r: &ConfidenceReport,
    selected: Option<&str>,
    cx: &mut Context<AppRoot>,
) -> Div {
    let mut out = div().class("stack");

    // 结果归属：这是防「选B看A」的唯一一道闸。
    let owner = result_owner(state, r);
    match (&owner, selected) {
        (Some(o), Some(s)) if o != s => {
            out = out.child(
                div()
                    .class("banner warn")
                    .child(div().class("banner-title").child("这份结果不是当前选择项目的"))
                    .child(div().class("banner-body").child(format!(
                        "结果显示的是「{o}」的分析；你现在选的是「{s}」。点「运行分析」才会重新扫描 {s}。"
                    ))),
            );
        }
        (Some(o), None) => {
            out = out.child(
                div()
                    .class("banner warn")
                    .child(div().class("banner-title").child("结果有归属，但当前没有可选项目"))
                    .child(div().class("banner-body").child(format!(
                        "结果显示的是「{o}」的分析；当前项目清单为空或不可读，无法确认 {o} 还在注册表里。"
                    ))),
            );
        }
        (None, _) => {
            out = out.child(
                div()
                    .class("banner unknown")
                    .child(div().class("banner-title").child("结果归属无法核验"))
                    .child(div().class("banner-body").child(format!(
                        "引擎只给了 root，没有项目名；无法把它和项目清单对上。若你刚刚运行过分析，它可能失败并保留了上一次的报告。root：{}",
                        if r.root.is_empty() {
                            "（root 为空）".to_string()
                        } else {
                            r.root.clone()
                        }
                    ))),
            );
        }
        _ => {}
    }

    out = out.child(score_card(r, owner.as_deref()));
    out = out.child(ast_card(r));
    out = out.child(capped_total_disclosure(r));
    out = out.child(dimensions_card(r));
    out = out.child(kinds_card(r));
    out = out.child(findings_card(state, r, cx));
    out = out.child(penalty_card(r));
    out
}

fn score_card(r: &ConfidenceReport, owner: Option<&str>) -> Div {
    let tone = score_tone(r.score);
    let mut head = div()
        .class("card-head")
        .child(div().class("card-title").child("结构置信度"))
        .child(div().class("spacer"));
    if let Some(o) = owner {
        head = head.child(div().class("chip chip-sm info").child(format!("项目：{o}")));
    }
    head = head.child(div().class("chip chip-sm idle").child(format!(
        "{} 个文件",
        r.files_analyzed
    )));

    let semantics = if r.semantics.trim().is_empty() {
        "引擎没有给出 semantics（口径未说明）——不能假定分数是正确率。".to_string()
    } else {
        r.semantics.clone()
    };

    let mut card = div()
        .class("card")
        .child(head)
        .child(
            div()
                .class("row")
                .child(
                    div()
                        .class("score")
                        .child(div().class("score-value").child(format!("{}", r.score)))
                        .child(div().class("score-label").child("结构分 / 100")),
                )
                .child(div().class("divider-v"))
                .child(
                    div()
                        .class("stack-sm grow")
                        .child(ratio_bar(r.score as f64 / 100.0, tone))
                        .child(div().class("t-caption").child(
                            "分数越高 = 结构性疑点越少；它不是正确率，也不是测试覆盖。",
                        ))
                        .child(
                            div()
                                .class("t-caption mono t-ellipsis")
                                .title(r.root.clone())
                                .child(if r.root.trim().is_empty() {
                                    "root 未给出".to_string()
                                } else {
                                    format!("root：{}", r.root)
                                }),
                        ),
                ),
        )
        .child(div().class("t-caption").child(semantics));

    // 0 个文件必须单独说：它可能是路径不对/没有源文件，也可能是引擎没给这个字段
    // （模型默认 0，无法区分）。无论哪种，分数都不能代表这份代码。
    if r.files_analyzed <= 0 {
        card = card.child(
            div()
                .class("banner unknown")
                .child(
                    div()
                        .class("banner-title")
                        .child("引擎分析了 0 个文件（或没有给 filesAnalyzed）"),
                )
                .child(div().class("banner-body").child(
                    "这不是「代码很干净」：没有分析到文件时，score / findings 都不代表这份代码的结构质量。",
                )),
        );
    }
    card
}

fn ast_card(r: &ConfidenceReport) -> Div {
    let note = r.ast_note.trim().to_string();
    match r.ast_used {
        Some(true) => {
            let mut card = div()
                .class("banner ok")
                .child(div().class("banner-title").child("语法树已启用（astUsed=true）"))
                .child(div().class("banner-body").child(
                    "本次分析包含语法树级信号；词法级仍可能参与，具体以引擎 semantics 为准。",
                ));
            if !note.is_empty() {
                card = card.child(div().class("banner-body").child(format!("astNote：{note}")));
            }
            card
        }
        Some(false) => div()
            .class("banner warn")
            .child(
                div()
                    .class("banner-title")
                    .child("词法级近似（astUsed=false）：这不是语法树分析"),
            )
            .child(div().class("banner-body").child(if note.is_empty() {
                "引擎没有给出 astNote（降级原因未说明）。函数粒度信号可能是启发式近似。".to_string()
            } else {
                format!("引擎原文：{note}")
            })),
        None => div()
            .class("banner unknown")
            .child(
                div()
                    .class("banner-title")
                    .child("引擎没有告知语法树状态（astUsed 缺键）"),
            )
            .child(div().class("banner-body").child(format!(
                "缺键不是 false，也不是 true —— 不能假定已启用，也不能断定是词法级。{}",
                if note.is_empty() {
                    "astNote 也是空的。".to_string()
                } else {
                    format!("astNote：{note}")
                }
            ))),
    }
}

fn capped_total_disclosure(r: &ConfidenceReport) -> Div {
    match r.capped_total {
        Some(true) => div()
            .class("banner warn")
            .child(
                div()
                    .class("banner-title")
                    .child("疑点总数被引擎截断（cappedTotal=true）"),
            )
            .child(div().class("banner-body").child(
                "下面的疑点表是**样本**，不是全量。比例、排名、「最多的类型」都不能当全体结论。",
            )),
        // false 是「没截断」，不必刷一条屏；缺键必须单独说，见下。
        // 仍返回一个 hidden 占位，避免 `.stack` 的 gap 留下一段空白。
        Some(false) => div().class("hidden").id("capped-total-none"),
        None => div()
            .class("banner unknown")
            .child(
                div()
                    .class("banner-title")
                    .child("cappedTotal 缺键：无法判断疑点是否被截断"),
            )
            .child(div().class("banner-body").child(
                "缺键 ≠ 未截断。旧引擎或该路径没写这个字段时，页面不能替你保证下面的表是全量。",
            )),
    }
}

fn dimensions_card(r: &ConfidenceReport) -> Div {
    let card = div()
        .class("card")
        .child(
            div()
                .class("card-head")
                .child(div().class("card-title").child("维度（引擎给几条画几条）"))
                .child(div().class("spacer"))
                .child(div().class("chip chip-sm idle").child(format!(
                    "{} 条",
                    r.dimensions.len()
                ))),
        );

    if r.dimensions.is_empty() {
        return card.child(div().class("empty").child(
            div()
                .class("empty-body")
                .child("引擎没有返回维度明细。这是「没给」，不是「0 个维度」或「每个维度都满分」。"),
        ));
    }

    let mut dims = div().class("dims");
    for d in &r.dimensions {
        dims = dims.child(dimension_row(d));
    }
    card.child(dims)
}

fn dimension_row(d: &Dimension) -> Div {
    let label = if !d.label.trim().is_empty() {
        d.label.clone()
    } else if !d.id.trim().is_empty() {
        d.id.clone()
    } else {
        "未命名维度".to_string()
    };
    let tone = score_tone(d.score);
    div()
        .class("dim-row")
        .title(format!(
            "id={} · penalty={} · findings={}",
            d.id, d.penalty, d.findings
        ))
        .child(div().class("dim-name t-ellipsis").child(label))
        .child(
            div()
                .class("dim-bar")
                .child(ratio_bar(d.score as f64 / 100.0, tone)),
        )
        .child(
            div()
                .class("dim-val")
                .child(format!("{} · {} 条", d.score, d.findings)),
        )
}

fn kinds_card(r: &ConfidenceReport) -> Div {
    let mut card = div()
        .class("card")
        .child(
            div()
                .class("card-head")
                .child(div().class("card-title").child("疑点类型汇总（引擎 byKind）"))
                .child(div().class("spacer"))
                .child(div().class("chip chip-sm idle").child(format!(
                    "{} 类",
                    r.by_kind.len()
                ))),
        );

    if r.by_kind.is_empty() {
        card = card.child(div().class("t-caption").child(
            "引擎没有给出类型明细。这是「没给」，不是「没有类型」。",
        ));
    } else {
        let mut row = div().class("row-wrap");
        for k in &r.by_kind {
            let label = if !k.label.trim().is_empty() {
                k.label.clone()
            } else if !k.kind.trim().is_empty() {
                k.kind.clone()
            } else {
                "未命名类型".to_string()
            };
            row = row.child(
                div()
                    .class("chip")
                    .title(format!("kind={} · weight={}", k.kind, k.weight))
                    .child(format!("{label} · {} 条 · 权重 {}", k.count, k.weight)),
            );
        }
        card = card.child(row);
    }

    match r.capped_kind {
        Some(true) => card = card.child(
            div()
                .class("banner warn")
                .child(
                    div()
                        .class("banner-title")
                        .child("类型明细被引擎截断（cappedKind=true）"),
                )
                .child(div().class("banner-body").child(
                    "上面的类型汇总不是全部类型；疑点表仍按引擎返回的 findings 逐条列出。",
                )),
        ),
        Some(false) => {}
        None => card = card.child(
            div()
                .class("banner unknown")
                .child(
                    div()
                        .class("banner-title")
                        .child("cappedKind 缺键：无法判断类型明细是否完整"),
                )
                .child(div().class("banner-body").child(
                    "缺键 ≠ 未截断；不要把「类型条数」当作完整清单。",
                )),
        ),
    }
    card
}

fn findings_card(state: &AppState, r: &ConfidenceReport, cx: &mut Context<AppRoot>) -> Div {
    let selected_kind = selected_kind(state);
    let min_weight = state.ui.confidence.min_weight.max(0);
    let show_all = state.ui.confidence.expanded.contains(SHOW_ALL);

    // 类型计数按**当前权重门槛**统计：让 chip 上的数字与点进去看到的行数一致。
    let mut kind_counts: BTreeMap<String, usize> = BTreeMap::new();
    for f in &r.findings {
        if f.weight >= min_weight {
            *kind_counts.entry(f.kind.clone()).or_insert(0) += 1;
        }
    }

    let filtered: Vec<(usize, &Finding)> = r
        .findings
        .iter()
        .enumerate()
        .filter(|(_, f)| {
            f.weight >= min_weight
                && selected_kind
                    .as_ref()
                    .map(|k| &f.kind == k)
                    .unwrap_or(true)
        })
        .collect();
    let shown_n = if show_all {
        filtered.len()
    } else {
        filtered.len().min(FINDINGS_PAGE)
    };
    let shown = &filtered[..shown_n];

    let kind_labels: BTreeMap<String, String> = r
        .by_kind
        .iter()
        .map(|k| {
            (
                k.kind.clone(),
                if k.label.trim().is_empty() {
                    k.kind.clone()
                } else {
                    k.label.clone()
                },
            )
        })
        .collect();

    let mut card = div()
        .class("card")
        .child(
            div()
                .class("card-head")
                .child(div().class("card-title").child("疑点表"))
                .child(div().class("spacer"))
                .child(div().class("chip chip-sm idle").child(format!(
                    "显示 {shown_n} / 筛后 {} / 共 {}",
                    filtered.len(),
                    r.findings.len()
                ))),
        )
        .child(div().class("t-caption").child(
            "file:line 是引擎给的定位；权重是引擎原值（不是概率）。点一行展开证据。",
        ));

    // 类型筛选 chips：类型清单从 findings 派生（而不是只从 byKind 派生），
    // 这样即使 byKind 被截断，每一条疑点仍然有可点到的类型。
    let mut filters = div().class("row-wrap");
    let all_on = selected_kind.is_none();
    filters = filters.child(seg_item(
        format!("全部 {}", kind_counts.values().sum::<usize>()),
        all_on,
        "conf-kind-all",
        Action::Confidence(ConfidenceAction::SetKind(None)),
        cx,
    ));
    for (kind, count) in &kind_counts {
        let label = kind_labels.get(kind).cloned().unwrap_or_else(|| {
            if kind.trim().is_empty() {
                "类型未给出".to_string()
            } else {
                kind.clone()
            }
        });
        let on = selected_kind.as_deref() == Some(kind.as_str());
        filters = filters.child(seg_item(
            format!("{label} {count}"),
            on,
            format!("conf-kind-{kind}"),
            Action::Confidence(ConfidenceAction::SetKind(Some(kind.clone()))),
            cx,
        ));
    }
    // 选中的类型在当前权重门槛下 0 条时，仍然保留 chip：否则筛选条件
    // 会「看不见地」生效，用户只看到一张空表却找不到是谁把它滤空的。
    if let Some(sel) = selected_kind.as_deref() {
        if !kind_counts.contains_key(sel) {
            let label = kind_labels.get(sel).cloned().unwrap_or_else(|| sel.to_string());
            filters = filters.child(seg_item(
                format!("{label} 0"),
                true,
                "conf-kind-current",
                Action::Confidence(ConfidenceAction::SetKind(None)),
                cx,
            ));
        }
    }
    if selected_kind.is_some() || min_weight > 0 {
        filters = filters.child(btn_action(
            "清除筛选",
            "btn btn-sm btn-ghost",
            "conf-clear-filters",
            Action::Confidence(ConfidenceAction::ClearFindingFilters),
            cx,
        ));
    }
    card = card.child(filters);

    // 筛选披露：分母必须是「引擎给的全部」。
    if selected_kind.is_some() || min_weight > 0 {
        let mut parts: Vec<String> = Vec::new();
        if let Some(k) = &selected_kind {
            parts.push(format!("类型 = {k}"));
        }
        if min_weight > 0 {
            parts.push(format!("weight ≥ {min_weight}"));
        }
        card = card.child(div().class("t-caption").child(format!(
            "筛选：{}；命中 {}/{} 条。筛选不会改变引擎结论，只改变这里显示哪几条。",
            parts.join(" · "),
            filtered.len(),
            r.findings.len()
        )));
    }

    if r.capped_total == Some(true) {
        card = card.child(div().class("banner warn").child(div().class("banner-body").child(
            "引擎已截断疑点总数：下表不是全量，筛后计数也只是样本内的计数。",
        )));
    }

    if r.findings.is_empty() {
        return card.child(
            div()
                .class("empty")
                .child(div().class("empty-icon").child("✓"))
                .child(div().class("empty-title").child("引擎返回 0 条疑点"))
                .child(div().class("empty-body").child(
                    "0 是引擎的结论，不是「代码正确」：它只覆盖词法/语法树能看见的结构。\
                     若 cappedTotal=true，这个 0 还可能是截断后的 0。",
                )),
        );
    }

    if filtered.is_empty() {
        return card.child(
            div()
                .class("empty")
                .child(div().class("empty-icon").child("○"))
                .child(div().class("empty-title").child("当前筛选下没有疑点"))
                .child(div().class("empty-body").child(format!(
                    "这不是「没有疑点」：引擎共 {} 条，被当前筛选排除了全部。",
                    r.findings.len()
                )))
                .child(
                    div().class("row-sm").child(btn_action(
                        "清除筛选",
                        "btn btn-sm btn-accent",
                        "conf-clear-empty",
                        Action::Confidence(ConfidenceAction::ClearFindingFilters),
                        cx,
                    )),
                ),
        );
    }

    let table = div()
        .class("table")
        .child(
            div()
                .class("thead")
                .child(div().class("th").child("类型"))
                .child(div().class("th").child("位置"))
                .child(div().class("th").child("符号"))
                .child(div().class("th").child("权重"))
                .child(div().class("th").child("证据")),
        );
    let mut tbody = div().class("tbody");
    for (idx, f) in shown.iter().copied() {
        let key = finding_key(idx, f);
        let open = state.ui.confidence.expanded.contains(&key);
        let kind_label = kind_labels.get(&f.kind).cloned().unwrap_or_else(|| {
            if f.kind.trim().is_empty() {
                "类型未给出".to_string()
            } else {
                f.kind.clone()
            }
        });
        let loc = file_line(&f.file, f.line);
        let symbol = if f.symbol.trim().is_empty() {
            "符号未给出".to_string()
        } else {
            f.symbol.clone()
        };
        let toggle = Action::Confidence(ConfidenceAction::ToggleFinding(key));
        tbody = tbody.child(
            div()
                .class("tr")
                .id(format!("conf-finding-{idx}"))
                .child(div().class("td").child(chip_text(kind_label.clone(), weight_tone(f.weight))))
                .child(
                    div()
                        .class("td mono t-ellipsis")
                        .title(loc.clone())
                        .child(loc.clone()),
                )
                .child(
                    div()
                        .class("td t-ellipsis")
                        .title(symbol.clone())
                        .child(symbol),
                )
                .child(div().class("td-num").child(format!("{}", f.weight)))
                .child(
                    div()
                        .class("td")
                        .child(if open { "收起 ▴" } else { "证据 ▾" }),
                )
                .on_click(cx.listener(move |this, _, _window, cx| {
                    cx.stop_propagation();
                    this.state.dispatch(toggle.clone());
                    cx.notify();
                })),
        );
        if open {
            let evidence = if f.evidence.trim().is_empty() {
                "引擎给出了这条疑点，但证据文本为空 —— 不等于「没有问题」，需要外部复核。".to_string()
            } else {
                f.evidence.clone()
            };
            let copy = format!("{kind_label} · {loc} · weight {}\n{evidence}", f.weight);
            tbody = tbody.child(
                div()
                    .class("finding-body")
                    .child(div().class("t-caption").child(format!(
                        "{} · 类型 {} · 权重 {}（引擎原值）",
                        loc,
                        if f.kind.trim().is_empty() {
                            "未给出"
                        } else {
                            f.kind.as_str()
                        },
                        f.weight
                    )))
                    .child(div().class("t-body").child(evidence))
                    .child(
                        div().class("row-sm").child(btn_action(
                            "复制这条",
                            "btn btn-sm btn-ghost",
                            format!("conf-copy-{idx}"),
                            Action::Confidence(ConfidenceAction::CopyText {
                                text: copy,
                                label: "置信度疑点".to_string(),
                            }),
                            cx,
                        )),
                    ),
            );
        }
    }
    card = card.child(table.child(tbody));

    // 分页披露：**界面自己砍的**那一层也要说自己砍了。
    if filtered.len() > FINDINGS_PAGE {
        let mut foot = div().class("row-wrap");
        if show_all {
            foot = foot.child(div().class("t-caption").child(format!(
                "已显示全部 {} 条（引擎返回 {} 条）。",
                filtered.len(),
                r.findings.len()
            )));
            foot = foot.child(btn_action(
                "只显示前 40 条",
                "btn btn-sm btn-ghost",
                "conf-show-less",
                Action::Confidence(ConfidenceAction::ToggleShowAll),
                cx,
            ));
        } else {
            foot = foot.child(div().class("t-caption").child(format!(
                "界面只显示前 {FINDINGS_PAGE} 条 / 筛后 {} 条 / 共 {} 条。",
                filtered.len(),
                r.findings.len()
            )));
            foot = foot.child(btn_action(
                format!("显示全部（{} 条）", filtered.len()),
                "btn btn-sm",
                "conf-show-all",
                Action::Confidence(ConfidenceAction::ToggleShowAll),
                cx,
            ));
        }
        card = card.child(foot);
    }

    card
}

fn penalty_card(r: &ConfidenceReport) -> Div {
    let mut card = div()
        .class("card")
        .child(
            div()
                .class("card-head")
                .child(div().class("card-title").child("按文件扣分（引擎 penaltyByFile）"))
                .child(div().class("spacer"))
                .child(div().class("chip chip-sm idle").child(format!(
                    "{} 个文件",
                    r.penalty_by_file.len()
                ))),
        );

    if r.penalty_by_file.is_empty() {
        return card.child(div().class("t-caption").child(
            "引擎没有给出文件扣分。这是「没给」，不是「没有文件被扣分」。",
        ));
    }

    let max = r
        .penalty_by_file
        .iter()
        .map(|p| p.penalty.max(0))
        .max()
        .unwrap_or(0)
        .max(1);
    let mut list = div().class("list");
    for p in r.penalty_by_file.iter().take(8) {
        let frac = (p.penalty.max(0) as f64) / (max as f64);
        list = list.child(
            div()
                .class("list-item")
                .child(
                    div()
                        .class("list-main mono t-ellipsis")
                        .title(p.file.clone())
                        .child(if p.file.trim().is_empty() {
                            "文件未给出".to_string()
                        } else {
                            p.file.clone()
                        }),
                )
                .child(div().class("dim-bar").child(ratio_bar(frac, Tone::Warn)))
                .child(div().class("list-side t-num").child(format!("{}", p.penalty))),
        );
    }
    card = card.child(list);
    if r.penalty_by_file.len() > 8 {
        card = card.child(div().class("t-caption").child(format!(
            "只显示前 8 个文件 / 引擎给出 {} 个。",
            r.penalty_by_file.len()
        )));
    }
    card.child(div().class("t-caption").child(
        "这是按文件汇总的扣分，不是文件里的问题条数；载荷没有截断标志，不能断言这里就是全部文件。",
    ))
}

// ══════════════════════════════════════════════════════════════════════
// 小件
// ══════════════════════════════════════════════════════════════════════

fn finding_key(idx: usize, f: &Finding) -> String {
    format!("finding:{idx}:{}:{}:{}", f.kind, f.file, f.line)
}

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

fn score_tone(score: i64) -> Tone {
    if score >= 80 {
        Tone::Ok
    } else if score >= 60 {
        Tone::Info
    } else if score >= 40 {
        Tone::Warn
    } else {
        Tone::Err
    }
}

fn weight_tone(w: i64) -> Tone {
    if w >= 12 {
        Tone::Err
    } else if w >= 8 {
        Tone::Warn
    } else if w >= 4 {
        Tone::Info
    } else {
        Tone::Idle
    }
}

fn chip_text(text: String, tone: Tone) -> Div {
    div()
        .class(format!("chip chip-sm {}", tone.class()))
        .child(text)
}

/// 动态几何：`ui::bar` 尚不存在（本阶段 core 没有 ui 模块），
/// 宽度只能在这里用 inline style 表达。除宽度外不写任何样式。
fn ratio_bar(fraction: f64, tone: Tone) -> Div {
    let pct = (fraction.clamp(0.0, 1.0) * 100.0) as f32;
    div().class("bar").child(
        div()
            .class(format!("bar-fill {}", tone.class()))
            .style(format!("width: {pct:.2}%;")),
    )
}

/// core 还没有 `ui::spinner`（本阶段没有 ui 模块），按设计系统的 `.spinner` 类自理。
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
