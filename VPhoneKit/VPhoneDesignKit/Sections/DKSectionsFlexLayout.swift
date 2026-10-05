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

extension View {
    /// The item's flex basis (its ideal width when nil) and grow factor inside a
    /// `DKSectionsFlexLayout`.
    func dkSectionsFlex(basis: CGFloat? = nil, grow: CGFloat = 0) -> some View {
        layoutValue(key: DKSectionsFlexBasis.self, value: basis)
            .layoutValue(key: DKSectionsFlexGrow.self, value: grow)
    }
}

/// A row that wraps its items onto further lines when they do not fit, each line
/// centered vertically. Without a width it lays everything out on one line at
/// ideal widths.
struct DKSectionsFlexLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat, verticalSpacing: CGFloat) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
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
        guard let width, width.isFinite else {
            let height = ideals.map(\.height).max() ?? 0
            var x: CGFloat = 0
            var placements: [Placement] = []
            for (index, ideal) in ideals.enumerated() {
                placements.append(Placement(index: index, frame: CGRect(x: x, y: (height - ideal.height) / 2, width: ideal.width, height: ideal.height)))
                x += ideal.width + horizontalSpacing
            }
            return (CGSize(width: max(x - horizontalSpacing, 0), height: height), placements)
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
