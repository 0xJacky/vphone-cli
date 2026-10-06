import Testing
@testable import VPhoneDesignKit

/// The Launchpad and Guest Tools sidebars, and the sidebar item model.
@Suite("DesignKit sidebars")
struct DKSidebarTests {
    // MARK: Launchpad

    @Test
    func `launchpad destinations fall into Library then System in sidebar order`() {
        #expect(DKLaunchpadSection.allCases.map(\.title) == ["Library", "System"])
        #expect(DKLaunchpadSection.library.destinations == [.machines, .firmwares, .disks])
        #expect(DKLaunchpadSection.system.destinations == [.bundles, .network, .hostSetup])
        #expect(DKLaunchpadDestination.allCases.map(\.title) == ["Machines", "Firmwares", "Disks", "Bundles", "Network", "Host Setup"])
    }

    @Test
    func `launchpad destinations use the design's glyphs`() {
        #expect(DKLaunchpadDestination.allCases.map(\.glyph) == [.phone, .image, .disk, .bundle, .network, .checklist])
    }

    @Test
    func `the launchpad sidebar shows running machines, counts and the host setup warning, and no bundle version`() throws {
        let sections = DKLaunchpadSidebar.sections(
            runningMachines: 1,
            machineCount: 4,
            firmwareCount: 4,
            hostSetupNeedsAttention: true,
        )
        #expect(sections.map(\.title) == ["Library", "System"])
        let items = sections.allSidebarItems()
        #expect(items.map(\.id) == DKLaunchpadDestination.allCases)

        let machines = try #require(items.first { $0.id == .machines })
        #expect(machines.trailingText == "1/4")
        #expect(machines.metaTone == .success)

        let firmwares = try #require(items.first { $0.id == .firmwares })
        #expect(firmwares.trailingText == "4")
        #expect(firmwares.metaTone == nil)

        let bundles = try #require(items.first { $0.id == .bundles })
        #expect(bundles.trailingText == nil)

        let host = try #require(items.first { $0.id == .hostSetup })
        #expect(host.isWarning)
        #expect(items.filter(\.isWarning).map(\.id) == [.hostSetup])
    }

    @Test
    func `no machine running dims the dot, and a lone machine count shows as a count`() throws {
        let idle = try #require(DKLaunchpadSidebar.sections(runningMachines: 0, machineCount: 3).allSidebarItems().first)
        #expect(idle.trailingText == "0/3")
        #expect(idle.metaTone == .idle)

        let counted = try #require(DKLaunchpadSidebar.sections(machineCount: 3).allSidebarItems().first)
        #expect(counted.trailingText == "3")
        #expect(counted.metaTone == nil)

        let bare = DKLaunchpadSidebar.sections().allSidebarItems()
        #expect(bare.allSatisfy { $0.trailingText == nil && !$0.isWarning })
    }

    @Test
    func `the launchpad footer has the helper line with its dot and the library path in monospace`() {
        let lines = DKLaunchpadSidebar.footerLines(helperStatus: "Helper 2.6.0 ready", helperTone: .success, libraryPath: "~/VPhone")
        #expect(lines == [
            DKSidebarFooterLine("Helper 2.6.0 ready", tone: .success),
            DKSidebarFooterLine("~/VPhone", isMonospaced: true),
        ])
        #expect(DKLaunchpadSidebar.footerLines(helperStatus: nil, helperTone: .success, libraryPath: nil).isEmpty)
    }

    // MARK: Guest Tools

    @Test
    func `guest tools fall into Device, Software, Data and Logs in sidebar order`() {
        #expect(DKGuestToolSection.allCases.map(\.title) == ["Device", "Software", "Data", "Logs"])
        #expect(DKGuestToolSection.device.tools == [.deviceInfo, .controls])
        #expect(DKGuestToolSection.software.tools == [.apps, .processes, .services])
        #expect(DKGuestToolSection.data.tools == [.files, .keychain, .preferences, .clipboard])
        #expect(DKGuestToolSection.logs.tools == [.console, .crashLogs])
        #expect(DKGuestToolSection.allCases.flatMap(\.tools) == DKGuestTool.allCases)
    }

    @Test
    func `guest tools have the design's titles and glyphs`() {
        #expect(DKGuestTool.allCases.count == 11)
        #expect(DKGuestTool.allCases.map(\.title) == [
            "Device Info", "Controls", "Apps", "Processes", "Services",
            "Files", "Keychain", "Preferences", "Clipboard", "Console", "Crash Logs",
        ])
        #expect(DKGuestTool.allCases.map(\.glyph) == [
            .info, .sliders, .apps, .cpu, .gear,
            .folder, .key, .list, .clipboard, .terminal, .warning,
        ])
    }

    @Test
    func `the guest sidebar carries counts and no warnings, and its facts skip what is unknown`() {
        let sections = DKGuestSidebar.sections(counts: [.crashLogs: 3])
        #expect(sections.map(\.title) == ["Device", "Software", "Data", "Logs"])
        let items = sections.allSidebarItems()
        #expect(items.map(\.id) == DKGuestTool.allCases)
        #expect(items.first { $0.id == .crashLogs }?.trailingText == "3")
        #expect(items.filter { $0.trailingText != nil }.count == 1)
        #expect(items.allSatisfy { !$0.isWarning })

        #expect(DKGuestSidebar.facts(iOSVersion: "26.6.2", address: "192.168.64.12") == [
            DKSidebarFact("iOS", "26.6.2"),
            DKSidebarFact("Address", "192.168.64.12", isMonospaced: true),
        ])
        #expect(DKGuestSidebar.facts(iOSVersion: nil, address: "10.0.0.2").map(\.label) == ["Address"])
    }

    // MARK: Item model

    @Test
    func `meta text wins over a count, and empty meta falls back to the count`() {
        #expect(DKSidebarItem(id: 1, label: "A", glyph: .disk, meta: "2.6.0", count: 4).trailingText == "2.6.0")
        #expect(DKSidebarItem(id: 1, label: "A", glyph: .disk, meta: "", count: 4).trailingText == "4")
        #expect(DKSidebarItem(id: 1, label: "A", glyph: .disk).trailingText == nil)
    }

    @Test
    func `voiceover reads the label, the trailing text and the warning`() {
        let item = DKSidebarItem(id: 1, label: "Host Setup", glyph: .checklist, isWarning: true, count: 2)
        #expect(item.accessibilityText == "Host Setup, 2, Needs attention")
        #expect(DKSidebarItem(id: 1, label: "Disks", glyph: .disk).accessibilityText == "Disks")
    }

    @Test
    func `untitled sections get distinct ids from their items`() {
        let a = DKSidebarSection(items: [DKSidebarItem(id: "a", label: "A", glyph: .disk)])
        let b = DKSidebarSection(items: [DKSidebarItem(id: "b", label: "B", glyph: .disk)])
        #expect(a.id != b.id)
        #expect(DKSidebarSection("Library", items: [DKSidebarItem<String>]()).id == "Library")
    }

    @Test
    func `arrow keys move across sections and stop at the ends`() {
        let sections = DKLaunchpadSidebar.sections()
        #expect(sections.sidebarItemID(from: .disks, offset: 1) == .bundles)
        #expect(sections.sidebarItemID(from: .bundles, offset: -1) == .disks)
        #expect(sections.sidebarItemID(from: .hostSetup, offset: 1) == .hostSetup)
        #expect(sections.sidebarItemID(from: .machines, offset: -1) == .machines)
        #expect(sections.sidebarItemID(from: nil, offset: 1) == .machines)
        #expect(sections.sidebarItemID(from: nil, offset: -1) == .hostSetup)
        #expect([DKSidebarSection<Int>]().sidebarItemID(from: nil, offset: 1) == nil)
    }
}
