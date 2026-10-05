import AppKit
import SwiftUI
import VPhoneDesignKit

struct VPhoneLaunchpadMachinesView: View {
    typealias MachinePath = VPhoneLaunchpadMachinePath

    enum Sheet: Identifiable {
        case newMachine
        case creation(MachinePath)
        case settings([VPhoneLaunchpadMachine])
        case changeBundle([VPhoneLaunchpadMachine])
        case rename(MachinePath)
        case clone(MachinePath)
        case export([MachinePath])
        case snapshots(MachinePath)
        case console(MachinePath)

        var id: String {
            switch self {
            case .newMachine: "new"
            case let .creation(machine): "creation-\(machine.url.path)"
            case let .settings(machines): "settings-\(machines.map(\.path.url.path).joined(separator: "|"))"
            case let .changeBundle(machines): "bundle-\(machines.map(\.path.url.path).joined(separator: "|"))"
            case let .rename(machine): "rename-\(machine.url.path)"
            case let .clone(machine): "clone-\(machine.url.path)"
            case let .export(machines): "export-\(machines.map(\.url.path).joined(separator: "|"))"
            case let .snapshots(machine): "snapshots-\(machine.url.path)"
            case let .console(machine): "console-\(machine.url.path)"
            }
        }
    }

    /// The header's filter. Machines that are busy (being created, exported
    /// or shut down) show only under All.
    enum Scope: Hashable {
        case all, running, stopped
    }

    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var sheet: Sheet?
    /// The machines the delete confirmation is for; empty when it is closed.
    @State private var deletion: [MachinePath] = []
    @State private var filter = ""
    @State private var scope = Scope.all
    /// Empty keeps the order `vm list` returns; a header click replaces it.
    @State private var sortOrder: [KeyPathComparator<VPhoneLaunchpadMachine>] = []
    /// The table appears only once `vm list` returns, after the window has
    /// picked its first responder, so nothing focuses it by itself. Unfocused,
    /// AppKit draws the library's automatic selection in gray, not in the
    /// accent color.
    @FocusState private var tableIsFocused: Bool

    private var library: VPhoneLaunchpadMachineLibrary {
        model.machines
    }

    private var actions: VPhoneLaunchpadMachineActions {
        VPhoneLaunchpadMachineActions(
            model: model,
            present: { sheet = $0 },
            delete: { deletion = $0 },
        )
    }

    /// The machines the table shows: those in the scope that match the
    /// search, in the header's order.
    private var rows: [VPhoneLaunchpadMachine] {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        let matching = library.machines.filter { machine in
            inScope(machine) && (needle.isEmpty || Self.matches(machine, needle))
        }
        return matching.sorted(using: sortOrder)
    }

    private func inScope(_ machine: VPhoneLaunchpadMachine) -> Bool {
        switch scope {
        case .all: true
        case .running: library.state(of: machine.path) == .running
        case .stopped: library.state(of: machine.path) == .stopped
        }
    }

    var body: some View {
        @Bindable var library = library
        @Bindable var model = model
        VStack(spacing: 0) {
            header
            Group {
                if library.machines.isEmpty {
                    emptyState
                } else if rows.isEmpty {
                    if filter.trimmingCharacters(in: .whitespaces).isEmpty {
                        ContentUnavailableView("No Machines in This View", systemImage: "iphone")
                    } else {
                        ContentUnavailableView.search(text: filter)
                    }
                } else {
                    table(selection: $library.selection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DK.Palette.window)
        // A hidden machine stays out of the selection, so Start, Delete and
        // the inspector act only on rows the table shows.
        .onChange(of: filter) { dropHiddenSelection() }
        .onChange(of: scope) { dropHiddenSelection() }
        .inspector(isPresented: $model.showsInspector) {
            inspector
                .inspectorColumnWidth(min: 300, ideal: 380, max: 520)
                // The toggle belongs to the inspector's own toolbar section.
                // Put in the content's toolbar, the section and its background
                // were set up at launch but not again after the inspector was
                // hidden and shown.
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        inspectorToggle
                    }
                }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: VPhoneLaunchpadPreview.sheetNotification)) { note in
            sheet = note.object as? Sheet
        }
        #endif
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .environment(model)
        }
        .confirmationDialog(
            deletion.count == 1 ? "Delete \(deletion[0].name)?" : "Delete \(deletion.count) Machines?",
            isPresented: Binding(get: { !deletion.isEmpty }, set: {
                if !$0 {
                    deletion = []
                }
            }),
        ) {
            Button("Delete", role: .destructive) {
                let machines = deletion
                Task {
                    for machine in machines {
                        await library.delete(machine)
                    }
                }
            }
        } message: {
            if deletion.count == 1 {
                Text("The machine's disk, firmware and settings are removed. This cannot be undone.")
            } else {
                Text("Their disks, firmware and settings are removed. This cannot be undone.")
            }
        }
        .alert(
            library.actionError?.message ?? "",
            isPresented: Binding(get: { library.actionError != nil }, set: {
                if !$0 {
                    library.actionError = nil
                }
            }),
            presenting: library.actionError,
        ) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.detail ?? "")
        }
    }

    private func dropHiddenSelection() {
        let visible = Set(rows.map(\.path))
        library.selection.formIntersection(visible)
    }

    // MARK: - Header

    /// The page's title, counts and tools: the state filter, New Machine,
    /// Import and the search field. What acts on the selection is in the
    /// inspector and the context menu.
    private var header: some View {
        let all = library.machines
        let running = all.count { library.state(of: $0.path) == .running }
        let stopped = all.count { library.state(of: $0.path) == .stopped }
        let shown = String(AttributedString(localized: "^[\(rows.count) machine](inflect: true)").characters)
        let hasBundle = model.bundles.defaultVersion != nil
        return DKPageHeader(
            String(localized: "Machines"),
            subtitle: String(localized: "\(shown) · \(running) running"),
        ) {
            DKSegmented(String(localized: "Show"), selection: $scope, options: [
                DKSegmentOption(String(localized: "All"), value: .all, count: all.count),
                DKSegmentOption(String(localized: "Running"), value: .running, count: running),
                DKSegmentOption(String(localized: "Stopped"), value: .stopped, count: stopped),
            ])
            DKButton(DKButtonSpec(
                String(localized: "New Machine"),
                glyph: .plus,
                variant: .primary,
                isEnabled: hasBundle,
                help: String(localized: "Create a machine"),
            ) { sheet = .newMachine })
            DKButton(DKButtonSpec(
                String(localized: "Import…"),
                glyph: .download,
                isEnabled: hasBundle && library.globalActivity == nil,
            ) { chooseImport() })
            DKSearchField(String(localized: "Search machines"), text: $filter, width: 180)
        }
    }

    private var inspectorToggle: some View {
        Button {
            model.showsInspector.toggle()
        } label: {
            Label("Inspector", systemImage: "sidebar.trailing")
        }
        .help(model.showsInspector ? "Hide the inspector" : "Show the inspector")
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if let machine = library.selected {
            VPhoneLaunchpadMachineInspector(
                machine: machine,
                onShowProgress: { path in sheet = .creation(path) },
                onOpenConsole: { path in sheet = .console(path) },
                onPresent: { sheet = $0 },
                onDelete: { deletion = $0 },
            )
        } else if library.selection.count > 1 {
            selectionSummary(library.selectedMachines)
        } else {
            ContentUnavailableView("No Selection", systemImage: "iphone")
        }
    }

    /// Several machines: Start for the stopped ones, or Stop when none is
    /// stopped and some are running, beside the batch menu.
    private func selectionSummary(_ machines: [VPhoneLaunchpadMachine]) -> some View {
        let stopped = machines.filter { library.state(of: $0.path) == .stopped }
        let running = machines.filter { library.state(of: $0.path) == .running }
        let actions = actions
        return ContentUnavailableView {
            Label("\(machines.count) Machines Selected", systemImage: "iphone")
        } actions: {
            HStack(spacing: DK.Space.s2) {
                if stopped.isEmpty, !running.isEmpty {
                    DKButton(DKButtonSpec(
                        String(localized: "Stop"),
                        glyph: .stop,
                        help: String(localized: "Stop \(running.map(\.name).joined(separator: ", "))"),
                    ) { actions.stop(running) })
                } else {
                    DKButton(DKButtonSpec(
                        String(localized: "Start"),
                        glyph: .play,
                        variant: .primary,
                        isEnabled: !stopped.isEmpty,
                        help: String(localized: "Start the selected machine"),
                    ) { actions.start(stopped) })
                }
                VPhoneLaunchpadMachineMoreButton(items: actions.items(for: machines))
            }
        }
    }

    // MARK: - Table

    private func table(selection: Binding<Set<MachinePath>>) -> some View {
        Table(rows, selection: selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { machine in
                VPhoneLaunchpadTableCell(.title(
                    machine.name,
                    subtitle: machine.restoreInfo?.device,
                    leading: .glyph(machine.glyph),
                ))
            }
            .width(min: 130, ideal: 170)
            if library.spansLibraries {
                TableColumn("Location", value: \.libraryRoot) { machine in
                    VPhoneLaunchpadTableCell(.muted(VPhoneLaunchpadMachineLocations.volumeName(machine.libraryRoot)))
                        .help(VPhoneLaunchpadHostSetup.abbreviated(URL(fileURLWithPath: machine.libraryRoot, isDirectory: true)))
                }
                .width(min: 80, ideal: 110)
            }
            TableColumn("State") { machine in
                VPhoneLaunchpadTableCell(VPhoneLaunchpadMachineStatus(machine.path, library: library).cell)
            }
            .width(min: 140, ideal: 170)
            // Standard comparison orders 18.10 after 18.9.
            TableColumn("Firmware", value: \.iosVersion) { machine in
                VPhoneLaunchpadTableCell(firmwareCell(machine))
            }
            .width(min: 100, ideal: 130)
            TableColumn("Core Bundle") { machine in
                VPhoneLaunchpadTableCell(bundleCell(machine.path))
            }
            .width(min: 64, ideal: 84)
            TableColumn("Resources", value: \.cpuCount) { machine in
                VPhoneLaunchpadTableCell(.muted(machine.resourcesDescription))
            }
            .width(min: 120, ideal: 150)
        }
        .contextMenu(forSelectionType: MachinePath.self) { paths in
            DKMenuContent(actions.items(for: library.machines.filter { paths.contains($0.path) }))
        } primaryAction: { paths in
            actions.start(library.machines.filter { paths.contains($0.path) && library.state(of: $0.path) == .stopped })
        }
        .focused($tableIsFocused)
        .onAppear {
            // The table comes back when a search matches again; the search
            // field keeps the keyboard then. With no search typed, the field
            // in the header, which the window may have focused first, gives
            // it up.
            if filter.isEmpty || !(NSApp.keyWindow?.firstResponder is NSText) {
                tableIsFocused = true
            }
        }
    }

    /// The iOS version over its build, with a warning while the custom
    /// firmware install is unfinished: such a machine cannot boot.
    private func firmwareCell(_ machine: VPhoneLaunchpadMachine) -> DKTableCell {
        guard let info = machine.restoreInfo else {
            return .muted("—")
        }
        let cell = DKTableCell.title(
            "\(machine.osName) \(info.ios.version)",
            subtitle: info.ios.build,
            subtitleMonospaced: true,
            strong: false,
        )
        return cell.warning(machine.customFirmwareInstalled == false ? machine.firmwareName : nil)
    }

    /// The version a machine runs with, with a warning when that version is
    /// gone or the guest environment came from another. Worked out here, not
    /// in the cell: a row leaving the table updates its cell once more with
    /// an empty environment, where reading the model is a fatal error.
    private func bundleCell(_ machine: MachinePath) -> DKTableCell {
        let version = library.bundleVersion(for: machine)
        let warning: String? = if let version, !model.bundles.selectableVersions.contains(version) {
            String(localized: "VPhone.bundle \(version) is not installed. Choose Change Core Bundle… to run this machine with another version.")
        } else if let binding = library.bindings[machine], binding.hasMixedVersions, let guest = binding.guestEnvironment {
            String(localized: "The guest environment is from \(guest).") + " " + VPhoneLaunchpadMachineInspector.mixedHelp
        } else {
            nil
        }
        return DKTableCell.mono(version ?? "—").warning(warning)
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.bundles.defaultVersion == nil {
            ContentUnavailableView {
                Label("No Core Bundle", systemImage: "shippingbox")
            } description: {
                Text("Install a VPhone.bundle to create and run machines.")
            } actions: {
                Button("Set Up…") { model.present(model.host.requiredPassed ? .coreBundle : .hostSetup) }
                    .buttonStyle(.borderedProminent)
            }
        } else if !library.hasListed {
            Color.clear
        } else {
            ContentUnavailableView {
                Label("No Machines", systemImage: "iphone")
            } description: {
                Text(library.listError ?? String(localized: "Machines in \(VPhoneLaunchpadHostSetup.abbreviated(URL(fileURLWithPath: library.libraryRoot, isDirectory: true))) appear here."))
            } actions: {
                Button("New Machine…") { sheet = .newMachine }
                    .buttonStyle(.borderedProminent)
                Button("Import…") { chooseImport() }
            }
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .newMachine:
            VPhoneLaunchpadNewMachineView { path in
                self.sheet = .creation(path)
            }
        case let .creation(path):
            if let creation = library.creations[path] {
                VPhoneLaunchpadCreationView(creation: creation)
            }
        case let .settings(machines):
            VPhoneLaunchpadMachineSettingsView(machines: machines)
        case let .changeBundle(machines):
            VPhoneLaunchpadChangeBundleView(machines: machines)
        case let .rename(path):
            VPhoneLaunchpadNameSheet(title: "Rename \(path.name)", action: "Rename", initial: path.name, machine: path) { newName in
                Task { await library.rename(path, to: newName) }
            }
        case let .clone(path):
            VPhoneLaunchpadCloneSheet(machine: path) { newName, newIdentity in
                Task { await library.clone(path, as: newName, newIdentity: newIdentity) }
            }
        case let .export(paths):
            VPhoneLaunchpadExportView(machines: paths)
        case let .snapshots(path):
            VPhoneLaunchpadSnapshotsView(machine: path)
        case let .console(path):
            VPhoneLaunchpadConsoleView(title: "\(path.name) Console", url: VPhoneLaunchpadMachineLibrary.consoleLog(path))
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Machine")
        panel.message = String(localized: "Choose an exported machine archive (.tzst or .txz).")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.present { url in
            Task { await library.importArchive(url) }
        }
    }

    // MARK: - Search

    private static func matches(_ machine: VPhoneLaunchpadMachine, _ needle: String) -> Bool {
        [
            machine.name,
            machine.restoreInfo?.ios.version,
            machine.restoreInfo?.ios.build,
            machine.restoreInfo?.device,
            machine.udid,
            VPhoneLaunchpadMachineLocations.volumeName(machine.libraryRoot),
        ]
        .compactMap(\.self)
        .contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    // MARK: - Formatting

    static func memory(_ megabytes: Int) -> String {
        megabytes % 1024 == 0 ? "\(megabytes / 1024) GB" : "\(megabytes) MB"
    }

    static func disk(_ bytes: Int64) -> String {
        // Decimal, as iOS and the creation stepper count it.
        "\(bytes / 1_000_000_000) GB"
    }
}
