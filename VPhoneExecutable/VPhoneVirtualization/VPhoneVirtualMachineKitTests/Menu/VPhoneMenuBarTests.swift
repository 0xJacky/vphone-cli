import AppKit
import ObjectiveC.runtime
import Testing
import VPhoneDesignKit
@testable import VPhoneVirtualMachineKit

/// The real menu bar `VPhoneMenuController` installs, without a VM: the
/// shortcuts it claims, the order of its menus, and which items a guest
/// connection turns on.
@MainActor
@Suite("VM menu bar", .serialized)
struct VPhoneMenuBarTests {
    // MARK: - Layout

    @Test
    func `the menus follow the design's order`() {
        let bar = VPhoneMenuBarFixture()
        let titles = bar.mainMenu.items.map { $0.submenu?.title ?? $0.title }
        let expected = ["VPhone", "Edit", "Device", "Input", "Simulate", "Apps", "Data", "Diagnostics", "Capture", "Window"]
        #expect(titles == expected.map(VPhoneLocalization.text))
    }

    @Test
    func `no two items claim the same shortcut`() {
        let bar = VPhoneMenuBarFixture()
        let menus = bar.mainMenu.items.compactMap { item in
            item.submenu.map { DKMenu($0.title, items: Self.designKitItems($0)) }
        }
        let conflicts = DKShortcutConflicts.find(in: menus)
        #expect(conflicts.isEmpty, "\(conflicts.map(\.description).joined(separator: "; "))")
    }

    @Test
    func `items keep the design's shortcuts`() throws {
        let bar = VPhoneMenuBarFixture()
        let expected: [(String, String, DKShortcut)] = [
            ("Edit", "Find…", DKShortcut("f", [.command])),
            ("Edit", "Show Guest Clipboard", DKShortcut("c", [.shift, .command])),
            ("Device", "Home Screen", DKShortcut("h", [.shift, .command])),
            ("Input", "Controls", DKShortcut("k", [.option, .command])),
            ("Input", "Use Hardware Keyboard", DKShortcut("k", [.shift, .command])),
            ("Apps", "App Browser", DKShortcut("a", [.shift, .command])),
            ("Data", "File Browser", DKShortcut("f", [.shift, .command])),
            ("Data", "Keychain Browser", DKShortcut("k", [.control, .command])),
            ("Data", "Preferences", DKShortcut("p", [.shift, .command])),
            ("Diagnostics", "Device Info", DKShortcut("i", [.option, .command])),
            ("Diagnostics", "Processes", DKShortcut("p", [.option, .command])),
            ("Diagnostics", "Services", DKShortcut("s", [.option, .command])),
            ("Diagnostics", "Console", DKShortcut("l", [.option, .command])),
            ("Diagnostics", "Crash Logs", DKShortcut("c", [.option, .command])),
            ("Capture", "Start Recording", DKShortcut("r", [.shift, .command])),
            ("Capture", "Copy Screenshot", DKShortcut("c", [.control, .command])),
            ("Capture", "Save Screenshot", DKShortcut("s", [.shift, .command])),
            ("Window", "Terminal", DKShortcut("3", [.option, .command])),
            ("Window", "New Terminal Tab", DKShortcut("t", [.command])),
        ]
        for (menu, title, shortcut) in expected {
            let item = try #require(bar.item(menu, title), "\(menu) › \(title)")
            let actual = DKShortcut(keyEquivalent: item.keyEquivalent, modifierMask: item.keyEquivalentModifierMask)
            #expect(actual == shortcut, "\(menu) › \(title)")
        }
    }

    @Test
    func `every display window button finds its menu item`() {
        let bar = VPhoneMenuBarFixture()
        for command in VPhoneMenuCommand.allCases {
            #expect(command.item != nil, "\(command)")
        }
        #expect(VPhoneMenuCommand.guestTools.item?.menu === bar.menu("Window"))
        #expect(VPhoneMenuCommand.rotateLeft.item?.menu === bar.menu("Device"))
    }

    /// An item whose target does not answer its action raises when chosen.
    /// Items without a target go up the responder chain.
    @Test
    func `every item's target answers its action`() {
        let bar = VPhoneMenuBarFixture()
        func check(_ menu: NSMenu) {
            for item in menu.items {
                // AppKit gives an item with a submenu its own target and action.
                if item.submenu == nil, let target = item.target as? NSObject, let action = item.action {
                    #expect(target.responds(to: action), "\(item.title): \(NSStringFromSelector(action))")
                    // NSObject's own `perform(_:)` would take the menu item as a selector.
                    #expect(action != #selector(NSObject.perform(_:)), "\(item.title)")
                }
                if let submenu = item.submenu {
                    check(submenu)
                }
            }
        }
        check(bar.mainMenu)
    }

    // MARK: - Connection

    @Test
    func `panels follow the agent's capabilities and go off on disconnect`() throws {
        let bar = VPhoneMenuBarFixture()
        let panels = ["Device Info", "Processes", "Services", "Console", "Crash Logs"]
        for title in panels {
            #expect(try #require(bar.item("Diagnostics", title)).isEnabled == false, "\(title) before connect")
        }
        #expect(try #require(bar.item("Input", "Controls")).isEnabled == false)
        #expect(!VPhoneMenuCommand.rotateLeft.isEnabled)

        bar.controller.updatePanelAvailability(capabilities: ["device_info", "processes", "logs", "display"])
        #expect(try #require(bar.item("Diagnostics", "Device Info")).isEnabled)
        #expect(try #require(bar.item("Diagnostics", "Processes")).isEnabled)
        #expect(try #require(bar.item("Diagnostics", "Services")).isEnabled == false)
        #expect(try #require(bar.item("Diagnostics", "Console")).isEnabled)
        #expect(try #require(bar.item("Diagnostics", "Crash Logs")).isEnabled)
        #expect(try #require(bar.item("Input", "Controls")).isEnabled)
        #expect(VPhoneMenuCommand.rotateLeft.isEnabled)

        bar.controller.updatePanelAvailability(capabilities: [])
        for title in panels {
            #expect(try #require(bar.item("Diagnostics", title)).isEnabled == false, "\(title) after disconnect")
        }
        #expect(!VPhoneMenuCommand.rotateLeft.isEnabled)
    }

    @Test
    func `agent items follow the connection`() throws {
        let bar = VPhoneMenuBarFixture()
        let items = [
            ("Data", "File Browser"), ("Data", "Keychain Browser"),
            ("Diagnostics", "Developer Mode Status"), ("Diagnostics", "Ping"), ("Diagnostics", "Guest Agent Hash"),
        ]
        for (menu, title) in items {
            #expect(try #require(bar.item(menu, title)).isEnabled == false, "\(title) before connect")
        }
        bar.controller.updateConnectAvailability(available: true)
        bar.controller.updateSettingsAvailability(available: true)
        for (menu, title) in items {
            #expect(try #require(bar.item(menu, title)).isEnabled, "\(title) while connected")
        }
        #expect(try #require(bar.item("Data", "Preferences")).isEnabled)
        #expect(try #require(bar.item("Data", "Write Preference…")).isEnabled)

        bar.controller.updateConnectAvailability(available: false)
        bar.controller.updateSettingsAvailability(available: false)
        for (menu, title) in items {
            #expect(try #require(bar.item(menu, title)).isEnabled == false, "\(title) after disconnect")
        }
        #expect(try #require(bar.item("Data", "Preferences")).isEnabled == false)
    }

    /// The Edit menu enables its items itself, so its Guest Clipboard items
    /// answer validation.
    @Test
    func `guest clipboard items validate with the clipboard capability`() throws {
        let bar = VPhoneMenuBarFixture()
        let edit = try #require(bar.menu("Edit"))
        let show = try #require(bar.item("Edit", "Show Guest Clipboard"))
        let set = try #require(bar.item("Edit", "Set Clipboard Text…"))

        edit.update()
        #expect(!show.isEnabled)
        #expect(!set.isEnabled)

        bar.controller.updateClipboardAvailability(available: true)
        edit.update()
        #expect(show.isEnabled)
        #expect(set.isEnabled)

        bar.controller.updateClipboardAvailability(available: false)
        edit.update()
        #expect(!show.isEnabled)
        #expect(!set.isEnabled)
    }

    // MARK: - Guest Tools

    @Test
    func `Guest Tools needs a connected agent`() {
        let bar = VPhoneMenuBarFixture()
        #expect(!VPhoneMenuCommand.guestTools.isEnabled)
        #expect(!VPhoneMenuCommand.guestTools.perform())

        // An agent without device_info still opens the window: every tool
        // the agent does not serve says so on its page.
        bar.controller.updatePanelAvailability(capabilities: ["apps"])
        #expect(VPhoneMenuCommand.guestTools.isEnabled)

        bar.controller.updatePanelAvailability(capabilities: [])
        #expect(!VPhoneMenuCommand.guestTools.isEnabled)
    }

    @Test
    func `Guest Tools opens on Device Info the first time, then on the last tool`() {
        let bar = VPhoneMenuBarFixture()
        let shell = bar.controller.guestPanelsWindowController.shell
        bar.controller.updatePanelAvailability(capabilities: ["device_info", "services"])
        defer { VPhoneGuestToolsShellWindow.close(shell) }

        #expect(VPhoneMenuCommand.guestTools.perform())
        #expect(shell.selection == .deviceInfo)
        #expect(VPhoneGuestToolsShellWindow.isVisible(shell))

        // Diagnostics › Services moves the window to Services; closing it
        // and choosing Guest Tools again comes back there.
        let services = bar.item("Diagnostics", "Services")
        #expect(services.map { bar.perform($0) } == true)
        #expect(shell.selection == .services)
        VPhoneGuestToolsShellWindow.close(shell)
        #expect(!VPhoneGuestToolsShellWindow.isVisible(shell))

        #expect(VPhoneMenuCommand.guestTools.perform())
        #expect(shell.selection == .services)
        #expect(VPhoneGuestToolsShellWindow.isVisible(shell))
    }

    // MARK: - Terminal

    @Test
    func `Terminal follows the terminal capability and says why it is off`() throws {
        let bar = VPhoneMenuBarFixture()
        let window = try #require(bar.menu("Window"))
        let terminal = try #require(bar.item("Window", "Terminal"))
        let newTab = try #require(bar.item("Window", "New Terminal Tab"))

        window.update()
        #expect(!terminal.isEnabled)
        #expect(!newTab.isEnabled)
        #expect(terminal.toolTip == VPhoneTerminalAvailability.notConnected.reason)

        // An agent from before the terminal: still off, with the reason.
        bar.controller.updatePanelAvailability(capabilities: ["apps", "device_info"])
        window.update()
        #expect(!terminal.isEnabled)
        #expect(terminal.toolTip == VPhoneTerminalAvailability.unsupported.reason)

        bar.controller.updatePanelAvailability(capabilities: ["apps", "terminal"])
        window.update()
        #expect(terminal.isEnabled)
        #expect(terminal.toolTip == nil)
        // ⌘T belongs to the guest until the Terminal window is key.
        #expect(!newTab.isEnabled)

        bar.controller.updatePanelAvailability(capabilities: [])
        window.update()
        #expect(!terminal.isEnabled)
    }

    // MARK: - Helpers

    /// The rows of an `NSMenu` as DesignKit menu items, with the shortcuts
    /// AppKit would match.
    static func designKitItems(_ menu: NSMenu) -> [DKMenuItem] {
        menu.items.map { item in
            if item.isSeparatorItem {
                return .separator
            }
            if item.isSectionHeader {
                return .header(item.title)
            }
            if let submenu = item.submenu {
                return .submenu(item.title, items: designKitItems(submenu))
            }
            return DKMenuItem(
                item.title,
                shortcut: DKShortcut(keyEquivalent: item.keyEquivalent, modifierMask: item.keyEquivalentModifierMask),
                isAlternate: item.isAlternate,
            )
        }
    }
}

// MARK: - Fixture

/// A `VPhoneMenuController` with the menu bar it installs as `NSApp.mainMenu`.
@MainActor
struct VPhoneMenuBarFixture {
    let control: VPhoneGuestControl
    let controller: VPhoneMenuController

    /// Key senders made without a VM. They are never used and never released:
    /// their stored properties were not initialized.
    private static var keySenders: [VPhoneVirtualMachineKeySender] = []

    init() {
        _ = NSApplication.shared
        control = VPhoneGuestControl()
        let instance: AnyObject = class_createInstance(VPhoneVirtualMachineKeySender.self, 0) as AnyObject
        let keySender = unsafeDowncast(instance, to: VPhoneVirtualMachineKeySender.self)
        Self.keySenders.append(keySender)
        controller = VPhoneMenuController(keySender: keySender, control: control)
    }

    var mainMenu: NSMenu {
        NSApp.mainMenu ?? NSMenu()
    }

    /// A top-level menu by its English title.
    func menu(_ title: String) -> NSMenu? {
        let title = VPhoneLocalization.text(title)
        return mainMenu.items.compactMap(\.submenu).first { $0.title == title }
    }

    /// An item of a top-level menu by their English titles.
    func item(_ menuTitle: String, _ title: String) -> NSMenuItem? {
        let title = VPhoneLocalization.text(title)
        return menu(menuTitle)?.items.first { $0.title == title }
    }

    /// Chooses an enabled item, as a click would.
    func perform(_ item: NSMenuItem) -> Bool {
        guard item.isEnabled, let menu = item.menu else { return false }
        menu.performActionForItem(at: menu.index(of: item))
        return true
    }
}

// MARK: - Guest Tools Window

/// The Guest Tools window of a shell, found by its delegate. A closed window
/// can linger in `NSApp.windows` until it is released, so only visible ones count.
@MainActor
enum VPhoneGuestToolsShellWindow {
    static func windows(_ shell: VPhoneGuestToolsShell) -> [NSWindow] {
        NSApp.windows.filter { $0.delegate === shell && $0.isVisible }
    }

    static func isVisible(_ shell: VPhoneGuestToolsShell) -> Bool {
        !windows(shell).isEmpty
    }

    static func close(_ shell: VPhoneGuestToolsShell) {
        windows(shell).forEach { $0.close() }
    }
}
