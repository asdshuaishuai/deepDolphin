# Windows 客户端（规划中）

- 技术：WinUI 3 或 WPF（待定）
- 职责：通过 CLI 子进程调用 deepGit Engine（与 macOS 客户端同构）
- 系统集成：系统托盘常驻 + 主面板窗口 + 开机自启（注册表 Run 键或 Startup 文件夹）
- 引擎发现：`DEEPGIT_BIN` → 内嵌副本 → `%LOCALAPPDATA%\deepgit\bin` → PATH

引擎侧前置：仓颉 Windows 工具链构建 `deepgit.exe`（见 deepgit-engine 仓库多平台路线）。
