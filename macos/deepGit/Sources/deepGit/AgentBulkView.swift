// AgentBulkView.swift — 顶栏的「一键全量」两个入口 + 结果面板。
//
// 【它和顶栏那对双轨按钮不是同一个东西，界面上必须能分清】
//   双轨「浅更新 · X / 深更新 · X」：范围 = 当前选中（全局或某个仓库），
//                                    执行 = 直接调引擎，不经过 AI
//   这里「全量浅更新 / 全量深更新」：    范围 = 永远所有已注册仓库，
//                                    执行 = 逐个走 agent 工具通道 + AI 简报
// 所以标题里写「全量」而不是「全部」——「全部」会和双轨的「· 全部」撞词，
// 而两个同名按钮动作不同，是最难排查的一类 UI 缺陷。
import SwiftUI

struct AgentBulkButtons: View {
    @EnvironmentObject var model: AppModel

    @State private var report: AgentBulkUpdate.Report?
    @State private var showSheet = false
    @State private var title = ""

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            bulkButton(deep: false)
            bulkButton(deep: true)
        }
        .sheet(isPresented: $showSheet) {
            if let r = report {
                AIResultSheet(
                    title: title,
                    markdown: r.markdown,
                    busy: false,
                    errorText: nil,
                    // 逐仓库结果**不许让模型重生成** —— 那是事实陈述，
                    // 重新生成等于允许「再编一份表」。重跑请回到全量按钮本身。
                    onRegenerate: nil
                )
            }
        }
    }

    private func bulkButton(deep: Bool) -> some View {
        let running = model.agentBulkTrack != nil
        let isThis = model.agentBulkTrack == (deep ? .deep : .shallow)
        let n = model.projects.count
        return Button {
            model.startAgentBulk(deep: deep) { r in
                // ⚠️ 标题里的仓库数**必须取结果里的真值**，不能取点击那一刻的
                // `model.projects.count`。两者会不一样：全量在跑之前会先刷新注册表
                // （否则「全量」冻结的是陈旧名单，见 startAgentBulk 的注释），
                // 所以点下去时看到的 N 可能比实际执行的少。
                // 真 app 实测：标题写「4 个仓库」、正文写「已注册项目 5 个」——
                // 面板自己跟自己打架，而用户没有任何线索该信哪个。
                title = "全量\(deep ? "深度" : "浅")更新 · \(r.attempted) 个仓库"
                report = r
                showSheet = true
            }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                if isThis {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "sparkles")
                }
                Text("全量\(deep ? "深" : "浅")")
                    .font(DSTypography.label)
            }
        }
        .buttonStyle(.bordered)
        .tint(deep ? DSColor.deep : DSColor.shallow)
        // ⚠️ 禁用条件必须包含 `agentBulkTrack != nil`，而不只是「有没有项目」：
        // 「一键全量」自己跑的时候 `busyAll` 也是 true —— 两个按钮一起禁用是对的
        // （不能再并发一批），但**按钮本身要留在原地显示它正在跑哪一轨**，
        // 否则用户只看到两个灰按钮，得靠别处猜现在跑的是浅还是深。
        .disabled(n == 0 || running)
        .help(n == 0
              ? "还没有已注册的项目，先添加或扫描一个"
              : "对**全部 \(n) 个已注册仓库**执行\(deep ? "深度" : "浅")更新，由 AI agent 逐个执行并出简报")
        .accessibilityLabel(A11y.label("全量\(deep ? "深度" : "浅")更新，全部 \(n) 个仓库"))
    }
}
