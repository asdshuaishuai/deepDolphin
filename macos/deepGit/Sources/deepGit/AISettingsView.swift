// AISettingsView.swift — AI 配置（deepOrca 模式：models.dev 目录驱动）。
//
// provider/model 选择器由 models.dev 目录填充（含 tool_call/上下文/成本提示）；
// baseURL 默认取目录 api 字段，可覆盖；key 存 macOS 钥匙串。引擎不感知 AI。
import SwiftUI

struct AISettingsView: View {
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
                    Picker("Provider", selection: $providerID) {
                        ForEach(ModelCatalog.shared.popularProviders(), id: \.id) { p in
                            Text("\(p.name) (\(p.id))").tag(p.id)
                        }
                        if ModelCatalog.shared.provider(providerID) == nil {
                            Text(providerID).tag(providerID)
                        }
                    }
                    .onChange(of: providerID) { _ in providerChanged() }

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
                        HStack(spacing: 8) {
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
                    Text("AI 全部在客户端执行（deepDesign 模式）：模型目录来自 models.dev，上下文来自引擎 /api/context，工具经引擎 HTTP API 执行；密钥只存本机钥匙串。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .padding(.leading, 8)
            }
            .padding()
        }
        .frame(width: 520, height: 560)
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

    private func save() {
        draft().save()
        dismiss()
    }
}
