import SwiftUI

// The wrapping rows of the design's sections, list rows, detail bars and page
// headers are CSS `flex-wrap: wrap` boxes with a basis and a grow factor per
// item, and its facts are an auto-fit grid. These layouts reproduce both. The
// arithmetic is kept apart from the views so tests can check it.

// MARK: - Flex arithmetic

/// One item of a wrapping row as CSS flex sees it: the width it starts from and
/// its share of the width a line has left over.
struct DKSectionsFlexItem: Equatable, Sendable {
    var basis: CGFloat
    var grow: CGFloat
}

/// Where one item lands: the line it is on and the width it gets there.
struct DKSectionsFlexSlot: Equatable, Sendable {
    var index: Int
    var width: CGFloat
}

enum DKSectionsFlexMath {
    /// Packs items into lines the way `flex-wrap: wrap` does: an item moves to a
    /// new line when its basis no longer fits, an item wider than the container
    /// shrinks to it, and each line's spare width goes to its growing items in
    /// proportion to their grow factors.
    static func pack(_ items: [DKSectionsFlexItem], width: CGFloat, spacing: CGFloat) -> [[DKSectionsFlexSlot]] {
        let width = max(width, 0)
        var lines: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for (index, item) in items.enumerated() {
            let basis = min(max(item.basis, 0), width)
            let needed = current.isEmpty ? basis : used + spacing + basis
            if !current.isEmpty, needed > width + 0.5 {
                lines.append(current)
                current = [index]
                used = basis
            } else {
                current.append(index)
                used = needed
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines.map { line in
            let bases = line.map { min(max(items[$0].basis, 0), width) }
            let free = width - bases.reduce(0, +) - spacing * CGFloat(line.count - 1)
            let totalGrow = line.reduce(0) { $0 + max(items[$1].grow, 0) }
            return zip(line, bases).map { index, basis in
                let share = free > 0 && totalGrow > 0 ? free * max(items[index].grow, 0) / totalGrow : 0
                return DKSectionsFlexSlot(index: index, width: basis + share)
            }
        }
    }

    /// The column count of `repeat(auto-fit, minmax(minimum, 1fr))`: as many
    /// columns of at least `minimum` as fit, never more than there are items,
    /// never fewer than one.
    static func columnCount(itemCount: Int, width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        guard itemCount > 0 else {
            return 0
        }
        let fitting = Int(((width + spacing) / (minimum + spacing)).rounded(.down))
        return min(itemCount, max(1, fitting))
    }
}

// MARK: - Wrapping row

struct DKSectionsFlexBasis: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

struct DKSectionsFlexGrow: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

public extension View {
    /// This view's flex basis and grow factor inside a `DKFlowLayout`, as CSS
    /// `flex: grow 1 basis` sets them: the width it starts from (its ideal width
    /// when nil) and its share of the width a line has left over.
    func dkFlowItem(basis: CGFloat? = nil, grow: CGFloat = 0) -> some View {
        layoutValue(key: DKSectionsFlexBasis.self, value: basis)
            .layoutValue(key: DKSectionsFlexGrow.self, value: grow)
    }
}

extension View {
    func dkSectionsFlex(basis: CGFloat? = nil, grow: CGFloat = 0) -> some View {
        dkFlowItem(basis: basis, grow: grow)
    }
}

/// A row that wraps its items onto further lines when they do not fit, each
/// line centered vertically: tags, a legend, a toolbar that folds on a narrow
/// window. Items keep their ideal widths unless `dkFlowItem(basis:grow:)` gives
/// them a basis and a share of the spare width.
///
/// ```swift
/// DKFlowLayout(horizontalSpacing: DK.Space.s6, verticalSpacing: DK.Space.s2) {
///     ForEach(parts) { LegendEntry($0) }
/// }
/// ```
///
/// Without a width to fit it lays everything out on one line. Measured at zero
/// width, as a hosting view does to find its minimum size, it reports zero wide
/// and one line tall rather than stacking every item a character wide.
public struct DKFlowLayout: Layout {
    public var horizontalSpacing: CGFloat
    public var verticalSpacing: CGFloat

    public init(horizontalSpacing: CGFloat = DK.Space.s2, verticalSpacing: CGFloat = DK.Space.s2) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    public func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for placement in arrange(width: bounds.width, subviews: subviews).placements {
            subviews[placement.index].place(
                at: CGPoint(x: bounds.minX + placement.frame.minX, y: bounds.minY + placement.frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: placement.frame.width, height: placement.frame.height),
            )
        }
    }

    private struct Placement {
        var index: Int
        var frame: CGRect
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> (size: CGSize, placements: [Placement]) {
        guard !subviews.isEmpty else {
            return (.zero, [])
        }
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        guard let width, width.isFinite, width > 0 else {
            // No width (nil or infinite): one line at ideal widths. Zero: the
            // minimum-size probe, answered with that same line but zero wide;
            // wrapping at zero would measure text one character per line and
            // report a height that grows the window.
            let height = ideals.map(\.height).max() ?? 0
            var x: CGFloat = 0
            var placements: [Placement] = []
            for (index, ideal) in ideals.enumerated() {
                placements.append(Placement(index: index, frame: CGRect(x: x, y: (height - ideal.height) / 2, width: ideal.width, height: ideal.height)))
                x += ideal.width + horizontalSpacing
            }
            let lineWidth = max(x - horizontalSpacing, 0)
            return (CGSize(width: width == nil || width?.isInfinite == true ? lineWidth : 0, height: height), placements)
        }
        let items = subviews.indices.map { index in
            DKSectionsFlexItem(
                basis: subviews[index][DKSectionsFlexBasis.self] ?? ideals[index].width,
                grow: subviews[index][DKSectionsFlexGrow.self],
            )
        }
        var placements: [Placement] = []
        var y: CGFloat = 0
        var usedWidth: CGFloat = 0
        for line in DKSectionsFlexMath.pack(items, width: width, spacing: horizontalSpacing) {
            let sizes = line.map { subviews[$0.index].sizeThatFits(ProposedViewSize(width: $0.width, height: nil)) }
            let height = sizes.map(\.height).max() ?? 0
            var x: CGFloat = 0
            for (slot, size) in zip(line, sizes) {
                placements.append(Placement(index: slot.index, frame: CGRect(x: x, y: y + (height - size.height) / 2, width: slot.width, height: size.height)))
                x += slot.width + horizontalSpacing
            }
            usedWidth = max(usedWidth, x - horizontalSpacing)
            y += height + verticalSpacing
        }
        return (CGSize(width: min(usedWidth, width), height: max(y - verticalSpacing, 0)), placements)
    }
}

/// The layout behind the sections' wrapping rows.
typealias DKSectionsFlexLayout = DKFlowLayout

// MARK: - Zero-width probe

/// Passes its one child every proposal but a zero width, which it answers with
/// the child's height at its ideal width and a width of zero. A hosting view
/// finds its minimum size by measuring at zero width; text that wraps
/// (`fixedSize(horizontal: false, vertical: true)`) measured there stacks one
/// character per line and reports a height of a thousand points or more, which
/// becomes the window's minimum height.
struct DKZeroWidthProbeLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let child = subviews.first else {
            return .zero
        }
        if let width = proposal.width, width <= 0 {
            return CGSize(width: 0, height: child.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height)).height)
        }
        return child.sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

// MARK: - Facts grid

/// The detail bar's facts: an auto-fit grid of columns at least 180pt wide that
/// share the width equally.
struct DKSectionsFactsLayout: Layout {
    static let minimumColumnWidth: CGFloat = 180
    static let columnSpacing: CGFloat = 24
    static let rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in arrangement.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height),
            )
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let count = subviews.count
        guard count > 0 else {
            return (.zero, [])
        }
        let spacing = Self.columnSpacing
        let columns: Int
        let columnWidth: CGFloat
        if let width, width.isFinite {
            columns = DKSectionsFlexMath.columnCount(itemCount: count, width: width, minimum: Self.minimumColumnWidth, spacing: spacing)
            columnWidth = max((width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 0)
        } else {
            columns = count
            columnWidth = Self.minimumColumnWidth
        }
        var frames: [CGRect] = []
        var y: CGFloat = 0
        for rowStart in stride(from: 0, to: count, by: columns) {
            let row = rowStart ..< min(rowStart + columns, count)
            let heights = row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
            for (offset, height) in heights.enumerated() {
                frames.append(CGRect(x: CGFloat(offset) * (columnWidth + spacing), y: y, width: columnWidth, height: height))
            }
            y += (heights.max() ?? 0) + Self.rowSpacing
        }
        let totalWidth = CGFloat(columns) * columnWidth + spacing * CGFloat(columns - 1)
        return (CGSize(width: totalWidth, height: max(y - Self.rowSpacing, 0)), frames)
    }
}
