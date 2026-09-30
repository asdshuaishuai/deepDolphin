// ScanSheet.swift — 添加项目 / 批量扫描目录。
import SwiftUI

struct ScanSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode = 0
    @State private var singlePath = ""
    @State private var singleName = ""
    @State private var scanRoot = ""
    @State private var scanDepth = 2
    @State private var busy = false
    @State private var results: [String] = []
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("添加单个项目").tag(0)
                Text("批量扫描目录").tag(1)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 16)

            Form {
                if mode == 0 {
                    Section("项目路径") {
                        TextField("/path/to/project", text: $singlePath)
                            .textFieldStyle(.roundedBorder)
                        TextField("项目名（可选）", text: $singleName)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    Section("扫描根目录") {
                        TextField("/path/to/parent/dir", text: $scanRoot)
                            .textFieldStyle(.roundedBorder)
                        Stepper("扫描深度：\(scanDepth) 层", value: $scanDepth, in: 1...6)
                    }
                }
                if !results.isEmpty {
                    Section("结果") {
                        ForEach(results, id: \.self) { line in
                            Text(line).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let err = errorText {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(mode == 0 ? "添加" : "扫描") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || (mode == 0 ? singlePath.isEmpty : scanRoot.isEmpty))
                    .padding(.leading, 8)
            }
            .padding()
        }
        .frame(width: 480, height: 400)
    }

    private func submit() {
        busy = true
        errorText = nil
        results = []
        Task {
            do {
                if mode == 0 {
                    var body: [String: Any] = ["path": singlePath]
                    if !singleName.isEmpty { body["name"] = singleName }
                    let _: Data = try await EngineCLI.shared.addProject(path: singlePath, name: singleName)
                    results = ["已注册"]
                } else {
                    let data = try await EngineCLI.shared.scan(root: scanRoot, depth: scanDepth)
                    if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let added = obj["added"] as? Int ?? 0
                        let existing = obj["existing"] as? Int ?? 0
                        results = ["新增 \(added) 个项目" + (existing > 0 ? "（已存在 \(existing) 个跳过）" : "")]
                    }
                }
                await model.refreshAll()
            } catch {
                errorText = error.localizedDescription
            }
            busy = false
        }
    }
}
