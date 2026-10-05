import AppKit

// MARK: - NSMenu

/// Builds real `NSMenu`s from `DKMenuItem`s, for AppKit menu bars, status
/// items and `NSView.menu`. Each item that has an action owns its closure, so
/// nothing else has to keep a target alive. Menus turn off `autoenablesItems`,
/// so `isEnabled` is what the user sees.
@MainActor
public extension DKMenu {
    /// The menu with its rows.
    func makeNSMenu() -> NSMenu {
        items.makeNSMenu(title: title)
    }

    /// A menu-bar item that opens this menu, for `NSApp.mainMenu`.
    func makeMenuBarItem() -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = makeNSMenu()
        return item
    }
}

@MainActor
public extension [DKMenuItem] {
    /// An `NSMenu` of these rows. Leading, trailing and doubled separators are dropped.
    func makeNSMenu(title: String = "") -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        for section in DKMenuLayout(self).sections {
            if section.separatorBefore {
                menu.addItem(.separator())
            }
            if let header = section.header {
                menu.addItem(.sectionHeader(title: header))
            }
            for row in section.rows {
                menu.addItem(row.item.makeNSMenuItem(shortcut: row.shortcut))
                if let alternate = row.alternate {
                    let item = alternate.item.makeNSMenuItem(shortcut: alternate.shortcut)
                    if alternate.shortcut == nil {
                        item.keyEquivalentModifierMask = alternate.modifiers.modifierFlags
                    }
                    item.isAlternate = true
                    menu.addItem(item)
                }
            }
        }
        return menu
    }
}

@MainActor
public extension DKMenuItem {
    /// This row as one `NSMenuItem`: a separator, a section header, a command,
    /// or an item that opens its submenu.
    func makeNSMenuItem() -> NSMenuItem {
        makeNSMenuItem(shortcut: shortcut)
    }

    /// A submenu's rows as an `NSMenu` titled with this item's title. Any other
    /// row becomes a menu holding just that row.
    func makeNSMenu() -> NSMenu {
        kind == .submenu ? children.makeNSMenu(title: title) : [self].makeNSMenu(title: title)
    }

    internal func makeNSMenuItem(shortcut: DKShortcut?) -> NSMenuItem {
        let item: NSMenuItem
        switch kind {
        case .separator:
            return .separator()
        case .header:
            return .sectionHeader(title: title)
        case .submenu:
            item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = children.makeNSMenu(title: title)
        case .action:
            if let action {
                item = DKClosureMenuItem(title: title, keyEquivalent: shortcut?.keyEquivalent ?? "", handler: action)
            } else {
                item = NSMenuItem(title: title, action: nil, keyEquivalent: shortcut?.keyEquivalent ?? "")
            }
        }
        item.keyEquivalentModifierMask = shortcut?.modifierMask ?? []
        item.isEnabled = isEnabled
        item.state = switch state {
        case .on: .on
        case .mixed: .mixed
        case .off, nil: .off
        }
        if let glyph {
            item.image = NSImage(systemSymbolName: glyph.symbolName, accessibilityDescription: nil)
        }
        if let identifier {
            item.identifier = NSUserInterfaceItemIdentifier(identifier)
        }
        if isDestructive {
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.menuFont(ofSize: 0),
            ])
        }
        return item
    }
}

// MARK: - Closure target

/// An `NSMenuItem` that runs a closure. It is its own target, so the closure
/// lives exactly as long as the item.
@MainActor
final class DKClosureMenuItem: NSMenuItem {
    let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(runHandler(_:)), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("DKClosureMenuItem is built in code")
    }

    @objc func runHandler(_ sender: Any?) {
        handler()
    }
}
