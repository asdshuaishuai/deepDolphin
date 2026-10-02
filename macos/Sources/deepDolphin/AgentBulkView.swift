// AgentBulkView.swift — 全量更新的**结果面板**（没有按钮）。
//
// ⚠️ 这个文件原来还画过一对按钮（「全量浅」/「全量深」），2026-10-02 按用户要求删掉了：
//    顶栏双轨在**全局范围**下的标题本来就是「浅更新 · 全部 / 深更新 · 全部」，
//    同一个动作在同一屏里出现两次、措辞还不一样（「全量」vs「· 全部」），
//    用户会以为是两种不同的东西。
//    **删掉的是按钮，不是能力** —— 「全量基于 AI agent 执行」这条要求仍然成立，
//    改由 `AppModel.updateAll` 走 `AgentBulkUpdate.run`（agent 工具通道）实现。
//
// 所以现在这里是：**全量跑完之后，把逐仓库结果摊给用户看**。
// 以前这条路径只有一条聚合通知（「N 个项目已更新」），
// 哪个仓库改了哪些文档、哪个失败了、备份在哪，全都看不见。
import SwiftUI

/// 全量结果面板。由确认框在 `startUpdateAll` 跑完后唤起。
struct AgentBulkResultSheet: View {
    let report: AgentBulkUpdate.Report

    var body: some View {
        AIResultSheet(
            title: "全量\(report.deep ? "深度" : "浅")更新 · \(report.attempted) 个仓库",
            markdown: report.markdown,
            busy: false,
            errorText: nil,
            // 逐仓库结果**不许让模型重生成** —— 那是事实陈述，
            // 重新生成等于允许「再编一份表」。要重跑请回到双轨按钮本身。
            onRegenerate: nil
        )
    }
}
