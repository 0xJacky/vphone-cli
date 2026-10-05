import Foundation

/// One row of a menu, described as data. The same value renders as a SwiftUI
/// menu (`DKMenuContent`), as an `NSMenu` (`makeNSMenu()`), and as the design's
/// static artboard (`DKMenuPreview`).
///
/// ```swift
/// DKMenu("Machine") {
///     DKMenuItem("Start", shortcut: "⌘R") { start() }
///     DKMenuItem("Start Headless").alternate()
///     DKMenuItem.separator
///     DKMenuItem.submenu("Logs") {
///         DKMenuItem("Console Log") { showConsole() }
///     }
///     DKMenuItem("Delete…", shortcut: "⌘⌫") { delete() }.destructive()
/// }
/// ```
public struct DKMenuItem {
    /// What a row is.
    public enum Kind: Hashable, Sendable {
        /// A command; runs `action` when chosen.
        case action
        /// A thin line between groups.
        case separator
        /// A small, unselectable title over the rows after it.
        case header
        /// A row that opens `children`.
        case submenu
    }

    /// A checkmark state. An item with no state is a plain command; one with a
    /// state is a checkbox, and `.off` still reads as unchecked to VoiceOver.
    public enum State: Hashable, Sendable {
        case off, on, mixed
    }

    public var kind: Kind
    public var title: String
    public var glyph: DKGlyph?
    public var shortcut: DKShortcut?
    public var state: State?
    public var isEnabled: Bool
    /// Deletes or discards something; drawn in the danger color.
    public var isDestructive: Bool
    /// Replaces the item before it while Option is held. Without a shortcut of
    /// its own it takes the previous item's shortcut plus ⌥.
    public var isAlternate: Bool
    /// Becomes `NSMenuItem.identifier`, so a controller can find the item later.
    public var identifier: String?
    /// A submenu's rows.
    public var children: [DKMenuItem]
    public var action: (@MainActor () -> Void)?

    /// A command.
    public init(
        _ title: String,
        glyph: DKGlyph? = nil,
        shortcut: DKShortcut? = nil,
        state: State? = nil,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        isAlternate: Bool = false,
        identifier: String? = nil,
        action: (@MainActor () -> Void)? = nil,
    ) {
        kind = .action
        self.title = title
        self.glyph = glyph
        self.shortcut = shortcut
        self.state = state
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.isAlternate = isAlternate
        self.identifier = identifier
        children = []
        self.action = action
    }

    private init(kind: Kind, title: String = "", glyph: DKGlyph? = nil, children: [DKMenuItem] = []) {
        self.kind = kind
        self.title = title
        self.glyph = glyph
        shortcut = nil
        state = nil
        isEnabled = true
        isDestructive = false
        isAlternate = false
        identifier = nil
        self.children = children
        action = nil
    }

    /// A line between groups of rows.
    public static var separator: DKMenuItem {
        DKMenuItem(kind: .separator)
    }

    /// A section title, such as "Running" or "Guest Clipboard".
    public static func header(_ title: String) -> DKMenuItem {
        DKMenuItem(kind: .header, title: title)
    }

    /// A row that opens more rows.
    public static func submenu(
        _ title: String,
        glyph: DKGlyph? = nil,
        isEnabled: Bool = true,
        @DKMenuBuilder children: () -> [DKMenuItem],
    ) -> DKMenuItem {
        var item = DKMenuItem(kind: .submenu, title: title, glyph: glyph, children: children())
        item.isEnabled = isEnabled
        return item
    }

    /// A row that opens the rows given.
    public static func submenu(
        _ title: String,
        glyph: DKGlyph? = nil,
        isEnabled: Bool = true,
        items: [DKMenuItem],
    ) -> DKMenuItem {
        var item = DKMenuItem(kind: .submenu, title: title, glyph: glyph, children: items)
        item.isEnabled = isEnabled
        return item
    }
}

// MARK: - Modifiers

public extension DKMenuItem {
    func shortcut(_ shortcut: DKShortcut?) -> DKMenuItem {
        with { $0.shortcut = shortcut }
    }

    func glyph(_ glyph: DKGlyph?) -> DKMenuItem {
        with { $0.glyph = glyph }
    }

    func state(_ state: State?) -> DKMenuItem {
        with { $0.state = state }
    }

    /// A checkbox row, checked or not.
    func checked(_ isOn: Bool) -> DKMenuItem {
        with { $0.state = isOn ? .on : .off }
    }

    func disabled(_ isDisabled: Bool = true) -> DKMenuItem {
        with { $0.isEnabled = !isDisabled }
    }

    func destructive(_ isDestructive: Bool = true) -> DKMenuItem {
        with { $0.isDestructive = isDestructive }
    }

    func alternate(_ isAlternate: Bool = true) -> DKMenuItem {
        with { $0.isAlternate = isAlternate }
    }

    func identifier(_ identifier: String?) -> DKMenuItem {
        with { $0.identifier = identifier }
    }

    func onSelect(_ action: @escaping @MainActor () -> Void) -> DKMenuItem {
        with { $0.action = action }
    }

    private func with(_ change: (inout DKMenuItem) -> Void) -> DKMenuItem {
        var copy = self
        change(&copy)
        return copy
    }
}

// MARK: - Menu

/// A titled menu: one menu-bar menu, a context menu, or the menu behind a button.
public struct DKMenu {
    public var title: String
    public var items: [DKMenuItem]

    public init(_ title: String, items: [DKMenuItem]) {
        self.title = title
        self.items = items
    }

    public init(_ title: String, @DKMenuBuilder items: () -> [DKMenuItem]) {
        self.title = title
        self.items = items()
    }
}

// MARK: - Builder

/// Builds a list of menu rows from statements, `if`, `switch` and `for`.
@resultBuilder
public enum DKMenuBuilder {
    public static func buildExpression(_ item: DKMenuItem) -> [DKMenuItem] {
        [item]
    }

    public static func buildExpression(_ items: [DKMenuItem]) -> [DKMenuItem] {
        items
    }

    public static func buildBlock(_ parts: [DKMenuItem]...) -> [DKMenuItem] {
        parts.flatMap(\.self)
    }

    public static func buildOptional(_ part: [DKMenuItem]?) -> [DKMenuItem] {
        part ?? []
    }

    public static func buildEither(first part: [DKMenuItem]) -> [DKMenuItem] {
        part
    }

    public static func buildEither(second part: [DKMenuItem]) -> [DKMenuItem] {
        part
    }

    public static func buildArray(_ parts: [[DKMenuItem]]) -> [DKMenuItem] {
        parts.flatMap(\.self)
    }

    public static func buildLimitedAvailability(_ part: [DKMenuItem]) -> [DKMenuItem] {
        part
    }
}

// MARK: - Layout

/// How rows group once separators, headers and alternates are taken into
/// account. Every renderer reads the same layout.
struct DKMenuLayout {
    /// A run of rows under an optional header, after an optional separator.
    struct Section {
        var header: String?
        var separatorBefore: Bool
        var rows: [Row]
    }

    /// A row and the alternate that replaces it while its modifiers are held.
    struct Row {
        var item: DKMenuItem
        var shortcut: DKShortcut?
        var alternate: Alternate?
    }

    struct Alternate {
        var item: DKMenuItem
        var shortcut: DKShortcut?
        /// The keys that swap the alternate in.
        var modifiers: DKShortcut.Modifiers
    }

    var sections: [Section]

    init(_ items: [DKMenuItem]) {
        var sections: [Section] = []
        var current = Section(header: nil, separatorBefore: false, rows: [])
        var pendingSeparator = false

        func close() {
            if current.header != nil || !current.rows.isEmpty {
                sections.append(current)
            }
        }

        for item in items {
            switch item.kind {
            case .separator:
                close()
                current = Section(header: nil, separatorBefore: false, rows: [])
                pendingSeparator = !sections.isEmpty
            case .header:
                close()
                current = Section(header: item.title, separatorBefore: pendingSeparator, rows: [])
                pendingSeparator = false
            case .action, .submenu:
                if current.header == nil, current.rows.isEmpty {
                    current.separatorBefore = pendingSeparator
                    pendingSeparator = false
                }
                if item.isAlternate, let index = current.rows.indices.last, current.rows[index].alternate == nil {
                    let primary = current.rows[index].shortcut
                    let shortcut = item.shortcut ?? primary?.adding(.option)
                    let held = (shortcut?.modifiers ?? .option).subtracting(primary?.modifiers ?? [])
                    current.rows[index].alternate = Alternate(
                        item: item,
                        shortcut: shortcut,
                        modifiers: held.isEmpty ? .option : held,
                    )
                } else {
                    current.rows.append(Row(item: item, shortcut: item.shortcut, alternate: nil))
                }
            }
        }
        close()
        self.sections = sections
    }
}
