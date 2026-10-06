import SwiftUI
import VPhoneDesignKit

// MARK: - Sidebar

/// The window's sidebar: Library (Machines, Firmwares, Disks) and System
/// (Bundles, Network, Host Setup), with the helper's state and the default
/// library in the footer. The rows are `DKLaunchpadSidebar`'s; they are
/// drawn here so the warning glyph is read out in the user's language.
struct VPhoneLaunchpadSidebar: View {
    @Environment(VPhoneLaunchpadModel.self) private var model

    var body: some View {
        DKSidebar(
            sections: sections,
            selection: Binding(get: { model.destination }, set: { model.show($0) }),
            // The window has no title bar; its buttons sit in the sidebar's
            // top band, above Library.
            windowControls: true,
            footer: { DKSidebarFooter(footer) },
        )
        .accessibilityLabel(Text("Launchpad"))
        // The Firmwares count, read again when a download may have finished.
        .task(id: VPhoneLaunchpadLibraryScanKey.key(model.machines)) { await countFirmwares() }
    }

    private var sections: [DKSidebarSection<DKLaunchpadDestination>] {
        let library = model.machines
        return VPhoneLaunchpadSidebarMeta.sections(
            listed: library.hasListed,
            running: library.runningCount,
            total: library.machines.count,
            firmwareCount: model.firmwareCount,
            bundleVersion: model.bundles.defaultVersion,
            hostWarning: model.hostNeedsAttention,
            bundleWarning: model.bundleNeedsAttention,
        )
    }

    /// Lists the IPSW cache without measuring any machine.
    private func countFirmwares() async {
        #if DEBUG
            if VPhoneLaunchpadPreview.isActive {
                model.firmwareCount = VPhoneLaunchpadPreview.libraryScan.completeIPSWs.count
                return
            }
        #endif
        let roots = model.machines.roots
        guard let scan = try? await VPhoneLaunchpadLibraryScanner.scan(libraryRoots: roots, machines: [], includeMachines: false) else {
            return
        }
        model.firmwareCount = scan.completeIPSWs.count
    }

    private var footer: [DKSidebarFooterLine] {
        let (status, tone) = helperStatus
        let library = VPhoneLaunchpadHostSetup.abbreviated(URL(fileURLWithPath: model.machines.libraryRoot, isDirectory: true))
        return [
            DKSidebarFooterLine(status, tone: tone),
            DKSidebarFooterLine(library, isMonospaced: true),
        ]
    }

    private var helperStatus: (String, DKTone) {
        switch model.helper.state {
        case .unknown:
            (String(localized: "Checking helper…"), .idle)
        case .notInstalled:
            (String(localized: "Helper not installed"), .warning)
        case .outdated:
            (String(localized: "Helper update available"), .warning)
        case let .ready(version):
            (String(localized: "Helper \(version) ready"), .success)
        case .unconfigured:
            (String(localized: "Helper not available in this build"), .danger)
        }
    }
}
