// engine.rs — moonGit 引擎桥（CLI 子进程，与既有客户端同一条传输层）。
//
// 契约（AGENTS.md「传输层哲学」）：只在本机进程之间通信——spawn `moongit <命令> --json`，
// 读 stdout 的 JSON。没有 HTTP，没有 FFI。
//
// ⚠️ v0 同步调用：BUI 0.5 没有 spawn/定时器，所有引擎调用都在 UI 线程上
// 阻塞完成（首屏数据在开窗前预取，避免一进来就冻结）。单命令实测
// 100ms–1.3s（status 全量）；这是本分支的已知取舍，写进 README。

use std::process::Command;

/// 引擎可执行文件发现顺序（与 Swift 客户端同一条纪律）：
///   MOONGIT_BIN / DEEPGIT_BIN 环境变量 → 可执行文件旁的 moongit/deepgit →
///   PATH 上的 moongit → deepgit。
/// 引擎命令名 2026-10-03 从 deepgit 改为 moongit，老机器上仍可能只有旧名，
/// 所以两个名字都要找。
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
        // Windows 的 PATHEXT 世界：moongit.exe / moongit.bat / moongit.cmd
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

pub struct Engine {
    pub bin: String,
}

impl Engine {
    pub fn new() -> Engine {
        Engine { bin: discover_bin() }
    }

    /// 跑一条引擎命令，返回 stdout 文本。非 0 退出返回 Err（带 stdout/stderr）。
    pub fn run(&self, args: &[&str]) -> Result<String, String> {
        let mut cmd = Command::new(&self.bin);
        cmd.args(args);
        #[cfg(windows)]
        {
            // Win32 GUI 子进程：不弹控制台黑框
            use std::os::windows::process::CommandExt;
            cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
        }
        let out = cmd
            .output()
            .map_err(|e| format!("无法启动引擎（{}）：{e}", self.bin))?;
        let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
        if !out.status.success() {
            let stderr = String::from_utf8_lossy(&out.stderr);
            let msg = if stdout.trim().is_empty() {
                stderr.trim().to_string()
            } else {
                stdout.trim().to_string()
            };
            return Err(format!("引擎退出码 {}：{}", out.status.code().unwrap_or(-1), msg));
        }
        Ok(stdout)
    }

    pub fn status(&self) -> Result<crate::models::StatusEnvelope, String> {
        let text = self.run(&["status", "--json"])?;
        serde_json::from_str(&text).map_err(|e| format!("status JSON 解析失败：{e}"))
    }

    pub fn milestones(&self) -> Result<crate::models::MilestoneList, String> {
        let text = self.run(&["milestone", "list", "--json"])?;
        serde_json::from_str(&text).map_err(|e| format!("milestone JSON 解析失败：{e}"))
    }

    /// 面板级 git 操作（引擎白名单：pull/push/fetch/stash/unstash/commit）。
    pub fn git_op(&self, project: &str, op: &str, message: Option<&str>) -> Result<String, String> {
        let mut args = vec!["git", op, project];
        if let Some(m) = message {
            args.push("--message");
            args.push(m);
        }
        args.push("--json");
        self.run(&args)
    }

    /// 产物存在性探测（引擎 render check：只探测，绝不自愈重建）。
    pub fn artifact_exists(&self, project: &str, artifact: &str) -> Option<String> {
        let text = self
            .run(&["render", "check", artifact, project, "--json"])
            .ok()?;
        let v: serde_json::Value = serde_json::from_str(&text).ok()?;
        if v.get("exists").and_then(|x| x.as_bool()).unwrap_or(false) {
            v.get("path").and_then(|x| x.as_str()).map(|s| s.to_string())
        } else {
            None
        }
    }

    pub fn milestone_action(
        &self,
        project: &str,
        name: &str,
        action: &str,
    ) -> Result<String, String> {
        self.run(&["milestone", action, project, name, "--json"])
    }
}

/// 用系统默认程序打开文件/URL（图谱交付物 = 引擎产出的交互 HTML，
/// BUI 没有 JS/webview，正身交给系统浏览器渲染）。
pub fn open_external(path: &str) {
    #[cfg(target_os = "macos")]
    let _ = Command::new("open").arg(path).spawn();
    #[cfg(target_os = "windows")]
    let _ = Command::new("cmd").args(["/C", "start", "", path]).spawn();
    #[cfg(all(unix, not(target_os = "macos")))]
    let _ = Command::new("xdg-open").arg(path).spawn();
}
