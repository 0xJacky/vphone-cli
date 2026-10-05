import Testing
@testable import VPhoneVirtualMachineKit

/// Text typed into the guest as US keyboard presses (keyboard page usages).
@Suite("Guest keystrokes")
struct VPhoneGuestKeystrokesTests {
    private typealias Key = VPhoneGuestKeystrokes.Key

    @Test
    func `letters map to their usages, capitals with Shift`() {
        #expect(VPhoneGuestKeystrokes.key(for: "a") == Key(usage: 0x04, shift: false))
        #expect(VPhoneGuestKeystrokes.key(for: "z") == Key(usage: 0x1D, shift: false))
        #expect(VPhoneGuestKeystrokes.key(for: "A") == Key(usage: 0x04, shift: true))
        #expect(VPhoneGuestKeystrokes.key(for: "Z") == Key(usage: 0x1D, shift: true))
    }

    @Test
    func `digits follow the number row, with 0 after 9`() {
        #expect(VPhoneGuestKeystrokes.key(for: "1") == Key(usage: 0x1E, shift: false))
        #expect(VPhoneGuestKeystrokes.key(for: "9") == Key(usage: 0x26, shift: false))
        #expect(VPhoneGuestKeystrokes.key(for: "0") == Key(usage: 0x27, shift: false))
    }

    @Test
    func `shifted symbols share the key of the character under them`() {
        let pairs: [(Character, Character)] = [
            ("1", "!"), ("2", "@"), ("3", "#"), ("4", "$"), ("5", "%"), ("6", "^"), ("7", "&"), ("8", "*"),
            ("9", "("), ("0", ")"), ("-", "_"), ("=", "+"), ("[", "{"), ("]", "}"), ("\\", "|"), (";", ":"),
            ("'", "\""), ("`", "~"), (",", "<"), (".", ">"), ("/", "?"),
        ]
        for (plain, shifted) in pairs {
            let base = VPhoneGuestKeystrokes.key(for: plain)
            let upper = VPhoneGuestKeystrokes.key(for: shifted)
            #expect(base?.shift == false, "\(plain)")
            #expect(upper?.shift == true, "\(shifted)")
            #expect(base?.usage == upper?.usage, "\(plain) and \(shifted)")
        }
    }

    @Test
    func `whitespace keys`() {
        #expect(VPhoneGuestKeystrokes.key(for: " ") == Key(usage: 0x2C, shift: false))
        #expect(VPhoneGuestKeystrokes.key(for: "\t") == Key(usage: 0x2B, shift: false))
        #expect(VPhoneGuestKeystrokes.key(for: "\n") == Key(usage: 0x28, shift: false))
        #expect(VPhoneGuestKeystrokes.key(for: "\r") == Key(usage: 0x28, shift: false))
        // A CRLF pair is one Character and one Return.
        #expect(VPhoneGuestKeystrokes(text: "a\r\nb").keys.map(\.usage) == [0x04, 0x28, 0x05])
    }

    @Test
    func `a password with a Return types every character in order`() {
        let plan = VPhoneGuestKeystrokes(text: "Password1!\n")
        #expect(plan.skipped == 0)
        #expect(plan.keys == [
            Key(usage: 0x13, shift: true), // P
            Key(usage: 0x04, shift: false), // a
            Key(usage: 0x16, shift: false), // s
            Key(usage: 0x16, shift: false), // s
            Key(usage: 0x1A, shift: false), // w
            Key(usage: 0x12, shift: false), // o
            Key(usage: 0x15, shift: false), // r
            Key(usage: 0x07, shift: false), // d
            Key(usage: 0x1E, shift: false), // 1
            Key(usage: 0x1E, shift: true), // !
            Key(usage: 0x28, shift: false), // Return
        ])
    }

    @Test
    func `characters a US keyboard has no key for are skipped and counted`() {
        let accented = VPhoneGuestKeystrokes(text: "naïve café")
        #expect(accented.keys.count == 8)
        #expect(accented.skipped == 2)

        let emoji = VPhoneGuestKeystrokes(text: "ok 👍🏽")
        #expect(emoji.keys.count == 3)
        #expect(emoji.skipped == 1)

        #expect(VPhoneGuestKeystrokes.key(for: "é") == nil)
        #expect(VPhoneGuestKeystrokes.key(for: "\u{7F}") == nil)

        let empty = VPhoneGuestKeystrokes(text: "")
        #expect(empty.keys.isEmpty)
        #expect(empty.skipped == 0)
    }
}
