import AppKit
import Dynamic
import Foundation

// MARK: - Menu Controller

@MainActor
class VPhoneMenuController {
    let keySender: VPhoneVirtualMachineKeySender
    let control: VPhoneGuestControl
    let guestToolsWindowController: VPhoneGuestToolsWindowController
    let guestPanelsWindowController: VPhoneGuestPanelsWindowController
    weak var vm: VPhoneVirtualMachine? {
        didSet {
            hardwareKeyboardItem?.state = vm?.usesHardwareKeyboard == true ? .on : .off
            hardwareKeyboardItem?.isEnabled = vm != nil
            if let vm, let item = hardwareKeyboardItem {
                let count = (Dynamic(vm.virtualMachine)._keyboards.asObject as? NSArray)?.count
                print("[keyboard] Menu checked: \(item.state == .on), active keyboards: \(count.map(String.init) ?? "unknown")")
            }
        }
    }

    var hardwareKeyboardItem: NSMenuItem?
    var onHardwareKeyboardChange: ((Bool) async throws -> Void)?
    var onFrameRateDisplayChange: ((Bool) -> Void)?
    /// Saves the unlock-at-startup setting to this machine's config.plist.
    var onUnlockAtStartupChange: ((Bool) throws -> Void)?
    var unlockAtStartupItem: NSMenuItem?

    var onFilesPressed: (() -> Void)?
    var onKeychainPressed: (() -> Void)?
    var onFindPressed: (() -> Void)?
    var onAppsPressed: (() -> Void)?
    var connectFileBrowserItem: NSMenuItem?
    var connectKeychainBrowserItem: NSMenuItem?
    var connectDevModeStatusItem: NSMenuItem?
    var connectPingItem: NSMenuItem?
    var connectGuestHashItem: NSMenuItem?
    var installBootstrapItem: NSMenuItem?
    var installBootstrapFromFileItem: NSMenuItem?
    var uninstallBootstrapItem: NSMenuItem?
    var uninstallBootstrapNoRestartItem: NSMenuItem?
    var rebuildAppRegistrationsItem: NSMenuItem?
    var isInstallingBootstrap = false
    var isUninstallingBootstrap = false
    var isRebuildingAppRegistrations = false
    var installPackageItem: NSMenuItem?
    var clipboardGetItem: NSMenuItem?
    var clipboardSetItem: NSMenuItem?
    var appsListItem: NSMenuItem?
    var appsOpenURLItem: NSMenuItem?
    var settingsGetItem: NSMenuItem?
    var settingsSetItem: NSMenuItem?
    var restartGuestItem: NSMenuItem?
    var shutDownGuestItem: NSMenuItem?
    var setUDIDItem: NSMenuItem?
    var resetUDIDItem: NSMenuItem?
    var skipSetupAssistantItem: NSMenuItem?
    var panelMenuItems: [VPhoneGuestPanel: NSMenuItem] = [:]
    var rotateMenuItems: [NSMenuItem] = []
    var touchIDMonitor: VPhoneTouchIDMonitor? {
        didSet { touchIDMonitor?.isEnabled = touchIDMenuItem?.state == .on }
    }

    var touchIDMenuItem: NSMenuItem?
    var trackpadGesturesItem: NSMenuItem?
    var locationProvider: VPhoneLocationProvider?
    var locationMenuItem: NSMenuItem?
    var locationPresetMenuItem: NSMenuItem?
    var locationReplayStartItem: NSMenuItem?
    var locationReplayStopItem: NSMenuItem?
    var screenRecorder: VPhoneScreenRecorder?
    var recordingItem: NSMenuItem?
    var cameraServer: VPhoneCameraServer?
    var cameraStatusItem: NSMenuItem?
    var cameraSourceOffItem: NSMenuItem?
    var cameraSourceTestPatternItem: NSMenuItem?
    var cameraSourceVideoFileItem: NSMenuItem?
    var cameraStartStopItem: NSMenuItem?
    weak var captureView: VPhoneVirtualMachineView?
    var batterySyncEnabled = false
    var batteryHeaderItem: NSMenuItem?
    var batteryLevelItem: NSMenuItem?
    var batteryLevelMenuItems: [NSMenuItem] = []
    var batteryConnectivityMenuItems: [NSMenuItem] = []
    var powerSourceRunLoopSource: CFRunLoopSource?
    var powerSourceRetainedPtr: UnsafeMutableRawPointer?
    var lowPowerObserver: (any NSObjectProtocol)?
    /// Whether the agent serves the guest clipboard. The Edit menu enables its
    /// items itself, so its Guest Clipboard items read this when validated.
    var clipboardAvailable = false
    /// Targets of the items in menus that enable their items themselves.
    var menuItemValidators: [VPhoneMenuItemValidator] = []

    init(keySender: VPhoneVirtualMachineKeySender, control: VPhoneGuestControl) {
        self.keySender = keySender
        self.control = control
        guestToolsWindowController = VPhoneGuestToolsWindowController(control: control)
        guestPanelsWindowController = VPhoneGuestPanelsWindowController(control: control)
        setupMenuBar()
    }

    // MARK: - Menu Bar Setup

    /// The menus, grouped by what their items act on: the phone, how the Mac
    /// drives it, what the Mac simulates for it, its apps and data, then
    /// inspection, capture and windows.
    private func setupMenuBar() {
        let mainMenu = NSMenu()
        mainMenu.addItem(buildAppMenu())
        mainMenu.addItem(buildEditMenu())
        mainMenu.addItem(buildDeviceMenu())
        mainMenu.addItem(buildInputMenu())
        mainMenu.addItem(buildSimulateMenu())
        mainMenu.addItem(buildAppsMenu())
        mainMenu.addItem(buildDataMenu())
        mainMenu.addItem(buildDiagnosticsMenu())
        mainMenu.addItem(buildRecordMenu())
        mainMenu.addItem(buildWindowMenu())
        VPhoneLocalization.menu(mainMenu)
        NSApp.mainMenu = mainMenu
    }

    private func buildAppMenu() -> NSMenuItem {
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "VPhone")
        let buildItem = NSMenuItem(
            title: VPhoneLocalization.format("Build: %@", Self.buildDescription()),
            action: nil,
            keyEquivalent: "",
        )
        buildItem.isEnabled = false
        appMenu.addItem(buildItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit VPhone",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q",
        )
        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    /// The Mac's own editing commands, then the guest's clipboard.
    private func buildEditMenu() -> NSMenuItem {
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        let findItem = editMenu.addItem(
            withTitle: "Find…",
            action: #selector(findKeychain),
            keyEquivalent: "f",
        )
        findItem.target = self
        editMenu.addItem(NSMenuItem.separator())
        addGuestClipboardItems(to: editMenu)
        editMenuItem.submenu = editMenu
        return editMenuItem
    }

    /// Provides ⌘W and ⌘M for any key window, and opens Guest Tools.
    private func buildWindowMenu() -> NSMenuItem {
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w",
        )
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m",
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: "",
        )
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(makeGuestToolsItem())
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: "",
        )
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        return windowMenuItem
    }

    /// "2.3.2 (26, 735927f)": the bundle version, its build number and the
    /// commit `StageBundle.sh` stamped into the Info.plist. vphone-vm runs from
    /// `VPhone.bundle/Contents/MacOS`, so `Bundle.main` is that bundle.
    static func buildDescription() -> String {
        func value(_ key: String) -> String? {
            (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        let details = [value("CFBundleVersion"), value("VPhoneBuildHash")].compactMap(\.self)
        let detail = details.isEmpty ? nil : details.joined(separator: ", ")
        switch (value("CFBundleShortVersionString"), detail) {
        case let (version?, detail?): return "\(version) (\(detail))"
        case let (version?, nil): return version
        case let (nil, detail?): return detail
        case (nil, nil): return VPhoneLocalization.text("unknown")
        }
    }

    func makeItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        symbol: String? = nil,
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.image = symbol.flatMap(menuSymbol)
        return item
    }

    /// An item for a menu that enables its items itself, such as Edit or
    /// Window, whose responder-chain commands need it. AppKit asks the item's
    /// target whether it is enabled; `isEnabled` answers.
    func makeValidatedItem(
        _ title: String,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        symbol: String? = nil,
        isEnabled: @escaping @MainActor () -> Bool,
        action: @escaping @MainActor () -> Void,
    ) -> NSMenuItem {
        let validator = VPhoneMenuItemValidator(isEnabled: isEnabled, action: action)
        menuItemValidators.append(validator)
        let item = NSMenuItem(
            title: title,
            action: #selector(VPhoneMenuItemValidator.perform(_:)),
            keyEquivalent: keyEquivalent,
        )
        item.keyEquivalentModifierMask = modifiers
        item.target = validator
        item.image = symbol.flatMap(menuSymbol)
        return item
    }

    /// An SF Symbol for a menu item. Checkable items, value lists and status
    /// rows have none, so the icons mark actions, windows and submenus.
    func menuSymbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    @objc private func findKeychain() {
        onFindPressed?()
    }
}

// MARK: - Validated Items

/// The target of an item in a menu that enables its items itself. It runs the
/// controller's action and answers AppKit's validation for it. The menu item
/// holds its target weakly, so the controller keeps these.
@MainActor
final class VPhoneMenuItemValidator: NSObject, NSMenuItemValidation {
    private let isEnabled: @MainActor () -> Bool
    private let action: @MainActor () -> Void

    init(isEnabled: @escaping @MainActor () -> Bool, action: @escaping @MainActor () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    @objc func perform(_: Any?) {
        action()
    }

    func validateMenuItem(_: NSMenuItem) -> Bool {
        isEnabled()
    }
}
