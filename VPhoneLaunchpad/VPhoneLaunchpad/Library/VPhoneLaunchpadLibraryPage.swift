import SwiftUI
import VPhoneDesignKit

// MARK: - Page

/// The frame of a Library page: the DesignKit header, then the sections in a
/// scrolling column on the window ground (`.dk-content`, or with `roomy`,
/// `.dk-content--roomy`).
struct VPhoneLaunchpadLibraryPage<Tools: View, Content: View>: View {
    let title: String
    let subtitle: String?
    let roomy: Bool
    let tools: Tools
    let content: Content

    init(
        _ title: String,
        subtitle: String?,
        roomy: Bool = false,
        @ViewBuilder tools: () -> Tools,
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.roomy = roomy
        self.tools = tools()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            DKPageHeader(title, subtitle: subtitle) {
                tools
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: roomy ? DK.Space.s8 : DK.Space.s6) {
                    content
                }
                .padding(roomy ? DK.Space.s6 : DK.Space.s5)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .font(DK.Typeface.body)
        .foregroundStyle(DK.Palette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DK.Palette.window)
    }
}

// MARK: - Placeholder

/// A muted line inside a card while the page reads the disk, or when a list
/// is empty.
struct VPhoneLaunchpadLibraryNote: View {
    let text: String
    var isWorking = false

    var body: some View {
        HStack(spacing: DK.Space.s2) {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Text(text)
                .foregroundStyle(DK.Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DK.Space.s3)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight, alignment: .leading)
    }
}

// MARK: - Usage bar

/// One share of a stacked usage bar, with its legend entry.
struct VPhoneLaunchpadUsagePart: Identifiable, Hashable {
    var label: String
    var bytes: Int64
    var color: Color

    var id: String {
        label
    }
}

/// The Disks page's stacked bar: one 12pt track split into the parts by size,
/// 2pt apart, under a legend of colored squares, labels and sizes.
/// DesignKit has a single-value meter only (`DKTableCell.bar`).
struct VPhoneLaunchpadUsageBar: View {
    let parts: [VPhoneLaunchpadUsagePart]

    private var shown: [VPhoneLaunchpadUsagePart] {
        parts.filter { $0.bytes > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            bar
            legend
        }
    }

    private var bar: some View {
        let shown = shown
        let total = max(1, shown.reduce(Int64(0)) { $0 + $1.bytes })
        return GeometryReader { proxy in
            let gaps = CGFloat(max(0, shown.count - 1)) * 2
            let width = max(0, proxy.size.width - gaps)
            HStack(spacing: 2) {
                ForEach(shown) { part in
                    Rectangle()
                        .fill(part.color)
                        // Every part stays visible, however small.
                        .frame(width: max(2, width * CGFloat(part.bytes) / CGFloat(total)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 12)
        .background(DK.Palette.track)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(shown.map { "\($0.label) \(VPhoneLaunchpadLibraryFormat.size($0.bytes))" }.joined(separator: ", "))
    }

    private var legend: some View {
        VPhoneLaunchpadFlowLayout(horizontalSpacing: DK.Space.s6, verticalSpacing: DK.Space.s2) {
            ForEach(shown) { part in
                HStack(spacing: DK.Space.s2) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(part.color)
                        .frame(width: 10, height: 10)
                    Text(part.label)
                    Text(VPhoneLaunchpadLibraryFormat.size(part.bytes))
                        .foregroundStyle(DK.Palette.muted)
                        .monospacedDigit()
                }
                .fixedSize()
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Figures

/// A caption over a large figure: "Used by ~/.vphone/machines" over "166 GB".
struct VPhoneLaunchpadUsageFigure: View {
    let caption: String
    let value: String
    var alignment: HorizontalAlignment = .leading
    var tone: DKTone?

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(caption)
                .font(DK.Typeface.caption)
                .foregroundStyle(DK.Palette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tone?.text ?? DK.Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Flow layout

/// Lays its children out left to right, wrapping onto further lines, each
/// child at its ideal size. DesignKit's own flex layout is internal.
struct VPhoneLaunchpadFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + verticalSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let added = row.indices.isEmpty ? size.width : row.width + horizontalSpacing + size.width
            if !row.indices.isEmpty, added > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + horizontalSpacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }
}
