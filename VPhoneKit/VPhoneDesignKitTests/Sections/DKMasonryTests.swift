import CoreGraphics
import Testing
@testable import VPhoneDesignKit

/// Where the masonry layout puts sections of different heights.
@Suite("DesignKit masonry")
struct DKMasonryTests {
    @Test
    func `the width decides the number of columns, up to the maximum`() {
        let count = { (width: CGFloat) in
            DKMasonry.columnCount(width: width, minimumColumnWidth: 360, maximumColumns: 3, spacing: 20)
        }
        #expect(count(300) == 1)
        #expect(count(739) == 1)
        #expect(count(740) == 2)
        #expect(count(1120) == 3)
        #expect(count(4000) == 3)
        #expect(count(.infinity) == 1)
    }

    @Test
    func `columns share the width less the gaps`() {
        #expect(DKMasonry.columnWidth(width: 1000, columns: 2, spacing: 20) == 490)
        #expect(DKMasonry.columnWidth(width: 400, columns: 1, spacing: 20) == 400)
    }

    @Test
    func `each section goes to the shortest column and keeps its own height`() {
        let arrangement = DKMasonry.arrange(heights: [300, 120, 100, 200], columns: 2, columnWidth: 400, spacing: 20)
        #expect(arrangement.places.map(\.column) == [0, 1, 1, 1])
        #expect(arrangement.places.map(\.y) == [0, 0, 140, 260])
        #expect(arrangement.places.map(\.height) == [300, 120, 100, 200])
        #expect(arrangement.height == 460)
    }

    @Test
    func `equal columns take the leftmost first`() {
        let arrangement = DKMasonry.arrange(heights: [100, 100, 100], columns: 3, columnWidth: 300, spacing: 20)
        #expect(arrangement.places.map(\.column) == [0, 1, 2])
        #expect(arrangement.height == 100)
    }

    @Test
    func `no sections take no height`() {
        #expect(DKMasonry.arrange(heights: [], columns: 2, columnWidth: 300, spacing: 20).height == 0)
    }
}
