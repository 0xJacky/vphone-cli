import AppKit
import SwiftUI
import VPhoneDesignKit

// MARK: - Actions

/// Every action on machines, in one order: run, inspect, configure,
/// maintain, delete. The table's context menu, the inspector's ⋯ button, the
/// multiple-selection inspector and the menu bar's Machine menu share it:
/// `VPhoneLaunchpadMachineMenu` decides the items and their enablement, this
/// gives each one its title, shortcut and action.
///
/// Sheets and the delete confirmation are the library's page state, so the
/// menu bar reaches them from any page; asking for one shows the Machines
/// page.
struct VPhoneLaunchpadMachineActions {
    typealias MachinePath = VPhoneLaunchpadMachinePath
    typealias Plan = VPhoneLaunchpadMachineMenu

    let model: VPhoneLaunchpadModel

    private var library: VPhoneLaunchpadMachineLibrary {
        model.machines
    }

    // MARK: - Page state

    /// Opens one of the Machines page's sheets.
    func present(_ sheet: VPhoneLaunchpadMachinesView.Sheet) {
        if model.destination != .machines {
            model.show(.machines)
        }
        library.sheet = sheet
    }

    /// Asks to delete the machines; the page confirms first.
    func delete(_ machines: [MachinePath]) {
        if model.destination != .machines {
            model.show(.machines)
        }
        library.deletion = machines
    }

    /// New Machine needs a Core Bundle to create with.
    var canCreate: Bool {
        model.bundles.defaultVersion != nil
    }

    /// Import waits for another import, and needs a Core Bundle too.
    var canImport: Bool {
        canCreate && library.globalActivity == nil
    }

    func newMachine() {
        present(.newMachine)
    }

    func chooseImport() {
        let library = library
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Machine")
        panel.message = String(localized: "Choose an exported machine archive (.tzst or .txz).")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.present { url in
            Task { await library.importArchive(url) }
        }
    }

    // MARK: - Run

    func start(_ machines: [VPhoneLaunchpadMachine], headless: Bool = false) {
        let library = library
        Task {
            for machine in machines {
                await library.start(machine.path, headless: headless)
            }
        }
    }

    func stop(_ machines: [VPhoneLaunchpadMachine]) {
        let library = library
        Task {
            await withTaskGroup(of: Void.self) { group in
                for machine in machines {
                    group.addTask { await library.stop(machine.path) }
                }
            }
        }
    }

    func openTerminal(_ machine: VPhoneLaunchpadMachine) {
        let library = library
        // macOS lets an app take the front only when the active one yields
        // it. Every vphone-vm has this identifier; only the one asked opens
        // a window.
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: "com.vphone.bundle")
        Task { await library.openTerminal(machine.path) }
    }

    // MARK: - Menus

    /// The menu for `machines`, as the right-click menu and the ⋯ button
    /// show it.
    func items(for machines: [VPhoneLaunchpadMachine]) -> [DKMenuItem] {
        items(Plan.entries(for: machines.map(fact), placement: .contextMenu), machines: machines, shortcuts: false)
    }

    /// The ⋯ button that opens that menu.
    func moreButton(for machines: [VPhoneLaunchpadMachine]) -> DKMenuButton {
        let items = items(for: machines)
        return DKMenuButton(
            DKButtonSpec(String(localized: "Actions"), glyph: .ellipsis, size: .icon, isEnabled: !items.isEmpty),
            items: items,
        )
    }

    /// The menu bar's Machine menu: the same plan for the selection, with
    /// shortcuts. It acts only while the Machines page shows the selection
    /// and no sheet of the window is open: a shortcut typed into a sheet's
    /// field is not meant for the machines behind it.
    func menuBarItems() -> [DKMenuItem] {
        let acts = model.destination == .machines && library.sheet == nil && model.panel == nil
        let machines = acts ? library.selectedMachines : []
        return items(Plan.entries(for: machines.map(fact), placement: .menuBar), machines: machines, shortcuts: true)
    }

    /// The plan's facts about one machine, read from the library.
    func fact(_ machine: VPhoneLaunchpadMachine) -> Plan.Machine {
        let path = machine.path
        let isCreating = library.creations[path]?.isRunning == true
        let run: Plan.Run = switch library.state(of: path) {
        case .stopped: .stopped
        case .running: .running
        case .busy: .busy
        }
        return Plan.Machine(
            run: run,
            isCreating: isCreating,
            isExporting: library.exports[path] != nil,
            isRestored: machine.restoreInfo != nil,
            customFirmwareInstalled: machine.customFirmwareInstalled,
            hasPatchLog: FileManager.default.fileExists(atPath: Self.patchLog(path).path),
            canChangeBundle: !model.bundles.selectableVersions.isEmpty && !isCreating,
        )
    }

    /// Rebinding applies at the next start, so running machines may change
    /// too. A machine still being created gets its bundle from the pipeline.
    func canChangeBundle(_ machines: [VPhoneLaunchpadMachine]) -> Bool {
        !machines.isEmpty && machines.allSatisfy { fact($0).canChangeBundle }
    }

    private func items(_ entries: [Plan.Entry], machines: [VPhoneLaunchpadMachine], shortcuts: Bool) -> [DKMenuItem] {
        entries.map { entry in
            switch entry {
            case .separator:
                return .separator
            case let .submenu(action, isEnabled, children):
                return .submenu(
                    title(action, count: machines.count),
                    isEnabled: isEnabled,
                    items: items(children, machines: machines, shortcuts: shortcuts),
                )
            case let .item(action, isEnabled):
                return DKMenuItem(
                    title(action, count: machines.count),
                    shortcut: shortcuts ? Self.shortcut(action) : nil,
                    isEnabled: isEnabled,
                    isDestructive: action == .delete,
                ) {
                    // The sheets the inspector opens are its own state.
                    if shortcuts, NSApp.keyWindow?.sheetParent != nil {
                        return
                    }
                    perform(action, on: machines)
                }
            }
        }
    }

    private func title(_ action: Plan.Action, count: Int) -> String {
        switch action {
        case .cancelExport: String(localized: "Cancel Export")
        case .showProgress: String(localized: "Show Progress")
        case .start: String(localized: "Start")
        case .startHeadless: String(localized: "Start Headless")
        case .stop: String(localized: "Stop")
        case .openConsole: String(localized: "Open Console")
        case .showInFinder: String(localized: "Show in Finder")
        case .logs: String(localized: "Logs")
        case .consoleLog: String(localized: "Console Log")
        case .patchLog: String(localized: "Patch Log")
        case .settings: String(localized: "Settings…")
        case .rename: String(localized: "Rename…")
        case .clone: String(localized: "Clone…")
        case .export: String(localized: "Export…")
        case .snapshots: String(localized: "Snapshots…")
        case .coreBundle: String(localized: "Core Bundle")
        case .changeBundle: String(localized: "Change Core Bundle…")
        case .updateGuestEnvironment: String(localized: "Update Guest Environment")
        case .installCustomFirmware: String(localized: "Install Custom Firmware")
        case .delete: count > 1 ? String(localized: "Delete \(count) Machines…") : String(localized: "Delete…")
        }
    }

    /// The Machine menu's shortcuts, as the design gives them. The
    /// right-click menu and the ⋯ button show none.
    static func shortcut(_ action: Plan.Action) -> DKShortcut? {
        switch action {
        case .start: "⌘R"
        case .startHeadless: "⌥⌘R"
        case .stop: "⌘."
        case .openConsole: "⇧⌘C"
        case .settings: "⌘I"
        case .clone: "⌘D"
        case .export: "⇧⌘E"
        case .delete: "⌘⌫"
        default: nil
        }
    }

    private func perform(_ action: Plan.Action, on machines: [VPhoneLaunchpadMachine]) {
        guard let path = machines.first?.path else {
            return
        }
        let library = library
        let paths = machines.map(\.path)
        switch action {
        case .cancelExport:
            for path in paths where library.exports[path] != nil {
                library.cancelExport(path)
            }
        case .showProgress:
            present(.creation(path))
        case .start:
            start(machines.filter { library.state(of: $0.path) == .stopped })
        case .startHeadless:
            start(machines.filter { library.state(of: $0.path) == .stopped }, headless: true)
        case .stop:
            stop(machines.filter { library.state(of: $0.path) == .running })
        case .openConsole:
            present(.console(path))
        case .showInFinder:
            NSWorkspace.shared.activateFileViewerSelecting(paths.map(\.url))
        case .logs, .coreBundle:
            break
        case .consoleLog:
            NSWorkspace.shared.open(VPhoneLaunchpadMachineLibrary.consoleLog(path))
        case .patchLog:
            NSWorkspace.shared.open(Self.patchLog(path))
        case .settings:
            present(.settings(machines))
        case .rename:
            present(.rename(path))
        case .clone:
            present(.clone(path))
        case .export:
            present(.export(paths))
        case .snapshots:
            present(.snapshots(path))
        case .changeBundle:
            present(.changeBundle(machines))
        case .updateGuestEnvironment:
            Task { await library.updateGuestEnvironment(path) }
        case .installCustomFirmware:
            Task { await library.installCustomFirmware(path) }
        case .delete:
            delete(paths)
        }
    }

    private static func patchLog(_ path: MachinePath) -> URL {
        VPhoneLaunchpadMachineLibrary.consoleLog(path, suffix: "-patch")
    }
}

// MARK: - Presentation

extension VPhoneLaunchpadMachine {
    /// True for an iPad guest, from its product type.
    var isPad: Bool {
        guestProductType?.hasPrefix("iPad") == true
    }

    var glyph: DKGlyph {
        isPad ? .ipad : .phone
    }

    /// The guest OS's name: iPadOS on an iPad.
    var osName: String {
        isPad ? "iPadOS" : "iOS"
    }

    /// "iOS 26.6.2 (23G90)", or nil before the first restore.
    var osDescription: String? {
        restoreInfo.map { "\(osName) \($0.ios.version) (\($0.ios.build))" }
    }

    /// The Resources column: "8 CPU · 8 GB · 64 GB".
    var resourcesDescription: String {
        String(localized: "\(cpuCount) CPU · \(VPhoneLaunchpadMachinesView.memory(memoryMB)) · \(VPhoneLaunchpadMachinesView.disk(diskSizeBytes))")
    }
}

/// A machine's state as the table and the inspector chip show it: a tone,
/// its text, and a progress fraction while an export or an IPSW download
/// reports one.
struct VPhoneLaunchpadMachineStatus {
    let tone: DKTone
    let text: String
    let progress: Double?

    init(_ path: VPhoneLaunchpadMachinePath, library: VPhoneLaunchpadMachineLibrary) {
        let progress = library.progress(of: path)
        self.progress = progress
        switch library.state(of: path) {
        case .running:
            tone = .success
            if let started = library.startedAt[path] {
                text = String(localized: "Running since \(started.formatted(date: .omitted, time: .shortened))")
            } else {
                text = String(localized: "Running")
            }
        case .stopped:
            tone = .idle
            text = String(localized: "Stopped")
        case let .busy(activity):
            tone = .warning
            // The bar under the text carries no number of its own.
            text = progress.map { "\(activity) \($0.formatted(.percent.precision(.fractionLength(0))))" } ?? activity
        }
    }

    var cell: DKTableCell {
        .status(tone, text, progress: progress)
    }
}
