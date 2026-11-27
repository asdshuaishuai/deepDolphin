# AGENTS.md

**Sylva** 项目的客户端仓库。整个项目叫 Sylva：引擎叫 **Cambium**（独立仓库，GitHub `asdshuaishuai/moongit`，
本地通常在兄弟目录 `../moongit`），客户端叫 **Canopy**，引擎里的置信度模块叫 **Dendro**。
本仓不含引擎源码：客户端经 CLI 子进程调用引擎（`cambium <命令> --json`），只负责数据渲染、AI 通道与系统集成。

名字改过两轮（deepGit → moonGit，再 → Cambium / Canopy / Dendro），**仓库与目录名没有跟着改**：
两个仓库都开着 GitHub Pages，改名后 Pages 地址不跳转。看到 `moongit` / `deepDolphin` 的目录名、
链接、旧命令别名，都是有意保留的，不要「顺手改名」。

## 仓库形状

单 git 仓。**全平台的客户端就是 `client/` 里的 CMP 这一份**（Kotlin + Compose Desktop，
macOS / Linux / Windows 都跑它），不再做任何平台的原生开发（用户 2026-11-26 定，见 `client/PLAN.md`
「平台决定」）。其余目录是冻结的历史参照，**不投入新工作、不删**：

- `client/` — **Canopy（CMP）**：唯一的在研客户端。Compose Desktop 1.7 / Kotlin 2.0 / JDK 21
- `macos/` `linux/` `deepin/` `windows/` `harmonyos/` — 冻结的各平台原生端（SwiftUI / 仓颉+CUI / DTK6+Qt6 / …），
  目录名、包名仍是旧的 deepDolphin；只当历史参照，各自的 README 与判据脚本仍在
- `docs/` — `ui-cmp/`（界面实拍与说明）、`ROADMAP.md` 等；`client/PLAN.md` 是客户端的施工台账（每批的取舍与边界）
- `assets/` — 图标等资产的真相源；`website/` — 项目主页（GitHub Pages 从 gh-pages 分支发布）
- `PLATFORM-CHARTER.md` — 跨平台能力基准（C1–C11）

唯一耦合面 = 引擎 `--json` 键名。引擎仓的 `AGENTS.md` 是协作规约与不变量的**上游出处**，改契约前先读它。

## Setup commands

只走 `client/`。JDK 21 与 Gradle 装在家目录（`~/.local/jdk`、`~/.local/gradle`），脚本自动定位，**不需要 root**。

```sh
cd client
scripts/build.sh --test     # 编译 + 全量判据（jvmTest），末行 CMPTEST_SUMMARY passed=N skipped=S failed=M
scripts/build.sh --run      # 编译后真窗口启动（需 DISPLAY）
gradle packageDeb           # jpackage 打 deb（或 packageAppImage）
scripts/install-user.sh     # 免 root 安装：~/.local/opt/canopy + ~/.local/bin/canopy + 应用菜单项（--uninstall 卸掉）
```

引擎发现链：`CAMBIUM_BIN` → `MOONGIT_BIN` / `DEEPGIT_BIN`（旧名兜底）→ 仓内构建 → PATH
（`cambium` / `moongit` / `deepgit`）。引擎的装法见引擎仓 README。
**缺系统依赖（引擎、ast-grep、sudo 才能装的东西）时告诉用户来装**，不自行安装系统包。

## Code style

无仓库级 linter / formatter——**照邻近文件的写法走**。本仓特有的硬约定：

- **判定与渲染分开**：判定抽到零依赖纯函数（`canopy.engine` / `canopy.sysint` 等），Composable 只渲染。
  判定藏进视图 = 单测抓不到。
- **单一真相源**：一条规则只许有一个出处。字符串表是生成物（`scripts/gen_l10n.py` → `L10nTables.kt`），
  **手改会被下次生成覆盖**——要改就改生成器。
- **设计令牌单一来源**：色值 / 字号 / 圆角 / 材质只从 `ui/Design.kt`（`Palette` / `Type` / `Radius`）与
  `ui/Skin.kt`（换肤时派生）取。界面代码里手写色值 = 要逐个修的 bug。
- **文字极性看主题色**：浅色主题主文字纯黑、深色主题纯白；容器上的前景只有纯黑 / 纯白（`readableOn`）。
  文字与表面的对比度由换肤时的保底与 `SkinTest` 守卫钉住，不在调用点手调。
- **注释写「为什么」不写「什么」**：注释密度高、逐条记取舍与代价，中文书写。
- **文档随代码同步**：每批的取舍、判据与边界当轮写进 `client/PLAN.md`，状态数字写进 `client/README.md`。

## Testing instructions

- **判据先行**：每个行为改动配一条判据；**负控必须真红**（摘掉接线或改成恒真，确认判据红）。
  「判据全绿」本身不构成证据。
- **门禁证据必须禁用缓存**：`gradle jvmTest --rerun-tasks --no-build-cache`。增量构建下跑过旧字节码、
  读到陈旧 test-results 的事都出过。
- **界面改动要量，不要凭感觉**：皮肤 / 对比度走离屏体检（`SkinContrastAudit`，需显示器：
  `CANOPY_SKIN_AUDIT=<目录> gradle jvmTest --rerun-tasks --tests '*SkinContrastAudit*'`；加
  `CANOPY_SKIN_AUDIT_HOVER=1` / `_PRESSED=1` 把悬停 / 按下态也量一遍）；真窗口实拍归档在 `docs/ui-cmp/`。
  离屏只能证明「画出来的东西」，证明不了「和真窗口是同一棵树」——两者都要。
- **真窗口取图按窗口取，不从屏幕合成结果取**；锁屏时**一律不发键鼠**（会打进锁屏的密码框）。
- 引擎缺席时契约检查 SKIP——**SKIP 不算通过**，如实报告。

## 协作规约

继承引擎仓 `AGENTS.md`「协作规约」节：

1. **拿不准时按最佳预案定，不停下来提问。** 只有两类可以问：① 会写进用户真实数据或造成不可逆损失的动作；
   ② 物理授权（OAuth / MFA / 硬件钥匙）。
2. **决定必须同轮落文档**，否则等于不存在：通用结论 → 判据；本次取舍与已知代价 → `client/PLAN.md`。
   两者都要能回答「后来者凭什么这么定」。
3. **改名字不改身份**：`DEEPGIT_BIN` / `DEEPGIT_HOME` 环境变量名、`~/.deepgit` 数据目录、
   `<!-- deepgit:begin -->` 文档托管标记、已落盘产物的 schema 串都是既有接口，不许改（用户 2026-11-27：`~/.deepgit` 不动）。
4. **界面要完全的 Fluent 美学**；不设独立的「AI 助手」入口；图谱两页跟仓库走、是独立页面不弹窗、由 WebView 渲染。
5. **诚实降级**：AI 未配置 → 更新动作照常可用（仅无摘要）；引擎不可达 → 明确报错 + 引导安装。
   每条出口都要区分「跑成了 / 没跑成（附原因与下一步）/ 跑了但没产出」，永不静默。
6. **缺字段不回落成 0**：引擎没说 ≠ 没有。缺披露字段显示「?」，不显示 0。
7. **失败要说清是哪一种**：引擎找不到 / 契约过旧 / 部分项目失败——三者分开说，处置不同。
8. **失败的项目留在列表里并显示引擎给的原因**，不静默过滤（过滤掉 = 谎称读过那个仓库）。

## PR & commit conventions

- 在最新分支上工作（当前是 `next/cmp`）；`main` 与 `dev` 落后，不直接提交
- Conventional commits：`feat(ui):` / `fix(ui):` / `docs:` / `chore:` …；提交信息写清「改了什么 + 为什么 + 影响面」
- 阶段完成即提交：判据全绿 + 负控真红 + 复验完成即算一个阶段；提交后推送
- 对外、难撤回的动作（改仓库名、公开发版打标、动用户数据）先确认

## Security

- **API key 只进平台安全存储**（钥匙串 / libsecret /…）；不进日志、不进配置文件明文。
  降级到文件（chmod 600）时**在设置页显式写明**，不静默降级。
- **客户端零业务数据写入**：一切文档 / 进度写操作只经引擎子进程；客户端自己写盘的只有配置与自启条目。
- 引擎不可达时明确报错，不静默失败。
- `.gitignore` / `.zcodeignore` 已排除构建产物与代理会话状态（`.stepcode/` / `.zcode/`）。
