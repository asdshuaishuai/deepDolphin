// Components.swift — 面板与 bar 共用的基础视图件。
import SwiftUI

/// 状态色点
struct StatusDot: View {
    let status: String
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case "active": return .green
        case "idle": return .yellow
        case "stale": return .red
        case "merged": return .purple
        default: return .secondary
        }
    }
}

/// 概览统计卡
struct StatCard: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 分段比例条（提交构成 / 语言分布）
struct SegmentedBar: View {
    struct Segment: Identifiable {
        let label: String
        let value: Double
        let color: Color
        var id: String { label }
    }

    let segments: [Segment]

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.value }, 1)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments) { s in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(s.color)
                        .frame(width: max(geo.size.width * (s.value / total) - 2, 4))
                }
            }
        }
        .frame(height: 12)
    }
}

/// 小圆角标签
struct Chip: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// 卡片容器
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// 空状态
struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 数值颜色
func statTint(_ n: Int) -> Color {
    if n > 0 { return .orange }
    return .primary
}
