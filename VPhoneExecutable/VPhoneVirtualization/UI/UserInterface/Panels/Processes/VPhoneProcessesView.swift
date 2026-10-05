import SwiftUI
import VPhoneDesignKit

struct VPhoneProcessesView: View {
    @Bindable var model: VPhoneProcessesModel
    @FocusState private var searchFocused: Bool
    /// Which columns show. Bundle ID, PPID, Resident, Limit, Started and
    /// Executable start hidden: the detail bar shows them for the selection,
    /// and the table header's menu turns them on as columns.
    @AppStorage("vphone-processes-columns") private var columnData = Data()

    var body: some View {
        VStack(spacing: 0) {
            header
            VPhoneSystemPageBanner(status: model.status)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            detailBar
            VPhoneSystemPageStatusBar(
                isConnected: model.control.isConnected,
                activity: model.activity?.title,
                status: model.status,
                detail: model.hasLoaded ? countText : nil,
            )
        }
        .background(DK.Palette.window)
        .guestToolShortcuts([
            VPhoneGuestToolShortcut(key: "r", isEnabled: !model.isBusy) {
                Task { await model.refresh() }
            },
            // ⌘⌫ stays with the search field while it is being edited.
            VPhoneGuestToolShortcut(key: .delete, isEnabled: model.canSignal && !searchFocused) {
                model.requestSignal(.term)
            },
            VPhoneGuestToolShortcut(key: "f") { searchFocused = true },
        ])
        .task(id: model.autoRefresh) {
            await model.refresh()
            while model.autoRefresh, !Task.isCancelled {
                try? await Task.sleep(for: VPhoneProcessesModel.autoRefreshInterval)
                guard !Task.isCancelled else { return }
                await model.refresh(automatic: true)
            }
        }
        .confirmationDialog(
            model.pendingSignal?.title ?? "",
            isPresented: Binding(
                get: { model.pendingSignal != nil },
                set: {
                    if !$0 {
                        model.pendingSignal = nil
                    }
                },
            ),
            presenting: model.pendingSignal,
        ) { request in
            Button(request.confirmTitle, role: request.signal.isDestructive ? .destructive : nil) {
                Task { await model.send(request) }
            }
            Button("Cancel", role: .cancel) { model.pendingSignal = nil }
        } message: { request in
            Text(request.message)
        }
    }

    // MARK: - Header

    private var header: some View {
        DKPageHeader(VPhoneLocalization.text("Processes"), subtitle: subtitle) {
            VPhoneSystemToggleButton(
                label: VPhoneLocalization.text("Auto Refresh"),
                glyph: .timer,
                isOn: $model.autoRefresh,
                help: VPhoneLocalization.text("Refresh every 3 seconds while this window is open"),
            )
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Terminate"),
                glyph: .xCircle,
                variant: .danger,
                isEnabled: model.canSignal,
                help: VPhoneLocalization.text("Send SIGTERM to the selected processes (⌘⌫)"),
            ) { model.requestSignal(.term) })
            VPhoneSystemMenuButton(
                label: VPhoneLocalization.text("Signal"),
                glyph: .bolt,
                isEnabled: model.canSignal,
                help: VPhoneLocalization.text("Send another signal to the selected processes"),
            ) {
                VPhoneProcessSignal.menuSignals.map { signal in
                    DKMenuItem(signal.menuTitle) { model.requestSignal(signal) }
                }
            }
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Refresh"),
                glyph: .refresh,
                size: .icon,
                isEnabled: !model.isBusy,
                help: VPhoneLocalization.text("Reload the process list (⌘R)"),
            ) { Task { await model.refresh() } })
            VPhoneSystemSearchField(
                placeholder: VPhoneLocalization.text("Search Processes"),
                text: $model.searchText,
                width: 170,
                focus: $searchFocused,
            )
        }
    }

    /// Memory pressure and installed RAM, as `memory.pressure` reports them.
    private var subtitle: String? {
        var parts: [String] = []
        if let summary = model.memory?.summary {
            parts.append(String(localized: "memory pressure: \(summary)", bundle: VPhoneLocalization.bundle))
        }
        if let total = model.memory?.totalBytes {
            parts.append(String(localized: "\(VPhonePanelFormat.bytes(total)) RAM", bundle: VPhoneLocalization.bundle))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var countText: String {
        model.trimmedSearch.isEmpty
            ? String(localized: "\(model.rows.count) processes", bundle: VPhoneLocalization.bundle)
            : String(localized: "\(model.visibleRows.count) of \(model.rows.count) processes", bundle: VPhoneLocalization.bundle)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            if model.isBusy {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.control.isConnected {
                VPhonePanelEmptyState(
                    title: "Guest Not Connected",
                    systemImage: "cpu",
                    message: "Processes appear here once vphoned is running in the guest.",
                )
            } else {
                VPhonePanelEmptyState(
                    title: "No Processes Loaded",
                    systemImage: "cpu",
                    message: "Choose Refresh to list the guest's processes.",
                )
            }
        } else if model.visibleRows.isEmpty {
            if model.trimmedSearch.isEmpty {
                VPhonePanelEmptyState(title: "No Processes", systemImage: "cpu")
            } else {
                VPhonePanelEmptyState(
                    title: "No Matching Processes",
                    systemImage: "magnifyingglass",
                    message: "No process name, bundle ID, path or PID matches the search.",
                )
            }
        } else {
            table
        }
    }

    private var table: some View {
        Table(
            model.visibleRows,
            selection: $model.selection,
            sortOrder: $model.sortOrder,
            columnCustomization: columnCustomization,
        ) {
            identityColumns
            usageColumns
        }
        .systemPageTable()
        .contextMenu(forSelectionType: VPhoneProcessRow.ID.self) { pids in
            if !pids.isEmpty {
                Button("Copy PID") { model.copy({ String($0.pid) }, pids: pids) }
                Button("Copy Name") { model.copy(\.displayName, pids: pids) }
                Button("Copy Executable Path") { model.copy(\.executable, pids: pids) }
                Button("Copy Bundle ID") { model.copy(\.bundleID, pids: pids) }
                Divider()
                Button("Terminate…") { model.requestSignal(.term, pids: pids) }
                    .disabled(model.isBusy)
                Button("Kill…") { model.requestSignal(.kill, pids: pids) }
                    .disabled(model.isBusy)
            }
        }
        .accessibilityLabel("Guest processes")
    }

    private var columnCustomization: Binding<TableColumnCustomization<VPhoneProcessRow>> {
        Binding(
            get: { (try? JSONDecoder().decode(TableColumnCustomization<VPhoneProcessRow>.self, from: columnData)) ?? .init() },
            set: { columnData = (try? JSONEncoder().encode($0)) ?? Data() },
        )
    }

    // MARK: - Columns

    typealias Comparator = KeyPathComparator<VPhoneProcessRow>

    @TableColumnBuilder<VPhoneProcessRow, Comparator>
    private var identityColumns: some TableColumnContent<VPhoneProcessRow, Comparator> {
        TableColumn("PID", value: \VPhoneProcessRow.pid) { row in
            VPhoneSystemCell(.mono(String(row.pid)), alignment: .trailing)
        }
        .width(min: 44, ideal: 52, max: 80)
        .customizationID("pid")

        TableColumn("Name", value: \VPhoneProcessRow.nameSortKey) { row in
            VPhoneSystemCell(
                model.selection.contains(row.id) ? .strong(row.displayName) : .text(row.displayName),
                help: row.displayName,
            )
        }
        .width(min: 120, ideal: 200)
        .customizationID("name")

        TableColumn("Bundle ID", value: \VPhoneProcessRow.bundleSortKey) { row in
            VPhoneSystemCell(row.bundleID.map(DKTableCell.mono) ?? .muted("—"), help: row.bundleID)
        }
        .width(min: 70, ideal: 160)
        .customizationID("bundle")
        .defaultVisibility(.hidden)

        TableColumn("User", value: \VPhoneProcessRow.uidSortKey) { row in
            VPhoneSystemCell(.muted(row.userTitle))
        }
        .width(min: 48, ideal: 70, max: 100)
        .customizationID("user")

        TableColumn("PPID", value: \VPhoneProcessRow.ppidSortKey) { row in
            VPhoneSystemCell(.mono(row.ppidTitle), alignment: .trailing)
        }
        .width(min: 36, ideal: 48, max: 80)
        .customizationID("ppid")
        .defaultVisibility(.hidden)

        TableColumn("Memory", value: \VPhoneProcessRow.footprintSortKey) { row in
            VPhoneSystemCell(.mono(row.footprintTitle), alignment: .trailing)
        }
        .width(min: 60, ideal: 80, max: 120)
        .customizationID("memory")
    }

    @TableColumnBuilder<VPhoneProcessRow, Comparator>
    private var usageColumns: some TableColumnContent<VPhoneProcessRow, Comparator> {
        TableColumn("Resident", value: \VPhoneProcessRow.residentSortKey) { row in
            VPhoneSystemCell(.mono(row.residentTitle), alignment: .trailing)
        }
        .width(min: 52, ideal: 70, max: 120)
        .customizationID("resident")
        .defaultVisibility(.hidden)

        TableColumn("CPU Time", value: \VPhoneProcessRow.cpuSortKey) { row in
            VPhoneSystemCell(.mono(row.cpuTitle), alignment: .trailing)
        }
        .width(min: 60, ideal: 80, max: 120)
        .customizationID("cpu")

        TableColumn("Jetsam Priority", value: \VPhoneProcessRow.jetsamPrioritySortKey) { row in
            VPhoneSystemCell(.mono(row.jetsamPriorityTitle), alignment: .trailing)
        }
        .width(min: 60, ideal: 110, max: 130)
        .customizationID("jetsam-priority")

        TableColumn("Limit", value: \VPhoneProcessRow.jetsamLimitSortKey) { row in
            VPhoneSystemCell(.mono(row.jetsamLimitTitle), alignment: .trailing)
        }
        .width(min: 44, ideal: 70, max: 110)
        .customizationID("limit")
        .defaultVisibility(.hidden)

        TableColumn("Started", value: \VPhoneProcessRow.startSortKey) { row in
            VPhoneSystemCell(.muted(row.startedTitle), help: row.startedHelp)
        }
        .width(min: 44, ideal: 80, max: 140)
        .customizationID("started")
        .defaultVisibility(.hidden)

        TableColumn("Executable", value: \VPhoneProcessRow.executableSortKey) { row in
            VPhoneSystemCell(.mono(row.executableTitle), help: row.executable)
        }
        .width(min: 120, ideal: 200)
        .customizationID("executable")
        .defaultVisibility(.hidden)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailBar: some View {
        let selected = model.hasLoaded ? model.visibleRows.filter { model.selection.contains($0.id) } : []
        if selected.count == 1, let row = selected.first {
            DKDetailBar(
                row.displayName,
                subtitle: "pid \(row.pid)",
                facts: [
                    DKKeyValue(VPhoneLocalization.text("Bundle ID"), row.bundleTitle),
                    DKKeyValue(VPhoneLocalization.text("PPID"), row.ppidTitle),
                    DKKeyValue(VPhoneLocalization.text("Resident"), row.residentTitle),
                    DKKeyValue(VPhoneLocalization.text("Limit"), row.jetsamLimitTitle),
                    DKKeyValue(VPhoneLocalization.text("Started"), row.startedHelp),
                    DKKeyValue(VPhoneLocalization.text("Executable"), row.executableTitle),
                ],
            )
        } else if selected.count > 1 {
            DKDetailBar(
                String(localized: "\(selected.count) processes selected", bundle: VPhoneLocalization.bundle),
                note: selected.prefix(6).map(\.reference).joined(separator: ", ") + (selected.count > 6 ? "…" : ""),
            )
        }
    }
}
