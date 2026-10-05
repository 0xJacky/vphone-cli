import AppKit

// MARK: - Menu Commands

/// Menu-bar items the display window's buttons press. A button goes through
/// its menu item, so the two are one action with one enablement, and the
/// window needs no reference to the menu controller.
enum VPhoneMenuCommand: String, CaseIterable {
    case rotateLeft = "vphone.device.rotate-left"
    case copyScreenshot = "vphone.capture.copy-screenshot"
    case toggleRecording = "vphone.capture.toggle-recording"
    case guestTools = "vphone.window.guest-tools"

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(rawValue)
    }

    /// The item in the current main menu, searched through every submenu.
    @MainActor
    var item: NSMenuItem? {
        NSApp.mainMenu.flatMap { Self.find(identifier, in: $0) }
    }

    /// Whether the item would run now. A menu that enables its items itself
    /// is validated first, as AppKit does before it shows the menu.
    @MainActor
    var isEnabled: Bool {
        guard let item else { return false }
        if let menu = item.menu, menu.autoenablesItems {
            menu.update()
        }
        return item.isEnabled
    }

    /// Runs the item as if it were chosen, unless it is disabled.
    @MainActor
    @discardableResult
    func perform() -> Bool {
        guard isEnabled, let item, let menu = item.menu else { return false }
        let index = menu.index(of: item)
        guard index >= 0 else { return false }
        menu.performActionForItem(at: index)
        return true
    }

    @MainActor
    private static func find(_ identifier: NSUserInterfaceItemIdentifier, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.identifier == identifier {
                return item
            }
            if let submenu = item.submenu, let found = find(identifier, in: submenu) {
                return found
            }
        }
        return nil
    }
}

extension NSMenuItem {
    /// Tags the item as the target of a display window button.
    func command(_ command: VPhoneMenuCommand) -> NSMenuItem {
        identifier = command.identifier
        return self
    }
}
