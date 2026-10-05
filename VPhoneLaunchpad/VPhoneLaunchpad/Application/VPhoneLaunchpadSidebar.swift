import SwiftUI
import VPhoneDesignKit

// MARK: - Pages

extension DKLaunchpadDestination {
    /// The page's name in the sidebar, the View menu and the window title.
    /// The kit's own `title` is not localized.
    var localizedTitle: String {
        switch self {
        case .machines: String(localized: "Machines")
        case .firmwares: String(localized: "Firmwares")
        case .disks: String(localized: "Disks")
        case .bundles: String(localized: "Bundles")
        case .network: String(localized: "Network")
        case .hostSetup: String(localized: "Host Setup")
        }
    }

    /// ⌘1 to ⌘6, in sidebar order.
    var shortcut: DKShortcut {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return DKShortcut(Character("\(index + 1)"), .command)
    }
}

extension DKLaunchpadSection {
    var localizedTitle: String {
        switch self {
        case .library: String(localized: "Library")
        case .system: String(localized: "System")
        }
    }
}

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
        switch destination {
        case .machines:
            let library = model.machines
            // Nothing until `vm list` answers, so it does not read 0/0 first.
            if library.hasListed {
                let running = library.runningCount
                item.meta = "\(running)/\(library.machines.count)"
                item.metaTone = running > 0 ? .success : .idle
            }
        case .bundles:
            item.meta = model.bundles.defaultVersion
            item.isMetaMonospaced = true
            item.isWarning = model.bundleNeedsAttention
        case .hostSetup:
            item.isWarning = model.hostNeedsAttention
        case .firmwares, .disks, .network:
            break
        }
        return item
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
