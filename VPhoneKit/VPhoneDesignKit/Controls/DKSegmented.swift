import SwiftUI

// MARK: - Option

/// One segment of a `DKSegmented`: a value, its label, and optionally a count shown
/// as a muted number after the label ("All 4") and a leading glyph. An icon-only
/// segment shows just the glyph; its label becomes the accessibility label and
/// tooltip.
public struct DKSegmentOption<Value: Hashable>: Identifiable {
    public var value: Value
    public var label: String
    public var count: Int?
    public var glyph: DKGlyph?
    public var isIconOnly: Bool

    public var id: Value {
        value
    }

    public init(_ label: String, value: Value, count: Int? = nil, glyph: DKGlyph? = nil) {
        self.value = value
        self.label = label
        self.count = count
        self.glyph = glyph
        isIconOnly = false
    }

    /// A segment that shows only `glyph`; `label` is what VoiceOver and the tooltip say.
    public static func icon(_ glyph: DKGlyph, label: String, value: Value) -> DKSegmentOption {
        var option = DKSegmentOption(label, value: value, glyph: glyph)
        option.isIconOnly = true
        return option
    }

    /// What VoiceOver reads for the segment: the label, then the count if there is one.
    public var accessibilityLabel: String {
        guard let count else {
            return label
        }
        return "\(label), \(count)"
    }
}

// MARK: - Selection logic

enum DKSegmentedSelection {
    /// The value an arrow key lands on from `current`, moving `step` segments and
    /// stopping at either end. A selection not among the options moves to the first.
    static func value<Value: Hashable>(after current: Value, step: Int, in options: [DKSegmentOption<Value>]) -> Value? {
        guard !options.isEmpty else {
            return nil
        }
        guard let index = options.firstIndex(where: { $0.value == current }) else {
            return options[0].value
        }
        let target = min(max(index + step, 0), options.count - 1)
        return options[target].value
    }
}

// MARK: - Segmented control

/// The DesignKit segmented control: a sunken track of segments, one of them
/// selected. Page switchers in sheets (General / Hardware / Advanced) and list
/// filters (All 4 / Running / Stopped) use it. With `fill`, the segments share the
/// full width equally; otherwise the control hugs its labels.
public struct DKSegmented<Selection: Hashable>: View {
    let label: String
    @Binding var selection: Selection
    let options: [DKSegmentOption<Selection>]
    let fill: Bool

    /// - Parameters:
    ///   - label: Names the group for VoiceOver ("Show", "Page").
    ///   - selection: The selected option's value.
    ///   - options: The segments, leading to trailing.
    ///   - fill: Stretch to the proposed width and give every segment the same share.
    public init(_ label: String, selection: Binding<Selection>, options: [DKSegmentOption<Selection>], fill: Bool = false) {
        self.label = label
        _selection = selection
        self.options = options
        self.fill = fill
    }

    public var body: some View {
        let track = RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
        segments
            .padding(Self.trackInset)
            .frame(maxWidth: fill ? .infinity : nil)
            .background(track.fill(DK.Palette.surfaceSunken))
            .overlay(track.strokeBorder(DK.Palette.lineStrong, lineWidth: DK.Metric.hairline))
            .fixedSize(horizontal: !fill, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .onMoveCommand { direction in
                let step = switch direction {
                case .left: -1
                case .right: 1
                default: 0
                }
                if step != 0, let next = DKSegmentedSelection.value(after: selection, step: step, in: options) {
                    selection = next
                }
            }
    }

    @ViewBuilder
    private var segments: some View {
        if fill {
            DKEqualWidthLayout {
                ForEach(options) { segment($0) }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(options) { segment($0) }
            }
        }
    }

    private func segment(_ option: DKSegmentOption<Selection>) -> some View {
        DKSegmentButton(option: option, isSelected: option.value == selection, fill: fill) {
            selection = option.value
        }
    }

    /// Track padding plus its border: the segments sit 3pt inside the outer edge.
    static var trackInset: CGFloat {
        2 + DK.Metric.hairline
    }
}

// MARK: - Segment

private struct DKSegmentButton<Value: Hashable>: View {
    let option: DKSegmentOption<Value>
    let isSelected: Bool
    let fill: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let glyph = option.glyph {
                    DKIcon(glyph, size: 13)
                }
                if !option.isIconOnly {
                    Text(option.label)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    if let count = option.count {
                        Text(count, format: .number)
                            .foregroundStyle(DK.Palette.muted)
                            .monospacedDigit()
                            .padding(.leading, DK.Space.s1)
                    }
                }
            }
            .font(DK.Typeface.body)
            .foregroundStyle(DK.Palette.ink)
            .padding(.horizontal, fill ? 0 : 11)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: DK.Metric.controlHeightSmall)
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.field, style: .continuous)
                    .fill(isSelected ? DK.Palette.segmentSelected : .clear),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.isIconOnly ? option.label : "")
        .accessibilityLabel(option.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Equal-width layout

/// Lays its children out in a row of equal shares of the proposed width, each as
/// tall as the tallest. Used by `DKSegmented` in fill mode.
struct DKEqualWidthLayout: Layout {
    /// The width of each of `count` equal shares of `total`, never negative.
    static func segmentWidth(total: CGFloat, count: Int) -> CGFloat {
        guard count > 0, total.isFinite else {
            return 0
        }
        return max(total, 0) / CGFloat(count)
    }

    /// The leading edge of each share, measured from the row's leading edge.
    static func offsets(total: CGFloat, count: Int) -> [CGFloat] {
        let width = segmentWidth(total: total, count: count)
        return (0 ..< max(count, 0)).map { CGFloat($0) * width }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = ideals.map(\.height).max() ?? 0
        let natural = (ideals.map(\.width).max() ?? 0) * CGFloat(subviews.count)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? natural
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let width = Self.segmentWidth(total: bounds.width, count: subviews.count)
        for (subview, offset) in zip(subviews, Self.offsets(total: bounds.width, count: subviews.count)) {
            subview.place(
                at: CGPoint(x: bounds.minX + offset, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height),
            )
        }
    }
}

// MARK: - Previews

private enum DKPreviewPage: Hashable {
    case general, hardware, advanced
}

private enum DKPreviewFilter: Hashable {
    case all, running, stopped
}

private struct DKSegmentedPreview: View {
    @State private var page = DKPreviewPage.general
    @State private var filter = DKPreviewFilter.all
    @State private var view = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s4) {
            DKSegmented("Show", selection: $filter, options: [
                DKSegmentOption("All", value: .all, count: 4),
                DKSegmentOption("Running", value: .running, count: 1),
                DKSegmentOption("Stopped", value: .stopped),
            ])
            DKSegmented("Page", selection: $page, options: [
                DKSegmentOption("General", value: .general),
                DKSegmentOption("Hardware", value: .hardware),
                DKSegmentOption("Advanced", value: .advanced),
            ], fill: true)
            DKSegmented("View", selection: $view, options: [
                DKSegmentOption.icon(.list, label: "List", value: 0),
                DKSegmentOption.icon(.apps, label: "Grid", value: 1),
                DKSegmentOption("Disks", value: 2, glyph: .disk),
            ])
        }
        .padding(DK.Space.s4)
        .frame(width: 380)
        .background(DK.Palette.window)
    }
}

#Preview("Segmented, light") {
    DKSegmentedPreview().preferredColorScheme(.light)
}

#Preview("Segmented, dark") {
    DKSegmentedPreview().preferredColorScheme(.dark)
}
