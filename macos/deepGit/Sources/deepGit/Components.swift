// Components.swift — 面板与 bar 共用的基础视图件。
import SwiftUI

/// 状态色点
struct StatusDot: View {
    let status: String
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            // 8pt 的点没有文字替代，VoiceOver 只能靠标签
            .accessibilityElement()
            .accessibilityLabel("状态")
            .accessibilityValue(DSStatus.from(status).label)
    }

    private var color: Color {
        DSColor.color(DSStatus.from(status))
    }
}

/// 概览统计卡
struct StatCard: View {
    let label: String
    let value: String
    var tint: Color = .primary
    var icon: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text(value)
                    .font(DSTypography.metric)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .foregroundStyle(tint.opacity(0.55))
                        .font(DSTypography.label)
                }
            }
            Text(label)
                .font(DSTypography.label)
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.md)
        .surface()
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
                    RoundedRectangle(cornerRadius: DSRadius.chip)
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
                .font(DSTypography.cardTitle)
                .foregroundStyle(DSColor.textSecondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.md)
        .surface()
    }
}

/// 空状态
struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String = ""

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(DSTypography.label)
                    .foregroundStyle(DSColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 数值颜色。
///
/// 【行为已改】原来是「任何 n>0 都橙」——1 个未提交文件和 300 个同色，等于没分级。
/// 现在按量级分四档，负数（数据本身有问题）按最严重处理，宁可说「要处理」也不说「干净」。
/// 判据在 Tests/ClientCheck 的「数值必须按量级分档」那条。
func statTint(_ n: Int) -> Color {
    DSColor.color(DSStat.from(n))
}
