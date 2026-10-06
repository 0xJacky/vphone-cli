import AppKit
import GhosttyTerminal
import Observation
import SwiftUI
import UniformTypeIdentifiers
import VPhoneDesignKit

// MARK: - Window Controller

/// The VM's one Terminal window: shell tabs in the guest, independent of the
/// display window. Window › Terminal opens it, or brings it forward; opening it
/// with no tab starts one. Closing a tab ends its shell, and closing the window
/// ends them all, so a shell never outlives what shows it.
///
/// Tabs live in split panes (`DKPaneGroupsModel`), after uTerm: drag a tab onto
/// a pane's edge to split it, onto its center to move the tab there, or drag a
/// splitter to resize. A pane whose last tab closes collapses, and the window
/// closes with its last tab. New tabs open in the active pane, and the keyboard
/// follows it.
@MainActor
@Observable
final class VPhoneTerminalWindowController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 860, height: 560)
    static let minimumSize = NSSize(width: 480, height: 300)
    /// Dragged tabs carry this type, declared in the bundle's Info.plist.
    static let tabDragType = UTType(exportedAs: "com.vphone.terminal-tab")

    let control: VPhoneGuestControl
    let machineName: String
    let panes = DKPaneGroupsModel<VPhoneTerminalSession>(
        policy: DKPaneGroupsPolicy(collapsesEmptyGroups: true, allowsLastGroupEmpty: false, keepAlive: .allTabs),
    )

    @ObservationIgnored fileprivate var window: NSWindow?

    init(control: VPhoneGuestControl, machineName: String) {
        self.control = control
        self.machineName = machineName
        super.init()
        panes.onTabRemoved = { removed, _ in removed.payload.close() }
        panes.onAreaEmptied = { [weak self] in self?.closeWindowIfOpen() }
        // The only tab of a pane dropped on that pane's own edge: a second
        // shell beside it, as in uTerm.
        panes.cloneTab = { [weak self] _ in self?.makeTab() }
    }

    // MARK: Showing

    /// Brings the window forward, creating it and a first tab when needed.
    func show() {
        let window = window ?? makeWindow()
        if panes.isEmpty {
            newTab()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        focusActivePane()
    }

    /// True while the Terminal window is the key window, for New Terminal Tab.
    var isKey: Bool {
        window?.isKeyWindow == true
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    // MARK: Tabs

    var sessions: [VPhoneTerminalSession] {
        panes.allTabs.map(\.payload)
    }

    /// Opens a shell in the active pane, or in `groupID`.
    func newTab(in groupID: UUID? = nil) {
        let tab = makeTab()
        panes.openTab({ tab }, in: groupID)
        focusActivePane()
    }

    /// Asks a tab to close: its shell ends.
    func closeTab(_ id: UUID) {
        panes.closeTab(id)
        focusActivePane()
    }

    /// Closes the window, ending every shell: the title bar's Disconnect and Close.
    func closeWindow() {
        window?.performClose(nil)
    }

    private func makeTab() -> DKPaneTab<VPhoneTerminalSession> {
        let number = VPhoneTerminalTabNumbering.next(after: sessions.map(\.number))
        let session = VPhoneTerminalSession(control: control, machineName: machineName, number: number)
        session.onStateChange = { [weak self] session in self?.stateChanged(session) }
        return DKPaneTab(id: session.id, payload: session)
    }

    private func stateChanged(_ session: VPhoneTerminalSession) {
        if session.state.closesTab {
            closeTab(session.id)
        }
    }

    private func closeWindowIfOpen() {
        if window?.isVisible == true {
            window?.close()
        }
    }

    /// Gives the keyboard to the active pane's terminal. Each pane also asks
    /// for it when its `DKActivePaneGate` turns active.
    func focusActivePane() {
        panes.activeTab?.payload.view.requestFocus()
    }

    fileprivate func tabItem(_ tab: DKPaneTab<VPhoneTerminalSession>) -> DKTab<UUID> {
        let session = tab.payload
        return DKTab(
            id: tab.id,
            title: VPhoneTerminalTabNumbering.title(machine: machineName, number: session.number),
            glyph: .terminal,
            statusTone: session.state.tone,
            help: help(for: session),
        )
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
        MainActor.assumeIsolated { focusActivePane() }
    }

    nonisolated func windowWillClose(_: Notification) {
        MainActor.assumeIsolated {
            // Every shell ends with the window; reset skips the removal hook.
            let sessions = sessions
            panes.reset()
            sessions.forEach { $0.close() }
            window = nil
        }
    }
}

// MARK: - Window Content

/// The Terminal window: compact title bar, the panes of shell tabs filling the
/// window, and a compact status bar. Every tab's terminal stays mounted,
/// hidden when not in front, so switching, moving or splitting keeps each
/// one's screen and scrollback.
struct VPhoneTerminalWindowView: View {
    let model: VPhoneTerminalWindowController

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
            DKPaneGroupArea(
                model: model.panes,
                dragType: VPhoneTerminalWindowController.tabDragType,
                label: VPhoneLocalization.text("Terminal tabs"),
                newTabLabel: VPhoneLocalization.text("New Terminal Tab"),
                tab: { model.tabItem($0) },
                onNewTab: { model.newTab(in: $0) },
                onRequestClose: { model.closeTab($0.id) },
                content: { tab, _ in VPhoneTerminalPane(session: tab.payload) },
                emptyGroup: { _ in DK.Palette.terminalBackground },
            )
            DK.Palette.divider.frame(height: DK.Metric.hairline)
            DKStatusBar(
                isConnected: control.isConnected,
                items: statusItems(control),
                detail: VPhoneLocalization.format("%ld tabs", model.panes.allTabs.count),
                compact: true,
            )
        }
        .background(DK.Palette.window)
        .environment(\.dkLocalizationBundle, VPhoneLocalization.bundle)
        .frame(minWidth: VPhoneTerminalWindowController.minimumSize.width, minHeight: VPhoneTerminalWindowController.minimumSize.height)
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

/// One shell's terminal in its pane. It takes the keyboard when its pane
/// becomes the active one, and only then: every pane stays mounted.
private struct VPhoneTerminalPane: View {
    let session: VPhoneTerminalSession
    @Environment(\.dkActivePaneGate) private var gate

    var body: some View {
        TerminalSurfaceView(context: session.view)
            .background(DK.Palette.terminalBackground)
            .onChange(of: gate?.isActive ?? false, initial: true) { _, isActive in
                if isActive {
                    session.view.requestFocus()
                }
            }
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
                "unknown terminal action \(action); use open, new_tab, select, focus_pane, move, close_tab, input, resize, close or state"
            case .noTab: "the Terminal window has no tab"
            case let .badArgument(text): text
            }
        }
    }

    /// One `{"t":"terminal","do":…}` request from the VM's control socket,
    /// as the window's own controls would do it. `index` counts tabs across
    /// every pane in order, `pane` counts panes.
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
            let tab = try tab(at: request["index"])
            if let at = panes.locateTab(tab.id) {
                panes.activateTab(groupID: at.groupID, index: at.index)
            }
            focusActivePane()
        case "focus_pane":
            panes.focusGroup(try pane(at: request["pane"]))
            focusActivePane()
        case "move":
            // What a drop does: the tab onto a pane's center or edge.
            let tab = try tab(at: request["index"])
            let pane = try pane(at: request["pane"])
            guard let zone = (request["zone"] as? String).flatMap(DKPaneDropZone.init(rawValue:)) else {
                throw AutomationError.badArgument("move needs a zone: center, top, bottom, leading or trailing")
            }
            panes.moveTab(tab.id, toGroup: pane, zone: zone)
            focusActivePane()
        case "close_tab":
            guard let tab = panes.activeTab else { throw AutomationError.noTab }
            closeTab(tab.id)
        case "input":
            guard let text = request["text"] as? String else {
                throw AutomationError.badArgument("input needs text")
            }
            guard let tab = panes.activeTab else { throw AutomationError.noTab }
            tab.payload.type(text)
        case "resize":
            guard let width = request["width"] as? Double, let height = request["height"] as? Double, let window else {
                throw AutomationError.badArgument("resize needs width and height, and an open window")
            }
            window.setContentSize(NSSize(width: width, height: height))
            if let x = request["x"] as? Double, let y = request["y"] as? Double,
               let screen = window.screen ?? NSScreen.main
            {
                // Top-left in screen points, as CGWindowList reports it.
                window.setFrameTopLeftPoint(NSPoint(x: x, y: screen.frame.maxY - y))
            }
        case "close":
            closeWindow()
        default:
            throw AutomationError.unknownAction(action)
        }
    }

    /// What the window shows: its id for `screencapture -l` and frame, the
    /// panes and their tabs with their state, and the active terminal's
    /// visible text.
    var automationState: [String: Any] {
        var state: [String: Any] = ["visible": isVisible, "key": isKey]
        if let window, window.isVisible {
            state["window_id"] = window.windowNumber
            state["width"] = window.contentLayoutRect.width
            state["height"] = window.contentLayoutRect.height
        }
        let tabs = panes.allTabs
        let activeTab = panes.activeTab?.id
        state["tabs"] = tabs.enumerated().map { index, tab in
            [
                "index": index,
                "title": VPhoneTerminalTabNumbering.title(machine: machineName, number: tab.payload.number),
                "pane": panes.locateTab(tab.id).flatMap { panes.groupIDs.firstIndex(of: $0.groupID) } ?? -1,
                "selected": tab.id == activeTab,
                "state": String(describing: tab.payload.state),
            ] as [String: Any]
        }
        state["panes"] = panes.groupIDs.enumerated().map { index, id in
            [
                "index": index,
                "active": id == panes.activeGroupID,
                "tabs": (panes.groups[id]?.tabs ?? []).compactMap { tab in tabs.firstIndex { $0.id == tab.id } },
            ] as [String: Any]
        }
        state["layout"] = Self.describe(panes.root, panes: panes.groupIDs)
        if let text = panes.activeTab?.payload.visibleText {
            state["text"] = text
        }
        return state
    }

    /// The split tree in one line: `H(0.50: 0 | V(0.50: 1 / 2))`.
    static func describe(_ layout: DKPaneLayout, panes: [UUID]) -> String {
        switch layout {
        case let .leaf(id):
            return panes.firstIndex(of: id).map(String.init) ?? "?"
        case let .split(split):
            let fraction = String(format: "%.2f", split.fraction)
            let first = describe(split.first, panes: panes)
            let second = describe(split.second, panes: panes)
            return split.direction == .horizontal
                ? "H(\(fraction): \(first) | \(second))"
                : "V(\(fraction): \(first) / \(second))"
        }
    }

    private func tab(at value: Any?) throws -> DKPaneTab<VPhoneTerminalSession> {
        let tabs = panes.allTabs
        guard let index = value as? Int, tabs.indices.contains(index) else {
            throw AutomationError.badArgument("index must name an open tab")
        }
        return tabs[index]
    }

    private func pane(at value: Any?) throws -> UUID {
        let ids = panes.groupIDs
        guard let index = value as? Int, ids.indices.contains(index) else {
            throw AutomationError.badArgument("pane must name an open pane")
        }
        return ids[index]
    }
}
