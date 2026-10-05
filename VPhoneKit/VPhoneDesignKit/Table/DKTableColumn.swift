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

/// One column of a `DKDataTable`: a header title, a width and an alignment.
public struct DKTableColumn: Hashable, Sendable {
    public var title: String
    public var width: DKTableColumnWidth
    public var alignment: DKTableAlignment

    public init(_ title: String, width: DKTableColumnWidth = .flexible(), alignment: DKTableAlignment = .leading) {
        self.title = title
        self.width = width
        self.alignment = alignment
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

/// Where the selection lands after a keyboard move, kept free of views so it can be tested.
public enum DKTableSelection {
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
