import SwiftUI

// MARK: - Rows and groups

/// A ready-made row of `DKTableCell`s, one per column, for tables that need no
/// custom cell views.
public struct DKTableRow<ID: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    public var id: ID
    public var cells: [DKTableCell]
    /// Tints the row and draws a 3pt bar in the tone's color at its leading edge.
    public var highlight: DKTone?

    public init(id: ID, cells: [DKTableCell], highlight: DKTone? = nil) {
        self.id = id
        self.cells = cells
        self.highlight = highlight
    }
}

/// A run of rows under an optional group header: a title, a monospaced identifier
/// and a trailing note such as a count ("Kernel Base  com.vphone.patchset.kernel.base  18 patches").
/// A group without a title draws its rows only.
public struct DKTableGroup<Row: Identifiable>: Identifiable {
    public var id: String
    public var title: String?
    public var detail: String?
    public var trailing: String?
    public var rows: [Row]

    public init(id: String? = nil, title: String? = nil, detail: String? = nil, trailing: String? = nil, rows: [Row]) {
        self.id = id ?? detail ?? title ?? ""
        self.title = title
        self.detail = detail
        self.trailing = trailing
        self.rows = rows
    }
}

/// How a `DKDataTable` draws its rows.
public enum DKTableRowStyle: String, Sendable, CaseIterable, Hashable {
    /// Rows inset from the table's edges with rounded corners: machine and image lists.
    case inset
    /// Rows that run edge to edge, for grouped tables with highlight bars: the patch list.
    case plain
}

// MARK: - Selection

/// How a `DKDataTable` selects: not at all, one row, or any set of rows.
enum DKDataTableSelection<ID: Hashable> {
    case none
    case single(Binding<ID?>)
    case multiple(Binding<Set<ID>>)

    var isSelectable: Bool {
        if case .none = self {
            return false
        }
        return true
    }

    func contains(_ id: ID) -> Bool {
        switch self {
        case .none: false
        case let .single(binding): binding.wrappedValue == id
        case let .multiple(binding): binding.wrappedValue.contains(id)
        }
    }
}

// MARK: - Table

/// A lightweight table for panels and sheets: a header of muted column titles, rows
/// of cells, optional group headers, an accent-tinted selection of one row or of
/// many, highlighted rows, an empty state, and sideways scrolling once the panel
/// is narrower than the columns allow.
///
/// A row selects on mouse-down, as a native table's does. In a table of many
/// selected rows, Command-click toggles a row and Shift-click selects the run
/// from the last row clicked. While the table has focus the up and down arrow
/// keys, Home and End move the selection, and with Shift extend it.
///
/// A column with a `sortKey` gets a clickable header when the table has a
/// `sortOrder`; the header shows the primary column's direction and a click
/// changes the order (`DKTableSortDescriptor.clicking(_:in:)`). The caller sorts
/// the rows it passes in, as with SwiftUI's `Table`.
///
/// For the main lists of a window use SwiftUI's `Table` with `DKTableCellView`
/// inside each `TableColumn`; this view is for the smaller tables around it.
///
/// Rows are any `Identifiable` value, drawn column by column by `cell`, so a column
/// can hold a control (a toggle, a menu) beside `DKTableCellView`s. `DKTableRow`
/// covers the common case where every column is a `DKTableCell`.
public struct DKDataTable<Row: Identifiable, CellContent: View>: View {
    let label: String
    let columns: [DKTableColumn]
    let groups: [DKTableGroup<Row>]
    let selection: DKDataTableSelection<Row.ID>
    let sortOrder: Binding<[DKTableSortDescriptor]>?
    let roomy: Bool
    let rowStyle: DKTableRowStyle
    let minWidth: CGFloat
    let scrollsVertically: Bool
    let emptyText: String
    let background: Color
    let highlight: (Row) -> DKTone?
    let rowMenu: ((Row) -> [DKMenuItem])?
    let cell: (Row, Int) -> CellContent

    @State private var viewportWidth: CGFloat = 0
    @State private var tracker = DKRowTracker()
    /// Where Shift extends a multiple selection from, and the row the last
    /// click or arrow key landed on.
    @State private var anchor: Row.ID?
    @State private var cursor: Row.ID?
    @FocusState private var isFocused: Bool

    init(
        label: String,
        columns: [DKTableColumn],
        groups: [DKTableGroup<Row>],
        selection: DKDataTableSelection<Row.ID>,
        sortOrder: Binding<[DKTableSortDescriptor]>?,
        roomy: Bool,
        rowStyle: DKTableRowStyle,
        minWidth: CGFloat,
        scrollsVertically: Bool,
        emptyText: String,
        background: Color,
        highlight: @escaping (Row) -> DKTone?,
        rowMenu: ((Row) -> [DKMenuItem])?,
        cell: @escaping (Row, Int) -> CellContent,
    ) {
        self.label = label
        self.columns = columns
        self.groups = groups
        self.selection = selection
        self.sortOrder = sortOrder
        self.roomy = roomy
        self.rowStyle = rowStyle
        self.minWidth = minWidth
        self.scrollsVertically = scrollsVertically
        self.emptyText = emptyText
        self.background = background
        self.highlight = highlight
        self.rowMenu = rowMenu
        self.cell = cell
    }

    /// A table of grouped rows.
    ///
    /// - Parameters:
    ///   - label: The table's accessibility label ("Machines").
    ///   - selection: The selected row; rows are not selectable when nil.
    ///   - sortOrder: The sort order the sortable headers show and change.
    ///   - roomy: Two-line rows (58pt) for title cells with subtitles.
    ///   - minWidth: The narrowest the table lays out before it scrolls sideways;
    ///     never less than the columns' minimum widths.
    ///   - scrollsVertically: Scroll the rows under a pinned header. When false the
    ///     table is as tall as its rows, for sheets that size to their content.
    ///   - background: The table's ground, also behind the pinned header. Match the card it sits on.
    ///   - highlight: The tone a row is highlighted in, or nil.
    ///   - contextMenu: The menu a row shows on a secondary click, or nil for none.
    ///   - cell: The view for a row's column, by column index.
    public init(
        _ label: String,
        columns: [DKTableColumn],
        groups: [DKTableGroup<Row>],
        selection: Binding<Row.ID?>? = nil,
        sortOrder: Binding<[DKTableSortDescriptor]>? = nil,
        roomy: Bool = false,
        rowStyle: DKTableRowStyle = .inset,
        minWidth: CGFloat = 0,
        scrollsVertically: Bool = true,
        emptyText: String = "Nothing to show.",
        background: Color = DK.Palette.surfaceRaised,
        highlight: @escaping (Row) -> DKTone? = { _ in nil },
        contextMenu: ((Row) -> [DKMenuItem])? = nil,
        @ViewBuilder cell: @escaping (Row, Int) -> CellContent,
    ) {
        self.init(
            label: label, columns: columns, groups: groups,
            selection: selection.map { .single($0) } ?? .none,
            sortOrder: sortOrder, roomy: roomy, rowStyle: rowStyle, minWidth: minWidth,
            scrollsVertically: scrollsVertically, emptyText: emptyText, background: background,
            highlight: highlight, rowMenu: contextMenu, cell: cell,
        )
    }

    /// A table of grouped rows where any set of rows can be selected.
    public init(
        _ label: String,
        columns: [DKTableColumn],
        groups: [DKTableGroup<Row>],
        selection: Binding<Set<Row.ID>>,
        sortOrder: Binding<[DKTableSortDescriptor]>? = nil,
        roomy: Bool = false,
        rowStyle: DKTableRowStyle = .inset,
        minWidth: CGFloat = 0,
        scrollsVertically: Bool = true,
        emptyText: String = "Nothing to show.",
        background: Color = DK.Palette.surfaceRaised,
        highlight: @escaping (Row) -> DKTone? = { _ in nil },
        contextMenu: ((Row) -> [DKMenuItem])? = nil,
        @ViewBuilder cell: @escaping (Row, Int) -> CellContent,
    ) {
        self.init(
            label: label, columns: columns, groups: groups, selection: .multiple(selection),
            sortOrder: sortOrder, roomy: roomy, rowStyle: rowStyle, minWidth: minWidth,
            scrollsVertically: scrollsVertically, emptyText: emptyText, background: background,
            highlight: highlight, rowMenu: contextMenu, cell: cell,
        )
    }

    /// A table of rows without group headers.
    public init(
        _ label: String,
        columns: [DKTableColumn],
        rows: [Row],
        selection: Binding<Row.ID?>? = nil,
        sortOrder: Binding<[DKTableSortDescriptor]>? = nil,
        roomy: Bool = false,
        rowStyle: DKTableRowStyle = .inset,
        minWidth: CGFloat = 0,
        scrollsVertically: Bool = true,
        emptyText: String = "Nothing to show.",
        background: Color = DK.Palette.surfaceRaised,
        highlight: @escaping (Row) -> DKTone? = { _ in nil },
        contextMenu: ((Row) -> [DKMenuItem])? = nil,
        @ViewBuilder cell: @escaping (Row, Int) -> CellContent,
    ) {
        self.init(
            label: label, columns: columns, groups: [DKTableGroup(rows: rows)],
            selection: selection.map { .single($0) } ?? .none,
            sortOrder: sortOrder, roomy: roomy, rowStyle: rowStyle, minWidth: minWidth,
            scrollsVertically: scrollsVertically, emptyText: emptyText, background: background,
            highlight: highlight, rowMenu: contextMenu, cell: cell,
        )
    }

    /// A table of rows without group headers where any set of rows can be selected.
    public init(
        _ label: String,
        columns: [DKTableColumn],
        rows: [Row],
        selection: Binding<Set<Row.ID>>,
        sortOrder: Binding<[DKTableSortDescriptor]>? = nil,
        roomy: Bool = false,
        rowStyle: DKTableRowStyle = .inset,
        minWidth: CGFloat = 0,
        scrollsVertically: Bool = true,
        emptyText: String = "Nothing to show.",
        background: Color = DK.Palette.surfaceRaised,
        highlight: @escaping (Row) -> DKTone? = { _ in nil },
        contextMenu: ((Row) -> [DKMenuItem])? = nil,
        @ViewBuilder cell: @escaping (Row, Int) -> CellContent,
    ) {
        self.init(
            label: label, columns: columns, groups: [DKTableGroup(rows: rows)], selection: .multiple(selection),
            sortOrder: sortOrder, roomy: roomy, rowStyle: rowStyle, minWidth: minWidth,
            scrollsVertically: scrollsVertically, emptyText: emptyText, background: background,
            highlight: highlight, rowMenu: contextMenu, cell: cell,
        )
    }

    public var body: some View {
        let metrics = DKDataTableMetrics(style: rowStyle, roomy: roomy)
        let required = max(
            minWidth,
            DKTableLayout.minimumWidth(of: columns.map(\.width), spacing: metrics.columnSpacing) + 2 * metrics.contentInset,
        )
        let contentWidth = max(viewportWidth, required)
        let widths = DKTableLayout.resolveWidths(
            columns.map(\.width),
            in: contentWidth - 2 * metrics.contentInset,
            spacing: metrics.columnSpacing,
        )

        ScrollViewReader { proxy in
            ScrollView(scrollsVertically ? [.horizontal, .vertical] : .horizontal) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: scrollsVertically ? [.sectionHeaders] : []) {
                    Section {
                        rowsView(widths: widths, metrics: metrics)
                    } header: {
                        header(widths: widths, metrics: metrics)
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .dkRowTracking(tracker, tracksHover: false, onPointerDown: selection.isSelectable ? { id, modifiers in
                    if let id = id.base as? Row.ID {
                        click(id, modifiers: modifiers)
                    }
                } : nil)
            }
            .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
            .focusable(selection.isSelectable)
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .home, .end]) { press in
                let move: DKTableSelectionMove = switch press.key {
                case .upArrow: .previous
                case .downArrow: .next
                case .home: .first
                default: .last
                }
                return moveSelection(move, extending: press.modifiers.contains(.shift), proxy: proxy)
            }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            viewportWidth = width
        }
        .background(background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    // MARK: Header

    private func header(widths: [CGFloat], metrics: DKDataTableMetrics) -> some View {
        HStack(spacing: metrics.columnSpacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                headerCell(column)
                    .frame(width: widths[index], alignment: column.alignment.frameAlignment)
            }
        }
        .padding(.horizontal, metrics.contentInset)
        .padding(.vertical, DK.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DK.Palette.divider).frame(height: DK.Metric.hairline)
        }
    }

    @ViewBuilder
    private func headerCell(_ column: DKTableColumn) -> some View {
        let title = Text(column.title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DK.Palette.muted)
            .lineLimit(1)
            .truncationMode(.tail)
        if let key = column.sortKey, let sortOrder {
            let primary = sortOrder.wrappedValue.first.flatMap { $0.key == key ? $0 : nil }
            Button {
                sortOrder.wrappedValue = DKTableSortDescriptor.clicking(key, in: sortOrder.wrappedValue)
            } label: {
                HStack(spacing: DK.Space.s1) {
                    title
                    if let primary {
                        Image(systemName: primary.ascending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DK.Palette.muted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(primary.map { $0.ascending ? "Sorted ascending" : "Sorted descending" } ?? "")
            .accessibilityHint("Sorts by this column")
        } else {
            title.accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func rowsView(widths: [CGFloat], metrics: DKDataTableMetrics) -> some View {
        if groups.allSatisfy(\.rows.isEmpty) {
            Text(emptyText)
                .font(DK.Typeface.body)
                .foregroundStyle(DK.Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.vertical, DK.Space.s8)
                .padding(.horizontal, 14)
                .frame(width: viewportWidth > 0 ? viewportWidth : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(height: metrics.bodyPadding)
            ForEach(groups) { group in
                if group.title != nil {
                    groupHeader(group)
                }
                ForEach(group.rows) { row in
                    rowView(row, widths: widths, metrics: metrics)
                        .id(row.id)
                }
            }
            Color.clear.frame(height: metrics.bodyPadding)
        }
    }

    private func groupHeader(_ group: DKTableGroup<Row>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DK.Space.s2) {
            Text(group.title ?? "")
                .font(DK.Typeface.captionStrong)
                .foregroundStyle(DK.Palette.ink)
            if let detail = group.detail {
                Text(detail)
                    .font(DK.Typeface.monoSmall)
                    .foregroundStyle(DK.Palette.muted)
            }
            Spacer(minLength: DK.Space.s2)
            if let trailing = group.trailing {
                Text(trailing)
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)
            }
        }
        .lineLimit(1)
        .padding(.top, 10)
        .padding(.bottom, DK.Space.s1)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DK.Palette.surfaceRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(DK.Palette.dividerSoft).frame(height: DK.Metric.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func rowView(_ row: Row, widths: [CGFloat], metrics: DKDataTableMetrics) -> some View {
        let isSelected = selection.contains(row.id)
        return HStack(spacing: metrics.columnSpacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                cell(row, index)
                    .frame(width: widths[index], alignment: column.alignment.frameAlignment)
                    .clipped()
            }
        }
        .padding(.horizontal, metrics.rowPadding)
        .padding(.vertical, metrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.rowHeight, alignment: .leading)
        .background(DKTableRowBackground(tone: highlight(row), isSelected: isSelected, cornerRadius: metrics.cornerRadius))
        .contentShape(Rectangle())
        .dkTrackedRow(selection.isSelectable ? tracker : nil, id: row.id)
        .modifier(DKDataTableRowMenu(items: rowMenu.map { menu in { menu(row) } }))
        .padding(.horizontal, metrics.outerInset)
        .padding(.vertical, metrics.rowGap / 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAddTraits(selection.isSelectable ? [.isButton] : [])
        .accessibilityAction {
            click(row.id, modifiers: [])
        }
    }

    // MARK: Selection

    private var selectableIDs: [Row.ID] {
        groups.flatMap { $0.rows.map(\.id) }
    }

    private func click(_ id: Row.ID, modifiers: NSEvent.ModifierFlags) {
        switch selection {
        case .none:
            return
        case let .single(binding):
            if binding.wrappedValue != id {
                binding.wrappedValue = id
            }
        case let .multiple(binding):
            let next = DKTableSelection.click(
                id,
                extending: modifiers.contains(.shift),
                toggling: modifiers.contains(.command),
                selection: binding.wrappedValue,
                anchor: anchor,
                in: selectableIDs,
            )
            if binding.wrappedValue != next.selection {
                binding.wrappedValue = next.selection
            }
            anchor = next.anchor
        }
        cursor = id
        isFocused = true
    }

    private func moveSelection(_ move: DKTableSelectionMove, extending: Bool, proxy: ScrollViewProxy) -> KeyPress.Result {
        switch selection {
        case .none:
            return .ignored
        case let .single(binding):
            guard let target = DKTableSelection.target(of: move, from: binding.wrappedValue, in: selectableIDs) else {
                return .ignored
            }
            binding.wrappedValue = target
            proxy.scrollTo(target)
            return .handled
        case let .multiple(binding):
            let from = cursor.flatMap { binding.wrappedValue.contains($0) ? $0 : nil }
                ?? selectableIDs.last { binding.wrappedValue.contains($0) }
            guard let next = DKTableSelection.move(
                move,
                extending: extending,
                selection: binding.wrappedValue,
                anchor: anchor ?? from,
                cursor: from,
                in: selectableIDs,
            ) else {
                return .ignored
            }
            binding.wrappedValue = next.selection
            anchor = next.anchor
            cursor = next.cursor
            if let target = next.cursor {
                proxy.scrollTo(target)
            }
            return .handled
        }
    }
}

/// A row's context menu, built from the table's hook when the row has one.
private struct DKDataTableRowMenu: ViewModifier {
    let items: (() -> [DKMenuItem])?

    func body(content: Content) -> some View {
        if let items {
            content.contextMenu {
                DKMenuContent(items())
            }
        } else {
            content
        }
    }
}

// MARK: - DKTableRow convenience

public extension DKDataTable where CellContent == DKTableCellView {
    /// A grouped table of `DKTableRow`s; each row's highlight is its own.
    init<ID: Hashable & Sendable>(
        _ label: String,
        columns: [DKTableColumn],
        groups: [DKTableGroup<DKTableRow<ID>>],
        selection: Binding<ID?>? = nil,
        sortOrder: Binding<[DKTableSortDescriptor]>? = nil,
        roomy: Bool = false,
        rowStyle: DKTableRowStyle = .inset,
        minWidth: CGFloat = 0,
        scrollsVertically: Bool = true,
        emptyText: String = "Nothing to show.",
        background: Color = DK.Palette.surfaceRaised,
        contextMenu: ((DKTableRow<ID>) -> [DKMenuItem])? = nil,
    ) where Row == DKTableRow<ID> {
        self.init(
            label: label, columns: columns, groups: groups,
            selection: selection.map { .single($0) } ?? .none,
            sortOrder: sortOrder, roomy: roomy, rowStyle: rowStyle, minWidth: minWidth,
            scrollsVertically: scrollsVertically, emptyText: emptyText, background: background,
            highlight: \.highlight, rowMenu: contextMenu, cell: Self.tableRowCell,
        )
    }

    /// A grouped table of `DKTableRow`s where any set of rows can be selected.
    init<ID: Hashable & Sendable>(
        _ label: String,
        columns: [DKTableColumn],
        groups: [DKTableGroup<DKTableRow<ID>>],
        selection: Binding<Set<ID>>,
        sortOrder: Binding<[DKTableSortDescriptor]>? = nil,
        roomy: Bool = false,
        rowStyle: DKTableRowStyle = .inset,
        minWidth: CGFloat = 0,
        scrollsVertically: Bool = true,
        emptyText: String = "Nothing to show.",
        background: Color = DK.Palette.surfaceRaised,
        contextMenu: ((DKTableRow<ID>) -> [DKMenuItem])? = nil,
    ) where Row == DKTableRow<ID> {
        self.init(
            label: label, columns: columns, groups: groups, selection: .multiple(selection),
            sortOrder: sortOrder, roomy: roomy, rowStyle: rowStyle, minWidth: minWidth,
            scrollsVertically: scrollsVertically, emptyText: emptyText, background: background,
            highlight: \.highlight, rowMenu: contextMenu, cell: Self.tableRowCell,
        )
    }

    /// A table of `DKTableRow`s without group headers; each row's highlight is its own.
    init<ID: Hashable & Sendable>(
        _ label: String,
        columns: [DKTableColumn],
        rows: [DKTableRow<ID>],
        selection: Binding<ID?>? = nil,
        sortOrder: Binding<[DKTableSortDescriptor]>? = nil,
        roomy: Bool = false,
        rowStyle: DKTableRowStyle = .inset,
        minWidth: CGFloat = 0,
        scrollsVertically: Bool = true,
        emptyText: String = "Nothing to show.",
        background: Color = DK.Palette.surfaceRaised,
        contextMenu: ((DKTableRow<ID>) -> [DKMenuItem])? = nil,
    ) where Row == DKTableRow<ID> {
        self.init(
            label, columns: columns, groups: [DKTableGroup(rows: rows)], selection: selection,
            sortOrder: sortOrder, roomy: roomy, rowStyle: rowStyle, minWidth: minWidth,
            scrollsVertically: scrollsVertically, emptyText: emptyText, background: background,
            contextMenu: contextMenu,
        )
    }

    /// A table of `DKTableRow`s without group headers where any set of rows can be selected.
    init<ID: Hashable & Sendable>(
        _ label: String,
        columns: [DKTableColumn],
        rows: [DKTableRow<ID>],
        selection: Binding<Set<ID>>,
        sortOrder: Binding<[DKTableSortDescriptor]>? = nil,
        roomy: Bool = false,
        rowStyle: DKTableRowStyle = .inset,
        minWidth: CGFloat = 0,
        scrollsVertically: Bool = true,
        emptyText: String = "Nothing to show.",
        background: Color = DK.Palette.surfaceRaised,
        contextMenu: ((DKTableRow<ID>) -> [DKMenuItem])? = nil,
    ) where Row == DKTableRow<ID> {
        self.init(
            label, columns: columns, groups: [DKTableGroup(rows: rows)], selection: selection,
            sortOrder: sortOrder, roomy: roomy, rowStyle: rowStyle, minWidth: minWidth,
            scrollsVertically: scrollsVertically, emptyText: emptyText, background: background,
            contextMenu: contextMenu,
        )
    }

    private static func tableRowCell<ID: Hashable & Sendable>(_ row: DKTableRow<ID>, _ column: Int) -> DKTableCellView {
        DKTableCellView(column < row.cells.count ? row.cells[column] : .text(""))
    }
}

// MARK: - Metrics

/// The design's `.dk-table` geometry for each row style.
struct DKDataTableMetrics: Equatable {
    /// Body padding around the rows (`.dk-table__body`).
    var outerInset: CGFloat
    /// Padding inside a row before its first cell (`.dk-table__row`).
    var rowPadding: CGFloat
    var rowVerticalPadding: CGFloat
    var rowHeight: CGFloat
    var rowGap: CGFloat
    var bodyPadding: CGFloat
    var columnSpacing: CGFloat
    var cornerRadius: CGFloat

    /// Where the first column starts: the header lines up with it.
    var contentInset: CGFloat {
        outerInset + rowPadding
    }

    init(style: DKTableRowStyle, roomy: Bool) {
        rowHeight = roomy ? DK.Metric.tableRowHeightRoomy : DK.Metric.tableRowHeight
        switch style {
        case .inset:
            outerInset = DK.Space.s2
            rowPadding = DK.Space.s2
            rowVerticalPadding = roomy ? 10 : 0
            rowGap = 1
            bodyPadding = DK.Space.s1
            columnSpacing = 14
            cornerRadius = DK.Radius.field
        case .plain:
            outerInset = 0
            rowPadding = 14
            rowVerticalPadding = roomy ? 10 : 7
            rowGap = 0
            bodyPadding = 0
            columnSpacing = DK.Space.s3
            cornerRadius = 0
        }
    }
}

// MARK: - Row highlight

/// A table row's fill: the accent tint when selected, otherwise the highlight
/// tone's surface, plus a 3pt bar in the tone's color at the leading edge.
struct DKTableRowBackground: View {
    let tone: DKTone?
    let isSelected: Bool
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack(alignment: .leading) {
            shape.fill(isSelected ? DK.Palette.accentTint : tone?.surface ?? .clear)
            if let tone {
                Rectangle()
                    .fill(tone.color)
                    .frame(width: 3)
            }
        }
        .clipShape(shape)
    }
}

public extension View {
    /// Highlights a table row in `tone`: the tone's surface behind it and a 3pt bar
    /// in the tone's color at its leading edge, as the patch list marks patches the
    /// guest does not run yet. `isSelected` draws the selection tint instead of the
    /// surface and keeps the bar. A nil tone draws nothing unless selected.
    ///
    /// `DKDataTable` applies this to its rows through its `highlight` parameter.
    /// SwiftUI's `Table` on macOS draws its own row backgrounds and has no public
    /// way to fill a whole row, so inside a `TableColumn` this tints only the cell
    /// it is applied to, inset by the table's cell spacing. Use `DKDataTable` when
    /// whole rows must be highlighted.
    func dkTableRowHighlight(_ tone: DKTone?, isSelected: Bool = false) -> some View {
        background(DKTableRowBackground(tone: tone, isSelected: isSelected, cornerRadius: 0))
    }
}
