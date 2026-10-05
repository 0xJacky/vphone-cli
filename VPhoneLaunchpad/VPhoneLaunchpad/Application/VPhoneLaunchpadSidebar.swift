import SwiftUI
import VPhoneDesignKit

// MARK: - Sidebar

/// The window's sidebar: Library (Machines, Firmwares, Disks) and System
/// (Bundles, Network, Host Setup), with the helper's state and the default
/// library in the footer. Built from the kit's rows rather than
/// `DKLaunchpadSidebar`, which has no warning for Bundles and English titles.
struct VPhoneLaunchpadSidebar: View {
    @Environment(VPhoneLaunchpadModel.self) private var model

    var body: some View {
        DKSidebar(
            sections: sections,
            selection: Binding(get: { model.destination }, set: { model.show($0) }),
            footer: { DKSidebarFooter(footer) },
        )
        .accessibilityLabel(Text("Launchpad"))
        // The Firmwares count, read again when a download may have finished.
        .task(id: VPhoneLaunchpadLibraryScanKey.key(model.machines)) { await countFirmwares() }
    }

    private var sections: [DKSidebarSection<DKLaunchpadDestination>] {
        DKLaunchpadSection.allCases.map { section in
            DKSidebarSection(section.localizedTitle, id: section.rawValue, items: section.destinations.map(item))
        }
    }

    private func item(_ destination: DKLaunchpadDestination) -> DKSidebarItem<DKLaunchpadDestination> {
        var item = DKSidebarItem(
            id: destination,
            label: destination.localizedTitle,
            glyph: destination.glyph,
            warningLabel: String(localized: "Needs attention"),
        )
        let meta: VPhoneLaunchpadSidebarMeta.Meta?
        switch destination {
        case .machines:
            let library = model.machines
            meta = VPhoneLaunchpadSidebarMeta.machines(
                listed: library.hasListed,
                running: library.runningCount,
                total: library.machines.count,
            )
        case .firmwares:
            meta = VPhoneLaunchpadSidebarMeta.firmwares(count: model.firmwareCount)
        case .bundles:
            meta = VPhoneLaunchpadSidebarMeta.bundles(defaultVersion: model.bundles.defaultVersion)
            item.isWarning = model.bundleNeedsAttention
        case .hostSetup:
            meta = nil
            item.isWarning = model.hostNeedsAttention
        case .disks, .network:
            meta = nil
        }
        if let meta {
            item.meta = meta.text
            item.metaTone = meta.tone
            item.isMetaMonospaced = meta.isMonospaced
        }
        return item
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
