import SwiftUI
import VPhoneDesignKit

/// The Firmwares page as drawn from its rows (`Images.dc.html`): the kind
/// filter, the downloaded IPSWs, and each machine's prepared restore files.
struct VPhoneLaunchpadFirmwaresPage: View {
    let rows: [VPhoneLaunchpadFirmwareRow]
    let restoreItems: [VPhoneLaunchpadRestoreFilesItem]
    /// True until the first scan answers.
    let isLoading: Bool
    @Binding var filter: VPhoneLaunchpadFirmwareFilter
    var onRemove: (VPhoneLaunchpadRestoreFilesItem) -> Void = { _ in }
    /// Deleting a downloaded IPSW, from its row's menu.
    var onDelete: (VPhoneLaunchpadFirmwareRow) -> Void = { _ in }

    private static let columns = [
        DKTableColumn(String(localized: "Image"), width: .flexible(min: 260, weight: 2.2)),
        DKTableColumn(String(localized: "Kind"), width: .flexible(min: 100, weight: 0.9)),
        DKTableColumn(String(localized: "Size"), width: .fixed(72), alignment: .trailing),
        DKTableColumn(String(localized: "Used by"), width: .flexible(min: 150, weight: 1.3)),
        DKTableColumn(String(localized: "Status"), width: .flexible(min: 130, weight: 1)),
    ]

    private var subtitle: String? {
        isLoading ? nil : Self.subtitle(rows)
    }

    /// "4 IPSWs · 38.1 GB": the finished downloads and what they take.
    static func subtitle(_ rows: [VPhoneLaunchpadFirmwareRow]) -> String {
        let complete = rows.filter { !$0.isDownloading }
        let count = complete.count
        let total = complete.reduce(Int64(0)) { $0 + $1.size }
        let files = count == 1 ? String(localized: "1 IPSW") : String(localized: "\(count) IPSWs")
        return count == 0 ? files : "\(files) · \(VPhoneLaunchpadLibraryFormat.size(total))"
    }

    var body: some View {
        VPhoneLaunchpadLibraryPage(String(localized: "Firmwares"), subtitle: subtitle, roomy: true) {
            DKSegmented(String(localized: "Kind"), selection: $filter, options: filterOptions)
        } content: {
            downloaded
            prepared
        }
    }

    private var filterOptions: [DKSegmentOption<VPhoneLaunchpadFirmwareFilter>] {
        let counts = VPhoneLaunchpadFirmwareRows.counts(rows)
        return [
            DKSegmentOption(String(localized: "All"), value: .all, count: counts[.all]),
            DKSegmentOption(String(localized: "iPhone"), value: .iPhone, count: counts[.iPhone]),
            DKSegmentOption(String(localized: "iPad"), value: .iPad, count: counts[.iPad]),
            DKSegmentOption(String(localized: "cloudOS"), value: .cloudOS, count: counts[.cloudOS]),
        ]
    }

    // MARK: Downloaded

    private var downloaded: some View {
        DKSection(
            String(localized: "Downloaded"),
            footnote: String(localized: "cloudOS 26.4 (23E5207q) is the newest cloudOS that contains vphone600ap. Later cloudOS releases list only the PCC boards, and fw prepare refuses them."),
        ) {
            if isLoading {
                VPhoneLaunchpadLibraryNote(text: String(localized: "Reading the IPSW cache…"), isWorking: true)
            } else {
                DKDataTable(
                    String(localized: "Downloaded images"),
                    columns: Self.columns,
                    rows: rows.filter { filter.admits($0.kind) },
                    roomy: true,
                    minWidth: 780,
                    scrollsVertically: false,
                    emptyText: rows.isEmpty
                        ? String(localized: "No IPSWs downloaded. New Machine downloads the ones it needs.")
                        : String(localized: "No images of this kind."),
                    contextMenu: { row in
                        [DKMenuItem(String(localized: "Delete…"), isDestructive: true) { onDelete(row) }]
                    },
                ) { row, column in
                    cell(row, column)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ row: VPhoneLaunchpadFirmwareRow, _ column: Int) -> some View {
        switch column {
        case 0:
            DKTableCellView(.title(row.title, subtitle: row.fileName, subtitleMonospaced: true, leading: .glyph(.image)))
                .help(row.fileName)
        case 1:
            DKTableCellView(.muted(row.kindLabel))
        case 2:
            DKTableCellView(.muted(VPhoneLaunchpadLibraryFormat.size(row.size)))
        case 3:
            let users = row.usedBy.joined(separator: ", ")
            DKTableCellView(.muted(users.isEmpty ? "—" : users))
                .help(users)
        default:
            if let status = row.status {
                DKTableCellView(row.isDownloading
                    ? .status(status.tone.designTone, status.text)
                    : .badge(status.tone.designTone, status.text))
            }
        }
    }

    // MARK: Prepared restore files

    private var prepared: some View {
        DKSection(
            String(localized: "Prepared Restore Files"),
            footnote: String(localized: "Extracted and patched per machine by fw prepare and fw patch. Launchpad removes them after the first boot unless “Keep prepared restore files” was on."),
        ) {
            if isLoading {
                VPhoneLaunchpadLibraryNote(text: String(localized: "Measuring machine folders…"), isWorking: true)
            } else if restoreItems.isEmpty {
                VPhoneLaunchpadLibraryNote(text: String(localized: "No machine keeps prepared restore files."))
            } else {
                ForEach(restoreItems) { item in
                    DKListRow(listItem(item))
                }
            }
        }
    }

    private func listItem(_ item: VPhoneLaunchpadRestoreFilesItem) -> DKListItem {
        var lines: [DKListItem.Line] = item.trees.map { DKListItem.Line($0, monospaced: true) }
        if let library = item.library {
            lines.append(DKListItem.Line(library, monospaced: true))
        }
        lines.append(DKListItem.Line(item.detail))
        return DKListItem(
            item.machine,
            lines: lines,
            value: VPhoneLaunchpadLibraryFormat.size(item.size),
            actions: [
                DKButtonSpec(
                    String(localized: "Remove…"),
                    variant: .danger,
                    isEnabled: item.blockedReason == nil,
                    help: item.blockedReason,
                    id: "remove",
                ) { onRemove(item) },
            ],
            id: item.id,
        )
    }
}

extension VPhoneLaunchpadFirmwareStatus.Tone {
    var designTone: DKTone {
        switch self {
        case .success: .success
        case .info: .info
        case .warning: .warning
        case .danger: .danger
        case .neutral: .neutral
        }
    }
}
