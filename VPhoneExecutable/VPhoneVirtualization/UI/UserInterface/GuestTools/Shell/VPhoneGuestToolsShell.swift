import AppKit
import SwiftUI
import VPhoneDesignKit

// MARK: - Shell

/// The one Guest Tools window of a VM: the guest sidebar and the selected
/// tool's page. Every menu entry point (the Data menu, the Diagnostics and
/// Device panels, the App, File and Keychain browsers) opens this window on
/// its tool.
///
/// There is one shell per guest connection. The window controllers that the
/// menus and the app delegate own each hold it; it lives while any of them
/// does, and every tool's model lives with it, so closing and reopening the
/// window, or switching tools, keeps each tool's last loaded state.
@MainActor
@Observable
final class VPhoneGuestToolsShell: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 1180, height: 780)
    static let minimumSize = NSSize(width: 760, height: 480)

    let control: VPhoneGuestControl
    /// The VM's name, for the sidebar header and the window subtitle.
    let machineName: String
    /// The tool the window shows.
    var selection: DKGuestTool = .deviceInfo

    /// Called when Apps asks to show a path in the File Browser. When nil the
    /// shell switches to Files at that path itself.
    @ObservationIgnored var onRevealPath: ((String) -> Void)?

    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private let quickLookController = VPhoneQuickLookController()

    // MARK: Models

    // Created on first use and kept for the shell's lifetime.
    @ObservationIgnored private(set) lazy var deviceInfoModel = VPhoneDeviceInfoModel(control: control)
    @ObservationIgnored private(set) lazy var controlsModel = VPhoneControlsModel(control: control)
    @ObservationIgnored private(set) lazy var processesModel = VPhoneProcessesModel(control: control)
    @ObservationIgnored private(set) lazy var servicesModel = VPhoneServicesModel(control: control)
    @ObservationIgnored private(set) lazy var consoleModel = VPhoneConsoleModel(control: control)
    @ObservationIgnored private(set) lazy var crashLogsModel = VPhoneCrashLogsModel(control: control)
    @ObservationIgnored private(set) lazy var clipboardModel = VPhoneGuestClipboardModel(control: control)
    @ObservationIgnored private(set) lazy var preferencesModel = VPhoneGuestPreferencesModel(control: control)
    @ObservationIgnored private(set) lazy var keychainModel = VPhoneKeychainBrowserModel(control: control)
    @ObservationIgnored private(set) lazy var filesModel = VPhoneFileBrowserModel(
        control: control,
        quickLookController: quickLookController,
    )
    @ObservationIgnored private(set) lazy var appsModel: VPhoneAppBrowserModel = {
        let model = VPhoneAppBrowserModel(control: control)
        model.onRevealPath = { [weak self] path in self?.revealPath(path) }
        return model
    }()

    // MARK: Registry

    /// Shells by guest connection. Weak, so a shell goes away with the window
    /// controllers that hold it, as on a restart for a hardware keyboard change.
    private static var shells: [ObjectIdentifier: WeakShell] = [:]

    private struct WeakShell {
        weak var shell: VPhoneGuestToolsShell?
    }

    /// The shell for a guest connection, made on first use.
    static func shared(for control: VPhoneGuestControl) -> VPhoneGuestToolsShell {
        shells = shells.filter { $0.value.shell != nil }
        let key = ObjectIdentifier(control)
        if let shell = shells[key]?.shell, shell.control === control {
            return shell
        }
        let shell = VPhoneGuestToolsShell(control: control, machineName: VPhoneGuestToolsShell.currentMachineName())
        shells[key] = WeakShell(shell: shell)
        return shell
    }

    init(control: VPhoneGuestControl, machineName: String) {
        self.control = control
        self.machineName = machineName
        super.init()
    }

    // MARK: Showing

    /// Brings the window forward on `tool`, creating it the first time.
    func show(_ tool: DKGuestTool) {
        selection = tool
        let window = window ?? makeWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Shows Files at a guest directory, such as an app's data container.
    func showFiles(at path: String) {
        let isShowingFiles = window?.isVisible == true && selection == .files
        show(.files)
        guard filesModel.currentPath != path else { return }
        if isShowingFiles {
            filesModel.navigate(to: path)
        } else {
            // The Files page loads `currentPath` when it appears.
            filesModel.currentPath = path
        }
    }

    /// True while the window is key and shows `tool`.
    func isKey(showing tool: DKGuestTool) -> Bool {
        window?.isKeyWindow == true && selection == tool
    }

    /// Puts the keyboard focus in the first search field of the shown page.
    func focusSearchField() {
        guard let window, let root = window.contentView else { return }
        if let field = Self.firstSearchField(in: root) ?? window.toolbar?.items
            .compactMap({ ($0 as? NSSearchToolbarItem)?.searchField }).first
        {
            window.makeFirstResponder(field)
        }
    }

    private static func firstSearchField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField, !field.isHidden {
            return field
        }
        for subview in view.subviews {
            if let field = firstSearchField(in: subview) {
                return field
            }
        }
        return nil
    }

    private func revealPath(_ path: String) {
        if let onRevealPath {
            onRevealPath(path)
        } else {
            showFiles(at: path)
        }
    }

    // MARK: Availability

    /// Whether the connected agent serves `tool`. While the guest is not
    /// connected every tool is available, and its page says the guest is not
    /// connected.
    func availability(of tool: DKGuestTool) -> VPhoneGuestToolAvailability {
        guard control.isConnected, let capability = tool.requiredCapability else { return .available }
        return control.guestCapabilities.contains(capability) ? .available : .unsupported(capability: capability)
    }

    // MARK: Window

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: VPhoneGuestToolsView(shell: self))
        // Pages that still put their tools in a window toolbar keep them there.
        hostingController.sceneBridgingOptions = [.toolbars]
        hostingController.sizingOptions = [.minSize]

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.title = String(localized: "Guest Tools", bundle: VPhoneLocalization.bundle)
        window.subtitle = machineName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentViewController = hostingController
        window.contentMinSize = Self.minimumSize
        window.setContentSize(Self.defaultSize)
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.delegate = self
        window.setFrameAutosaveName("vphone-guest-tools")
        if window.frame.origin == .zero {
            window.center()
        }

        // Quick Look finds Files' preview controller through the window's
        // responder chain.
        quickLookController.nextResponder = window.nextResponder
        window.nextResponder = quickLookController

        self.window = window
        return window
    }

    nonisolated func windowWillClose(_: Notification) {
        MainActor.assumeIsolated {
            filesModel.closeQuickLook()
            window = nil
        }
    }

    // MARK: Machine Name

    /// The VM's name: the folder holding the `--config` manifest this process
    /// was started with.
    private static func currentMachineName() -> String {
        let arguments = CommandLine.arguments
        var path: String?
        for (index, argument) in arguments.enumerated() {
            if argument == "--config" || argument == "-c", index + 1 < arguments.count {
                path = arguments[index + 1]
            } else if argument.hasPrefix("--config=") {
                path = String(argument.dropFirst("--config=".count))
            }
        }
        if let path, !path.isEmpty {
            return VPhoneDockName.name(forConfig: URL(fileURLWithPath: path))
        }
        return ProcessInfo.processInfo.processName
    }
}

// MARK: - Availability

enum VPhoneGuestToolAvailability: Equatable {
    case available
    /// The agent does not report this `/v1/health` capability.
    case unsupported(capability: String)
}

extension DKGuestTool {
    /// The `/v1/health` capability the agent must report before the tool can
    /// talk to it, or nil for tools any connected agent serves. The panels
    /// keep the capabilities their menu items are gated on.
    var requiredCapability: String? {
        switch self {
        case .deviceInfo: VPhoneGuestPanel.deviceInfo.capability
        case .controls: VPhoneGuestPanel.controls.capability
        case .processes: VPhoneGuestPanel.processes.capability
        case .services: VPhoneGuestPanel.services.capability
        case .console: VPhoneGuestPanel.console.capability
        case .crashLogs: VPhoneGuestPanel.crashLogs.capability
        case .apps: "apps"
        case .clipboard: "clipboard"
        case .files, .keychain, .preferences: nil
        }
    }

    /// The title in the user's language.
    var localizedTitle: String {
        switch self {
        case .deviceInfo: String(localized: "Device Info", bundle: VPhoneLocalization.bundle)
        case .controls: String(localized: "Controls", bundle: VPhoneLocalization.bundle)
        case .apps: String(localized: "Apps", bundle: VPhoneLocalization.bundle)
        case .processes: String(localized: "Processes", bundle: VPhoneLocalization.bundle)
        case .services: String(localized: "Services", bundle: VPhoneLocalization.bundle)
        case .files: String(localized: "Files", bundle: VPhoneLocalization.bundle)
        case .keychain: String(localized: "Keychain", bundle: VPhoneLocalization.bundle)
        case .preferences: String(localized: "Preferences", bundle: VPhoneLocalization.bundle)
        case .clipboard: String(localized: "Clipboard", bundle: VPhoneLocalization.bundle)
        case .console: String(localized: "Console", bundle: VPhoneLocalization.bundle)
        case .crashLogs: String(localized: "Crash Logs", bundle: VPhoneLocalization.bundle)
        }
    }
}
