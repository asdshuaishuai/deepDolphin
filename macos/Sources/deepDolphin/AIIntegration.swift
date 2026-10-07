// AIIntegration.swift — AI 与更新流的整合件（deepDesign 模式的 UI 面）。
//
// - AIResultSheet：AI 输出的统一呈现（Markdown + 复制/重生成）
// - AppModel 扩展：agent 一次性调用、定时更新调度（含 AI 简报通知）
// - UpdateActionMenu：浅/深更新菜单（带 AI 摘要变体）
// - 一键项目说明按钮
import SwiftUI

// MARK: - AI 结果 Sheet

struct AIResultSheet: View {
    let title: String
    let markdown: String
    let busy: Bool
    let errorText: String?
    var onRegenerate: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text(title)
                    .font(.headline)
                Spacer()
                if !markdown.isEmpty {
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(markdown, forType: .string)
                    } label: {
                        Label(L10n.t("common.copy"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.t("airesult.copyMarkdown"))
                    .accessibilityLabel(A11y.label(L10n.t("airesult.copyMarkdown")))
                }
                if let regen = onRegenerate, !busy {
                    Button {
                        regen()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.t("airesult.regenerate"))
                    .accessibilityLabel(A11y.label(L10n.t("airesult.regenerate")))
                }
                // ⚠️ 原来**没有关闭按钮**，而 `dismiss` 声明了却一次都没用。
                // macOS 的 sheet 是贴在窗口上的，没有窗口红点可点，
                // 于是这个 620×560 的模态只能靠 Esc —— 而它也没绑 cancelAction。
                // 结论是「AI 结果一出来就出不去」，得重启 app。
                //
                // 这跟之前修的那族缺陷同源：**声明了能力却没接上**，
                // 编译器不会报，代码评审也看不出来（`dismiss` 在不在，
                // 看起来都只是个 Environment 属性）。
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help(L10n.t("common.close"))
                .accessibilityLabel(A11y.label(L10n.t("common.close")))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if busy {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.t("airesult.collecting"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorText {
                VStack(spacing: DSSpacing.sm) {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button(L10n.t("common.retry")) { onRegenerate?() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    MarkdownView(text: markdown)
                        .padding(DSSpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        // ⚠️ 原来是 `.frame(width: 620, height: 560)` —— **固定尺寸，不可缩放**。
        // 一份 AI 报告常常好几千字，620×560 的窗口里只能看到开头两三段，
        // 而用户没法拖大它（macOS 的 sheet 尺寸由这个 frame 决定）。
        // 改成「可缩放 + 有下限」：下限保证小报告不至于挤成一团，
        // 可缩放让长报告能被拖大。上下限都取合理的整数，别写死成设计稿的数值。
        .frame(minWidth: 520, idealWidth: 720,
               minHeight: 420, idealHeight: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - AppModel 扩展（AI 集成 + 定时更新）

extension AppModel {
    /// 一次性 agent 调用（供 sheet / 菜单动作）
    func askAgent(_ question: String, target: AgentTarget) async throws -> String {
        try await AgentCore.run(question: question, target: target)
    }

    /// 一键项目说明
    func projectBrief(for project: ProjectStatus) async throws -> String {
        try await AgentCore.projectBrief(projectName: project.name)
    }

    // MARK: 定时更新

    static let autoUpdateHoursKey = "update.autoHours"

    var autoUpdateHours: Int {
        UserDefaults.standard.integer(forKey: Self.autoUpdateHoursKey)
    }

    func setAutoUpdate(hours: Int) {
        UserDefaults.standard.set(hours, forKey: Self.autoUpdateHoursKey)
        restartAutoTimer()
        objectWillChange.send()
    }

    /// 启动后延迟首轮更新 + 周期更新。**必须先收掉旧的**，
    /// 否则每次面板 onAppear（→ start()）都会多挂一个 600 秒幽灵 timer。
    func restartAutoTimer() {
        autoTimer?.invalidate()
        autoTimer = nil
        // ⚠️ 原来这个「首轮延迟」timer 是**一次性**的（repeats: false），
        // 创建完既不存也不取消 —— `firstRunTimer` 当时声明了却从没赋值，
        // 于是它是个谁都碰不到的孤儿。面板开关 N 次 ⇒ 10 分钟后 N 次幽灵更新，
        // 且和 autoTimer 的周期更新撞在一起。
        firstRunTimer?.invalidate()
        firstRunTimer = nil
        let hours = autoUpdateHours
        guard hours > 0 else { return }
        autoTimer = Timer.scheduledTimer(withTimeInterval: Double(hours) * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runScheduledUpdate() }
        }
        // 首轮延迟 10 分钟（避免启动即全量更新）
        firstRunTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.runScheduledUpdate() }
        }
    }

    func runScheduledUpdate() async {
        guard !busyAll else { return }
        let ok = await updateAll(deep: false, silent: true)
        guard ok else {
            Notifier.shared.notify(title: L10n.t("notify.updateFailed"), body: AppModel.shared.lastError ?? L10n.t("notify.unknownError"))
            return
        }
        // AI 已配置 → 生成简报并通知
        if AIConfig.load().isConfigured {
            do {
                let digest = try await AgentCore.scheduledDigest()
                Notifier.shared.notify(title: L10n.t("notify.digestTitle"), body: String(digest.prefix(180)))
            } catch {
                Notifier.shared.notify(title: L10n.t("notify.digestDone.title"), body: L10n.t("notify.digestDone.bodyAI", String(EngineError.userMessage(for: error).prefix(60))))
            }
        } else {
            Notifier.shared.notify(title: "定时更新完成", body: "\(projects.count) 个项目进度已记录")
        }
    }

    /// 更新 + AI 摘要（浅/深通用）。返回摘要文本。
    func updateWithAISummary(_ project: ProjectStatus, deep: Bool) async throws -> String {
        _ = try await EngineCLI.shared.update(name: project.name, deep: deep)
        await loadProject(project.name)
        return try await AgentCore.updateDigest(projectName: project.name, deep: deep)
    }
}

// MARK: - 更新动作菜单（浅/深 × AI 变体 + 定时更新）

struct UpdateActionMenu: View {
    @EnvironmentObject var model: AppModel
    var project: ProjectStatus?
    @State private var aiResult: String?
    @State private var aiBusy = false
    @State private var aiError: String?
    @State private var showAI = false
    @State private var aiTitle = ""
    /// 本次 sheet 是**哪种模式**发起的 —— 「重试」必须重试同一个动作。
    ///
    /// ⚠️ 原来 `onRegenerate: nil`，于是错误态那个「重试」按钮点了没反应
    /// （`Button(L10n.t("common.retry")) { onRegenerate?() }` 里那个 `?` 静默吞掉）。
    /// 而那恰恰是最需要重试的时刻：引擎失败、网络失败、AI 超时。
    /// 另外三个 AIResultSheet 调用点（项目群说明 / 项目说明 / 看板说明）
    /// 都传了真闭包，只有这里漏了。
    @State private var aiDeep = false

    var body: some View {
        Menu {
            Button {
                updateAction(deep: false, withAI: true)
            } label: {
                Label(L10n.t("menu.shallowAI"), systemImage: "sparkles")
            }
            Button {
                updateAction(deep: true, withAI: true)
            } label: {
                Label(L10n.t("menu.deepAI"), systemImage: "sparkles.rectangle.stack")
            }
            if project == nil {
                Divider()
                ScheduleMenu()
            }
        } label: {
            // ⚠️ 菜单里**不再**有「浅更新」「深度更新」两个裸项：
            // 它们已经升成顶栏那对双轨按钮（设计稿最突出的元素）。
            // 同一个动作在同一个窗口里出现两次，用户会以为是两种不同的东西 ——
            // 而其中一份还少了范围信息（菜单项的标题不会随 selection 变）。
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "ellipsis.circle")
                Text(L10n.t("menu.more"))
            }
        }
        .fixedSize()
        .help(L10n.t("menu.more.help"))
        .accessibilityLabel(A11y.label(L10n.t("menu.more.a11y")))
        .sheet(isPresented: $showAI) {
            AIResultSheet(
                title: aiTitle,
                markdown: aiResult ?? "",
                busy: aiBusy,
                errorText: aiError,
                onRegenerate: { updateAction(deep: aiDeep, withAI: true) }
            )
        }
    }

    private func updateAction(deep: Bool, withAI: Bool) {
        Task {
            if withAI {
                aiBusy = true
                aiError = nil
                aiResult = nil
                // 记下模式，供「重试」用（见 aiDeep 的注释）
                aiDeep = deep
                aiTitle = L10n.t("airesult.aiReport", deep ? L10n.t("update.deepWord") : L10n.t("update.shallowWord"), project.map { " · " + $0.name } ?? "")
                showAI = true
                do {
                    if let p = project {
                        model.busyProject = p.name
                        let summary = try await model.updateWithAISummary(p, deep: deep)
                        aiResult = summary
                        Notifier.shared.notify(title: deep ? L10n.t("notify.deepDone.title") : L10n.t("notify.shallowDone.title"), body: L10n.t("notify.aiSummary.body"))
                    } else {
                        // ⚠️ 原来直接调 `EngineCLI.shared.updateAll(deep:)`，
                        // **绕过了** AppModel.updateAll 的 `busyAll` 闸门
                        // （那里有 `guard !busyAll else { return false }`）。
                        // 于是这一条路径上的批量更新可以和别的入口并发跑，
                        // 两个 `deepgit update` 同时写文档托管区域与进度库。
                        // 走 model 才有锁、才有刷新、才有通知。
                        _ = await model.updateAll(deep: deep, silent: true)
                        let digest = try await AgentCore.scheduledDigest()
                        aiResult = digest
                        Notifier.shared.notify(title: L10n.t("notify.bulkDone.title"), body: L10n.t("notify.bulkDone.body"))
                    }
                } catch {
                    aiError = EngineError.userMessage(for: error)
                }
                model.busyProject = nil
                aiBusy = false
            } else {
                if let p = project {
                    await model.update(p, deep: deep)
                } else {
                    await model.updateAll(deep: deep)
                }
            }
        }
    }
}

/// 顶栏**双轨主动作**：浅更新 / 深更新。
///
/// 为什么把它们从 `UpdateActionMenu` 里提出来做成两个按钮：
/// 设计稿最突出的元素就是这一对（绿色浅更新 → 箭头 → 紫色深更新），
/// 而原来它们被折叠在一个写着「更新」的下拉里 ——
/// 整个应用最常做的两个动作，用户得先点开菜单才能看见。
///
/// 两个不能省的细节：
///   · **标题带范围**（「浅更新 · 全部」/「浅更新 · deepGit」）：
///     同一个按钮在两种范围下动作完全不同，不写清楚用户按下前无从知道会动谁。
///   · **深更新写明会动哪些托管文档**：这是不可逆的一步（会改用户的文件），
///     动手前必须让用户看见它要写哪几个。
///
/// ⚠️ **「待记录 N」徽章的前世**：这个徽章我画过一次又撤掉了。
/// 撤的理由是它**拿不到真数** —— 引擎的 status 当时读的是进度库里存的快照，
/// 而那个快照在 update 算完后立刻归零（`moonGit/src/flow/update.cj:591`），
/// 于是 `pendingCommits` 实质恒为 0，徽章永远不亮。
/// 引擎自己的注释早就承认了（`flow/dashboard.cj:205`）。
/// 现在引擎的 status 改成**实时**计算了（`moonGit/src/flow/status.cj`），
/// 徽章才有意义，所以又装回来 —— 见不变量 89 的前后半段。
struct DualTrackButtons: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let scope = model.updateScope
        let pending = ScopeRules.pending(scope,
                                         allTotal: model.pendingAll,
                                         byProject: model.pendingByProject)
        HStack(spacing: DSSpacing.sm) {
            Button {
                model.runUpdate(deep: false)
            } label: {
                // ⚠️ 用 `Label { title } icon: { … }` 而不是裸 `HStack { Image; Text }`。
                // 语义完全等价（图标在前、标题在后），而 `Label` 是 macOS 按钮的
                // 语义化 label 通路，对 VoiceOver 更友好，项目里其它按钮
                // （详情页的 gitOpButton）也是这么写的。
                //
                // ⚠️ 别把「离屏渲染快照里这个按钮只画得出空白底、画不出文字」
                // 记到这次改动头上：我为此做过对照实验 —— 改成 `Label` 之后
                // 快照里**仍然**是白框，而同一张图里 gitOpButton 的文字正常。
                // 所以那是离屏环境对 header 位置按钮的已知限制
                // （见 scripts/render-harness/main.swift 顶部的边界说明），
                // 与 label 结构无关。要判断按钮对不对，得看真窗口。
                Label {
                    HStack(spacing: 5) {
                        Text(ScopeRules.shallowLabel(scope))
                        // 只在真有东西时出现。恒显的 0 徽章会被无视，
                        // 而「0」还容易被读成「引擎说不用更新」。
                        if pending > 0 {
                            Text("\(pending)")
                                .font(.caption2.weight(.bold))
                                .monospacedDigit()
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(DSColor.shallow, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                } icon: {
                    Image(systemName: "bolt.fill")
                }
            }
            .disabled(model.updateScopeBusy)
            .help(L10n.t("menu.shallow.help", pending, ShortcutMap.shallow.display))
            .accessibilityLabel(A11y.label(
                ScopeRules.shallowLabel(scope, en: L10n.shared.language.usesEnglishFacts),
                value: pending > 0 ? L10n.t("menu.shallow.a11y.value", pending) : L10n.t("menu.shallow.a11y.none")))

            Button {
                model.runUpdate(deep: true)
            } label: {
                Label {
                    Text(ScopeRules.deepLabel(scope))
                } icon: {
                    Image(systemName: "wand.and.stars")
                }
            }
            .disabled(model.updateScopeBusy)
            .help(L10n.t("menu.deep.help", ScopeRules.deepTouches, ShortcutMap.deep.display))
            .accessibilityLabel(A11y.label(
                ScopeRules.deepLabel(scope),
                value: L10n.t("menu.deep.a11y.value", ScopeRules.deepTouches)))

            if model.updateScopeBusy {
                ProgressView().controlSize(.small)
            }
        }
    }
}

/// 定时更新间隔选择
struct ScheduleMenu: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Picker(L10n.t("schedule.label"), selection: Binding(
            get: { model.autoUpdateHours },
            set: { model.setAutoUpdate(hours: $0) }
        )) {
            Text(L10n.t("schedule.off")).tag(0)
            Text(L10n.t("schedule.h1")).tag(1)
            Text(L10n.t("schedule.h3")).tag(3)
            Text(L10n.t("schedule.h6")).tag(6)
            Text(L10n.t("schedule.h12")).tag(12)
            Text(L10n.t("schedule.h24")).tag(24)
        }
    }
}

// MARK: - 一键项目群说明按钮

struct GroupBriefButton: View {
    @EnvironmentObject var model: AppModel
    @State private var show = false
    @State private var busy = false
    @State private var result = ""
    @State private var errorText: String?

    var body: some View {
        Button {
            generate()
        } label: {
            HStack(spacing: 5) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(L10n.t("brief.button"))
            }
        }
        .disabled(busy)
        .help(L10n.t("brief.help"))
        .accessibilityLabel(A11y.label(L10n.t("brief.help")))
        .sheet(isPresented: $show) {
            AIResultSheet(
                title: "项目群说明",
                markdown: result,
                busy: busy,
                errorText: errorText,
                onRegenerate: { generate() }
            )
        }
    }

    private func generate() {
        busy = true
        errorText = nil
        result = ""
        show = true
        Task {
            do {
                result = try await model.askAgent(
                    "生成一份项目群说明（markdown）：项目构成与定位、各项目一句话现状、需要人处理的事项（未提交/停滞/待合入）、整体建议。400 字以内。",
                    target: .group
                )
            } catch {
                errorText = EngineError.userMessage(for: error)
            }
            busy = false
        }
    }
}

// MARK: - 一键项目说明按钮

struct ProjectBriefButton: View {
    @EnvironmentObject var model: AppModel
    let project: ProjectStatus
    @State private var show = false
    @State private var busy = false
    @State private var result = ""
    @State private var errorText: String?

    var body: some View {
        Button {
            generate()
        } label: {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Label("项目说明", systemImage: "sparkles")
            }
        }
        .disabled(busy)
        .help(L10n.t("brief.project.help"))
        .accessibilityLabel(A11y.label(L10n.t("brief.project.help")))
        .sheet(isPresented: $show) {
            AIResultSheet(
                title: L10n.t("brief.projectTitle", project.name),
                markdown: result,
                busy: busy,
                errorText: errorText,
                onRegenerate: { generate() }
            )
        }
    }

    private func generate() {
        busy = true
        errorText = nil
        result = ""
        show = true
        Task {
            do {
                result = try await model.projectBrief(for: project)
            } catch {
                errorText = EngineError.userMessage(for: error)
            }
            busy = false
        }
    }
}
