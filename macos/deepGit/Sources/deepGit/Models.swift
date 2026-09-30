// Models.swift — 与引擎 HTTP API 对齐的契约模型。
//
// 【边界】字段名必须与 engine/src/flow/*.cj 的 JSON 输出严格一致；
// 引擎改键名 = 破坏契约，必须同步改这里（AGENTS.md 有约定）。
import Foundation

// MARK: - 状态（/api/status）

struct EngineSummary: Decodable, Hashable {
    let projectCount: Int
    let activeProjects: Int
    let staleProjects: Int
    let dirtyProjects: Int
    let branchCount: Int
}

struct CommitTypeStat: Decodable, Hashable {
    let type: String
    let count: Int
}

struct MergeHint: Decodable, Hashable {
    let kind: String
    let ahead: Int
    let behind: Int
    let defaultBranch: String
    let target: String
    let description: String
}

struct BranchStatus: Decodable, Identifiable, Hashable {
    let name: String
    let status: String
    let statusLabel: String
    let headShort: String
    let headAgo: String
    let summary: String
    let pendingCommits: Int
    let aheadOfDefault: Int
    let isCurrent: Bool
    let isDefault: Bool

    var id: String { name }
}

struct JournalEntry: Decodable, Identifiable, Hashable {
    let id: String
    let at: String
    let mode: String
    let branch: String
    let summary: String
    let providerLabel: String
    let commitCount: Int

    var modeLabel: String {
        switch mode {
        case "track": return "快照"
        case "shallow": return "浅更新"
        case "deep": return "深度更新"
        case "manual": return "手动"
        default: return mode
        }
    }
}

struct ProjectStatus: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let kind: String
    let remote: String
    let headline: String
    let currentBranch: String
    let defaultBranch: String
    let userDirtyCount: Int
    let untrackedCount: Int
    let stashCount: Int
    let worktreeCount: Int
    let lastCommitAgo: String
    let commitTypes: [CommitTypeStat]?
    let mergeHint: MergeHint?
    let branches: [BranchStatus]
    let journal: [JournalEntry]?
    let error: String?

    var isGit: Bool { kind == "git" }

    /// 工程脉搏（有值得说才返回）
    var pulseLine: String? {
        var parts: [String] = []
        if userDirtyCount > 0 { parts.append("未提交 \(userDirtyCount)") }
        if untrackedCount > 0 { parts.append("未跟踪 \(untrackedCount)") }
        if stashCount > 0 { parts.append("stash \(stashCount)") }
        if worktreeCount > 1 { parts.append("工作区 ×\(worktreeCount)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var commitTypeLine: String? {
        guard let types = commitTypes, !types.isEmpty else { return nil }
        return types.prefix(5).map { "\($0.type) ×\($0.count)" }.joined(separator: " · ")
    }
}

struct StatusEnvelope: Decodable {
    let projects: [ProjectStatus]
    let summary: EngineSummary?
}

// MARK: - 仪表盘（/api/dashboard）

struct DashboardProjects: Decodable, Hashable {
    let total: Int
    let dirty: Int
    let active7d: Int
    let active30d: Int
}

struct DashboardWork: Decodable, Hashable {
    let branches: Int
    let mergeCandidates: Int
    let untrackedFiles: Int
    let stashes: Int
}

struct LanguageStat: Decodable, Hashable {
    let language: String
    let count: Int
}

struct MilestoneCounts: Decodable, Hashable {
    let open: Int
    let done: Int
    let dropped: Int
}

struct MilestoneItem: Decodable, Identifiable, Hashable {
    let projectId: String
    let projectName: String
    let name: String
    let description: String
    let status: String
    let targetDate: String
    let daysToTarget: Int
    let overdue: Bool
    let tag: String
    let tagReached: Bool
    let commitsSince: Int

    var id: String { "\(projectId)/\(name)" }

    var statusLabel: String {
        if status == "done" { return "已达成" }
        if status == "dropped" { return "已放弃" }
        return overdue ? "已逾期" : "进行中"
    }

    /// 目标日期描述：还剩 N 天 / 逾期 N 天 / 无
    var dueText: String {
        guard !targetDate.isEmpty, daysToTarget != -1 else { return "" }
        if daysToTarget >= 0 { return "还剩 \(daysToTarget) 天" }
        return "逾期 \(-daysToTarget) 天"
    }
}

struct DashboardMilestones: Decodable, Hashable {
    let counts: MilestoneCounts
    let items: [MilestoneItem]
}

struct ActiveProject: Decodable, Hashable {
    let name: String
    let lastCommitAgo: String
    let headline: String
}

struct Dashboard: Decodable {
    let projects: DashboardProjects
    let work: DashboardWork
    let languages: [LanguageStat]
    let milestones: DashboardMilestones
    let activeProjects: [ActiveProject]
    let fetchedAt: String
}

struct MilestonesEnvelope: Decodable {
    let milestones: [MilestoneItem]
}

// MARK: - 展示辅助

/// 统一的状态色：active 绿 / idle 黄 / stale 红 / merged 紫
enum StatusColor {
    static func systemColor(for status: String) -> String {
        switch status {
        case "active": return "green"
        case "idle": return "yellow"
        case "stale": return "red"
        case "merged": return "purple"
        default: return "gray"
        }
    }
}

// MARK: - 项目文档（/api/docs）

struct DocFile: Decodable, Identifiable, Hashable {
    let file: String
    let content: String

    var id: String { file }
}

struct DocsEnvelope: Decodable {
    let project: String
    let docs: [DocFile]
}

// MARK: - git 操作（POST /api/git）

struct GitOpResponse: Decodable {
    let op: String
    let ok: Bool
    let output: String
    let project: String?
}
