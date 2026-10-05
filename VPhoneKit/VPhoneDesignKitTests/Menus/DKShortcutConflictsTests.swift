import Testing
@testable import VPhoneDesignKit

/// Shortcut clashes inside one menu tree and across a menu bar, and the
/// design's own menu bars, which must have none.
@Suite("DesignKit shortcut conflicts")
struct DKShortcutConflictsTests {
    @Test
    func `a clash inside one menu tree is reported with both paths`() throws {
        let conflicts = DKShortcutConflicts.find(in: [
            DKMenuItem("Start", shortcut: "⌘R"),
            DKMenuItem.submenu("Logs") {
                DKMenuItem("Reload", shortcut: "⌘R")
            },
            DKMenuItem("Stop", shortcut: "⌘."),
        ], menuTitle: "Machine")
        let conflict = try #require(conflicts.first)
        #expect(conflicts.count == 1)
        #expect(conflict.shortcut == "⌘R")
        #expect(conflict.paths == ["Machine › Start", "Machine › Logs › Reload"])
        #expect(conflict.description == "⌘R: Machine › Start, Machine › Logs › Reload")
    }

    @Test
    func `the old Shift-Command-K clash between two VM menus is caught`() {
        // Device > Use Hardware Keyboard and Data > Keychain Browser both had ⇧⌘K.
        let menus = [
            DKMenu("Device") { DKMenuItem("Use Hardware Keyboard", shortcut: "⇧⌘K").checked(true) },
            DKMenu("Data") { DKMenuItem("Keychain Browser", shortcut: "⇧⌘K").disabled() },
        ]
        let conflicts = DKShortcutConflicts.find(in: menus)
        #expect(conflicts == [DKShortcutConflicts.Conflict(
            shortcut: "⇧⌘K",
            paths: ["Device › Use Hardware Keyboard", "Data › Keychain Browser"],
        )])
    }

    @Test
    func `an upper-case key equivalent clashes with the same key written with Shift`() {
        let conflicts = DKShortcutConflicts.find(in: [
            DKMenuItem("Home Screen", shortcut: DKShortcut("H", .command)),
            DKMenuItem("Hide Others", shortcut: "⇧⌘H"),
        ])
        #expect(conflicts.count == 1)
    }

    @Test
    func `an alternate clashes through the shortcut it inherits`() {
        let conflicts = DKShortcutConflicts.find(in: [
            DKMenu("Machine") {
                DKMenuItem("Start", shortcut: "⌘R")
                DKMenuItem("Start Headless").alternate()
            },
            DKMenu("Capture") { DKMenuItem("Start Recording", shortcut: "⌥⌘R") },
        ])
        #expect(conflicts.map(\.paths) == [["Machine › Start Headless", "Capture › Start Recording"]])
    }

    @Test
    func `distinct shortcuts and items without one never clash`() {
        let conflicts = DKShortcutConflicts.find(in: [
            DKMenuItem("Copy", shortcut: "⌘C"),
            DKMenuItem("Copy Screenshot", shortcut: "⌃⌘C"),
            DKMenuItem("Show Guest Clipboard", shortcut: "⇧⌘C"),
            DKMenuItem("Crash Logs", shortcut: "⌥⌘C"),
            DKMenuItem("Power"),
            DKMenuItem("Volume Up"),
        ])
        #expect(conflicts.isEmpty)
    }

    @Test
    func `the design's VM window menu bar has no shortcut clashes`() {
        let conflicts = DKShortcutConflicts.find(in: Self.vmMenuBar)
        #expect(conflicts.isEmpty, "\(conflicts)")
        // The data really carries shortcuts: 30 of them.
        let shortcuts = Self.vmMenuBar.flatMap { DKMenuLayout($0.items).sections.flatMap(\.rows) }.compactMap(\.shortcut)
        #expect(shortcuts.count == 30)
    }

    @Test
    func `the design's Launchpad menu bar has no shortcut clashes`() {
        let conflicts = DKShortcutConflicts.find(in: Self.launchpadMenuBar)
        #expect(conflicts.isEmpty, "\(conflicts)")
    }

    // MARK: - Design data

    /// `VMMenus.dc.html`, re-typed: the menus of a running machine's window.
    static var vmMenuBar: [DKMenu] { [
        DKMenu("Edit") {
            DKMenuItem("Cut", shortcut: "⌘X")
            DKMenuItem("Copy", shortcut: "⌘C")
            DKMenuItem("Paste", shortcut: "⌘V")
            DKMenuItem("Select All", shortcut: "⌘A")
            DKMenuItem.separator
            DKMenuItem("Find", shortcut: "⌘F")
            DKMenuItem.separator
            DKMenuItem.header("Guest Clipboard")
            DKMenuItem("Show Guest Clipboard", shortcut: "⇧⌘C")
            DKMenuItem("Set Clipboard Text…")
            DKMenuItem("Type Mac Clipboard as ASCII")
        },
        DKMenu("Device") {
            DKMenuItem("Home Screen", shortcut: "⇧⌘H")
            DKMenuItem("Back", shortcut: "esc")
            DKMenuItem("Power")
            DKMenuItem("Volume Up")
            DKMenuItem("Volume Down")
            DKMenuItem.separator
            DKMenuItem("Rotate Left", shortcut: "⌘←")
            DKMenuItem("Rotate Right", shortcut: "⌘→")
            DKMenuItem.submenu("Orientation") {
                DKMenuItem("Portrait").checked(true)
                DKMenuItem("Landscape Left").checked(false)
                DKMenuItem("Landscape Right").checked(false)
            }
            DKMenuItem.separator
            DKMenuItem("Restart Guest…")
            DKMenuItem.separator
            DKMenuItem.header("Setup")
            DKMenuItem("Skip Setup Assistant…")
            DKMenuItem("Set UDID…")
            DKMenuItem("Reset UDID")
        },
        DKMenu("Input") {
            DKMenuItem("Controls", shortcut: "⌥⌘K")
            DKMenuItem.separator
            DKMenuItem("Use Hardware Keyboard", shortcut: "⇧⌘K").checked(true)
            DKMenuItem("Trackpad Scroll & Pinch to Touch").checked(true)
            DKMenuItem("Touch ID Home Forwarding").checked(true)
            DKMenuItem.separator
            DKMenuItem("Open Guest Spotlight")
            DKMenuItem("Switch Guest Input Source")
        },
        DKMenu("Simulate") {
            DKMenuItem.header("Location")
            DKMenuItem("Sync Host Location").checked(true)
            DKMenuItem.submenu("Preset Location") {}
            DKMenuItem("Start Route Replay")
            DKMenuItem("Stop Route Replay").disabled()
            DKMenuItem.separator
            DKMenuItem.header("Battery — 100%, charging")
            DKMenuItem("Sync with Host").checked(true)
            DKMenuItem.submenu("Level") {}
            DKMenuItem("Charging").checked(true)
            DKMenuItem("Not Charging")
            DKMenuItem.separator
            DKMenuItem.header("Camera — disconnected")
            DKMenuItem.submenu("Source") {}
            DKMenuItem("Start Streaming").disabled()
        },
        DKMenu("Apps") {
            DKMenuItem("App Browser", shortcut: "⇧⌘A")
            DKMenuItem.separator
            DKMenuItem("Open URL…")
            DKMenuItem("Install App Package…")
            DKMenuItem.separator
            DKMenuItem("Rebuild App Registrations")
            DKMenuItem.separator
            DKMenuItem.header("Bootstrap")
            DKMenuItem("Install Bootstrap…")
            DKMenuItem("Install from File…").alternate()
            DKMenuItem("Uninstall Bootstrap…")
            DKMenuItem("Uninstall Without Restarting…").alternate()
        },
        DKMenu("Data") {
            DKMenuItem("File Browser", shortcut: "⇧⌘F")
            DKMenuItem("Keychain Browser", shortcut: "⌃⌘K")
            DKMenuItem.separator
            DKMenuItem("Preferences", shortcut: "⇧⌘P")
            DKMenuItem("Write Preference…")
        },
        DKMenu("Diagnostics") {
            DKMenuItem("Device Info", shortcut: "⌥⌘I")
            DKMenuItem("Processes", shortcut: "⌥⌘P")
            DKMenuItem("Services", shortcut: "⌥⌘S")
            DKMenuItem.separator
            DKMenuItem("Console", shortcut: "⌥⌘L")
            DKMenuItem("Crash Logs", shortcut: "⌥⌘C")
            DKMenuItem.separator
            DKMenuItem("Show Frame Rate")
            DKMenuItem("Developer Mode Status")
            DKMenuItem.separator
            DKMenuItem.header("Guest Agent")
            DKMenuItem("Ping")
            DKMenuItem("Guest Agent Hash")
        },
        DKMenu("Capture") {
            DKMenuItem("Start Recording", shortcut: "⇧⌘R")
            DKMenuItem.separator
            DKMenuItem("Copy Screenshot", shortcut: "⌃⌘C")
            DKMenuItem("Save Screenshot…", shortcut: "⇧⌘S")
        },
        DKMenu("Window") {
            DKMenuItem.header("research-26")
            DKMenuItem("Display", shortcut: "⌥⌘1").checked(true)
            DKMenuItem("Workspace", shortcut: "⌥⌘2").checked(false)
            DKMenuItem("Terminal", shortcut: "⌥⌘3").checked(false)
            DKMenuItem("Files", shortcut: "⌥⌘4").checked(false)
            DKMenuItem.separator
            DKMenuItem("New Terminal Tab", shortcut: "⌘T")
            DKMenuItem.separator
            DKMenuItem("Minimize", shortcut: "⌘M")
            DKMenuItem("Zoom")
            DKMenuItem.separator
            DKMenuItem("Bring All to Front")
        },
    ] }

    /// `Menus.dc.html`, re-typed: Launchpad's menu bar.
    static var launchpadMenuBar: [DKMenu] { [
        DKMenu("VPhone Launchpad") {
            DKMenuItem("About VPhone Launchpad")
            DKMenuItem.separator
            DKMenuItem("Settings…", shortcut: "⌘,")
            DKMenuItem.separator
            DKMenuItem("Hide VPhone Launchpad", shortcut: "⌘H")
            DKMenuItem("Quit VPhone Launchpad", shortcut: "⌘Q")
        },
        DKMenu("File") {
            DKMenuItem("New Machine…", shortcut: "⌘N")
            DKMenuItem("Import…", shortcut: "⌘O")
            DKMenuItem.separator
            DKMenuItem("Close Window", shortcut: "⌘W")
        },
        DKMenu("View") {
            DKMenuItem("Machines", shortcut: "⌘1").checked(true)
            DKMenuItem("Firmwares", shortcut: "⌘2")
            DKMenuItem("Disks", shortcut: "⌘3")
            DKMenuItem("Bundles", shortcut: "⌘4")
            DKMenuItem("Network", shortcut: "⌘5")
            DKMenuItem("Host Setup", shortcut: "⌘6")
            DKMenuItem.separator
            DKMenuItem("Hide Sidebar", shortcut: "⌃⌘S")
            DKMenuItem("Hide Inspector", shortcut: "⌥⌘I")
        },
        DKMenu("Machine") {
            DKMenuItem("Start", shortcut: "⌘R")
            DKMenuItem("Start Headless", shortcut: "⌥⌘R")
            DKMenuItem("Stop", shortcut: "⌘.").disabled()
            DKMenuItem.separator
            DKMenuItem("Open in Terminal", shortcut: "⇧⌘C")
            DKMenuItem("Show in Finder")
            DKMenuItem.submenu("Logs") {
                DKMenuItem("Console Log")
                DKMenuItem("Patch Log")
            }
            DKMenuItem.separator
            DKMenuItem("Settings…", shortcut: "⌘I")
            DKMenuItem("Rename…")
            DKMenuItem("Clone…", shortcut: "⌘D")
            DKMenuItem("Export…", shortcut: "⇧⌘E")
            DKMenuItem.separator
            DKMenuItem.submenu("Core Bundle") {
                DKMenuItem("Change Core Bundle…")
                DKMenuItem("Update Guest Environment")
                DKMenuItem("Install Custom Firmware")
            }
            DKMenuItem.separator
            DKMenuItem("Delete…", shortcut: "⌘⌫").destructive()
        },
    ] }
}
