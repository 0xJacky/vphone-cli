import SwiftUI
import VPhoneCoreKit
import VPhoneDesignKit

struct VPhoneAppBrowserView: View {
    @Bindable var model: VPhoneAppBrowserModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            VPhoneSystemPageBanner(status: model.status)
            HStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.isInspectorPresented {
                    DK.Palette.divider
                        .frame(width: DK.Metric.hairline)
                    VPhoneAppInfoView(model: model)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VPhoneSystemPageStatusBar(
                isConnected: model.control.isConnected,
                activity: model.activity?.title,
                status: model.status,
                detail: model.hasLoaded ? model.countText : nil,
            )
        }
        .background(DK.Palette.window)
        .guestToolShortcuts(shortcuts)
        .task { await model.refresh() }
        .task(id: inspectedID) {
            guard model.isInspectorPresented else { return }
            await model.loadDetail(for: inspectedID)
        }
        .onChange(of: model.control.isConnected) { _, connected in
            if connected {
                Task { await model.refresh() }
            }
        }
        .onAppear(perform: applySearchFocusRequest)
        .onChange(of: model.isSearchFocusRequested) { _, _ in applySearchFocusRequest() }
        .confirmationDialog(
            uninstallTitle,
            isPresented: $model.isConfirmingUninstall,
            titleVisibility: .visible,
        ) {
            Button("Uninstall", role: .destructive) {
                Task { await model.uninstallConfirmed() }
            }
            Button("Cancel", role: .cancel) { model.uninstallCandidates = [] }
        } message: {
            Text("The app, its data container and its plug-ins' data are removed from the guest. This cannot be undone.")
        }
        .sheet(item: $model.openURLTarget) { app in
            VPhoneAppOpenURLSheet(model: model, app: app)
        }
        .fileImporter(
            isPresented: $model.isImportingPackage,
            allowedContentTypes: VPhoneInstallPackage.allowedContentTypes,
        ) { result in
            guard case let .success(url) = result else { return }
            Task { await model.install(packageAt: url) }
        }
    }

    /// The info pane follows the selection while it is open.
    private var inspectedID: VPhoneAppRecord.ID? {
        model.isInspectorPresented ? model.selectedApp?.id : nil
    }

    private var uninstallTitle: String {
        let targets = model.uninstallCandidates
        if targets.count == 1, let app = targets.first {
            return String(localized: "Uninstall “\(app.displayName)”?", bundle: VPhoneLocalization.bundle)
        }
        return String(localized: "Uninstall \(targets.count) apps?", bundle: VPhoneLocalization.bundle)
    }

    private func applySearchFocusRequest() {
        guard model.isSearchFocusRequested else { return }
        model.isSearchFocusRequested = false
        Task { isSearchFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        DKPageHeader(VPhoneLocalization.text("Apps"), subtitle: model.hasLoaded ? subtitle : nil) {
            DKSegmented(
                VPhoneLocalization.text("Filter"),
                selection: $model.filter,
                options: VPhoneAppBrowserModel.Filter.allCases.map { DKSegmentOption($0.title, value: $0) },
            )
            .help(VPhoneLocalization.text("Filter apps by type (⌘1, ⌘2, ⌘3, ⌘4)"))
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Launch"),
                glyph: .play,
                variant: .primary,
                isEnabled: model.canLaunch(model.selection),
                help: VPhoneLocalization.text("Launch the selected app (⌘↩)"),
            ) { launchSelection() })
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Terminate"),
                glyph: .stop,
                size: .icon,
                isEnabled: model.canTerminate(model.selection),
                help: VPhoneLocalization.text("Terminate the selected apps (⌥⌘Q)"),
            ) { Task { await model.terminate(model.apps(model.selection)) } })
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Install App Package"),
                glyph: .download,
                size: .icon,
                isEnabled: !model.isBusy && model.control.isConnected,
                help: VPhoneLocalization.text("Install an IPA or TIPA package (⌘O)"),
            ) { model.isImportingPackage = true })
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Refresh"),
                glyph: .refresh,
                size: .icon,
                isEnabled: !model.isBusy,
                help: VPhoneLocalization.text("Reload the app list (⌘R)"),
            ) { Task { await model.refresh() } })
            VPhoneSystemToggleButton(
                label: VPhoneLocalization.text("App Info"),
                glyph: .info,
                isOn: $model.isInspectorPresented,
                size: .icon,
                help: VPhoneLocalization.text("Show or hide app info (⌘I)"),
            )
            VPhoneSystemSearchField(
                placeholder: VPhoneLocalization.text("Search Apps"),
                text: $model.searchText,
                width: 160,
                focus: $isSearchFocused,
            )
        }
    }

    private var subtitle: String {
        let running = model.apps.count(where: \.isRunning)
        return "\(model.countText) · " + String(localized: "\(running) running", bundle: VPhoneLocalization.bundle)
    }

    private func launchSelection() {
        if let app = model.selectedApp {
            Task { await model.launch(app) }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded {
            if model.activity != nil {
                ProgressView()
            } else if !model.control.isConnected {
                VPhonePanelEmptyState(
                    title: "Guest Not Connected",
                    systemImage: "bolt.horizontal.circle",
                    message: "Start the VM and wait for the guest to connect. The app list loads automatically.",
                )
            } else if model.loadFailed {
                VPhonePanelEmptyState(
                    title: "Unable to Load Apps",
                    systemImage: "exclamationmark.triangle",
                    message: "Check the guest connection, then choose Refresh.",
                )
            } else {
                ProgressView()
            }
        } else {
            appTable
        }
    }

    private var appTable: some View {
        Table(of: VPhoneAppRecord.self, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.displayName) { app in
                VPhoneSystemCell(
                    model.selection.contains(app.id) ? .strong(app.displayName) : .text(app.displayName),
                    help: app.displayName,
                )
            }
            .width(min: 100, ideal: 150, max: .infinity)

            TableColumn("Bundle ID", value: \.bundleID) { app in
                VPhoneSystemCell(.mono(app.bundleID), help: app.bundleID)
            }
            .width(min: 130, ideal: 200, max: .infinity)

            TableColumn("Version", value: \.version) { app in
                VPhoneSystemCell(.muted(app.version.isEmpty ? "—" : app.version))
            }
            .width(min: 52, ideal: 64, max: 140)

            TableColumn("Type", value: \.type) { app in
                VPhoneSystemCell(.muted(app.typeTitle))
            }
            .width(min: 48, ideal: 60, max: 90)

            TableColumn("PID", value: \.pid) { app in
                VPhoneSystemCell(app.isRunning ? .status(.success, String(app.pid)) : .muted("—"))
                    .accessibilityLabel(app.isRunning ? Text("Running, PID \(app.pid)") : Text("Not running"))
            }
            .width(min: 60, ideal: 70, max: 100)
        } rows: {
            ForEach(model.filteredApps) { app in
                TableRow(app)
            }
        }
        .systemPageTable()
        .contextMenu(forSelectionType: VPhoneAppRecord.ID.self) { ids in
            rowMenu(ids)
        } primaryAction: { ids in
            guard ids.count == 1 else { return }
            model.selection = ids
            model.isInspectorPresented = true
        }
        .overlay {
            if model.filteredApps.isEmpty {
                VPhonePanelEmptyState(
                    title: "No Apps",
                    systemImage: "app.dashed",
                    message: model.searchText.isEmpty
                        ? "No apps match this filter."
                        : "No apps match your search.",
                )
            }
        }
    }

    // MARK: - Row Menu

    @ViewBuilder
    private func rowMenu(_ ids: Set<VPhoneAppRecord.ID>) -> some View {
        let targets = model.apps(ids)
        let single = targets.count == 1 ? targets.first : nil

        Button("Launch") {
            if let single {
                Task { await model.launch(single) }
            }
        }
        .disabled(!model.canLaunch(ids))
        Button("Terminate") {
            Task { await model.terminate(targets) }
        }
        .disabled(!model.canTerminate(ids))
        Button("Open URL…") {
            if let single {
                model.requestOpenURL(single)
            }
        }
        .disabled(!model.canLaunch(ids))

        Divider()

        Button("Show Info") {
            model.selection = ids
            model.isInspectorPresented = true
        }
        .disabled(single == nil)
        Button("Show Data Container") {
            if let single {
                Task { await model.showDataContainer(single) }
            }
        }
        .disabled(single == nil || !model.control.isConnected)

        Divider()

        Button("Copy Bundle ID") { model.copy(targets.map(\.bundleID)) }
        Button("Copy Path") { model.copy(targets.map(\.bundlePath)) }
            .disabled(targets.allSatisfy(\.bundlePath.isEmpty))

        Divider()

        Button("Uninstall…", role: .destructive) { model.requestUninstall(targets) }
            .disabled(!model.canUninstall(ids))
    }

    private var shortcuts: [VPhoneGuestToolShortcut] {
        let filters = VPhoneAppBrowserModel.Filter.allCases.map { filter in
            VPhoneGuestToolShortcut(key: filter.shortcut) { model.filter = filter }
        }
        return filters + [
            VPhoneGuestToolShortcut(key: "r", isEnabled: !model.isBusy) {
                Task { await model.refresh() }
            },
            VPhoneGuestToolShortcut(key: "i") { model.isInspectorPresented.toggle() },
            VPhoneGuestToolShortcut(key: "f") { isSearchFocused = true },
            VPhoneGuestToolShortcut(key: .return, isEnabled: model.canLaunch(model.selection)) {
                launchSelection()
            },
            VPhoneGuestToolShortcut(key: "q", modifiers: [.command, .option], isEnabled: model.canTerminate(model.selection)) {
                Task { await model.terminate(model.apps(model.selection)) }
            },
            VPhoneGuestToolShortcut(key: .delete, isEnabled: model.canUninstall(model.selection) && !isSearchFocused) {
                model.requestUninstall(model.apps(model.selection))
            },
            VPhoneGuestToolShortcut(key: "o", isEnabled: !model.isBusy && model.control.isConnected) {
                model.isImportingPackage = true
            },
        ]
    }
}

// MARK: - Open URL Sheet

/// Opens a URL in one app through `apps.open_url`.
struct VPhoneAppOpenURLSheet: View {
    @Bindable var model: VPhoneAppBrowserModel
    let app: VPhoneAppRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s3) {
            Text("Open URL in \(app.displayName)")
                .font(DK.Typeface.sheetTitle)
                .foregroundStyle(DK.Palette.ink)
            TextField("URL", text: $model.openURLText, prompt: Text(verbatim: "scheme://path"))
                .textFieldStyle(DKFieldStyle(mono: true))
                .onSubmit(open)
            HStack(spacing: DK.Space.s2) {
                Spacer()
                Button(VPhoneLocalization.text("Cancel"), role: .cancel) { dismiss() }
                    .buttonStyle(DKButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(VPhoneLocalization.text("Open"), action: open)
                    .buttonStyle(DKButtonStyle(variant: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.openURLText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DK.Space.s5)
        .frame(width: 420)
        .background(DK.Palette.window)
    }

    private func open() {
        let url = model.openURLText
        dismiss()
        Task { await model.openURL(url, in: app) }
    }
}
