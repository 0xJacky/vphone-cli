import SwiftUI

// MARK: - Destinations

/// A page of the Launchpad window, in sidebar order.
public enum DKLaunchpadDestination: String, Sendable, CaseIterable, Hashable, Identifiable {
    case machines, firmwares, disks, bundles, network, hostSetup

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .machines: "Machines"
        case .firmwares: "Firmwares"
        case .disks: "Disks"
        case .bundles: "Bundles"
        case .network: "Network"
        case .hostSetup: "Host Setup"
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

    public var title: String {
        switch self {
        case .library: "Library"
        case .system: "System"
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
    ///   - bundleVersion: The default bundle's version, in monospace.
    ///   - hostSetupNeedsAttention: Shows the warning glyph on Host Setup.
    ///   - helperStatus: The footer's first line ("Helper 2.6.0 ready").
    ///   - helperTone: The dot before `helperStatus`.
    ///   - libraryPath: The footer's second line, in monospace ("~/VPhone").
    public init(
        selection: Binding<DKLaunchpadDestination>,
        runningMachines: Int? = nil,
        machineCount: Int? = nil,
        firmwareCount: Int? = nil,
        bundleVersion: String? = nil,
        hostSetupNeedsAttention: Bool = false,
        helperStatus: String? = nil,
        helperTone: DKTone = .success,
        libraryPath: String? = nil,
    ) {
        _selection = selection
        sections = Self.sections(
            runningMachines: runningMachines,
            machineCount: machineCount,
            firmwareCount: firmwareCount,
            bundleVersion: bundleVersion,
            hostSetupNeedsAttention: hostSetupNeedsAttention,
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
        bundleVersion: String? = nil,
        hostSetupNeedsAttention: Bool = false,
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
                    item.meta = bundleVersion
                    item.isMetaMonospaced = true
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
            bundleVersion: "2.6.0",
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
