# Linux 客户端（规划中）

- 技术：GTK4 或 Tauri（待定）
- 职责：通过 CLI 子进程调用 deepGit Engine（与 macOS 客户端同构）
- 系统集成：StatusNotifier 托盘 + 主窗口 + autostart（XDG `~/.config/autostart`）
- 引擎发现：`DEEPGIT_BIN` → 内嵌副本 → `~/.local/bin` → PATH

引擎侧前置：仓颉 Linux 工具链构建（x86_64 / aarch64）。
