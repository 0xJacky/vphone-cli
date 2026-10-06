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
    /// The tool the window shows, kept while the window is closed so Guest
    /// Tools reopens on it. Device Info until another tool has been shown.
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

    /// Brings the window forward on the tool it showed last: Window > Guest
    /// Tools and the display window's title bar button.
    func showLastTool() {
        show(selection)
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

    /// Puts the keyboard focus in the search field in the shown page's header.
    func focusSearchField() {
        guard let window, let root = window.contentView,
              let field = Self.firstSearchField(in: root)
        else { return }
        window.makeFirstResponder(field)
    }

    static func firstSearchField(in view: NSView) -> NSSearchField? {
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
        Self.availability(of: tool, isConnected: control.isConnected, capabilities: control.guestCapabilities)
    }

    static func availability(
        of tool: DKGuestTool,
        isConnected: Bool,
        capabilities: [String],
    ) -> VPhoneGuestToolAvailability {
        guard isConnected, let capability = tool.requiredCapability else { return .available }
        return capabilities.contains(capability) ? .available : .unsupported(capability: capability)
    }

    /// The tools the connected agent does not serve, each with the reason the
    /// sidebar shows for it.
    var unavailableTools: [DKGuestTool: String] {
        Self.unavailableTools(isConnected: control.isConnected, capabilities: control.guestCapabilities)
    }

    static func unavailableTools(isConnected: Bool, capabilities: [String]) -> [DKGuestTool: String] {
        var tools: [DKGuestTool: String] = [:]
        for tool in DKGuestTool.allCases {
            if case let .unsupported(capability) = availability(of: tool, isConnected: isConnected, capabilities: capabilities) {
                tools[tool] = tool.unsupportedReason(capability: capability)
            }
        }
        return tools
    }

    // MARK: Window

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: VPhoneGuestToolsView(shell: self))
        // The window has no toolbar: every page keeps its tools and its
        // search field in its own header.
        hostingController.sceneBridgingOptions = []
        hostingController.sizingOptions = [.minSize]
        // The sidebar and the page headers run to the window's top edge, so
        // the title bar safe area must not push them down.
        hostingController.safeAreaRegions = []

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        // The chrome is the content's own: the sidebar draws the window
        // buttons, which hide the system ones, and each page header runs
        // under the transparent title bar. The title and subtitle are still
        // set for the Window menu and accessibility.
        window.title = String(localized: "Guest Tools", bundle: VPhoneLocalization.bundle)
        window.subtitle = machineName
        DKWindowChromeStyle.apply(to: window)
        window.contentViewController = hostingController
        window.contentMinSize = Self.minimumSize
        window.setContentSize(Self.defaultSize)
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

    /// Why the tool cannot be used: the agent does not report `capability`.
    func unsupportedReason(capability: String) -> String {
        let name = title(bundle: VPhoneLocalization.bundle)
        return String(
            localized: "The guest agent does not report the “\(capability)” capability. Update vphoned in the guest to use \(name).",
            bundle: VPhoneLocalization.bundle,
        )
    }
}
