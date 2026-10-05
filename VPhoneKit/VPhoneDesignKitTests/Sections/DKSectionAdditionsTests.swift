import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// Key-value extras, Markdown footnotes, toned cards and the usage bar.
@Suite("DesignKit section additions")
struct DKSectionAdditionsTests {
    @Test
    func `a key-value row keeps its tooltip, progress and action`() {
        let row = DKKeyValue("Disk", "31 GB of 64 GB", help: "Allocated on the host", progress: 1.4, action: DKButtonSpec("Reveal", glyph: .folder))
        #expect(row.help == "Allocated on the host")
        #expect(row.visibleProgress == 1)
        #expect(row.action?.label == "Reveal")
        #expect(DKKeyValue("CPU", "8").visibleProgress == nil)
        #expect(DKKeyValue("CPU", "8", progress: .nan).visibleProgress == 0)
    }

    @Test
    func `rows compare by how their action looks, not by its closure`() {
        let a = DKKeyValue("Path", "/tmp", action: DKButtonSpec("Copy") {})
        let b = DKKeyValue("Path", "/tmp", action: DKButtonSpec("Copy") {})
        let c = DKKeyValue("Path", "/tmp", action: DKButtonSpec("Reveal") {})
        #expect(a == b)
        #expect(a != c)
        #expect(a != DKKeyValue("Path", "/tmp"))
        #expect(Set([a, b, c]).count == 2)
        var d = a
        d.action = nil
        #expect(d == DKKeyValue("Path", "/tmp"))
    }

    @Test
    func `a markdown footnote keeps its links and text that does not parse stays as it is`() throws {
        let note = DKSection<EmptyView>.markdown("See [Host Setup](https://example.com/setup) for **details**.")
        #expect(String(note.characters) == "See Host Setup for details.")
        let link = note.runs.compactMap(\.link).first
        #expect(link == URL(string: "https://example.com/setup"))
        #expect(String(DKSection<EmptyView>.markdown("plain text").characters) == "plain text")
    }

    @Test
    func `a toned card takes its tone's line`() {
        #expect(DKCard<EmptyView>.border(for: .warning) == DKTone.warning.line)
        #expect(DKCard<EmptyView>.border(for: nil) == DK.Palette.line)
    }

    // MARK: Usage bar

    @Test
    func `segments share the track by value less the gaps`() {
        let widths = DKUsageBar.widths(for: [3, 1], capacity: nil, in: 402)
        #expect(widths == [300, 100])
    }

    @Test
    func `a capacity leaves the unused share of the track empty`() {
        let widths = DKUsageBar.widths(for: [25, 25], capacity: 100, in: 202)
        #expect(widths == [50, 50])
    }

    @Test
    func `a tiny segment stays visible and the widths still fit`() {
        let widths = DKUsageBar.widths(for: [1000, 0.001, 1000], capacity: nil, in: 404)
        #expect(widths[1] == DKUsageBar.minimumSegmentWidth)
        #expect(abs(widths.reduce(0, +) - 400) < 0.001)
        #expect(widths[0] == widths[2])
    }

    @Test
    func `an empty or zero bar has no widths to give`() {
        #expect(DKUsageBar.widths(for: [], capacity: nil, in: 300).isEmpty)
        #expect(DKUsageBar.widths(for: [0, 0], capacity: nil, in: 300) == [0, 0])
        #expect(DKUsageBar.widths(for: [1], capacity: nil, in: 0) == [0])
    }

    @Test
    func `a byte segment writes its size`() {
        let segment = DKUsageSegment("Machine disks", bytes: 1536, color: DK.Palette.accent)
        #expect(segment.valueText == "1.5 KB")
        #expect(segment.accessibilityText == "Machine disks 1.5 KB")
        #expect(DKUsageSegment("Free", value: 1, color: DK.Palette.track).accessibilityText == "Free")
    }
}
