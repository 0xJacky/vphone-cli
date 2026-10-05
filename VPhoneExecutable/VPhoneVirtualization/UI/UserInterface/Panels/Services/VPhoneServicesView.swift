import SwiftUI
import VPhoneDesignKit

struct VPhoneServicesView: View {
    @Bindable var model: VPhoneServicesModel
    @FocusState private var searchFocused: Bool
    /// Which columns show. Domains starts hidden; the detail bar shows it.
    @AppStorage("vphone-services-columns") private var columnData = Data()

    var body: some View {
        VStack(spacing: 0) {
            header
            VPhoneSystemPageBanner(status: model.status)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VPhoneSystemPageStatusBar(
                isConnected: model.isConnected,
                activity: model.activity,
                status: model.status,
                detail: model.hasLoaded ? countText : nil,
            )
        }
        .background(DK.Palette.window)
        .guestToolShortcuts(shortcuts)
        .confirmationDialog(
            model.pendingAction.map { $0.action.confirmationTitle($0.label) } ?? "",
            isPresented: isConfirming,
            titleVisibility: .visible,
            presenting: model.pendingAction,
        ) { pending in
            Button(pending.action.confirmationButton, role: .destructive) {
                Task { await model.perform(pending.action, on: pending.label) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.action.confirmationMessage)
        }
        .task { await model.monitorConnection() }
        .task(id: model.selection) { await model.loadDetail() }
    }

    // MARK: - Header

    private var header: some View {
        let row = model.selectedRow
        return DKPageHeader(VPhoneLocalization.text("Services"), subtitle: model.hasLoaded ? countText : nil) {
            DKSegmented(
                VPhoneLocalization.text("Filter"),
                selection: $model.filter,
                options: VPhoneServicesModel.Filter.allCases.map { DKSegmentOption($0.title, value: $0) },
            )
            .help(VPhoneLocalization.text("Show all, running, stopped, or disabled services (⌘1–⌘4)"))
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Start"),
                glyph: .play,
                isEnabled: model.canPerform(.start, on: row),
                help: VPhoneLocalization.text("Start the selected service"),
            ) { request(.start) })
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Stop"),
                glyph: .stop,
                isEnabled: model.canPerform(.stop, on: row),
                help: VPhoneLocalization.text("Stop the selected service"),
            ) { request(.stop) })
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Restart"),
                glyph: .restart,
                isEnabled: model.canPerform(.restart, on: row),
                help: VPhoneLocalization.text("Stop the selected service, then start it again"),
            ) { request(.restart) })
            VPhoneSystemMenuButton(
                label: VPhoneLocalization.text("More Actions"),
                glyph: .ellipsis,
                size: .icon,
                isEnabled: row != nil && !model.isBusy && model.isConnected,
                help: VPhoneLocalization.text("Enable, disable, signal, or remove the selected service"),
            ) {
                model.selectedRow.map(moreActionItems) ?? []
            }
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Refresh"),
                glyph: .refresh,
                size: .icon,
                isEnabled: !model.isBusy && model.isConnected,
                help: VPhoneLocalization.text("Reload the service list (⌘R)"),
            ) { Task { await model.refresh() } })
            VPhoneSystemSearchField(
                placeholder: VPhoneLocalization.text("Label or Program"),
                text: $model.searchText,
                width: 160,
                focus: $searchFocused,
            )
        }
    }

    private var countText: String {
        String(localized: "\(model.visibleRows.count) of \(model.rows.count) services, \(model.runningCount) running", bundle: VPhoneLocalization.bundle)
    }

    private var shortcuts: [VPhoneGuestToolShortcut] {
        var shortcuts = [
            VPhoneGuestToolShortcut(key: "r", isEnabled: !model.isBusy && model.isConnected) {
                Task { await model.refresh() }
            },
            VPhoneGuestToolShortcut(key: "f") { searchFocused = true },
        ]
        for (index, filter) in VPhoneServicesModel.Filter.allCases.enumerated() {
            shortcuts.append(VPhoneGuestToolShortcut(key: KeyEquivalent(Character(String(index + 1)))) {
                model.filter = filter
            })
        }
        return shortcuts
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.rows.isEmpty {
            if model.isBusy, !model.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.isConnected {
                VPhonePanelEmptyState(
                    title: "Guest Not Connected",
                    systemImage: "bolt.horizontal.circle",
                    message: "The service list loads when vphoned connects.",
                )
            } else if model.hasLoaded {
                VPhonePanelEmptyState(
                    title: "No Services",
                    systemImage: "gearshape.2",
                    message: "launchd reported no services.",
                )
            } else {
                VPhonePanelEmptyState(
                    title: "Services Not Loaded",
                    systemImage: "gearshape.2",
                    message: "Choose Refresh to load the service list.",
                )
            }
        } else {
            VSplitView {
                table
                    .frame(minHeight: 160, maxHeight: .infinity)
                    .layoutPriority(1)
                VPhoneServiceDetailView(model: model)
                    .frame(minHeight: 240, idealHeight: 320)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            }
        }
    }

    private var table: some View {
        Table(
            model.visibleRows,
            selection: $model.selection,
            sortOrder: $model.sortOrder,
            columnCustomization: columnCustomization,
        ) {
            TableColumn("Label", value: \.label) { row in
                VPhoneSystemCell(.mono(row.label), help: row.label)
            }
            .width(min: 160, ideal: 220)
            .customizationID("label")

            TableColumn("State", value: \.stateRank) { row in
                VPhoneSystemCell(Self.stateCell(row))
            }
            .width(min: 80, ideal: 90, max: 110)
            .customizationID("state")

            TableColumn("PID", value: \.pidValue) { row in
                VPhoneSystemCell(.mono(row.pidText), alignment: .trailing)
            }
            .width(min: 44, ideal: 52, max: 72)
            .customizationID("pid")

            TableColumn("Last Exit", value: \.lastExitValue) { row in
                VPhoneSystemCell(Self.lastExitCell(row), help: row.lastExit.help)
            }
            .width(min: 64, ideal: 80, max: 120)
            .customizationID("last-exit")

            TableColumn("Disabled", value: \.disabledRank) { row in
                VPhoneSystemCell(Self.disabledCell(row))
            }
            .width(min: 60, ideal: 70, max: 90)
            .customizationID("disabled")

            TableColumn("Domains", value: \.domainText) { row in
                VPhoneSystemCell(.mono(row.domainText))
            }
            .width(min: 64, ideal: 88, max: 140)
            .customizationID("domains")
            .defaultVisibility(.hidden)

            TableColumn("Program", value: \.programText) { row in
                VPhoneSystemCell(row.program.map(DKTableCell.mono) ?? .muted("—"), help: row.program)
            }
            .width(min: 120, ideal: 260)
            .customizationID("program")
        }
        .systemPageTable()
        .contextMenu(forSelectionType: VPhoneServiceRow.ID.self) { labels in
            if let label = labels.first, let row = model.row(label) {
                Button("Copy Label") { model.copy(row.label) }
                Button("Copy Program Path") { model.copy(row.program ?? "") }
                    .disabled(row.program == nil)
                Divider()
                actionItems(for: row)
            }
        }
        .overlay {
            if model.visibleRows.isEmpty {
                VPhonePanelEmptyState(
                    title: "No Matching Services",
                    systemImage: "magnifyingglass",
                    message: "No service matches the filter and search.",
                )
            }
        }
        .accessibilityLabel("launchd services")
    }

    private var columnCustomization: Binding<TableColumnCustomization<VPhoneServiceRow>> {
        Binding(
            get: { (try? JSONDecoder().decode(TableColumnCustomization<VPhoneServiceRow>.self, from: columnData)) ?? .init() },
            set: { columnData = (try? JSONEncoder().encode($0)) ?? Data() },
        )
    }

    // MARK: - Cells

    static func stateCell(_ row: VPhoneServiceRow) -> DKTableCell {
        row.isRunning
            ? .status(.success, VPhoneLocalization.text("Running"))
            : .status(.idle, VPhoneLocalization.text("Stopped"))
    }

    /// A clean exit in plain figures; an exit code or signal as a badge.
    static func lastExitCell(_ row: VPhoneServiceRow) -> DKTableCell {
        let exit = row.lastExit
        return exit.isAbnormal ? .badge(.warning, exit.text) : .mono(exit.text)
    }

    static func disabledCell(_ row: VPhoneServiceRow) -> DKTableCell {
        row.disabled == true ? .badge(.warning, row.disabledText) : .muted(row.disabledText)
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionItems(for row: VPhoneServiceRow) -> some View {
        Button("Start") { model.request(.start, on: row.label) }
            .disabled(!model.canPerform(.start, on: row))
        Button("Stop…") { model.request(.stop, on: row.label) }
            .disabled(!model.canPerform(.stop, on: row))
        Button("Restart…") { model.request(.restart, on: row.label) }
            .disabled(!model.canPerform(.restart, on: row))
        Divider()
        Button("Enable") { model.request(.enable, on: row.label) }
            .disabled(!model.canPerform(.enable, on: row))
        Button("Disable…") { model.request(.disable, on: row.label) }
            .disabled(!model.canPerform(.disable, on: row))
        Menu("Send Signal") {
            ForEach(VPhoneServiceSignal.allCases) { signal in
                Button {
                    model.request(.signal(signal), on: row.label)
                } label: {
                    Text(verbatim: "\(signal.title)…")
                }
            }
        }
        .disabled(!model.canPerform(.signal(.term), on: row))
        Divider()
        Button("Remove…", role: .destructive) { model.request(.remove, on: row.label) }
            .disabled(!model.canPerform(.remove, on: row))
    }

    /// The More Actions menu: the context menu's actions after Start, Stop
    /// and Restart, which have their own buttons.
    private func moreActionItems(for row: VPhoneServiceRow) -> [DKMenuItem] {
        let label = row.label
        return [
            DKMenuItem(VPhoneLocalization.text("Enable"), isEnabled: model.canPerform(.enable, on: row)) {
                model.request(.enable, on: label)
            },
            DKMenuItem(VPhoneLocalization.text("Disable…"), isEnabled: model.canPerform(.disable, on: row)) {
                model.request(.disable, on: label)
            },
            .submenu(
                VPhoneLocalization.text("Send Signal"),
                isEnabled: model.canPerform(.signal(.term), on: row),
                items: VPhoneServiceSignal.allCases.map { signal in
                    DKMenuItem("\(signal.title)…") { model.request(.signal(signal), on: label) }
                },
            ),
            .separator,
            DKMenuItem(VPhoneLocalization.text("Remove…"), isEnabled: model.canPerform(.remove, on: row), isDestructive: true) {
                model.request(.remove, on: label)
            },
        ]
    }

    private func request(_ action: VPhoneServiceAction) {
        guard let label = model.selection else { return }
        model.request(action, on: label)
    }

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { model.pendingAction != nil },
            set: {
                if !$0 {
                    model.pendingAction = nil
                }
            },
        )
    }
}
