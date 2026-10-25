// CommitSheetView.swift — 提交弹窗：列出仓库改动、勾选文件、填信息后本地提交。
//
// 数据面是引擎 `git status <项目> --json`（恒发 ok/entries/total/project），
// 提交走 `git commit <项目> --message M --paths a,b` —— 引擎只暂存勾选的路径。
// rename 行的 file 是引擎拼好的 "old -> new"，**原样**传回（引擎拆两侧暂存，
// 已暂存 rename 的旧路径会被引擎自动跳过，见 kernel/git.cj 的判据注释）。
//
// ⚠️ 用户定稿：仓库面板页头的「提交」按钮是提交的**唯一入口**——
// 原来页头下面那张「提交改动」长卡（输入框 + 提交全部）已删除；
// 它的 `git add -A` 口径会把整个工作区提交掉，与「让用户自己选」冲突。
import SwiftUI

struct CommitSheetView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let project: ProjectStatus

    private enum Phase {
        case loading
        case loaded
        case clean
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var entries: [GitStatusEntry] = []
    /// 勾选集，装的是 entry.file（rename 行即整条 "old -> new"）。
    @State private var selected: Set<String> = []
    @State private var message = ""
    @State private var submitting = false

    private var allSelected: Bool { !entries.isEmpty && selected.count == entries.count }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // ── 标题行 ──
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("gitop.commitSheet.title"))
                        .font(.headline)
                    Text(project.name)
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DSColor.textSecondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(A11y.label(L10n.t("common.cancel")))
            }

            // ── 主体：清单 / 干净 / 读失败 ──
            switch phase {
            case .loading:
                VStack(spacing: DSSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("gitop.commitSheet.loading"))
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .clean:
                // 「工作区干净」与「读失败」必须分开：前者是事实，后者是降级。
                EmptyState(
                    icon: "checkmark.circle",
                    title: L10n.t("gitop.commitSheet.clean"),
                    subtitle: ""
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let reason):
                VStack(spacing: DSSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(L10n.t("gitop.commitSheet.readFailed"))
                        .font(.callout.weight(.medium))
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                fileList
            }

            // ── 底部：信息 + 提交 ──
            if case .loaded = phase {
                Divider()
                HStack(spacing: DSSpacing.sm) {
                    Text(L10n.t("gitop.commitSheet.selectedCount", selected.count, entries.count))
                        .font(.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    Button(allSelected ? L10n.t("gitop.commitSheet.deselectAll") : L10n.t("gitop.commitSheet.selectAll")) {
                        if allSelected { selected.removeAll() } else { selected = Set(entries.map(\.file)) }
                    }
                    .controlSize(.small)
                    Spacer()
                    TextField(L10n.t("gitop.commitSheet.messagePlaceholder"), text: $message)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220)
                        .onSubmit { submit() }
                    Button(L10n.t("gitop.commit")) { submit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSubmit)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(DSSpacing.lg)
        .frame(minWidth: 520, minHeight: 380)
        .task { await load() }
    }

    // MARK: 文件清单

    private var fileList: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DSSpacing.xs) {
                    ForEach(entries) { e in
                        row(e)
                    }
                }
            }
        }
    }

    private func row(_ e: GitStatusEntry) -> some View {
        let visual = Self.kindVisual(e.kind)
        return Button {
            if selected.contains(e.file) { selected.remove(e.file) } else { selected.insert(e.file) }
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: selected.contains(e.file) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected.contains(e.file) ? Color.accentColor : DSColor.textSecondary)
                Image(systemName: visual.symbol)
                    .foregroundStyle(visual.tint)
                    .font(.caption)
                Text(e.file)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(visual.label)
                    .font(.caption2)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.t("gitop.commitSheet.xyHelp", e.xy))
        .accessibilityLabel(A11y.label(e.file))
        .accessibilityHint(A11y.label(visual.label))
    }

    private var canSubmit: Bool {
        !submitting
            && !selected.isEmpty
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model.busyProject != project.name
    }

    private func submit() {
        guard canSubmit else { return }
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = entries.filter { selected.contains($0.file) }.map(\.file)
        submitting = true
        Task {
            let ok = await model.gitOp(project, op: "commit", message: msg, paths: paths)
            submitting = false
            if ok {
                dismiss()
            }
            // 失败不关弹窗：结果横幅（lastGitOpOutput）在详情页里，
            // 但用户此刻盯着的是这张弹窗——把失败原因留在原地才看得见。
        }
    }

    // MARK: 数据

    private func load() async {
        guard let payload = await model.fetchGitStatus(project.name) else {
            phase = .failed(model.lastError ?? L10n.t("gitop.commitSheet.readFailed"))
            return
        }
        guard payload.ok else {
            // 引擎对非 git 仓库恒发 ok=false + 说明，不编造成空清单。
            phase = .failed(L10n.t("gitop.commitSheet.readFailed"))
            return
        }
        entries = payload.entries
        selected = Set(entries.map(\.file))
        phase = entries.isEmpty ? .clean : .loaded
    }

    // MARK: kind → 图标/颜色/文案

    struct KindVisual { let symbol: String; let tint: Color; let label: String }

    /// kind 是引擎归一化后的枚举词；未知词渲染成通用文件图标——
    /// 不猜（「不知道」不许编成一个确定状态）。
    static func kindVisual(_ kind: String) -> KindVisual {
        switch kind {
        case "added": return KindVisual(symbol: "plus.circle", tint: .green, label: L10n.t("gitop.kind.added"))
        case "modified": return KindVisual(symbol: "pencil", tint: .orange, label: L10n.t("gitop.kind.modified"))
        case "deleted": return KindVisual(symbol: "trash", tint: .red, label: L10n.t("gitop.kind.deleted"))
        case "untracked": return KindVisual(symbol: "questionmark.circle", tint: .gray, label: L10n.t("gitop.kind.untracked"))
        case "renamed": return KindVisual(symbol: "arrow.triangle.swap", tint: .purple, label: L10n.t("gitop.kind.renamed"))
        case "conflict": return KindVisual(symbol: "exclamationmark.triangle.fill", tint: .red, label: L10n.t("gitop.kind.conflict"))
        case "staged": return KindVisual(symbol: "checkmark.circle", tint: .blue, label: L10n.t("gitop.kind.staged"))
        default: return KindVisual(symbol: "doc", tint: .gray, label: kind)
        }
    }
}
