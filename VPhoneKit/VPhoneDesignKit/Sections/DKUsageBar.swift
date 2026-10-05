import SwiftUI

// MARK: - Segment

/// One part of a `DKUsageBar`: what it is, how much of it there is, and the
/// color it is drawn in.
public struct DKUsageSegment: Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    /// The amount, in any unit shared by the bar's segments (bytes, cores).
    public var value: Double
    /// The amount as the legend shows it ("38.1 GB"); nil shows the label alone.
    public var valueText: String?
    public var color: Color

    public init(_ label: String, value: Double, valueText: String? = nil, color: Color, id: String? = nil) {
        self.id = id ?? label
        self.label = label
        self.value = value
        self.valueText = valueText
        self.color = color
    }

    /// A segment of bytes, with its size written by `DKFormat.bytes(_:)`.
    public init(_ label: String, bytes: Int64, color: Color, id: String? = nil) {
        self.init(label, value: Double(max(bytes, 0)), valueText: DKFormat.bytes(bytes), color: color, id: id)
    }

    /// What VoiceOver reads for the segment: "Machine disks 166 GB".
    public var accessibilityText: String {
        guard let valueText, !valueText.isEmpty else {
            return label
        }
        return "\(label) \(valueText)"
    }
}

// MARK: - Bar

/// A stacked usage bar (the Disks page's "where the space goes"): one 12pt
/// track split into its segments by value, 2pt apart, over a wrapping legend of
/// color swatches, labels and amounts. Segments of zero or less are left out;
/// any other segment stays at least 2pt wide, however small.
///
/// With a `capacity`, the segments fill their share of it and the rest of the
/// track stays empty; without one they fill the whole track.
///
/// ```swift
/// DKUsageBar([
///     DKUsageSegment("Machine disks", bytes: disks, color: DK.Palette.accent),
///     DKUsageSegment("Restore files", bytes: restores, color: DK.Palette.accentSoft),
/// ])
/// ```
public struct DKUsageBar: View {
    public var segments: [DKUsageSegment]
    public var capacity: Double?
    public var showsLegend: Bool
    public var label: String

    public init(_ segments: [DKUsageSegment], capacity: Double? = nil, showsLegend: Bool = true, label: String = "Usage") {
        self.segments = segments
        self.capacity = capacity
        self.showsLegend = showsLegend
        self.label = label
    }

    public var body: some View {
        let shown = segments.filter { $0.value > 0 && $0.value.isFinite }
        VStack(alignment: .leading, spacing: 14) {
            bar(shown)
            if showsLegend, !shown.isEmpty {
                legend(shown)
            }
        }
    }

    private func bar(_ shown: [DKUsageSegment]) -> some View {
        GeometryReader { proxy in
            let widths = Self.widths(for: shown.map(\.value), capacity: capacity, in: proxy.size.width)
            HStack(spacing: Self.gap) {
                ForEach(Array(zip(shown, widths)), id: \.0.id) { segment, width in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: width)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: Self.height)
        .background(DK.Palette.track)
        .clipShape(RoundedRectangle(cornerRadius: Self.height / 2, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(shown.map(\.accessibilityText).joined(separator: ", "))
    }

    private func legend(_ shown: [DKUsageSegment]) -> some View {
        DKFlowLayout(horizontalSpacing: DK.Space.s6, verticalSpacing: DK.Space.s2) {
            ForEach(shown) { segment in
                HStack(spacing: DK.Space.s2) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(segment.color)
                        .frame(width: 10, height: 10)
                    Text(segment.label)
                        .foregroundStyle(DK.Palette.ink)
                    if let valueText = segment.valueText {
                        Text(valueText)
                            .foregroundStyle(DK.Palette.muted)
                            .monospacedDigit()
                    }
                }
                .font(DK.Typeface.body)
                .fixedSize()
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Geometry

    nonisolated static let height: CGFloat = 12
    nonisolated static let gap: CGFloat = 2
    nonisolated static let minimumSegmentWidth: CGFloat = 2

    /// Each segment's width in a track `width` wide: segments share the track,
    /// less the gaps between them, by value (of `capacity` when it is larger
    /// than their sum), each at least `minimumSegmentWidth`. The widths never
    /// add up to more than the track holds.
    nonisolated static func widths(for values: [Double], capacity: Double?, in width: CGFloat) -> [CGFloat] {
        guard !values.isEmpty, width.isFinite, width > 0 else {
            return values.map { _ in 0 }
        }
        let available = max(0, width - gap * CGFloat(values.count - 1))
        let sum = values.reduce(0, +)
        let total = max(sum, capacity ?? 0)
        guard total > 0 else {
            return values.map { _ in 0 }
        }
        let filled = available * CGFloat(sum / total)
        let floor = min(minimumSegmentWidth, filled / CGFloat(values.count))
        // Give every segment the floor, then share what is left by value among
        // the segments whose share exceeds the floor.
        var widths = values.map { CGFloat($0 / sum) * filled }
        let small = widths.indices.filter { widths[$0] < floor }
        if !small.isEmpty {
            let reserved = floor * CGFloat(small.count)
            let large = widths.indices.filter { !small.contains($0) }
            let largeSum = large.reduce(0.0) { $0 + values[$1] }
            for index in small {
                widths[index] = floor
            }
            for index in large {
                widths[index] = largeSum > 0 ? CGFloat(values[index] / largeSum) * (filled - reserved) : 0
            }
        }
        return widths
    }
}

// MARK: - Previews

#Preview("Usage bar") {
    VStack(alignment: .leading, spacing: DK.Space.s6) {
        DKUsageBar([
            DKUsageSegment("Machine disks", bytes: 166_000_000_000, color: DK.Palette.accent),
            DKUsageSegment("Restore files", bytes: 38_000_000_000, color: DK.Palette.accentSoft),
            DKUsageSegment("Other machine files", bytes: 300_000_000, color: DK.Palette.muted),
            DKUsageSegment("IPSW cache", bytes: 21_000_000_000, color: DK.Palette.inkDisabled),
        ])
        DKUsageBar([
            DKUsageSegment("Used", value: 31, valueText: "31 GB", color: DK.Palette.accent),
        ], capacity: 64)
    }
    .padding(DK.Space.s4)
    .frame(width: 520)
    .background(DK.Palette.window)
}
