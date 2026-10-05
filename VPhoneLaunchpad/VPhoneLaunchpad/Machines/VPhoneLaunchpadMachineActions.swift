import AppKit
import SwiftUI
import VPhoneDesignKit

// MARK: - Actions

/// Every action on machines, in one order: run, inspect, configure,
/// maintain, delete. The table's context menu, the inspector's more button
/// and the multiple-selection inspector share it, so an item and its
/// enablement are written once.
struct VPhoneLaunchpadMachineActions {
    typealias MachinePath = VPhoneLaunchpadMachinePath

    let model: VPhoneLaunchpadModel
    /// Opens one of the Machines page's sheets.
    let present: (VPhoneLaunchpadMachinesView.Sheet) -> Void
    /// Asks to delete the machines; the page confirms first.
    let delete: ([MachinePath]) -> Void

    private var library: VPhoneLaunchpadMachineLibrary {
        model.machines
    }

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

    /// The menu for `machines`. Several machines get the batch actions only:
    /// start and stop, one settings edit, export, Core Bundle change and
    /// delete, which need every machine stopped.
    func items(for machines: [VPhoneLaunchpadMachine]) -> [DKMenuItem] {
        if machines.count > 1 {
            batchItems(machines)
        } else if let machine = machines.first {
            singleItems(machine)
        } else {
            []
        }
    }

    // MARK: - One machine

    private func singleItems(_ machine: VPhoneLaunchpadMachine) -> [DKMenuItem] {
        let library = library
        let path = machine.path
        let state = library.state(of: path)
        let isStopped = state == .stopped
        let isCreating = library.creations[path]?.isRunning == true
        let isExporting = library.exports[path] != nil
        let patchLog = VPhoneLaunchpadMachineLibrary.consoleLog(path, suffix: "-patch")
        var items: [DKMenuItem] = []

        // Run. A machine being exported or created offers to stop that
        // instead; a running one offers Stop.
        if isExporting {
            items.append(DKMenuItem("Cancel Export") { library.cancelExport(path) })
        }
        if isCreating {
            items.append(DKMenuItem("Show Progress") { present(.creation(path)) })
        }
        if state == .running {
            items.append(DKMenuItem("Stop") { stop([machine]) })
        } else if !isCreating, !isExporting {
            items.append(DKMenuItem("Start", isEnabled: isStopped) { start([machine]) })
            items.append(DKMenuItem("Start Headless", isEnabled: isStopped) { start([machine], headless: true) })
        }

        // Inspect.
        items.append(.separator)
        items.append(DKMenuItem("Open Console") { present(.console(path)) })
        items.append(DKMenuItem("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([path.url])
        })
        items.append(.submenu("Logs", items: [
            DKMenuItem("Console Log") {
                NSWorkspace.shared.open(VPhoneLaunchpadMachineLibrary.consoleLog(path))
            },
            DKMenuItem("Patch Log", isEnabled: FileManager.default.fileExists(atPath: patchLog.path)) {
                NSWorkspace.shared.open(patchLog)
            },
        ]))

        // Configure.
        items.append(.separator)
        items.append(DKMenuItem("Settings…", isEnabled: isStopped) { present(.settings([machine])) })
        items.append(DKMenuItem("Rename…", isEnabled: isStopped) { present(.rename(path)) })
        items.append(DKMenuItem("Clone…", isEnabled: isStopped) { present(.clone(path)) })
        items.append(DKMenuItem("Export…", isEnabled: isStopped) { present(.export([path])) })

        // Maintain.
        items.append(.separator)
        items.append(.submenu("Core Bundle", items: [
            changeBundleItem([machine]),
            // The finished-install counterpart of the item below: redeploys
            // the machine's own bundle's guest resources without the restore
            // tree.
            DKMenuItem(
                "Update Guest Environment",
                isEnabled: isStopped && machine.restoreInfo != nil && machine.customFirmwareInstalled != false,
            ) {
                Task { await library.updateGuestEnvironment(path) }
            },
            // Only for an unfinished install: that is when the restore tree
            // it reads is still there. A finished one removes it.
            DKMenuItem("Install Custom Firmware", isEnabled: isStopped && machine.customFirmwareInstalled == false) {
                Task { await library.installCustomFirmware(path) }
            },
        ]))

        // Delete.
        items.append(.separator)
        items.append(DKMenuItem("Delete…", isEnabled: isStopped, isDestructive: true) { delete([path]) })
        return items
    }

    // MARK: - Several machines

    private func batchItems(_ machines: [VPhoneLaunchpadMachine]) -> [DKMenuItem] {
        let library = library
        let stopped = machines.filter { library.state(of: $0.path) == .stopped }
        let running = machines.filter { library.state(of: $0.path) == .running }
        let allStopped = stopped.count == machines.count
        // Only while one of them is exporting or waiting to.
        let exporting = machines.filter { library.exports[$0.path] != nil }
        var items: [DKMenuItem] = []

        if !exporting.isEmpty {
            items.append(DKMenuItem("Cancel Export") {
                for machine in exporting {
                    library.cancelExport(machine.path)
                }
            })
            items.append(.separator)
        }
        items.append(DKMenuItem("Start", isEnabled: !stopped.isEmpty) { start(stopped) })
        items.append(DKMenuItem("Start Headless", isEnabled: !stopped.isEmpty) { start(stopped, headless: true) })
        items.append(DKMenuItem("Stop", isEnabled: !running.isEmpty) { stop(running) })

        items.append(.separator)
        items.append(DKMenuItem("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(machines.map(\.path.url))
        })

        items.append(.separator)
        items.append(DKMenuItem("Settings…", isEnabled: allStopped) { present(.settings(machines)) })
        items.append(DKMenuItem("Export…", isEnabled: allStopped) { present(.export(machines.map(\.path))) })

        items.append(.separator)
        items.append(changeBundleItem(machines))

        items.append(.separator)
        items.append(DKMenuItem(
            String(localized: "Delete \(machines.count) Machines…"),
            isEnabled: allStopped,
            isDestructive: true,
        ) {
            delete(machines.map(\.path))
        })
        return items
    }

    /// Rebinding applies at the next start, so running machines may change
    /// too. A machine still being created gets its bundle from the pipeline.
    func canChangeBundle(_ machines: [VPhoneLaunchpadMachine]) -> Bool {
        !model.bundles.selectableVersions.isEmpty
            && !machines.contains { library.creations[$0.path]?.isRunning == true }
    }

    private func changeBundleItem(_ machines: [VPhoneLaunchpadMachine]) -> DKMenuItem {
        DKMenuItem("Change Core Bundle…", isEnabled: canChangeBundle(machines)) {
            present(.changeBundle(machines))
        }
    }
}

// MARK: - More button

/// The ⋯ button that opens the machine menu, drawn as a DesignKit icon button.
struct VPhoneLaunchpadMachineMoreButton: View {
    let items: [DKMenuItem]

    var body: some View {
        Menu {
            DKMenuContent(items)
        } label: {
            DKIcon(.ellipsis, size: 15)
        }
        .menuStyle(.button)
        .buttonStyle(DKButtonStyle(variant: .secondary, size: .icon))
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(items.isEmpty)
        .help("Actions")
        .accessibilityLabel(Text("Actions"))
    }
}

// MARK: - Presentation

extension VPhoneLaunchpadMachine {
    /// True for an iPad guest, from the device the machine was restored as.
    var isPad: Bool {
        restoreInfo?.device?.hasPrefix("iPad") == true
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

// MARK: - Table cell

/// A DesignKit cell inside a system `Table` row. The kit's cells draw in
/// fixed colors, which are unreadable on the accent fill of a selected row;
/// with the row's increased prominence the cell draws in the dark
/// appearance, whose ink is light.
struct VPhoneLaunchpadTableCell: View {
    let cell: DKTableCell
    /// Room above and below, for the two-line rows of the machine list.
    var verticalPadding: CGFloat = 3
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.colorScheme) private var colorScheme

    init(_ cell: DKTableCell, verticalPadding: CGFloat = 3) {
        self.cell = cell
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        DKTableCellView(cell)
            .environment(\.colorScheme, prominence == .increased ? .dark : colorScheme)
            .padding(.vertical, verticalPadding)
    }
}
