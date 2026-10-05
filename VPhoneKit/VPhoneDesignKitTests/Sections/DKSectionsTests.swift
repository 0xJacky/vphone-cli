import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// Sections, lists, form rows, detail bars and page headers.
@Suite("DesignKit sections")
struct DKSectionsTests {
    // MARK: Key-value rows

    @Test
    func `a key-value row without a tone draws no dot and keeps the body ink`() {
        let row = DKKeyValue("CPU", "8 cores")
        #expect(row.dotTone == nil)
        #expect(row.valueTone == nil)
        #expect(row.monospaced == false)
    }

    @Test
    func `a passed check draws a success dot but keeps its value in the body ink`() {
        let row = DKKeyValue("Apple silicon", "M4 Max", tone: .success)
        #expect(row.dotTone == .success)
        #expect(row.valueTone == nil)
    }

    @Test
    func `warning and danger checks color their value with the tone`() {
        #expect(DKKeyValue("Free disk space", "41 GB free", tone: .warning).valueTone == .warning)
        #expect(DKKeyValue("Helper", "Missing", tone: .danger).valueTone == .danger)
        for tone in [DKTone.neutral, .idle, .success, .info, .accent] {
            #expect(DKKeyValue("Key", "Value", tone: tone).valueTone == nil, "\(tone)")
            #expect(DKKeyValue("Key", "Value", tone: tone).dotTone == tone, "\(tone)")
        }
    }

    @Test
    func `a key-value row is identified by its key unless given an id`() {
        #expect(DKKeyValue("IPv4 Address", "192.168.64.12").id == "IPv4 Address")
        #expect(DKKeyValue("Address", "10.0.0.1", id: "en1").id == "en1")
    }

    @Test
    func `text that carries the accent tone is the accent color, not the white ink of an accent badge`() {
        #expect(DKTone.accent.sectionsTextColor == DKTone.accent.color)
        #expect(DKTone.warning.sectionsTextColor == DKTone.warning.ink)
    }

    // MARK: List items

    @Test
    func `a list item is identified by its title unless given an id`() {
        let plain = DKListItem("2.6.0")
        let keyed = DKListItem("2.6.0", id: "release-2.6.0")
        #expect(plain.id == "2.6.0")
        #expect(keyed.id == "release-2.6.0")
        #expect(Set([plain.id, keyed.id]).count == 2)
    }

    @Test
    func `list lines read from string literals as plain muted lines`() {
        let item = DKListItem("IPSW cache", lines: ["4 downloaded images.", .init("[digest]", monospaced: true, tone: .warning)])
        #expect(item.lines[0] == DKListItem.Line("4 downloaded images."))
        #expect(item.lines[0].monospaced == false)
        #expect(item.lines[0].tone == nil)
        #expect(item.lines[1].monospaced)
        #expect(item.lines[1].tone == .warning)
    }

    @Test @MainActor
    func `list row actions are drawn small unless they are icon buttons`() {
        #expect(DKListRow.small(DKButtonSpec("Show in Finder")).size == .small)
        #expect(DKListRow.small(DKButtonSpec("More", size: .icon)).size == .icon)
    }

    @Test @MainActor
    func `a section accessory is drawn as a plain link whatever its variant`() {
        let spec = DKSection<EmptyView>.plain(DKButtonSpec("Change…", variant: .primary))
        #expect(spec.variant == .plain)
        #expect(spec.label == "Change…")
    }

    // MARK: Detail bar layout

    @Test
    func `only the row layout wraps`() {
        #expect(DKDetailBarLayout.row.wraps)
        #expect(!DKDetailBarLayout.column.wraps)
        #expect(DKDetailBarLayout.row.spacing == 16)
        #expect(DKDetailBarLayout.row.lineSpacing == 8)
        #expect(DKDetailBarLayout.column.spacing == 10)
    }

    @Test
    func `a wide row bar keeps head and actions on one line and gives the head the spare width`() {
        let items = [DKDetailBarLayout.headFlex, DKSectionsFlexItem(basis: 330, grow: 0)]
        let lines = DKSectionsFlexMath.pack(items, width: 868, spacing: 16)
        #expect(lines.count == 1)
        #expect(lines[0].map(\.index) == [0, 1])
        // 868 - 330 - 16: everything the actions and the gap leave.
        #expect(lines[0][0].width == 522)
        #expect(lines[0][1].width == 330)
    }

    @Test
    func `a narrow row bar wraps the actions under the head`() {
        let items = [DKDetailBarLayout.headFlex, DKSectionsFlexItem(basis: 330, grow: 0)]
        let lines = DKSectionsFlexMath.pack(items, width: 500, spacing: 16)
        #expect(lines.map { $0.map(\.index) } == [[0], [1]])
        #expect(lines[0][0].width == 500)
        #expect(lines[1][0].width == 330)
    }

    @Test
    func `head and facts split the spare width one to two`() {
        let lines = DKSectionsFlexMath.pack([DKDetailBarLayout.headFlex, DKDetailBarLayout.factsFlex], width: 936, spacing: 16)
        #expect(lines.count == 1)
        // 936 - 260 - 360 - 16 = 300 spare: 100 to the head, 200 to the facts.
        #expect(lines[0][0].width == 360)
        #expect(lines[0][1].width == 560)
    }

    @Test
    func `an item wider than the bar shrinks to it`() {
        let lines = DKSectionsFlexMath.pack([DKSectionsFlexItem(basis: 900, grow: 0)], width: 400, spacing: 8)
        #expect(lines == [[DKSectionsFlexSlot(index: 0, width: 400)]])
    }

    @Test
    func `facts take as many 180 point columns as fit, never more than there are facts`() {
        #expect(DKSectionsFlexMath.columnCount(itemCount: 6, width: 868, minimum: 180, spacing: 24) == 4)
        #expect(DKSectionsFlexMath.columnCount(itemCount: 2, width: 868, minimum: 180, spacing: 24) == 2)
        #expect(DKSectionsFlexMath.columnCount(itemCount: 4, width: 120, minimum: 180, spacing: 24) == 1)
        #expect(DKSectionsFlexMath.columnCount(itemCount: 0, width: 868, minimum: 180, spacing: 24) == 0)
    }
}
