import SwiftUI
import VPhoneDesignKit

// MARK: - Model

/// A machine's network mode as `vm config --network` spells it.
enum VPhoneLaunchpadNetworkMode: String, CaseIterable, Hashable {
    case nat, tunnel, bridged, hostOnly, none

    init(config: String) {
        self = Self(rawValue: config) ?? .none
    }

    var title: String {
        switch self {
        case .nat: String(localized: "NAT")
        case .tunnel: String(localized: "Tunnel")
        case .bridged: String(localized: "Bridged")
        case .hostOnly: String(localized: "Host Only")
        case .none: String(localized: "None")
        }
    }
}

/// The Network page's mode filter.
enum VPhoneLaunchpadNetworkFilter: Hashable {
    case all
    case mode(VPhoneLaunchpadNetworkMode)

    func admits(_ mode: VPhoneLaunchpadNetworkMode) -> Bool {
        switch self {
        case .all: true
        case let .mode(wanted): wanted == mode
        }
    }
}

/// One machine in the Network table.
struct VPhoneLaunchpadNetworkRow: Identifiable, Hashable {
    enum Address: Hashable {
        /// Set with `vm config --ip`.
        case fixed(String)
        /// What the Mac's DHCP server holds for the machine's MAC.
        case lease(String)
        /// DHCP, with no lease known.
        case dhcp
        /// No address in this mode.
        case none
    }

    var id: String
    var name: String
    var state: DKTone
    var mode: VPhoneLaunchpadNetworkMode
    var modeLabel: String
    var address: Address
    var mac: String
    var mdnsName: String?
    var portForwards: [String]
}

/// The facts and notes under the table for the mode shown.
struct VPhoneLaunchpadNetworkDetail: Hashable {
    var title: String
    var rows: [DKKeyValue]
    var description: String
}

/// The orphaned NAT leases, as the release action reports them.
struct VPhoneLaunchpadLeaseSummary: Hashable {
    enum State: Hashable {
        case checking
        case releasing
        case unavailable(String)
        case failed(String)
        /// The addresses no machine uses.
        case listed(Int)
    }

    var title: String
    /// Why the addresses are not known, or what the release waits for.
    var detail: String?
    var canRelease: Bool

    init(_ state: State, canRelease: Bool) {
        self.canRelease = canRelease
        switch state {
        case .checking:
            title = String(localized: "Checking…")
        case .releasing:
            title = String(localized: "Releasing…")
            detail = String(localized: "Waiting for administrator approval…")
        case let .unavailable(reason):
            title = String(localized: "Not checked")
            detail = reason
        case let .failed(reason):
            title = String(localized: "Unable to list leases")
            detail = reason
        case let .listed(count):
            title = count == 0 ? String(localized: "None") : count == 1 ? String(localized: "1 address") : String(localized: "\(count) addresses")
        }
    }
}

// MARK: - Page

/// The Network page as drawn from its rows (`Network.dc.html`).
struct VPhoneLaunchpadNetworkPage: View {
    let rows: [VPhoneLaunchpadNetworkRow]
    @Binding var filter: VPhoneLaunchpadNetworkFilter
    let detail: VPhoneLaunchpadNetworkDetail
    /// Shown with the NAT detail only.
    let leases: VPhoneLaunchpadLeaseSummary?
    var isLoading = false
    var onRelease: () -> Void = {}

    private static let columns = [
        DKTableColumn(String(localized: "Machine"), width: .flexible(min: 130, weight: 1)),
        DKTableColumn(String(localized: "Mode"), width: .fixed(96)),
        DKTableColumn(String(localized: "IPv4 Address"), width: .flexible(min: 130, weight: 1)),
        DKTableColumn(String(localized: "MAC Address"), width: .flexible(min: 140, weight: 1.1)),
        DKTableColumn(String(localized: "mDNS Name"), width: .flexible(min: 130, weight: 1.1)),
        DKTableColumn(String(localized: "Port Forwards"), width: .flexible(min: 150, weight: 1.5)),
    ]

    private var subtitle: String? {
        isLoading ? nil : Self.subtitle(machines: rows.count)
    }

    /// "4 machines · NAT, Tunnel, Bridged or None for each".
    static func subtitle(machines count: Int) -> String {
        let machines = count == 1 ? String(localized: "1 machine") : String(localized: "\(count) machines")
        return machines + " · " + String(localized: "NAT, Tunnel, Bridged or None for each")
    }

    var body: some View {
        VPhoneLaunchpadLibraryPage(String(localized: "Network"), subtitle: subtitle) {
            DKSegmented(String(localized: "Mode"), selection: $filter, options: filterOptions)
        } content: {
            machines
            DKSection(detail.title, footnote: detail.rows.isEmpty ? nil : detail.description) {
                if detail.rows.isEmpty {
                    VPhoneLaunchpadLibraryNote(text: detail.description)
                } else {
                    ForEach(detail.rows) { DKKeyValueRow($0) }
                }
            }
            if let leases {
                DKSection(String(localized: "Addresses Held by Old Guests"), items: [
                    DKListItem(
                        leases.title,
                        lines: [DKListItem.Line(String(localized: "The Mac keeps an address for every guest MAC it has seen. Release frees the ones no machine uses any more. It needs an administrator."))]
                            + (leases.detail.map { [DKListItem.Line($0)] } ?? []),
                        actions: [DKButtonSpec(String(localized: "Release…"), isEnabled: leases.canRelease, action: onRelease)],
                    ),
                ])
            }
        }
    }

    private var filterOptions: [DKSegmentOption<VPhoneLaunchpadNetworkFilter>] {
        var modes: [VPhoneLaunchpadNetworkMode] = [.nat, .tunnel, .bridged]
        // vphone-vm refuses host-only; show it only when a machine is set to it.
        if rows.contains(where: { $0.mode == .hostOnly }) {
            modes.append(.hostOnly)
        }
        modes.append(.none)
        return [DKSegmentOption(String(localized: "All"), value: .all, count: rows.count)]
            + modes.map { mode in
                DKSegmentOption(mode.title, value: .mode(mode), count: rows.count { $0.mode == mode })
            }
    }

    // MARK: Machines

    private var machines: some View {
        DKSection(
            String(localized: "Machines"),
            note: String(localized: "A change applies from the machine’s next start."),
        ) {
            if isLoading {
                VPhoneLaunchpadLibraryNote(text: String(localized: "Listing machines…"), isWorking: true)
            } else {
                DKDataTable(
                    String(localized: "Machines and their network"),
                    columns: Self.columns,
                    rows: rows.filter { filter.admits($0.mode) },
                    minWidth: 760,
                    scrollsVertically: false,
                    emptyText: rows.isEmpty ? String(localized: "No machines.") : String(localized: "No machine uses this mode."),
                ) { row, column in
                    cell(row, column)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ row: VPhoneLaunchpadNetworkRow, _ column: Int) -> some View {
        switch column {
        case 0:
            DKTableCellView(.title(row.name, leading: .dot(row.state)))
        case 1:
            DKTableCellView(.text(row.modeLabel))
        case 2:
            address(row.address)
        case 3:
            DKTableCellView(.mono(row.mac))
        case 4:
            DKTableCellView(row.mdnsName.map { .mono($0) } ?? .muted("—"))
        default:
            let forwards = row.portForwards.joined(separator: ", ")
            DKTableCellView(forwards.isEmpty ? .muted("—") : .mono(forwards))
                .help(forwards)
        }
    }

    @ViewBuilder
    private func address(_ address: VPhoneLaunchpadNetworkRow.Address) -> some View {
        switch address {
        case let .fixed(text):
            DKTableCellView(.mono(text))
                .help(String(localized: "Fixed address"))
        case let .lease(text):
            HStack(spacing: 6) {
                Text(text)
                    .font(DK.Typeface.mono)
                    .foregroundStyle(DK.Palette.ink)
                Text("DHCP")
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)
            }
            .lineLimit(1)
            .help(String(localized: "The address the Mac’s DHCP server holds for this MAC"))
            .accessibilityElement(children: .combine)
        case .dhcp:
            DKTableCellView(.muted(String(localized: "DHCP")))
        case .none:
            DKTableCellView(.muted("—"))
        }
    }
}
