import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// Multiple selection, sort descriptors and the on-accent cell colors.
@Suite("DesignKit table selection and sorting")
struct DKTableSelectionSortTests {
    private let ids = ["a", "b", "c", "d", "e"]

    // MARK: Clicks

    @Test
    func `a plain click selects one row and anchors there`() {
        let result = DKTableSelection.click("c", extending: false, toggling: false, selection: ["a", "b"], anchor: "a", in: ids)
        #expect(result.selection == ["c"])
        #expect(result.anchor == "c")
    }

    @Test
    func `command toggles a row and keeps the rest`() {
        var result = DKTableSelection.click("c", extending: false, toggling: true, selection: ["a"], anchor: "a", in: ids)
        #expect(result.selection == ["a", "c"])
        #expect(result.anchor == "c")
        result = DKTableSelection.click("a", extending: false, toggling: true, selection: result.selection, anchor: result.anchor, in: ids)
        #expect(result.selection == ["c"])
    }

    @Test
    func `shift selects the run from the anchor in either direction`() {
        var result = DKTableSelection.click("d", extending: true, toggling: false, selection: ["b"], anchor: "b", in: ids)
        #expect(result.selection == ["b", "c", "d"])
        #expect(result.anchor == "b")
        result = DKTableSelection.click("a", extending: true, toggling: false, selection: result.selection, anchor: "b", in: ids)
        #expect(result.selection == ["a", "b"])
    }

    @Test
    func `shift and command add the run to the selection`() {
        let result = DKTableSelection.click("e", extending: true, toggling: true, selection: ["a"], anchor: "d", in: ids)
        #expect(result.selection == ["a", "d", "e"])
    }

    @Test
    func `shift without an anchor acts as a plain click`() {
        let result = DKTableSelection.click("c", extending: true, toggling: false, selection: [], anchor: nil, in: ids)
        #expect(result.selection == ["c"])
        #expect(result.anchor == "c")
    }

    // MARK: Keys

    @Test
    func `an arrow key moves a single row of a multiple selection`() throws {
        let result = try #require(DKTableSelection.move(.next, extending: false, selection: ["b"], anchor: "b", cursor: "b", in: ids))
        #expect(result.selection == ["c"])
        #expect(result.anchor == "c")
        #expect(result.cursor == "c")
    }

    @Test
    func `shift and an arrow key extend from the anchor`() throws {
        var result = try #require(DKTableSelection.move(.next, extending: true, selection: ["b"], anchor: "b", cursor: "b", in: ids))
        result = try #require(DKTableSelection.move(.next, extending: true, selection: result.selection, anchor: result.anchor, cursor: result.cursor, in: ids))
        #expect(result.selection == ["b", "c", "d"])
        result = try #require(DKTableSelection.move(.first, extending: true, selection: result.selection, anchor: result.anchor, cursor: result.cursor, in: ids))
        #expect(result.selection == ["a", "b"])
        #expect(DKTableSelection.move(.next, extending: false, selection: Set<String>(), anchor: nil, cursor: nil, in: []) == nil)
    }

    // MARK: Sort order

    @Test
    func `clicking the primary column flips it and another column becomes primary`() {
        var order = [DKTableSortDescriptor("name")]
        order = DKTableSortDescriptor.clicking("name", in: order)
        #expect(order == [DKTableSortDescriptor("name", ascending: false)])
        order = DKTableSortDescriptor.clicking("size", in: order)
        #expect(order == [DKTableSortDescriptor("size"), DKTableSortDescriptor("name", ascending: false)])
        order = DKTableSortDescriptor.clicking("name", in: order)
        #expect(order == [DKTableSortDescriptor("name"), DKTableSortDescriptor("size")])
    }

    private struct File {
        var name: String
        var size: Int
    }

    @Test
    func `rows sort by the first key, break ties on the next and keep their order otherwise`() {
        let files = [File(name: "b", size: 2), File(name: "a", size: 2), File(name: "c", size: 1), File(name: "d", size: 1)]
        let comparators: [String: (File, File) -> ComparisonResult] = [
            "size": { $0.size == $1.size ? .orderedSame : ($0.size < $1.size ? .orderedAscending : .orderedDescending) },
            "name": { $0.name.compare($1.name) },
        ]
        let bySize = DKTableSortDescriptor.sort(files, by: [DKTableSortDescriptor("size")], comparators: comparators)
        #expect(bySize.map(\.name) == ["c", "d", "b", "a"])
        let bySizeThenName = DKTableSortDescriptor.sort(files, by: [DKTableSortDescriptor("size", ascending: false), DKTableSortDescriptor("name")], comparators: comparators)
        #expect(bySizeThenName.map(\.name) == ["a", "b", "c", "d"])
        #expect(DKTableSortDescriptor.sort(files, by: [DKTableSortDescriptor("unknown")], comparators: comparators).map(\.name) == ["b", "a", "c", "d"])
    }

    @Test
    func `table rows sort by their cells, numbers as Finder does and bars by fraction`() {
        let columns = [DKTableColumn("Name", sortKey: "name"), DKTableColumn("Disk", sortKey: "disk"), DKTableColumn("Note")]
        let rows = [
            DKTableRow(id: 1, cells: [.title("vm-10"), .bar(0.9, value: "58 GB"), .text("x")]),
            DKTableRow(id: 2, cells: [.title("vm-9"), .bar(0.2, value: "13 GB"), .text("y")]),
            DKTableRow(id: 3, cells: [DKTableCell.mono("vm-1").warning("old"), .bar(0.5, value: "32 GB"), .text("z")]),
        ]
        #expect(rows.sorted(by: [DKTableSortDescriptor("name")], columns: columns).map(\.id) == [3, 2, 1])
        #expect(rows.sorted(by: [DKTableSortDescriptor("disk", ascending: false)], columns: columns).map(\.id) == [1, 3, 2])
        #expect(DKTableColumn("Note").sortKey == nil)
    }

    // MARK: Cell ink

    @Test
    func `cells take white ink on an increased background prominence or when told to`() {
        #expect(DKTableCellView.ink(onAccent: nil, prominence: .increased) == .onAccent)
        #expect(DKTableCellView.ink(onAccent: nil, prominence: .standard) == .standard)
        #expect(DKTableCellView.ink(onAccent: false, prominence: .increased) == .standard)
        #expect(DKTableCellView.ink(onAccent: true, prominence: .standard) == .onAccent)
    }

    @Test
    func `on the accent, accent glyphs turn white and status tones keep their color`() {
        let ink = DKTableCellInk.onAccent
        #expect(ink.primary == DK.Palette.onAccent)
        #expect(ink.muted == DK.Palette.onAccentMuted)
        #expect(ink.tone(nil) == DK.Palette.onAccent)
        #expect(ink.tone(.accent) == DK.Palette.onAccent)
        #expect(ink.tone(.danger) == DKTone.danger.color)
        #expect(DKTableCellInk.standard.tone(.accent) == DKTone.accent.color)
        #expect(DKTableCellInk.standard.primary == DK.Palette.ink)
    }
}
