// MilestonesView.swift — 里程碑管理页。
// 行内直操作：点击行跳项目；··· 菜单 = 达成/重开/放弃/打开项目/删除（右键同效）。
import SwiftUI

struct MilestonesView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAddSheet = false

    var body: some View {
        Group {
            if model.milestones.isEmpty {
                EmptyState(
                    icon: "flag.2.crossed",
                    title: "暂无里程碑",
                    subtitle: "里程碑绑定 git tag 后，tag 出现即自动判定达成"
                )
            } else {
                List {
                    Section {
                        ForEach(model.milestones) { m in
                            MilestoneRow(milestone: m)
                        }
                    } header: {
                        HStack {
                            Text("全部里程碑（\(model.milestones.count)）")
                            Spacer()
                            if let c = model.dashboard?.milestones.counts {
                                Text("进行中 \(c.open) · 已达成 \(c.done) · 已放弃 \(c.dropped)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("里程碑")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("新建里程碑", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMilestoneSheet()
                .environmentObject(model)
        }
        .task { await model.fetchMilestones() }
    }
}

// MARK: - 行

struct MilestoneRow: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var model: AppModel
    let milestone: MilestoneItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconTint)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(milestone.projectName)
                        .foregroundStyle(.secondary)
                    Text(milestone.name)
                        .font(.headline)
                    if milestone.tagReached {
                        Chip(text: "tag ✓", tint: .green)
                    }
                }
                if !milestone.description.isEmpty {
                    Text(milestone.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    if !milestone.tag.isEmpty && !milestone.tagReached {
                        Text("tag \(milestone.tag)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if milestone.commitsSince > 0 {
                        Text("创建以来 \(milestone.commitsSince) 提交")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(milestone.statusLabel)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(statusTint)
                if !milestone.dueText.isEmpty {
                    Text("目标 \(milestone.targetDate) · \(milestone.dueText)")
                        .font(.caption2)
                        .foregroundStyle(milestone.overdue ? .red : .secondary)
                } else if !milestone.targetDate.isEmpty {
                    Text("目标 \(milestone.targetDate)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // 行内直达按钮（不用 Menu：List 行内 Menu 命中率不可靠）
            HStack(spacing: 2) {
                if milestone.status == "open" {
                    actionButton("达成", "checkmark.circle.fill", .green) {
                        Task { await model.milestoneAction(milestone, action: "done") }
                    }
                }
                if milestone.status != "open" {
                    actionButton("重开", "arrow.counterclockwise.circle.fill", .blue) {
                        Task { await model.milestoneAction(milestone, action: "reopen") }
                    }
                }
                actionButton("删除", "trash.fill", .red) {
                    Task { await model.milestoneAction(milestone, action: "remove") }
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                model.selection = .project(milestone.projectName)
                openWindow(id: "panel")
                await model.loadProject(milestone.projectName)
            }
        }
        .contextMenu { rowActions }
    }

    @ViewBuilder
    private var rowActions: some View {
        if milestone.status != "done" {
            Button("标记达成") { Task { await model.milestoneAction(milestone, action: "done") } }
        }
        if milestone.status != "open" {
            Button("重新打开") { Task { await model.milestoneAction(milestone, action: "reopen") } }
        }
        if milestone.status != "dropped" {
            Button("放弃") { Task { await model.milestoneAction(milestone, action: "drop") } }
        }
        Divider()
        Button("打开项目") {
            Task {
                model.selection = .project(milestone.projectName)
                openWindow(id: "panel")
                await model.loadProject(milestone.projectName)
            }
        }
        Divider()
        Button("删除", role: .destructive) { Task { await model.milestoneAction(milestone, action: "remove") } }
    }

    private func actionButton(_ label: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .foregroundStyle(tint.opacity(0.75))
                .font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private var icon: String {
        if milestone.status == "done" { return "checkmark.circle.fill" }
        if milestone.status == "dropped" { return "xmark.circle" }
        return milestone.overdue ? "exclamationmark.circle.fill" : "circle.dashed"
    }

    private var iconTint: Color {
        if milestone.status == "done" { return .green }
        if milestone.status == "dropped" { return .secondary }
        return milestone.overdue ? .red : .blue
    }

    private var statusTint: Color {
        if milestone.status == "done" { return .green }
        if milestone.status == "dropped" { return .secondary }
        return milestone.overdue ? .red : .primary
    }
}

// MARK: - 新建里程碑

struct AddMilestoneSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var project = ""
    @State private var name = ""
    @State private var tag = ""
    @State private var hasDate = false
    @State private var date = Date().addingTimeInterval(30 * 86400)
    @State private var desc = ""
    @State private var submitting = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("项目", selection: $project) {
                    ForEach(model.projects) { p in
                        Text(p.name).tag(p.name)
                    }
                }
                TextField("名称（如 v1.0）", text: $name)
                TextField("绑定 tag（可选，tag 存在即自动达成）", text: $tag)
                Toggle("设定目标日期", isOn: $hasDate)
                if hasDate {
                    DatePicker("目标日期", selection: $date, displayedComponents: .date)
                }
                TextField("描述（可选）", text: $desc)
            }
            .formStyle(.grouped)

            if let err = errorText {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(project.isEmpty || name.isEmpty || submitting)
                    .padding(.leading, 8)
            }
            .padding()
        }
        .frame(width: 440, height: 340)
        .onAppear {
            if project.isEmpty {
                project = model.selection.flatMap {
                    if case .project(let name) = $0 { return name }
                    return nil
                } ?? model.projects.first?.name ?? ""
            }
        }
    }

    private func submit() {
        submitting = true
        errorText = nil
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        Task {
            do {
                try await model.addMilestone(
                    project: project,
                    name: name,
                    tag: tag,
                    targetDate: hasDate ? formatter.string(from: date) : "",
                    description: desc
                )
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            submitting = false
        }
    }
}
