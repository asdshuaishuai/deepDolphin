// AISettingsView.swift — AI 配置（客户端 AI 层的设置界面）。
//
// key 存 macOS Keychain；其余存 UserDefaults。引擎不感知 AI。
import SwiftUI

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var preset: AIPreset = .deepseek
    @State private var model = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Provider") {
                    Picker("预设", selection: $preset) {
                        ForEach(AIPreset.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .onChange(of: preset) { _ in
                        // 切预设时带出默认值（用户可再改）
                        if baseURL.isEmpty || baseURL == previousDefaultBase {
                            baseURL = preset.defaultBaseURL
                        }
                        previousDefaultBase = preset.defaultBaseURL
                    }
                    TextField("模型（如 deepseek-chat）", text: $model)
                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                }
                Section("API Key（存入 macOS 钥匙串）") {
                    SecureField(preset == .ollama ? "本地服务通常无需 Key" : "sk-…", text: $apiKey)
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
                    Text("AI 全部在客户端执行：上下文来自引擎（/api/context），工具通过引擎 HTTP API 执行，密钥只存在本机钥匙串。")
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
        .frame(width: 480, height: 430)
        .onAppear {
            let c = AIConfig.load()
            preset = c.preset
            model = c.model
            baseURL = c.baseURL
            apiKey = c.apiKey
            previousDefaultBase = preset.defaultBaseURL
        }

    }

    @State private var previousDefaultBase = ""

    private func test() async {
        var c = AIConfig.load()
        c.preset = preset
        c.model = model
        c.baseURL = baseURL
        c.apiKey = apiKey
        let provider = AIProvider(config: c)
        do {
            let reply = try await provider.testConnection()
            testResult = (true, "连通：\(reply.prefix(40))")
        } catch {
            testResult = (false, error.localizedDescription)
        }
        testing = false
    }

    private func save() {
        var c = AIConfig.load()
        c.preset = preset
        c.model = model
        c.baseURL = baseURL
        c.apiKey = apiKey
        c.save()
        dismiss()
    }
}
