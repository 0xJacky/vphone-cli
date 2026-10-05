import AppKit
import SwiftUI
import VPhoneDesignKit

struct VPhoneCrashLogsView: View {
    @Bindable var model: VPhoneCrashLogsModel
    @State private var searchFocused = false

    var body: some View {
        VStack(spacing: 0) {
            header
            VPhoneSystemPageBanner(status: model.status)
            HSplitView {
                listPane
                    .frame(minWidth: 400, maxHeight: .infinity)
                detailPane
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            VPhoneGuestToolShortcut(key: "c", modifiers: [.command, .shift], isEnabled: model.canCopy) {
                model.copyFocusedReport()
            },
            VPhoneGuestToolShortcut(key: "s", isEnabled: model.canExport) {
                export(model.selection)
            },
        ])
        .task { await model.refresh() }
        .onChange(of: model.selection) { _, _ in model.loadSelection() }
        .onChange(of: model.control.isConnected) { _, connected in
            guard connected, !model.hasLoaded else { return }
            Task { await model.refresh() }
        }
    }

    // MARK: - Header

    private var header: some View {
        DKPageHeader(VPhoneLocalization.text("Crash Logs"), subtitle: model.hasLoaded ? subtitle : nil) {
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Copy"),
                glyph: .copy,
                isEnabled: model.canCopy,
                help: VPhoneLocalization.text("Copy the full report text (⇧⌘C)"),
            ) { model.copyFocusedReport() })
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Export…"),
                glyph: .upload,
                isEnabled: model.canExport,
                help: VPhoneLocalization.text("Save the selected reports to the Mac (⌘S)"),
            ) { export(model.selection) })
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Refresh"),
                glyph: .refresh,
                size: .icon,
                isEnabled: !model.isBusy,
                help: VPhoneLocalization.text("Reload the list of crash reports (⌘R)"),
            ) { Task { await model.refresh() } })
            DKSearchField(
                VPhoneLocalization.text("Filter by process or name"),
                text: $model.searchText,
                isFocused: $searchFocused,
                width: 200,
            )
        }
    }

    private var subtitle: String {
        String(localized: "\(model.reports.count) reports in CrashReporter and DiagnosticReports", bundle: VPhoneLocalization.bundle)
    }

    private var countText: String {
        let visible = model.visibleReports.count
        return visible == model.reports.count
            ? String(localized: "\(visible) reports", bundle: VPhoneLocalization.bundle)
            : String(localized: "\(visible) of \(model.reports.count) reports", bundle: VPhoneLocalization.bundle)
    }

    // MARK: - List

    @ViewBuilder
    private var listPane: some View {
        let rows = model.visibleReports
        if !model.hasLoaded {
            if model.activity == .listing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.control.isConnected {
                VPhonePanelEmptyState(
                    title: "Guest Not Connected",
                    systemImage: "network.slash",
                    message: "Crash reports appear here once the guest connects.",
                )
            } else {
                VPhonePanelEmptyState(
                    title: "No Crash Reports Loaded",
                    systemImage: "exclamationmark.octagon",
                    message: "Choose Refresh to list the guest's crash reports.",
                )
            }
        } else if model.reports.isEmpty {
            VPhonePanelEmptyState(
                title: "No Crash Reports",
                systemImage: "checkmark.seal",
                message: "The guest has no reports in CrashReporter or DiagnosticReports.",
            )
        } else if rows.isEmpty {
            VPhonePanelEmptyState(
                title: "No Matching Reports",
                systemImage: "magnifyingglass",
                message: "No process or file name contains that text.",
            )
        } else {
            table(rows)
        }
    }

    private func table(_ rows: [VPhoneCrashReport]) -> some View {
        Table(rows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Date", value: \.mtime) { report in
                VPhoneSystemCell(.muted(report.dateText))
            }
            .width(min: 110, ideal: 134, max: 160)

            TableColumn("Process", value: \.process) { report in
                VPhoneSystemCell(
                    model.selection.contains(report.id) ? .strong(report.process) : .text(report.process),
                    help: report.process,
                )
            }
            .width(min: 80, ideal: 120)

            TableColumn("Type", value: \.kindTitle) { report in
                VPhoneSystemCell(.muted(report.kindTitle), help: report.name)
            }
            .width(min: 80, ideal: 110, max: 140)

            TableColumn("File Size", value: \.size) { report in
                VPhoneSystemCell(.mono(report.sizeText), alignment: .trailing)
            }
            .width(min: 56, ideal: 64, max: 90)
        }
        .systemPageTable()
        .contextMenu(forSelectionType: VPhoneCrashReport.ID.self) { ids in
            if !ids.isEmpty {
                let reports = model.reports(for: ids)
                Button("Copy Path") { model.copy(reports.map(\.path)) }
                Button("Copy Name") { model.copy(reports.map(\.name)) }
                Divider()
                Button("Export…") { export(ids) }
                    .disabled(model.isBusy)
            }
        }
        .accessibilityLabel("Crash reports")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let report = model.focusedReport {
            let content = model.contents[report.path]
            VStack(spacing: 0) {
                DKDetailBar(
                    report.name,
                    note: report.path,
                    facts: facts(content?.header),
                ) {
                    detailControls(content)
                }
                detailBody(report)
                    .padding(.vertical, DK.Space.s3)
                    .padding(.horizontal, DK.Space.s4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if model.selection.count > 1 {
            VPhonePanelEmptyState(
                title: "\(model.selection.count) Reports Selected",
                systemImage: "doc.on.doc",
                message: "Choose Export to save each report to a folder.",
            )
        } else {
            VPhonePanelEmptyState(
                title: "No Report Selected",
                systemImage: "doc.text.magnifyingglass",
                message: "Select a report to read it.",
            )
        }
    }

    private func facts(_ header: VPhoneCrashReportContent.Header?) -> [DKKeyValue] {
        guard let header else { return [] }
        let values: [(String, String?)] = [
            ("App", header.appName),
            ("Bug Type", header.bugType),
            ("OS Version", header.osVersion),
            ("Timestamp", header.timestamp),
            ("Incident ID", header.incidentID),
        ]
        return values.compactMap { key, value in
            value.map { DKKeyValue(VPhoneLocalization.text(key), $0) }
        }
    }

    private func detailControls(_ content: VPhoneCrashReportContent?) -> some View {
        HStack(spacing: DK.Space.s3) {
            HStack(spacing: DK.Space.s2) {
                Text(VPhoneLocalization.text("Wrap Lines"))
                    .font(DK.Typeface.body)
                DKSwitch(VPhoneLocalization.text("Wrap Lines"), isOn: $model.wrapLines)
            }
            .help(VPhoneLocalization.text("Wrap long lines to the width of the pane"))
            if content?.truncated == true {
                HStack(spacing: DK.Space.s1) {
                    DKIcon(.warning, size: 13)
                        .foregroundStyle(DK.Palette.warning)
                    Text(VPhoneLocalization.text("The guest sent only part of this report."))
                        .font(DK.Typeface.caption)
                        .foregroundStyle(DK.Palette.warningInk)
                }
            }
        }
    }

    @ViewBuilder
    private func detailBody(_ report: VPhoneCrashReport) -> some View {
        if let content = model.contents[report.path] {
            VPhoneCrashReportTextView(identity: content.path, text: content.displayText, wrapLines: model.wrapLines)
                .clipShape(RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                        .strokeBorder(DK.Palette.line, lineWidth: DK.Metric.hairline)
                }
        } else if let message = model.loadErrors[report.path], !model.loadingPaths.contains(report.path) {
            DKBanner(
                String(localized: "Unable to load the report. \(message)", bundle: VPhoneLocalization.bundle),
                tone: .warning,
                actionLabel: VPhoneLocalization.text("Try Again"),
            ) { model.retryFocusedReport() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(VPhoneLocalization.text("Loading report…"))
                    .font(DK.Typeface.monoSmall)
                    .foregroundStyle(DK.Palette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Export

    /// One report goes through a save panel under its guest file name;
    /// several go into a folder the user picks.
    private func export(_ ids: Set<VPhoneCrashReport.ID>) {
        let reports = model.reports(for: ids)
        guard !reports.isEmpty, !model.isBusy else { return }
        if reports.count == 1, let report = reports.first {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = report.name
            panel.canCreateDirectories = true
            VPhoneAlert.present(panel, on: NSApp.keyWindow) { response in
                guard response == .OK, let url = panel.url else { return }
                Task { await model.export(report, to: url) }
            }
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = VPhoneLocalization.text("Export Here")
            panel.message = VPhoneLocalization.text("Choose a folder for the selected reports.")
            VPhoneAlert.present(panel, on: NSApp.keyWindow) { response in
                guard response == .OK, let url = panel.url else { return }
                Task { await model.export(reports, toDirectory: url) }
            }
        }
    }
}
