import AppKit
import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// How a detail bar answers the size probes a hosting view makes.
@MainActor
@Suite("DesignKit detail bar sizing")
struct DKDetailBarSizingTests {
    private static let note = "The value is protected by the keychain's access control and cannot be shown without unlocking the guest first."

    private func height(_ view: some View, width: CGFloat) -> CGFloat {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 0)).height
    }

    @Test
    func `a row detail bar with a note measured at zero width stays short`() {
        let bar = DKDetailBar(
            "Password",
            subtitle: "research-26@vphone",
            note: Self.note,
            facts: [DKKeyValue("Class", "genp"), DKKeyValue("Access", "WhenUnlocked")],
            actions: [DKButtonSpec("Delete…", glyph: .trash, variant: .danger)],
            layout: .row,
        )
        #expect(height(bar, width: 0) < 200)
        #expect(height(bar, width: 900) < 200)
    }

    @Test
    func `a column detail bar with a note measured at zero width stays short`() {
        let bar = DKDetailBar("SpringBoard", subtitle: "pid 61", note: Self.note, facts: [DKKeyValue("PPID", "1")])
        #expect(height(bar, width: 0) < 200)
    }
}

/// A detail bar with nothing selected shows its hint note.
@MainActor
@Suite("DesignKit detail bar note")
struct DKDetailBarNoteTests {
    @Test
    func `a note without a title still takes up a line`() {
        let empty = NSHostingController(rootView: DKDetailBar()).sizeThatFits(in: CGSize(width: 600, height: 0)).height
        let hint = NSHostingController(rootView: DKDetailBar(note: "Select an item to copy, reveal, edit or delete it."))
            .sizeThatFits(in: CGSize(width: 600, height: 0)).height
        #expect(hint > empty + 10)
        let zero = NSHostingController(rootView: DKDetailBar(note: String(repeating: "Select an item. ", count: 20), layout: .row))
            .sizeThatFits(in: CGSize(width: 0, height: 0)).height
        #expect(zero < 200)
    }
}
