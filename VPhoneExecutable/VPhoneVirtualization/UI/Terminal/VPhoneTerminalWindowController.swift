import AppKit
import GhosttyTerminal
import Observation
import SwiftUI
import VPhoneDesignKit

// MARK: - Window Controller

/// The VM's one Terminal window: shell tabs in the guest, independent of the
/// display window. Window › Terminal opens it, or brings it forward; opening it
/// with no tab starts one. Closing a tab ends its shell, and closing the window
/// ends them all, so a shell never outlives what shows it.
@MainActor
@Observable
final class VPhoneTerminalWindowController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 860, height: 560)
    static let minimumSize = NSSize(width: 480, height: 300)

    let control: VPhoneGuestControl
    let machineName: String
    private(set) var sessions: [VPhoneTerminalSession] = []
    fileprivate var tabList = VPhoneTerminalTabList<UUID>()

    @ObservationIgnored fileprivate var window: NSWindow?

    init(control: VPhoneGuestControl, machineName: String) {
        self.control = control
        self.machineName = machineName
        super.init()
    }

    // MARK: Showing

    /// Brings the window forward, creating it and a first tab when needed.
    func show() {
        let window = window ?? makeWindow()
        if sessions.isEmpty {
            newTab()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        focusSelection()
    }

    /// True while the Terminal window is the key window, for New Terminal Tab.
    var isKey: Bool {
        window?.isKeyWindow == true
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    // MARK: Tabs

    var selection: UUID? {
        get { tabList.selection }
        set {
            guard newValue != tabList.selection else { return }
            tabList.selection = newValue
            focusSelection()
        }
    }

    /// The strip's tabs; setting it keeps the tabs the strip kept, which is
    /// how its close buttons close a tab.
    var tabs: [DKTab<UUID>] {
        get {
            tabList.entries.compactMap { entry in
                guard let session = session(entry.id) else { return nil }
                return DKTab(
                    id: entry.id,
                    title: VPhoneTerminalTabList<UUID>.title(machine: machineName, number: entry.number),
                    glyph: .terminal,
                    statusTone: session.state.tone,
                    help: help(for: session),
                )
            }
        }
        set {
            for id in tabList.keep(newValue.map(\.id)) {
                end(id)
            }
            closeWindowIfEmpty()
        }
    }

    func newTab() {
        let session = VPhoneTerminalSession(control: control, machineName: machineName)
        session.onStateChange = { [weak self] session in self?.stateChanged(session) }
        sessions.append(session)
        tabList.add(session.id)
        focusSelection()
    }

    func closeTab(_ id: UUID) {
        guard tabList.ids.contains(id) else { return }
        tabList.remove(id)
        end(id)
        closeWindowIfEmpty()
        focusSelection()
    }

    /// Closes the window, ending every shell: the title bar's Disconnect and Close.
    func closeWindow() {
        window?.performClose(nil)
    }

    fileprivate func session(_ id: UUID) -> VPhoneTerminalSession? {
        sessions.first { $0.id == id }
    }

    private func end(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: index).close()
    }

    private func stateChanged(_ session: VPhoneTerminalSession) {
        if session.state.closesTab {
            closeTab(session.id)
        }
    }

    private func closeWindowIfEmpty() {
        if tabList.isEmpty, window?.isVisible == true {
            window?.close()
        }
    }

    private func focusSelection() {
        guard let id = tabList.selection, let session = session(id) else { return }
        session.view.requestFocus()
    }

    private func help(for session: VPhoneTerminalSession) -> String? {
        switch session.state {
        case let .running(shell): shell
        case .connecting: VPhoneLocalization.text("Starting a shell in the guest…")
        default: session.state.notice
        }
    }

    // MARK: Window

    private func makeWindow() -> NSWindow {
        let content = NSHostingView(rootView: VPhoneTerminalWindowView(model: self))
        content.sizingOptions = [.minSize]
        // The title bar sits at the window's top edge by design; the system
        // title bar's safe area must not push it down.
        content.safeAreaRegions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.title = DKVMWindowKind.terminal.title(machine: machineName)
        // The chrome is the content's own, window buttons included: the title
        // bar's DKWindowControls hide the system ones, and bring them back in
        // full screen. `window.title` still names the window in the Window
        // menu and for accessibility.
        DKWindowChromeStyle.apply(to: window)
        window.contentView = content
        window.contentMinSize = Self.minimumSize
        window.setContentSize(Self.defaultSize)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.delegate = self
        window.setFrameAutosaveName("vphone-terminal")
        if window.frame.origin == .zero {
            window.center()
        }
        self.window = window
        return window
    }


    nonisolated func windowDidBecomeKey(_: Notification) {
        MainActor.assumeIsolated { focusSelection() }
    }

    nonisolated func windowWillClose(_: Notification) {
        MainActor.assumeIsolated {
            for id in tabList.ids {
                tabList.remove(id)
                end(id)
            }
            window = nil
        }
    }
}

// MARK: - Window Content

/// The Terminal window: compact title bar, the shell tabs, the selected
/// shell's terminal filling the window, and a compact status bar. Every tab's
/// terminal stays in the view, hidden when not selected, so switching tabs
/// keeps each one's screen and scrollback.
struct VPhoneTerminalWindowView: View {
    @Bindable var model: VPhoneTerminalWindowController


    var body: some View {
        let control = model.control
        VStack(spacing: 0) {
            DKTitleBar(
                machine: model.machineName,
                kind: .terminal,
                tone: control.isConnected ? .success : .warning,
                status: control.isConnected ? VPhoneLocalization.text("Running") : nil,
                os: osText(control),
                address: control.isConnected ? control.guestIPAddress : nil,
                actions: [
                    DKButtonSpec(
                        VPhoneLocalization.text("Disconnect and Close"),
                        glyph: .stop,
                        variant: .ghost,
                        size: .icon,
                        id: "disconnect-and-close",
                        action: { model.closeWindow() },
                    ),
                ],
            )
            DKTabStrip(
                tabs: $model.tabs,
                selection: $model.selection,
                label: VPhoneLocalization.text("Terminal tabs"),
                newTabLabel: VPhoneLocalization.text("New Terminal Tab"),
                onNewTab: { model.newTab() },
            )
            terminals
            DK.Palette.divider.frame(height: DK.Metric.hairline)
            DKStatusBar(
                isConnected: control.isConnected,
                items: statusItems(control),
                detail: VPhoneLocalization.format("%ld tabs", model.sessions.count),
                compact: true,
            )
        }
        .background(DK.Palette.window)
        .environment(\.dkLocalizationBundle, VPhoneLocalization.bundle)
        .frame(minWidth: VPhoneTerminalWindowController.minimumSize.width, minHeight: VPhoneTerminalWindowController.minimumSize.height)
    }

    private var terminals: some View {
        ZStack {
            DK.Palette.terminalBackground
            ForEach(model.sessions) { session in
                let isSelected = session.id == model.selection
                TerminalSurfaceView(context: session.view)
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .accessibilityHidden(!isSelected)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func osText(_ control: VPhoneGuestControl) -> String {
        if control.isConnected, let version = control.guestIOSVersion, !version.isEmpty {
            return "iOS \(version)"
        }
        return VPhoneLocalization.text(control.isConnected ? "Guest agent connected" : "Guest agent not connected")
    }

    private func statusItems(_ control: VPhoneGuestControl) -> [DKStatusItem] {
        guard control.isConnected else { return [] }
        var items: [DKStatusItem] = []
        if let version = control.guestIOSVersion, !version.isEmpty {
            items.append(DKStatusItem("iOS \(version)", glyph: .phone, title: VPhoneLocalization.text("Guest OS")))
        }
        if let address = control.guestIPAddress, !address.isEmpty {
            items.append(DKStatusItem(address, glyph: .network, title: VPhoneLocalization.text("Address")))
        }
        return items
    }
}

// MARK: - Automation

extension VPhoneTerminalWindowController {
    enum AutomationError: Error, CustomStringConvertible {
        case unknownAction(String)
        case noTab
        case badArgument(String)

        var description: String {
            switch self {
            case let .unknownAction(action):
                "unknown terminal action \(action); use open, new_tab, select, close_tab, input, resize, close or state"
            case .noTab: "the Terminal window has no tab"
            case let .badArgument(text): text
            }
        }
    }

    /// One `{"t":"terminal","do":…}` request from the VM's control socket,
    /// as the window's own controls would do it.
    func perform(automation request: [String: Any]) throws {
        let action = request["do"] as? String ?? "state"
        switch action {
        case "state":
            break
        case "open":
            show()
        case "new_tab":
            show()
            newTab()
        case "select":
            guard let index = request["index"] as? Int, tabList.ids.indices.contains(index) else {
                throw AutomationError.badArgument("select needs the index of an open tab")
            }
            selection = tabList.ids[index]
        case "close_tab":
            guard let id = tabList.selection else { throw AutomationError.noTab }
            closeTab(id)
        case "input":
            guard let text = request["text"] as? String else {
                throw AutomationError.badArgument("input needs text")
            }
            guard let session = selectedSession else { throw AutomationError.noTab }
            session.type(text)
        case "resize":
            guard let width = request["width"] as? Double, let height = request["height"] as? Double,
                  let window
            else {
                throw AutomationError.badArgument("resize needs width and height, and an open window")
            }
            window.setContentSize(NSSize(width: width, height: height))
        case "close":
            closeWindow()
        default:
            throw AutomationError.unknownAction(action)
        }
    }

    /// What the window shows: its id for `screencapture -l`, its size, the
    /// tabs with their state, and the selected terminal's visible text.
    var automationState: [String: Any] {
        var state: [String: Any] = ["visible": isVisible, "key": isKey]
        if let window, window.isVisible {
            state["window_id"] = window.windowNumber
            state["width"] = window.contentLayoutRect.width
            state["height"] = window.contentLayoutRect.height
        }
        state["tabs"] = tabs.enumerated().map { index, tab in
            let session = session(tab.id)
            return [
                "index": index,
                "title": tab.title,
                "selected": tab.id == selection,
                "state": session.map { String(describing: $0.state) } ?? "closed",
            ] as [String: Any]
        }
        if let text = selectedSession?.visibleText {
            state["text"] = text
        }
        return state
    }

    private var selectedSession: VPhoneTerminalSession? {
        tabList.selection.flatMap { session($0) }
    }
}
