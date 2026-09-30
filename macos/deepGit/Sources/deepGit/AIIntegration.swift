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
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("复制 Markdown")
                }
                if let regen = onRegenerate, !busy {
                    Button {
                        regen()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("重新生成")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if busy {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("AI 正在收集引擎事实并生成…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorText {
                VStack(spacing: 8) {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button("重试") { onRegenerate?() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    MarkdownView(text: markdown)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(width: 620, height: 560)
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

    func restartAutoTimer() {
        autoTimer?.invalidate()
        autoTimer = nil
        let hours = autoUpdateHours
        guard hours > 0 else { return }
        autoTimer = Timer.scheduledTimer(withTimeInterval: Double(hours) * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runScheduledUpdate() }
        }
        // 首轮延迟 10 分钟（避免启动即全量更新）
        Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.runScheduledUpdate() }
        }
    }

    func runScheduledUpdate() async {
        guard !busyAll else { return }
        await updateAll(deep: false, silent: true)
        // AI 已配置 → 生成简报并通知
        if AIConfig.load().isConfigured {
            do {
                let digest = try await AgentCore.scheduledDigest()
                Notifier.shared.notify(title: "定时更新简报", body: String(digest.prefix(180)))
            } catch {
                Notifier.shared.notify(title: "定时更新完成", body: "全部项目进度已记录（AI 简报失败：\(error.localizedDescription.prefix(60)))")
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

    var body: some View {
        Menu {
            Button {
                updateAction(deep: false, withAI: false)
            } label: {
                Label("浅更新", systemImage: "arrow.down.circle")
            }
            Button {
                updateAction(deep: false, withAI: true)
            } label: {
                Label("浅更新 + AI 摘要", systemImage: "sparkles")
            }
            Divider()
            Button {
                updateAction(deep: true, withAI: false)
            } label: {
                Label("深度更新", systemImage: "arrow.triangle.branch")
            }
            Button {
                updateAction(deep: true, withAI: true)
            } label: {
                Label("深度更新 + AI 报告", systemImage: "sparkles.rectangle.stack")
            }
            if project == nil {
                Divider()
                ScheduleMenu()
            }
        } label: {
            HStack(spacing: 4) {
                if model.busyAll || (project != nil && model.busyProject == project?.name) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                Text(project == nil ? "更新" : "动作")
            }
        }
        .fixedSize()
        .sheet(isPresented: $showAI) {
            AIResultSheet(
                title: aiTitle,
                markdown: aiResult ?? "",
                busy: aiBusy,
                errorText: aiError,
                onRegenerate: nil
            )
        }
    }

    private func updateAction(deep: Bool, withAI: Bool) {
        Task {
            if withAI {
                aiBusy = true
                aiError = nil
                aiResult = nil
                aiTitle = "\(deep ? "深度更新" : "浅更新")AI 报告\(project.map { " · " + $0.name } ?? "")"
                showAI = true
                do {
                    if let p = project {
                        model.busyProject = p.name
                        let summary = try await model.updateWithAISummary(p, deep: deep)
                        aiResult = summary
                        Notifier.shared.notify(title: deep ? "深度更新完成" : "浅更新完成", body: "AI 摘要已生成")
                    } else {
                        _ = try await EngineCLI.shared.updateAll(deep: deep)
                        await model.refreshAll()
                        let digest = try await AgentCore.scheduledDigest()
                        aiResult = digest
                        Notifier.shared.notify(title: "批量更新完成", body: "AI 简报已生成")
                    }
                } catch {
                    aiError = error.localizedDescription
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

/// 定时更新间隔选择
struct ScheduleMenu: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Picker("定时更新", selection: Binding(
            get: { model.autoUpdateHours },
            set: { model.setAutoUpdate(hours: $0) }
        )) {
            Text("关闭").tag(0)
            Text("每 1 小时").tag(1)
            Text("每 3 小时").tag(3)
            Text("每 6 小时").tag(6)
            Text("每 12 小时").tag(12)
            Text("每 24 小时").tag(24)
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
                Text("项目群说明")
            }
        }
        .disabled(busy)
        .help("AI 生成项目群说明（结合全部项目事实）")
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
                errorText = error.localizedDescription
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
        .help("AI 生成项目说明（结合 README、代码构成与进度事实）")
        .sheet(isPresented: $show) {
            AIResultSheet(
                title: "项目说明 · \(project.name)",
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
                errorText = error.localizedDescription
            }
            busy = false
        }
    }
}
