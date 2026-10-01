// AISettingsView.swift — AI 配置（deepOrca 模式：models.dev 目录驱动）。
//
// provider/model 选择器由 models.dev 目录填充（含 tool_call/上下文/成本提示）；
// baseURL 默认取目录 api 字段，可覆盖；key 存 macOS 钥匙串。引擎不感知 AI。
import SwiftUI

struct GeneralSettingsView: View {
    /// 关闭宿主窗口（PanelWindow 注入）
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    LoginItemCard()
                    ScheduleCard()
                    AISettingsView(onClose: onClose)
                }
                .padding(16)
            }
            .environmentObject(AppModel.shared)  // 覆盖全部子树（ScheduleCard/AISettingsView 都要用）
        }
        // NSHostingView 会按内容最小尺寸收缩窗口：没有最小约束窗口会被压成 0×0
        .frame(minWidth: 540, minHeight: 640)
    }
}

/// 开机自启卡片（复活 LoginItem）
struct LoginItemCard: View {
    @State private var enabled = false
    @State private var loaded = false
    /// 设置没生效时的说明（回滚原因）
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("通用", systemImage: "arrow.clockwise.circle")
                .font(.subheadline.weight(.semibold))
            if #available(macOS 13.0, *) {
                Toggle("登录时自动启动 deepGit", isOn: $enabled)
                    .onChange(of: enabled) { on in
                        if #available(macOS 13.0, *) {
                            LoginItem.shared.setEnabled(on)
                        }
                    }
                Text("通过系统「登录项」注册；菜单栏速览与面板随登录可用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // ⚠️ 原来没有这一段：注册/注销失败只 NSLog 一句，
                // Toggle 仍停在用户点的那一侧 —— **开关说自己知道是假的话**。
                // 用户只能靠重启去发现它压根没生效。
                if let note {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if #available(macOS 13.0, *) {
                enabled = LoginItem.shared.isEnabled
                // 订阅回滚：系统状态与请求不一致时，把 Toggle 拨回**系统的真实状态**
                LoginItem.shared.onLoginItemMismatch = { actual, reason in
                    enabled = actual
                    note = reason
                }
            }
        }
    }
}

/// 定时更新卡片
struct ScheduleCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("自动化", systemImage: "clock.badge.checkmark")
                .font(.subheadline.weight(.semibold))
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
            .pickerStyle(.segmented)
            Text("开启后按间隔对全部项目执行浅更新；AI 已配置时会生成简报并推送通知。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
    }
}

struct AISettingsView: View {
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var providerID = "deepseek"
    @State private var model = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var modelFilter = ""
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    private var catalogProvider: CatalogProvider? {
        ModelCatalog.shared.provider(providerID)
    }

    /// 目录里的候选模型（按过滤词过滤；无过滤词时 tool_call 的排前）
    private var modelCandidates: [CatalogModel] {
        guard let p = catalogProvider else { return [] }
        let q = modelFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let list = q.isEmpty
            ? p.modelWithToolCall + p.models.filter { !$0.toolCall }
            : p.models.filter { $0.id.lowercased().contains(q) || $0.name.lowercased().contains(q) }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Provider（models.dev 目录 · \(ModelCatalog.shared.providers.count) 家）") {
                    // ⚠️ 标题里的 225 与列表里的 40 讲的是**不同的集合**（缺陷 #209）：
                    // 目录 225 家里只有 199 家有可用端点，列表只列前 40 家。
                    // 原来标题零限定词 ⇒ 读成「225 家里随便挑」，而 provider 栏
                    // 又没有过滤框（只有模型栏有），于是那 159 家用户根本选不到。
                    let coverage = ModelCatalog.shared.providerPickerCoverage
                    Picker("Provider", selection: $providerID) {
                        ForEach(ModelCatalog.shared.popularProviders(), id: \.id) { p in
                            Text("\(p.name) (\(p.id))").tag(p.id)
                        }
                        if ModelCatalog.shared.provider(providerID) == nil {
                            Text(providerID).tag(providerID)
                        }
                    }
                    .onChange(of: providerID) { _ in providerChanged() }
                    // 披露恒发：哪怕没被砍（比如目录只有 12 家有端点），
                    // 也不许把「这个数字是什么口径」留给读者猜。
                    if let note = coverage.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LabeledContent("端点") {
                        Text(baseURL.isEmpty ? "（空 — 将在测试时报错）" : baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section("模型") {
                    TextField("过滤模型…", text: $modelFilter)
                        .textFieldStyle(.roundedBorder)
                    Picker("模型", selection: $model) {
                        Text("（手动输入）").tag("")
                        ForEach(modelCandidates, id: \.id) { m in
                            Text(modelLabel(m)).tag(m.id)
                        }
                        if !model.isEmpty && !modelCandidates.contains(where: { $0.id == model }) {
                            Text(model).tag(model)
                        }
                    }
                    if let m = catalogProvider?.model(model) {
                        HStack(spacing: DSSpacing.sm) {
                            if m.toolCall { Chip(text: "tool_call ✓", tint: .green) }
                            if m.reasoning { Chip(text: "reasoning", tint: .purple) }
                            if let ctx = m.contextTokens {
                                Chip(text: "ctx \(ctx / 1000)k", tint: .secondary)
                            }
                            if let cin = m.costInputPerMTok {
                                Chip(text: String(format: "$%.2f/M in", cin), tint: .secondary)
                            }
                        }
                    }
                    TextField("或手动输入模型 id", text: $model)
                        .textFieldStyle(.roundedBorder)
                }

                Section("API Key（存入 macOS 钥匙串）") {
                    SecureField(providerID == "ollama" ? "本地服务通常无需 Key" : "sk-…", text: $apiKey)
                    LabeledContent("Base URL 覆盖") {
                        TextField("留空 = 目录默认", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                }

                Section {
                    HStack {
                        Button("测试连接") {
                            testing = true
                            testResult = nil
                            Task { await test() }
                        }
                        .disabled(testing)
                        if testing {
                            ProgressView().controlSize(.small)
                        }
                        if let r = testResult {
                            Label(r.text, systemImage: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(r.ok ? Color.green : Color.red)
                                .lineLimit(2)
                        }
                    }
                    Text("AI 全部在客户端执行：模型目录来自 models.dev（启动后会联网刷新一次），上下文与工具经引擎本地调用；密钥只存本机钥匙串。注意：项目路径、分支、文档摘要等上下文会发送到你所配置的 provider 服务器。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { close() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .padding(.leading, 8)
            }
            .padding()
        }
        .onAppear(perform: load)
    }

    @State private var loadedOnce = false

    private func load() {
        guard !loadedOnce else { return }
        loadedOnce = true
        let c = AIConfig.load()
        providerID = c.providerID
        model = c.model
        baseURL = c.baseURL
        apiKey = c.apiKey
        if baseURL.isEmpty, let api = catalogProvider?.api {
            baseURL = api
        }
    }

    private func providerChanged() {
        model = ""
        modelFilter = ""
        baseURL = catalogProvider?.api ?? ""
    }

    private func modelLabel(_ m: CatalogModel) -> String {
        var label = "\(m.id)"
        if m.toolCall { label += "  ⚡︎" }
        if m.reasoning { label += "  🧠" }
        if let ctx = m.contextTokens { label += "  · \(ctx / 1000)k" }
        return label
    }

    private func test() async {
        let provider = LanguageModel(config: draft())
        do {
            let reply = try await provider.testConnection()
            testResult = (true, "连通：\(reply.prefix(40))")
        } catch {
            testResult = (false, error.localizedDescription)
        }
        testing = false
    }

    private func draft() -> AIConfig {
        var c = AIConfig()
        c.providerID = providerID
        c.model = model
        c.baseURL = baseURL
        c.apiKey = apiKey
        return c
    }

    private func close() {
        if let onClose { onClose() } else {
            dismiss()
        }
    }

    private func save() {
        // ⚠️ 原来是无条件 `draft().save(); close()` ——
        // 保存完立刻关窗，**任何失败都被关在窗后面**。
        // 现在 save() 会返回失败原因（Keychain 写不进去就是其中一种），
        // 失败时**不关窗**，把原因摆在用户面前让他重试。
        // 静默关窗的成功假象，正是这个项目反复在修的那族缺陷。
        if let problem = draft().save() {
            testResult = (false, problem)
            return
        }
        close()
    }
}
