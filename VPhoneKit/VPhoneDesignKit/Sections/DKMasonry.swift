import SwiftUI

// MARK: - Masonry

/// Sections in as many columns as the width allows, each placed in the
/// column that is shortest so far, at its own height. Nothing is stretched to
/// line columns up, so a short section never turns into an empty card next
/// to a long one.
///
/// The number of columns follows the width: as many `minimumColumnWidth`
/// columns as fit, up to `maximumColumns`, and at least one. Sections keep
/// their order within each column.
///
/// ```swift
/// DKMasonry {
///     DKSection("Device") { … }
///     DKSection("Hardware") { … }
///     DKSection("Network") { … }
/// }
/// ```
public struct DKMasonry: Layout {
    public var minimumColumnWidth: CGFloat
    public var maximumColumns: Int
    public var spacing: CGFloat

    public init(minimumColumnWidth: CGFloat = 360, maximumColumns: Int = 3, spacing: CGFloat = DK.Space.s5) {
        self.minimumColumnWidth = minimumColumnWidth
        self.maximumColumns = maximumColumns
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? minimumColumnWidth
        let arrangement = arrange(subviews, width: width)
        return CGSize(width: width, height: arrangement.height)
    }

    public func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let arrangement = arrange(subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let place = arrangement.places[index]
            subview.place(
                at: CGPoint(x: bounds.minX + CGFloat(place.column) * (arrangement.columnWidth + spacing), y: bounds.minY + place.y),
                proposal: ProposedViewSize(width: arrangement.columnWidth, height: place.height),
            )
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> DKMasonryArrangement {
        let columns = Self.columnCount(width: width, minimumColumnWidth: minimumColumnWidth, maximumColumns: maximumColumns, spacing: spacing)
        let columnWidth = Self.columnWidth(width: width, columns: columns, spacing: spacing)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
        return Self.arrange(heights: heights, columns: columns, columnWidth: columnWidth, spacing: spacing)
    }

    // MARK: Placement

    /// As many columns of at least `minimumColumnWidth` as fit, between one
    /// and `maximumColumns`.
    nonisolated static func columnCount(width: CGFloat, minimumColumnWidth: CGFloat, maximumColumns: Int, spacing: CGFloat) -> Int {
        guard width.isFinite, minimumColumnWidth > 0 else { return 1 }
        let fitting = Int(((width + spacing) / (minimumColumnWidth + spacing)).rounded(.down))
        return min(max(fitting, 1), max(maximumColumns, 1))
    }

    nonisolated static func columnWidth(width: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    /// Puts each height, in order, at the bottom of the shortest column (the
    /// leftmost of equals).
    nonisolated static func arrange(heights: [CGFloat], columns: Int, columnWidth: CGFloat, spacing: CGFloat) -> DKMasonryArrangement {
        var bottoms = [CGFloat](repeating: 0, count: max(columns, 1))
        var used = [Bool](repeating: false, count: bottoms.count)
        var places: [DKMasonryArrangement.Place] = []
        for height in heights {
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            let y = used[column] ? bottoms[column] + spacing : 0
            places.append(.init(column: column, y: y, height: height))
            bottoms[column] = y + height
            used[column] = true
        }
        return DKMasonryArrangement(columnWidth: columnWidth, places: places, height: bottoms.max() ?? 0)
    }
}

/// Where `DKMasonry` puts each section.
struct DKMasonryArrangement: Equatable {
    struct Place: Equatable {
        var column: Int
        var y: CGFloat
        var height: CGFloat
    }

    var columnWidth: CGFloat
    var places: [Place]
    var height: CGFloat
}

// MARK: - Previews

#if DEBUG
#Preview("Masonry") {
    ScrollView {
        DKMasonry {
            ForEach(Array([7, 4, 4, 8, 3, 2, 12].enumerated()), id: \.offset) { _, rows in
                DKSection("\(rows) rows") {
                    ForEach(0 ..< rows, id: \.self) { row in
                        DKFormRow("Row \(row)") { Text("Value") }
                    }
                }
            }
        }
        .padding(20)
    }
    .frame(width: 1240, height: 820)
}
#endif
