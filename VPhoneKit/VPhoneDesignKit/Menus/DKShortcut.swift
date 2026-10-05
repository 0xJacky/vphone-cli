import AppKit
import SwiftUI

/// A keyboard shortcut as the design writes it: a key plus a modifier set.
///
/// The same value renders the design's text ("⇧⌘H", "⌥⌘1", "esc", "⌘,"), becomes
/// a SwiftUI `KeyboardShortcut`, and becomes an `NSMenuItem` key equivalent and
/// modifier mask. Modifiers always print in Apple's order, ⌃⌥⇧⌘, whatever order
/// they were given in.
///
/// A letter key is stored lower case. An upper-case letter means Shift, as it
/// does for `NSMenuItem.keyEquivalent`, so `DKShortcut(.character("H"), [.command])`
/// is the same shortcut as `DKShortcut(.character("h"), [.shift, .command])`.
public struct DKShortcut: Hashable, Sendable {
    public let key: Key
    public let modifiers: Modifiers

    public init(_ key: Key, _ modifiers: Modifiers = []) {
        if case let .character(character) = key, character.isUppercase, character.isLetter {
            self.key = .character(Character(character.lowercased()))
            self.modifiers = modifiers.union(.shift)
        } else {
            self.key = key
            self.modifiers = modifiers
        }
    }

    /// A character shortcut: `DKShortcut("r", [.option, .command])`. The modifiers
    /// are required: a lone `DKShortcut("r")` is the string literal "r", the bare key.
    public init(_ character: Character, _ modifiers: Modifiers) {
        self.init(.character(character), modifiers)
    }
}

// MARK: - Modifiers

public extension DKShortcut {
    /// The four menu modifiers. Their order here is the order they print in.
    struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// Each modifier with its symbol, in Apple's canonical order.
        static let ordered: [(Modifiers, Character)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
        ]

        /// "⌃⌥⇧⌘" for every modifier present, in canonical order.
        public var symbols: String {
            String(Self.ordered.filter { contains($0.0) }.map(\.1))
        }

        /// SwiftUI's modifier set.
        public var eventModifiers: EventModifiers {
            var result: EventModifiers = []
            if contains(.control) { result.insert(.control) }
            if contains(.option) { result.insert(.option) }
            if contains(.shift) { result.insert(.shift) }
            if contains(.command) { result.insert(.command) }
            return result
        }

        /// AppKit's modifier mask, as `NSMenuItem.keyEquivalentModifierMask` takes it.
        public var modifierFlags: NSEvent.ModifierFlags {
            var result: NSEvent.ModifierFlags = []
            if contains(.control) { result.insert(.control) }
            if contains(.option) { result.insert(.option) }
            if contains(.shift) { result.insert(.shift) }
            if contains(.command) { result.insert(.command) }
            return result
        }

        /// The menu modifiers in an AppKit mask; other flags are ignored.
        public init(_ flags: NSEvent.ModifierFlags) {
            self = []
            if flags.contains(.control) { insert(.control) }
            if flags.contains(.option) { insert(.option) }
            if flags.contains(.shift) { insert(.shift) }
            if flags.contains(.command) { insert(.command) }
        }
    }
}

// MARK: - Keys

public extension DKShortcut {
    /// The key a shortcut presses.
    enum Key: Hashable, Sendable {
        /// A printable key: a letter, a digit or punctuation.
        case character(Character)
        case escape
        /// ⌫, the Delete key above Return.
        case delete
        /// ⌦, Forward Delete.
        case forwardDelete
        case `return`
        case tab
        case space
        case upArrow, downArrow, leftArrow, rightArrow
        case home, end, pageUp, pageDown
        /// F1 through F35.
        case function(Int)

        /// How the design prints the key: upper-case letters, "esc", "⌫", "←".
        public var symbol: String {
            switch self {
            case let .character(character): character.uppercased()
            case .escape: "esc"
            case .delete: "⌫"
            case .forwardDelete: "⌦"
            case .return: "↩"
            case .tab: "⇥"
            case .space: "Space"
            case .upArrow: "↑"
            case .downArrow: "↓"
            case .leftArrow: "←"
            case .rightArrow: "→"
            case .home: "↖"
            case .end: "↘"
            case .pageUp: "⇞"
            case .pageDown: "⇟"
            case let .function(number): "F\(number)"
            }
        }

        /// The string `NSMenuItem.keyEquivalent` takes for this key.
        public var keyEquivalent: String {
            switch self {
            case let .character(character): String(character)
            case .escape: "\u{1B}"
            case .delete: "\u{08}"
            case .forwardDelete: Self.functionKey(NSDeleteFunctionKey)
            case .return: "\r"
            case .tab: "\t"
            case .space: " "
            case .upArrow: Self.functionKey(NSUpArrowFunctionKey)
            case .downArrow: Self.functionKey(NSDownArrowFunctionKey)
            case .leftArrow: Self.functionKey(NSLeftArrowFunctionKey)
            case .rightArrow: Self.functionKey(NSRightArrowFunctionKey)
            case .home: Self.functionKey(NSHomeFunctionKey)
            case .end: Self.functionKey(NSEndFunctionKey)
            case .pageUp: Self.functionKey(NSPageUpFunctionKey)
            case .pageDown: Self.functionKey(NSPageDownFunctionKey)
            case let .function(number): Self.functionKey(NSF1FunctionKey + number - 1)
            }
        }

        /// SwiftUI's key equivalent for this key.
        public var swiftUIKeyEquivalent: KeyEquivalent {
            switch self {
            case .delete: .delete
            case let .character(character): KeyEquivalent(character)
            default: KeyEquivalent(Character(keyEquivalent))
            }
        }

        /// The key an `NSMenuItem.keyEquivalent` names, or nil for an empty or
        /// unknown one. Upper-case letters come back upper case; `DKShortcut`
        /// turns them into Shift.
        public init?(keyEquivalent: String) {
            guard keyEquivalent.count == 1, let scalar = keyEquivalent.unicodeScalars.first else { return nil }
            switch Int(scalar.value) {
            case 0x1B: self = .escape
            case 0x08, 0x7F: self = .delete
            case 0x0D, 0x03: self = .return
            case 0x09: self = .tab
            case 0x20: self = .space
            case NSDeleteFunctionKey: self = .forwardDelete
            case NSUpArrowFunctionKey: self = .upArrow
            case NSDownArrowFunctionKey: self = .downArrow
            case NSLeftArrowFunctionKey: self = .leftArrow
            case NSRightArrowFunctionKey: self = .rightArrow
            case NSHomeFunctionKey: self = .home
            case NSEndFunctionKey: self = .end
            case NSPageUpFunctionKey: self = .pageUp
            case NSPageDownFunctionKey: self = .pageDown
            case NSF1FunctionKey ... NSF35FunctionKey:
                self = .function(Int(scalar.value) - NSF1FunctionKey + 1)
            default:
                guard !scalar.properties.generalCategory.isControl else { return nil }
                self = .character(Character(scalar))
            }
        }

        /// The key named by the part of a design string after its modifiers.
        init?(symbol: String) {
            switch symbol.lowercased() {
            case "esc", "⎋", "escape": self = .escape
            case "⌫", "delete": self = .delete
            case "⌦": self = .forwardDelete
            case "↩", "⏎", "return": self = .return
            case "⇥", "tab": self = .tab
            case "space", "␣": self = .space
            case "↑": self = .upArrow
            case "↓": self = .downArrow
            case "←": self = .leftArrow
            case "→": self = .rightArrow
            case "↖", "home": self = .home
            case "↘", "end": self = .end
            case "⇞": self = .pageUp
            case "⇟": self = .pageDown
            default:
                if symbol.count == 1, let character = symbol.first {
                    self = .character(Character(character.lowercased()))
                } else if symbol.count >= 2, symbol.first == "F",
                          let number = Int(symbol.dropFirst()), (1 ... 35).contains(number) {
                    self = .function(number)
                } else {
                    return nil
                }
            }
        }

        private static func functionKey(_ code: Int) -> String {
            String(Character(UnicodeScalar(UInt32(code))!))
        }
    }
}

private extension Unicode.GeneralCategory {
    var isControl: Bool {
        self == .control || self == .format || self == .privateUse || self == .unassigned
    }
}

// MARK: - Text

extension DKShortcut: CustomStringConvertible, ExpressibleByStringLiteral {
    /// The design's text: modifiers in ⌃⌥⇧⌘ order, then the key.
    public var description: String {
        modifiers.symbols + key.symbol
    }

    /// The design's text for this shortcut. Same as `description`.
    public var displayText: String {
        description
    }

    /// Parses the design's text: any of ⌃⌥⇧⌘ in any order, then one key
    /// ("H", "1", ",", "esc", "⌫", "←", "F5"). Returns nil for text with no key,
    /// such as a lone "⌥" (the design's mark for an alternate item).
    public init?(parsing text: String) {
        var modifiers: Modifiers = []
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        while rest.count > 1, let first = rest.first,
              let modifier = Modifiers.ordered.first(where: { $0.1 == first })?.0 {
            modifiers.insert(modifier)
            rest = rest.dropFirst()
        }
        guard !rest.isEmpty, let key = Key(symbol: String(rest)) else { return nil }
        if case let .character(character) = key, Modifiers.ordered.contains(where: { $0.1 == character }) {
            return nil
        }
        self.init(key, modifiers)
    }

    /// A shortcut written as the design writes it: `"⇧⌘H"`. The literal must
    /// parse; a typo stops the program where it was written.
    public init(stringLiteral value: String) {
        guard let parsed = DKShortcut(parsing: value) else {
            preconditionFailure("Not a shortcut: \(value)")
        }
        self = parsed
    }
}

// MARK: - SwiftUI and AppKit

public extension DKShortcut {
    /// The shortcut for `.keyboardShortcut(_:)`.
    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(key.swiftUIKeyEquivalent, modifiers: modifiers.eventModifiers)
    }

    /// The `NSMenuItem.keyEquivalent` string. Letters stay lower case; Shift is in the mask.
    var keyEquivalent: String {
        key.keyEquivalent
    }

    /// The `NSMenuItem.keyEquivalentModifierMask`.
    var modifierMask: NSEvent.ModifierFlags {
        modifiers.modifierFlags
    }

    /// The shortcut an `NSMenuItem` already carries, or nil when it has none.
    init?(keyEquivalent: String, modifierMask: NSEvent.ModifierFlags) {
        guard let key = Key(keyEquivalent: keyEquivalent) else { return nil }
        self.init(key, Modifiers(modifierMask))
    }

    /// The same key with more modifiers.
    func adding(_ more: Modifiers) -> DKShortcut {
        DKShortcut(key, modifiers.union(more))
    }
}
