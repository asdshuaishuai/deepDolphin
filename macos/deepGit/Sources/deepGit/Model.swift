// Model.swift — 应用状态、数据编排与系统集成（通知 / 开机自启）。
import Foundation
import AppKit
import UserNotifications
import ServiceManagement

// MARK: - 通知

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    func setUp() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - 开机自启（SMAppService，macOS 13+）

@available(macOS 13.0, *)
final class LoginItem {
    static let shared = LoginItem()

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("deepgit: 登录项设置失败 \(error)")
        }
    }
}

// MARK: - 导航

enum RootSection: Hashable {
    case dashboard
    case milestones
    case project(String)  // 项目名
}

// MARK: - 应用状态

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // 面板数据
    @Published var projects: [ProjectStatus] = []
    @Published var summary: EngineSummary?
    @Published var dashboard: Dashboard?
    @Published var milestones: [MilestoneItem] = []
    @Published var projectDetails: [String: ProjectStatus] = [:]
    @Published var projectDocs: [String: [DocFile]] = [:]
    @Published var lastGitOpOutput: (ok: Bool, text: String)?

    // UI 状态
    @Published var selection: RootSection? = .dashboard {
        didSet { NSLog("deepgit-bar: selection → \(String(describing: selection))") }
    }
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var engineFound = true
    @Published var serverReady = false
    @Published var lastRefreshed: Date?
    @Published var busyProject: String?
    @Published var busyAll = false

    private var timer: Timer?
    private var notifiedKeys = Set<String>()
    var autoTimer: Timer?

    // MARK: 菜单栏状态项（图标 + 标题 = 实时健康度）

    var menuTitle: String {
        if isLoading && projects.isEmpty { return "⋯" }
        if !engineFound { return "?" }
        if lastError != nil && projects.isEmpty { return "!" }
        var title = "\(projects.count)"
        let stale = summary?.staleProjects
            ?? projects.filter { $0.branches.contains { $0.status == "stale" } }.count
        let dirty = summary?.dirtyProjects
            ?? projects.filter { $0.userDirtyCount > 0 }.count
        if stale > 0 { title += " ⚠︎\(stale)" }
        else if dirty > 0 { title += " ●\(dirty)" }
        return title
    }

    var menuSymbol: String {
        if !engineFound { return "questionmark.circle" }
        if lastError != nil && projects.isEmpty { return "exclamationmark.circle" }
        let stale = summary?.staleProjects ?? 0
        let dirty = summary?.dirtyProjects ?? 0
        if stale > 0 { return "exclamationmark.triangle.fill" }
        if dirty > 0 { return "circle.circle.fill" }
        return "circle.grid.2x2.fill"
    }

    var menuTint: String {
        if !engineFound { return "orange" }
        if lastError != nil && projects.isEmpty { return "red" }
        let stale = summary?.staleProjects ?? 0
        if stale > 0 { return "red" }
        let dirty = summary?.dirtyProjects ?? 0
        if dirty > 0 { return "orange" }
        return "green"
    }

    var summaryLine: String? {
        guard let s = summary else { return nil }
        var parts = ["\(s.projectCount) 项目", "\(s.branchCount) 分支"]
        if s.dirtyProjects > 0 { parts.append("\(s.dirtyProjects) 有改动") }
        if s.staleProjects > 0 { parts.append("\(s.staleProjects) 停滞") }
        return parts.joined(separator: " · ")
    }

    // MARK: 生命周期

    func start() async {
        await refreshAll()
        restartAutoTimer()
        timer?.invalidate()
        // 每 5 分钟轻量刷新（bar 常驻，保持轻量）
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshLight() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        DeepGitEngine.shared.stopServerIfOurs()
    }

    // MARK: 数据加载

    /// 确保引擎服务就绪（发现引擎 → 拉起 serve → 探测 health）
    func ensureReady() async -> Bool {
        if serverReady, await DeepGitEngine.shared.probeServer() { return true }
        if DeepGitEngine.shared.binaryPath == nil {
            DeepGitEngine.shared.refreshBinary()
        }
        engineFound = DeepGitEngine.shared.binaryPath != nil
        guard engineFound else { return false }
        let ok = await DeepGitEngine.shared.ensureServer()
        serverReady = ok
        return ok
    }

    /// 轻量刷新：仅状态（bar 周期任务用）
    func refreshLight() async {
        await fetchStatus(light: true)
    }

    /// 全量刷新：状态 + 仪表盘 + 里程碑（面板打开 / 手动刷新用）
    func refreshAll() async {
        if isLoading { return }
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let ready = await ensureReady()
        guard ready else {
            lastError = EngineError.notFound.localizedDescription
            return
        }

        await fetchStatus(light: false)
        // 冷启动首发容易撞上引擎还在采集：失败后自动补一轮
        if lastError != nil && !projects.isEmpty == false {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            lastError = nil
            await fetchStatus(light: false)
        }
        await fetchDashboard()
        await fetchMilestones()
        lastRefreshed = Date()
        postNotificationsIfNeeded()
    }

    func fetchStatus(light: Bool) async {
        do {
            let env: StatusEnvelope = try await APIClient.shared.get(
                "api/status", query: ["light": light ? "1" : "0"]
            )
            projects = env.projects.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            summary = env.summary
            engineFound = true
        } catch {
            if DeepGitEngine.shared.binaryPath == nil { engineFound = false }
            lastError = error.localizedDescription
        }
    }

    func fetchDashboard() async {
        dashboard = try? await APIClient.shared.get("api/dashboard")
    }

    func fetchMilestones() async {
        if let env: MilestonesEnvelope = try? await APIClient.shared.get("api/milestones") {
            milestones = env.milestones
        }
    }

    /// 单项目完整状态（含 8 条日志），面板详情用
    func loadProject(_ name: String) async {
        do {
            let p: ProjectStatus = try await APIClient.shared.get(
                "api/status", query: ["name": name]
            )
            projectDetails[name] = p
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 项目文档内容（README / AGENTS / CLAUDE 平铺展示用）
    func loadDocs(_ name: String) async {
        do {
            let env: DocsEnvelope = try await APIClient.shared.get(
                "api/docs", query: ["name": name]
            )
            projectDocs[name] = env.docs
        } catch {
            // 文档读取失败不阻塞详情页
        }
    }

    // MARK: git 操作（引擎侧执行，无破坏性命令）

    @discardableResult
    func gitOp(_ project: ProjectStatus, op: String, message: String = "") async -> Bool {
        busyProject = project.name
        defer { busyProject = nil }
        do {
            let data = try await APIClient.shared.post(
                "api/git",
                body: ["project": project.name, "op": op, "message": message]
            )
            let r = try JSONDecoder().decode(GitOpResponse.self, from: data)
            let text = r.output.isEmpty ? (r.ok ? "完成" : "失败") : r.output
            lastGitOpOutput = (r.ok, "[\(r.op)] \(text)")
            await loadProject(project.name)
            await fetchStatus(light: true)
            if r.ok && (op == "commit" || op == "push") {
                Notifier.shared.notify(title: "git \(op) 完成", body: project.name)
            }
            return r.ok
        } catch {
            lastGitOpOutput = (false, "[\(op)] \(error.localizedDescription)")
            return false
        }
    }

    // MARK: 更新动作（引擎侧执行）

    func update(_ project: ProjectStatus, deep: Bool) async {
        busyProject = project.name
        defer { busyProject = nil }
        do {
            let _: Data = try await APIClient.shared.post(
                deep ? "api/deep" : "api/update",
                query: ["name": project.name]
            )
            await refreshAll()
            await loadProject(project.name)
            Notifier.shared.notify(
                title: deep ? "深度更新完成" : "进度已记录",
                body: "\(project.name) 的文档托管区域已刷新"
            )
        } catch {
            lastError = error.localizedDescription
            Notifier.shared.notify(title: "更新失败", body: "\(project.name)：\(error.localizedDescription)")
        }
    }

    func updateAll(deep: Bool, silent: Bool = false) async {
        guard !busyAll else { return }
        busyAll = true
        defer { busyAll = false }
        do {
            let _: Data = try await APIClient.shared.post(deep ? "api/deep" : "api/update")
            await refreshAll()
            if !silent {
                Notifier.shared.notify(
                    title: deep ? "全部深度更新完成" : "全部进度已记录",
                    body: "\(projects.count) 个项目"
                )
            }
        } catch {
            lastError = error.localizedDescription
            if !silent {
                Notifier.shared.notify(title: "批量更新失败", body: error.localizedDescription)
            }
        }
    }

    // MARK: 里程碑动作（引擎侧执行）

    func milestoneAction(_ m: MilestoneItem, action: String) async {
        do {
            let _: Data = try await APIClient.shared.post(
                "api/milestones/action",
                body: ["project": m.projectName, "name": m.name, "action": action]
            )
            await fetchMilestones()
            await fetchDashboard()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addMilestone(project: String, name: String, tag: String, targetDate: String, description: String) async throws {
        var body: [String: Any] = ["project": project, "name": name]
        if !tag.isEmpty { body["tag"] = tag }
        if !targetDate.isEmpty { body["targetDate"] = targetDate }
        if !description.isEmpty { body["description"] = description }
        let _: Data = try await APIClient.shared.post("api/milestones", body: body)
        await fetchMilestones()
        await fetchDashboard()
    }

    // MARK: 提醒策略：只在状态「新变差」时提醒，避免重复打扰

    private func postNotificationsIfNeeded() {
        for p in projects {
            for b in p.branches where b.status == "stale" && !b.isDefault {
                let key = "stale:\(p.id):\(b.name)"
                if !notifiedKeys.contains(key) {
                    notifiedKeys.insert(key)
                    Notifier.shared.notify(
                        title: "分支停滞：\(p.name)",
                        body: "`\(b.name)` 已 \(b.headAgo) 无提交，考虑合并或关闭"
                    )
                }
            }
            if p.userDirtyCount >= 10 {
                let key = "dirty:\(p.id):\(p.userDirtyCount / 10)"
                if !notifiedKeys.contains(key) {
                    notifiedKeys.insert(key)
                    Notifier.shared.notify(
                        title: "未提交改动较多：\(p.name)",
                        body: "\(p.userDirtyCount) 处改动未提交"
                    )
                }
            }
        }
    }
}
