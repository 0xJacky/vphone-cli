import SwiftUI

// MARK: - Destinations

/// A page of the Launchpad window, in sidebar order.
public enum DKLaunchpadDestination: String, Sendable, CaseIterable, Hashable, Identifiable {
    case machines, firmwares, disks, bundles, network, hostSetup

    public var id: Self {
        self
    }

    /// The page's name, from the host app's string catalog (see `title(bundle:)`).
    public var title: String {
        title(bundle: .main)
    }

    /// The page's name, looked up in `bundle`'s string catalog. DesignKit is a
    /// static library without resources of its own, so the keys live in the
    /// catalog of the app that links it; a missing key reads as the English name.
    public func title(bundle: Bundle) -> String {
        switch self {
        case .machines: String(localized: "Machines", bundle: bundle, comment: "Launchpad sidebar page")
        case .firmwares: String(localized: "Firmwares", bundle: bundle, comment: "Launchpad sidebar page")
        case .disks: String(localized: "Disks", bundle: bundle, comment: "Launchpad sidebar page")
        case .bundles: String(localized: "Bundles", bundle: bundle, comment: "Launchpad sidebar page")
        case .network: String(localized: "Network", bundle: bundle, comment: "Launchpad sidebar page")
        case .hostSetup: String(localized: "Host Setup", bundle: bundle, comment: "Launchpad sidebar page")
        }
    }

    public var glyph: DKGlyph {
        switch self {
        case .machines: .phone
        case .firmwares: .image
        case .disks: .disk
        case .bundles: .bundle
        case .network: .network
        case .hostSetup: .checklist
        }
    }

    public var section: DKLaunchpadSection {
        switch self {
        case .machines, .firmwares, .disks: .library
        case .bundles, .network, .hostSetup: .system
        }
    }
}

/// A group of Launchpad pages under one sidebar title, in sidebar order.
public enum DKLaunchpadSection: String, Sendable, CaseIterable, Hashable, Identifiable {
    case library, system

    public var id: Self {
        self
    }

    /// The section's title, from the host app's string catalog (see `title(bundle:)`).
    public var title: String {
        title(bundle: .main)
    }

    /// The section's title, looked up in `bundle`'s string catalog.
    public func title(bundle: Bundle) -> String {
        switch self {
        case .library: String(localized: "Library", bundle: bundle, comment: "Launchpad sidebar section")
        case .system: String(localized: "System", bundle: bundle, comment: "Launchpad sidebar section")
        }
    }

    /// The section's pages, in sidebar order.
    public var destinations: [DKLaunchpadDestination] {
        DKLaunchpadDestination.allCases.filter { $0.section == self }
    }
}

// MARK: - Sidebar

/// The Launchpad window's sidebar: Library (Machines, Firmwares, Disks) and
/// System (Bundles, Network, Host Setup), with the helper's state and the
/// library path in the footer.
public struct DKLaunchpadSidebar: View {
    @Binding var selection: DKLaunchpadDestination
    let sections: [DKSidebarSection<DKLaunchpadDestination>]
    let footerLines: [DKSidebarFooterLine]

    /// - Parameters:
    ///   - runningMachines: Running machines; with `machineCount`, Machines
    ///     shows "running/total" after a green dot (gray when none run).
    ///   - machineCount: Machines in the library. Alone, it shows as a count.
    ///   - firmwareCount: Firmwares in the library, shown as a count.
    ///   - hostSetupNeedsAttention: Shows the warning glyph on Host Setup.
    ///   - bundlesNeedAttention: Shows the warning glyph on Bundles, as when the
    ///     guest environment and the host programs come from different bundles.
    ///   - helperStatus: The footer's first line ("Helper 2.6.0 ready").
    ///   - helperTone: The dot before `helperStatus`.
    ///   - libraryPath: The footer's second line, in monospace ("~/VPhone").
    public init(
        selection: Binding<DKLaunchpadDestination>,
        runningMachines: Int? = nil,
        machineCount: Int? = nil,
        firmwareCount: Int? = nil,
        hostSetupNeedsAttention: Bool = false,
        bundlesNeedAttention: Bool = false,
        helperStatus: String? = nil,
        helperTone: DKTone = .success,
        libraryPath: String? = nil,
    ) {
        _selection = selection
        sections = Self.sections(
            runningMachines: runningMachines,
            machineCount: machineCount,
            firmwareCount: firmwareCount,
            hostSetupNeedsAttention: hostSetupNeedsAttention,
            bundlesNeedAttention: bundlesNeedAttention,
        )
        footerLines = Self.footerLines(helperStatus: helperStatus, helperTone: helperTone, libraryPath: libraryPath)
    }

    public var body: some View {
        if footerLines.isEmpty {
            DKSidebar(sections: sections, selection: $selection)
                .accessibilityLabel("Launchpad")
        } else {
            DKSidebar(sections: sections, selection: $selection, footer: {
                DKSidebarFooter(footerLines)
            })
            .accessibilityLabel("Launchpad")
        }
    }

    // MARK: Model

    /// The sidebar's sections for the given library state.
    public nonisolated static func sections(
        runningMachines: Int? = nil,
        machineCount: Int? = nil,
        firmwareCount: Int? = nil,
        hostSetupNeedsAttention: Bool = false,
        bundlesNeedAttention: Bool = false,
    ) -> [DKSidebarSection<DKLaunchpadDestination>] {
        DKLaunchpadSection.allCases.map { section in
            DKSidebarSection(section.title, items: section.destinations.map { destination in
                var item = DKSidebarItem(id: destination, label: destination.title, glyph: destination.glyph)
                switch destination {
                case .machines:
                    if let runningMachines, let machineCount {
                        item.meta = "\(runningMachines)/\(machineCount)"
                        item.metaTone = runningMachines > 0 ? .success : .idle
                    } else {
                        item.count = machineCount
                    }
                case .firmwares:
                    item.count = firmwareCount
                case .bundles:
                    // No version: a local build's name ("2.6.0-local.0d5e6f90")
                    // crowds out the row's label, and the Bundles page names it.
                    item.isWarning = bundlesNeedAttention
                case .hostSetup:
                    item.isWarning = hostSetupNeedsAttention
                case .disks, .network:
                    break
                }
                return item
            })
        }
    }

    nonisolated static func footerLines(helperStatus: String?, helperTone: DKTone, libraryPath: String?) -> [DKSidebarFooterLine] {
        var lines: [DKSidebarFooterLine] = []
        if let helperStatus {
            lines.append(DKSidebarFooterLine(helperStatus, tone: helperTone))
        }
        if let libraryPath {
            lines.append(DKSidebarFooterLine(libraryPath, isMonospaced: true))
        }
        return lines
    }
}

// MARK: - Previews

private struct DKLaunchpadSidebarPreview: View {
    @State private var selection: DKLaunchpadDestination = .machines

    var body: some View {
        DKLaunchpadSidebar(
            selection: $selection,
            runningMachines: 1,
            machineCount: 4,
            firmwareCount: 4,
            hostSetupNeedsAttention: true,
            helperStatus: "Helper 2.6.0 ready",
            libraryPath: "~/VPhone",
        )
        .frame(height: 640)
    }
}

#Preview("Launchpad sidebar, light") {
    DKLaunchpadSidebarPreview().preferredColorScheme(.light)
}

#Preview("Launchpad sidebar, dark") {
    DKLaunchpadSidebarPreview().preferredColorScheme(.dark)
}
