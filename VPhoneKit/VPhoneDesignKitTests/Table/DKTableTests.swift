import CoreGraphics
import Testing
@testable import VPhoneDesignKit

/// Column widths, keyboard selection and the cell model behind the DesignKit tables.
@Suite("DesignKit table")
struct DKTableTests {
    // MARK: Column widths

    @Test
    func `fixed columns keep their width and flexible columns share the rest by weight`() {
        let widths = DKTableLayout.resolveWidths(
            [.fixed(76), .flexible(weight: 1), .flexible(weight: 3)],
            in: 76 + 400 + 2 * 10,
            spacing: 10,
        )
        #expect(widths == [76, 100, 300])
    }

    @Test
    func `a flexible column below its minimum takes the minimum and the others share what is left`() {
        let widths = DKTableLayout.resolveWidths(
            [.flexible(min: 200, weight: 1), .flexible(weight: 1)],
            in: 300,
            spacing: 0,
        )
        #expect(widths == [200, 100])
    }

    @Test
    func `a flexible column above its maximum stops there and the others take the slack`() {
        let widths = DKTableLayout.resolveWidths(
            [.flexible(max: 50, weight: 1), .flexible(weight: 1)],
            in: 300,
            spacing: 0,
        )
        #expect(widths == [50, 250])
    }

    @Test
    func `a fraction column takes its share of the columns width before flexible columns`() {
        let widths = DKTableLayout.resolveWidths(
            [.fraction(0.25), .flexible()],
            in: 410,
            spacing: 10,
        )
        #expect(widths == [100, 300])
        #expect(DKTableLayout.resolveWidths([.fraction(0.1, min: 80)], in: 400, spacing: 0) == [80])
    }

    @Test
    func `columns narrower than their minimums overflow at the minimum width`() {
        let specs: [DKTableColumnWidth] = [.flexible(min: 170, weight: 1.5), .fixed(76), .flexible(min: 120)]
        let minimum = DKTableLayout.minimumWidth(of: specs, spacing: 14)
        let expected: CGFloat = 170 + 76 + 120 + 2 * 14
        #expect(minimum == expected)
        let widths = DKTableLayout.resolveWidths(specs, in: 200, spacing: 14)
        #expect(widths == [170, 76, 120])
    }

    @Test
    func `the design's machine columns fill the width with every flexible column at or above its minimum`() {
        let specs: [DKTableColumnWidth] = [
            .flexible(min: 170, weight: 1.5), .flexible(min: 150, weight: 1.2),
            .flexible(min: 120, weight: 1.1), .fixed(76), .flexible(min: 120),
        ]
        let width: CGFloat = 900
        let widths = DKTableLayout.resolveWidths(specs, in: width, spacing: 14)
        #expect(abs(widths.reduce(0, +) + 14 * 4 - width) < 0.001)
        for (resolved, spec) in zip(widths, specs) {
            #expect(resolved >= spec.minimum)
        }
        #expect(widths[3] == 76)
    }

    @Test
    func `no columns resolve to nothing`() {
        #expect(DKTableLayout.resolveWidths([], in: 400, spacing: 14).isEmpty)
        #expect(DKTableLayout.minimumWidth(of: [], spacing: 14) == 0)
    }

    // MARK: Selection

    @Test
    func `arrow keys step through the rows and stop at the ends`() {
        let ids = ["a", "b", "c"]
        #expect(DKTableSelection.target(of: .next, from: "a", in: ids) == "b")
        #expect(DKTableSelection.target(of: .previous, from: "b", in: ids) == "a")
        #expect(DKTableSelection.target(of: .next, from: "c", in: ids) == "c")
        #expect(DKTableSelection.target(of: .previous, from: "a", in: ids) == "a")
        #expect(DKTableSelection.target(of: .first, from: "b", in: ids) == "a")
        #expect(DKTableSelection.target(of: .last, from: "a", in: ids) == "c")
    }

    @Test
    func `with nothing selected down picks the first row and up the last`() {
        let ids = [1, 2, 3]
        #expect(DKTableSelection.target(of: .next, from: nil, in: ids) == 1)
        #expect(DKTableSelection.target(of: .previous, from: nil, in: ids) == 3)
        #expect(DKTableSelection.target(of: .next, from: 9, in: ids) == 1)
        #expect(DKTableSelection.target(of: .next, from: nil, in: [Int]()) == nil)
    }

    // MARK: Cells

    @Test
    func `cells compare by kind and content`() {
        #expect(DKTableCell.mono("2.6.0") == .mono("2.6.0"))
        #expect(DKTableCell.mono("2.6.0") != .text("2.6.0"))
        #expect(DKTableCell.status(.warning, "Creating", progress: 0.63) != .status(.warning, "Creating"))
        #expect(DKTableCell.title("research-26", subtitle: "iPhone17,3") == .title("research-26", subtitle: "iPhone17,3", strong: true))
    }

    @Test
    func `a warning wraps a cell and a nil warning leaves it alone`() {
        let cell = DKTableCell.mono("2.5.0")
        #expect(cell.warning(nil) == cell)
        #expect(cell.warning("Mixed bundle versions") == .warned(cell, warning: "Mixed bundle versions"))
        #expect(cell.warning("Mixed bundle versions").warningMessage == "Mixed bundle versions")
        #expect(cell.warningMessage == nil)
    }

    @Test
    func `accessibility text reads each kind the way it is shown`() {
        #expect(DKTableCell.text("Ready").accessibilityText == "Ready")
        #expect(DKTableCell.title("research-26", subtitle: "iPhone17,3", leading: .glyph(.phone)).accessibilityText == "research-26, iPhone17,3")
        #expect(DKTableCell.title("research-26", subtitle: "").accessibilityText == "research-26")
        #expect(DKTableCell.status(.success, "Running since 09:41").accessibilityText == "Running since 09:41")
        #expect(DKTableCell.status(.warning, "Creating · Downloading 63%", progress: 0.63).accessibilityText == "Creating · Downloading 63%")
        #expect(DKTableCell.status(.warning, "Downloading", progress: 0.5).accessibilityText == "Downloading, 50%")
        #expect(DKTableCell.badge(.success, "Supported").accessibilityText == "Supported")
        #expect(DKTableCell.icon(.check, tone: .success, label: "Verified").accessibilityText == "Verified")
        #expect(DKTableCell.bar(38.0 / 64.0, value: "38 GB").accessibilityText == "38 GB, 59%")
        #expect(DKTableCell.mono("2.5.0").warning("Mixed bundle versions").accessibilityText == "2.5.0, Mixed bundle versions")
    }

    @Test
    func `bar fractions are clamped to the track`() {
        #expect(DKTableCell.clampedFraction(-0.2) == 0)
        #expect(DKTableCell.clampedFraction(0.4) == 0.4)
        #expect(DKTableCell.clampedFraction(1.7) == 1)
        #expect(DKTableCell.clampedFraction(.nan) == 0)
        #expect(DKTableCell.clampedFraction(.infinity) == 1)
        #expect(DKTableCell.bar(1.5, value: "70 GB").accessibilityText == "70 GB, 100%")
    }

    // MARK: Rows

    @Test
    func `a group takes its identifier from the detail, then the title`() {
        let rows = [DKTableRow(id: 1, cells: [.text("a")], highlight: .warning)]
        #expect(DKTableGroup(title: "Kernel Base", detail: "com.vphone.patchset.kernel.base", rows: rows).id == "com.vphone.patchset.kernel.base")
        #expect(DKTableGroup(title: "Kernel Base", rows: rows).id == "Kernel Base")
        #expect(DKTableGroup(id: "x", title: "Kernel Base", rows: rows).id == "x")
        #expect(rows[0].highlight == .warning)
    }

    @Test
    func `row styles line the header up with the first column`() {
        let inset = DKDataTableMetrics(style: .inset, roomy: false)
        #expect(inset.contentInset == 16)
        #expect(inset.rowHeight == DK.Metric.tableRowHeight)
        let plain = DKDataTableMetrics(style: .plain, roomy: true)
        #expect(plain.contentInset == 14)
        #expect(plain.rowHeight == DK.Metric.tableRowHeightRoomy)
    }
}
