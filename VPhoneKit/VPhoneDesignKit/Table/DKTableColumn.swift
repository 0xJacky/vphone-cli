import SwiftUI

// MARK: - Column

/// Where a column's content sits inside its width.
public enum DKTableAlignment: String, Sendable, CaseIterable, Hashable {
    case leading, center, trailing

    /// The frame alignment a cell uses inside its column.
    public var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    /// The text alignment for multi-line text inside a cell.
    public var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// How wide a column is, the design's grid tracks in points.
///
/// - `fixed`: always that width (`76px`).
/// - `flexible`: shares the width left after fixed and fraction columns with the
///   other flexible columns in proportion to `weight`, never below `min` or above
///   `max` (`minmax(170px, 1.5fr)` is `.flexible(min: 170, weight: 1.5)`).
/// - `fraction`: that share of the columns' total width, never below `min`.
public enum DKTableColumnWidth: Hashable, Sendable {
    case fixed(CGFloat)
    case flexible(min: CGFloat = 0, max: CGFloat = .infinity, weight: CGFloat = 1)
    case fraction(CGFloat, min: CGFloat = 0)

    /// The narrowest this column gets; the table scrolls sideways below the sum.
    public var minimum: CGFloat {
        switch self {
        case let .fixed(width): Swift.max(0, width)
        case let .flexible(min, _, _): Swift.max(0, min)
        case let .fraction(_, min): Swift.max(0, min)
        }
    }
}

/// One column of a `DKDataTable`: a header title, a width, an alignment and,
/// for a sortable column, the key its sort descriptors use.
public struct DKTableColumn: Hashable, Sendable {
    public var title: String
    public var width: DKTableColumnWidth
    public var alignment: DKTableAlignment
    /// Makes the header clickable to sort by this column; nil leaves it fixed.
    public var sortKey: String?

    public init(_ title: String, width: DKTableColumnWidth = .flexible(), alignment: DKTableAlignment = .leading, sortKey: String? = nil) {
        self.title = title
        self.width = width
        self.alignment = alignment
        self.sortKey = sortKey
    }
}

// MARK: - Sorting

/// One key of a table's sort order, as `NSSortDescriptor` is for `NSTableView`.
/// The table only draws the order and changes it when a header is clicked;
/// the caller sorts its rows, with `DKTableSortDescriptor.sort(_:by:comparators:)`
/// or, for `DKTableRow`s, `sorted(by:columns:)`.
public struct DKTableSortDescriptor: Hashable, Sendable {
    public var key: String
    public var ascending: Bool

    public init(_ key: String, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }

    /// The order after a click on the header of the column sorted by `key`:
    /// the primary column flips direction; any other column becomes primary,
    /// ascending, ahead of the others.
    public static func clicking(_ key: String, in order: [DKTableSortDescriptor]) -> [DKTableSortDescriptor] {
        if let first = order.first, first.key == key {
            var order = order
            order[0].ascending.toggle()
            return order
        }
        return [DKTableSortDescriptor(key)] + order.filter { $0.key != key }
    }

    /// `rows` in `order`: by the first descriptor, ties broken by the next, and
    /// rows that tie on every key keep their order. Keys without a comparator
    /// are skipped.
    public static func sort<Row>(
        _ rows: [Row],
        by order: [DKTableSortDescriptor],
        comparators: [String: (Row, Row) -> ComparisonResult],
    ) -> [Row] {
        let keys = order.compactMap { descriptor in
            comparators[descriptor.key].map { (compare: $0, ascending: descriptor.ascending) }
        }
        guard !keys.isEmpty else {
            return rows
        }
        return rows.enumerated().sorted { lhs, rhs in
            for key in keys {
                switch key.compare(lhs.element, rhs.element) {
                case .orderedAscending: return key.ascending
                case .orderedDescending: return !key.ascending
                case .orderedSame: continue
                }
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }
}

public extension Array {
    /// `DKTableRow`s in `order`, comparing the cells of the column each
    /// descriptor names (see `DKTableCell.compare(_:)`). Unknown keys are skipped.
    func sorted<ID>(by order: [DKTableSortDescriptor], columns: [DKTableColumn]) -> [DKTableRow<ID>] where Element == DKTableRow<ID> {
        var comparators: [String: (DKTableRow<ID>, DKTableRow<ID>) -> ComparisonResult] = [:]
        for (index, column) in columns.enumerated() {
            guard let key = column.sortKey else {
                continue
            }
            comparators[key] = { lhs, rhs in
                let left = index < lhs.cells.count ? lhs.cells[index] : .text("")
                let right = index < rhs.cells.count ? rhs.cells[index] : .text("")
                return left.compare(right)
            }
        }
        return DKTableSortDescriptor.sort(self, by: order, comparators: comparators)
    }
}

// MARK: - Width resolution

/// The arithmetic behind `DKDataTable`'s columns, kept free of views so it can be tested.
public enum DKTableLayout {
    /// The narrowest the columns can be laid out: every column at its minimum plus
    /// the gaps between them.
    public static func minimumWidth(of widths: [DKTableColumnWidth], spacing: CGFloat) -> CGFloat {
        guard !widths.isEmpty else {
            return 0
        }
        return widths.reduce(0) { $0 + $1.minimum } + spacing * CGFloat(widths.count - 1)
    }

    /// Each column's width when the columns, with `spacing` between them, fill
    /// `width`. Fixed and fraction columns are placed first; flexible columns share
    /// the rest by weight, clamped to their bounds the way CSS `minmax(_, fr)`
    /// tracks are. When `width` is below `minimumWidth(of:spacing:)` every column
    /// gets its minimum and the result is wider than `width`.
    public static func resolveWidths(_ widths: [DKTableColumnWidth], in width: CGFloat, spacing: CGFloat) -> [CGFloat] {
        guard !widths.isEmpty else {
            return []
        }
        let inner = max(0, width - spacing * CGFloat(widths.count - 1))
        var result = [CGFloat](repeating: 0, count: widths.count)
        var remaining = inner
        var open: [Int] = []

        for (index, spec) in widths.enumerated() {
            switch spec {
            case let .fixed(fixed):
                result[index] = max(0, fixed)
                remaining -= result[index]
            case let .fraction(fraction, minimum):
                result[index] = max(max(0, minimum), max(0, fraction) * inner)
                remaining -= result[index]
            case .flexible:
                open.append(index)
            }
        }

        // Freeze columns that break a bound and share again, until every
        // remaining column fits inside its bounds.
        while !open.isEmpty {
            let available = max(0, remaining)
            let totalWeight = open.reduce(CGFloat(0)) { $0 + weight(of: widths[$1]) }
            var tentative: [Int: CGFloat] = [:]
            for index in open {
                tentative[index] = totalWeight > 0 ? available * weight(of: widths[index]) / totalWeight : 0
            }
            let underMinimum = open.filter { tentative[$0]! < bounds(of: widths[$0]).min }
            let overMaximum = open.filter { tentative[$0]! > bounds(of: widths[$0]).max }
            let frozen = !underMinimum.isEmpty ? underMinimum : overMaximum
            if frozen.isEmpty {
                for index in open {
                    result[index] = tentative[index]!
                }
                break
            }
            for index in frozen {
                let limits = bounds(of: widths[index])
                result[index] = underMinimum.isEmpty ? limits.max : limits.min
                remaining -= result[index]
            }
            open.removeAll { frozen.contains($0) }
        }
        return result
    }

    private static func weight(of spec: DKTableColumnWidth) -> CGFloat {
        if case let .flexible(_, _, weight) = spec {
            return max(0, weight)
        }
        return 0
    }

    private static func bounds(of spec: DKTableColumnWidth) -> (min: CGFloat, max: CGFloat) {
        if case let .flexible(minimum, maximum, _) = spec {
            let low = max(0, minimum)
            return (low, max(low, maximum))
        }
        return (0, .infinity)
    }
}

// MARK: - Selection movement

/// A keyboard move through a table's rows.
public enum DKTableSelectionMove: Sendable, Hashable {
    case previous, next, first, last
}

/// Where the selection lands after a click or a keyboard move, kept free of
/// views so it can be tested.
public enum DKTableSelection {
    /// The selection of a multiple-selection table after a click on `id`, and
    /// the new anchor that Shift extends from.
    ///
    /// - A plain click selects only `id`.
    /// - Command toggles `id` and leaves the rest.
    /// - Shift selects the run from the anchor to `id`; with Command too, the
    ///   run is added to the selection. Without an anchor in `ids` it acts as a
    ///   plain click. The anchor stays where it was.
    public static func click<ID: Hashable>(
        _ id: ID,
        extending: Bool,
        toggling: Bool,
        selection: Set<ID>,
        anchor: ID?,
        in ids: [ID],
    ) -> (selection: Set<ID>, anchor: ID?) {
        if extending, let anchor, let range = run(from: anchor, to: id, in: ids) {
            return (toggling ? selection.union(range) : Set(range), anchor)
        }
        if toggling {
            var selection = selection
            if selection.remove(id) == nil {
                selection.insert(id)
            }
            return (selection, id)
        }
        return ([id], id)
    }

    /// The selection of a multiple-selection table after a keyboard move from
    /// `cursor`, the row the last move or click landed on. Without `extending`
    /// the target row alone is selected and becomes the anchor; with it
    /// (Shift), the run from the anchor to the target is.
    public static func move<ID: Hashable>(
        _ move: DKTableSelectionMove,
        extending: Bool,
        selection _: Set<ID>,
        anchor: ID?,
        cursor: ID?,
        in ids: [ID],
    ) -> (selection: Set<ID>, anchor: ID?, cursor: ID?)? {
        guard let target = target(of: move, from: cursor, in: ids) else {
            return nil
        }
        if extending, let anchor, let range = run(from: anchor, to: target, in: ids) {
            return (Set(range), anchor, target)
        }
        return ([target], target, target)
    }

    /// The rows from `start` to `end`, both included, in display order.
    static func run<ID: Hashable>(from start: ID, to end: ID, in ids: [ID]) -> ArraySlice<ID>? {
        guard let a = ids.firstIndex(of: start), let b = ids.firstIndex(of: end) else {
            return nil
        }
        return ids[min(a, b) ... max(a, b)]
    }

    /// The row `move` selects, given the current selection and the selectable rows
    /// in display order. With nothing selected (or the selection no longer listed),
    /// `next` and `first` pick the first row and `previous` and `last` the last.
    /// Moves stop at the ends; an empty table selects nothing.
    public static func target<ID: Hashable>(of move: DKTableSelectionMove, from current: ID?, in ids: [ID]) -> ID? {
        guard let firstID = ids.first, let lastID = ids.last else {
            return nil
        }
        switch move {
        case .first:
            return firstID
        case .last:
            return lastID
        case .previous, .next:
            guard let current, let index = ids.firstIndex(of: current) else {
                return move == .next ? firstID : lastID
            }
            let step = move == .next ? 1 : -1
            return ids[min(max(index + step, 0), ids.count - 1)]
        }
    }
}
