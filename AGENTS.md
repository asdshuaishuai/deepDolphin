# AGENTS.md

deepDolphin —— moonGit 引擎的**多平台客户端**（展示层 + AI 层）。业务核心在**独立仓库** moonGit
（本仓不含引擎源码）；每个客户端经 CLI 子进程调用引擎（`moongit <命令> --json`），
只负责数据渲染、AI 通道与系统集成。

## 仓库形状

单 git 仓，多平台客户端并列（不是多仓）。

- `macos/` — macOS 14+ · SwiftUI · SwiftPM 5.9（target `deepDolphin`）· **功能基准**
- `linux/` — Linux · 仓颉 1.0.5 LTS（**禁升级**）+ CangjieGUI(CUI) 0.9.6 · `cjpm`
- `deepin/` — deepin/DDE · C++17 + DTK6/Qt6 Widgets · CMake（**禁混 DTK5/Qt5**）· 1:1 对标 macos
- `windows/` — 规划中：WinUI 3 / WPF
- `harmonyos/` — 规划中：ArkUI
- `assets/icon/` — 全平台唯一图标真相源：`mark.png` 母版 → `make-icons.py` → `out/`（平台只许引用，不许复制）
- `assets/models/models-dev.json` — models.dev provider 目录快照（客户端 AI 选型数据源）

跨平台能力基准 = `PLATFORM-CHARTER.md`（C1–C11）：**交互 UI 各平台自由，能力必须一致**。
唯一耦合面 = 引擎 `--json` 键名；改动必须同步各端模型层。
引擎仓（兄弟目录 `../moongit`）的 `AGENTS.md` 是协作规约与不变量的**上游出处**，先读它。

## Setup commands

**各平台独立，无全仓统一命令** —— 只走你要改的那个目录。

| 目录 | 装依赖 | 构建 | 测试 / 验证 | 运行 |
|---|---|---|---|---|
| `macos/` | — | `sh build.sh` | `sh scripts/client-check.sh`（+ `agent-check` / `catalog-check` / `markdown-check`）；契约 `sh scripts/contract-check.sh`（需可执行的 `moongit`） | `open deepDolphin.app` |
| `linux/` | `sh scripts/fetch-deps.sh`（vendor/ 已 gitignore） | `sh scripts/build.sh`（环境自举幂等 + `cjpm build`） | `sh scripts/ci-local.sh` → `cjpm test`；末尾 `CJTEST_SUMMARY … failed=0`；AI 链路 `sh scripts/ai-e2e.sh` | `sh scripts/run.sh` / `sh scripts/dev-launch.sh` |
| `deepin/` | `python3 scripts/bootstrap-deps.py --download` + `sh scripts/setup-deps.sh`（用户态 sysroot，无需 root） | `cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --parallel 4` | `./build/deepDolphin --selfcheck`（66 例，须 0 失败）；`sh scripts/ci.sh`（6 道门）；契约 `sh scripts/contract-check.sh` | `sh scripts/dev-run.sh`（`-o` 离屏冒烟） |
| 根 | — | — | `bash assets/icon/check-icon.sh` | — |

引擎发现链：`DEEPGIT_BIN` → 应用内嵌副本 → `~/.local/bin` → PATH。
引擎安装步骤见 `deepin/README.md`「引擎安装前提」。

## Code style

无 linter / formatter 配置（无 `.editorconfig` / swiftlint / clang-format）—— **照邻近文件的写法走**。
本仓特有的硬约定：

- **纯函数判定层**：判定抽到零依赖纯函数，视图层只渲染。
  macos：进 `client-check.sh` 编译清单的文件**不得** `import SwiftUI|AppKit`；
  deepin：`src/models/`、`src/logic/` 零 QWidget 头；linux：判据在 `src/*_test.cj`。
  判定藏回视图 = 运行时抓不到 = 缺陷漏网。
- **单一真相源**：一条规则只许有一个出处（如「当前分支」= `ProjectStatus.primaryBranch`，
  快捷键 = `logic/ShortcutMap.h` / `ShortcutMap.swift`）。抄第二份，迟早两份都错。
- **设计令牌单一来源**：色值/间距/字号走 `DS::*`（macos）、`tokens.cj`（linux）、`DesignTokens`（deepin）。
  deepin 有 grep 硬门：DS 之外出现色值 / px 字号即失败（存量上限 4，只减不增）。
- **动效极少**：macOS 全项目只 1 处动效，必须走 `DSMotion.standard`；不许新增裸 `withAnimation`。
- **注释写「为什么」不写「什么」**：本仓注释密度高、逐条记取舍与代价，中文书写。
- **文档随代码同步**：代码结构清单按磁盘重建（`client-check.sh` 有双向判据）——改了文件要改 README 清单。

## Testing instructions

- **判据先行**：每个行为改动配一条判据；**负控必须真红**（摘掉接线或改成恒真，确认判据红）。
  「判据全绿」本身不构成证据。
- 各端判据落点：macos `scripts/*-check.sh`（`swiftc` 单独编译**本体**而非副本）；
  linux `src/model_test.cj`(140) + `src/ai_test.cj`(46) + `src/markdown_test.cj`(17)；
  deepin 二进制内置 `--selfcheck`（`src/app/SelfCheck.cpp`）。
- **交叉验证必须拿非空样本**；负控按判据的**实际位置**选套件（源码扫描类判据先剥注释再匹配）。
- 契约改动必须同时过 `contract-check.sh`（真引擎输出喂真模型层），且各端模型层同步。
- UI 改动走离屏快照对比**同机位** before/after 基线（linux `scripts/ui-snap.sh`、deepin `--snapshot`）；
  凭感觉说「应该好看了」不算验收。
- 引擎缺席时契约检查 SKIP —— **SKIP 不算通过**，如实报告。

## 协作规约

继承 `../moongit/AGENTS.md`「协作规约」节：

1. **拿不准时按最佳预案定，不停下来提问。** 只有两类可以问：① 会写进用户真实数据或造成不可逆损失的动作；
   ② 物理授权（OAuth / MFA / 硬件钥匙）。
2. **决定必须同轮落文档**，否则等于不存在：通用结论 → 判据 / 不变量；本次取舍与已知代价 → README「已知边界」。
   两者都要能回答「后来者凭什么这么定」。
3. **改名字不改身份**：`DEEPGIT_BIN` / `DEEPGIT_HOME` 环境变量名、`~/.deepgit` 数据目录、
   `<!-- deepgit:begin -->` 文档托管标记都是既有接口，不许改。
4. **诚实降级**：AI 未配置 → 更新动作照常可用（仅无摘要）；引擎不可达 → 明确报错 + 引导安装。
   每条出口都要区分「跑成了 / 没跑成（附原因与下一步）/ 跑了但没产出」，永不静默。
5. **缺字段不回落成 0**：引擎没说 ≠ 没有。缺披露字段显示「?」，不显示 0。
6. **失败要说清是哪一种**：引擎找不到 / 契约过旧 / 部分项目失败 —— 三者分开说，处置不同。
7. **失败的项目留在列表里并显示引擎给的原因**，不静默过滤（过滤掉 = 谎称读过那个仓库）。

## PR & commit conventions

- 分支从 `main` 起，不直接提交到 `main`
- Conventional commits，**带平台 scope**：`feat(linux):` / `fix(deepin):` / `docs(linux):` / `chore(linux):`
- 提交信息写清「改了什么 + 为什么 + 影响面」
- 阶段完成即提交：判据全绿 + 负控真红 + 复验完成即算一个阶段
- 提交前跑对应平台的测试命令 + `bash assets/icon/check-icon.sh`

## Security

- **API key 只进平台安全存储**：macOS 钥匙串 / libsecret / DPAPI / 鸿蒙关键资产。
  不进日志、不进配置文件明文。降级到文件（chmod 600）时**在设置页显式写明**，不静默降级。
- **客户端零业务数据写入**：一切文档 / 进度写操作只经引擎子进程；客户端唯一写盘是自启 `.desktop`。
- 引擎不可达时明确报错，不静默失败。
- `.gitignore` / `.zcodeignore` 已排除构建产物与代理会话状态（`.stepcode/`、`.zcode/`）。
