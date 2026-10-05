import Foundation

/// Text turned into US keyboard presses for the guest: keyboard page (0x07)
/// usages, each with Shift when the character needs it. Sent through
/// vphoned's `input.hid`, which queues them in order behind earlier input.
/// Characters a US keyboard has no key for are skipped and counted.
struct VPhoneGuestKeystrokes {
    struct Key: Equatable {
        let usage: UInt32
        let shift: Bool
    }

    private(set) var keys: [Key] = []
    private(set) var skipped = 0

    private static let keyboardPage: UInt32 = 0x07
    private static let leftShift: UInt32 = 0xE1

    init(text: String) {
        for character in text {
            if let key = Self.key(for: character) {
                keys.append(key)
            } else {
                skipped += 1
            }
        }
    }

    @MainActor
    func send(through control: VPhoneGuestControl) {
        for key in keys {
            if key.shift {
                control.sendHIDDown(page: Self.keyboardPage, usage: Self.leftShift)
            }
            control.sendHIDPress(page: Self.keyboardPage, usage: key.usage)
            if key.shift {
                control.sendHIDUp(page: Self.keyboardPage, usage: Self.leftShift)
            }
        }
    }

    // MARK: - US Layout

    static func key(for character: Character) -> Key? {
        if character == "\r\n" {
            return Key(usage: 0x28, shift: false)
        }
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first, scalar.isASCII else {
            return nil
        }
        let value = scalar.value
        switch value {
        case 0x61 ... 0x7A: // a-z
            return Key(usage: 0x04 + value - 0x61, shift: false)
        case 0x41 ... 0x5A: // A-Z
            return Key(usage: 0x04 + value - 0x41, shift: true)
        case 0x31 ... 0x39: // 1-9
            return Key(usage: 0x1E + value - 0x31, shift: false)
        case 0x30: // 0
            return Key(usage: 0x27, shift: false)
        default:
            return symbols[character]
        }
    }

    private static let symbols: [Character: Key] = [
        "\n": Key(usage: 0x28, shift: false),
        "\r": Key(usage: 0x28, shift: false),
        "\t": Key(usage: 0x2B, shift: false),
        " ": Key(usage: 0x2C, shift: false),
        "!": Key(usage: 0x1E, shift: true),
        "@": Key(usage: 0x1F, shift: true),
        "#": Key(usage: 0x20, shift: true),
        "$": Key(usage: 0x21, shift: true),
        "%": Key(usage: 0x22, shift: true),
        "^": Key(usage: 0x23, shift: true),
        "&": Key(usage: 0x24, shift: true),
        "*": Key(usage: 0x25, shift: true),
        "(": Key(usage: 0x26, shift: true),
        ")": Key(usage: 0x27, shift: true),
        "-": Key(usage: 0x2D, shift: false),
        "_": Key(usage: 0x2D, shift: true),
        "=": Key(usage: 0x2E, shift: false),
        "+": Key(usage: 0x2E, shift: true),
        "[": Key(usage: 0x2F, shift: false),
        "{": Key(usage: 0x2F, shift: true),
        "]": Key(usage: 0x30, shift: false),
        "}": Key(usage: 0x30, shift: true),
        "\\": Key(usage: 0x31, shift: false),
        "|": Key(usage: 0x31, shift: true),
        ";": Key(usage: 0x33, shift: false),
        ":": Key(usage: 0x33, shift: true),
        "'": Key(usage: 0x34, shift: false),
        "\"": Key(usage: 0x34, shift: true),
        "`": Key(usage: 0x35, shift: false),
        "~": Key(usage: 0x35, shift: true),
        ",": Key(usage: 0x36, shift: false),
        "<": Key(usage: 0x36, shift: true),
        ".": Key(usage: 0x37, shift: false),
        ">": Key(usage: 0x37, shift: true),
        "/": Key(usage: 0x38, shift: false),
        "?": Key(usage: 0x38, shift: true),
    ]
}
