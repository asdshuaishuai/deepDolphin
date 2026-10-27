// AISettingsView.swift — 设置：通用 / 自动化 / AI 三个分类（页签切换）。
//
// provider/model 选择器由 models.dev 目录填充（含 tool_call/上下文/成本提示）；
// baseURL 默认取目录 api 字段，可覆盖；key 存 macOS 钥匙串。引擎不感知 AI。
import SwiftUI

/// 设置的三个分类。**唯一出处** —— 页签栏的文案、图标、每页内容都从这里来。
///
/// ⚠️ 原来三张卡（开机自启 / 定时更新 / AI 配置）在**一个滚动里平铺**，
///    窗口高度 640 时 AI 那张要滚很久才看得到，而它是设置里最常改的一块。
///    拆成页签是按「用户想找哪一块」分的，不是按卡片分的。
enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general, automation, ai
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:    return "通用"
        case .automation: return "自动化"
        case .ai:         return "AI"
        }
    }

    var symbol: String {
        switch self {
        case .general:    return "gearshape"
        case .automation: return "clock.badge.checkmark"
        case .ai:         return "sparkle"
        }
    }
}

struct GeneralSettingsView: View {
    /// 关闭宿主窗口（PanelWindow 注入）
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var tab: SettingsTab = .general
    /// AI 页的草稿。**唯一真身**：既供 AI 页的输入框编辑，也供页脚保存。
    /// 之所以住在父层，是因为页脚不属于任何一页 —— 拆页签之前保存按钮
    /// 就在 AI 那张卡里，分页后它变成了三页共用的一行。
    @State private var draft = AIConfig()
    /// 打开时加载的那一份。用来判「有没有改动过」——
    /// 没改动就摆一个点不动的「保存」，是本项目反复在修的那族缺陷。
    @State private var original = AIConfig()
    @State private var loadedOnce = false
    @State private var saveProblem: String?

    /// 只有 AI 页有「未保存的改动」——开机自启与定时更新都是**即时写入**
    /// （前者写系统登录项、后者写 AppModel），不存在「取消能回滚」这回事。
    private var aiDirty: Bool { draft != original }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pane
            Divider()
            footer
        }
        // NSHostingView 会按内容最小尺寸收缩窗口：没有最小约束窗口会被压成 0×0。
        //
        // ⚠️ 这两个数字直接决定 sheet 的实际大小 —— 前提是**内容不再反过来撑大它**。
        //    640 → 520 → 480×400：AI 页改成让 `Form` 自己滚之后，内容高度不再外泄，
        //    sheet 才真的缩到 min frame（改之前实测 776×689，页脚被顶出窗口框）。
        //    再往小压，页签栏（标题 + 280 宽的分段控件）会先挤扁，所以 480 是下限附近。
        .frame(minWidth: 480, minHeight: 400)
        .onAppear(perform: load)
    }

    // MARK: 页签栏

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
            Text("设置")
                .font(.title3.weight(.semibold))
            Spacer(minLength: DSSpacing.md)
            Picker("", selection: $tab) {
                ForEach(SettingsTab.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)
            // 分段控件只有控件没有标签：不配无障碍标签，VoiceOver 只会读「未命名」。
            .accessibilityLabel(A11y.label("设置分类"))
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
        .background(DSColor.surfaceAlt)
    }

    // MARK: 内容区

    /// 每页只画**一个**分支。三个分支都在 body 里写全了也不会同时出现，
    /// 但那样「哪一页有哪些控件」就得读三遍代码才看得出来。
    ///
    /// ⚠️ **滚动策略逐页写死，不许统一套一层 ScrollView。**
    ///    `AISettingsPane` 的 `Form` 在 macOS 是 List-backed。把它塞进外层
    ///    `ScrollView`，Form 会把**整份内容高度**报给外层（它自己不当滚动容器用），
    ///    于是：① 外层永远判定「装得下」，滚不动，AI 页下半段够不着；
    ///    ② sheet 被撑到比窗口还高，页脚被顶到窗口框外、压在桌面上。
    ///    实测：窗口 940×672 时 sheet 高 689，页脚落在 y=809、窗口底边 772。
    ///    另两页是普通 VStack，套 ScrollView 没问题，所以只有 AI 页例外。
    @ViewBuilder
    private var pane: some View {
        switch tab {
        case .general:
            ScrollView {
                LoginItemCard()
                    .padding(DSSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .automation:
            ScrollView {
                ScheduleCard()
                    .padding(DSSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .ai:
            // 不套 ScrollView：Form 自己就是滚动容器。
            AISettingsPane(draft: $draft)
        }
    }

    // MARK: 页脚

    private var footer: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            // ⚠️ 保存失败的消息贴在按钮**旁边**，不是塞进某一页里。
            //    失败可能发生在用户已经切走之后 —— 消息跟着页签走就会看不见，
            //    而「点了保存但什么都没发生」是最坏的一种反馈。
            if let saveProblem {
                Label(saveProblem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                // 另两页没有未保存的改动可回滚，按钮写「取消」就是不诚实的 ——
                // 它并不撤销任何东西，只有关闭这一层含义。
                Button(tab == .ai ? "取消" : "关闭") { close() }
                    .keyboardShortcut(.cancelAction)
                if tab == .ai {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                        // 没改动时摆一个点不动的「保存」＝死控件。
                        .disabled(!aiDirty)
                        .padding(.leading, DSSpacing.sm)
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
        .background(DSColor.surfaceAlt)
    }

    // MARK: 存读

    private func load() {
        guard !loadedOnce else { return }
        loadedOnce = true
        var c = AIConfig.load()
        if c.baseURL.isEmpty, let api = ModelCatalog.shared.provider(c.providerID)?.api {
            c.baseURL = api
        }
        // original 存的是**补过 baseURL 之后**的那一份：
        // 「有没有改动」要拿同一基准比，否则一打开就恒为「有改动」。
        draft = c
        original = c
    }

    private func save() {
        // ⚠️ 原来是无条件 `draft().save(); close()` ——
        // 保存完立刻关窗，**任何失败都被关在窗后面**。
        // 现在 save() 会返回失败原因（Keychain 写不进去就是其中一种），
        // 失败时**不关窗**，把原因摆在按钮旁边让用户重试。
        // 静默关窗的成功假象，正是这个项目反复在修的那族缺陷。
        saveProblem = nil
        if let problem = draft.save() {
            saveProblem = problem
            // 出问题的是 AI 页 ⇒ 把用户送回出问题的那一页，
            // 否则他可能停在「自动化」上看着一条与自己无关的报错。
            tab = .ai
            return
        }
        close()
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

/// 开机自启卡片（LoginItem）
struct LoginItemCard: View {
    @State private var enabled = false
    @State private var loaded = false
    /// 设置没生效时的说明（回滚原因）
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Label("开机自启", systemImage: "power")
                .font(.subheadline.weight(.semibold))
            if #available(macOS 13.0, *) {
                Toggle("登录时自动启动 deepDolphin", isOn: $enabled)
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
                        .foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DSSpacing.md)
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

/// 定时更新页。**与通用页同一形态**（grouped Form）——
/// 原来是自绘卡片（surface + 大标题 + 分段选择器），
/// 与旁边的 Form 分组页放在一起就是两种语言。
/// 自动更新是「立即生效」的设置，不走 AI 页的草稿/保存流，
/// 所以这里也不放保存按钮 —— 控件旁的说明把这一点说清楚。
struct ScheduleCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("定时更新") {
                Picker("间隔", selection: Binding(
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
                Text("开启后按间隔对全部项目执行浅更新；AI 已配置时会生成简报并推送通知。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("改完立即生效（此页没有保存按钮）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// AI 配置那一页。**纯呈现** —— 草稿是 `GeneralSettingsView` 持有的 `@Binding`，
/// 因为保存动作在页脚，而页脚不属于任何一页。
///
/// ⚠️ 本页**不许**再自持一份可编辑的 `AIConfig`。
///    父层那份同时供输入框编辑与页脚保存；两份真身必然分叉 ——
///    界面上改的是这一份，存下去的是那一份，而哪里出错不报错。
///
/// 2026-10-13 按用户定稿简化为四段：端点（可选/自定义）、模型（下拉+手输）、
/// API Key、测试。provider 目录退居幕后——选已知端点即选定 provider，
/// 自定义端点沿用当前 provider 的请求格式（OpenAI 兼容）。
struct AISettingsPane: View {
    @Binding var draft: AIConfig
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?
    /// 自定义端点模式（URL 手输；未选中时走下方已知端点下拉）
    @State private var customEndpoint = false

    private var catalogProvider: CatalogProvider? {
        ModelCatalog.shared.provider(draft.providerID)
    }

    /// 目录里的候选模型（tool_call 可用的排前）。
    /// ⚠️ 用户定稿 2026-10-27：模型行 = 一个输入框 + 后面一个下拉，
    /// 与端点行同构——**不做过滤框**（模型目录量级用不着搜索，
    /// 多一个框就多一个要理解的东西）。
    private var modelCandidates: [CatalogModel] {
        guard let p = catalogProvider else { return [] }
        return p.modelWithToolCall + p.models.filter { !$0.toolCall }
    }

    /// 已知端点（目录里有 api 的常用 provider）
    private var knownEndpoints: [(id: String, name: String, api: String)] {
        ModelCatalog.shared.popularProviders().compactMap { p in
            guard let api = p.api, !api.isEmpty else { return nil }
            return (p.id, p.name, api)
        }
    }

    /// 当前端点落在哪个选项上：从草稿反推（磁盘加载也能对上号），
    /// 自定义 = 没有已知端点能同时对上 providerID + baseURL。
    private var endpointKey: String {
        if customEndpoint { return "custom" }
        if let hit = knownEndpoints.first(where: { $0.id == draft.providerID && $0.api == draft.baseURL }) {
            return "p:" + hit.id
        }
        // baseURL 为空 = 还没配过：如果当前 provider 有已知端点就落在它上面
        if draft.baseURL.isEmpty,
           let hit = knownEndpoints.first(where: { $0.id == draft.providerID }) {
            return "p:" + hit.id
        }
        return "custom"
    }

    private func applyEndpoint(_ key: String) {
        if key == "custom" {
            customEndpoint = true
            return
        }
        customEndpoint = false
        let pid = String(key.dropFirst(2))
        guard let p = ModelCatalog.shared.provider(pid) else { return }
        draft.providerID = p.id
        draft.baseURL = p.api ?? ""
        draft.model = ""
    }

    var body: some View {
        Form {
            Section("端点") {
                Picker("端点", selection: Binding(
                    get: { endpointKey },
                    set: { applyEndpoint($0) }
                )) {
                    ForEach(knownEndpoints, id: \.id) { e in
                        Text("\(e.name) — \(e.api)").tag("p:\(e.id)")
                    }
                    Text("自定义…").tag("custom")
                }
                .onChange(of: draft.providerID) { _ in
                    // provider 变了（端点联动）→ 模型重选
                    draft.model = ""
                }
                if customEndpoint || draft.baseURL.isEmpty && knownEndpoints.isEmpty {
                    TextField("https://…/v1", text: $draft.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Text("自定义端点沿用当前请求格式（OpenAI 兼容）。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("模型") {
                // 用户定稿：与端点行同构——一个输入框 + 后面一个下拉，只此一行。
                // 下拉选中即填入输入框；输入框里手打的 id 也合法（tag 兜底行
                // 让下拉显示当前值而不是空白）。
                HStack {
                    TextField("模型 id（可手动输入）", text: $draft.model)
                        .textFieldStyle(.roundedBorder)
                    Picker("模型", selection: Binding(
                        get: { draft.model },
                        set: { draft.model = $0 }
                    )) {
                        Text("（手动输入）").tag("")
                        ForEach(modelCandidates, id: \.id) { m in
                            Text(modelLabel(m)).tag(m.id)
                        }
                        if !draft.model.isEmpty
                            && !modelCandidates.contains(where: { $0.id == draft.model }) {
                            Text(draft.model).tag(draft.model)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 190)
                }
            }

            Section("API Key（存入 macOS 钥匙串）") {
                SecureField(catalogProvider?.id == "ollama" ? "本地服务通常无需 Key" : "sk-…",
                            text: $draft.apiKey)
            }

            Section("测试") {
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
                Text("上下文与工具经引擎本地调用；密钥只存本机钥匙串。注意：项目路径、分支、文档摘要等上下文会发送到你所配置的端点服务器。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func modelLabel(_ m: CatalogModel) -> String {
        var label = "\(m.id)"
        if m.toolCall { label += "  ⚡︎" }
        if m.reasoning { label += "  🧠" }
        if let ctx = m.contextTokens { label += "  · \(ctx / 1000)k" }
        return label
    }

    private func test() async {
        let provider = LanguageModel(config: draft)
        do {
            let reply = try await provider.testConnection()
            testResult = (true, "连通：\(reply.prefix(40))")
        } catch {
            testResult = (false, error.localizedDescription)
        }
        testing = false
    }
}
