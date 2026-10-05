import SwiftUI
import VPhoneDesignKit

// MARK: - Model

/// One machine in the Disks table.
struct VPhoneLaunchpadDiskRow: Identifiable, Hashable {
    var id: String
    var name: String
    /// The library folder, shown when the machines span several.
    var library: String?
    var state: DKTone
    /// The disk image's logical size: what the guest sees.
    var diskSize: Int64?
    /// What the disk image takes on the volume.
    var diskAllocated: Int64?
    var restoreAllocated: Int64
    var totalAllocated: Int64
}

/// The usage card and the low-space banners.
struct VPhoneLaunchpadDiskSummary: Hashable {
    struct Volume: Hashable {
        var name: String
        var available: Int64?
        var isLow: Bool
    }

    var usedCaption: String
    var machineDisks: Int64
    var restoreFiles: Int64
    var otherMachineFiles: Int64
    var ipswCache: Int64
    var volumes: [Volume]
    /// Restore files that can go, by machine: "ios27-hooks (13.9 GB)".
    var removableRestoreFiles: [String]
    var ipswCount: Int

    var used: Int64 {
        machineDisks + restoreFiles + otherMachineFiles + ipswCache
    }

    /// Host Setup's advisory check asks for this much free space.
    static let recommendedFree: Int64 = 100_000_000_000
}

// MARK: - Page

/// The Disks page as drawn from its rows (`Disks.dc.html`).
struct VPhoneLaunchpadDisksPage: View {
    let subtitle: String?
    let summary: VPhoneLaunchpadDiskSummary?
    let rows: [VPhoneLaunchpadDiskRow]
    var onShowLibrary: (() -> Void)?
    /// Opens the Firmwares page, where restore files and IPSWs are removed.
    var onOpenFirmwares: (() -> Void)?

    private static let columns = [
        DKTableColumn(String(localized: "Machine"), width: .flexible(min: 150, weight: 1.4)),
        DKTableColumn(String(localized: "Disk size"), width: .fixed(90)),
        DKTableColumn(String(localized: "Disk image"), width: .flexible(min: 180, weight: 2)),
        DKTableColumn(String(localized: "Restore files"), width: .fixed(100)),
        DKTableColumn(String(localized: "Total"), width: .fixed(80), alignment: .trailing),
    ]

    var body: some View {
        VPhoneLaunchpadLibraryPage(String(localized: "Disks"), subtitle: subtitle) {
            if let onShowLibrary {
                DKButton(String(localized: "Show in Finder"), glyph: .folder, action: onShowLibrary)
            }
        } content: {
            if let summary {
                usage(summary)
                ForEach(summary.volumes.filter(\.isLow), id: \.self) { volume in
                    banner(volume, summary: summary)
                }
            } else {
                DKSection {
                    VPhoneLaunchpadLibraryNote(text: String(localized: "Measuring machine folders…"), isWorking: true)
                }
            }
            machines
            if let summary {
                shared(summary)
            }
        }
    }

    // MARK: Usage

    private func usage(_ summary: VPhoneLaunchpadDiskSummary) -> some View {
        DKCard(.padded) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: DK.Space.s6) {
                    VPhoneLaunchpadUsageFigure(caption: summary.usedCaption, value: VPhoneLaunchpadLibraryFormat.compactSize(summary.used))
                    Spacer(minLength: 0)
                    ForEach(summary.volumes, id: \.self) { volume in
                        VPhoneLaunchpadUsageFigure(
                            caption: String(localized: "Free on \(volume.name)"),
                            value: volume.available.map(VPhoneLaunchpadLibraryFormat.compactSize) ?? String(localized: "Unknown"),
                            alignment: .trailing,
                            tone: volume.isLow ? .warning : nil,
                        )
                    }
                }
                DKUsageBar([
                    Self.segment(String(localized: "Machine disks"), summary.machineDisks, DK.Palette.accent),
                    Self.segment(String(localized: "Restore files"), summary.restoreFiles, DK.Palette.accentSoft),
                    Self.segment(String(localized: "Other machine files"), summary.otherMachineFiles, DK.Palette.muted),
                    Self.segment(String(localized: "IPSW cache"), summary.ipswCache, DK.Palette.inkDisabled),
                ], label: summary.usedCaption)
            }
            .padding(6)
        }
    }

    /// A share of the usage bar, its size written as the rest of the page
    /// writes sizes: in decimal units, as the Finder does.
    private static func segment(_ label: String, _ bytes: Int64, _ color: Color) -> DKUsageSegment {
        DKUsageSegment(label, value: Double(max(bytes, 0)), valueText: VPhoneLaunchpadLibraryFormat.size(bytes), color: color)
    }

    private func banner(_ volume: VPhoneLaunchpadDiskSummary.Volume, summary: VPhoneLaunchpadDiskSummary) -> DKBanner {
        let text = Self.lowSpaceText(volume, summary: summary)
        guard let onOpenFirmwares else {
            return DKBanner(text)
        }
        return DKBanner(text, actionLabel: String(localized: "Open Firmwares"), action: onOpenFirmwares)
    }

    /// The low-space banner: how much is free, and what can go to make room.
    static func lowSpaceText(_ volume: VPhoneLaunchpadDiskSummary.Volume, summary: VPhoneLaunchpadDiskSummary) -> String {
        let free = volume.available.map(VPhoneLaunchpadLibraryFormat.compactSize) ?? "?"
        let fits = String(localized: "\(free) free on \(volume.name). A new machine’s 64 GB disk may not fit.")
        guard !summary.removableRestoreFiles.isEmpty else {
            return fits + " " + String(localized: "Unused IPSWs can be removed in Firmwares.")
        }
        let kept = summary.removableRestoreFiles.formatted(.list(type: .and))
        return fits + " " + String(localized: "Restore files kept for \(kept) and unused IPSWs can be removed in Firmwares.")
    }

    // MARK: Machines

    private var machines: some View {
        DKSection(
            String(localized: "Machines"),
            note: String(localized: "A disk image only takes the space the guest has written."),
        ) {
            DKDataTable(
                String(localized: "Machine disks"),
                columns: Self.columns,
                rows: rows,
                roomy: rows.contains { $0.library != nil },
                minWidth: 600,
                scrollsVertically: false,
                emptyText: String(localized: "No machines in the library folders."),
            ) { row, column in
                cell(row, column)
            }
        }
    }

    @ViewBuilder
    private func cell(_ row: VPhoneLaunchpadDiskRow, _ column: Int) -> some View {
        switch column {
        case 0:
            DKTableCellView(.title(row.name, subtitle: row.library, subtitleMonospaced: true, leading: .dot(row.state)))
        case 1:
            DKTableCellView(.muted(row.diskSize.map(VPhoneLaunchpadLibraryFormat.diskSize) ?? "—"))
        case 2:
            if let allocated = row.diskAllocated {
                let fraction = row.diskSize.map { $0 > 0 ? Double(allocated) / Double($0) : 0 } ?? 0
                DKTableCellView(.bar(fraction, value: VPhoneLaunchpadLibraryFormat.compactSize(allocated)))
                    .help(String(localized: "\(VPhoneLaunchpadLibraryFormat.size(allocated)) written of \(VPhoneLaunchpadLibraryFormat.size(row.diskSize ?? 0))"))
            } else {
                DKTableCellView(.muted(String(localized: "No disk image")))
            }
        case 3:
            DKTableCellView(.muted(row.restoreAllocated > 0 ? VPhoneLaunchpadLibraryFormat.size(row.restoreAllocated) : "—"))
        default:
            DKTableCellView(.strong(VPhoneLaunchpadLibraryFormat.size(row.totalAllocated)))
        }
    }

    // MARK: Shared

    private func shared(_ summary: VPhoneLaunchpadDiskSummary) -> some View {
        var actions: [DKButtonSpec] = []
        if let onOpenFirmwares {
            actions.append(DKButtonSpec(String(localized: "Manage in Firmwares"), action: onOpenFirmwares))
        }
        return DKSection(String(localized: "Shared by All Machines"), items: [
            DKListItem(
                String(localized: "IPSW cache"),
                lines: [DKListItem.Line(Self.cacheLine(ipswCount: summary.ipswCount))],
                value: VPhoneLaunchpadLibraryFormat.size(summary.ipswCache),
                actions: actions,
            ),
        ])
    }

    /// "4 downloaded images. A second machine from the same image downloads nothing."
    static func cacheLine(ipswCount: Int) -> String {
        let count = ipswCount == 1
            ? String(localized: "1 downloaded image.")
            : String(localized: "\(ipswCount) downloaded images.")
        return count + " " + String(localized: "A second machine from the same image downloads nothing.")
    }
}
