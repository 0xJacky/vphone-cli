import SwiftUI
import VPhoneDesignKit

// MARK: - Window Content

/// The Guest Tools window: the guest sidebar beside the selected tool's page.
/// Each page draws its own header and status bar, so the panel gets neither.
struct VPhoneGuestToolsView: View {
    @Bindable var shell: VPhoneGuestToolsShell

    var body: some View {
        // The sidebar draws its own trailing edge and each page its own
        // header and status bar lines.
        DKPanel(drawsDividers: false) {
            VPhoneGuestToolsSidebar(shell: shell)
        } header: {
            EmptyView()
        } content: {
            page
                .id(shell.selection)
        }
    }

    @ViewBuilder
    private var page: some View {
        switch shell.availability(of: shell.selection) {
        case .available:
            VPhoneGuestToolPage(tool: shell.selection, shell: shell)
        case let .unsupported(capability):
            VPhoneGuestToolUnavailableView(tool: shell.selection, capability: capability)
        }
    }
}

// MARK: - Pages

/// The page of one tool, over the shell's model for it.
private struct VPhoneGuestToolPage: View {
    let tool: DKGuestTool
    let shell: VPhoneGuestToolsShell

    var body: some View {
        switch tool {
        case .deviceInfo: VPhoneDeviceInfoView(model: shell.deviceInfoModel)
        case .controls: VPhoneControlsView(model: shell.controlsModel)
        case .apps: VPhoneAppBrowserView(model: shell.appsModel)
        case .processes: VPhoneProcessesView(model: shell.processesModel)
        case .services: VPhoneServicesView(model: shell.servicesModel)
        case .files: VPhoneFileBrowserView(model: shell.filesModel)
        case .keychain: VPhoneKeychainBrowserView(model: shell.keychainModel)
        case .preferences: VPhoneGuestPreferencesView(model: shell.preferencesModel)
        case .clipboard: VPhoneGuestClipboardView(model: shell.clipboardModel)
        case .console: VPhoneConsoleView(model: shell.consoleModel)
        case .crashLogs: VPhoneCrashLogsView(model: shell.crashLogsModel)
        }
    }
}

// MARK: - Sidebar

/// The guest sidebar: the machine with its connection, iOS version and
/// address, then the tools. A tool the connected agent does not serve stays
/// listed, marked Unavailable; its page says why.
struct VPhoneGuestToolsSidebar: View {
    @Bindable var shell: VPhoneGuestToolsShell

    var body: some View {
        let control = shell.control
        DKSidebar(sections: sections, selection: $shell.selection, header: {
            DKSidebarMachineHeader(
                shell.machineName,
                tone: DKConnectionState(isConnected: control.isConnected).tone,
                stateLabel: control.isConnected
                    ? String(localized: "Guest connected", bundle: VPhoneLocalization.bundle)
                    : String(localized: "Guest not connected", bundle: VPhoneLocalization.bundle),
                facts: facts(control),
            )
        })
        .accessibilityLabel(String(localized: "Guest Tools", bundle: VPhoneLocalization.bundle))
    }

    private var sections: [DKSidebarSection<DKGuestTool>] {
        let unavailable = String(localized: "Unavailable", bundle: VPhoneLocalization.bundle)
        return DKGuestSidebar.sections().map { section in
            var section = section
            section.items = section.items.map { item in
                var item = item
                item.label = item.id.localizedTitle
                if shell.availability(of: item.id) != .available {
                    item.meta = unavailable
                }
                return item
            }
            return section
        }
    }

    private func facts(_ control: VPhoneGuestControl) -> [DKSidebarFact] {
        var facts: [DKSidebarFact] = []
        if let version = control.guestIOSVersion, !version.isEmpty {
            facts.append(DKSidebarFact(String(localized: "iOS", bundle: VPhoneLocalization.bundle), version))
        }
        if let address = control.guestIPAddress, !address.isEmpty {
            facts.append(DKSidebarFact(
                String(localized: "Address", bundle: VPhoneLocalization.bundle),
                address,
                isMonospaced: true,
            ))
        }
        return facts
    }
}

// MARK: - Unavailable Tool

/// The page of a tool the connected agent does not serve.
struct VPhoneGuestToolUnavailableView: View {
    let tool: DKGuestTool
    let capability: String

    var body: some View {
        VStack(spacing: 0) {
            DKPageHeader(
                tool.localizedTitle,
                subtitle: String(localized: "Not available on this guest", bundle: VPhoneLocalization.bundle),
            )
            VPhoneGuestToolPlaceholder(
                glyph: tool.glyph,
                title: String(localized: "\(tool.localizedTitle) Unavailable", bundle: VPhoneLocalization.bundle),
                message: String(
                    localized: "The guest agent does not report the “\(capability)” capability. Update vphoned in the guest to use \(tool.localizedTitle).",
                    bundle: VPhoneLocalization.bundle,
                ),
            )
            DKStatusBar(isConnected: true, detail: capability)
        }
    }
}

// MARK: - Placeholder

/// A centered glyph, title and sentence for a page with nothing to show yet:
/// before the first load, while the guest is not connected, or for a tool the
/// guest does not serve.
struct VPhoneGuestToolPlaceholder: View {
    let glyph: DKGlyph
    let title: String
    var message: String?
    var isLoading = false

    var body: some View {
        VStack(spacing: DK.Space.s2) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, DK.Space.s1)
            } else {
                DKIcon(glyph, size: 28)
                    .foregroundStyle(DK.Palette.muted)
                    .padding(.bottom, DK.Space.s1)
            }
            Text(title)
                .font(DK.Typeface.bodyStrong)
                .foregroundStyle(DK.Palette.ink)
            if let message, !message.isEmpty {
                Text(message)
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
            }
        }
        .padding(DK.Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
