import SwiftUI
import VPhoneDesignKit

/// The Network page. Each machine's network mode, address and port forwards, and the addresses the Mac holds for guests.
///
/// Everything comes from what Launchpad already reads: `vm list --json` for
/// each machine's network config, `vm leases --json` for the addresses the
/// Mac's DHCP server holds, and vmnet's preferences, when readable, for the
/// shared NAT network. Releasing orphaned leases is the Host Setup action,
/// through the helper.
struct VPhoneLaunchpadNetworkView: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var filter = VPhoneLaunchpadNetworkFilter.all
    @State private var sharedNAT: VPhoneLaunchpadSharedNAT?
    @State private var confirmsRelease = false

    var body: some View {
        @Bindable var leases = model.leases
        VPhoneLaunchpadNetworkPage(
            rows: rows,
            filter: $filter,
            detail: detail,
            leases: showsLeases ? leaseSummary : nil,
            isLoading: !library.hasListed,
            onRelease: { confirmsRelease = true },
        )
        .navigationTitle("Network")
        .task {
            sharedNAT = await Self.readSharedNAT()
            await model.leases.refresh()
        }
        .confirmationDialog(
            String(localized: "Release \(model.leases.orphans.count) Addresses?"),
            isPresented: $confirmsRelease,
        ) {
            Button(String(localized: "Release")) {
                Task { await model.leases.releaseFromUI() }
            }
        } message: {
            Text(String(localized: "Their leases have run out and no machine in your libraries has their MAC. A guest that comes back with one of these MACs gets a new address."))
        }
        .errorAlert($leases.actionError, isEnabled: model.panel == nil)
    }

    private var library: VPhoneLaunchpadMachineLibrary {
        model.machines
    }

    @concurrent
    private static func readSharedNAT() async -> VPhoneLaunchpadSharedNAT? {
        VPhoneLaunchpadSharedNAT.current()
    }

    // MARK: - Rows

    private var rows: [VPhoneLaunchpadNetworkRow] {
        // A lease names the machine whose MAC it is for; match on both.
        var leased: [String: String] = [:]
        for lease in model.leases.leases {
            if let mac = lease.mac.flatMap(VPhoneLaunchpadLibraryFormat.normalizedMAC), let address = lease.address {
                leased[mac] = address
            }
        }
        return library.machines.map { machine in
            let network = machine.network
            let mode = VPhoneLaunchpadNetworkMode(config: network.mode)
            let mac = VPhoneLaunchpadLibraryFormat.normalizedMAC(network.macAddress)
            let address: VPhoneLaunchpadNetworkRow.Address = if mode == .none {
                .none
            } else if let fixed = network.ipv4 {
                .fixed(fixed.address)
            } else if mode == .nat, let address = mac.flatMap({ leased[$0] }) {
                .lease(address)
            } else {
                .dhcp
            }
            let modeLabel = mode == .bridged
                ? network.bridgeInterface.map { String(localized: "Bridged (\($0))") } ?? mode.title
                : mode.title
            return VPhoneLaunchpadNetworkRow(
                id: "\(machine.libraryRoot)/\(machine.name)",
                name: machine.name,
                state: library.stateTone(machine.path),
                mode: mode,
                modeLabel: modeLabel,
                address: address,
                mac: network.macAddress.isEmpty ? "—" : network.macAddress,
                mdnsName: network.localHostName.flatMap { $0.isEmpty ? nil : "\($0).local" },
                portForwards: (network.portForwards ?? []).map {
                    VPhoneLaunchpadLibraryFormat.portForward(
                        transport: $0.transport,
                        hostAddress: $0.hostAddress,
                        hostPort: $0.hostPort,
                        guestPort: $0.guestPort,
                    )
                },
            )
        }
    }

    // MARK: - Detail

    private var shownMode: VPhoneLaunchpadNetworkMode {
        switch filter {
        case .all: .nat
        case let .mode(mode): mode
        }
    }

    private var showsLeases: Bool {
        shownMode == .nat
    }

    private var detail: VPhoneLaunchpadNetworkDetail {
        switch shownMode {
        case .nat:
            var rows: [DKKeyValue] = []
            if let sharedNAT {
                rows.append(DKKeyValue(String(localized: "Subnet"), sharedNAT.subnet, monospaced: true))
                rows.append(DKKeyValue(String(localized: "Gateway and DNS"), sharedNAT.gateway, monospaced: true))
            }
            return VPhoneLaunchpadNetworkDetail(
                title: String(localized: "Shared NAT Network"),
                rows: rows,
                description: String(localized: "The default. Guests share one network on this Mac and leave through its physical interface, so they skip a VPN."),
            )
        case .tunnel:
            return VPhoneLaunchpadNetworkDetail(
                title: String(localized: "Tunnel"),
                rows: [],
                description: String(localized: "The guest’s network card lives inside vphone-vm, which opens ordinary connections on the Mac for it, so traffic follows the Mac’s VPN or proxy. Only forwarded ports reach the guest."),
            )
        case .bridged:
            let interfaces = Set(library.machines.compactMap { machine in
                machine.network.mode == "bridged" ? machine.network.bridgeInterface : nil
            }).sorted()
            return VPhoneLaunchpadNetworkDetail(
                title: String(localized: "Bridged"),
                rows: interfaces.isEmpty ? [] : [
                    DKKeyValue(interfaces.count == 1 ? String(localized: "Interface") : String(localized: "Interfaces"), interfaces.joined(separator: ", "), monospaced: true),
                    DKKeyValue(String(localized: "Address"), String(localized: "From that network’s DHCP")),
                ],
                description: String(localized: "The guest joins a physical network of the Mac with its own address, so other devices on that network can reach it. It needs no port forwards."),
            )
        case .hostOnly:
            return VPhoneLaunchpadNetworkDetail(
                title: String(localized: "Host Only"),
                rows: [],
                description: String(localized: "vphone-vm has no host-only network, so a machine set to it does not start. Choose NAT, Tunnel, Bridged or None in its settings."),
            )
        case .none:
            return VPhoneLaunchpadNetworkDetail(
                title: String(localized: "None"),
                rows: [],
                description: String(localized: "No network device. The guest stays offline; USB access and vphone.sock still work."),
            )
        }
    }

    // MARK: - Leases

    private var leaseSummary: VPhoneLaunchpadLeaseSummary {
        let leases = model.leases
        let count = leases.orphans.count
        let title: String
        var detail: String?
        if leases.isReleasing {
            title = String(localized: "Releasing…")
            detail = String(localized: "Waiting for administrator approval…")
        } else {
            switch leases.state {
            case .unknown, .checking:
                title = String(localized: "Checking…")
            case let .unavailable(reason):
                title = String(localized: "Not checked")
                detail = reason
            case let .failed(reason):
                title = String(localized: "Unable to list leases")
                detail = reason
            case .listed:
                title = count == 0 ? String(localized: "None") : count == 1 ? String(localized: "1 address") : String(localized: "\(count) addresses")
                if count > 0 {
                    detail = leases.orphans.compactMap(\.address).joined(separator: ", ")
                }
            }
        }
        return VPhoneLaunchpadLeaseSummary(
            title: title,
            detail: detail,
            detailIsAddresses: leases.state == .listed && !leases.isReleasing,
            canRelease: count > 0 && !leases.isReleasing && model.canReleaseLeases,
        )
    }
}
