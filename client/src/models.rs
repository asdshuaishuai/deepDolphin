// models.rs — 引擎 JSON 契约的 Rust 只读镜像。
//
// 【纪律】引擎的键名就是契约；这里只做**只读投影**：
//   · 只取 UI 用得上的字段（不为「完整性」抄整份引擎结构）；
//   · 缺键一律 Option —— 缺席不是 0、不是空串、不是 false；
//   · 引擎用 `-1` 表示「读不出来」的计数，这里保留原值并由 `Reading` 解释，
//     绝不在反序列化时把它抹成 0（那会把故障渲染成「干净」）。
//
// 【本文件的三种「不知道」】
//   · `Option<T>::None`       —— 键不存在（旧引擎 / 该路径不写这个键）；
//   · `i64 == -1`             —— 引擎明确说「这个数读不出来」（`read_i64`）；
//   · `Option<bool>::None`    —— 披露类布尔缺失：**不许当成 false**。
//
// 【实测依据】2026-11-13 对 `moonGit/target/release/bin/main` 实跑：
//   status（17 项目，含 2 个失败项目 `dirty:{} / overall:{} / -1`）、dashboard、
//   milestone list（17 键条目 / 7 键孤儿 / 9 键 add 回执）、docs、journal、
//   git status（内层 JSON 在 `output` 字符串里）、git commit --paths、
//   scan（三轴覆盖度）、graph confidence、graph patchconf。
//   形状与 `AGENTS.md` 的契约条一致。

// 契约镜像：部分字段当前 UI 未消费，但保留形状（引擎契约的文档价值）。
#![allow(dead_code)]

use serde::Deserialize;
use std::collections::BTreeMap;
use std::time::Instant;


// ══════════════════════════════════════════════════════════════════════
// 基础三态
// ══════════════════════════════════════════════════════════════════════

/// 「读出来了」/「没读出来」。读不出来是**第三态**，不是 0、不是空、不是失败。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Reading<T> {
    Known(T),
    NotRead,
}

impl<T> Reading<T> {
    pub fn known(self) -> Option<T> {
        match self {
            Reading::Known(v) => Some(v),
            Reading::NotRead => None,
        }
    }
    pub fn is_known(&self) -> bool {
        matches!(self, Reading::Known(_))
    }
    pub fn unwrap_or(self, fallback: T) -> T {
        match self {
            Reading::Known(v) => v,
            Reading::NotRead => fallback,
        }
    }
}

/// 引擎的 `-1` = 读不出来。`>= 0` 才是真实数字。
pub fn read_i64(v: i64) -> Reading<i64> {
    if v < 0 {
        Reading::NotRead
    } else {
        Reading::Known(v)
    }
}

/// 缺键（None）与 `-1` 都算读不出来。
pub fn read_opt_i64(v: Option<i64>) -> Reading<i64> {
    match v {
        Some(n) if n >= 0 => Reading::Known(n),
        _ => Reading::NotRead,
    }
}

/// 八种色调（与 design.rs 的 `.ok/.warn/...` 一一对应）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tone {
    Ok,
    Warn,
    Stale,
    Err,
    Info,
    Unknown,
    Accent,
    Idle,
}

impl Tone {
    /// 对应 design.rs 的色调 token（可直接拼进 class 列表）。
    pub fn class(&self) -> &'static str {
        match self {
            Tone::Ok => "ok",
            Tone::Warn => "warn",
            Tone::Stale => "stale",
            Tone::Err => "err",
            Tone::Info => "info",
            Tone::Unknown => "unknown",
            Tone::Accent => "accent",
            Tone::Idle => "idle",
        }
    }
}

/// 一层截断的披露：「谁砍的、砍到多少、原文多少」。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Truncation {
    pub layer: &'static str,
    pub shown: usize,
    pub total: Option<usize>,
    pub note: String,
}

/// 看板四列。**顺序即优先级**：Pending > Stale > Active > Other。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BoardColumn {
    Pending,
    Stale,
    Active,
    Other,
}

impl BoardColumn {
    pub fn title(&self) -> &'static str {
        match self {
            BoardColumn::Pending => "待处理",
            BoardColumn::Stale => "久未更新",
            BoardColumn::Active => "活跃中",
            BoardColumn::Other => "其他",
        }
    }
    pub fn criteria(&self) -> &'static str {
        match self {
            BoardColumn::Pending => "有未提交 / 未跟踪 / stash；读不出来的脏度不算",
            BoardColumn::Stale => "最近提交超过 30 天（或当前分支停滞 >30 天）",
            BoardColumn::Active => "最近 7 天内有提交",
            BoardColumn::Other => "其余项目（含提交时间读不出来）",
        }
    }
}

/// journal `commitCount` 的口径：同名不同义的数字必须自带口径。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScopeBadge {
    New(i64),
    RepoTotal(i64),
    UnknownScope(i64),
    NotRead,
}

impl ScopeBadge {
    pub fn label(&self) -> String {
        match self {
            ScopeBadge::New(n) => format!("+{n} 本轮新增"),
            ScopeBadge::RepoTotal(n) => format!("累计 {n}"),
            ScopeBadge::UnknownScope(n) => format!("口径未知 {n}"),
            ScopeBadge::NotRead => "提交数读不出来".to_string(),
        }
    }
    pub fn tone(&self) -> Tone {
        match self {
            ScopeBadge::New(_) => Tone::Ok, // 绿色只留给真增量
            ScopeBadge::RepoTotal(_) => Tone::Idle,
            ScopeBadge::UnknownScope(_) => Tone::Unknown,
            ScopeBadge::NotRead => Tone::Unknown,
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// status
// ══════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct StatusEnvelope {
    #[serde(default)]
    pub projects: Vec<Project>,
    #[serde(default)]
    pub summary: Summary,
    /// 引擎事实语言（zh / en）。缺键 = 不知道，不假设 zh。
    #[serde(default)]
    pub language: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Summary {
    #[serde(default)]
    pub project_count: i64,
    #[serde(default)]
    pub degraded_stores: i64,
    #[serde(default)]
    pub listed_projects: i64,
    #[serde(default)]
    pub failed_projects: i64,
    #[serde(default)]
    pub active_projects: i64,
    #[serde(default)]
    pub stale_projects: i64,
    #[serde(default)]
    pub dirty_projects: i64,
    #[serde(default)]
    pub branch_count: i64,
    #[serde(default)]
    pub repo_branch_total: i64,
    #[serde(default)]
    pub branch_truncated_projects: i64,
    #[serde(default)]
    pub branch_unknown_projects: i64,
    #[serde(default)]
    pub generated_at: String,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Project {
    // ── 身份 ──
    #[serde(default)]
    pub store_health: String,
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub path: String,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub remote: String,
    /// 采集失败原因。**失败项目仍然是完整形状**（dirty/overall 是 `{}`）。
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub headline: Option<String>,
    // ── 分支 ──
    #[serde(default)]
    pub current_branch: Option<String>,
    #[serde(default)]
    pub default_branch: Option<String>,
    // ── 脏度（-1 = 读不出来）──
    #[serde(default)]
    pub user_dirty_count: Option<i64>,
    #[serde(default)]
    pub untracked_count: Option<i64>,
    #[serde(default)]
    pub untracked_error: String,
    #[serde(default)]
    pub stash_count: Option<i64>,
    #[serde(default)]
    pub worktree_count: Option<i64>,
    // ── 最近提交 ──
    #[serde(default)]
    pub last_commit_ago: Option<String>,
    #[serde(default)]
    pub last_commit_at: String,
    // ── 提交构成 ──
    #[serde(default)]
    pub commit_types: Vec<CommitTypeCount>,
    /// `None` = 引擎没发这个键（不许当成「没截断」）。
    #[serde(default)]
    pub commit_types_truncated: Option<bool>,
    // ── 分支明细 ──
    #[serde(default)]
    pub branches: Vec<Branch>,
    #[serde(default)]
    pub repo_branch_count: Option<i64>,
    // ── 日志 ──
    #[serde(default)]
    pub journal: Vec<JournalEntry>,
    #[serde(default)]
    pub journal_truncated: Option<bool>,
    #[serde(default)]
    pub journal_limit: i64,
    #[serde(default)]
    pub journal_unparsable_lines: Option<i64>,
    // ── 披露与元数据 ──
    #[serde(default)]
    pub warnings: Option<Vec<String>>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub manifests: Vec<String>,
    /// 失败项目实测是 `{}`（不是 null）。`Option` 区分「对象缺席」。
    #[serde(default)]
    pub dirty: Option<Dirty>,
    /// `-1` = 读不出来（失败项目）。
    #[serde(default)]
    pub commit_count: Option<i64>,
    /// 失败项目实测是 `{}`。
    #[serde(default)]
    pub overall: Option<Overall>,
    #[serde(default)]
    pub docs: Option<Vec<DocEntry>>,
    #[serde(default)]
    pub progress: Progress,
    #[serde(default)]
    pub fetched_at: String,
}

impl Project {
    pub fn is_git(&self) -> bool {
        self.kind == "git"
    }

    /// 有 `error` 就是采集失败：**读不出来**，不是「健康但空」。
    pub fn is_readable(&self) -> bool {
        self.error.is_none()
    }

    /// 结构化脏度。`None` / `ok=false` / `total` 缺失都算 NotRead。
    pub fn dirty_state(&self) -> Reading<&Dirty> {
        match &self.dirty {
            Some(d) if d.ok => Reading::Known(d),
            _ => Reading::NotRead,
        }
    }

    /// 总体摘要。失败项目的 `{}`（summary 空 + notes 空）算 NotRead。
    pub fn overall_state(&self) -> Reading<&Overall> {
        match &self.overall {
            Some(o) if !o.summary.trim().is_empty() || !o.notes.is_empty() => Reading::Known(o),
            _ => Reading::NotRead,
        }
    }

    /// 当前分支条目（HEAD 短 SHA / 停滞天数的来源）。
    pub fn current_branch_entry(&self) -> Option<&Branch> {
        self.branches.iter().find(|b| b.is_current)
    }

    /// 最近一次更新距今（引擎给的是字符串，不可解析时 None）。
    pub fn progress_age_days(&self) -> Reading<i64> {
        age_days(&self.progress.last_update_at)
    }
}

#[derive(Debug, Clone, Deserialize, Default, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Dirty {
    #[serde(default)]
    pub ok: bool,
    #[serde(default)]
    pub clean: bool,
    #[serde(default)]
    pub staged: i64,
    #[serde(default)]
    pub modified: i64,
    #[serde(default)]
    pub untracked: i64,
    #[serde(default)]
    pub conflicts: i64,
    #[serde(default)]
    pub total: i64,
    #[serde(default)]
    pub files: Vec<String>,
    #[serde(default)]
    pub err: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Default, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Overall {
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Progress {
    #[serde(default)]
    pub updated_at: String,
    #[serde(default)]
    pub last_update_at: String,
    #[serde(default)]
    pub last_track_at: String,
    #[serde(default)]
    pub last_deep_at: String,
    #[serde(default)]
    pub entry_count: i64,
    #[serde(default)]
    pub entry_count_truncated: Option<bool>,
    #[serde(default)]
    pub entries_kept: i64,
    #[serde(default)]
    pub run_count: i64,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct DocEntry {
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub exists: bool,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Branch {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub status_label: String,
    #[serde(default)]
    pub head: String,
    #[serde(default)]
    pub head_short: String,
    #[serde(default)]
    pub head_date: String,
    #[serde(default)]
    pub head_ago: String,
    #[serde(default)]
    pub head_subject: String,
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub highlights: Vec<String>,
    #[serde(default)]
    pub next_steps: Vec<String>,
    #[serde(default)]
    pub ahead_of_default: i64,
    #[serde(default)]
    pub merged: bool,
    #[serde(default)]
    pub pending_commits: i64,
    #[serde(default)]
    pub baseline_reset: bool,
    #[serde(default)]
    pub provider: String,
    #[serde(default)]
    pub is_current: bool,
    #[serde(default)]
    pub is_default: bool,
    #[serde(default)]
    pub updated_at: String,
    /// `-1` = 停滞天数读不出来。
    #[serde(default)]
    pub stale_days: i64,
}

impl Branch {
    /// 停滞天数（`-1` 是「读不出来」，不是「0 天」）。
    pub fn stale_days_reading(&self) -> Reading<i64> {
        read_i64(self.stale_days)
    }

    /// 待记录提交数：基线重置后不报数（数字没有意义）。
    pub fn pending_label(&self) -> String {
        if self.baseline_reset {
            "基线已重置".to_string()
        } else {
            format!("{} 个待记录", self.pending_commits)
        }
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct JournalEntry {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub at: String,
    #[serde(default)]
    pub project: String,
    #[serde(default)]
    pub project_id: String,
    #[serde(default)]
    pub branch: String,
    #[serde(default)]
    pub mode: String,
    #[serde(default)]
    pub source: String,
    #[serde(default)]
    pub provider: String,
    #[serde(default)]
    pub provider_label: String,
    #[serde(default)]
    pub summary: String,
    /// `None` = 键不存在；`-1` = 读不出来。两者都不是 0。
    #[serde(default)]
    pub commit_count: Option<i64>,
    /// 口径：`new`（本轮新增）/ `repoTotal`（仓库累计）。缺键 = 口径未知。
    #[serde(default)]
    pub commit_count_scope: Option<String>,
    #[serde(default)]
    pub commit_count_truncated: Option<bool>,
    #[serde(default)]
    pub repo_branch_count: Option<i64>,
    #[serde(default)]
    pub branch_count_truncated: Option<bool>,
    #[serde(default)]
    pub highlights: Vec<String>,
    #[serde(default)]
    pub next_steps: Vec<String>,
    #[serde(default)]
    pub notes: Vec<String>,
    /// 只有 deep 路径写 `docs`；浅更新缺席 ⇒ 不许显示「没改文档」。
    #[serde(default)]
    pub docs: Option<Vec<String>>,
}

impl JournalEntry {
    pub fn scope_badge(&self) -> ScopeBadge {
        journal_scope_badge(self)
    }

    pub fn is_deep(&self) -> bool {
        self.mode == "deep"
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct CommitTypeCount {
    #[serde(rename = "type", default)]
    pub type_: String,
    #[serde(default)]
    pub count: i64,
}

// ══════════════════════════════════════════════════════════════════════
// dashboard
// ══════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct DashboardData {
    #[serde(default)]
    pub projects: DashProjects,
    #[serde(default)]
    pub work: DashWork,
    #[serde(default)]
    pub languages: Vec<LangCount>,
    #[serde(default)]
    pub languages_truncated: Option<bool>,
    #[serde(default)]
    pub languages_top_cut: Option<bool>,
    #[serde(default)]
    pub languages_failed: i64,
    #[serde(default)]
    pub languages_failed_reasons: Vec<String>,
    #[serde(default)]
    pub milestones: DashMilestones,
    #[serde(default)]
    pub active_projects: Vec<ActiveProject>,
    #[serde(default)]
    pub fetched_at: String,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct DashProjects {
    #[serde(default)]
    pub total: i64,
    #[serde(default)]
    pub listed: i64,
    #[serde(default)]
    pub registered: i64,
    #[serde(default)]
    pub excluded_disabled: i64,
    #[serde(default)]
    pub failed: i64,
    #[serde(default)]
    pub dirty: i64,
    #[serde(default)]
    pub active7d: i64,
    #[serde(default)]
    pub active30d: i64,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct DashWork {
    #[serde(default)]
    pub branches: i64,
    #[serde(default)]
    pub merge_candidates: i64,
    #[serde(default)]
    pub untracked_files: i64,
    #[serde(default)]
    pub untracked_failed: i64,
    #[serde(default)]
    pub untracked_failed_reasons: Vec<String>,
    #[serde(default)]
    pub stashes: i64,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct LangCount {
    #[serde(default)]
    pub language: String,
    #[serde(default)]
    pub count: i64,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct DashMilestones {
    #[serde(default)]
    pub counts: MilestoneCounts,
    #[serde(default)]
    pub items: Vec<Milestone>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MilestoneCounts {
    #[serde(default)]
    pub open: i64,
    #[serde(default)]
    pub done: i64,
    #[serde(default)]
    pub dropped: i64,
    #[serde(default)]
    pub unknown: i64,
    #[serde(default)]
    pub other: i64,
    #[serde(default)]
    pub store_health: String,
    #[serde(default)]
    pub degraded: Option<bool>,
    #[serde(default)]
    pub read_count: i64,
    #[serde(default)]
    pub excluded_disabled: i64,
    #[serde(default)]
    pub orphaned: i64,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ActiveProject {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub last_commit_ago: String,
    #[serde(default)]
    pub headline: String,
}

// ══════════════════════════════════════════════════════════════════════
// milestone
// ══════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MilestoneList {
    #[serde(default)]
    pub milestones: Vec<Milestone>,
    #[serde(default)]
    pub store_health: Option<String>,
    #[serde(default)]
    pub read_count: i64,
    /// 孤儿是**另一种形状**（7 键，没有 projectName/tagName/commitsSince）。
    #[serde(default)]
    pub orphaned: Vec<OrphanedMilestone>,
    #[serde(default)]
    pub excluded_disabled: i64,
}

impl MilestoneList {
    /// 存储降级：storeHealth 不是 ok。`None`（缺键）也算不知道 ⇒ 降级。
    pub fn degraded(&self) -> bool {
        match self.store_health.as_deref() {
            Some("ok") => false,
            _ => true,
        }
    }

    pub fn health_label(&self) -> String {
        match self.store_health.as_deref() {
            Some("ok") => "正常".to_string(),
            Some(other) => other.to_string(),
            None => "读不出来".to_string(),
        }
    }
}

/// 只读出口的 17 键条目（`kernel.milestoneJson`）。
/// 没有 `id`（主键只出不进）；项目名键是 `projectName`，这里映射到 `project`
/// 以兼容 v0 页面 —— 语义仍是「项目名」。
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Milestone {
    #[serde(default)]
    pub project_id: String,
    #[serde(default)]
    pub name: String,
    /// 描述：缺键 = None（旧引擎或该路径不写）。空串与缺键在 UI 上都渲染成「无描述」。
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub target_date: String,
    #[serde(default)]
    pub tag: String,
    /// `open` / `done` / `dropped` / `unknown`；缺键 = None（无法核验）。
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub created_at: String,
    #[serde(default)]
    pub completed_at: String,
    /// 引擎键名是 `projectName`；v0 页面读的是「项目名」，这里直接映射。
    /// `alias = "project"` 兼容手写夹具与早期载荷（两种键不同时出现）。
    #[serde(default, rename = "projectName", alias = "project")]
    pub project: Option<String>,
    #[serde(default)]
    pub tag_name: String,
    #[serde(default)]
    pub tag_reached: Option<bool>,
    #[serde(default)]
    pub commits_since: i64,
    #[serde(default)]
    pub commits_since_readable: Option<bool>,
    #[serde(default)]
    pub days_to_target: i64,
    #[serde(default)]
    pub overdue: bool,
    #[serde(default)]
    pub git_readable: Option<bool>,
    #[serde(default)]
    pub unverified_reason: String,
}

impl Milestone {
    /// `unknown` / 缺键 = 无法核验。绝不并入「进行中」。
    pub fn status_word(&self) -> &'static str {
        match self.status.as_deref() {
            Some("done") => "已达成",
            Some("open") => "进行中",
            Some("dropped") => "已放弃",
            _ => "无法核验",
        }
    }

    pub fn status_tone(&self) -> Tone {
        match self.status.as_deref() {
            Some("done") => Tone::Ok,
            Some("open") => Tone::Accent,
            Some("dropped") => Tone::Idle,
            _ => Tone::Unknown,
        }
    }

    /// 描述的人话（None / 空串都是「无描述」）。
    pub fn description_text(&self) -> String {
        self.description
            .clone()
            .unwrap_or_default()
            .trim()
            .to_string()
    }

    /// 项目名（缺键时退回 projectId 的前缀，仍然不编造名字）。
    pub fn project_label(&self) -> String {
        self.project
            .clone()
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| self.project_id.clone())
    }

    /// 提交数：只有 `commitsSinceReadable` 为 true 才是一个可信数字。
    pub fn commits_since_reading(&self) -> Reading<i64> {
        match self.commits_since_readable {
            Some(false) | None => Reading::NotRead,
            Some(true) => read_i64(self.commits_since),
        }
    }

    /// 目标日期的人话（`daysToTarget` 负数 = 已逾期）。
    pub fn target_label(&self) -> String {
        if self.target_date.trim().is_empty() {
            return "无目标日期".to_string();
        }
        if self.overdue {
            format!("已逾期 {} 天", self.days_to_target.abs())
        } else if self.days_to_target >= 0 {
            format!("还剩 {} 天", self.days_to_target)
        } else {
            "目标日期读不出来".to_string()
        }
    }
}

/// 孤儿条目：所属项目已注销（没有 projectName / tagName 等 10 个键）。
/// **只读**：`milestone <action>` 收项目名，孤儿解析不出项目名。
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct OrphanedMilestone {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub project_id: Option<String>,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub target_date: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub orphaned: bool,
}

impl OrphanedMilestone {
    pub fn status_word(&self) -> &'static str {
        match self.status.as_str() {
            "done" => "已达成",
            "open" => "进行中",
            "dropped" => "已放弃",
            _ => "无法核验",
        }
    }
}

/// `milestone add` 回执里的**存储形状**（9 键，不是只读 17 键）。
/// 成功后不要把它当活条目渲染（它没有 projectName/tagName/commitsSince）。
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct StoredMilestone {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub project_id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub target_date: String,
    #[serde(default)]
    pub tag: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub created_at: String,
    #[serde(default)]
    pub completed_at: String,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MilestoneAddReceipt {
    #[serde(default)]
    pub project: String,
    #[serde(default)]
    pub milestone: Option<StoredMilestone>,
    #[serde(default)]
    pub created: bool,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MilestoneActionReceipt {
    #[serde(default)]
    pub project: String,
    #[serde(default)]
    pub milestone: String,
    #[serde(default)]
    pub requested: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub applied: bool,
}

impl MilestoneActionReceipt {
    /// 回执必须显示**实际生效的状态**，不是请求的状态。
    pub fn outcome_label(&self) -> String {
        if self.applied {
            format!("{} → {}", self.milestone, milestone_status_cn(&self.status))
        } else {
            format!(
                "{} 未生效（请求 {}，实际 {}）",
                self.milestone,
                milestone_status_cn(&self.requested),
                milestone_status_cn(&self.status)
            )
        }
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MilestoneRemoveReceipt {
    #[serde(default)]
    pub project: String,
    #[serde(default)]
    pub milestone: String,
    #[serde(default)]
    pub removed: bool,
}

pub fn milestone_status_cn(status: &str) -> &'static str {
    match status {
        "done" => "已达成",
        "open" => "进行中",
        "dropped" => "已放弃",
        "unknown" => "无法核验",
        _ => "未知状态",
    }
}

// ══════════════════════════════════════════════════════════════════════
// docs / journal
// ══════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct DocsPayload {
    /// 单项目时有；多项目平铺时缺键（各 doc 自带 project）。
    #[serde(default)]
    pub project: Option<String>,
    #[serde(default)]
    pub docs: Vec<DocContent>,
    #[serde(default)]
    pub unreadable: Vec<UnreadableDocs>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct DocContent {
    #[serde(default)]
    pub project: String,
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub content: String,
}

/// `unreadable` 的 `unreadable` 字段是**逗号分隔的文件名串**（引擎事实）。
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct UnreadableDocs {
    #[serde(default)]
    pub project: String,
    #[serde(default)]
    pub unreadable: String,
}

impl UnreadableDocs {
    pub fn files(&self) -> Vec<String> {
        self.unreadable
            .split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string)
            .collect()
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct JournalPayload {
    #[serde(default)]
    pub entries: Vec<JournalEntry>,
    #[serde(default)]
    pub limit: i64,
    #[serde(default)]
    pub branches: String,
    #[serde(default)]
    pub projects: i64,
    #[serde(default)]
    pub unparsable_lines: i64,
    /// `None` = 旧引擎没发这个键 ⇒ 不知道窗口外还有没有记录。
    #[serde(default)]
    pub window_exhausted: Option<bool>,
    /// 分支级耗尽：`none-in-window` / `window-full`。
    #[serde(default)]
    pub branch_window_exhausted: BTreeMap<String, String>,
}

impl JournalPayload {
    pub fn window_note(&self) -> Option<String> {
        if self.window_exhausted == Some(true) {
            Some(format!(
                "只加载了最近 {} 条（引擎窗口已满），更早的记录未加载",
                self.limit
            ))
        } else if self.window_exhausted.is_none() {
            Some("引擎未披露窗口是否耗尽：这不等于「已经全部加载」".to_string())
        } else {
            None
        }
    }

    pub fn branch_window_note(&self, branch: &str) -> Option<String> {
        match self.branch_window_exhausted.get(branch).map(String::as_str) {
            Some("none-in-window") => {
                Some("该分支的记录都在窗口之外：增大 limit 再查".to_string())
            }
            Some("window-full") => Some("窗口已满：该分支更早还有记录".to_string()),
            Some(other) => Some(format!("引擎披露的分支窗口状态：{other}")),
            None => None,
        }
    }

    pub fn unparsable_note(&self) -> Option<String> {
        if self.unparsable_lines < 0 {
            Some("坏行数读不出来".to_string())
        } else if self.unparsable_lines > 0 {
            Some(format!("{} 行日志无法解析，已跳过", self.unparsable_lines))
        } else {
            None
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// git
// ══════════════════════════════════════════════════════════════════════

/// 引擎所有 git 写操作的统一回执：`{op, ok, output, project}`。
/// `output` 是**字符串**：成功时是 git 的人话输出，`git status` 时是内层 JSON。
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct GitOpResponse {
    #[serde(default)]
    pub op: String,
    #[serde(default)]
    pub ok: bool,
    #[serde(default)]
    pub output: String,
    #[serde(default)]
    pub project: String,
}

/// `git status` 内层 JSON（从 `GitOpResponse.output` 二次解码）。
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct GitStatusPayload {
    #[serde(default)]
    pub ok: bool,
    /// 客户端二次解码失败时，这里放原因（`output` 可能是纯文本）。
    #[serde(default)]
    pub err: Option<String>,
    #[serde(default)]
    pub entries: Vec<GitEntry>,
    #[serde(default)]
    pub total: Option<i64>,
}

impl GitStatusPayload {
    pub fn total_count(&self) -> usize {
        match self.total {
            Some(n) if n >= 0 => n as usize,
            _ => self.entries.len(),
        }
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct GitEntry {
    /// porcelain 的两列状态（`" M"` / `"M "` / `"??"` …）。
    #[serde(default)]
    pub xy: String,
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub kind: String,
}

impl GitEntry {
    pub fn is_untracked(&self) -> bool {
        self.xy.starts_with("??")
    }
    /// 路径里带逗号时无法用 `--paths` 单独提交（引擎按逗号切分）。
    pub fn has_comma(&self) -> bool {
        self.file.contains(',')
    }
}

// ══════════════════════════════════════════════════════════════════════
// update / deep
// ══════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct UpdateReceipt {
    #[serde(default)]
    pub ok: bool,
    #[serde(default)]
    pub mode: String,
    #[serde(default)]
    pub project_id: String,
    #[serde(default)]
    pub project: String,
    #[serde(default)]
    pub provider: String,
    #[serde(default)]
    pub provider_label: String,
    // shallow 有；deep 没有（deep 的这几项在 journalEntry 里）
    #[serde(default)]
    pub branch_count: Option<i64>,
    #[serde(default)]
    pub repo_branch_count: Option<i64>,
    #[serde(default)]
    pub branch_count_truncated: Option<bool>,
    #[serde(default)]
    pub commit_count: Option<i64>,
    #[serde(default)]
    pub docs: Option<Vec<DocChange>>,
    #[serde(default)]
    pub journal_entry: Option<JournalEntry>,
    #[serde(default)]
    pub highlights: Option<Vec<String>>,
    #[serde(default)]
    pub at: Option<String>,
}

impl UpdateReceipt {
    pub fn is_deep(&self) -> bool {
        self.mode == "deep"
    }

    /// 更新事实的人话（逐条 doc 三态 + 提交口径）。
    pub fn facts(&self) -> Vec<String> {
        let mut out = Vec::new();
        if let Some(docs) = &self.docs {
            for d in docs {
                let what = if d.created {
                    "已创建"
                } else if d.changed {
                    "已更新"
                } else {
                    "无变化"
                };
                let backup = if d.backup.is_empty() {
                    String::new()
                } else {
                    format!(" · 备份 {}", d.backup)
                };
                out.push(format!("{} {}{}", d.file, what, backup));
            }
        }
        if let Some(je) = &self.journal_entry {
            out.push(format!("日志：{}", je.summary));
            let b = je.scope_badge();
            out.push(format!("提交：{}", b.label()));
        }
        out
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct DocChange {
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub changed: bool,
    #[serde(default)]
    pub created: bool,
    /// 空串 = 这次没有备份（新建 / 无变化），**不许自己拼路径**。
    #[serde(default)]
    pub backup: String,
}

/// 全项目 update/deep 的混合结果：成功项与失败项在同一个数组里。
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct MultiResults {
    #[serde(default)]
    pub results: Vec<serde_json::Value>,
    #[serde(default)]
    pub count: i64,
    #[serde(default)]
    pub failed: i64,
    #[serde(default)]
    pub succeeded: i64,
}

// ══════════════════════════════════════════════════════════════════════
// scan / registry / render
// ══════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ScanPayload {
    #[serde(default)]
    pub candidates: Vec<ScanCandidate>,
    #[serde(default)]
    pub found: i64,
    #[serde(default)]
    pub added: i64,
    #[serde(default)]
    pub existing: i64,
    #[serde(default)]
    pub dirs_visited: i64,
    /// 三轴覆盖度之一：目录数上限。
    #[serde(default)]
    pub truncated: Option<bool>,
    /// 三轴之二：深度上限（下面可能还有没看过的子目录）。
    #[serde(default)]
    pub depth_capped: Option<bool>,
    /// 三轴之三：读不到的目录（结果不完整，不是「没有」）。
    #[serde(default)]
    pub unreadable: Vec<String>,
    #[serde(default)]
    pub depth: i64,
}

impl ScanPayload {
    /// 三轴各自一句话；不合并成「结果可能不完整」。
    pub fn coverage_notes(&self) -> Vec<String> {
        let mut out = Vec::new();
        match self.truncated {
            Some(true) => out.push("目录数撞到引擎上限：本次**没有**覆盖全部范围".to_string()),
            None => out.push("引擎未披露目录数是否被截断".to_string()),
            Some(false) => {}
        }
        match self.depth_capped {
            Some(true) => out.push("深度撞到 --depth 上限：更深的子目录**没有被看过**".to_string()),
            None => out.push("引擎未披露深度是否被截断".to_string()),
            Some(false) => {}
        }
        if !self.unreadable.is_empty() {
            out.push(format!(
                "{} 个目录读不出来（权限/占用）：这些地方的结果不完整",
                self.unreadable.len()
            ));
        }
        out
    }

    pub fn complete(&self) -> bool {
        self.truncated == Some(false) && self.depth_capped == Some(false) && self.unreadable.is_empty()
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ScanCandidate {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub path: String,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub remote: String,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RegistryEntry {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub path: String,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub remote: String,
    #[serde(default)]
    pub added_at: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub disabled: bool,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RenderCheck {
    #[serde(default)]
    pub ok: bool,
    #[serde(default)]
    pub artifact: String,
    #[serde(default)]
    pub exists: bool,
    /// 不存在时是空串（引擎事实）。
    #[serde(default)]
    pub path: String,
}

// ══════════════════════════════════════════════════════════════════════
// graph confidence
// ══════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ConfidenceReport {
    #[serde(default)]
    pub root: String,
    #[serde(default)]
    pub score: i64,
    #[serde(default)]
    pub dimensions: Vec<Dimension>,
    #[serde(default)]
    pub penalty_by_file: Vec<FilePenalty>,
    #[serde(default)]
    pub findings: Vec<Finding>,
    #[serde(default)]
    pub ast_used: Option<bool>,
    #[serde(default)]
    pub ast_note: String,
    #[serde(default)]
    pub by_kind: Vec<KindCount>,
    #[serde(default)]
    pub capped_kind: Option<bool>,
    #[serde(default)]
    pub capped_total: Option<bool>,
    #[serde(default)]
    pub files_analyzed: i64,
    #[serde(default)]
    pub semantics: String,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Dimension {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub penalty: i64,
    #[serde(default)]
    pub findings: i64,
    #[serde(default)]
    pub score: i64,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct FilePenalty {
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub penalty: i64,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Finding {
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub symbol: String,
    #[serde(default)]
    pub evidence: String,
    #[serde(default)]
    pub line: i64,
    #[serde(default)]
    pub weight: i64,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct KindCount {
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub count: i64,
    #[serde(default)]
    pub weight: i64,
}

// ══════════════════════════════════════════════════════════════════════
// graph patchconf（单份 / 合并）
// ══════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Deserialize, Default)]
pub struct PatchReport {
    #[serde(default)]
    pub schema: String,
    #[serde(default)]
    pub overall: f64,
    /// S1–S10；`null` 是「词法层算不出来」，不是 0。
    #[serde(default)]
    pub signals: BTreeMap<String, Option<f64>>,
    #[serde(default)]
    pub entities: Vec<PatchEntity>,
    #[serde(default)]
    pub uncertain: Vec<Uncertain>,
    #[serde(default)]
    pub diagnostics: PatchDiag,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct PatchEntity {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub confidence: f64,
    #[serde(default)]
    pub line: i64,
    #[serde(default)]
    pub relations: Vec<PatchRelation>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct PatchRelation {
    #[serde(rename = "type", default)]
    pub type_: String,
    #[serde(default)]
    pub target: String,
    #[serde(default)]
    pub confidence: f64,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct Uncertain {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub issue: String,
    #[serde(default)]
    pub detail: String,
    #[serde(default)]
    pub candidates: Vec<String>,
    #[serde(default)]
    pub context_ref: Ref,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct Ref {
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub line: i64,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct PatchDiag {
    #[serde(default)]
    pub total_entities: i64,
    #[serde(default)]
    pub total_relations: i64,
    #[serde(default)]
    pub parse_errors: i64,
    #[serde(default)]
    pub patch_files: i64,
    #[serde(default)]
    pub added_lines: i64,
    #[serde(default)]
    pub null_signals: Vec<String>,
    #[serde(default)]
    pub null_signals_note: String,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct MergedReport {
    #[serde(default)]
    pub schema: String,
    #[serde(default)]
    pub overall: f64,
    #[serde(default)]
    pub signals: BTreeMap<String, Option<f64>>,
    #[serde(default)]
    pub entities: Vec<MergedEntity>,
    #[serde(default)]
    pub alerts: Vec<Alert>,
    #[serde(default)]
    pub sources: Sources,
    #[serde(default)]
    pub diagnostics: MergeDiag,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct MergedEntity {
    #[serde(default)]
    pub id: String,
    /// 合并结果里的疑点类别（实测是 `unresolved_call` 这类 issue 名）。
    #[serde(default)]
    pub issue: String,
    /// 疑点定位（合并报告里是 `context_ref`，与 `Uncertain` 同一形状）。
    #[serde(default)]
    pub context_ref: Ref,
    /// 算法侧实体可能带的字段（合并报告当前不写；保留形状以免未来漂移）。
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub confidence: f64,
    #[serde(default)]
    pub line: i64,
    #[serde(default)]
    pub relations: Vec<PatchRelation>,
    /// 来源：`algorithm` / `agent` / `deferred`。
    #[serde(default)]
    pub source: String,
    #[serde(default)]
    pub verdict: Option<String>,
    #[serde(default)]
    pub reason: Option<String>,
    #[serde(default)]
    pub evidence_refs: Option<Vec<String>>,
}

impl MergedEntity {
    /// 疑点的人话定位：优先 context_ref，其次 file:line。
    pub fn location(&self) -> String {
        let file = if !self.context_ref.file.is_empty() {
            &self.context_ref.file
        } else {
            &self.file
        };
        let line = if self.context_ref.line > 0 {
            self.context_ref.line
        } else {
            self.line
        };
        if file.is_empty() {
            "位置读不出来".to_string()
        } else if line > 0 {
            format!("{file}:{line}")
        } else {
            file.clone()
        }
    }

    pub fn label(&self) -> String {
        if !self.issue.is_empty() {
            self.issue.clone()
        } else if !self.kind.is_empty() {
            self.kind.clone()
        } else {
            "疑点".to_string()
        }
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct Alert {
    #[serde(default)]
    pub level: String,
    #[serde(rename = "type", default)]
    pub type_: String,
    #[serde(default)]
    pub detail: String,
}

impl Alert {
    pub fn level_class(&self) -> &'static str {
        match self.level.as_str() {
            "high" => "alert-high",
            "medium" => "alert-medium",
            _ => "alert-low",
        }
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct Sources {
    #[serde(default)]
    pub algorithm: bool,
    #[serde(default)]
    pub agent: bool,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct MergeDiag {
    #[serde(default)]
    pub certain_from_algorithm: i64,
    #[serde(default)]
    pub reviewed_by_agent: i64,
    #[serde(default)]
    pub deferred: i64,
}

// ══════════════════════════════════════════════════════════════════════
// context / tools（只读展示；AI 的 schema 以后走 MCP，不在本层）
// ══════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ContextPayload {
    #[serde(default)]
    pub scope: String,
    #[serde(default)]
    pub budget: i64,
    #[serde(default)]
    pub context: String,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ToolsManifest {
    #[serde(default)]
    pub tools: Vec<ToolDef>,
    #[serde(default)]
    pub note: Option<String>,
}

/// 能力清单：`params` 是逗号串，**没有类型与可选性**。
/// 给模型用的 schema 必须来自 `moongit mcp` 的 `tools/list`，不是这里。
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ToolDef {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub params: String,
}

/// MCP `tools/list` 的条目（`inputSchema` 有 type/required）。
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct McpTool {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub input_schema: serde_json::Value,
}

// ══════════════════════════════════════════════════════════════════════
// 派生纯函数（core；四个页面组共用，禁止各写一份）
// ══════════════════════════════════════════════════════════════════════

/// 状态色：err > stale > warn > ok。
/// 顺序即优先级 —— 「又脏又停滞」必须显示更紧急的那个。
pub fn status_tone(p: &Project) -> Tone {
    if p.error.is_some() || (p.store_health != "" && p.store_health != "ok") {
        return Tone::Err;
    }
    if p.stale_days_now() > 30 {
        return Tone::Stale;
    }
    if dirty_total_known(p) > 0 {
        return Tone::Warn;
    }
    // git 项目：dirty 缺键 / ok=false 是「脏度读不出来」，不是「干净」。
    // 原来这里直接落到 `Tone::Ok`，于是 dashboard 卡与项目页头显示绿点 +「干净」，
    // 而同一条数据在侧栏（`row_word`）与事实区（「脏度读不出来」）已经说了真话。
    if p.is_git() && matches!(p.dirty_state(), Reading::NotRead) {
        return Tone::Unknown;
    }
    Tone::Ok
}

pub fn status_word(p: &Project) -> &'static str {
    match status_tone(p) {
        Tone::Err => "读不出来",
        Tone::Stale => "停滞",
        Tone::Warn => "有未提交",
        Tone::Unknown => "无法核验",
        _ => "干净",
    }
}

fn dirty_total_known(p: &Project) -> i64 {
    match p.dirty_state() {
        Reading::Known(d) => d.total,
        Reading::NotRead => 0,
    }
}

impl Project {
    /// 停滞天数：优先当前分支的 `staleDays`，再退回最近提交日期。
    /// 两个都读不出来 ⇒ -1（不是 0 天）。
    pub fn stale_days_now(&self) -> i64 {
        if let Some(b) = self.current_branch_entry() {
            if b.stale_days >= 0 {
                return b.stale_days;
            }
        }
        match age_days(&self.last_commit_at) {
            Reading::Known(d) => d,
            Reading::NotRead => -1,
        }
    }

    /// 待处理：dirty.total>0 || untracked>0 || stash>0。
    /// **读不出来的脏度不算**（不能把「没读到」当成「有改动」）。
    pub fn is_pending(&self) -> bool {
        let dirty = matches!(self.dirty_state(), Reading::Known(d) if d.total > 0);
        let untracked = self.untracked_count.unwrap_or(0) > 0;
        let stash = self.stash_count.unwrap_or(0) > 0;
        dirty || untracked || stash
    }

    /// 看板列：Pending > Stale > Active > Other。
    pub fn board_column(&self) -> BoardColumn {
        if self.is_pending() {
            return BoardColumn::Pending;
        }
        let days = self.stale_days_now();
        if days > 30 {
            return BoardColumn::Stale;
        }
        if (0..=7).contains(&days) {
            return BoardColumn::Active;
        }
        BoardColumn::Other
    }
}

pub fn is_pending(p: &Project) -> bool {
    p.is_pending()
}

pub fn board_column(p: &Project) -> BoardColumn {
    p.board_column()
}

pub fn pending_count(ps: &[Project]) -> usize {
    ps.iter().filter(|p| p.is_pending()).count()
}

/// 里程碑完成率：`done / (done + open)`；分母 0 → None（不是 0%）。
/// `unknown` 单列，绝不当成 open 或 done。
pub fn milestone_rate(c: &MilestoneCounts) -> Option<f32> {
    let denom = c.done + c.open;
    if denom <= 0 {
        None
    } else {
        Some(c.done as f32 / denom as f32)
    }
}

/// 明细下界：`visible = milestones.len() + orphaned.len() + excludedDisabled`
/// 与引擎的 `readCount` 对账（**不是** `items.len() < readCount`）。
pub fn milestone_lower_bound(list: &MilestoneList) -> Option<Truncation> {
    if list.read_count < 0 {
        return None;
    }
    let visible = list.milestones.len() + list.orphaned.len() + list.excluded_disabled.max(0) as usize;
    if visible < list.read_count as usize {
        Some(Truncation {
            layer: "里程碑·明细",
            shown: visible,
            total: Some(list.read_count as usize),
            note: format!(
                "明细只是下界：引擎读到 {} 条，当前可对账 {} 条",
                list.read_count, visible
            ),
        })
    } else {
        None
    }
}

/// `YYYY-MM-DD`（或 RFC3339 前 10 字符）距今天数。
/// 解析不出来 ⇒ NotRead（**不是 0 天**）。
pub fn age_days(iso: &str) -> Reading<i64> {
    let date = match parse_ymd(iso) {
        Some(d) => d,
        None => return Reading::NotRead,
    };
    let today = today_utc();
    match days_from_civil(today.0, today.1, today.2) {
        Some(t0) => match days_from_civil(date.0, date.1, date.2) {
            Some(t1) => Reading::Known(t0 - t1),
            None => Reading::NotRead,
        },
        None => Reading::NotRead,
    }
}

/// `YYYY-MM-DD` 的客户端即时校验（新建里程碑表单用）。
/// 空串由调用方决定是否允许（可选的 target date）。
pub fn valid_date(s: &str) -> bool {
    parse_ymd(s).is_some()
}

fn parse_ymd(s: &str) -> Option<(i64, i64, i64)> {
    let s = s.trim();
    if s.len() < 10 {
        return None;
    }
    let bytes = s.as_bytes();
    if bytes[4] != b'-' || bytes[7] != b'-' {
        return None;
    }
    let y: i64 = s.get(0..4)?.parse().ok()?;
    let m: i64 = s.get(5..7)?.parse().ok()?;
    let d: i64 = s.get(8..10)?.parse().ok()?;
    if !(1..=12).contains(&m) || d < 1 || d > days_in_month(y, m) {
        return None;
    }
    Some((y, m, d))
}

fn days_in_month(y: i64, m: i64) -> i64 {    match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 {
                29
            } else {
                28
            }
        }
        _ => 0,
    }
}

fn today_utc() -> (i64, i64, i64) {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let days = secs.div_euclid(86_400);
    civil_from_days(days)
}

/// Howard Hinnant 的 days_from_civil：公历日期 → 1970-01-01 起的天数。
fn days_from_civil(y: i64, m: i64, d: i64) -> Option<i64> {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    Some(era * 146_097 + doe - 719_468)
}

fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// journal 数字的口径。绿色只留给真增量（`new`）。
pub fn journal_scope_badge(e: &JournalEntry) -> ScopeBadge {
    let n = match e.commit_count {
        Some(v) if v >= 0 => v,
        _ => return ScopeBadge::NotRead,
    };
    match e.commit_count_scope.as_deref() {
        Some("new") => ScopeBadge::New(n),
        Some("repoTotal") => ScopeBadge::RepoTotal(n),
        _ => ScopeBadge::UnknownScope(n),
    }
}

/// 语言的**三层**截断各自披露：
///   ① 引擎·文件采样（`languagesTruncated`）；
///   ② 引擎·语言条数（`languagesTopCut`）；
///   ③ 界面自己只画前 `shown` 条。
/// `shown` 必须是**界面上实际画出来的条数**（不是引擎条数）。
pub fn language_disclosures(d: &DashboardData, shown: usize) -> Vec<Truncation> {
    let mut out = Vec::new();
    match d.languages_truncated {
        Some(true) => out.push(Truncation {
            layer: "语言·文件采样",
            shown: d.languages.len(),
            total: None,
            note: "文件采样被引擎截断：上面的计数是已采样文件的分布".to_string(),
        }),
        None => out.push(Truncation {
            layer: "语言·文件采样",
            shown: d.languages.len(),
            total: None,
            note: "引擎未披露文件采样是否被截断".to_string(),
        }),
        Some(false) => {}
    }
    match d.languages_top_cut {
        Some(true) => out.push(Truncation {
            layer: "语言·条数",
            shown: d.languages.len(),
            total: None,
            note: "语言条数被引擎上限截断：还有语言没有列出来".to_string(),
        }),
        None => out.push(Truncation {
            layer: "语言·条数",
            shown: d.languages.len(),
            total: None,
            note: "引擎未披露语言条数是否被截断".to_string(),
        }),
        Some(false) => {}
    }
    if shown < d.languages.len() {
        out.push(Truncation {
            layer: "语言·界面显示",
            shown,
            total: Some(d.languages.len()),
            note: format!("界面只显示前 {} 条，共 {} 条", shown, d.languages.len()),
        });
    }
    out
}

/// 脏度数字的人话：`-1` = 读不出来，不是 0。
pub fn dirty_label(v: i64) -> String {
    if v < 0 {
        "读不出来".to_string()
    } else {
        v.to_string()
    }
}

/// journal 提交数：数字 + 口径一起读，避免两个同名不同义的绿数字。
pub fn commit_count_label(v: i64, scope: Option<&str>) -> String {
    if v < 0 {
        return "提交数读不出来".to_string();
    }
    match scope {
        Some("new") => format!("+{v} 本轮新增"),
        Some("repoTotal") => format!("累计 {v}"),
        _ => format!("口径未知 {v}"),
    }
}

/// `2026-10-01T00:05:35+08:00` → `10-01 00:05`。非法输入原样返回（不 panic）。
pub fn short_iso(s: &str) -> String {
    if s.len() >= 16 {
        if let (Some(date), Some(time)) = (s.get(5..10), s.get(11..16)) {
            if s.as_bytes().get(10) == Some(&b'T') {
                return format!("{date} {time}");
            }
        }
    }
    s.to_string()
}

/// 相对时间（秒级）。仅用于「上次刷新」这类本机时刻。
pub fn human_ago(t: Instant) -> String {
    let secs = t.elapsed().as_secs();
    if secs < 5 {
        "刚刚".to_string()
    } else if secs < 60 {
        format!("{secs} 秒前")
    } else if secs < 3_600 {
        format!("{} 分钟前", secs / 60)
    } else if secs < 86_400 {
        format!("{} 小时前", secs / 3_600)
    } else {
        format!("{} 天前", secs / 86_400)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn negative_counters_are_not_read() {
        assert_eq!(read_i64(-1), Reading::NotRead);
        assert_eq!(read_i64(0), Reading::Known(0));
        assert_eq!(read_opt_i64(None), Reading::NotRead);
        assert_eq!(read_opt_i64(Some(-3)), Reading::NotRead);
        assert_eq!(dirty_label(-1), "读不出来");
        assert_eq!(dirty_label(0), "0");
    }

    #[test]
    fn commit_count_scope_is_explicit() {
        let mk = |n: i64, scope: Option<&str>| JournalEntry {
            commit_count: Some(n),
            commit_count_scope: scope.map(str::to_string),
            ..Default::default()
        };
        assert_eq!(journal_scope_badge(&mk(3, Some("new"))), ScopeBadge::New(3));
        assert_eq!(
            journal_scope_badge(&mk(3, Some("repoTotal"))),
            ScopeBadge::RepoTotal(3)
        );
        assert_eq!(journal_scope_badge(&mk(3, None)), ScopeBadge::UnknownScope(3));
        assert_eq!(journal_scope_badge(&mk(-1, Some("new"))), ScopeBadge::NotRead);
        assert_eq!(commit_count_label(3, None), "口径未知 3");
        assert_eq!(commit_count_label(-1, Some("new")), "提交数读不出来");
    }

    #[test]
    fn failed_project_shape_is_not_clean() {
        // 实测失败项目：dirty/overall 是 {}，计数是 -1，仍有完整形状。
        let p: Project = serde_json::from_str(
            r#"{
                "name":"x","path":"/nope","kind":"dir",
                "error":"路径不存在","dirty":{},"overall":{},
                "commitCount":-1,"userDirtyCount":-1,"untrackedCount":-1,
                "stashCount":-1,"repoBranchCount":-1,"journalUnparsableLines":-1
            }"#,
        )
        .unwrap();
        assert_eq!(p.dirty_state(), Reading::NotRead);
        assert_eq!(p.overall_state(), Reading::NotRead);
        assert_eq!(p.commit_count, Some(-1));
        assert_eq!(status_tone(&p), Tone::Err);
        assert!(!p.is_pending(), "读不出来的脏度不能算待处理");
        assert_eq!(p.board_column(), BoardColumn::Other);
    }

    #[test]
    fn git_project_with_unread_dirty_is_unknown_not_clean() {
        // git 项目、无 error、dirty 缺键：这是「读不出来」，不是「干净」。
        let p = Project {
            kind: "git".to_string(),
            ..Default::default()
        };
        assert_eq!(p.dirty_state(), Reading::NotRead);
        assert_eq!(status_tone(&p), Tone::Unknown);
        assert_eq!(status_word(&p), "无法核验");

        // 非 git 项目没有 git 脏度这个概念，保持原判定（不把每个非 git 项目都说成无法核验）。
        let nongit = Project {
            kind: "dir".to_string(),
            ..Default::default()
        };
        assert_eq!(status_tone(&nongit), Tone::Ok);
    }

    #[test]
    fn pending_beats_stale() {
        let p = Project {
            dirty: Some(Dirty {
                ok: true,
                total: 2,
                ..Default::default()
            }),
            branches: vec![Branch {
                is_current: true,
                stale_days: 90,
                ..Default::default()
            }],
            ..Default::default()
        };
        assert!(p.is_pending());
        assert_eq!(p.board_column(), BoardColumn::Pending);

        let stale = Project {
            dirty: Some(Dirty {
                ok: true,
                total: 0,
                ..Default::default()
            }),
            branches: vec![Branch {
                is_current: true,
                stale_days: 90,
                ..Default::default()
            }],
            ..Default::default()
        };
        assert_eq!(stale.board_column(), BoardColumn::Stale);
    }

    #[test]
    fn milestone_rate_denominator_excludes_unknown() {
        let c = MilestoneCounts {
            done: 2,
            open: 1,
            unknown: 9,
            dropped: 4,
            ..Default::default()
        };
        let r = milestone_rate(&c).unwrap();
        assert!((r - 2.0 / 3.0).abs() < 1e-6);
        assert_eq!(milestone_rate(&MilestoneCounts::default()), None);
    }

    #[test]
    fn milestone_lower_bound_reconciles_with_read_count() {
        let list = MilestoneList {
            milestones: vec![Milestone::default()],
            orphaned: vec![OrphanedMilestone::default()],
            excluded_disabled: 1,
            read_count: 3,
            ..Default::default()
        };
        assert!(milestone_lower_bound(&list).is_none(), "visible == readCount");
        let list2 = MilestoneList {
            read_count: 5,
            ..list
        };
        let t = milestone_lower_bound(&list2).unwrap();
        assert_eq!(t.shown, 3);
        assert_eq!(t.total, Some(5));
    }

    #[test]
    fn milestone_readonly_shape_uses_project_name_and_option_status() {
        let m: Milestone = serde_json::from_str(
            r#"{
                "projectId":"p1","name":"n","description":"d","targetDate":"2026-12-31",
                "tag":"v1","status":"open","createdAt":"","completedAt":"",
                "projectName":"proj","tagName":"v1","tagReached":false,
                "commitsSince":2,"commitsSinceReadable":true,"daysToTarget":10,
                "overdue":false,"gitReadable":true,"unverifiedReason":""
            }"#,
        )
        .unwrap();
        assert_eq!(m.project.as_deref(), Some("proj"));
        assert_eq!(m.status.as_deref(), Some("open"));
        assert_eq!(m.description.as_deref(), Some("d"));
        assert_eq!(m.commits_since_reading(), Reading::Known(2));

        let unknown = Milestone {
            status: None,
            commits_since_readable: None,
            ..Default::default()
        };
        assert_eq!(unknown.status_word(), "无法核验");
        assert_eq!(unknown.commits_since_reading(), Reading::NotRead);
    }

    #[test]
    fn orphan_shape_has_no_project_name() {
        let o: OrphanedMilestone = serde_json::from_str(
            r#"{
                "id":"m1","projectId":"p1","name":"n","description":"d",
                "targetDate":"2026-01-01","status":"open","orphaned":true
            }"#,
        )
        .unwrap();
        assert!(o.orphaned);
        assert_eq!(o.project_id.as_deref(), Some("p1"));
    }

    #[test]
    fn dates_are_validated_not_guessed() {
        assert!(valid_date("2026-12-31"));
        assert!(valid_date("2024-02-29"));
        assert!(!valid_date("2026-02-29"));
        assert!(!valid_date("2026-13-01"));
        assert!(!valid_date(""));
        assert_eq!(age_days("not-a-date"), Reading::NotRead);
        assert!(matches!(age_days("1970-01-01"), Reading::Known(n) if n > 10_000));
    }
}
