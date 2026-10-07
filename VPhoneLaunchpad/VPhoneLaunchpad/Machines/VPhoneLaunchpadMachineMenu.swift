import Foundation

// MARK: - Machine menu plan

/// Which actions a machine menu lists, in what order and which of them are
/// enabled, worked out from plain facts about the machines. The right-click
/// menu, the inspector's ⋯ button and the menu bar's Machine menu all draw
/// this plan; `VPhoneLaunchpadMachineActions` gives each entry its title,
/// shortcut and action. Kept free of SwiftUI and the library so the
/// standalone tests can run it.
///
/// The order is run, inspect, configure, maintain, delete.
nonisolated enum VPhoneLaunchpadMachineMenu {
    enum Action: Hashable, Sendable {
        case cancelExport
        case showProgress
        case start
        case startHeadless
        case stop
        case openConsole
        case showInFinder
        case logs
        case consoleLog
        case patchLog
        case settings
        case rename
        case clone
        case export
        case snapshots
        case coreBundle
        case changeBundle
        case updateGuestEnvironment
        case installCustomFirmware
        case delete
    }

    enum Entry: Hashable, Sendable {
        case item(Action, isEnabled: Bool)
        case separator
        case submenu(Action, isEnabled: Bool, children: [Entry])

        var action: Action? {
            switch self {
            case let .item(action, _), let .submenu(action, _, _): action
            case .separator: nil
            }
        }

        var isEnabled: Bool {
            switch self {
            case let .item(_, isEnabled), let .submenu(_, isEnabled, _): isEnabled
            case .separator: false
            }
        }

        var children: [Entry] {
            if case let .submenu(_, _, children) = self {
                return children
            }
            return []
        }
    }

    /// Where the menu is shown. The menu bar keeps Start, Start Headless and
    /// Stop in place and dims the ones that do not apply, as a menu-bar menu
    /// should; a context menu lists only the run actions that apply.
    enum Placement: Sendable {
        case contextMenu
        case menuBar
    }

    enum Run: Hashable, Sendable {
        case stopped
        case running
        /// Starting, stopping, installing or waiting to export.
        case busy
    }

    /// What the plan needs to know about one machine.
    struct Machine: Hashable, Sendable {
        var run: Run
        var isCreating = false
        var isExporting = false
        /// Restored at least once, so the guest environment has a target.
        var isRestored = true
        /// Whether `cfw install` finished; nil when not recorded.
        var customFirmwareInstalled: Bool? = true
        var hasPatchLog = false
        /// Whether its Core Bundle may be changed: some version is installed
        /// to change to, and the machine is not being created.
        var canChangeBundle = true
    }

    static func entries(for machines: [Machine], placement: Placement = .contextMenu) -> [Entry] {
        if machines.count > 1 {
            batch(machines)
        } else if let machine = machines.first {
            single(machine, placement: placement)
        } else if placement == .menuBar {
            // Nothing selected: the menu keeps its shape, all dimmed.
            disabled(single(Machine(run: .stopped), placement: .menuBar))
        } else {
            []
        }
    }

    // MARK: - One machine

    private static func single(_ machine: Machine, placement: Placement) -> [Entry] {
        let isStopped = machine.run == .stopped
        var entries: [Entry] = []

        // Run. A machine being exported or created offers to stop that
        // instead; a running one offers Stop.
        if machine.isExporting {
            entries.append(.item(.cancelExport, isEnabled: true))
        }
        if machine.isCreating {
            entries.append(.item(.showProgress, isEnabled: true))
        }
        switch placement {
        case .menuBar:
            entries.append(.item(.start, isEnabled: isStopped))
            entries.append(.item(.startHeadless, isEnabled: isStopped))
            entries.append(.item(.stop, isEnabled: machine.run == .running))
        case .contextMenu:
            if machine.run == .running {
                entries.append(.item(.stop, isEnabled: true))
            } else if !machine.isCreating, !machine.isExporting {
                entries.append(.item(.start, isEnabled: isStopped))
                entries.append(.item(.startHeadless, isEnabled: isStopped))
            }
        }

        // Inspect.
        entries.append(.separator)
        entries.append(.item(.openConsole, isEnabled: true))
        entries.append(.item(.showInFinder, isEnabled: true))
        entries.append(.submenu(.logs, isEnabled: true, children: [
            .item(.consoleLog, isEnabled: true),
            .item(.patchLog, isEnabled: machine.hasPatchLog),
        ]))

        // Configure.
        entries.append(.separator)
        entries.append(.item(.settings, isEnabled: isStopped))
        entries.append(.item(.rename, isEnabled: isStopped))
        entries.append(.item(.clone, isEnabled: isStopped))
        entries.append(.item(.export, isEnabled: isStopped))
        // Open while the machine runs too, to read the list; taking,
        // reverting and deleting wait for it to stop.
        entries.append(.item(.snapshots, isEnabled: !machine.isCreating))

        // Maintain. Update Guest Environment redeploys a finished install's
        // guest resources; Install Custom Firmware finishes an unfinished one,
        // while the restore tree it reads is still there.
        let bundle: [Entry] = [
            .item(.changeBundle, isEnabled: machine.canChangeBundle),
            .item(
                .updateGuestEnvironment,
                isEnabled: isStopped && machine.isRestored && machine.customFirmwareInstalled != false,
            ),
            .item(.installCustomFirmware, isEnabled: isStopped && machine.customFirmwareInstalled == false),
        ]
        entries.append(.separator)
        entries.append(.submenu(.coreBundle, isEnabled: bundle.contains(where: \.isEnabled), children: bundle))

        // Delete.
        entries.append(.separator)
        entries.append(.item(.delete, isEnabled: isStopped))
        return entries
    }

    // MARK: - Several machines

    /// Batch actions only: start and stop, one settings edit, export, a
    /// Core Bundle change and delete, which need every machine stopped.
    private static func batch(_ machines: [Machine]) -> [Entry] {
        let stopped = machines.count { $0.run == .stopped }
        let running = machines.count { $0.run == .running }
        let allStopped = stopped == machines.count
        var entries: [Entry] = []
        if machines.contains(where: \.isExporting) {
            entries.append(.item(.cancelExport, isEnabled: true))
            entries.append(.separator)
        }
        entries.append(.item(.start, isEnabled: stopped > 0))
        entries.append(.item(.startHeadless, isEnabled: stopped > 0))
        entries.append(.item(.stop, isEnabled: running > 0))
        entries.append(.separator)
        entries.append(.item(.showInFinder, isEnabled: true))
        entries.append(.separator)
        entries.append(.item(.settings, isEnabled: allStopped))
        entries.append(.item(.export, isEnabled: allStopped))
        entries.append(.separator)
        entries.append(.item(.changeBundle, isEnabled: machines.allSatisfy(\.canChangeBundle)))
        entries.append(.separator)
        entries.append(.item(.delete, isEnabled: allStopped))
        return entries
    }

    private static func disabled(_ entries: [Entry]) -> [Entry] {
        entries.map { entry in
            switch entry {
            case let .item(action, _): .item(action, isEnabled: false)
            case let .submenu(action, _, children): .submenu(action, isEnabled: false, children: disabled(children))
            case .separator: .separator
            }
        }
    }
}
