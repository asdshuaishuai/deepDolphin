// models.rs — 引擎 JSON 契约的 Rust 模型（只取 UI 用得上的子集）。
//
// 纪律（AGENTS.md 契约条）：引擎键名就是契约——这里只做**只读投影**，
// 缺键一律 Option 并如实渲染「读不出来」，绝不把缺席当默认值 0。

// 契约镜像：部分字段当前 UI 未消费，但保留形状（引擎契约的文档价值）。
#![allow(dead_code)]

use serde::Deserialize;

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct StatusEnvelope {
    #[serde(default)]
    pub projects: Vec<Project>,
    #[serde(default)]
    pub summary: Summary,
    #[serde(default)]
    pub language: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Summary {
    #[serde(default)]
    pub project_count: i64,
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
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Project {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub path: String,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub headline: Option<String>,
    #[serde(default)]
    pub current_branch: Option<String>,
    #[serde(default)]
    pub default_branch: Option<String>,
    #[serde(default)]
    pub user_dirty_count: Option<i64>,
    #[serde(default)]
    pub untracked_count: Option<i64>,
    #[serde(default)]
    pub stash_count: Option<i64>,
    #[serde(default)]
    pub commit_count: Option<i64>,
    #[serde(default)]
    pub last_commit_ago: Option<String>,
    #[serde(default)]
    pub warnings: Option<Vec<String>>,
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub docs: Option<Vec<DocEntry>>,
}

impl Project {
    pub fn is_git(&self) -> bool {
        self.kind == "git"
    }
    pub fn is_readable(&self) -> bool {
        self.error.is_none()
    }
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
pub struct MilestoneList {
    #[serde(default)]
    pub milestones: Vec<Milestone>,
    #[serde(default)]
    pub store_health: Option<String>,
    #[serde(default)]
    pub read_count: i64,
    #[serde(default)]
    pub orphaned: Vec<Milestone>,
    #[serde(default)]
    pub excluded_disabled: i64,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Milestone {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub target_date: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub project: Option<String>,
    #[serde(default)]
    pub project_id: Option<String>,
    #[serde(default)]
    pub orphaned: bool,
    #[serde(default)]
    pub tag_name: Option<String>,
    #[serde(default)]
    pub unverified_reason: Option<String>,
}

impl Milestone {
    /// 状态词。unknown = 「读不出来」——绝不渲染成「进行中」。
    pub fn status_word(&self) -> &'static str {
        match self.status.as_deref() {
            Some("done") => "已达成",
            Some("open") => "进行中",
            Some("dropped") => "已放弃",
            _ => "无法核验",
        }
    }
}
