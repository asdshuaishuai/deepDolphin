// ScanSheet.swift — 添加项目 / 批量扫描目录。
//
// ⚠️ 原来两个路径字段都是**纯手打 TextField** —— 在 macOS 上让用户
// 敲 `/Users/xxx/Developer/某个项目` 是把 Finder 能做的事推给用户。
// 而且提交前不做任何整理：实测引擎对 `"  /path  "`（首尾空格）直接失败，
// 且报错把两个路径拼在一起，完全指不出错在哪。
//
// 现在：`PathInput` 负责判定（纯函数，可测），这里负责取路径与呈现。
import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @State private var dropTargeted = false
    @State private var work: Task<Void, Never>?

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
                        pathRow(text: $singlePath,
                                placeholder: "选择一个 git 仓库文件夹",
                                problem: problemFor(singlePath))
                        TextField("项目名（可选）", text: $singleName)
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    Section("扫描根目录") {
                        pathRow(text: $scanRoot,
                                placeholder: "选择要扫描的父目录",
                                problem: problemFor(scanRoot))
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
                Button("取消") {
                    work?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(mode == 0 ? "添加" : "扫描") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || currentProblem != nil)
                    .padding(.leading, 8)
            }
            .padding()
        }
        .frame(width: 480, height: 440)
        .onDisappear { work?.cancel() }
    }

    // MARK: - 路径输入

    /// 当前模式下用户填的路径。
    private var currentPath: String { mode == 0 ? singlePath : scanRoot }

    /// 当前路径的判定结论。**按钮的可用性直接挂在它上面** ——
    /// 原来只看 `isEmpty`，于是打错路径也能点提交，点了才弹一句看不懂的错。
    private var currentProblem: String? {
        if currentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return problemFor(currentPath)
    }

    private func problemFor(_ raw: String) -> String? {
        let p = PathInput.validateScanRoot(raw, classify: Self.classify)
        return p.problem
    }

    /// 磁盘三态。**不要退回 Bool** —— 那样"不存在"和"是文件"会被压成
    /// 同一句"不是文件夹"，用户拿着错误信息去排查方向就错了。
    private static func classify(_ path: String) -> PathKind {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            return .missing
        }
        return isDir.boolValue ? .directory : .file
    }

    /// 一个路径行：可编辑文本框 + 「选择…」按钮 + 判定提示 + 拖放。
    @ViewBuilder
    private func pathRow(text: Binding<String>,
                         placeholder: String,
                         problem: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                Button("选择…") { choosePath(into: text) }
                    .disabled(busy)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            // 闭包必须返回 Bool。返回 true = 「我接了」——
            // 后续取 URL 是异步的，但拖放事件本身已经被接收，
            // 返回 false 会让系统认为没人要而拒绝这一拖。
            loadFirstDirectory(from: providers, into: text, error: $errorText)
            return true
        }
    }

    private func choosePath(into binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        // 从当前已填的路径起步：重新挑一个相邻项目时省一次导航。
        let current = PathInput.prepare(binding.wrappedValue)
        if current.isUsable { panel.directoryURL = URL(fileURLWithPath: current.path) }
        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        }
    }

    /// 取拖放内容里第一个文件夹，回填到输入框；取不到就把原因说清楚。
    ///
    /// ⚠️ 这里刻意**不捕获 self**：ScanSheet 是 struct，`[weak self]` 根本不合法
    /// （编译器会直接拒绝），而强捕获一个视图快照跨越异步边界也没意义。
    /// 需要的只有两个 Binding 和一个 static 方法 —— 刚好都不依赖实例。
    private func loadFirstDirectory(from providers: [NSItemProvider],
                                    into binding: Binding<String>,
                                    error: Binding<String?>) {
        let group = DispatchGroup()
        var resolved: [String] = []
        let lock = NSLock()
        for p in providers {
            guard p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            group.enter()
            _ = p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                let url: URL? = {
                    if let d = item as? Data { return URL(dataRepresentation: d, relativeTo: nil) }
                    if let u = item as? URL { return u }
                    return nil
                }()
                if let u = url {
                    lock.lock(); resolved.append(u.path); lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            let p = PathInput.pickDirectory(among: resolved, classify: Self.classify)
            if p.isUsable {
                binding.wrappedValue = p.path
                error.wrappedValue = nil
            } else {
                error.wrappedValue = p.problem
            }
        }
    }

    // MARK: - 提交

    private func submit() {
        let raw = currentPath
        let prepared = PathInput.validateScanRoot(raw, classify: Self.classify)
        guard prepared.isUsable else {
            // 按钮本该是禁用的；这里仍然兜一道，
            // 因为 Esc 之外还有别的入口（拖放、粘贴）能改这个字段。
            errorText = prepared.problem
            return
        }
        busy = true
        errorText = nil
        results = []

        work?.cancel()
        work = Task {
            defer { busy = false }
            do {
                if mode == 0 {
                    // ⚠️ 原来这里先造了个 `body` 字典（意图是"name 为空就不发 name 键"），
                    // 然后**一次都没用**，直接把 singleName 传了下去。
                    // 好在 EngineCLI.addProject 本来就处理了这件事，
                    // 所以行为没错 —— 但那段死代码会让人以为"发的是 body"，
                    // 改 EngineCLI 时就可能改错地方。删掉。
                    _ = try await EngineCLI.shared.addProject(path: prepared.path, name: singleName)
                    results = ["已注册 \(prepared.path)"]
                } else {
                    let data = try await EngineCLI.shared.scan(root: prepared.path, depth: scanDepth)
                    if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let added = obj["added"] as? Int ?? 0
                        let existing = obj["existing"] as? Int ?? 0
                        let found = obj["found"] as? Int ?? 0
                        let cov = ScanCoverage.input(from: obj)
                        let note = ScanCoverage.note(cov)
                        // 披露分母：只说"新增 0 个"会被读成"扫过了但没有仓库"，
                        // 而"扫了 120 个目录一个都没有"是完全不同的两件事。
                        var line = "新增 \(added) 个 / 共发现 \(found) 个"
                        if existing > 0 { line += "（已存在 \(existing) 个跳过）" }
                        // ⚠️ 「该目录树里没有 git 仓库」**只在真的扫完时才许说**。
                        // 本表默认深度就是 2，扫一棵仓库在第 4 层的树 →
                        //   found=0、depthCapped=true
                        // 原来无条件加这一句，等于替用户断言了一个引擎没验证过的结论
                        // （引擎侧缺陷 #197 的**第二个出口**）。
                        //
                        // ⚠️ 「没扫完」和「没有」不许并排出现：那两句会互相拆台，
                        // 用户读完不知道该信哪个。所以 note 存在时不加这句 ——
                        // note 自己会把「只代表已访问的那部分里没有」说清楚。
                        if found == 0 && note == nil { line += " —— 该目录树里没有 git 仓库" }
                        if let note { line += "\n" + note }
                        results = [line]
                    }
                }
                await model.refreshAll()
            } catch {
                errorText = EngineError.userMessage(for: error)
            }
        }
    }
}
