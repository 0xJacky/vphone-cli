import AppKit
import Testing
import VPhoneDesignKit
@testable import VPhoneVirtualMachineKit

/// The Guest Tools window: which tools a guest serves, and which tool the
/// window opens on.
@MainActor
@Suite("Guest Tools shell", .serialized)
struct VPhoneGuestToolsShellTests {
    // MARK: - Availability

    @Test
    func `every tool is available while the guest is not connected`() {
        for tool in DKGuestTool.allCases {
            #expect(VPhoneGuestToolsShell.availability(of: tool, isConnected: false, capabilities: []) == .available)
        }
    }

    @Test
    func `a connected agent serves the tools it reports capabilities for`() {
        let capabilities = ["device_info", "processes", "apps"]
        let availability = { (tool: DKGuestTool) in
            VPhoneGuestToolsShell.availability(of: tool, isConnected: true, capabilities: capabilities)
        }
        #expect(availability(.deviceInfo) == .available)
        #expect(availability(.processes) == .available)
        #expect(availability(.apps) == .available)
        #expect(availability(.services) == .unsupported(capability: "services"))
        #expect(availability(.controls) == .unsupported(capability: "display"))
        #expect(availability(.console) == .unsupported(capability: "logs"))
        #expect(availability(.crashLogs) == .unsupported(capability: "logs"))
        #expect(availability(.clipboard) == .unsupported(capability: "clipboard"))
        // Any connected agent serves files, Keychain and preferences.
        #expect(availability(.files) == .available)
        #expect(availability(.keychain) == .available)
        #expect(availability(.preferences) == .available)
    }

    @Test
    func `tools ask for the capability their menu items are gated on`() {
        for panel in VPhoneGuestPanel.allCases {
            #expect(panel.tool.requiredCapability == panel.capability, "\(panel)")
        }
    }

    @Test
    func `every tool has a title`() {
        for tool in DKGuestTool.allCases {
            #expect(!tool.title(bundle: VPhoneLocalization.bundle).isEmpty, "\(tool)")
        }
    }

    @Test
    func `the sidebar dims the tools a connected agent does not serve, with the reason`() {
        let unavailable = VPhoneGuestToolsShell.unavailableTools(isConnected: true, capabilities: ["device_info", "processes", "apps"])
        #expect(Set(unavailable.keys) == [.controls, .services, .console, .crashLogs, .clipboard])
        #expect(unavailable[.services]?.contains("services") == true)
        #expect(VPhoneGuestToolsShell.unavailableTools(isConnected: false, capabilities: []).isEmpty)

        let items = VPhoneGuestToolsSidebar.sections(unavailable: unavailable).flatMap(\.items)
        #expect(items.map(\.id) == DKGuestToolSection.allCases.flatMap(\.tools))
        for item in items {
            #expect(item.isEnabled == (unavailable[item.id] == nil), "\(item.id)")
            #expect(item.disabledReason == unavailable[item.id], "\(item.id)")
            #expect(item.meta == nil, "\(item.id)")
        }
    }

    // MARK: - Chrome

    @Test
    func `the window draws its own chrome, with no toolbar or system buttons`() throws {
        let shell = VPhoneGuestToolsShell(control: VPhoneGuestControl(), machineName: "test")
        defer { VPhoneGuestToolsShellWindow.close(shell) }
        shell.show(.apps)
        let window = try #require(VPhoneGuestToolsShellWindow.windows(shell).first)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        #expect(window.toolbar == nil)
        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titlebarSeparatorStyle == .none)
        #expect(window.styleMask.contains(.fullSizeContentView))
        // The sidebar's own buttons take over from the system ones.
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            #expect(window.standardWindowButton(kind)?.isHidden != false, "\(kind)")
        }
        // The title stays for the Window menu and accessibility.
        #expect(window.title == String(localized: "Guest Tools", bundle: VPhoneLocalization.bundle))
        #expect(window.subtitle == "test")
    }

    @Test
    func `find focuses the search field in the page header`() throws {
        let shell = VPhoneGuestToolsShell(control: VPhoneGuestControl(), machineName: "test")
        defer { VPhoneGuestToolsShellWindow.close(shell) }
        shell.show(.apps)
        let window = try #require(VPhoneGuestToolsShellWindow.windows(shell).first)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let root = try #require(window.contentView)
        let field = try #require(VPhoneGuestToolsShell.firstSearchField(in: root))
        shell.focusSearchField()
        let editor = window.firstResponder as? NSTextView
        #expect(window.firstResponder === field || editor?.delegate === field)
    }

    // MARK: - Last Tool

    @Test
    func `the window opens on Device Info until another tool is shown`() {
        let shell = VPhoneGuestToolsShell(control: VPhoneGuestControl(), machineName: "test")
        defer { VPhoneGuestToolsShellWindow.close(shell) }
        #expect(shell.selection == .deviceInfo)

        shell.showLastTool()
        #expect(shell.selection == .deviceInfo)
        #expect(VPhoneGuestToolsShellWindow.isVisible(shell))
    }

    @Test
    func `closing the window keeps the last tool for the next open`() {
        let shell = VPhoneGuestToolsShell(control: VPhoneGuestControl(), machineName: "test")
        defer { VPhoneGuestToolsShellWindow.close(shell) }

        shell.show(.processes)
        VPhoneGuestToolsShellWindow.close(shell)
        #expect(!VPhoneGuestToolsShellWindow.isVisible(shell))

        shell.showLastTool()
        #expect(shell.selection == .processes)
        #expect(VPhoneGuestToolsShellWindow.isVisible(shell))

        // Choosing a tool in the sidebar counts too.
        shell.selection = .services
        VPhoneGuestToolsShellWindow.close(shell)
        shell.showLastTool()
        #expect(shell.selection == .services)
    }

    @Test
    func `a Data menu entry point leaves the window on its tool`() {
        let control = VPhoneGuestControl()
        let tools = VPhoneGuestToolsWindowController(control: control)
        let panels = VPhoneGuestPanelsWindowController(control: control)
        defer { VPhoneGuestToolsShellWindow.close(tools.shell) }
        #expect(tools.shell === panels.shell)

        tools.show(.readSetting)
        #expect(tools.shell.selection == .preferences)
        #expect(tools.preferencesModel.mode == .read)
        VPhoneGuestToolsShellWindow.close(tools.shell)

        panels.shell.showLastTool()
        #expect(panels.shell.selection == .preferences)
    }
}
