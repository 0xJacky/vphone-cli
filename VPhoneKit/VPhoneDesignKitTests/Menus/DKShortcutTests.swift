import AppKit
import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// Shortcut text, ordering, and the SwiftUI and AppKit forms.
@Suite("DesignKit shortcuts")
struct DKShortcutTests {
    @Test(arguments: [
        "⇧⌘H", "⌥⌘1", "esc", "⌘,", "⌘.", "⌘⌫", "⌘←", "⌘→", "⌃⌘C", "⌥⌘K", "⇧⌘K", "⌘Q",
        "⌃⌘S", "⌥⌘I", "F5", "⌃⌥⇧⌘Z", "⌘↩", "⌥⌘⇥", "⌘Space", "⌘⌦", "⌘↑", "⌘↓", "⌘⇞", "⌘⇟", "⌘↖", "⌘↘",
    ])
    func `the design's text parses and prints back unchanged`(text: String) throws {
        let shortcut = try #require(DKShortcut(parsing: text))
        #expect(shortcut.description == text)
        #expect(shortcut.displayText == text)
    }

    @Test
    func `modifiers print in Apple's order whatever order they were written in`() throws {
        #expect(try #require(DKShortcut(parsing: "⌘⇧H")).description == "⇧⌘H")
        #expect(try #require(DKShortcut(parsing: "⌘⌥⌃⇧K")).description == "⌃⌥⇧⌘K")
        #expect(try #require(DKShortcut(parsing: "⌘⌥1")).description == "⌥⌘1")
        #expect(DKShortcut("k", [.command, .shift, .option, .control]).description == "⌃⌥⇧⌘K")
        #expect(DKShortcut.Modifiers([.command, .control]).symbols == "⌃⌘")
    }

    @Test(arguments: ["", "⌥", "⌘", "⌥⌘", "⌘XY", "F36", "⌘Fn"])
    func `text without exactly one key does not parse`(text: String) {
        #expect(DKShortcut(parsing: text) == nil)
    }

    @Test
    func `named keys read the design's spellings and the Mac's symbols`() {
        #expect(DKShortcut(parsing: "esc")?.key == .escape)
        #expect(DKShortcut(parsing: "⎋")?.key == .escape)
        #expect(DKShortcut(parsing: "⌘⌫")?.key == .delete)
        #expect(DKShortcut(parsing: "⌘←")?.key == .leftArrow)
        #expect(DKShortcut(parsing: "⌥⌘F12")?.key == .function(12))
        #expect(DKShortcut(parsing: "esc")?.modifiers == [])
    }

    @Test
    func `an upper-case letter means Shift as it does in AppKit`() {
        #expect(DKShortcut("H", .command) == "⇧⌘H")
        #expect(DKShortcut("H", .command).key == .character("h"))
        // The design's letters are capitals but mean the plain key.
        #expect(DKShortcut(parsing: "⌘H") == DKShortcut("h", .command))
    }

    @Test
    func `a shortcut becomes an NSMenuItem key equivalent and modifier mask`() {
        let home: DKShortcut = "⇧⌘H"
        #expect(home.keyEquivalent == "h")
        #expect(home.modifierMask == [.shift, .command])

        let back: DKShortcut = "esc"
        #expect(back.keyEquivalent == "\u{1B}")
        #expect(back.modifierMask == [])

        let delete: DKShortcut = "⌘⌫"
        #expect(delete.keyEquivalent == "\u{08}")
        #expect(delete.modifierMask == .command)

        let rotate: DKShortcut = "⌘←"
        #expect(rotate.keyEquivalent == String(Character(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!)))

        let f5: DKShortcut = "F5"
        #expect(f5.keyEquivalent == String(Character(UnicodeScalar(UInt32(NSF5FunctionKey))!)))
    }

    @Test(arguments: [
        "⇧⌘H", "⌥⌘1", "esc", "⌘,", "⌘⌫", "⌘←", "⌃⌘C", "F5", "⌘↩", "⌥⌘⇥", "⌘Space", "⌘⌦", "⌘⇞", "⌘↘",
    ])
    func `a shortcut survives a trip through NSMenuItem`(text: String) throws {
        let shortcut = try #require(DKShortcut(parsing: text))
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: shortcut.keyEquivalent)
        item.keyEquivalentModifierMask = shortcut.modifierMask
        let back = DKShortcut(keyEquivalent: item.keyEquivalent, modifierMask: item.keyEquivalentModifierMask)
        #expect(back == shortcut)
    }

    @Test
    func `the VM window's existing NSMenuItem shortcuts read back as the design writes them`() {
        // From VPhoneMenuData and VPhoneMenuRecord.
        #expect(DKShortcut(keyEquivalent: "k", modifierMask: [.command, .control])?.description == "⌃⌘K")
        #expect(DKShortcut(keyEquivalent: "f", modifierMask: [.command, .shift])?.description == "⇧⌘F")
        #expect(DKShortcut(keyEquivalent: "c", modifierMask: [.command, .control])?.description == "⌃⌘C")
        #expect(DKShortcut(keyEquivalent: "r", modifierMask: [.command, .shift])?.description == "⇧⌘R")
        // An upper-case equivalent carries Shift; DEL is Delete too; nothing reads as nothing.
        #expect(DKShortcut(keyEquivalent: "H", modifierMask: .command)?.description == "⇧⌘H")
        #expect(DKShortcut(keyEquivalent: "\u{7F}", modifierMask: .command)?.description == "⌘⌫")
        #expect(DKShortcut(keyEquivalent: "", modifierMask: .command) == nil)
        // Flags other than the four menu modifiers are ignored.
        #expect(DKShortcut(keyEquivalent: "s", modifierMask: [.command, .capsLock, .function])?.description == "⌘S")
    }

    @Test
    func `a shortcut becomes a SwiftUI keyboard shortcut`() {
        let display: DKShortcut = "⌥⌘1"
        #expect(display.keyboardShortcut.key == KeyEquivalent("1"))
        #expect(display.keyboardShortcut.modifiers == [.option, .command])

        let delete: DKShortcut = "⌘⌫"
        #expect(delete.keyboardShortcut.key == .delete)

        let back: DKShortcut = "esc"
        #expect(back.keyboardShortcut.key == .escape)
        #expect(back.keyboardShortcut.modifiers == [])

        let rotate: DKShortcut = "⌘→"
        #expect(rotate.keyboardShortcut.key == .rightArrow)

        let home: DKShortcut = "⇧⌘H"
        #expect(home.keyboardShortcut.key == KeyEquivalent("h"))
        #expect(home.keyboardShortcut.modifiers == [.shift, .command])
    }

    @Test
    func `adding Option keeps the key`() {
        let start: DKShortcut = "⌘R"
        #expect(start.adding(.option) == "⌥⌘R")
    }
}
