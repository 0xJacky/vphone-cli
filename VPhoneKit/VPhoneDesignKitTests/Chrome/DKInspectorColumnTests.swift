import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// The inspector column a page draws under its own header.
@Suite("DesignKit inspector column")
struct DKInspectorColumnTests {
    private typealias Column = DKInspectorColumn<EmptyView>

    @Test
    func `the column starts at 380 points, within 300 to 520`() {
        #expect(Column.idealWidth == 380)
        #expect(Column.widthRange == 300 ... 520)
        #expect(Column.widthRange.contains(Column.idealWidth))
    }

    @Test
    func `dragging the divider left widens the column, right narrows it`() {
        #expect(Column.width(from: 380, dragged: -40) == 420)
        #expect(Column.width(from: 380, dragged: 30) == 350)
        #expect(Column.width(from: 380, dragged: 0) == 380)
    }

    @Test
    func `a drag stops at the column's limits`() {
        #expect(Column.width(from: 380, dragged: -500) == 520)
        #expect(Column.width(from: 380, dragged: 500) == 300)
    }
}
