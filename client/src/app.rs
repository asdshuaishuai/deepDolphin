// 契约面：本阶段先冻结 API，页面的下一阶段消费者尚未落地；未使用不是缺陷。
#![allow(dead_code)]

// app.rs — 应用状态、路由与动作。
//
// 【同步 / 后台的分界】绝大多数读命令仍在 UI 线程同步执行（首屏在开窗前预取，
// 见 `bootstrap`；status/dashboard/milestone 都是百毫秒级）。两个**长命令**
// （`graph confidence` / `graph patchconf`，超时 300s）走后台 Job：
//   · 动作层只把 `JobRequest` 放进 `AppState::pending_job`（同步语义不变）；
//   · 根视图的 `start_pending_job` 用 `UiSender` 起线程，完成后回到 UI 线程
//     更新同一个 `AppState`；
//   · 「停止」置 `AtomicBool`，`engine.rs` 在 25ms 内 kill 子进程并返回
//     `EngineError::Cancelled`（与超时分开）。
// 仍未后台化的读命令会阻塞，这是已知边界；不要在此基础上再加第二套状态。
//
// 【兼容层】`views/{sidebar,dashboard,project,milestones}.rs` 是本轮不改的 v0 页面，
// 由后续页面开发者重写。它们直接读 `status/milestones/error/commit_draft/feedback/
// artifacts/last_refresh_note` 并调用 `refresh/select/git_action/milestone_action/
// probe_artifact/open_artifact`。这些字段与方法**保留原签名**（v0 兼容层），
// 新页面应使用 `Load<T>` / `UiState` / `dispatch(Action)`；两者共享同一份状态，
// 不是两套事实来源。
//
// 【诚实披露】
//   · `Load<T>` 四态；`Reading<T>` 三态（Known / NotRead）；缺键是 None，不是 0；
//   · 反馈分成功/失败；写操作成功后**后续刷新失败不许把写操作报成失败**（见
//     `refresh_after_write`：只发 toast，不覆盖 feedback）。

use crate::engine::{
    self, Artifact, Engine, EngineError, GitOp, MilestoneOp, UpdateOutcome,
};
use crate::models::{
    self, ConfidenceReport, DashboardData, DocsPayload, GitStatusPayload,
    JournalPayload, MergedReport, MilestoneList, PatchReport, Project,
    RegistryEntry, RenderCheck, ScanPayload, StatusEnvelope,
};
use crate::views;
use blenderui::prelude::*;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

// 新页面按 PLAN §7 的 `crate::app::Tone` / `Reading` / `Truncation` 路径使用。
#[allow(unused_imports)]
pub use crate::models::{BoardColumn, Reading, ScopeBadge, Tone, Truncation};
// 派生纯函数（PLAN §7.8）只有一个实现处：models.rs。这里只是把它挂到 core 的
// 公共入口上，页面组不需要知道它住在哪个模块。
#[allow(unused_imports)]
pub use crate::models::{
    age_days, board_column, commit_count_label, dirty_label, human_ago, is_pending,
    journal_scope_badge, language_disclosures, milestone_lower_bound, milestone_rate,
    pending_count, short_iso, status_tone, status_word,
};
/// URL 脱敏的唯一实现（错误文本与派生展示共用）。
#[allow(unused_imports)]
pub use crate::engine::redact_url;

// ══════════════════════════════════════════════════════════════════════
// 语言 / 路由
// ══════════════════════════════════════════════════════════════════════

/// 引擎事实语言的选择（**不是**界面语言：客户端文案目前只有中文）。
/// 引擎只有 `zh` / `en` 两条事实语言；`zh-TW` 用中文事实，
/// `ja` **没有**对应的引擎语言 —— 不许回落到 en（那会把日文选择写成英文事实）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Lang {
    ZhCn,
    En,
    ZhTw,
    Ja,
}

impl Default for Lang {
    fn default() -> Self {
        Lang::ZhCn
    }
}

impl Lang {
    /// 侧栏选择器只列出**真的会改变引擎事实语言**的两档。
    /// `ZhTw` / `Ja` 仍可被 `--lang` 解析（旧脚本兼容），但它们没有独立的
    /// 引擎路径：繁体走 zh，日文没有对应语言 —— 放成可点选项只会制造假切换。
    pub fn all() -> [Lang; 2] {
        [Lang::ZhCn, Lang::En]
    }

    pub fn label(&self) -> &'static str {
        match self {
            Lang::ZhCn => "中文",
            Lang::En => "EN",
            Lang::ZhTw => "繁體",
            Lang::Ja => "日本語",
        }
    }

    /// 引擎事实语言代码（写入 `config set language`）。
    ///
    /// `None` = 引擎没有这条渲染路径。**不许把不支持的值悄悄映射到 en**：
    /// 那会让「切到日本語」实际把引擎事实语言改成英文，而界面上没有任何
    /// 对应的日文文案 —— 两边都在说假话。
    pub fn engine_code(&self) -> Option<&'static str> {
        match self {
            Lang::ZhCn | Lang::ZhTw => Some("zh"),
            Lang::En => Some("en"),
            Lang::Ja => None,
        }
    }

    /// 归一到选择器里真实存在的选项：繁体没有独立的引擎路径，等同中文；
    /// 日文保持原样（没有引擎语言，`engine_code()` 返回 None）。
    pub fn engine_option(self) -> Lang {
        match self {
            Lang::ZhTw => Lang::ZhCn,
            other => other,
        }
    }

    pub fn parse(s: &str) -> Option<Lang> {
        match s {
            "zh" | "zh-cn" | "zh_cn" => Some(Lang::ZhCn),
            "en" => Some(Lang::En),
            "tw" | "zh-tw" | "zh_tw" => Some(Lang::ZhTw),
            "ja" => Some(Lang::Ja),
            _ => None,
        }
    }
}

/// 项目页的六个标签。v0 的 `Route::Project(String)` 用 `AppState.project_tab`
/// 承载当前标签 —— 这样旧页面（`Route::Project(name)` 构造）无需改签名，
/// 也不出现两个代表同一页面的路由变体。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProjectTab {
    Overview,
    Branches,
    Journal,
    Docs,
    Milestones,
    Graph,
}

impl Default for ProjectTab {
    fn default() -> Self {
        ProjectTab::Overview
    }
}

impl ProjectTab {
    pub fn all() -> [ProjectTab; 6] {
        [
            ProjectTab::Overview,
            ProjectTab::Branches,
            ProjectTab::Journal,
            ProjectTab::Docs,
            ProjectTab::Milestones,
            ProjectTab::Graph,
        ]
    }
    pub fn key(&self) -> &'static str {
        match self {
            ProjectTab::Overview => "overview",
            ProjectTab::Branches => "branches",
            ProjectTab::Journal => "journal",
            ProjectTab::Docs => "docs",
            ProjectTab::Milestones => "milestones",
            ProjectTab::Graph => "graph",
        }
    }
    pub fn title(&self) -> &'static str {
        match self {
            ProjectTab::Overview => "概览",
            ProjectTab::Branches => "分支",
            ProjectTab::Journal => "日志",
            ProjectTab::Docs => "文档",
            ProjectTab::Milestones => "里程碑",
            ProjectTab::Graph => "图谱",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SettingsTab {
    General,
    Ai,
    Automation,
    About,
}

impl Default for SettingsTab {
    fn default() -> Self {
        SettingsTab::General
    }
}

impl SettingsTab {
    pub fn all() -> [SettingsTab; 4] {
        [
            SettingsTab::General,
            SettingsTab::Ai,
            SettingsTab::Automation,
            SettingsTab::About,
        ]
    }
    pub fn key(&self) -> &'static str {
        match self {
            SettingsTab::General => "general",
            SettingsTab::Ai => "ai",
            SettingsTab::Automation => "automation",
            SettingsTab::About => "about",
        }
    }
    pub fn title(&self) -> &'static str {
        match self {
            SettingsTab::General => "通用",
            SettingsTab::Ai => "AI",
            SettingsTab::Automation => "自动化",
            SettingsTab::About => "关于",
        }
    }
}

/// 路由。`Project` 保持**元组变体**以兼容 v0 页面；当前标签在 `AppState::project_tab`。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Route {
    Dashboard,
    Board,
    Milestones,
    Confidence,
    Patch,
    Project(String),
    Scan,
    Settings(SettingsTab),
    Agent,
}

impl Route {
    /// 滚动容器 id 的后半段：`scroll-<key>`。
    pub fn key(&self) -> String {
        match self {
            Route::Dashboard => "dashboard".to_string(),
            Route::Board => "board".to_string(),
            Route::Milestones => "milestones".to_string(),
            Route::Confidence => "confidence".to_string(),
            Route::Patch => "patch".to_string(),
            Route::Project(name) => format!("project-{name}"),
            Route::Scan => "scan".to_string(),
            Route::Settings(tab) => format!("settings-{}", tab.key()),
            Route::Agent => "agent".to_string(),
        }
    }

    /// 项目页的滚动 id 还包含标签（切标签要回到顶部）。
    pub fn scroll_id(&self, tab: &ProjectTab) -> String {
        match self {
            Route::Project(name) => format!("scroll-project-{name}-{}", tab.key()),
            _ => format!("scroll-{}", self.key()),
        }
    }

    pub fn title(&self) -> &'static str {
        match self {
            Route::Dashboard => "项目群脉搏",
            Route::Board => "看板",
            Route::Milestones => "里程碑",
            Route::Confidence => "代码置信度",
            Route::Patch => "补丁体检",
            Route::Project(_) => "项目",
            Route::Scan => "扫描与添加",
            Route::Settings(tab) => tab.title(),
            Route::Agent => "AI 助手",
        }
    }

    /// 当前路由对应的项目名（非项目页返回 None）。
    pub fn project_name(&self) -> Option<&str> {
        match self {
            Route::Project(name) => Some(name.as_str()),
            _ => None,
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// 四态 / 反馈 / 浮层
// ══════════════════════════════════════════════════════════════════════

/// 四态加载：Idle / Loading / Ready / Failed。**空不是失败，失败不是空。**
#[derive(Debug, Clone)]
pub enum Load<T> {
    Idle,
    Loading,
    Ready(T),
    Failed(EngineError),
}

impl<T> Default for Load<T> {
    fn default() -> Self {
        Load::Idle
    }
}

impl<T> Load<T> {
    pub fn is_loading(&self) -> bool {
        matches!(self, Load::Loading)
    }
    pub fn ready(&self) -> Option<&T> {
        match self {
            Load::Ready(v) => Some(v),
            _ => None,
        }
    }
    pub fn failed(&self) -> Option<&EngineError> {
        match self {
            Load::Failed(e) => Some(e),
            _ => None,
        }
    }
}

/// 顶部反馈条。字段只有 `ok/text` 两个 —— v0 页面直接构造 `Feedback { ok, text }`，
/// 加字段会破坏它们的结构体字面量（编译期就红，不是运行期）。色调由 `ok` 派生。
#[derive(Debug, Clone)]
pub struct Feedback {
    pub ok: bool,
    pub text: String,
}

impl Feedback {
    pub fn success(text: impl Into<String>) -> Self {
        Feedback {
            ok: true,
            text: text.into(),
        }
    }
    pub fn failure(text: impl Into<String>) -> Self {
        Feedback {
            ok: false,
            text: text.into(),
        }
    }
    pub fn tone(&self) -> Tone {
        if self.ok {
            Tone::Ok
        } else {
            Tone::Err
        }
    }
}

/// 右下角 toast。`expires` 由 `tick()` 清理（没有后台线程）。
#[derive(Debug, Clone)]
pub struct Toast {
    pub id: u64,
    pub tone: Tone,
    pub title: String,
    pub body: String,
    pub action: Option<AppAction>,
    pub expires: Option<Instant>,
}

/// 确认弹层。确认按钮是**动词**（「删除里程碑」），不是「确定」。
#[derive(Debug, Clone)]
pub struct Confirm {
    pub title: String,
    pub body: String,
    pub confirm_label: String,
    pub danger: bool,
    pub action: PendingAction,
}

/// 确认后才执行的破坏性动作。存动作而不是闭包：可 Clone、可测、可日志。
#[derive(Debug, Clone)]
pub enum PendingAction {
    MilestoneRemove { project: String, name: String },
    MilestoneDrop { project: String, name: String },
    UpdateAll { deep: bool },
    UpdateProject { project: String, deep: bool },
    RemoveProject { name: String },
    GitOp { project: String, op: GitOp },
}

/// 后台 Job 请求（BUI 的 UiSender 由根视图在渲染时取出并 spawn 线程）。
///
/// 为什么不在 `AppState` 里直接 spawn：`AppState` 的方法没有 `Context`，
/// 拿不到 `UiSender` / `Entity<AppRoot>`。把「请求」留在状态里、由根视图消费，
/// 让动作层保持同步语义，也让 Job 的启动点只有一个。
pub enum JobRequest {
    Confidence {
        project: String,
        cancel: Arc<AtomicBool>,
    },
    Patch {
        project: String,
        /// 用户显式给的 diff 路径（空 = 读工作区）。
        explicit_diff: Option<String>,
        /// 项目仓库路径（读工作区 diff 用）；注册表里没有时是 None。
        repo_path: Option<String>,
        cancel: Arc<AtomicBool>,
    },
}

/// 补丁 Job 的完成结果：即使失败，已经解析出的 diff 路径也要带回，
/// 让界面能指出「这次用的是哪份 diff」。
struct PatchJobDone {
    diff_path: Option<String>,
    algorithm_path: Option<String>,
    /// 分析成功但 Layer-1 落盘失败时的原因（不能把成功的分析报成失败）。
    note: Option<String>,
    result: Result<PatchReport, EngineError>,
}

/// 后台补丁分析：读 diff → `graph patchconf` → 把 Layer-1 原始 JSON 写到临时文件。
///
/// 全程可取消（`Engine::with_cancel`）：三个子进程（git diff / patchconf）
/// 都会在旗标置位后 25ms 内被 kill。
fn run_patch_job(
    engine: &Engine,
    cancel: Arc<AtomicBool>,
    project: &str,
    explicit_diff: Option<String>,
    repo_path: Option<String>,
) -> PatchJobDone {
    let engine = engine.clone().with_cancel(cancel);
    let stamp = || {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0)
    };

    let patch_path: Result<PathBuf, EngineError> = if let Some(p) = explicit_diff {
        let path = PathBuf::from(&p);
        if path.is_file() {
            Ok(path)
        } else {
            Err(EngineError::Io(format!("diff 文件不存在：{p}")))
        }
    } else if let Some(repo) = repo_path {
        let repo = PathBuf::from(repo);
        let r = match engine.git_diff_head(&repo) {
            Ok(r) => r,
            Err(e) => return failed_patch_job(None, e),
        };
        if r.timed_out {
            return failed_patch_job(
                None,
                EngineError::Io("读取工作区 diff 超时（180s），已终止".to_string()),
            );
        }
        if !r.ok {
            let reason = r.stderr.trim();
            return failed_patch_job(
                None,
                EngineError::Io(if reason.is_empty() {
                    "读取工作区 diff 失败（git 没有输出原因）".to_string()
                } else {
                    format!("读取工作区 diff 失败：{reason}")
                }),
            );
        }
        if r.stdout.trim().is_empty() {
            return failed_patch_job(
                None,
                EngineError::Io(
                    "工作区没有未提交改动（git diff HEAD 为空）。先改点东西，或指定已有 diff 文件。"
                        .to_string(),
                ),
            );
        }
        let path = std::env::temp_dir().join(format!(
            "deepdolphin-patch-{}-{}.diff",
            std::process::id(),
            stamp()
        ));
        if let Err(e) = std::fs::write(&path, &r.stdout) {
            return failed_patch_job(
                None,
                EngineError::Io(format!("写临时 diff 失败（{}）：{e}", path.display())),
            );
        }
        Ok(path)
    } else {
        Err(EngineError::Io(
            "没有可用的项目路径，也没有显式 diff 文件".to_string(),
        ))
    };
    let patch_path = match patch_path {
        Ok(p) => p,
        Err(e) => return failed_patch_job(None, e),
    };
    let diff_text = patch_path.to_string_lossy().into_owned();

    let (report, raw) = match engine.patchconf_raw(project, &patch_path) {
        Ok(v) => v,
        Err(e) => return failed_patch_job(Some(diff_text), e),
    };

    // Layer-1 原始 stdout 就是 `--merge` 要的 algorithm.json。
    let algorithm = std::env::temp_dir().join(format!(
        "deepdolphin-algorithm-{}-{}.json",
        std::process::id(),
        stamp()
    ));
    if let Err(e) = std::fs::write(&algorithm, raw) {
        // 分析本身已经成功：报告照常交回，只把「没落盘」作为附加说明。
        return PatchJobDone {
            diff_path: Some(diff_text),
            algorithm_path: None,
            note: Some(format!(
                "写 Layer-1 报告失败（{}）：{e}",
                algorithm.display()
            )),
            result: Ok(report),
        };
    }
    PatchJobDone {
        diff_path: Some(diff_text),
        algorithm_path: Some(algorithm.to_string_lossy().into_owned()),
        note: None,
        result: Ok(report),
    }
}

fn failed_patch_job(diff_path: Option<String>, error: EngineError) -> PatchJobDone {
    PatchJobDone {
        diff_path,
        algorithm_path: None,
        note: None,
        result: Err(error),
    }
}

/// 右键/更多菜单。
#[derive(Debug, Clone)]
pub struct MenuItem {
    pub label: String,
    pub shortcut: Option<String>,
    pub danger: bool,
    pub action: AppAction,
}

#[derive(Debug, Clone)]
pub struct MenuState {
    pub x: f32,
    pub y: f32,
    pub items: Vec<MenuItem>,
}

#[derive(Debug, Clone, Default)]
pub struct PaletteState {
    pub query: String,
    pub selected: usize,
}

/// 命令面板条目（由 `AppState::palette_items()` 派生，不另存一份清单）。
#[derive(Debug, Clone)]
pub struct PaletteItem {
    pub label: String,
    pub kind: &'static str,
    pub action: AppAction,
}

/// 提交弹层。默认全选；干净/读失败/有文件三态分开。
#[derive(Debug, Clone)]
pub struct CommitSheet {
    pub project: String,
    pub message: String,
    pub status: Load<GitStatusPayload>,
    pub selected: BTreeSet<String>,
    pub busy: bool,
}

/// 新建里程碑表单。
#[derive(Debug, Clone, Default)]
pub struct MilestoneAddForm {
    pub project: String,
    pub name: String,
    pub tag: String,
    pub date: String,
    pub desc: String,
    pub busy: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MilestoneField {
    Project,
    Name,
    Tag,
    Date,
    Desc,
}

/// 通用模态（诊断/AI 结果/Agent 任务书）。内容由一次性动作产生。
#[derive(Debug, Clone)]
pub enum ModalState {
    Doctor(String),
    Text { title: String, body: String },
    AiResult(AiResultState),
}

#[derive(Debug, Clone, Default)]
pub struct AiResultState {
    pub title: String,
    pub raw: Load<String>,
    pub retry: Option<AppAction>,
}

#[derive(Debug, Clone)]
pub enum OpenTarget {
    Url(String),
    Reveal(String),
    Terminal(String),
}

#[derive(Debug, Clone)]
pub struct PendingCopy {
    pub text: String,
    pub label: String,
}

// ══════════════════════════════════════════════════════════════════════
// 页面临时状态（筛选 / 搜索 / 表单）
// ══════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum RangeFilter {
    #[default]
    All,
    D30,
    D7,
}

impl RangeFilter {
    pub fn all() -> [RangeFilter; 3] {
        [RangeFilter::All, RangeFilter::D30, RangeFilter::D7]
    }
    pub fn label(&self) -> &'static str {
        match self {
            RangeFilter::All => "全量",
            RangeFilter::D30 => "30 天",
            RangeFilter::D7 => "7 天",
        }
    }
    pub fn days(&self) -> Option<i64> {
        match self {
            RangeFilter::All => None,
            RangeFilter::D30 => Some(30),
            RangeFilter::D7 => Some(7),
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct DashboardFilters {
    pub range: RangeFilter,
    /// 提交类型筛选（`type` 原文）。None = 不筛。
    pub commit_type: Option<String>,
    pub lang_expanded: bool,
}

impl DashboardFilters {
    /// 时间筛选只影响项目卡，不改 KPI。时间读不出来的项目**保留**（加 chip 说明）。
    pub fn matches(&self, p: &Project) -> bool {
        if let Some(days) = self.range.days() {
            match models::age_days(&p.last_commit_at) {
                Reading::Known(d) => {
                    if d > days {
                        return false;
                    }
                }
                Reading::NotRead => {}
            }
        }
        if let Some(t) = &self.commit_type {
            if !p.commit_types.is_empty() && !p.commit_types.iter().any(|c| &c.type_ == t) {
                return false;
            }
        }
        true
    }
}

#[derive(Debug, Clone, Default)]
pub struct BoardFilters {
    pub query: String,
}

impl BoardFilters {
    pub fn matches(&self, p: &Project) -> bool {
        matches_query(&p.name, &self.query) || matches_query(&p.headline.clone().unwrap_or_default(), &self.query)
    }
}

#[derive(Debug, Clone, Default)]
pub struct MilestoneFilters {
    pub search: String,
    pub project: Option<String>,
    pub status: Option<String>,
}

impl MilestoneFilters {
    pub fn matches(&self, m: &models::Milestone) -> bool {
        // 项目筛选与展示同口径：缺 `projectName` 时退回 projectId，
        // 否则按 projectId 筛「无法核验项目名」的条目永远匹配不上。
        if let Some(p) = &self.project {
            if m.project_label() != *p {
                return false;
            }
        }
        if let Some(s) = &self.status {
            // `unknown` / 缺键都是「无法核验」；不能因为缺键就一条都筛不出来。
            let actual = match m.status.as_deref() {
                Some("open") => "open",
                Some("done") => "done",
                Some("dropped") => "dropped",
                _ => "unknown",
            };
            if actual != s {
                return false;
            }
        }
        let hay = format!("{} {} {}", m.name, m.description_text(), m.project_label());
        matches_query(&hay, &self.search)
    }
}

#[derive(Debug, Clone, Default)]
pub struct ProjectUi {
    pub journal_branch: Option<String>,
    pub journal_limit: u32,
    pub expanded_docs: bool,
    pub expanded_findings: BTreeSet<String>,
}

impl ProjectUi {
    pub fn limit(&self) -> u32 {
        if self.journal_limit == 0 {
            50
        } else {
            self.journal_limit
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct ConfidenceForm {
    pub project: Option<String>,
    /// 只看高权重（weight >= 8）。
    pub min_weight: i64,
    pub expanded: BTreeSet<String>,
}

#[derive(Debug, Clone, Default)]
pub struct PatchForm {
    pub project: Option<String>,
    /// 用户显式指定的 diff 路径。留空 = 每次分析都重新读工作区 diff
    /// （自动生成的临时文件放 `last_diff_path`，绝不写回这里 —— 否则第二次
    /// 分析会静默使用上一次的旧 diff）。
    pub diff_path: String,
    pub last_diff_path: String,
    pub algorithm_path: String,
    pub agent_path: String,
    pub agent_json: String,
    pub expanded: BTreeSet<String>,
}

#[derive(Debug, Clone)]
pub struct ScanForm {
    pub path: String,
    pub name: String,
    pub roots: Vec<String>,
    pub depth: u32,
    pub git_only: bool,
    pub last: Option<ScanPayload>,
    pub busy: bool,
}

impl Default for ScanForm {
    fn default() -> Self {
        ScanForm {
            path: String::new(),
            name: String::new(),
            roots: Vec::new(),
            depth: 3,
            git_only: false,
            last: None,
            busy: false,
        }
    }
}

impl ScanForm {
    /// 实际要扫描的根：显式 roots；没有就把单项目路径当作一个根。
    pub fn effective_roots(&self) -> Vec<String> {
        let mut out: Vec<String> = self.roots.clone();
        let path = self.path.trim();
        if out.is_empty() && !path.is_empty() {
            out.push(path.to_string());
        }
        out
    }
}

#[derive(Debug, Clone, Default)]
pub struct SidebarUi {
    pub search: String,
    pub collapsed_views: bool,
    pub collapsed_repos: bool,
}

#[derive(Debug, Clone, Default)]
pub struct SettingsUi {
    pub secret_editing: bool,
    pub testing: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AiScope {
    Group,
    Project(String),
}

impl Default for AiScope {
    fn default() -> Self {
        AiScope::Group
    }
}

#[derive(Debug, Clone, Default)]
pub struct AgentUi {
    pub input: String,
    pub running: bool,
    pub scope: AiScope,
}

/// 页面临时状态。**只在 UI 层，不参与引擎契约。**
#[derive(Debug, Clone, Default)]
pub struct UiState {
    pub dashboard: DashboardFilters,
    pub board: BoardFilters,
    pub milestones: MilestoneFilters,
    pub project: ProjectUi,
    pub confidence: ConfidenceForm,
    pub patch: PatchForm,
    pub scan: ScanForm,
    pub sidebar: SidebarUi,
    pub settings: SettingsUi,
    pub agent: AgentUi,
}

// ══════════════════════════════════════════════════════════════════════
// 项目详情缓存
// ══════════════════════════════════════════════════════════════════════

/// 项目页的按需数据。`ProjectTab` 切换时由 core 预取；页面只读。
#[derive(Debug, Clone, Default)]
pub struct ProjectDetail {
    pub journal: Load<JournalPayload>,
    pub docs: Load<DocsPayload>,
    pub git_status: Load<GitStatusPayload>,
    pub artifacts: BTreeMap<Artifact, Load<RenderCheck>>,
    pub journal_branch: Option<String>,
    pub loaded_at: Option<Instant>,
}

// ══════════════════════════════════════════════════════════════════════
// 动作
// ══════════════════════════════════════════════════════════════════════

/// 顶部应用动作（不含页面私有动作；页面动作走 `Action::Xxx`）。
/// 必须 `Clone + Send`：菜单项/Toast/确认框都会存它。
#[derive(Debug, Clone)]
pub enum AppAction {
    // 路由与加载
    Navigate(Route),
    SetProjectTab(ProjectTab),
    Refresh(RefreshScope),
    LoadDashboard,
    LoadMilestones,
    LoadRegistry,
    LoadProject(String),
    // 设置
    SetLanguage(Lang),
    SetEngineBin(String),
    RedetectEngine,
    // 反馈 / 浮层
    DismissFeedback,
    DismissToast(u64),
    RouteNote(String),
    CopyText { text: String, label: String },
    Open(OpenTarget),
    AskConfirm(Confirm),
    ConfirmYes,
    ConfirmNo,
    OpenMenu { x: f32, y: f32, items: Vec<MenuItem> },
    CloseMenu,
    TogglePalette,
    SetPaletteQuery(String),
    PaletteMove(i32),
    PaletteSelect,
    ClosePalette,
    CloseModal,
    // 写动作（同步）
    Update { project: Option<String>, deep: bool },
    AskUpdate { project: Option<String>, deep: bool },
    Git { project: String, op: GitOp },
    AskRemoveProject(String),
    RemoveProject(String),
    MilestoneAction { project: String, name: String, op: MilestoneOp },
    AskMilestoneRemove { project: String, name: String },
    AskMilestoneDrop { project: String, name: String },
    MilestoneRemove { project: String, name: String },
    // 提交弹层
    OpenCommitSheet(String),
    CloseCommitSheet,
    SetCommitMessage(String),
    ToggleCommitPath(String),
    SelectAllPaths,
    ClearSelection,
    SubmitCommit,
    // 新建里程碑
    OpenMilestoneSheet(String),
    CloseMilestoneSheet,
    SetMilestoneField { field: MilestoneField, value: String },
    SubmitMilestone,
    // 扫描 / 置信度 / 补丁
    RunScan,
    AddProject,
    /// 项目日志切分支：重新 `journal --branch`（不是客户端筛已加载窗口）。
    SetJournalBranch { project: String, branch: Option<String> },
    LoadMoreJournal(String),
    RunConfidence,
    /// 取 `graph confidence --llm` 的纯文本复核任务书并复制到剪贴板。
    RunConfidenceLlmPrompt,
    RunPatch,
    RunPatchSkill,
    RunPatchMerge,
    CheckArtifact { project: String, artifact: Artifact },
    OpenArtifact { project: String, artifact: Artifact },
    ShowDoctor,
    // 筛选 / 搜索
    SetSidebarSearch(String),
    SetBoardQuery(String),
    SetMilestoneSearch(String),
    SetMilestoneProject(Option<String>),
    SetMilestoneStatus(Option<String>),
    SetDashboardRange(RangeFilter),
    SetDashboardCommitType(Option<String>),
    ToggleLangExpanded,
    SetScanPath(String),
    SetScanName(String),
    AddScanRoot,
    RemoveScanRoot(String),
    SetScanDepth(u32),
    SetScanGitOnly(bool),
    SetConfidenceProject(Option<String>),
    SetConfidenceMinWeight(i64),
    SetPatchProject(Option<String>),
    SetPatchDiffPath(String),
    SetPatchAlgorithmPath(String),
    SetPatchAgentPath(String),
    SetAgentJson(String),
    // 定时器（无后台线程时由根视图每帧调用；只在有 toast 过期时才改状态）
    Tick,
}

/// 刷新范围。`Project(name)` 只重取该项目的 status + 详情。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RefreshScope {
    All,
    Light,
    Project(String),
}

/// 页面私有动作的汇总。四个 v0 页面（dashboard/project/milestones/sidebar）
/// 由后续开发者重写后再加入各自的 `XxxAction`；本阶段它们直接调用 AppState
/// 的同步方法（v0 风格），因此这里先只有四个新页面的动作。
#[derive(Debug, Clone)]
pub enum Action {
    App(AppAction),
    Board(views::board::BoardAction),
    Confidence(views::confidence::ConfidenceAction),
    Patch(views::patch::PatchAction),
    Scan(views::scan::ScanAction),
}

// ══════════════════════════════════════════════════════════════════════
// AppState
// ══════════════════════════════════════════════════════════════════════

pub struct AppState {
    pub engine: Engine,
    pub lang: Lang,
    pub route: Route,
    pub project_tab: ProjectTab,

    // ── 读模型 ──
    /// v0 兼容：`None` = 还没读到；失败原因在 `error`。
    pub status: Option<StatusEnvelope>,
    pub dashboard: Load<DashboardData>,
    /// v0 兼容：降级时仍填充（`storeHealth` 另披露）。
    pub milestones: Option<MilestoneList>,
    /// 里程碑读取失败（与 status 的 `error` 分开；旧页面用 error 的语义不该被覆盖）。
    pub milestones_error: Option<EngineError>,
    pub registry: Load<Vec<RegistryEntry>>,
    pub project_cache: HashMap<String, ProjectDetail>,

    // 一次性结果（页面/模态读取）
    pub confidence: Load<ConfidenceReport>,
    pub patch: Load<PatchReport>,
    pub patch_merged: Load<MergedReport>,

    // ── 全局反馈 ──
    pub error: Option<String>,
    pub startup_error: Option<EngineError>,
    pub feedback: Option<Feedback>,
    pub route_note: Option<String>,
    pub engine_warnings: Vec<String>,
    pub last_refresh_note: String,
    pub last_refresh: Option<Instant>,
    pub last_refresh_failed: bool,
    pub refresh_queued: bool,
    pub loading: bool,

    // ── 浮层 ──
    pub toast: Vec<Toast>,
    pub confirm: Option<Confirm>,
    pub menu: Option<MenuState>,
    pub palette: Option<PaletteState>,
    pub commit_sheet: Option<CommitSheet>,
    pub milestone_sheet: Option<MilestoneAddForm>,
    pub modal: Option<ModalState>,
    pub pending_copy: Option<PendingCopy>,
    pub pending_scroll: Option<String>,

    // ── 后台 Job（置信度 / 补丁）──
    /// 根视图消费一次；`None` = 没有排队中的 Job。
    pub pending_job: Option<JobRequest>,
    /// 正在跑的置信度分析取消旗标（`Some` = 有 Job，可点「停止」）。
    pub confidence_cancel: Option<Arc<AtomicBool>>,
    /// 正在跑的补丁分析取消旗标。
    pub patch_cancel: Option<Arc<AtomicBool>>,

    // ── v0 兼容字段 ──
    /// 项目页提交信息草稿（v0 直接读写这个字段）。
    pub commit_draft: String,
    /// v0 图谱产物缓存：((project, "index"|"arch"), path)。
    /// **新代码用 `artifact_states`**；这里是为了不让旧 project.rs 改签名。
    pub artifacts: Vec<((String, String), Option<String>)>,
    /// 新代码的产物探测缓存（含失败态）。
    pub artifact_states: HashMap<(String, Artifact), Load<RenderCheck>>,

    pub ui: UiState,
    next_toast_id: u64,
}

impl AppState {
    pub fn bootstrap() -> AppState {
        Self::bootstrap_with(Engine::new())
    }

    /// 开窗前同步预取：status → dashboard → milestones → registry（首屏即数据）。
    /// 引擎不可用时不 panic：`startup_error` 让根视图渲染安装引导。
    pub fn bootstrap_with(engine: Engine) -> AppState {
        let mut st = AppState {
            engine,
            lang: Lang::default(),
            route: Route::Dashboard,
            project_tab: ProjectTab::Overview,
            status: None,
            dashboard: Load::Idle,
            milestones: None,
            milestones_error: None,
            registry: Load::Idle,
            project_cache: HashMap::new(),
            confidence: Load::Idle,
            patch: Load::Idle,
            patch_merged: Load::Idle,
            error: None,
            startup_error: None,
            feedback: None,
            route_note: None,
            engine_warnings: Vec::new(),
            last_refresh_note: String::new(),
            last_refresh: None,
            last_refresh_failed: false,
            refresh_queued: false,
            loading: false,
            toast: Vec::new(),
            confirm: None,
            menu: None,
            palette: None,
            commit_sheet: None,
            milestone_sheet: None,
            modal: None,
            pending_copy: None,
            pending_scroll: None,
            pending_job: None,
            confidence_cancel: None,
            patch_cancel: None,
            commit_draft: String::new(),
            artifacts: Vec::new(),
            artifact_states: HashMap::new(),
            ui: UiState::default(),
            next_toast_id: 1,
        };
        st.update_engine_note();
        st.refresh_scope(RefreshScope::All);
        st
    }

    // ── 基本查询 ──────────────────────────────────────────────────

    pub fn projects(&self) -> &[Project] {
        self.status
            .as_ref()
            .map(|s| s.projects.as_slice())
            .unwrap_or(&[])
    }

    pub fn project(&self, name: &str) -> Option<&Project> {
        self.projects().iter().find(|p| p.name == name)
    }

    pub fn project_detail(&self, name: &str) -> Option<&ProjectDetail> {
        self.project_cache.get(name)
    }

    pub fn engine_short(&self) -> String {
        self.engine.short_name()
    }

    pub fn t(&self) -> Lang {
        self.lang
    }

    pub fn current_project(&self) -> Option<&str> {
        self.route.project_name()
    }

    /// 当前生效的项目选择：页面表单显式选择优先，其次当前路由。
    pub fn chosen_project(&self, explicit: &Option<String>) -> Option<String> {
        explicit
            .clone()
            .or_else(|| self.route.project_name().map(str::to_string))
    }

    // ── 刷新 ──────────────────────────────────────────────────────

    /// v0 签名：全量刷新（旧页面直接调用）。
    pub fn refresh(&mut self) {
        self.refresh_scope(RefreshScope::All);
    }

    pub fn refresh_scope(&mut self, scope: RefreshScope) {
        if self.loading {
            // 合并，不丢：跑完再跑一次
            self.refresh_queued = true;
            return;
        }
        self.loading = true;
        match scope {
            RefreshScope::Light => {
                self.load_status(false);
            }
            RefreshScope::Project(name) => {
                if self.load_status(false) {
                    self.load_project_detail(&name, true);
                }
            }
            RefreshScope::All => {
                // status 失败：不再跑 dashboard / milestones（旧客户端同纪律）
                if self.load_status(false) {
                    self.load_dashboard_silent();
                    self.load_milestones_silent();
                    self.load_registry_silent();
                    if self.feedback.is_none() {
                        if let Some(e) = &self.milestones_error {
                            self.feedback = Some(Feedback::failure(format!(
                                "里程碑读取失败：{}",
                                e.user_message()
                            )));
                        }
                    }
                }
            }
        }
        self.loading = false;
        self.last_refresh = Some(Instant::now());
        self.update_engine_note();
        self.drain_warnings();
        if self.refresh_queued {
            self.refresh_queued = false;
            self.refresh_scope(RefreshScope::All);
        }
    }

    fn update_engine_note(&mut self) {
        self.last_refresh_note = format!("引擎：{}", self.engine_short());
    }

    /// 返回是否成功。`silent=true` 时不写 feedback（bootstrap/写后刷新）。
    fn load_status(&mut self, silent: bool) -> bool {
        match self.engine.status(None) {
            Ok(s) => {
                self.status = Some(s);
                self.error = None;
                self.startup_error = None;
                self.last_refresh_failed = false;
                true
            }
            Err(e) => {
                let msg = e.user_message();
                if self.startup_error.is_none()
                    && matches!(&e, EngineError::NotFound { .. } | EngineError::Spawn { .. })
                {
                    self.startup_error = Some(e.clone());
                }
                self.error = Some(msg.clone());
                self.last_refresh_failed = true;
                if !silent {
                    self.feedback = Some(Feedback::failure(msg));
                }
                false
            }
        }
    }

    fn load_dashboard_silent(&mut self) {
        self.dashboard = Load::Loading;
        match self.engine.dashboard() {
            Ok(d) => self.dashboard = Load::Ready(d),
            Err(e) => self.dashboard = Load::Failed(e),
        }
    }

    fn load_milestones_silent(&mut self) {
        match self.engine.milestone_list(None) {
            // 降级时 rc=1 但载荷合法：仍填充；storeHealth 单独披露。
            Ok(m) => {
                self.milestones = Some(m);
                self.milestones_error = None;
            }
            Err(e) => {
                // 不在这里写 feedback：写操作后的刷新不许把成功改写成失败。
                self.milestones_error = Some(e);
            }
        }
    }

    fn load_registry_silent(&mut self) {
        self.registry = Load::Loading;
        match self.engine.list_registry() {
            Ok(r) => self.registry = Load::Ready(r),
            Err(e) => self.registry = Load::Failed(e),
        }
    }

    pub fn load_dashboard(&mut self) {
        self.load_dashboard_silent();
    }

    pub fn load_milestones(&mut self) {
        self.load_milestones_silent();
    }

    pub fn load_registry(&mut self) {
        self.load_registry_silent();
    }

    pub fn ensure_status(&mut self) {
        if self.status.is_none() && !self.loading {
            self.refresh_scope(RefreshScope::Light);
        }
    }

    /// 写操作之后的刷新：**失败只发 toast，绝不覆盖成功 feedback**
    /// （已产生副作用的动作不许被报成失败）。
    fn refresh_after_write(&mut self, project: Option<&str>) {
        let before = self.feedback.clone();
        if self.load_status(true) {
            self.load_dashboard_silent();
            self.load_milestones_silent();
            self.load_registry_silent();
            if let Some(name) = project {
                self.load_project_detail(name, true);
            }
        } else if let Some(err) = self.error.clone() {
            self.toast(Tone::Warn, "刷新失败", format!("操作已生效，但刷新失败：{err}"));
        }
        self.feedback = before;
        self.last_refresh = Some(Instant::now());
        self.update_engine_note();
        self.drain_warnings();
    }

    fn drain_warnings(&mut self) {
        for line in self.engine.drain_warnings() {
            if !self.engine_warnings.contains(&line) {
                self.engine_warnings.push(line);
            }
        }
        if self.engine_warnings.len() > 50 {
            let cut = self.engine_warnings.len() - 50;
            self.engine_warnings.drain(0..cut);
        }
    }

    // ── 导航 ──────────────────────────────────────────────────────

    /// v0 签名：切路由 + 清草稿/反馈 + 预探产物。
    pub fn select(&mut self, route: Route) {
        self.navigate(route);
    }

    pub fn navigate(&mut self, route: Route) {
        let entering_new_project = match (&self.route, &route) {
            (Route::Project(a), Route::Project(b)) => a != b,
            (_, Route::Project(_)) => true,
            _ => false,
        };
        self.route = route;
        self.feedback = None;
        self.route_note = None;
        self.menu = None;
        self.palette = None;
        if entering_new_project {
            self.project_tab = ProjectTab::Overview;
            self.commit_draft.clear();
        }
        self.pending_scroll = Some(self.route.scroll_id(&self.project_tab));
        let entering = self.route.clone();
        crate::views::on_enter_route(self, &entering);
    }

    pub fn set_project_tab(&mut self, tab: ProjectTab) {
        self.project_tab = tab;
        if let Route::Project(name) = &self.route {
            let name = name.clone();
            self.pending_scroll = Some(format!("scroll-project-{name}-{}", tab.key()));
            self.load_project_detail(&name, false);
        }
    }

    // ── 反馈 / Toast / 复制 ───────────────────────────────────────

    pub fn toast(&mut self, tone: Tone, title: impl Into<String>, body: impl Into<String>) {
        self.toast_action(tone, title, body, None);
    }

    pub fn toast_action(
        &mut self,
        tone: Tone,
        title: impl Into<String>,
        body: impl Into<String>,
        action: Option<AppAction>,
    ) {
        let id = self.next_toast_id;
        self.next_toast_id += 1;
        self.toast.push(Toast {
            id,
            tone,
            title: title.into(),
            body: body.into(),
            action,
            // 10 分钟兜底；没有后台线程时由 tick() 清理
            expires: Some(Instant::now() + std::time::Duration::from_secs(600)),
        });
        if self.toast.len() > 3 {
            self.toast.remove(0);
        }
    }

    pub fn dismiss_toast(&mut self, id: u64) {
        self.toast.retain(|t| t.id != id);
    }

    pub fn tick(&mut self) {
        let now = Instant::now();
        self.toast
            .retain(|t| t.expires.map(|e| e > now).unwrap_or(true));
    }

    // ── 键盘 ──────────────────────────────────────────────────────

    /// 应用级快捷键（在根视图的 `on_key_down` 里调用）。
    ///
    /// 返回是否消费了这次按键。只处理**明确**的组合，其余一律放行：
    /// 普通字符必须照常进入输入框（BUI 的 key 事件同时送给根视图与原生控件，
    /// 这里吞掉一个字母就会让用户打不了字）。
    ///
    /// 注意：`modifiers.control` 在 macOS 上是 ⌘（kit 把 Command 映射成
    /// BK_CTRL），在 Windows/Linux 上是 Ctrl —— 与平台习惯一致。
    ///
    /// 未接 ⌘F：BUI 0.5 没有公开「把键盘焦点交给原生输入框」的 API
    /// （`Window::focus_id` 只改 Rust 侧的事件路由，原生 text widget 仍收不到
    /// 输入）。画一个焦点框却打不了字比不接更糟。
    pub fn handle_shortcut(&mut self, k: &Keystroke) -> bool {
        let cmd = k.modifiers.control;
        let key = k.key.as_str();
        if cmd && matches!(key, "k" | "K") {
            // 走 reducer（`AppAction::TogglePalette`），而不是在这里另写一份开关逻辑。
            self.apply(AppAction::TogglePalette);
            return true;
        }
        if cmd && matches!(key, "r" | "R") {
            self.apply(AppAction::Refresh(RefreshScope::All));
            return true;
        }
        if key == "Escape" {
            return self.close_top_overlay();
        }
        if self.palette.is_some() {
            match key {
                "Down" => {
                    self.apply(AppAction::PaletteMove(1));
                    return true;
                }
                "Up" => {
                    self.apply(AppAction::PaletteMove(-1));
                    return true;
                }
                "Return" | "KP_Enter" => {
                    self.apply(AppAction::PaletteSelect);
                    return true;
                }
                _ => {}
            }
        }
        false
    }

    /// 关闭最上层浮层（Esc）。一次只关一个：确认框盖在弹层上时，
    /// 先关确认框而不是把底下的弹层一起收掉。
    fn close_top_overlay(&mut self) -> bool {
        if self.palette.take().is_some() {
            return true;
        }
        if self.menu.take().is_some() {
            return true;
        }
        if self.confirm.take().is_some() {
            return true;
        }
        if self.commit_sheet.take().is_some() {
            return true;
        }
        if self.milestone_sheet.take().is_some() {
            return true;
        }
        if self.modal.take().is_some() {
            return true;
        }
        false
    }

    /// 只写 pending：`reduce` 里没有 `Window`，根视图下一帧落剪贴板。
    pub fn copy(&mut self, text: &str, label: &str) {
        self.pending_copy = Some(PendingCopy {
            text: text.to_string(),
            label: label.to_string(),
        });
    }

    pub fn fail(&mut self, err: EngineError) {
        // `error` 的语义是「status 刷新失败」（旧页面据此渲染读不出来）。
        // 动作失败只进 feedback，不能把一次 git 失败渲染成「项目读不出来」。
        if matches!(&err, EngineError::NotFound { .. } | EngineError::Spawn { .. })
            && self.startup_error.is_none()
        {
            self.startup_error = Some(err.clone());
        }
        self.feedback = Some(Feedback::failure(err.user_message()));
    }

    pub fn ask_confirm(&mut self, c: Confirm) {
        self.confirm = Some(c);
    }

    pub fn confirm_no(&mut self) {
        self.confirm = None;
    }

    pub fn confirm_yes(&mut self) {
        let Some(c) = self.confirm.take() else {
            return;
        };
        match c.action {
            PendingAction::MilestoneRemove { project, name } => {
                self.milestone_remove(&project, &name);
            }
            PendingAction::MilestoneDrop { project, name } => {
                self.milestone_action_typed(&project, &name, MilestoneOp::Drop);
            }
            PendingAction::UpdateAll { deep } => self.update(None, deep),
            PendingAction::UpdateProject { project, deep } => {
                self.update(Some(&project), deep)
            }
            PendingAction::RemoveProject { name } => self.remove_project(&name),
            PendingAction::GitOp { project, op } => {
                self.git_action_full(&project, op, None, &[]);
            }
        }
    }

    // ── 语言 / 引擎 ──────────────────────────────────────────────

    /// `lang` 是**引擎事实语言**的选择，不是界面语言。
    ///
    /// 客户端目前只有中文文案（全仓没有按 `lang` 分支的字符串）。所以：
    ///   · 成功回执只能说「引擎事实语言已设置」，**不许**说「界面语言已切换」；
    ///   · 引擎不支持的取值（日本語）不写配置，也不改选择 —— 写 en 是谎报。
    pub fn set_language(&mut self, lang: Lang) {
        let lang = lang.engine_option();
        let Some(code) = lang.engine_code() else {
            self.feedback = Some(Feedback::failure(format!(
                "「{}」不是引擎支持的事实语言（只支持 zh / en）；未写入任何设置。界面语言目前只有中文。",
                lang.label()
            )));
            return;
        };
        self.lang = lang;
        match self.engine.config_set_language(code) {
            Ok(r) if r.ok => {
                self.feedback = Some(Feedback::success(format!(
                    "引擎事实语言已设为 {}；界面语言目前只有中文（多语言界面尚未实现）",
                    code
                )));
            }
            Ok(_) => {
                self.feedback = Some(Feedback::failure(
                    "引擎拒绝更新事实语言（引擎只支持 zh / en）；界面仍是中文",
                ));
            }
            Err(e) => {
                self.feedback = Some(Feedback::failure(format!(
                    "引擎事实语言未更新：{}；界面仍是中文",
                    e.user_message()
                )));
            }
        }
    }

    pub fn set_engine_bin(&mut self, bin: &str) {
        if bin.trim().is_empty() {
            self.feedback = Some(Feedback::failure("引擎路径不能为空"));
            return;
        }
        self.engine = Engine::with_bin(bin.trim());
        self.startup_error = None;
        self.artifact_states.clear();
        self.artifacts.clear();
        self.project_cache.clear();
        self.refresh_scope(RefreshScope::All);
        if self.status.is_some() {
            self.feedback = Some(Feedback::success(format!(
                "引擎已切换为 {}",
                self.engine_short()
            )));
        }
        // status 失败时保留 refresh 写下的失败反馈，不覆盖成「切换成功」
    }

    pub fn redetect_engine(&mut self) {
        self.engine = Engine::new();
        self.startup_error = None;
        self.artifact_states.clear();
        self.artifacts.clear();
        self.project_cache.clear();
        self.refresh_scope(RefreshScope::All);
        if self.status.is_some() {
            self.feedback = Some(Feedback::success(format!(
                "已重新检测引擎：{}",
                self.engine_short()
            )));
        }
    }

    // ── git 动作（v0 兼容 + 完整版）──────────────────────────────

    /// v0 签名：`op` 是 "pull"/"push"/"fetch"/"stash"/"unstash"/"commit"。
    /// commit 用 `commit_draft` 作为信息（全部改动）。
    pub fn git_action(&mut self, project: &str, op: &str) {
        let op = match op {
            "pull" => GitOp::Pull,
            "push" => GitOp::Push,
            "fetch" => GitOp::Fetch,
            "stash" => GitOp::Stash,
            "unstash" => GitOp::Unstash,
            "commit" => GitOp::Commit,
            other => {
                self.feedback = Some(Feedback::failure(format!(
                    "未知的 git 操作：{other}（白名单：pull/push/fetch/stash/unstash/commit）"
                )));
                return;
            }
        };
        if op == GitOp::Commit {
            let msg = self.commit_draft.trim().to_string();
            if msg.is_empty() {
                self.feedback = Some(Feedback::failure(
                    "需要提交信息（--message）；客户端不会替你编一条",
                ));
                return;
            }
            self.git_action_full(project, op, Some(&msg), &[]);
        } else {
            self.git_action_full(project, op, None, &[]);
        }
    }

    /// 返回是否成功。`paths` 为空 = 提交全部（仅 commit 有意义）。
    pub fn git_action_full(
        &mut self,
        project: &str,
        op: GitOp,
        message: Option<&str>,
        paths: &[String],
    ) -> bool {
        // `--paths` 是逗号分隔：含逗号的路径会被引擎切错 —— 拦在调用之前。
        if let Some(bad) = paths.iter().find(|p| p.contains(',')) {
            self.feedback = Some(Feedback::failure(format!(
                "路径含逗号，无法用 --paths 单独提交：{bad}。请改用「提交全部」。"
            )));
            return false;
        }
        match self.engine.git(project, op, message, paths) {
            Ok(resp) if resp.ok => {
                let line = last_nonempty_line(&resp.output);
                self.feedback = Some(Feedback::success(format!(
                    "{} 完成 · {}",
                    op.label(),
                    line
                )));
                if op == GitOp::Commit {
                    self.commit_draft.clear();
                }
                self.refresh_after_write(Some(project));
                true
            }
            Ok(resp) => {
                let reason = if resp.output.trim().is_empty() {
                    "引擎没有给出原因".to_string()
                } else {
                    resp.output.trim().to_string()
                };
                self.feedback = Some(Feedback::failure(format!(
                    "{} 失败：{}",
                    op.label(),
                    reason
                )));
                false
            }
            Err(e) => {
                self.fail(e);
                false
            }
        }
    }

    // ── 更新 ──────────────────────────────────────────────────────

    /// 直接执行（确认由调用方负责；`ask_update` 会先弹确认）。
    pub fn update(&mut self, project: Option<&str>, deep: bool) {
        let label = if deep { "深更新" } else { "浅更新" };
        match project {
            Some(name) => match self.engine.update_project(name, deep) {
                Ok(r) if r.ok => {
                    let facts = r.facts();
                    let body = if facts.is_empty() {
                        "引擎没有返回文档/日志事实".to_string()
                    } else {
                        facts.join("；")
                    };
                    self.feedback = Some(Feedback::success(format!(
                        "{}完成（{}）：{}",
                        label, name, body
                    )));
                    self.toast(Tone::Ok, format!("{label}完成"), name.to_string());
                    self.refresh_after_write(Some(name));
                }
                Ok(_) => {
                    self.feedback = Some(Feedback::failure(format!(
                        "{}返回 ok=false（{}）；引擎没有给出原因",
                        label, name
                    )));
                }
                Err(e) => self.fail(e),
            },
            None => match self.engine.update_all(deep) {
                // 单项目时引擎返回单个回执（不是 results 信封）——不能报「0 个成功」。
                Ok(UpdateOutcome::Single(r)) if r.ok => {
                    let facts = r.facts();
                    let body = if facts.is_empty() {
                        "引擎没有返回文档/日志事实".to_string()
                    } else {
                        facts.join("；")
                    };
                    let who = if r.project.is_empty() {
                        "单个项目".to_string()
                    } else {
                        r.project.clone()
                    };
                    self.feedback = Some(Feedback::success(format!(
                        "{}完成（{}）：{}",
                        label, who, body
                    )));
                    let name = if r.project.is_empty() {
                        None
                    } else {
                        Some(r.project.as_str())
                    };
                    self.refresh_after_write(name);
                }
                Ok(UpdateOutcome::Single(r)) => {
                    self.feedback = Some(Feedback::failure(format!(
                        "{}返回 ok=false（{}）；引擎没有给出原因",
                        label,
                        if r.project.is_empty() {
                            "单个项目"
                        } else {
                            r.project.as_str()
                        }
                    )));
                }
                Ok(UpdateOutcome::Multi(m)) => {
                    let failed_names = multi_failed_names(&m);
                    if m.failed > 0 {
                        self.feedback = Some(Feedback::failure(format!(
                            "{}完成：成功 {} · 失败 {}{}",
                            label,
                            m.succeeded,
                            m.failed,
                            if failed_names.is_empty() {
                                String::new()
                            } else {
                                format!("（{}）", failed_names.join("、"))
                            }
                        )));
                    } else {
                        self.feedback = Some(Feedback::success(format!(
                            "{}完成：{} 个项目成功",
                            label, m.succeeded
                        )));
                    }
                    self.refresh_after_write(None);
                }
                Err(e) => self.fail(e),
            },
        }
    }

    pub fn ask_update(&mut self, project: Option<String>, deep: bool) {
        let what = if deep { "深更新" } else { "浅更新" };
        let body = match &project {
            Some(p) => format!(
                "将对「{p}」执行{what}：改写 README/AGENTS 托管区并写进度库。旧文档有备份，但请在确认前了解它会写入你的仓库。"
            ),
            None => format!(
                "将对**全部已注册项目**执行{what}：逐个改写托管文档并写进度库。这是批量写操作。"
            ),
        };
        self.ask_confirm(Confirm {
            title: format!("{what}？"),
            body,
            confirm_label: what.to_string(),
            danger: false,
            action: match project {
                Some(p) => PendingAction::UpdateProject { project: p, deep },
                None => PendingAction::UpdateAll { deep },
            },
        });
    }

    // ── 里程碑 ────────────────────────────────────────────────────

    /// v0 签名：action = "done"/"reopen"/"drop"/"remove"。
    pub fn milestone_action(&mut self, project: &str, name: &str, action: &str) {
        match action {
            "done" => self.milestone_action_typed(project, name, MilestoneOp::Done),
            "reopen" => self.milestone_action_typed(project, name, MilestoneOp::Reopen),
            "drop" => self.milestone_action_typed(project, name, MilestoneOp::Drop),
            "remove" => self.milestone_remove(project, name),
            other => {
                self.feedback = Some(Feedback::failure(format!(
                    "未知的里程碑动作：{other}"
                )));
            }
        }
    }

    pub fn milestone_action_typed(&mut self, project: &str, name: &str, op: MilestoneOp) {
        match self.engine.milestone_action(project, name, op) {
            Ok(r) => {
                // 显示**实际生效的状态**，不是 requested
                let applied = r.applied;
                let text = r.outcome_label();
                self.feedback = Some(if applied {
                    Feedback::success(text)
                } else {
                    Feedback::failure(text)
                });
                if applied {
                    self.refresh_after_write(Some(project));
                }
            }
            Err(e) => self.fail(e),
        }
    }

    pub fn milestone_remove(&mut self, project: &str, name: &str) {
        match self.engine.milestone_remove(project, name) {
            Ok(r) => {
                if r.removed {
                    self.feedback = Some(Feedback::success(format!(
                        "已删除里程碑：{} / {}",
                        project, name
                    )));
                    self.refresh_after_write(Some(project));
                } else {
                    self.feedback = Some(Feedback::failure(format!(
                        "未删除：{} / {}（引擎返回 removed=false）",
                        project, name
                    )));
                }
            }
            Err(e) => self.fail(e),
        }
    }

    pub fn ask_milestone_remove(&mut self, project: &str, name: &str) {
        self.ask_confirm(Confirm {
            title: "删除里程碑？".to_string(),
            body: format!(
                "将永久删除「{name}」（项目 {project}）。删除不可撤销，也不会删除对应的 git tag。"
            ),
            confirm_label: "删除里程碑".to_string(),
            danger: true,
            action: PendingAction::MilestoneRemove {
                project: project.to_string(),
                name: name.to_string(),
            },
        });
    }

    pub fn ask_milestone_drop(&mut self, project: &str, name: &str) {
        self.ask_confirm(Confirm {
            title: "放弃里程碑？".to_string(),
            body: format!(
                "将把「{name}」（项目 {project}）标记为已放弃。这个动作可以重新打开，不会删除 git tag。"
            ),
            confirm_label: "放弃里程碑".to_string(),
            danger: true,
            action: PendingAction::MilestoneDrop {
                project: project.to_string(),
                name: name.to_string(),
            },
        });
    }

    pub fn open_milestone_sheet(&mut self, project: &str) {
        self.milestone_sheet = Some(MilestoneAddForm {
            project: project.to_string(),
            ..Default::default()
        });
    }

    pub fn close_milestone_sheet(&mut self) {
        self.milestone_sheet = None;
    }

    pub fn set_milestone_field(&mut self, field: MilestoneField, value: String) {
        if let Some(f) = self.milestone_sheet.as_mut() {
            match field {
                MilestoneField::Project => f.project = value,
                MilestoneField::Name => f.name = value,
                MilestoneField::Tag => f.tag = value,
                MilestoneField::Date => f.date = value,
                MilestoneField::Desc => f.desc = value,
            }
            f.error = None;
        }
    }

    pub fn submit_milestone(&mut self) {
        let Some(form) = self.milestone_sheet.clone() else {
            return;
        };
        let project = form.project.trim().to_string();
        let name = form.name.trim().to_string();
        if project.is_empty() || name.is_empty() {
            if let Some(f) = self.milestone_sheet.as_mut() {
                f.error = Some("项目和名称都是必填".to_string());
            }
            return;
        }
        let date = form.date.trim();
        if !date.is_empty() && !models::valid_date(date) {
            if let Some(f) = self.milestone_sheet.as_mut() {
                f.error = Some("目标日期必须是 YYYY-MM-DD（例如 2026-12-31）".to_string());
            }
            return;
        }
        if let Some(f) = self.milestone_sheet.as_mut() {
            f.busy = true;
        }
        match self
            .engine
            .milestone_add(&project, &name, &form.tag, date, &form.desc)
        {
            Ok(r) => {
                if r.created {
                    self.feedback = Some(Feedback::success(format!(
                        "已新建里程碑：{} / {}",
                        project, name
                    )));
                } else {
                    // created=false 是「已存在」，不是失败
                    self.feedback = Some(Feedback::success(format!(
                        "里程碑已存在（created=false）：{} / {}",
                        project, name
                    )));
                }
                self.milestone_sheet = None;
                self.refresh_after_write(Some(&project));
            }
            Err(e) => {
                let msg = e.user_message();
                if let Some(f) = self.milestone_sheet.as_mut() {
                    f.busy = false;
                    f.error = Some(msg.clone());
                }
                self.feedback = Some(Feedback::failure(msg));
            }
        }
    }

    // ── 提交弹层 ──────────────────────────────────────────────────

    pub fn open_commit_sheet(&mut self, project: &str) {
        let status = match self.engine.git_status(project) {
            Ok(p) => Load::Ready(p),
            Err(e) => Load::Failed(e),
        };
        let selected = match &status {
            Load::Ready(p) if p.ok => p.entries.iter().map(|e| e.file.clone()).collect(),
            _ => BTreeSet::new(),
        };
        self.commit_sheet = Some(CommitSheet {
            project: project.to_string(),
            message: String::new(),
            status,
            selected,
            busy: false,
        });
    }

    pub fn close_commit_sheet(&mut self) {
        self.commit_sheet = None;
    }

    pub fn set_commit_message(&mut self, msg: String) {
        if let Some(s) = self.commit_sheet.as_mut() {
            s.message = msg;
        }
    }

    pub fn toggle_commit_path(&mut self, file: &str) {
        if let Some(s) = self.commit_sheet.as_mut() {
            if !s.selected.remove(file) {
                s.selected.insert(file.to_string());
            }
        }
    }

    pub fn select_all_paths(&mut self) {
        if let Some(s) = self.commit_sheet.as_mut() {
            if let Load::Ready(p) = &s.status {
                s.selected = p.entries.iter().map(|e| e.file.clone()).collect();
            }
        }
    }

    pub fn clear_selection(&mut self) {
        if let Some(s) = self.commit_sheet.as_mut() {
            s.selected.clear();
        }
    }

    pub fn submit_commit(&mut self) {
        let Some(sheet) = self.commit_sheet.clone() else {
            return;
        };
        let msg = sheet.message.trim().to_string();
        if msg.is_empty() {
            self.feedback = Some(Feedback::failure(
                "需要提交信息（--message）；客户端不会替你编一条",
            ));
            return;
        }
        let entries: Vec<String> = match &sheet.status {
            Load::Ready(p) if p.ok => p.entries.iter().map(|e| e.file.clone()).collect(),
            _ => Vec::new(),
        };
        if entries.is_empty() {
            self.feedback = Some(Feedback::failure(
                "没有可提交的文件（或 git status 读不出来）",
            ));
            return;
        }
        if sheet.selected.is_empty() {
            self.feedback = Some(Feedback::failure("没有选择要提交的文件"));
            return;
        }
        let all_selected = sheet.selected.len() == entries.len()
            && entries.iter().all(|f| sheet.selected.contains(f));
        let paths: Vec<String> = if all_selected {
            Vec::new() // 全部 = 不传 --paths
        } else {
            sheet.selected.iter().cloned().collect()
        };
        if let Some(bad) = paths.iter().find(|p| p.contains(',')) {
            self.feedback = Some(Feedback::failure(format!(
                "路径含逗号，无法用 --paths 单独提交：{bad}。请「全选」或改用「提交全部」。"
            )));
            return;
        }
        if let Some(s) = self.commit_sheet.as_mut() {
            s.busy = true;
        }
        match self
            .engine
            .git(&sheet.project, GitOp::Commit, Some(&msg), &paths)
        {
            Ok(resp) if resp.ok => {
                let line = last_nonempty_line(&resp.output);
                self.feedback = Some(Feedback::success(format!(
                    "提交完成 · {line}"
                )));
                self.commit_sheet = None;
                self.commit_draft.clear();
                self.refresh_after_write(Some(&sheet.project));
                self.toast(Tone::Ok, "提交完成", sheet.project.clone());
            }
            Ok(resp) => {
                // 失败**不关窗**：用户的选择与信息都还在
                let reason = if resp.output.trim().is_empty() {
                    "引擎没有给出原因".to_string()
                } else {
                    resp.output.trim().to_string()
                };
                self.feedback = Some(Feedback::failure(format!("提交失败：{reason}")));
                self.reload_commit_status(&sheet.project);
            }
            Err(e) => {
                self.feedback = Some(Feedback::failure(e.user_message()));
                self.reload_commit_status(&sheet.project);
            }
        }
    }

    fn reload_commit_status(&mut self, project: &str) {
        let status = match self.engine.git_status(project) {
            Ok(p) => Load::Ready(p),
            Err(e) => Load::Failed(e),
        };
        let selected = match &status {
            Load::Ready(p) if p.ok => p
                .entries
                .iter()
                .map(|e| e.file.clone())
                .filter(|f| {
                    self.commit_sheet
                        .as_ref()
                        .map(|s| s.selected.contains(f))
                        .unwrap_or(true)
                })
                .collect(),
            _ => BTreeSet::new(),
        };
        if let Some(s) = self.commit_sheet.as_mut() {
            s.status = status;
            s.selected = selected;
            s.busy = false;
        }
    }

    // ── 扫描 / 添加 / 移除 ───────────────────────────────────────

    pub fn run_scan(&mut self) {
        let roots = self.ui.scan.effective_roots();
        if roots.is_empty() {
            self.feedback = Some(Feedback::failure(
                "没有扫描根目录：输入一个路径，或点「浏览…」选择目录",
            ));
            return;
        }
        if self.ui.scan.depth < 1 || self.ui.scan.depth > 6 {
            self.feedback = Some(Feedback::failure("扫描深度必须在 1–6 之间"));
            return;
        }
        self.ui.scan.busy = true;
        let git_only = self.ui.scan.git_only;
        let depth = self.ui.scan.depth;
        match self.engine.scan(&roots, depth, git_only) {
            Ok(p) => {
                self.ui.scan.busy = false;
                self.feedback = Some(if p.complete() {
                    Feedback::success(format!(
                        "扫描完成：发现 {} · 新增 {} · 已存在 {} · 访问 {} 个目录",
                        p.found, p.added, p.existing, p.dirs_visited
                    ))
                } else {
                    Feedback::failure(format!(
                        "扫描完成但**没有覆盖全部范围**：发现 {} · 新增 {}；{}",
                        p.found,
                        p.added,
                        p.coverage_notes().join("；")
                    ))
                });
                self.ui.scan.last = Some(p);
                // scan 会自动注册发现的项目 ⇒ registry/status/dashboard 都要刷
                self.refresh_after_write(None);
            }
            Err(e) => {
                self.ui.scan.busy = false;
                self.fail(e);
            }
        }
    }

    pub fn add_project(&mut self) {
        let path = self.ui.scan.path.trim().to_string();
        if path.is_empty() {
            self.feedback = Some(Feedback::failure("路径不能为空"));
            return;
        }
        let name = self.ui.scan.name.trim().to_string();
        match self.engine.add_project(
            &path,
            if name.is_empty() {
                None
            } else {
                Some(name.as_str())
            },
        ) {
            Ok(entry) => {
                self.feedback = Some(Feedback::success(format!("已注册：{}", entry.name)));
                self.toast(Tone::Ok, "已添加项目", entry.name.clone());
                self.ui.scan.path.clear();
                self.ui.scan.name.clear();
                self.refresh_after_write(None);
            }
            Err(e) => self.fail(e),
        }
    }

    pub fn remove_project(&mut self, name: &str) {
        match self.engine.remove_project(name) {
            Ok(entry) => {
                self.project_cache.remove(name);
                // 先离开被删项目的路由（navigate 会清 feedback），再写回执
                if self.route.project_name() == Some(name) {
                    self.navigate(Route::Dashboard);
                }
                self.feedback = Some(Feedback::success(format!(
                    "已取消注册：{}（只取消注册，不删文件；进度库保留）",
                    entry.name
                )));
                self.refresh_after_write(None);
            }
            Err(e) => self.fail(e),
        }
    }

    // ── 置信度 / 补丁 ────────────────────────────────────────────

    pub fn run_confidence(&mut self) {
        let Some(project) = self.chosen_project(&self.ui.confidence.project) else {
            self.feedback = Some(Feedback::failure("先选择一个项目（置信度是单项目分析）"));
            return;
        };
        if self.confidence.is_loading() {
            return;
        }
        self.ui.confidence.project = Some(project.clone());
        self.confidence = Load::Loading;
        // 真正执行在根视图：那里拿得到 UiSender / Entity。这里只排队。
        let cancel = Arc::new(AtomicBool::new(false));
        self.confidence_cancel = Some(cancel.clone());
        self.pending_job = Some(JobRequest::Confidence { project, cancel });
    }

    /// 用户点「停止」：旗标置位，后台线程会在 ~25ms 内 kill 子进程。
    /// 不在这里直接把 `Load` 改成就绪 —— 只有真的等到 `Cancelled` 才算停。
    pub fn stop_confidence(&mut self) {
        if let Some(c) = &self.confidence_cancel {
            c.store(true, Ordering::Relaxed);
            self.toast(Tone::Info, "正在停止", "已向引擎进程发送终止请求…");
        }
    }

    /// `--llm` 的复核任务书是纯文本；取回后只复制，不当 JSON 解析。
    pub fn run_confidence_llm_prompt(&mut self) {
        let Some(project) = self.chosen_project(&self.ui.confidence.project) else {
            self.feedback = Some(Feedback::failure("先选择一个项目"));
            return;
        };
        self.ui.confidence.project = Some(project.clone());
        match self.engine.confidence_llm_prompt(&project) {
            Ok(text) => self.copy(&text, "置信度复核提示词"),
            Err(e) => self.fail(e),
        }
    }

    pub fn run_patch(&mut self) {
        let Some(project) = self.chosen_project(&self.ui.patch.project) else {
            self.feedback = Some(Feedback::failure("先选择一个项目（补丁体检按项目分析）"));
            return;
        };
        if self.patch.is_loading() {
            return;
        }
        self.ui.patch.project = Some(project.clone());
        let explicit = self.ui.patch.diff_path.trim().to_string();
        let explicit_diff = if explicit.is_empty() {
            None
        } else {
            // 显式路径不存在不必等后台线程；这里先报，语义与旧同步路径一致。
            if !PathBuf::from(&explicit).is_file() {
                self.feedback = Some(Feedback::failure(format!(
                    "diff 文件不存在：{explicit}"
                )));
                return;
            }
            Some(explicit)
        };
        let repo_path = self
            .project(&project)
            .map(|p| p.path.clone())
            .filter(|p| !p.trim().is_empty());
        if explicit_diff.is_none() && repo_path.is_none() {
            self.feedback = Some(Feedback::failure(format!(
                "注册表里没有项目「{project}」的可用路径，且没有显式 diff 文件"
            )));
            return;
        }

        self.patch = Load::Loading;
        // 读 diff / 跑 patchconf / 写 Layer-1 报告全在后台线程：
        // `git diff HEAD` 超时是 180s，不能让窗口跟着冻住。
        let cancel = Arc::new(AtomicBool::new(false));
        self.patch_cancel = Some(cancel.clone());
        self.pending_job = Some(JobRequest::Patch {
            project,
            explicit_diff,
            repo_path,
            cancel,
        });
    }

    pub fn stop_patch(&mut self) {
        if let Some(c) = &self.patch_cancel {
            c.store(true, Ordering::Relaxed);
            self.toast(Tone::Info, "正在停止", "已向引擎进程发送终止请求…");
        }
    }

    /// 取补丁输入：显式路径优先；否则读工作区 diff 并写临时文件。
    fn resolve_patch_path(&self, project: &str) -> Result<PathBuf, String> {
        let explicit = self.ui.patch.diff_path.trim();
        if !explicit.is_empty() {
            let p = PathBuf::from(explicit);
            if !p.is_file() {
                return Err(format!("diff 文件不存在：{explicit}"));
            }
            return Ok(p);
        }
        let Some(entry) = self.project(project) else {
            return Err(format!("注册表里没有项目「{project}」"));
        };
        let repo = PathBuf::from(&entry.path);
        let r = self
            .engine
            .git_diff_head(&repo)
            .map_err(|e| e.user_message())?;
        if r.timed_out {
            return Err("读取工作区 diff 超时（180s），已终止".to_string());
        }
        if !r.ok {
            let reason = r.stderr.trim();
            return Err(if reason.is_empty() {
                "读取工作区 diff 失败（git 没有输出原因）".to_string()
            } else {
                format!("读取工作区 diff 失败：{reason}")
            });
        }
        if r.stdout.trim().is_empty() {
            return Err("工作区没有未提交改动（git diff HEAD 为空）。先改点东西，或指定已有 diff 文件。".to_string());
        }
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0);
        let path = std::env::temp_dir().join(format!(
            "deepdolphin-patch-{}-{stamp}.diff",
            std::process::id()
        ));
        std::fs::write(&path, &r.stdout)
            .map_err(|e| format!("写临时 diff 失败（{}）：{e}", path.display()))?;
        Ok(path)
    }

    pub fn run_patch_skill(&mut self) {
        let Some(project) = self.chosen_project(&self.ui.patch.project) else {
            self.feedback = Some(Feedback::failure("先选择一个项目"));
            return;
        };
        let patch = match self.resolve_patch_path(&project) {
            Ok(p) => p,
            Err(msg) => {
                self.feedback = Some(Feedback::failure(msg));
                return;
            }
        };
        self.ui.patch.last_diff_path = patch.to_string_lossy().into_owned();
        match self.engine.patchconf_skill(&project, &patch) {
            Ok(text) => {
                self.modal = Some(ModalState::Text {
                    title: "补丁体检 · Agent 任务书".to_string(),
                    body: text,
                });
            }
            Err(e) => self.fail(e),
        }
    }

    pub fn run_patch_merge(&mut self) {
        let algorithm = self.ui.patch.algorithm_path.trim().to_string();
        if algorithm.is_empty() {
            self.feedback = Some(Feedback::failure(
                "先指定算法结果 JSON（--merge 需要两份报告）",
            ));
            return;
        }
        let algorithm_path = PathBuf::from(&algorithm);
        if !algorithm_path.is_file() {
            return self.set_feedback_failure(format!("算法结果文件不存在：{algorithm}"));
        }
        // agent 报告：文件路径优先；否则把粘贴的 JSON 落到临时文件
        let agent_path = if !self.ui.patch.agent_path.trim().is_empty() {
            let p = PathBuf::from(self.ui.patch.agent_path.trim());
            if !p.is_file() {
                return self.set_feedback_failure(format!(
                    "agent 结果文件不存在：{}",
                    self.ui.patch.agent_path
                ));
            }
            p
        } else if !self.ui.patch.agent_json.trim().is_empty() {
            if serde_json::from_str::<serde_json::Value>(self.ui.patch.agent_json.trim()).is_err() {
                return self.set_feedback_failure("粘贴的 agent JSON 不是合法 JSON");
            }
            let stamp = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis())
                .unwrap_or(0);
            let p = std::env::temp_dir().join(format!(
                "deepdolphin-agent-{}-{stamp}.json",
                std::process::id()
            ));
            if let Err(e) = std::fs::write(&p, self.ui.patch.agent_json.trim()) {
                return self.set_feedback_failure(format!("写临时 agent JSON 失败：{e}"));
            }
            p
        } else {
            return self.set_feedback_failure("先指定 agent 结果文件，或粘贴 agent JSON");
        };
        self.patch_merged = Load::Loading;
        match self.engine.patchconf_merge(&algorithm_path, &agent_path) {
            Ok(r) => self.patch_merged = Load::Ready(r),
            Err(e) => {
                let msg = e.user_message();
                self.patch_merged = Load::Failed(e);
                self.feedback = Some(Feedback::failure(msg));
            }
        }
    }

    fn set_feedback_failure(&mut self, msg: impl Into<String>) {
        self.feedback = Some(Feedback::failure(msg));
    }

    pub fn validate_agent_json(&mut self) -> bool {
        let text = self.ui.patch.agent_json.trim();
        if text.is_empty() {
            return true;
        }
        match serde_json::from_str::<serde_json::Value>(text) {
            Ok(_) => true,
            Err(e) => {
                self.set_feedback_failure(format!("agent JSON 不合法：{e}"));
                false
            }
        }
    }

    // ── 图谱产物 ──────────────────────────────────────────────────

    /// 新接口：完整四态（失败与「未生成」分开）；命中缓存时不打引擎。
    pub fn probe_artifact_state(&mut self, project: &str, artifact: Artifact) -> Load<RenderCheck> {
        let key = (project.to_string(), artifact);
        if let Some(v) = self.artifact_states.get(&key) {
            return v.clone();
        }
        self.refresh_artifact(project, artifact)
    }

    /// **强制重新探测**（「检查」按钮、进入项目页）。产物可能是在上次探测之后
    /// 才生成的，所以「检查」不能读缓存 —— 否则按钮永远显示第一次的结论。
    pub fn refresh_artifact(&mut self, project: &str, artifact: Artifact) -> Load<RenderCheck> {
        match self.engine.render_check(artifact, project) {
            Ok(rc) => {
                let load = Load::Ready(rc);
                self.store_artifact(project, artifact, load.clone());
                load
            }
            // 失败不写缓存：「未生成」与「查失败」是两种状态，下次要重新查。
            Err(e) => Load::Failed(e),
        }
    }

    fn store_artifact(&mut self, project: &str, artifact: Artifact, load: Load<RenderCheck>) {
        let path = match &load {
            Load::Ready(rc) if rc.exists => Some(rc.path.clone()),
            _ => None,
        };
        self.artifact_states
            .insert((project.to_string(), artifact), load);
        self.set_legacy_artifact_path(project, artifact.as_str(), path);
    }

    fn set_legacy_artifact_path(&mut self, project: &str, artifact: &str, path: Option<String>) {
        // 同步旧缓存（旧 project.rs 读这个 Vec）
        let key = (project.to_string(), artifact.to_string());
        if let Some(slot) = self.artifacts.iter_mut().find(|(k, _)| *k == key) {
            slot.1 = path;
        } else {
            self.artifacts.push((key, path));
        }
    }

    /// v0 签名：返回产物路径（None = 未生成 or 探测失败）。**每次调用都真的检查。**
    pub fn probe_artifact(&mut self, project: &str, artifact: &str) -> Option<String> {
        let art = match artifact {
            "index" => Artifact::Index,
            "arch" => Artifact::Arch,
            _ => return None,
        };
        let load = self.refresh_artifact(project, art);
        if let Load::Failed(e) = &load {
            // 旧 project.rs 的签名只有 Option，会把「探测失败」渲染成「尚未生成」。
            // 至少用 feedback 把真相说出来（新页面用 artifact_states 的四态）。
            self.feedback = Some(Feedback::failure(format!(
                "产物探测失败（不是「未生成」）：{}",
                e.user_message()
            )));
        }
        match &load {
            Load::Ready(rc) if rc.exists => Some(rc.path.clone()),
            _ => None,
        }
    }

    pub fn open_artifact(&mut self, project: &str, artifact: &str) {
        let art = match artifact {
            "index" => Artifact::Index,
            "arch" => Artifact::Arch,
            other => {
                self.feedback = Some(Feedback::failure(format!("未知产物：{other}")));
                return;
            }
        };
        // 打开前强制重查：产物可能刚生成，缓存里的「未生成」会让按钮打不开。
        match self.refresh_artifact(project, art) {
            Load::Ready(rc) if rc.exists && !rc.path.is_empty() => {
                engine::open_external(&rc.path);
            }
            Load::Ready(_) => {
                self.feedback = Some(Feedback::failure(format!(
                    "{} 尚未生成。用任意 AI agent 按 `moongit skill graph` 的工作流生成后再打开。",
                    art.label()
                )));
            }
            Load::Failed(e) => {
                self.feedback = Some(Feedback::failure(format!(
                    "产物探测失败（不是「未生成」）：{}",
                    e.user_message()
                )));
            }
            _ => {}
        }
    }

    /// 进入项目页时预探两份产物（懒探测会先显示「尚未生成」——那是把
    /// 「还没查」呈现成「没有」）。
    pub fn probe_all_artifacts(&mut self, project: &str) {
        // `probe_artifact` 内部已经走 `probe_artifact_state` 并同步旧缓存，
        // 这里不再重复调用，避免一次进入项目页打 4 次 render check。
        for name in ["index", "arch"] {
            let _ = self.probe_artifact(project, name);
        }
    }

    // ── 项目详情按需加载 ─────────────────────────────────────────

    pub fn load_project_detail(&mut self, project: &str, force: bool) {
        let fresh = self
            .project_cache
            .get(project)
            .and_then(|d| d.loaded_at)
            .map(|t| t.elapsed().as_secs() < 20)
            .unwrap_or(false);
        if fresh && !force {
            return;
        }
        let branch = self.ui.project.journal_branch.clone();
        let limit = self.ui.project.limit();
        let mut detail = self.project_cache.remove(project).unwrap_or_default();
        detail.journal = Load::Loading;
        detail.docs = Load::Loading;
        detail.git_status = Load::Loading;
        detail.loaded_at = Some(Instant::now());
        detail.journal_branch = branch.clone();
        match self.engine.journal(project, branch.as_deref(), Some(limit)) {
            Ok(j) => detail.journal = Load::Ready(j),
            Err(e) => detail.journal = Load::Failed(e),
        }
        match self.engine.docs(project) {
            Ok(d) => detail.docs = Load::Ready(d),
            Err(e) => detail.docs = Load::Failed(e),
        }
        match self.engine.git_status(project) {
            Ok(g) => detail.git_status = Load::Ready(g),
            Err(e) => detail.git_status = Load::Failed(e),
        }
        for art in Artifact::all() {
            detail
                .artifacts
                .insert(art, self.probe_artifact_state(project, art));
        }
        self.project_cache.insert(project.to_string(), detail);
    }

    /// 日志页切分支：重新 `journal --branch`（不是客户端筛已加载窗口）。
    pub fn set_journal_branch(&mut self, project: &str, branch: Option<String>) {
        self.ui.project.journal_branch = branch.clone();
        let limit = self.ui.project.limit();
        let entry = self
            .project_cache
            .entry(project.to_string())
            .or_default();
        entry.journal = Load::Loading;
        entry.journal_branch = branch.clone();
        match self.engine.journal(project, branch.as_deref(), Some(limit)) {
            Ok(j) => entry.journal = Load::Ready(j),
            Err(e) => entry.journal = Load::Failed(e),
        }
    }

    pub fn load_more_journal(&mut self, project: &str) {
        self.ui.project.journal_limit = self.ui.project.limit().saturating_mul(2).min(2_000);
        let branch = self.ui.project.journal_branch.clone();
        self.set_journal_branch(project, branch);
    }

    // ── 命令面板 ─────────────────────────────────────────────────

    pub fn toggle_palette(&mut self) {
        self.palette = match self.palette.take() {
            Some(_) => None,
            None => Some(PaletteState::default()),
        };
    }

    pub fn palette_items(&self) -> Vec<PaletteItem> {
        let mut items = Vec::new();
        let views: [(Route, &str); 8] = [
            (Route::Dashboard, "仪表盘"),
            (Route::Board, "看板"),
            (Route::Milestones, "里程碑"),
            (Route::Confidence, "代码置信度"),
            (Route::Patch, "补丁体检"),
            (Route::Scan, "扫描与添加"),
            (Route::Settings(SettingsTab::General), "设置"),
            (Route::Agent, "AI 助手"),
        ];
        for (route, label) in views {
            items.push(PaletteItem {
                label: label.to_string(),
                kind: "视图",
                action: AppAction::Navigate(route),
            });
        }
        for p in self.projects() {
            items.push(PaletteItem {
                label: p.name.clone(),
                kind: "项目",
                action: AppAction::Navigate(Route::Project(p.name.clone())),
            });
        }
        items.push(PaletteItem {
            label: "刷新全部".to_string(),
            kind: "动作",
            action: AppAction::Refresh(RefreshScope::All),
        });
        items.push(PaletteItem {
            label: "引擎诊断".to_string(),
            kind: "动作",
            action: AppAction::ShowDoctor,
        });
        items
    }

    pub fn filtered_palette_items(&self) -> Vec<PaletteItem> {
        let q = match &self.palette {
            Some(p) => p.query.clone(),
            None => String::new(),
        };
        self.palette_items()
            .into_iter()
            .filter(|i| matches_query(&format!("{} {}", i.label, i.kind), &q))
            .collect()
    }

    pub fn palette_move(&mut self, delta: i32) {
        let len = self.filtered_palette_items().len();
        let Some(state) = self.palette.as_mut() else {
            return;
        };
        if len == 0 {
            state.selected = 0;
            return;
        }
        let cur = state.selected as i32 + delta;
        state.selected = cur.clamp(0, len as i32 - 1) as usize;
    }

    pub fn palette_select(&mut self) {
        let items = self.filtered_palette_items();
        let idx = self
            .palette
            .as_ref()
            .map(|p| p.selected)
            .unwrap_or(0)
            .min(items.len().saturating_sub(1));
        let Some(item) = items.get(idx).cloned() else {
            return;
        };
        self.palette = None;
        self.apply(item.action);
    }

    // ── 分发 ─────────────────────────────────────────────────────

    pub fn dispatch(&mut self, action: Action) {
        match action {
            Action::App(a) => self.apply(a),
            Action::Board(a) => views::board::reduce(self, a),
            Action::Confidence(a) => views::confidence::reduce(self, a),
            Action::Patch(a) => views::patch::reduce(self, a),
            Action::Scan(a) => views::scan::reduce(self, a),
        }
    }

    /// 应用层动作的唯一 reduce。
    pub fn apply(&mut self, action: AppAction) {
        match action {
            AppAction::Navigate(route) => self.navigate(route),
            AppAction::SetProjectTab(tab) => self.set_project_tab(tab),
            AppAction::Refresh(scope) => self.refresh_scope(scope),
            AppAction::LoadDashboard => self.load_dashboard(),
            AppAction::LoadMilestones => self.load_milestones(),
            AppAction::LoadRegistry => self.load_registry(),
            AppAction::LoadProject(name) => self.load_project_detail(&name, true),
            AppAction::SetLanguage(lang) => self.set_language(lang),
            AppAction::SetEngineBin(bin) => self.set_engine_bin(&bin),
            AppAction::RedetectEngine => self.redetect_engine(),
            AppAction::DismissFeedback => self.feedback = None,
            AppAction::DismissToast(id) => self.dismiss_toast(id),
            AppAction::RouteNote(text) => self.route_note = Some(text),
            AppAction::CopyText { text, label } => self.copy(&text, &label),
            AppAction::Open(target) => match target {
                OpenTarget::Url(u) => engine::open_external(&u),
                OpenTarget::Reveal(p) => engine::reveal_in_file_manager(&p),
                OpenTarget::Terminal(p) => engine::open_terminal(&p),
            },
            AppAction::AskConfirm(c) => self.ask_confirm(c),
            AppAction::ConfirmYes => self.confirm_yes(),
            AppAction::ConfirmNo => self.confirm_no(),
            AppAction::OpenMenu { x, y, items } => {
                self.menu = Some(MenuState { x, y, items });
            }
            AppAction::CloseMenu => self.menu = None,
            AppAction::TogglePalette => self.toggle_palette(),
            AppAction::SetPaletteQuery(q) => {
                if let Some(p) = self.palette.as_mut() {
                    p.query = q;
                    p.selected = 0;
                }
            }
            AppAction::PaletteMove(d) => self.palette_move(d),
            AppAction::PaletteSelect => self.palette_select(),
            AppAction::ClosePalette => self.palette = None,
            AppAction::CloseModal => self.modal = None,
            AppAction::Update { project, deep } => self.update(project.as_deref(), deep),
            AppAction::AskUpdate { project, deep } => self.ask_update(project, deep),
            AppAction::Git { project, op } => {
                self.git_action_full(&project, op, None, &[]);
            }
            AppAction::AskRemoveProject(name) => {
                self.ask_confirm(Confirm {
                    title: "取消注册项目？".to_string(),
                    body: format!(
                        "将把「{name}」从注册表移除。只取消注册：不删除仓库文件，进度库也保留。"
                    ),
                    confirm_label: "取消注册".to_string(),
                    danger: true,
                    action: PendingAction::RemoveProject { name },
                });
            }
            AppAction::RemoveProject(name) => self.remove_project(&name),
            AppAction::MilestoneAction { project, name, op } => {
                self.milestone_action_typed(&project, &name, op)
            }
            AppAction::AskMilestoneRemove { project, name } => {
                self.ask_milestone_remove(&project, &name)
            }
            AppAction::AskMilestoneDrop { project, name } => {
                self.ask_milestone_drop(&project, &name)
            }
            AppAction::MilestoneRemove { project, name } => {
                self.milestone_remove(&project, &name)
            }
            AppAction::OpenCommitSheet(p) => self.open_commit_sheet(&p),
            AppAction::CloseCommitSheet => self.close_commit_sheet(),
            AppAction::SetCommitMessage(m) => self.set_commit_message(m),
            AppAction::ToggleCommitPath(f) => self.toggle_commit_path(&f),
            AppAction::SelectAllPaths => self.select_all_paths(),
            AppAction::ClearSelection => self.clear_selection(),
            AppAction::SubmitCommit => self.submit_commit(),
            AppAction::OpenMilestoneSheet(p) => self.open_milestone_sheet(&p),
            AppAction::CloseMilestoneSheet => self.close_milestone_sheet(),
            AppAction::SetMilestoneField { field, value } => {
                self.set_milestone_field(field, value)
            }
            AppAction::SubmitMilestone => self.submit_milestone(),
            AppAction::RunScan => self.run_scan(),
            AppAction::AddProject => self.add_project(),
            AppAction::SetJournalBranch { project, branch } => {
                self.set_journal_branch(&project, branch)
            }
            AppAction::LoadMoreJournal(project) => self.load_more_journal(&project),
            AppAction::RunConfidence => self.run_confidence(),
            AppAction::RunConfidenceLlmPrompt => self.run_confidence_llm_prompt(),
            AppAction::RunPatch => self.run_patch(),
            AppAction::RunPatchSkill => self.run_patch_skill(),
            AppAction::RunPatchMerge => self.run_patch_merge(),
            AppAction::CheckArtifact { project, artifact } => {
                // 「检查」必须真的重查，不能读缓存。
                let _ = self.refresh_artifact(&project, artifact);
            }
            AppAction::OpenArtifact { project, artifact } => {
                self.open_artifact(&project, artifact.as_str())
            }
            AppAction::ShowDoctor => match self.engine.doctor() {
                Ok(text) => self.modal = Some(ModalState::Doctor(text)),
                Err(e) => self.fail(e),
            },
            AppAction::SetSidebarSearch(q) => self.ui.sidebar.search = q,
            AppAction::SetBoardQuery(q) => self.ui.board.query = q,
            AppAction::SetMilestoneSearch(q) => self.ui.milestones.search = q,
            AppAction::SetMilestoneProject(p) => self.ui.milestones.project = p,
            AppAction::SetMilestoneStatus(s) => self.ui.milestones.status = s,
            AppAction::SetDashboardRange(r) => self.ui.dashboard.range = r,
            AppAction::SetDashboardCommitType(t) => self.ui.dashboard.commit_type = t,
            AppAction::ToggleLangExpanded => {
                self.ui.dashboard.lang_expanded = !self.ui.dashboard.lang_expanded
            }
            AppAction::SetScanPath(p) => self.ui.scan.path = p,
            AppAction::SetScanName(n) => self.ui.scan.name = n,
            AppAction::AddScanRoot => {
                let p = self.ui.scan.path.trim().to_string();
                if p.is_empty() {
                    self.feedback = Some(Feedback::failure("先输入要添加的根目录"));
                } else if !self.ui.scan.roots.contains(&p) {
                    self.ui.scan.roots.push(p);
                }
            }
            AppAction::RemoveScanRoot(p) => self.ui.scan.roots.retain(|r| r != &p),
            AppAction::SetScanDepth(d) => {
                if (1..=6).contains(&d) {
                    self.ui.scan.depth = d;
                } else {
                    self.feedback = Some(Feedback::failure("扫描深度必须在 1–6 之间"));
                }
            }
            AppAction::SetScanGitOnly(v) => self.ui.scan.git_only = v,
            AppAction::SetConfidenceProject(p) => self.ui.confidence.project = p,
            AppAction::SetConfidenceMinWeight(w) => self.ui.confidence.min_weight = w,
            AppAction::SetPatchProject(p) => self.ui.patch.project = p,
            AppAction::SetPatchDiffPath(p) => self.ui.patch.diff_path = p,
            AppAction::SetPatchAlgorithmPath(p) => self.ui.patch.algorithm_path = p,
            AppAction::SetPatchAgentPath(p) => self.ui.patch.agent_path = p,
            AppAction::SetAgentJson(j) => self.ui.patch.agent_json = j,
            AppAction::Tick => self.tick(),
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// 根视图
// ══════════════════════════════════════════════════════════════════════

pub struct AppRoot {
    pub state: AppState,
}

impl blenderui::Render for AppRoot {
    fn render(
        &mut self,
        w: &mut blenderui::Window,
        cx: &mut blenderui::Context<Self>,
    ) -> impl blenderui::IntoElement {
        use blenderui::prelude::*;

        // 后台 Job 必须先于渲染起线程：`state.pending_job` 是动作层排队的，
        // 启动后立刻返回，`Load::Loading` 这一帧才画得出来。
        self.start_pending_job(cx);

        // 根视图统一 flush：dispatch/reduce 里没有 Window。
        if let Some(p) = self.state.pending_copy.take() {
            w.write_clipboard(&p.text);
            self.state.toast(Tone::Ok, "已复制", p.label);
        }
        if let Some(id) = self.state.pending_scroll.take() {
            w.set_scroll_offset(&id, 0.0, 0.0);
        }

        let mut root = div()
            .class("app")
            .child(style().child(crate::design::SHEET))
            .child(
                div()
                    .class("app-bg")
                    .child(div().class("aurora aurora-a"))
                    .child(div().class("aurora aurora-b"))
                    .child(div().class("aurora aurora-c")),
            )
            .child(views::sidebar::render(&self.state, cx))
            .child(views::render_route(&self.state, cx));

        if let Some(m) = self.render_menu(w, cx) {
            root = root.child(m);
        }
        if let Some(t) = self.render_toasts(cx) {
            root = root.child(t);
        }
        if let Some(c) = self.render_confirm(cx) {
            root = root.child(c);
        }
        // 提交弹层只有一份：`views/commit_sheet.rs`（项目页挂载）。
        // 这里曾有一份 v0 根级副本，两份 overlay 叠在同一份 state 上。
        if let Some(m) = self.render_milestone_sheet(cx) {
            root = root.child(m);
        }
        if let Some(p) = self.render_palette(cx) {
            root = root.child(p);
        }
        if let Some(m) = self.render_modal(cx) {
            root = root.child(m);
        }
        // 键盘事件从被点中的元素冒泡到这里（BUI 的 key 事件先给原生控件，
        // 同时沿布局父链送到根）。只消费明确的应用级组合，见 `handle_shortcut`。
        root.on_key_down(cx.listener(
            |this, e: &blenderui::KeyDownEvent, _w, cx| {
                if this.state.handle_shortcut(&e.keystroke) {
                    cx.notify();
                }
            },
        ))
    }
}

impl AppRoot {
    /// 把 `AppState` 里排队的 Job 搬上后台线程。
    ///
    /// 只有这里拿得到 `UiSender` / `Entity<AppRoot>`（`AppState` 的方法没有
    /// `Context`）。Job 完成后经 `UiSender` 回到 UI 线程更新同一个 `AppState`，
    /// 所以动作层仍是同步语义，不需要第二套状态。
    fn start_pending_job(&mut self, cx: &mut blenderui::Context<AppRoot>) {
        let Some(job) = self.state.pending_job.take() else {
            return;
        };
        let base = self.state.engine.clone();
        let entity = cx.entity();
        let sender = cx.ui_sender();

        match job {
            JobRequest::Confidence { project, cancel } => {
                std::thread::spawn(move || {
                    let result = base.with_cancel(cancel).confidence(&project);
                    sender.send(move |app| {
                        entity.update(app, |this, cx| {
                            this.state.confidence_cancel = None;
                            match result {
                                Ok(r) => {
                                    this.state.confidence = Load::Ready(r);
                                    views::confidence::mark_result_project(
                                        &mut this.state,
                                        &project,
                                    );
                                }
                                Err(EngineError::Cancelled) => {
                                    // 用户自己停的不报「失败」，也不弹红色横幅。
                                    this.state.confidence = Load::Failed(EngineError::Cancelled);
                                    this.state.toast(
                                        Tone::Info,
                                        "已停止",
                                        format!("置信度分析已取消：{project}"),
                                    );
                                }
                                Err(e) => {
                                    let msg = e.user_message();
                                    this.state.confidence = Load::Failed(e);
                                    this.state.feedback = Some(Feedback::failure(msg));
                                }
                            }
                            // 后台线程写的 stderr 告警与主线程共用同一缓冲：回到 UI 线程再取。
                            this.state.drain_warnings();
                            cx.notify();
                        });
                    });
                });
            }
            JobRequest::Patch {
                project,
                explicit_diff,
                repo_path,
                cancel,
            } => {
                std::thread::spawn(move || {
                    let done = run_patch_job(&base, cancel, &project, explicit_diff, repo_path);
                    sender.send(move |app| {
                        entity.update(app, |this, cx| {
                            this.state.patch_cancel = None;
                            if let Some(p) = &done.diff_path {
                                this.state.ui.patch.last_diff_path = p.clone();
                            }
                            match done.result {
                                Ok(r) => {
                                    this.state.patch = Load::Ready(r);
                                    views::patch::mark_result_project(&mut this.state, &project);
                                    match done.algorithm_path {
                                        Some(a) => {
                                            // 只删上一份**自己建的**临时报告；用户指定的路径不动。
                                            let old = this.state.ui.patch.algorithm_path.clone();
                                            let old_is_ours = old.contains("deepdolphin-algorithm-")
                                                && std::path::Path::new(&old)
                                                    .starts_with(std::env::temp_dir());
                                            if old != a && old_is_ours {
                                                let _ = std::fs::remove_file(&old);
                                            }
                                            this.state.ui.patch.algorithm_path = a.clone();
                                            this.state.feedback = Some(Feedback::success(format!(
                                                "补丁体检完成；Layer-1 报告已写到 {a}（合并终稿会用它）"
                                            )));
                                        }
                                        None => {
                                            let caveat = done
                                                .note
                                                .unwrap_or_else(|| "原因未披露".to_string());
                                            this.state.feedback = Some(Feedback::success(format!(
                                                "补丁体检完成；但 Layer-1 报告没有落盘（{caveat}）——合并终稿前需手动另存"
                                            )));
                                            this.state.toast(
                                                Tone::Warn,
                                                "Layer-1 未落盘",
                                                "分析结果已显示；合并前需要 algorithm.json".to_string(),
                                            );
                                        }
                                    }
                                }
                                Err(EngineError::Cancelled) => {
                                    this.state.patch = Load::Failed(EngineError::Cancelled);
                                    this.state.toast(
                                        Tone::Info,
                                        "已停止",
                                        format!("补丁分析已取消：{project}"),
                                    );
                                }
                                Err(e) => {
                                    let msg = e.user_message();
                                    this.state.patch = Load::Failed(e);
                                    this.state.feedback = Some(Feedback::failure(msg));
                                }
                            }
                            this.state.drain_warnings();
                            cx.notify();
                        });
                    });
                });
            }
        }
    }

    fn render_menu(
        &self,
        w: &mut blenderui::Window,
        cx: &mut blenderui::Context<AppRoot>,
    ) -> Option<Div> {
        use blenderui::prelude::*;
        let menu = self.state.menu.as_ref()?;
        let clear = div()
            .class("overlay-clear")
            .on_click(cx.listener(|this, _, _, cx| {
                this.state.apply(AppAction::CloseMenu);
                cx.notify();
            }));
        // 菜单是 fixed 定位、宽 200px；右上角「更多 ▾」点开时 x/y 都靠近视口边缘，
        // 不加钳制会伸出窗口右侧/底部。放不下就翻到点击点上方，再钳回视口。
        const MENU_W: f32 = 200.0;
        const ROW_H: f32 = 31.0;
        const EDGE: f32 = 8.0;
        let vw = w.viewport_size().width.0;
        let vh = w.viewport_size().height.0;
        let est_h = (menu.items.len() as f32 * ROW_H + 8.0).min((vh - EDGE * 2.0).max(ROW_H));
        let left = menu.x.min((vw - MENU_W - EDGE).max(EDGE)).max(EDGE);
        let below = menu.y + est_h <= vh - EDGE;
        let mut top = if below { menu.y } else { menu.y - est_h };
        top = top.clamp(EDGE, (vh - est_h - EDGE).max(EDGE));
        let mut panel = div().class("menu").style(format!(
            "left: {left}px; top: {top}px; max-height: {est_h}px; overflow-y: auto;"
        ));
        for item in &menu.items {
            let action = item.action.clone();
            let mut row = div()
                .class(if item.danger {
                    "menu-item menu-danger"
                } else {
                    "menu-item"
                })
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.state.menu = None;
                    this.state.apply(action.clone());
                    cx.notify();
                }))
                .child(item.label.clone());
            if let Some(sc) = &item.shortcut {
                row = row.child(div().class("menu-shortcut").child(sc.clone()));
            }
            panel = panel.child(row);
        }
        Some(div().child(clear).child(panel))
    }

    fn render_toasts(&self, cx: &mut blenderui::Context<AppRoot>) -> Option<Div> {
        use blenderui::prelude::*;
        if self.state.toast.is_empty() {
            return None;
        }
        let mut wrap = div().class("toast-wrap");
        for t in &self.state.toast {
            let id = t.id;
            let mut card = div()
                .class(format!("toast {}", t.tone.class()))
                .child(div().class("row-between").child(
                    div()
                        .class("toast-title")
                        .child(t.title.clone()),
                ));
            if !t.body.is_empty() {
                card = card.child(div().class("toast-body").child(t.body.clone()));
            }
            let mut row = div().class("row");
            if let Some(action) = &t.action {
                let action = action.clone();
                row = row.child(
                    div()
                        .class("btn btn-sm btn-accent")
                        .child("打开")
                        .on_click(cx.listener(move |this, _, _, cx| {
                            this.state.apply(action.clone());
                            cx.notify();
                        })),
                );
            }
            row = row.child(div().class("spacer"));
            row = row.child(
                div()
                    .class("btn btn-sm btn-ghost")
                    .child("关闭")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.dismiss_toast(id);
                        cx.notify();
                    })),
            );
            card = card.child(row);
            wrap = wrap.child(card);
        }
        Some(wrap)
    }

    fn render_confirm(&self, cx: &mut blenderui::Context<AppRoot>) -> Option<Div> {
        use blenderui::prelude::*;
        let c = self.state.confirm.as_ref()?;
        let icon_class = if c.danger {
            "confirm-icon danger"
        } else {
            "confirm-icon"
        };
        let modal = div()
            .class("modal modal-sm glass-strong")
            .on_click(cx.listener(|_, _, _, cx| {
                cx.stop_propagation();
            }))
            .child(
                div()
                    .class("modal-head")
                    .child(div().class(icon_class).child(if c.danger { "!" } else { "?" }))
                    .child(div().class("modal-title").child(c.title.clone())),
            )
            .child(div().class("modal-body").child(div().class("t-body").child(c.body.clone())))
            .child(
                div()
                    .class("modal-foot")
                    .child(
                        div()
                            .class("btn btn-ghost")
                            .child("取消")
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.state.apply(AppAction::ConfirmNo);
                                cx.notify();
                            })),
                    )
                    .child(
                        div()
                            .class(if c.danger {
                                "btn btn-danger"
                            } else {
                                "btn btn-accent"
                            })
                            .child(c.confirm_label.clone())
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.state.apply(AppAction::ConfirmYes);
                                cx.notify();
                            })),
                    ),
            );
        Some(
            div()
                .class("overlay")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.apply(AppAction::ConfirmNo);
                    cx.notify();
                }))
                .child(modal),
        )
    }

    fn render_milestone_sheet(&self, cx: &mut blenderui::Context<AppRoot>) -> Option<Div> {
        use blenderui::prelude::*;
        let form = self.state.milestone_sheet.as_ref()?;
        let valid = !form.project.trim().is_empty()
            && !form.name.trim().is_empty()
            && (form.date.trim().is_empty() || crate::models::valid_date(form.date.trim()));

        let text_field = |label: &'static str, id: &'static str, value: String, placeholder: &'static str, cx: &mut blenderui::Context<AppRoot>, field: MilestoneField| {
            div()
                .class("field")
                .child(div().class("field-label").child(label))
                .child(
                    div().class("field-box").child(
                        input()
                            .class("input")
                            .id(id)
                            .placeholder(placeholder)
                            .value(value)
                            .on_input(cx.listener(move |this, e: &blenderui::ChangeEvent, _, cx| {
                                this.state.set_milestone_field(field, e.value.clone());
                                cx.notify();
                            })),
                    ),
                )
        };

        let body = div()
            .class("modal-body")
            .child(text_field(
                "项目（必填）",
                "ms-project",
                form.project.clone(),
                "注册表里的项目名",
                cx,
                MilestoneField::Project,
            ))
            .child(text_field(
                "名称（必填）",
                "ms-name",
                form.name.clone(),
                "例如 v0.2-面板版",
                cx,
                MilestoneField::Name,
            ))
            .child(text_field(
                "tag（可选）",
                "ms-tag",
                form.tag.clone(),
                "例如 v0.2",
                cx,
                MilestoneField::Tag,
            ))
            .child(text_field(
                "目标日期（可选，YYYY-MM-DD）",
                "ms-date",
                form.date.clone(),
                "2026-12-31",
                cx,
                MilestoneField::Date,
            ))
            .child(
                div()
                    .class("field")
                    .child(div().class("field-label").child("描述（可选）"))
                    .child(
                        div().class("field-box").child(
                            textarea()
                                .class("textarea")
                                .id("ms-desc")
                                .placeholder("这条里程碑要达成什么")
                                .value(form.desc.clone())
                                .on_input(cx.listener(|this, e: &blenderui::ChangeEvent, _, cx| {
                                    this.state.set_milestone_field(
                                        MilestoneField::Desc,
                                        e.value.clone(),
                                    );
                                    cx.notify();
                                })),
                        ),
                    ),
            );
        let body = match &form.error {
            Some(err) => body.child(div().class("field-error").child(err.clone())),
            None => body,
        };

        let foot = div()
            .class("modal-foot")
            .child(
                div()
                    .class("btn btn-ghost")
                    .child("取消")
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.state.apply(AppAction::CloseMilestoneSheet);
                        cx.notify();
                    })),
            )
            .child(
                div()
                    .class(if valid {
                        "btn btn-accent"
                    } else {
                        "btn btn-accent is-disabled"
                    })
                    .child(if form.busy { "提交中…" } else { "新建里程碑" })
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.state.apply(AppAction::SubmitMilestone);
                        cx.notify();
                    })),
            );

        let modal = div()
            .class("modal modal-md glass-strong")
            .on_click(cx.listener(|_, _, _, cx| {
                cx.stop_propagation();
            }))
            .child(
                div()
                    .class("modal-head")
                    .child(div().class("modal-title").child("新建里程碑"))
                    .child(div().class("modal-sub").child("项目与名称非空；日期用 YYYY-MM-DD")),
            )
            .child(body)
            .child(foot);

        Some(
            div()
                .class("overlay")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.apply(AppAction::CloseMilestoneSheet);
                    cx.notify();
                }))
                .child(modal),
        )
    }

    fn render_palette(&self, cx: &mut blenderui::Context<AppRoot>) -> Option<Div> {
        use blenderui::prelude::*;
        let state = self.state.palette.as_ref()?;
        let items = self.state.filtered_palette_items();
        let mut list = div().class("palette-list");
        if items.is_empty() {
            list = list.child(div().class("palette-empty").child("没有匹配的视图、项目或动作"));
        }
        for (i, item) in items.iter().enumerate() {
            let action = item.action.clone();
            let on = i == state.selected.min(items.len().saturating_sub(1));
            list = list.child(
                div()
                    .class(if on {
                        "palette-item palette-item-on"
                    } else {
                        "palette-item"
                    })
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.palette = None;
                        this.state.apply(action.clone());
                        cx.notify();
                    }))
                    .child(item.label.clone())
                    .child(div().class("palette-kind").child(item.kind)),
            );
        }
        let panel = div()
            .class("palette")
            .on_click(cx.listener(|_, _, _, cx| {
                cx.stop_propagation();
            }))
            .child(
                div().class("palette-input").child(
                    div().class("field-box").child(
                        input()
                            .class("input")
                            .id("palette-query")
                            .placeholder("搜索视图 / 项目 / 动作")
                            .value(state.query.clone())
                            .on_input(cx.listener(|this, e: &blenderui::ChangeEvent, _, cx| {
                                this.state.apply(AppAction::SetPaletteQuery(e.value.clone()));
                                cx.notify();
                            })),
                    ),
                ),
            )
            .child(list)
            .child(
                div()
                    .class("modal-foot")
                    .child(div().class("t-caption").child(
                        "⌘K 打开 · ↑↓ 选择 · Enter 执行 · Esc 关闭；搜索输入框需先点一下（BUI 不能把原生键盘焦点交给它）",
                    ))
                    .child(div().class("spacer"))
                    .child(
                        div()
                            .class("btn btn-sm btn-ghost")
                            .child("关闭")
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.state.apply(AppAction::ClosePalette);
                                cx.notify();
                            })),
                    ),
            );
        Some(
            div()
                .class("overlay-top")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.apply(AppAction::ClosePalette);
                    cx.notify();
                }))
                .child(panel),
        )
    }

    fn render_modal(&self, cx: &mut blenderui::Context<AppRoot>) -> Option<Div> {
        use blenderui::prelude::*;
        let m = self.state.modal.as_ref()?;
        let (title, body_text) = match m {
            ModalState::Doctor(text) => ("引擎诊断（doctor）", text.clone()),
            ModalState::Text { title, body } => (title.as_str(), body.clone()),
            ModalState::AiResult(r) => {
                let text = match &r.raw {
                    Load::Ready(t) => t.clone(),
                    Load::Failed(e) => format!("失败：{}", e.user_message()),
                    Load::Loading => "生成中…".to_string(),
                    Load::Idle => String::new(),
                };
                (r.title.as_str(), text)
            }
        };
        // 纯 ASCII 正文用等宽（诊断表/路径对齐）；含中文时留 CJK 字面，
        // 否则等宽字体没有的字形会变豆腐块。
        let pre_class = if body_text.chars().any(|c| (c as u32) >= 0x2E80) {
            "pre"
        } else {
            "pre pre-mono"
        };
        let body = div()
            .class("modal-body")
            .child(div().class(pre_class).child(body_text.clone()));
        let foot = div()
            .class("modal-foot")
            .child(
                div()
                    .class("btn")
                    .child("复制全文")
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.state.copy(&body_text, "全文");
                        cx.notify();
                    })),
            )
            .child(
                div()
                    .class("btn btn-accent")
                    .child("关闭")
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.state.apply(AppAction::CloseModal);
                        cx.notify();
                    })),
            );
        let modal = div()
            .class("modal modal-xl glass-strong")
            .on_click(cx.listener(|_, _, _, cx| {
                cx.stop_propagation();
            }))
            .child(
                div()
                    .class("modal-head")
                    .child(div().class("modal-title").child(title.to_string()))
                    .child(
                        div()
                            .class("modal-sub")
                            .child("文本输出；不含解释性加工"),
                    ),
            )
            .child(body)
            .child(foot);
        Some(
            div()
                .class("overlay")
                .on_click(cx.listener(|this, _, _, cx| {
                    this.state.apply(AppAction::CloseModal);
                    cx.notify();
                }))
                .child(modal),
        )
    }
}

// ══════════════════════════════════════════════════════════════════════
// 小工具
// ══════════════════════════════════════════════════════════════════════

/// ASCII 不区分大小写；中文按子串。空查询匹配全部。
pub fn matches_query(haystack: &str, query: &str) -> bool {
    let q = query.trim();
    if q.is_empty() {
        return true;
    }
    haystack.to_lowercase().contains(&q.to_lowercase())
}

fn last_nonempty_line(text: &str) -> String {
    text.lines()
        .rev()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .unwrap_or("完成")
        .to_string()
}

fn multi_failed_names(m: &models::MultiResults) -> Vec<String> {
    let mut out = Vec::new();
    for r in &m.results {
        // 成功项带 `ok:true`；失败项实测是 `{code,message}`（**没有 ok 键**），
        // 所以「不是 Some(true)」才是逐项的失败判据。
        if r.get("ok").and_then(|x| x.as_bool()) == Some(true) {
            continue;
        }
        let name = r
            .get("project")
            .and_then(|x| x.as_str())
            .or_else(|| r.get("name").and_then(|x| x.as_str()))
            .map(str::to_string)
            .or_else(|| {
                let msg = r.get("message").and_then(|x| x.as_str())?;
                // 失败项没有 project 键，项目名在 message 前缀里：
                // 「<项目> 更新失败：…」
                let prefix = msg.split(" 更新失败").next()?.trim();
                if prefix.is_empty() || prefix.len() == msg.trim().len() {
                    None
                } else {
                    Some(prefix.to_string())
                }
            })
            .unwrap_or_else(|| "(未命名)".to_string());
        let code = r.get("code").and_then(|x| x.as_str());
        match code {
            Some(code) => out.push(format!("{name}（{code}）")),
            None => out.push(name),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn multi_failed_names_recognizes_code_message_items() {
        // 成功项 ok:true；失败项可能是 ok:false + project，也可能是 {code,message} 且没有 project。
        let m = models::MultiResults {
            results: vec![
                serde_json::json!({"ok": true, "project": "ok1"}),
                serde_json::json!({"ok": false, "project": "bad1", "code": "WRITE_FAILED"}),
                serde_json::json!({"code": "VOLUME_BLOCKED", "message": "uf2 更新失败：路径不存在"}),
                serde_json::json!({"message": "something else"}),
            ],
            count: 4,
            failed: 3,
            succeeded: 1,
        };
        assert_eq!(
            multi_failed_names(&m),
            vec![
                "bad1（WRITE_FAILED）".to_string(),
                "uf2（VOLUME_BLOCKED）".to_string(),
                "(未命名)".to_string(),
            ]
        );
    }

    #[test]
    fn query_matching_is_ascii_case_insensitive_and_chinese_substring() {
        assert!(matches_query("DeepOrca-Site", "deeporca"));
        assert!(matches_query("项目群进度", "进度"));
        assert!(matches_query("任意", ""));
        assert!(!matches_query("abc", "xyz"));
    }

    #[test]
    fn scan_roots_fall_back_to_single_path() {
        let mut form = ScanForm::default();
        form.path = "  /tmp/one  ".to_string();
        assert_eq!(form.effective_roots(), vec!["/tmp/one".to_string()]);
        form.roots = vec!["/tmp/a".to_string(), "/tmp/b".to_string()];
        assert_eq!(form.effective_roots(), vec!["/tmp/a".to_string(), "/tmp/b".to_string()]);
    }

    #[test]
    fn feedback_tone_is_derived_from_ok() {
        assert_eq!(Feedback::success("x").tone(), Tone::Ok);
        assert_eq!(Feedback::failure("x").tone(), Tone::Err);
    }

    #[test]
    fn milestone_filter_matches_missing_status_as_unknown() {
        // 旧引擎/缺键的里程碑：status 是 None，但它必须能被「无法核验」筛出来。
        let m = models::Milestone {
            name: "x".to_string(),
            project: None,
            project_id: "p_1".to_string(),
            status: None,
            ..Default::default()
        };
        let unknown = MilestoneFilters {
            status: Some("unknown".to_string()),
            ..Default::default()
        };
        assert!(unknown.matches(&m));

        let open = MilestoneFilters {
            status: Some("open".to_string()),
            ..Default::default()
        };
        assert!(!open.matches(&m));

        // 项目筛选与展示同口径：缺 projectName 时按 projectId。
        let by_id = MilestoneFilters {
            project: Some("p_1".to_string()),
            ..Default::default()
        };
        assert!(by_id.matches(&m));
    }
}
