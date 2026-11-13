// 契约面：本阶段先冻结 API，页面的下一阶段消费者尚未落地；未使用不是缺陷。
#![allow(dead_code)]

// engine.rs — moonGit 引擎桥（CLI 子进程，与既有 macOS 客户端同一条传输层）。
//
// 契约（AGENTS.md「传输层哲学」）：只在本机进程之间通信 —— spawn
// `moongit <命令> --json`，读 stdout 的 JSON。没有 HTTP、没有 FFI、没有第二份事实来源。
//
// 【本层的三条硬规则】
//   1. **载荷优先于退出码**：`milestone list` 在存储降级时是 rc=1 + 合法 payload，
//      `git commit` 失败是 rc=1 + `{op,ok:false,output}`。先解析 stdout，
//      只有 stdout 不是 JSON 才把退出码当原因。
//   2. **失败原因来自载荷**：message → error → output → stderr → 退出码。
//      判据与引擎 `hasErrorOrCode` 同规则：**有 `ok` 键 ⇒ 不是失败**
//      （git / results 形状由调用方判），有 `results` / `projects` 的聚合信封
//      也不由本层判失败 —— 它们内部逐项带错误。
//   3. **超时 = kill + wait**：不是「不管了」。读 90s / 写 1800s / git 180s /
//      scan 600s / graph 300s（PLAN §8）。
//
// 【同步调用】BUI 0.5 没有 spawn/定时器，本分支的所有命令在调用线程上阻塞完成；
// 首屏数据在开窗前预取（见 app::AppState::bootstrap）。取消/后台 Job 需要
// 线程 + UiSender，属于下一阶段；本层已经把「超时就杀进程」做好，
// 因为那是**进程**层面的事，不依赖 UI 运行时。

use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::de::DeserializeOwned;
use serde_json::Value;

// ── 超时（PLAN §8 的同一组数字）────────────────────────────────────────
pub const READ_TIMEOUT: Duration = Duration::from_secs(90);
pub const WRITE_TIMEOUT: Duration = Duration::from_secs(1_800);
pub const GIT_TIMEOUT: Duration = Duration::from_secs(180);
pub const SCAN_TIMEOUT: Duration = Duration::from_secs(600);
pub const GRAPH_TIMEOUT: Duration = Duration::from_secs(300);

// ══════════════════════════════════════════════════════════════════════
// 错误
// ══════════════════════════════════════════════════════════════════════

/// 引擎层的错误。`user_message()` 是**唯一**给用户看的出口：
/// 中文、可执行、URL 只保留 host:port（凭据永不进错误文本）。
#[derive(Debug, Clone)]
pub enum EngineError {
    NotFound {
        bin: String,
    },
    Spawn {
        bin: String,
        message: String,
    },
    Exit {
        code: i32,
        message: String,
        details: Option<String>,
        stderr: String,
    },
    Json {
        command: String,
        message: String,
        raw: String,
    },
    Cancelled,
    Timeout {
        secs: u64,
        command: String,
    },
    Io(String),
}

impl EngineError {
    pub fn user_message(&self) -> String {
        match self {
            EngineError::NotFound { bin } => format!(
                "找不到引擎（{bin}）。请安装 moonGit，或用 MOONGIT_BIN 指向引擎可执行文件。"
            ),
            EngineError::Spawn { bin, message } => {
                format!("无法启动引擎（{bin}）：{}", sanitize(message))
            }
            EngineError::Exit {
                code,
                message,
                details,
                stderr,
            } => {
                let mut text = if message.trim().is_empty() {
                    format!("引擎退出码 {code}（引擎没有给出原因）")
                } else {
                    sanitize(message)
                };
                if let Some(d) = details {
                    let d = sanitize(d);
                    if !d.trim().is_empty() && !text.contains(&d) {
                        text.push_str("；");
                        text.push_str(&d);
                    }
                }
                let s = sanitize(stderr);
                if message.trim().is_empty() && !s.trim().is_empty() {
                    text.push_str("；stderr：");
                    text.push_str(&s);
                }
                text
            }
            EngineError::Json {
                command,
                message,
                raw,
            } => format!(
                "引擎输出不是预期 JSON（{}）：{}；原文前 200 字符：{}",
                command,
                sanitize(message),
                sanitize(&truncate_chars(raw, 200))
            ),
            EngineError::Cancelled => "已停止（用户取消）".to_string(),
            EngineError::Timeout { secs, command } => {
                format!("引擎超时（>{secs}s），已终止：{command}")
            }
            EngineError::Io(message) => format!("本机 I/O 错误：{}", sanitize(message)),
        }
    }

    pub fn is_cancelled(&self) -> bool {
        matches!(self, EngineError::Cancelled)
    }

    pub fn is_timeout(&self) -> bool {
        matches!(self, EngineError::Timeout { .. })
    }
}

impl std::fmt::Display for EngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.user_message())
    }
}

impl std::error::Error for EngineError {}

/// 消息里的 URL 只保留 `scheme://host:port/…`。
/// 有些服务把 key 放在 userinfo 或 query 里，而错误文本会进界面/日志/通知 ——
/// 泄出去无法收回。解析不出来就整段隐藏（宁可少说）。
pub fn redact_url(s: &str) -> String {
    let Some(pos) = s.find("://") else {
        return "(地址已隐藏)".to_string();
    };
    let scheme = &s[..pos];
    if scheme.is_empty() {
        return "(地址已隐藏)".to_string();
    }
    let rest = &s[pos + 3..];
    let authority_end = rest
        .find(|c| c == '/' || c == '?' || c == '#')
        .unwrap_or(rest.len());
    let authority = &rest[..authority_end];
    let host_port = match authority.rsplit_once('@') {
        Some((_, hp)) => hp,
        None => authority,
    };
    if host_port.is_empty() {
        return "(地址已隐藏)".to_string();
    }
    if authority_end < rest.len() {
        format!("{scheme}://{host_port}/…")
    } else {
        format!("{scheme}://{host_port}")
    }
}

/// 按空白切词，把含 `://` 的词脱敏后拼回。
fn sanitize(msg: &str) -> String {
    msg.split_whitespace()
        .map(|tok| {
            if tok.contains("://") {
                redact_url(tok)
            } else {
                tok.to_string()
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn truncate_chars(s: &str, max: usize) -> String {
    let mut out = String::new();
    for (i, ch) in s.chars().enumerate() {
        if i >= max {
            out.push('…');
            break;
        }
        out.push(ch);
    }
    out
}

// ══════════════════════════════════════════════════════════════════════
// 结果
// ══════════════════════════════════════════════════════════════════════

/// 一条子进程的原始结果。`ok` 是**退出码**语义，不是「命令成功」语义：
/// 引擎在降级时可能 rc=1 但 stdout 是合法 payload（由 `parse` 裁决）。
#[derive(Debug, Clone, Default)]
pub struct JobResult {
    pub ok: bool,
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
    pub timed_out: bool,
    pub duration_ms: u64,
}

impl JobResult {
    pub fn is_success(&self) -> bool {
        self.ok && !self.timed_out
    }
}

/// 全项目 update/deep 的**两种形状**（实测）：
///   · 注册表里只有一个项目时，引擎直接返回单个 `UpdateReceipt`；
///   · 两个及以上时返回 `{results,count,succeeded,failed}`。
/// 调用方必须两种都处理 —— 把单回执按 MultiResults 解会得到
/// `succeeded: 0`，把更新成功报成「0 个项目成功」。
#[derive(Debug, Clone)]
pub enum UpdateOutcome {
    Single(crate::models::UpdateReceipt),
    Multi(crate::models::MultiResults),
}

impl UpdateOutcome {
    pub fn failed(&self) -> i64 {
        match self {
            UpdateOutcome::Single(r) => {
                if r.ok {
                    0
                } else {
                    1
                }
            }
            UpdateOutcome::Multi(m) => m.failed,
        }
    }
    pub fn succeeded(&self) -> i64 {
        match self {
            UpdateOutcome::Single(r) => {
                if r.ok {
                    1
                } else {
                    0
                }
            }
            UpdateOutcome::Multi(m) => m.succeeded,
        }
    }
    pub fn count(&self) -> i64 {
        match self {
            UpdateOutcome::Single(_) => 1,
            UpdateOutcome::Multi(m) => m.count,
        }
    }
    pub fn single(&self) -> Option<&crate::models::UpdateReceipt> {
        match self {
            UpdateOutcome::Single(r) => Some(r),
            _ => None,
        }
    }
    pub fn multi(&self) -> Option<&crate::models::MultiResults> {
        match self {
            UpdateOutcome::Multi(m) => Some(m),
            _ => None,
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// 命令枚举
// ══════════════════════════════════════════════════════════════════════

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GitOp {
    Pull,
    Push,
    Fetch,
    Stash,
    Unstash,
    Commit,
}

impl GitOp {
    pub fn as_str(&self) -> &'static str {
        match self {
            GitOp::Pull => "pull",
            GitOp::Push => "push",
            GitOp::Fetch => "fetch",
            GitOp::Stash => "stash",
            GitOp::Unstash => "unstash",
            GitOp::Commit => "commit",
        }
    }
    pub fn label(&self) -> &'static str {
        match self {
            GitOp::Pull => "拉取",
            GitOp::Push => "推送",
            GitOp::Fetch => "抓取",
            GitOp::Stash => "暂存",
            GitOp::Unstash => "恢复",
            GitOp::Commit => "提交",
        }
    }
    /// 会改仓库的操作。读侧（status/fetch）不在白名单菜单里单独暴露。
    pub fn is_write(&self) -> bool {
        !matches!(self, GitOp::Fetch)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MilestoneOp {
    Done,
    Reopen,
    Drop,
}

impl MilestoneOp {
    pub fn as_str(&self) -> &'static str {
        match self {
            MilestoneOp::Done => "done",
            MilestoneOp::Reopen => "reopen",
            MilestoneOp::Drop => "drop",
        }
    }
    pub fn label(&self) -> &'static str {
        match self {
            MilestoneOp::Done => "达成",
            MilestoneOp::Reopen => "重开",
            MilestoneOp::Drop => "放弃",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Artifact {
    Index,
    Arch,
}

impl Artifact {
    pub fn as_str(&self) -> &'static str {
        match self {
            Artifact::Index => "index",
            Artifact::Arch => "arch",
        }
    }
    pub fn label(&self) -> &'static str {
        match self {
            Artifact::Index => "代码图谱 · 置信度热力图",
            Artifact::Arch => "技术架构图",
        }
    }
    pub fn description(&self) -> &'static str {
        match self {
            Artifact::Index => "列表/热力图双模式 · 关系连线 · 下钻",
            Artifact::Arch => "分层泳道 + 职责视图 · 违规/环治理信号",
        }
    }
    pub fn all() -> [Artifact; 2] {
        [Artifact::Index, Artifact::Arch]
    }
}

// ══════════════════════════════════════════════════════════════════════
// Engine
// ══════════════════════════════════════════════════════════════════════

/// 引擎桥。`Clone` 只复制二进制路径与共享的告警缓冲（没有连接要复用）。
#[derive(Debug, Clone)]
pub struct Engine {
    pub bin: String,
    /// 读命令 stderr 的告警（不是失败）。同步调用下用共享缓冲，
    /// AppState 每次动作后 `drain_warnings()` 取走并去重展示。
    warnings: Arc<Mutex<Vec<String>>>,
    /// 可选取消旗标（后台 Job 用）：置位后子进程在 ~25ms 内被 kill。
    /// `None` = 不可取消（首屏同步预取等）。
    cancel: Option<Arc<AtomicBool>>,
}

impl Default for Engine {
    fn default() -> Self {
        Self::new()
    }
}

impl Engine {
    /// 发现顺序（与既有 Swift 客户端同一条纪律）：
    ///   MOONGIT_BIN / DEEPGIT_BIN → 可执行文件旁的 moongit/deepgit →
    ///   PATH 上的 moongit → deepgit。
    /// 引擎命令名 2026-10-03 从 deepgit 改为 moongit，老机器上仍可能只有旧名。
    pub fn new() -> Engine {
        Engine {
            bin: discover_bin(),
            warnings: Arc::new(Mutex::new(Vec::new())),
            cancel: None,
        }
    }

    pub fn with_bin(bin: impl Into<String>) -> Engine {
        Engine {
            bin: bin.into(),
            warnings: Arc::new(Mutex::new(Vec::new())),
            cancel: None,
        }
    }

    /// 返回一个**可取消**的克隆：同一条二进制、同一份告警缓冲，
    /// 外加一个取消旗标。后台 Job 用它；置位后正在跑的子进程会被 kill。
    pub fn with_cancel(mut self, flag: Arc<AtomicBool>) -> Engine {
        self.cancel = Some(flag);
        self
    }

    pub fn exists(&self) -> bool {
        Path::new(&self.bin).is_file()
    }

    /// 引擎短名（侧栏页脚用；完整路径会顶出 260px）。
    pub fn short_name(&self) -> String {
        let base = self
            .bin
            .rsplit(['/', '\\'])
            .next()
            .filter(|s| !s.is_empty())
            .unwrap_or(&self.bin);
        base.strip_suffix(".exe").unwrap_or(base).to_string()
    }

    /// 取走并清空告警缓冲（去重、保序、上限 100 行）。
    pub fn drain_warnings(&self) -> Vec<String> {
        let mut guard = match self.warnings.lock() {
            Ok(g) => g,
            Err(poisoned) => poisoned.into_inner(),
        };
        std::mem::take(&mut *guard)
    }

    fn note_stderr(&self, stderr: &str) {
        let mut lines: Vec<String> = stderr
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            // 扫描/更新的进度行不是告警
            .filter(|l| !l.starts_with('›'))
            .map(str::to_string)
            .collect();
        if lines.is_empty() {
            return;
        }
        let mut guard = match self.warnings.lock() {
            Ok(g) => g,
            Err(poisoned) => poisoned.into_inner(),
        };
        for line in lines.drain(..) {
            if !guard.contains(&line) {
                guard.push(line);
            }
        }
        if guard.len() > 100 {
            let cut = guard.len() - 100;
            guard.drain(0..cut);
        }
    }

    // ── 原始执行 ────────────────────────────────────────────────────

    fn run_raw(&self, args: &[&str], timeout: Duration) -> Result<JobResult, EngineError> {
        let r = spawn_and_wait(&self.bin, args, timeout, self.cancel.as_deref()).map_err(|e| match e {
            EngineError::Spawn { message, .. }
                if message.contains("not found")
                    || message.contains("No such file")
                    || message.contains("cannot find") =>
            {
                EngineError::NotFound {
                    bin: self.bin.clone(),
                }
            }
            other => other,
        })?;
        if !r.stderr.trim().is_empty() {
            self.note_stderr(&r.stderr);
        }
        Ok(r)
    }

    /// 跑一条命令并做「载荷优先」裁决：
    ///   · stdout 是 JSON 且不是失败信封 ⇒ Ok（即使 rc≠0，如降级 milestone list）；
    ///   · stdout 是 JSON 但是 `{error:true,...}` / `{code,...}` / `{message,...}`
    ///     ⇒ Err(Exit)，message 取载荷；
    ///   · stdout 不是 JSON 且 rc≠0 ⇒ Err(Exit)，message 取 stderr → stdout → 退出码；
    ///   · 超时 ⇒ Err(Timeout)。
    pub fn run_checked(&self, args: &[&str], timeout: Duration) -> Result<JobResult, EngineError> {
        let r = self.run_raw(args, timeout)?;
        if r.timed_out {
            return Err(EngineError::Timeout {
                secs: timeout.as_secs(),
                command: command_label(args),
            });
        }
        if let Ok(v) = serde_json::from_str::<Value>(r.stdout.trim()) {
            if let Some(msg) = failure_message(&v) {
                return Err(EngineError::Exit {
                    code: r.code,
                    message: msg,
                    details: None,
                    stderr: r.stderr.clone(),
                });
            }
            return Ok(r);
        }
        if !r.ok {
            return Err(EngineError::Exit {
                code: r.code,
                message: best_failure_text(&r),
                details: None,
                stderr: r.stderr.clone(),
            });
        }
        Ok(r)
    }

    fn read_json<T: DeserializeOwned>(
        &self,
        cmd: &str,
        args: &[&str],
        timeout: Duration,
    ) -> Result<T, EngineError> {
        let r = self.run_checked(args, timeout)?;
        parse(cmd, &r)
    }

    // ── 读命令 ──────────────────────────────────────────────────────

    pub fn status(&self, project: Option<&str>) -> Result<crate::models::StatusEnvelope, EngineError> {
        let mut args = vec!["status"];
        if let Some(p) = project {
            args.push(p);
        }
        args.push("--json");
        args.push("--quiet");
        self.read_json("status", &args, READ_TIMEOUT)
    }

    pub fn dashboard(&self) -> Result<crate::models::DashboardData, EngineError> {
        self.read_json("dashboard", &["dashboard", "--json"], READ_TIMEOUT)
    }

    /// `milestone list` 在存储降级时 **rc=1 但 stdout 是合法 payload**。
    /// `run_checked` 的载荷优先规则让这里照常解出条目；降级由 `storeHealth` 披露。
    pub fn milestone_list(
        &self,
        project: Option<&str>,
    ) -> Result<crate::models::MilestoneList, EngineError> {
        let mut args = vec!["milestone", "list"];
        if let Some(p) = project {
            args.push(p);
        }
        args.push("--json");
        self.read_json("milestone list", &args, READ_TIMEOUT)
    }

    pub fn docs(&self, project: &str) -> Result<crate::models::DocsPayload, EngineError> {
        self.read_json("docs", &["docs", project, "--json"], READ_TIMEOUT)
    }

    pub fn journal(
        &self,
        project: &str,
        branch: Option<&str>,
        limit: Option<u32>,
    ) -> Result<crate::models::JournalPayload, EngineError> {
        let limit_text = limit.map(|n| n.to_string());
        let mut args = vec!["journal", project];
        if let Some(b) = branch {
            args.push("--branch");
            args.push(b);
        }
        if let Some(n) = limit_text.as_deref() {
            args.push("--limit");
            args.push(n);
        }
        args.push("--json");
        self.read_json("journal", &args, READ_TIMEOUT)
    }

    pub fn list_registry(&self) -> Result<Vec<crate::models::RegistryEntry>, EngineError> {
        // ⚠️ `list --json` 是裸数组，不是 envelope。
        self.read_json("list", &["list", "--json"], READ_TIMEOUT)
    }

    pub fn render_check(
        &self,
        artifact: Artifact,
        project: &str,
    ) -> Result<crate::models::RenderCheck, EngineError> {
        self.read_json(
            "render check",
            &["render", "check", artifact.as_str(), project, "--json"],
            READ_TIMEOUT,
        )
    }

    /// 裸 JSON 字符串（`config get language --json` → `"zh"`）。
    pub fn config_get_language(&self) -> Result<Option<String>, EngineError> {
        let r = self.run_checked(
            &["config", "get", "language", "--json"],
            READ_TIMEOUT,
        )?;
        let v: Value = serde_json::from_str(r.stdout.trim()).map_err(|e| EngineError::Json {
            command: "config get language".to_string(),
            message: e.to_string(),
            raw: r.stdout.clone(),
        })?;
        match v {
            Value::String(s) if !s.is_empty() => Ok(Some(s)),
            Value::Null => Ok(None),
            other => Ok(Some(other.to_string().trim_matches('"').to_string())),
        }
    }

    pub fn tools(&self) -> Result<crate::models::ToolsManifest, EngineError> {
        self.read_json("tools", &["tools", "--json"], READ_TIMEOUT)
    }

    pub fn context(
        &self,
        project: Option<&str>,
        budget: u32,
    ) -> Result<crate::models::ContextPayload, EngineError> {
        let budget_text = budget.max(500).to_string(); // 引擎会把预算夹到最小 500
        let mut args = vec!["context"];
        if let Some(p) = project {
            args.push(p);
        }
        args.extend(["--budget", budget_text.as_str(), "--json"]);
        self.read_json("context", &args, READ_TIMEOUT)
    }

    // ── 写命令（返回原始结果，由调用方按形状解析）──────────────────

    fn run_text(&self, args: &[&str], timeout: Duration) -> Result<JobResult, EngineError> {
        self.run_checked(args, timeout)
    }

    /// 单项目浅/深更新。
    pub fn update_project(
        &self,
        project: &str,
        deep: bool,
    ) -> Result<crate::models::UpdateReceipt, EngineError> {
        let op = if deep { "deep" } else { "update" };
        let args = [op, project, "--json", "--quiet"];
        self.read_json(op, &args, WRITE_TIMEOUT)
    }

    /// 全项目更新：成功项与失败项混在同一个 `results` 数组里。
    /// 全项目更新：**形状随注册项目数变化**（见 `UpdateOutcome`）。
    pub fn update_all(&self, deep: bool) -> Result<UpdateOutcome, EngineError> {
        let op = if deep { "deep" } else { "update" };
        let r = self.run_checked(&[op, "--json", "--quiet"], WRITE_TIMEOUT)?;
        let v = parse_or_payload(op, &r)?;
        let raw = truncate_chars(&v.to_string(), 400);
        if v.get("results").is_some() {
            serde_json::from_value::<crate::models::MultiResults>(v)
                .map(UpdateOutcome::Multi)
                .map_err(|e| EngineError::Json {
                    command: op.to_string(),
                    message: e.to_string(),
                    raw,
                })
        } else {
            serde_json::from_value::<crate::models::UpdateReceipt>(v)
                .map(UpdateOutcome::Single)
                .map_err(|e| EngineError::Json {
                    command: op.to_string(),
                    message: e.to_string(),
                    raw,
                })
        }
    }

    /// 面板级 git 操作（引擎白名单：pull / push / fetch / stash / unstash / commit）。
    /// 失败时 rc=1 且 `ok:false`，`output` 是人话原因 —— **不是** `code/error` 形状。
    pub fn git(
        &self,
        project: &str,
        op: GitOp,
        message: Option<&str>,
        paths: &[String],
    ) -> Result<crate::models::GitOpResponse, EngineError> {
        // 同一条判据在桥层再拦一次：`--paths` 是逗号分隔，含逗号的路径
        // 会被引擎切错成两个不存在的文件，而提交仍可能“成功”。
        if let Some(bad) = paths.iter().find(|p| p.contains(',')) {
            return Err(EngineError::Io(format!(
                "路径含逗号，无法用 --paths 表达：{bad}；请改用「提交全部」"
            )));
        }
        let joined = paths.join(",");
        let mut args = vec!["git", op.as_str(), project];
        if op == GitOp::Commit {
            // 没有信息时**不要**传 `--message ""`：引擎会把空值当成「缺少取值」，
            // 而它本来会返回结构化原因 `{op,ok:false,output:"需要提交信息（--message）"}`。
            // 让引擎说它自己的话，客户端只负责展示。
            if let Some(msg) = message {
                if !msg.is_empty() {
                    args.push("--message");
                    args.push(msg);
                }
            }
            // 空 = 提交全部；非空 = 只提交这些路径（逗号分隔，含逗号的路径会错切）
            if !paths.is_empty() {
                args.push("--paths");
                args.push(joined.as_str());
            }
        }
        args.push("--json");
        self.read_json(&format!("git {}", op.as_str()), &args, GIT_TIMEOUT)
    }

    /// `git status <p> --json` 的信封是 `{op,ok,output,project}`，
    /// 条目 JSON 在 `output` 字符串里 —— 必须**二次解码**。
    /// `output` 也可能是纯文本（失败时），那就不是条目，而是原因。
    pub fn git_status(
        &self,
        project: &str,
    ) -> Result<crate::models::GitStatusPayload, EngineError> {
        let outer: crate::models::GitOpResponse =
            self.read_json("git status", &["git", "status", project, "--json"], GIT_TIMEOUT)?;
        let raw = outer.output.trim();
        if raw.is_empty() {
            return Ok(crate::models::GitStatusPayload {
                ok: outer.ok,
                err: if outer.ok {
                    None
                } else {
                    Some("引擎没有给出 git status 的输出".to_string())
                },
                entries: Vec::new(),
                total: None,
            });
        }
        match serde_json::from_str::<crate::models::GitStatusPayload>(raw) {
            Ok(mut inner) => {
                if !outer.ok && inner.err.is_none() {
                    inner.err = Some("git status 失败（引擎未给出原因）".to_string());
                }
                Ok(inner)
            }
            Err(e) => Ok(crate::models::GitStatusPayload {
                ok: false,
                err: Some(format!(
                    "git status 条目解析失败：{}；原文：{}",
                    e,
                    truncate_chars(raw, 200)
                )),
                entries: Vec::new(),
                total: None,
            }),
        }
    }

    pub fn milestone_add(
        &self,
        project: &str,
        name: &str,
        tag: &str,
        date: &str,
        desc: &str,
    ) -> Result<crate::models::MilestoneAddReceipt, EngineError> {
        let mut args = vec!["milestone", "add", project, name];
        if !tag.trim().is_empty() {
            args.push("--tag");
            args.push(tag);
        }
        if !date.trim().is_empty() {
            args.push("--date");
            args.push(date);
        }
        if !desc.trim().is_empty() {
            args.push("--desc");
            args.push(desc);
        }
        args.push("--json");
        self.read_json("milestone add", &args, WRITE_TIMEOUT)
    }

    pub fn milestone_action(
        &self,
        project: &str,
        name: &str,
        op: MilestoneOp,
    ) -> Result<crate::models::MilestoneActionReceipt, EngineError> {
        self.read_json(
            "milestone action",
            &["milestone", op.as_str(), project, name, "--json"],
            WRITE_TIMEOUT,
        )
    }

    pub fn milestone_remove(
        &self,
        project: &str,
        name: &str,
    ) -> Result<crate::models::MilestoneRemoveReceipt, EngineError> {
        self.read_json(
            "milestone remove",
            &["milestone", "remove", project, name, "--json"],
            WRITE_TIMEOUT,
        )
    }

    pub fn scan(
        &self,
        roots: &[String],
        depth: u32,
        git_only: bool,
    ) -> Result<crate::models::ScanPayload, EngineError> {
        if roots.is_empty() {
            return Err(EngineError::Io("没有扫描根目录".to_string()));
        }
        if depth == 0 {
            // 「一个子目录都不看」永远不是想找仓库的人会提的要求（与 --depth 0 同处置）
            return Err(EngineError::Io("扫描深度必须 >= 1".to_string()));
        }
        let depth_text = depth.to_string();
        let mut args: Vec<&str> = vec!["scan"];
        for r in roots {
            args.push(r.as_str());
        }
        args.push("--depth");
        args.push(depth_text.as_str());
        if git_only {
            args.push("--git-only");
        }
        args.push("--json");
        self.read_json("scan", &args, SCAN_TIMEOUT)
    }

    pub fn add_project(
        &self,
        path: &str,
        name: Option<&str>,
    ) -> Result<crate::models::RegistryEntry, EngineError> {
        let mut args = vec!["add", path];
        if let Some(n) = name {
            if !n.trim().is_empty() {
                args.push("--name");
                args.push(n);
            }
        }
        args.push("--json");
        self.read_json("add", &args, WRITE_TIMEOUT)
    }

    pub fn remove_project(
        &self,
        name: &str,
    ) -> Result<crate::models::RegistryEntry, EngineError> {
        self.read_json("remove", &["remove", name, "--json"], WRITE_TIMEOUT)
    }

    // ── graph ────────────────────────────────────────────────────────

    /// 结构置信度报告（JSON）。
    pub fn confidence(
        &self,
        project: &str,
    ) -> Result<crate::models::ConfidenceReport, EngineError> {
        self.read_json(
            "graph confidence",
            &["graph", "confidence", project, "--json"],
            GRAPH_TIMEOUT,
        )
    }

    /// `--llm` 是**纯文本**的复核任务书（即使同时给 `--json` 也返回文本）：
    /// 不能走 `read_json`，否则会把提示词当 JSON 解析失败。
    pub fn confidence_llm_prompt(&self, project: &str) -> Result<String, EngineError> {
        let r = self.run_checked(
            &["graph", "confidence", project, "--json", "--llm"],
            GRAPH_TIMEOUT,
        )?;
        Ok(r.stdout)
    }

    pub fn patchconf(
        &self,
        project: &str,
        patch: &Path,
    ) -> Result<crate::models::PatchReport, EngineError> {
        self.patchconf_raw(project, patch).map(|(r, _)| r)
    }

    /// 同 `patchconf`，但把**原始 stdout** 一并交回。
    /// Layer-1 结果要落盘成 `--merge` 的 algorithm.json —— 只拿解析后的结构
    /// 写不回原样 JSON，客户端就无法在应用内走完「分析 → 合并」。
    pub fn patchconf_raw(
        &self,
        project: &str,
        patch: &Path,
    ) -> Result<(crate::models::PatchReport, String), EngineError> {
        let p = patch.to_string_lossy().into_owned();
        let r = self.run_checked(
            &["graph", "patchconf", project, "--patch", p.as_str(), "--json"],
            GRAPH_TIMEOUT,
        )?;
        let report = parse("graph patchconf", &r)?;
        Ok((report, r.stdout))
    }

    /// Agent 任务书是**纯文本**（不是 JSON）：`--skill` 必须同时给 `--patch`。
    pub fn patchconf_skill(
        &self,
        project: &str,
        patch: &Path,
    ) -> Result<String, EngineError> {
        let p = patch.to_string_lossy().into_owned();
        let r = self.run_text(
            &["graph", "patchconf", project, "--patch", p.as_str(), "--skill"],
            GRAPH_TIMEOUT,
        )?;
        Ok(r.stdout)
    }

    pub fn patchconf_merge(
        &self,
        algorithm: &Path,
        agent: &Path,
    ) -> Result<crate::models::MergedReport, EngineError> {
        let a = algorithm.to_string_lossy().into_owned();
        let b = agent.to_string_lossy().into_owned();
        self.read_json(
            "graph patchconf --merge",
            &["graph", "patchconf", "--merge", a.as_str(), b.as_str(), "--json"],
            GRAPH_TIMEOUT,
        )
    }

    // ── 系统 ────────────────────────────────────────────────────────

    /// 引擎诊断。**退出码表达「发现了几类问题」，不是「命令失败」**：
    /// 实测有失效项目时 rc=1，而 stdout 仍是完整的诊断表。
    /// 所以这里绕过 `run_checked` 的「非 0 即失败」裁决：有表格就交表格。
    pub fn doctor(&self) -> Result<String, EngineError> {
        let r = self.run_raw(&["doctor"], READ_TIMEOUT)?;
        if r.timed_out {
            return Err(EngineError::Timeout {
                secs: READ_TIMEOUT.as_secs(),
                command: "doctor".to_string(),
            });
        }
        if !r.stdout.trim().is_empty() {
            return Ok(r.stdout);
        }
        if !r.ok {
            return Err(EngineError::Exit {
                code: r.code,
                message: best_failure_text(&r),
                details: None,
                stderr: r.stderr,
            });
        }
        Err(EngineError::Io("引擎 doctor 没有输出".to_string()))
    }

    /// 引擎事实语言的写入（文本回执）。失败要显示，不许吞。
    pub fn config_set_language(&self, code: &str) -> Result<JobResult, EngineError> {
        self.run_text(&["config", "set", "language", code], READ_TIMEOUT)
    }

    /// 工作区 diff：**不是引擎命令**，是标准 git。
    /// 补丁体检的输入；写临时文件由调用方（core）负责。
    pub fn git_diff_head(&self, repo: &Path) -> Result<JobResult, EngineError> {
        let repo_text = repo.to_string_lossy().into_owned();
        spawn_and_wait(
            "git",
            &["-C", repo_text.as_str(), "diff", "HEAD"],
            GIT_TIMEOUT,
            self.cancel.as_deref(),
        )
    }
}

// ══════════════════════════════════════════════════════════════════════
// 解析与失败判据
// ══════════════════════════════════════════════════════════════════════

/// 从一份合法 JSON 载荷里找出「这条命令失败了吗、原因是什么」。
///
/// 判据与引擎 `hasErrorOrCode`（`src/util/log.cj`）同规则：
///   · **有 `ok` 键 ⇒ 不是失败** —— git 形状（`{op,ok,output}`）由调用方读 `ok`；
///   · 有 `results` / `projects` 的聚合信封也不是本层判失败 —— 它们逐项带错误；
///   · 否则 `error:true` / `code` / `message` 任一出现 ⇒ 失败，message 优先。
pub fn failure_message(v: &Value) -> Option<String> {
    let has_ok = v.get("ok").is_some();
    let has_results = v.get("results").is_some();
    let has_projects = v.get("projects").is_some();
    if has_ok || has_results || has_projects {
        return None;
    }
    let is_error = v
        .get("error")
        .map(|e| e == &Value::Bool(true) || e.is_string())
        .unwrap_or(false);
    let has_code = v.get("code").is_some();
    let has_message = v.get("message").is_some();
    if !(is_error || has_code || has_message) {
        return None;
    }
    for key in ["message", "error", "detail", "details"] {
        if let Some(s) = v.get(key).and_then(|x| x.as_str()) {
            if !s.trim().is_empty() {
                return Some(s.to_string());
            }
        }
    }
    Some("引擎报告失败但没有给出原因".to_string())
}

fn best_failure_text(r: &JobResult) -> String {
    let stderr = r.stderr.trim();
    if !stderr.is_empty() {
        return stderr.to_string();
    }
    let stdout = r.stdout.trim();
    if !stdout.is_empty() {
        return truncate_chars(stdout, 400);
    }
    format!("引擎退出码 {}（没有输出）", r.code)
}

/// 解析载荷。**载荷优先于退出码**；只有 stdout 不是 JSON 时才看退出码。
pub fn parse<T: DeserializeOwned>(cmd: &str, r: &JobResult) -> Result<T, EngineError> {
    let raw = r.stdout.trim();
    match serde_json::from_str::<Value>(raw) {
        Ok(v) => {
            if let Some(msg) = failure_message(&v) {
                return Err(EngineError::Exit {
                    code: r.code,
                    message: msg,
                    details: None,
                    stderr: r.stderr.clone(),
                });
            }
            serde_json::from_value::<T>(v).map_err(|e| EngineError::Json {
                command: cmd.to_string(),
                message: e.to_string(),
                raw: truncate_chars(raw, 400),
            })
        }
        Err(_) => {
            if !r.ok {
                Err(EngineError::Exit {
                    code: r.code,
                    message: best_failure_text(r),
                    details: None,
                    stderr: r.stderr.clone(),
                })
            } else {
                Err(EngineError::Json {
                    command: cmd.to_string(),
                    message: "stdout 不是 JSON".to_string(),
                    raw: truncate_chars(raw, 400),
                })
            }
        }
    }
}

/// 只要形状不要类型：给「失败也可能带合法 payload」的调用方用。
pub fn parse_or_payload(cmd: &str, r: &JobResult) -> Result<Value, EngineError> {
    let raw = r.stdout.trim();
    match serde_json::from_str::<Value>(raw) {
        Ok(v) => {
            if let Some(msg) = failure_message(&v) {
                return Err(EngineError::Exit {
                    code: r.code,
                    message: msg,
                    details: None,
                    stderr: r.stderr.clone(),
                });
            }
            Ok(v)
        }
        Err(_) => {
            if !r.ok {
                Err(EngineError::Exit {
                    code: r.code,
                    message: best_failure_text(r),
                    details: None,
                    stderr: r.stderr.clone(),
                })
            } else {
                Err(EngineError::Json {
                    command: cmd.to_string(),
                    message: "stdout 不是 JSON".to_string(),
                    raw: truncate_chars(raw, 400),
                })
            }
        }
    }
}

fn command_label(args: &[&str]) -> String {
    args.iter()
        .take(3)
        .copied()
        .collect::<Vec<_>>()
        .join(" ")
}

// ══════════════════════════════════════════════════════════════════════
// 进程执行
// ══════════════════════════════════════════════════════════════════════

/// spawn + 双管道并发读 + 超时/取消 kill。返回原始结果（不做 JSON 裁决）。
///
/// `cancel` 是**用户主动停止**的旗标（后台 Job）：置位后与超时走同一条
/// kill + wait 路径，但错误类型是 `Cancelled` 而不是 `Timeout` ——
/// 用户自己停的不该被报成「引擎卡住了」。
fn spawn_and_wait(
    program: &str,
    args: &[&str],
    timeout: Duration,
    cancel: Option<&AtomicBool>,
) -> Result<JobResult, EngineError> {
    let started = Instant::now();
    let mut cmd = Command::new(program);
    cmd.args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(windows)]
    {
        // Win32 GUI 子进程：不弹控制台黑框
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    let mut child = cmd.spawn().map_err(|e| EngineError::Spawn {
        bin: program.to_string(),
        message: e.to_string(),
    })?;

    // 两条管道必须并发排空：只 wait 不读会在输出很大时把子进程堵死
    // （管道缓冲满了 ⇒ 子进程写不进去 ⇒ 永远不退出 ⇒ 假超时）。
    let out_handle = child.stdout.take().map(|mut pipe| {
        std::thread::spawn(move || {
            let mut buf = Vec::new();
            let _ = pipe.read_to_end(&mut buf);
            buf
        })
    });
    let err_handle = child.stderr.take().map(|mut pipe| {
        std::thread::spawn(move || {
            let mut buf = Vec::new();
            let _ = pipe.read_to_end(&mut buf);
            buf
        })
    });

    let deadline = started + timeout;
    let mut timed_out = false;
    let mut cancelled = false;
    let mut status: Option<std::process::ExitStatus> = None;
    loop {
        if cancel.is_some_and(|c| c.load(Ordering::Relaxed)) {
            cancelled = true;
            let _ = child.kill();
            let _ = child.wait();
            break;
        }
        match child.try_wait() {
            Ok(Some(st)) => {
                status = Some(st);
                break;
            }
            Ok(None) => {}
            Err(e) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(EngineError::Io(format!("等待引擎进程失败：{e}")));
            }
        }
        if Instant::now() >= deadline {
            timed_out = true;
            let _ = child.kill();
            let _ = child.wait();
            break;
        }
        std::thread::sleep(Duration::from_millis(25));
    }

    let stdout = out_handle
        .and_then(|h| h.join().ok())
        .map(|b| String::from_utf8_lossy(&b).into_owned())
        .unwrap_or_default();
    let stderr = err_handle
        .and_then(|h| h.join().ok())
        .map(|b| String::from_utf8_lossy(&b).into_owned())
        .unwrap_or_default();

    if cancelled {
        // 管道已 join（子进程已死，读线程会退出）；丢弃半途输出 ——
        // 被用户停掉的结果不是结果，不能拿去解析。
        let _ = (stdout, stderr);
        return Err(EngineError::Cancelled);
    }

    let code = if timed_out {
        -1
    } else {
        status.and_then(|s| s.code()).unwrap_or(-1)
    };
    Ok(JobResult {
        ok: status.map(|s| s.success()).unwrap_or(false) && !timed_out,
        code,
        stdout,
        stderr,
        timed_out,
        duration_ms: started.elapsed().as_millis() as u64,
    })
}

// ══════════════════════════════════════════════════════════════════════
// 可执行文件发现
// ══════════════════════════════════════════════════════════════════════

pub fn discover_bin() -> String {
    for key in ["MOONGIT_BIN", "DEEPGIT_BIN"] {
        if let Ok(v) = std::env::var(key) {
            if !v.is_empty() {
                return v;
            }
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            for name in ["moongit", "deepgit"] {
                let p = dir.join(exe_name(name));
                if p.is_file() {
                    return p.to_string_lossy().into_owned();
                }
            }
        }
    }
    if let Some(p) = which("moongit") {
        return p;
    }
    if let Some(p) = which("deepgit") {
        return p;
    }
    "moongit".to_string()
}

fn exe_name(base: &str) -> String {
    if cfg!(windows) {
        format!("{base}.exe")
    } else {
        base.to_string()
    }
}

/// PATH 扫描（不借 shell：Windows 上没有 `which`，也不需要 `sh -c`）。
fn which(name: &str) -> Option<String> {
    let path = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&path) {
        let p = dir.join(exe_name(name));
        if p.is_file() {
            return Some(p.to_string_lossy().into_owned());
        }
        if cfg!(windows) {
            for ext in ["bat", "cmd", "ps1"] {
                let q = dir.join(format!("{name}.{ext}"));
                if q.is_file() {
                    return Some(q.to_string_lossy().into_owned());
                }
            }
        }
    }
    None
}

// ══════════════════════════════════════════════════════════════════════
// 系统打开（不是引擎通道；BUI 没有 webview，图谱正身交给系统浏览器）
// ══════════════════════════════════════════════════════════════════════

pub fn open_external(path: &str) {
    #[cfg(target_os = "macos")]
    let _ = Command::new("open").arg(path).spawn();
    #[cfg(target_os = "windows")]
    let _ = Command::new("cmd").args(["/C", "start", "", path]).spawn();
    #[cfg(all(unix, not(target_os = "macos")))]
    let _ = Command::new("xdg-open").arg(path).spawn();
}

pub fn reveal_in_file_manager(path: &str) {
    #[cfg(target_os = "macos")]
    let _ = Command::new("open").args(["-R", path]).spawn();
    #[cfg(target_os = "windows")]
    let _ = Command::new("explorer").arg(format!("/select,{path}")).spawn();
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        let dir = Path::new(path)
            .parent()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_else(|| path.to_string());
        let _ = Command::new("xdg-open").arg(dir).spawn();
    }
}

pub fn open_terminal(path: &str) {
    #[cfg(target_os = "macos")]
    let _ = Command::new("open").args(["-a", "Terminal", path]).spawn();
    #[cfg(target_os = "windows")]
    {
        let cd = format!("cd /d {path}");
        let _ = Command::new("cmd")
            .args(["/C", "start", "cmd", "/K", cd.as_str()])
            .spawn();
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    let _ = Command::new("x-terminal-emulator").current_dir(path).spawn();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ok_key_means_not_a_failure() {
        // 与引擎 hasErrorOrCode 同规则：有 ok 键 ⇒ 不是失败（git / results 由调用方判）
        assert!(failure_message(&serde_json::json!({
            "ok": false, "code": 2, "message": "x"
        }))
        .is_none());
        assert!(failure_message(&serde_json::json!({
            "results": [], "failed": 1
        }))
        .is_none());
        assert!(failure_message(&serde_json::json!({
            "projects": {}, "summary": {}
        }))
        .is_none());
        assert!(failure_message(&serde_json::json!({ "schema": "x" })).is_none());

        assert_eq!(
            failure_message(&serde_json::json!({ "code": 2, "message": "坏" })).as_deref(),
            Some("坏")
        );
        assert_eq!(
            failure_message(&serde_json::json!({ "error": true })).as_deref(),
            Some("引擎报告失败但没有给出原因")
        );
    }

    #[test]
    fn url_redaction_hides_credentials() {
        assert_eq!(
            redact_url("https://u:secret@host.example:8443/v1/x?key=abc"),
            "https://host.example:8443/…"
        );
        assert_eq!(
            redact_url("https://host.example?key=abc"),
            "https://host.example/…"
        );
        assert_eq!(redact_url("not-a-url"), "(地址已隐藏)");
        assert_eq!(redact_url("https://user:pass@"), "(地址已隐藏)");
    }

    #[test]
    fn user_message_redacts_and_keeps_actionable_text() {
        let e = EngineError::Exit {
            code: 1,
            message: "连接 https://u:k@h:1/x?key=z 失败".to_string(),
            details: None,
            stderr: String::new(),
        };
        let m = e.user_message();
        assert!(m.contains("https://h:1/…"), "{m}");
        assert!(!m.contains("k@h"), "{m}");
        assert!(!m.contains("key=z"), "{m}");
        assert!(m.contains("失败"), "{m}");
    }

    #[test]
    fn short_name_strips_dirs_and_exe() {
        assert_eq!(Engine::with_bin("/a/b/moongit").short_name(), "moongit");
        assert_eq!(
            Engine::with_bin("C:\\bin\\moongit.exe").short_name(),
            "moongit"
        );
    }

    #[test]
    fn update_outcome_shapes_are_distinct() {
        let single = UpdateOutcome::Single(crate::models::UpdateReceipt {
            ok: true,
            project: "p".to_string(),
            ..Default::default()
        });
        assert_eq!(single.count(), 1);
        assert_eq!(single.succeeded(), 1);
        assert_eq!(single.failed(), 0);
        assert!(single.multi().is_none());

        let multi = UpdateOutcome::Multi(crate::models::MultiResults {
            count: 2,
            succeeded: 1,
            failed: 1,
            ..Default::default()
        });
        assert_eq!(multi.count(), 2);
        assert_eq!(multi.failed(), 1);
        assert!(multi.single().is_none());
    }
}
