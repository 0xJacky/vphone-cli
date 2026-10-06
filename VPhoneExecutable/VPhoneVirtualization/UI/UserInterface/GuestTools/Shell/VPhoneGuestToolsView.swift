import SwiftUI
import VPhoneDesignKit

// MARK: - Window Content

/// The Guest Tools window: the guest sidebar beside the selected tool's page.
/// Each page draws its own header and status bar, so the panel gets neither.
///
/// The window has no system title bar, toolbar or buttons of its own: the
/// sidebar draws close, minimize and zoom at its top, and each page header
/// runs to the window's top edge, its title in line with the buttons.
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
        .environment(\.dkLocalizationBundle, VPhoneLocalization.bundle)
        .environment(\.dkPageHeaderIsTitleBar, true)
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
/// listed, dimmed, with the reason as its tooltip.
struct VPhoneGuestToolsSidebar: View {
    @Bindable var shell: VPhoneGuestToolsShell

    var body: some View {
        let control = shell.control
        DKSidebar(sections: sections, selection: $shell.selection, windowControls: true, header: {
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
        Self.sections(unavailable: shell.unavailableTools)
    }

    /// `DKGuestSidebar`'s sections, titled from this app's string catalog.
    static func sections(unavailable: [DKGuestTool: String]) -> [DKSidebarSection<DKGuestTool>] {
        let bundle = VPhoneLocalization.bundle
        return zip(DKGuestToolSection.allCases, DKGuestSidebar.sections(unavailable: unavailable)).map { group, section in
            var section = section
            section.title = group.title(bundle: bundle)
            section.items = section.items.map { item in
                var item = item
                item.label = item.id.title(bundle: bundle)
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
                tool.title(bundle: VPhoneLocalization.bundle),
                subtitle: String(localized: "Not available on this guest", bundle: VPhoneLocalization.bundle),
            )
            VPhoneGuestToolPlaceholder(
                glyph: tool.glyph,
                title: String(localized: "\(tool.title(bundle: VPhoneLocalization.bundle)) Unavailable", bundle: VPhoneLocalization.bundle),
                message: tool.unsupportedReason(capability: capability),
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
