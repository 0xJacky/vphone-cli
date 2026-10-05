import SwiftUI
import VPhoneDesignKit

struct VPhoneConsoleView: View {
    @Bindable var model: VPhoneConsoleModel
    @State private var searchFocused = false
    /// Which columns show. Category starts hidden; the detail bar shows it.
    @AppStorage("vphone-console-columns") private var columnData = Data()

    var body: some View {
        VStack(spacing: 0) {
            header
            VPhoneSystemPageBanner(status: model.status)
            Group {
                if model.visibleEntries.isEmpty {
                    emptyState
                } else {
                    VSplitView {
                        table
                            .frame(minHeight: 120, idealHeight: 420, maxHeight: .infinity)
                            .layoutPriority(1)
                        detail
                            .frame(minHeight: 140, idealHeight: 180, maxHeight: 420)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusBar
        }
        .background(DK.Palette.window)
        .guestToolShortcuts([
            VPhoneGuestToolShortcut(key: "p") { model.toggleRunning() },
            VPhoneGuestToolShortcut(key: "r", isEnabled: canCapture) {
                Task { await model.captureOnce() }
            },
            VPhoneGuestToolShortcut(key: "k", isEnabled: !model.entries.isEmpty) { model.clear() },
            VPhoneGuestToolShortcut(key: "s", isEnabled: !model.visibleEntries.isEmpty) { model.save() },
            VPhoneGuestToolShortcut(key: "f") { searchFocused = true },
        ])
        .task { await model.run() }
    }

    private var canCapture: Bool {
        !model.isRunning && !model.isCapturing && model.control.isConnected
    }

    // MARK: - Header

    private var header: some View {
        DKPageHeader(VPhoneLocalization.text("Console"), subtitle: subtitle) {
            DKButton(DKButtonSpec(
                VPhoneLocalization.text(model.isRunning ? "Pause" : "Start"),
                glyph: model.isRunning ? .pause : .play,
                variant: .primary,
                help: VPhoneLocalization.text(model.isRunning ? "Pause streaming (⌘P)" : "Start streaming (⌘P)"),
            ) { model.toggleRunning() })
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Refresh"),
                glyph: .refresh,
                size: .icon,
                isEnabled: canCapture,
                help: VPhoneLocalization.text("Capture 2 seconds of log while paused (⌘R)"),
            ) { Task { await model.captureOnce() } })
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Clear"),
                glyph: .trash,
                size: .icon,
                isEnabled: !model.entries.isEmpty,
                help: VPhoneLocalization.text("Clear all loaded entries (⌘K)"),
            ) { model.clear() })
            TextField(VPhoneLocalization.text("Process"), text: $model.processFilter, prompt: Text(VPhoneLocalization.text("Process")))
                .textFieldStyle(DKFieldStyle(mono: true))
                .frame(width: 104)
                .help(VPhoneLocalization.text("Capture only processes whose name contains this text. Applies to the next capture."))
            DKSegmented(
                VPhoneLocalization.text("Level"),
                selection: $model.levelFilter,
                options: VPhoneConsoleLevelFilter.allCases.map { DKSegmentOption($0.title, value: $0) },
            )
            .help(VPhoneLocalization.text("Show all levels, errors and faults, or faults only"))
            VPhoneSystemToggleButton(
                label: VPhoneLocalization.text("Auto-Scroll"),
                glyph: .download,
                isOn: $model.autoScroll,
                size: .icon,
                help: VPhoneLocalization.text("Keep the newest entry visible"),
            )
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Save…"),
                glyph: .download,
                size: .icon,
                isEnabled: !model.visibleEntries.isEmpty,
                help: VPhoneLocalization.text("Save the shown entries as a plain-text log (⌘S)"),
            ) { model.save() })
            DKSearchField(
                VPhoneLocalization.text("Search"),
                text: $model.searchText,
                isFocused: $searchFocused,
                width: 140,
            )
        }
    }

    private var subtitle: String {
        guard model.isRunning else {
            return VPhoneLocalization.text("Streaming paused")
        }
        let process = model.processFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        return process.isEmpty
            ? VPhoneLocalization.text("Streaming the guest unified log")
            : String(localized: "Streaming the guest unified log for “\(process)”", bundle: VPhoneLocalization.bundle)
    }

    // MARK: - Table

    @ViewBuilder
    private var emptyState: some View {
        if !model.entries.isEmpty {
            VPhonePanelEmptyState(
                title: "No Matching Entries",
                systemImage: "line.3.horizontal.decrease.circle",
                message: "No loaded entry matches the search or level filter.",
            )
        } else if !model.control.isConnected {
            VPhonePanelEmptyState(
                title: "Guest Not Connected",
                systemImage: "bolt.horizontal.circle",
                message: "The log streams once the guest connects.",
            )
        } else if model.isRunning {
            VPhonePanelEmptyState(
                title: "Waiting for Log Entries",
                systemImage: "text.alignleft",
                message: "Entries appear here as the guest logs them.",
            )
        } else {
            VPhonePanelEmptyState(
                title: "Streaming Paused",
                systemImage: "pause.circle",
                message: "Choose Start to stream the guest unified log.",
            )
        }
    }

    private var table: some View {
        ScrollViewReader { proxy in
            Table(
                model.visibleEntries,
                selection: $model.selection,
                sortOrder: $model.sortOrder,
                columnCustomization: columnCustomization,
            ) {
                TableColumn("Time", value: \.id) { entry in
                    VPhoneSystemCell(.mono(entry.time))
                }
                .width(min: 88, ideal: 96, max: 120)
                .customizationID("time")

                TableColumn("Level", value: \.level) { entry in
                    VPhoneSystemCell(.status(entry.level.tone, entry.level.title))
                }
                .width(min: 70, ideal: 86, max: 100)
                .customizationID("level")

                TableColumn("Process", value: \.process) { entry in
                    VPhoneSystemCell(.text(entry.process), help: entry.process)
                }
                .width(min: 72, ideal: 110, max: 240)
                .customizationID("process")

                TableColumn("PID", value: \.pid) { entry in
                    VPhoneSystemCell(.mono(String(entry.pid)), alignment: .trailing)
                }
                .width(min: 40, ideal: 48, max: 72)
                .customizationID("pid")

                TableColumn("Subsystem", value: \.subsystem) { entry in
                    VPhoneSystemCell(.mono(entry.subsystem), help: entry.subsystem)
                }
                .width(min: 72, ideal: 150, max: 320)
                .customizationID("subsystem")

                TableColumn("Category", value: \.category) { entry in
                    VPhoneSystemCell(.mono(entry.category))
                }
                .width(min: 56, ideal: 80, max: 200)
                .customizationID("category")
                .defaultVisibility(.hidden)

                TableColumn("Message", value: \.message) { entry in
                    VPhoneSystemCell(
                        .mono(entry.summary),
                        help: entry.message.count > 2000 ? String(entry.message.prefix(2000)) + "…" : entry.message,
                    )
                }
                .width(min: 160)
                .customizationID("message")
            }
            .systemPageTable()
            .contextMenu(forSelectionType: VPhoneConsoleEntry.ID.self) { ids in
                contextMenu(ids)
            }
            .onChange(of: model.newestVisibleID) { _, _ in scrollToNewest(proxy) }
            .onChange(of: model.autoScroll) { _, _ in scrollToNewest(proxy) }
            .onAppear { scrollToNewest(proxy) }
            .accessibilityLabel("Guest log entries")
        }
    }

    private var columnCustomization: Binding<TableColumnCustomization<VPhoneConsoleEntry>> {
        Binding(
            get: { (try? JSONDecoder().decode(TableColumnCustomization<VPhoneConsoleEntry>.self, from: columnData)) ?? .init() },
            set: { columnData = (try? JSONEncoder().encode($0)) ?? Data() },
        )
    }

    @ViewBuilder
    private func contextMenu(_ ids: Set<VPhoneConsoleEntry.ID>) -> some View {
        let rows = model.selectedEntries(ids)
        if !rows.isEmpty {
            if rows.count == 1, let entry = rows.first {
                Button("Copy Message") { model.copy(entry.message) }
            }
            Button(rows.count == 1 ? "Copy Line" : "Copy Lines") { model.copy(model.logText(rows)) }
            if rows.count == 1, let entry = rows.first, !entry.process.isEmpty {
                Divider()
                Button("Capture Only \(entry.process)") { model.showOnlyProcess(of: entry) }
            }
        }
    }

    private func scrollToNewest(_ proxy: ScrollViewProxy) {
        guard model.autoScroll, let id = model.newestVisibleID else { return }
        proxy.scrollTo(id, anchor: .bottomLeading)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let entry = model.selectedEntry {
            DKDetailBar(
                entry.process.isEmpty ? "—" : entry.process,
                subtitle: "[\(entry.pid)] · \(entry.level.title)",
                note: ([model.fullDate(entry)] + [entry.subsystem, entry.category].filter { !$0.isEmpty }).joined(separator: " · "),
            ) {
                VPhoneSystemTextLog(
                    text: entry.message,
                    tone: entry.level.lineTone,
                    label: VPhoneLocalization.text("Selected entry"),
                    minHeight: 48,
                )
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        } else {
            Text(model.selection.count > 1 ? "\(model.selection.count) entries selected." : "Select an entry to see its full message.")
                .font(DK.Typeface.caption)
                .foregroundStyle(DK.Palette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DK.Palette.surfaceRaised)
        }
    }

    // MARK: - Status

    private var statusBar: some View {
        var items: [DKStatusItem] = []
        if model.lastCaptureTruncated {
            items.append(DKStatusItem(
                VPhoneLocalization.text("Truncated"),
                glyph: .warning,
                title: String(localized: "The last capture reached \(VPhoneConsoleModel.captureMaxLines) entries; the guest dropped the rest.", bundle: VPhoneLocalization.bundle),
            ))
        }
        return VPhoneSystemPageStatusBar(
            isConnected: model.control.isConnected,
            activity: nil,
            status: model.status,
            idleText: model.isRunning ? VPhoneLocalization.text("Streaming…") : nil,
            items: items,
            detail: "\(countText) · \(VPhoneLocalization.text(model.isRunning ? "Running" : "Paused"))",
        )
    }

    private var countText: String {
        let loaded = model.entries.count
        if model.isFiltered {
            return String(localized: "\(model.visibleEntries.count) of \(loaded) entries", bundle: VPhoneLocalization.bundle)
        }
        return String(localized: "\(loaded) entries", bundle: VPhoneLocalization.bundle)
    }
}

// MARK: - Level Style

extension VPhoneConsoleLevel {
    /// The status dot of the Level column: fault red, error amber, others idle.
    var tone: DKTone {
        switch self {
        case .fault: .danger
        case .error: .warning
        default: .idle
        }
    }

    /// The color of the selected entry's message.
    var lineTone: DKLogLine.Tone {
        switch self {
        case .fault: .error
        case .error: .warning
        case .debug: .dim
        default: .plain
        }
    }
}
