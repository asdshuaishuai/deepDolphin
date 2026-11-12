// app.rs — 应用状态与根视图。
//
// v0 数据流：启动时同步预取 status + milestones（开窗之前完成，首屏即数据）；
// 每次动作（刷新/git/里程碑）同步执行引擎命令并就地更新状态。BUI 0.5 没有
// 异步运行时，这是本分支显式接受的取舍（见 README「已知边界」）。

use crate::engine::{open_external, Engine};
use crate::models::{MilestoneList, StatusEnvelope};
use crate::views;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Route {
    Dashboard,
    Milestones,
    Project(String),
}

/// 一次动作的反馈（成功/失败 + 文案），显示在主区顶部 banner。
#[derive(Debug, Clone)]
pub struct Feedback {
    pub ok: bool,
    pub text: String,
}

pub struct AppState {
    pub engine: Engine,
    pub status: Option<StatusEnvelope>,
    pub milestones: Option<MilestoneList>,
    pub error: Option<String>,
    pub route: Route,
    /// 项目面板的提交信息草稿（按项目名取）。
    pub commit_draft: String,
    pub feedback: Option<Feedback>,
    /// 图谱产物探测缓存：(project, artifact) -> 产物路径（None = 未生成）
    pub artifacts: Vec<((String, String), Option<String>)>,
    /// 本次启动的引擎回执（刷新时间等），页脚披露用
    pub last_refresh_note: String,
}

impl AppState {
    pub fn bootstrap() -> AppState {
        let engine = Engine::new();
        let mut st = AppState {
            engine,
            status: None,
            milestones: None,
            error: None,
            route: Route::Dashboard,
            commit_draft: String::new(),
            feedback: None,
            artifacts: Vec::new(),
            last_refresh_note: String::new(),
        };
        st.refresh();
        st
    }

    pub fn refresh(&mut self) {
        match self.engine.status() {
            Ok(s) => {
                self.status = Some(s);
                self.error = None;
            }
            Err(e) => self.error = Some(e),
        }
        match self.engine.milestones() {
            Ok(m) => self.milestones = Some(m),
            Err(e) => {
                if self.error.is_none() {
                    self.error = Some(e);
                }
            }
        }
        // 页脚只显示引擎短名（完整路径会顶出侧栏底部）
        let short = self
            .engine
            .bin
            .rsplit('/')
            .next()
            .filter(|s| !s.is_empty())
            .unwrap_or(&self.engine.bin)
            .to_string();
        let short = short.strip_suffix(".exe").unwrap_or(&short).to_string();
        self.last_refresh_note = format!("引擎：{short}");
    }

    pub fn projects(&self) -> &[crate::models::Project] {
        self.status.as_ref().map(|s| s.projects.as_slice()).unwrap_or(&[])
    }

    pub fn project(&self, name: &str) -> Option<&crate::models::Project> {
        self.projects().iter().find(|p| p.name == name)
    }

    pub fn select(&mut self, route: Route) {
        self.route = route;
        self.claim_draft_and_probe();
    }

    /// 进入项目页时：清草稿 + 预探两份图谱产物（懒探测会让卡片先显示
    /// 「尚未生成」，而产物其实就在——那是把「还没查」呈现成「没有」）。
    fn claim_draft_and_probe(&mut self) {
        self.commit_draft.clear();
        self.feedback = None;
        if let Route::Project(name) = self.route.clone() {
            let _ = self.probe_artifact(&name, "index");
            let _ = self.probe_artifact(&name, "arch");
        }
    }

    pub fn git_action(&mut self, project: &str, op: &str) {
        let msg = if op == "commit" { Some(self.commit_draft.clone()) } else { None };
        if op == "commit" && self.commit_draft.trim().is_empty() {
            self.feedback = Some(Feedback { ok: false, text: "需要提交信息".into() });
            return;
        }
        match self.engine.git_op(project, op, msg.as_deref()) {
            Ok(out) => {
                let receipt = last_line(&out);
                self.feedback = Some(Feedback { ok: true, text: format!("{op} 完成 · {receipt}") });
                if op == "commit" {
                    self.commit_draft.clear();
                }
                self.refresh();
            }
            Err(e) => self.feedback = Some(Feedback { ok: false, text: e }),
        }
    }

    pub fn milestone_action(&mut self, project: &str, name: &str, action: &str) {
        match self.engine.milestone_action(project, name, action) {
            Ok(out) => {
                self.feedback = Some(Feedback {
                    ok: true,
                    text: format!("{name} → {} · {}", action, last_line(&out)),
                });
                self.refresh();
            }
            Err(e) => self.feedback = Some(Feedback { ok: false, text: e }),
        }
    }

    /// 图谱产物探测（缓存；点击「检查」或进入项目页时调用）。
    pub fn probe_artifact(&mut self, project: &str, artifact: &str) -> Option<String> {
        let key = (project.to_string(), artifact.to_string());
        if let Some((_, v)) = self.artifacts.iter().find(|(k, _)| *k == key) {
            return v.clone();
        }
        let path = self.engine.artifact_exists(project, artifact);
        self.artifacts.push((key, path.clone()));
        path
    }

    pub fn open_artifact(&mut self, project: &str, artifact: &str) {
        match self.probe_artifact(project, artifact) {
            Some(p) => open_external(&p),
            None => {
                self.feedback = Some(Feedback {
                    ok: false,
                    text: format!(
                        "{artifact} 交付物尚未生成。用任意 AI agent 按 `moongit skill graph` 的工作流生成后再打开。"
                    ),
                });
            }
        }
    }
}

fn last_line(text: &str) -> String {
    text.lines()
        .rev()
        .map(|l| l.trim())
        .find(|l| !l.is_empty())
        .unwrap_or("完成")
        .to_string()
}

// ── 根视图 ──

pub struct AppRoot {
    pub state: AppState,
}

impl blenderui::Render for AppRoot {
    fn render(
        &mut self,
        _w: &mut blenderui::Window,
        cx: &mut blenderui::Context<Self>,
    ) -> impl blenderui::IntoElement {
        use blenderui::prelude::*;

        let body = match &self.state.route {
            Route::Dashboard => views::dashboard::render(&self.state, cx),
            Route::Milestones => views::milestones::render(&self.state, cx),
            Route::Project(name) => views::project::render(&self.state, name, cx),
        };

        div()
            .class("root")
            .child(style().child(crate::design::SHEET))
            .child(views::sidebar::render(&self.state, cx))
            .child(div().class("main").child(body))
    }
}
