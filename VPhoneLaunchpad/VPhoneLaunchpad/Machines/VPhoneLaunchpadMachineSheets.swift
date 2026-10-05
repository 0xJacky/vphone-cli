import AppKit
import SwiftUI
import VPhoneDesignKit

// MARK: - Settings

/// Hardware, network and startup for one machine, or for several at once. The
/// fields start from the first machine; only the ones edited are written, to
/// every machine, so values the machines do not share are left alone. A fixed
/// address, a MAC and forwarded ports belong to one machine, so they are only
/// offered when one is selected, on pages of their own.
struct VPhoneLaunchpadMachineSettingsView: View {
    private enum Field {
        case cpu, memory, network, address, mac, forwards, mdns, macName, unlock
    }

    enum Page: Hashable {
        case general, network, forwards
    }

    let machines: [VPhoneLaunchpadMachine]
    @Environment(VPhoneLaunchpadModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var page = Page.general
    @State private var cpu: Int
    @State private var memoryMB: Int
    @State private var network: String
    @State private var bridgeInterface: String
    @State private var manualAddress: Bool
    @State private var address: String
    @State private var gateway: String
    @State private var dns: String
    @State private var macAddress: String
    @State private var forwards: [String]
    @State private var advertisesName: Bool
    @State private var resolvesMacName: Bool
    @State private var unlocksAtStartup: Bool
    @State private var newTransport = "tcp"
    @State private var newHostPort = ""
    @State private var newGuestPort = ""
    @State private var newOnAllAddresses = false
    @State private var edited: Set<Field> = []

    init(machines: [VPhoneLaunchpadMachine]) {
        self.machines = machines
        let first = machines.first
        _cpu = State(initialValue: first?.cpuCount ?? 8)
        _memoryMB = State(initialValue: first?.memoryMB ?? 8192)
        _network = State(initialValue: first.map { $0.network.mode == "hostOnly" ? "none" : $0.network.mode } ?? "nat")
        _bridgeInterface = State(initialValue: first?.network.bridgeInterface ?? "")
        let ipv4 = first?.network.ipv4
        _manualAddress = State(initialValue: ipv4 != nil)
        _address = State(initialValue: ipv4.map { "\($0.address)/\($0.prefixLength)" } ?? "")
        _gateway = State(initialValue: ipv4?.router ?? "")
        _dns = State(initialValue: ipv4?.dns?.joined(separator: ", ") ?? "")
        _macAddress = State(initialValue: first?.network.macAddress ?? "")
        _forwards = State(initialValue: first?.network.portForwards?.map(\.argument) ?? [])
        _advertisesName = State(initialValue: first?.network.localHostName != nil)
        _resolvesMacName = State(initialValue: first?.network.resolvesMacName != false)
        _unlocksAtStartup = State(initialValue: first?.unlocksAtStartup == true)
    }

    private var title: String {
        machines.count == 1 ? String(localized: "\(machines[0].name) Settings") : String(localized: "Settings for \(machines.count) Machines")
    }

    private var single: Bool {
        machines.count == 1
    }

    private var forwardsSupported: Bool {
        network == "nat" || network == "tunnel"
    }

    /// The mDNS name the machine has, or the one `--mdns on` would give it.
    private var localHostName: String {
        machines.first?.network.localHostName ?? VPhoneLaunchpadMachineFormat.localHostName(for: machines.first?.name ?? "")
    }

    /// Bridged and none have no port forwarding; switching to them drops it.
    private var dropsForwards: Bool {
        single && !forwardsSupported && !forwards.isEmpty
    }

    private var newForward: String? {
        VPhoneLaunchpadMachineFormat.forwardArgument(
            transport: newTransport,
            hostPort: newHostPort,
            guestPort: newGuestPort,
            onAllAddresses: newOnAllAddresses,
        )
    }

    private var canSave: Bool {
        !edited.isEmpty && !(manualAddress && address.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        // Several machines share only hardware, the network mode and startup,
        // which fit on one page.
        DKSheet(
            title,
            width: 640,
            note: DKSheetNote(single
                ? String(localized: "Applies the next time \(machines[0].name) starts.")
                : String(localized: "Only the settings you change are applied to each machine.")),
            trailing: [
                .cancel(String(localized: "Cancel")) { dismiss() },
                .primary(String(localized: "Save"), isEnabled: canSave) { save() },
            ],
        ) {
            if !single || page == .general {
                hardwareSection
            }
            if !single || page == .network {
                networkSection
                if single {
                    addressSection
                }
            }
            if single, page == .forwards {
                forwardsSection
            }
            if !single || page == .general {
                startupSection
            }
        } pages: {
            if single {
                DKSegmented(String(localized: "Page"), selection: $page, options: [
                    DKSegmentOption(String(localized: "General"), value: Page.general),
                    DKSegmentOption(String(localized: "Network"), value: Page.network),
                    DKSegmentOption(String(localized: "Port Forwarding"), value: Page.forwards),
                ])
            }
        }
        .vphoneLaunchpadSheetChrome()
        .onChange(of: cpu) { edited.insert(.cpu) }
        .onChange(of: memoryMB) { edited.insert(.memory) }
        .onChange(of: network) { edited.insert(.network) }
        .onChange(of: bridgeInterface) { edited.insert(.network) }
        .onChange(of: manualAddress) { edited.insert(.address) }
        .onChange(of: address) { edited.insert(.address) }
        .onChange(of: gateway) { edited.insert(.address) }
        .onChange(of: dns) { edited.insert(.address) }
        .onChange(of: macAddress) { edited.insert(.mac) }
        .onChange(of: forwards) { edited.insert(.forwards) }
        .onChange(of: advertisesName) { edited.insert(.mdns) }
        .onChange(of: resolvesMacName) { edited.insert(.macName) }
        .onChange(of: unlocksAtStartup) { edited.insert(.unlock) }
        #if DEBUG
        .onAppear {
            if VPhoneLaunchpadPreview.isActive {
                page = VPhoneLaunchpadPreview.machineSettingsPage
            }
        }
        #endif
    }

    private var hardwareSection: some View {
        DKSection(String(localized: "Hardware")) {
            VPhoneLaunchpadStepperRow(
                label: String(localized: "CPU"),
                value: String(localized: "\(cpu) cores"),
                number: $cpu,
                range: 1 ... ProcessInfo.processInfo.activeProcessorCount,
            )
            VPhoneLaunchpadStepperRow(label: String(localized: "Memory"), value: "\(memoryMB) MB", number: $memoryMB, range: 2048 ... 65536, step: 1024)
        }
    }

    private var startupSection: some View {
        DKSection(
            String(localized: "Startup"),
            footnote: String(localized: "Each time the guest starts, its screen is turned on and the Lock Screen dismissed."),
        ) {
            VPhoneLaunchpadSwitchRow(isOn: $unlocksAtStartup) {
                Text("Unlock at startup")
            }
        }
    }

    private var networkSection: some View {
        DKSection(String(localized: "Network")) {
            DKFormRow(String(localized: "Mode"), fill: true) {
                Picker("Mode", selection: $network) {
                    Text("NAT").tag("nat")
                    Text("Bridged").tag("bridged")
                    Text("Tunnel").tag("tunnel")
                    Text("None").tag("none")
                }
                .dkFieldPicker(fill: true)
            }
            if network == "bridged" {
                DKFormRow(String(localized: "Interface"), fill: true) {
                    TextField("Interface", text: $bridgeInterface, prompt: Text("First available"))
                        .textFieldStyle(.dkFieldMono)
                }
            }
            if network == "tunnel" {
                VPhoneLaunchpadCardMessage(text: Text("Traffic leaves through this Mac's own connections, so it follows the Mac's VPN."))
            }
            if dropsForwards {
                VPhoneLaunchpadCardMessage(text: Text("This mode cannot forward ports, so saving removes the port forwards."), isWarning: true)
            }
        }
    }

    private var addressSection: some View {
        VPhoneLaunchpadSheetSection(String(localized: "Address")) {
            if network != "none" {
                DKFormRow(String(localized: "Configure IPv4"), fill: true) {
                    Picker("Configure IPv4", selection: $manualAddress) {
                        Text("Using DHCP").tag(false)
                        Text("Manually").tag(true)
                    }
                    .dkFieldPicker(fill: true)
                }
                if manualAddress {
                    DKFormRow(String(localized: "Address"), fill: true) {
                        TextField("Address", text: $address, prompt: Text(verbatim: network == "tunnel" ? "192.168.127.3/24" : "192.168.64.50/24"))
                            .textFieldStyle(.dkFieldMono)
                    }
                    DKFormRow(String(localized: "Gateway"), fill: true) {
                        TextField("Gateway", text: $gateway, prompt: Text("Automatic"))
                            .textFieldStyle(.dkFieldMono)
                    }
                    DKFormRow(String(localized: "DNS Servers"), fill: true) {
                        TextField("DNS Servers", text: $dns, prompt: Text("Automatic"))
                            .textFieldStyle(.dkFieldMono)
                    }
                }
                DKFormRow(String(localized: "MAC Address"), fill: true) {
                    TextField("MAC Address", text: $macAddress, prompt: Text("Generated at next start"))
                        .textFieldStyle(.dkFieldMono)
                    DKButton(String(localized: "Generate"), size: .small) { macAddress = VPhoneLaunchpadMachineFormat.randomMACAddress() }
                }
                VPhoneLaunchpadSwitchRow(isOn: $resolvesMacName) {
                    Text("Resolve this Mac's name in the guest")
                }
            }
            // The guest also announces over its USB link to the Mac, so this
            // works without a network device too.
            VPhoneLaunchpadSwitchRow(isOn: $advertisesName) {
                Text("Reachable as \(localHostName).local")
            }
        } footnote: {
            switch network {
            case "none":
                EmptyView()
            case "nat":
                Text("Use an address on the Mac's shared NAT network, usually 192.168.64.0/24. For another subnet, use Tunnel.")
            case "tunnel":
                Text("The tunnel hands this address to the guest itself.")
            default:
                Text("vphoned sets this address in the guest. Use your network's gateway and DNS servers.")
            }
        }
    }

    /// The page stays when the mode cannot forward, so the segments do not
    /// change under the pointer; it says why it is empty instead.
    @ViewBuilder
    private var forwardsSection: some View {
        if forwardsSupported {
            forwardsList
        } else {
            DKSection(String(localized: "Port Forwarding")) {
                VPhoneLaunchpadCardMessage(text: Text(dropsForwards
                        ? "This mode cannot forward ports, so saving removes the port forwards."
                        : "Port forwarding needs NAT or Tunnel. Change the mode in Network."))
            }
        }
    }

    @ViewBuilder
    private var forwardsList: some View {
        if !forwards.isEmpty {
            DKSection(String(localized: "Port Forwarding")) {
                ForEach(forwards, id: \.self) { forward in
                    VPhoneLaunchpadCardRow {
                        Text(verbatim: VPhoneLaunchpadMachineFormat.forwardLabel(forward))
                            .font(DK.Typeface.mono)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: Self.forwardScope(forward))
                            .font(DK.Typeface.caption)
                            .foregroundStyle(DK.Palette.muted)
                        DKButton(String(localized: "Remove"), size: .small) {
                            forwards.removeAll { $0 == forward }
                        }
                    }
                }
            }
        }
        DKSection(
            forwards.isEmpty ? String(localized: "Port Forwarding") : String(localized: "Add a Forward"),
            footnote: String(localized: "A forwarded port listens on this Mac only, unless it is reachable from other devices."),
        ) {
            DKFormRow(String(localized: "Protocol"), fill: true) {
                Picker("Protocol", selection: $newTransport) {
                    Text(verbatim: "TCP").tag("tcp")
                    Text(verbatim: "UDP").tag("udp")
                }
                .dkFieldPicker(fill: true)
            }
            DKFormRow(String(localized: "Mac Port"), fill: true) {
                TextField("Mac Port", text: $newHostPort)
                    .textFieldStyle(.dkFieldMono)
            }
            DKFormRow(String(localized: "Guest Port"), fill: true) {
                TextField("Guest Port", text: $newGuestPort)
                    .textFieldStyle(.dkFieldMono)
            }
            VPhoneLaunchpadSwitchRow(isOn: $newOnAllAddresses) {
                Text("Reachable from other devices")
            }
            VPhoneLaunchpadCardRow {
                Spacer(minLength: 0)
                DKButton(DKButtonSpec(String(localized: "Add"), glyph: .plus, size: .small, isEnabled: newForward != nil) {
                    if let newForward, !forwards.contains(newForward) {
                        forwards.append(newForward)
                        newHostPort = ""
                        newGuestPort = ""
                    }
                })
            }
        }
    }

    /// Who reaches a forward: this Mac only, other devices too, or the
    /// address it was set to listen on.
    private static func forwardScope(_ forward: String) -> String {
        switch VPhoneLaunchpadMachineFormat.forwardHost(forward) {
        case "127.0.0.1": String(localized: "This Mac only")
        case "0.0.0.0": String(localized: "Other devices too")
        case let host?: host
        case nil: ""
        }
    }

    private func save() {
        let cpu = edited.contains(.cpu) ? cpu : nil
        let memoryMB = edited.contains(.memory) ? memoryMB : nil
        let network = edited.contains(.network) ? network : nil
        let bridgeInterface = network == "bridged" ? bridgeInterface : nil
        let unlocksAtStartup = edited.contains(.unlock) ? unlocksAtStartup : nil
        var networkArguments: [String] = []
        if single {
            if edited.contains(.address) {
                if manualAddress {
                    let trimmedGateway = gateway.trimmingCharacters(in: .whitespaces)
                    let trimmedDNS = dns.replacingOccurrences(of: " ", with: "")
                    networkArguments += [
                        "--ip", address.trimmingCharacters(in: .whitespaces),
                        "--gateway", trimmedGateway.isEmpty ? "auto" : trimmedGateway,
                        "--dns", trimmedDNS.isEmpty ? "auto" : trimmedDNS,
                    ]
                } else {
                    networkArguments += ["--ip", "dhcp"]
                }
            }
            if edited.contains(.macName) {
                networkArguments += ["--mac-name", resolvesMacName ? "on" : "off"]
            }
            if edited.contains(.mdns) {
                networkArguments += ["--mdns", advertisesName ? "on" : "off"]
            }
            if edited.contains(.mac) {
                let trimmed = macAddress.trimmingCharacters(in: .whitespaces)
                networkArguments += ["--mac", trimmed.isEmpty ? "auto" : trimmed]
            }
            if dropsForwards {
                networkArguments += ["--clear-forwards"]
            } else if edited.contains(.forwards) {
                networkArguments += ["--clear-forwards"] + forwards.flatMap { ["--forward", $0] }
            }
        }
        let paths = machines.map(\.path)
        let library = model.machines
        Task {
            for path in paths {
                await library.configure(
                    path,
                    cpu: cpu,
                    memoryMB: memoryMB,
                    network: network,
                    bridgeInterface: bridgeInterface,
                    networkArguments: networkArguments,
                    unlocksAtStartup: unlocksAtStartup,
                )
            }
        }
        dismiss()
    }
}

// MARK: - Rename and clone

struct VPhoneLaunchpadNameSheet: View {
    let title: String.LocalizationValue
    let action: String.LocalizationValue
    let initial: String
    /// The machine renamed or cloned. The new name stays in its library.
    let machine: VPhoneLaunchpadMachinePath
    @ViewBuilder let options: Options
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    init(
        title: LocalizedStringKey,
        action: LocalizedStringKey,
        initial: String,
        machine: VPhoneLaunchpadMachinePath,
        @ViewBuilder options: () -> Options,
        onConfirm: @escaping (String) -> Void,
    ) {
        self.title = title
        self.action = action
        self.initial = initial
        self.machine = machine
        self.options = options()
        self.onConfirm = onConfirm
    }

    private var fitsLocation: Bool {
        VPhoneLaunchpadMachineLocations.socketPathFits(root: machine.libraryRoot, name: name)
    }

    private var isValid: Bool {
        VPhoneLaunchpadNames.isValidMachineName(name) && name != machine.name && fitsLocation
    }

    var body: some View {
        DKSheet(
            String(localized: title),
            width: 440,
            trailing: [
                .cancel(String(localized: "Cancel")) { dismiss() },
                .primary(String(localized: action), isEnabled: isValid) {
                    onConfirm(name)
                    dismiss()
                },
            ],
        ) {
            VStack(alignment: .leading, spacing: DK.Space.s2) {
                DKCard {
                    DKFormRow(String(localized: "Name"), fill: true, labelWidth: 60) {
                        TextField("Name", text: $name)
                            .textFieldStyle(.dkField)
                    }
                }
                if fitsLocation {
                    Text("Use letters, numbers, periods, hyphens, and underscores.")
                        .font(DK.Typeface.caption)
                        .foregroundStyle(DK.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DK.Space.s1)
                } else {
                    VPhoneLaunchpadFieldProblem(text: String(localized: "The path is too long. Use a shorter name, or a location with a shorter path."))
                }
            }
        }
        .vphoneLaunchpadSheetChrome()
        .onAppear { name = initial }
    }
}

extension VPhoneLaunchpadNameSheet where Options == EmptyView {
    init(
        title: LocalizedStringKey,
        action: LocalizedStringKey,
        initial: String,
        machine: VPhoneLaunchpadMachinePath,
        onConfirm: @escaping (String) -> Void,
    ) {
        self.init(title: title, action: action, initial: initial, machine: machine, options: { EmptyView() }, onConfirm: onConfirm)
    }
}

/// Clone, with the choice of a device of its own. A new identity is the
/// default: a clone that keeps the original's ECID, UDID and MAC cannot run
/// at the same time as it, and the host sees them as one device.
struct VPhoneLaunchpadCloneSheet: View {
    let machine: VPhoneLaunchpadMachinePath
    let onConfirm: (_ name: String, _ newIdentity: Bool) -> Void
    @State private var newIdentity = true

    var body: some View {
        VPhoneLaunchpadNameSheet(
            title: "Clone \(machine.name)",
            action: "Clone",
            initial: "\(machine.name)-clone",
            machine: machine,
        ) {
            Section {
                Toggle("New device identity", isOn: $newIdentity)
            } footer: {
                Text(newIdentity
                    ? "The clone gets its own ECID, UDID and MAC address, so it can run alongside the original. The guest asks to trust this Mac again the first time it connects."
                    : "The clone is the same device as the original. Run only one of them at a time.")
                    .foregroundStyle(.secondary)
            }
        } onConfirm: { name in
            onConfirm(name, newIdentity)
        }
    }
}

// MARK: - Export

/// One machine offers the archive options. Several are written with the
/// defaults, one `<name>.tzst` each, into a folder chosen once.
struct VPhoneLaunchpadExportView: View {
    let machines: [VPhoneLaunchpadMachinePath]
    @Environment(VPhoneLaunchpadModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var densest = false
    @State private var includeIPSW = false

    private var title: String {
        machines.count == 1 ? String(localized: "Export \(machines[0].name)") : String(localized: "Export \(machines.count) Machines")
    }

    var body: some View {
        DKSheet(
            title,
            width: 440,
            trailing: [
                .cancel(String(localized: "Cancel")) { dismiss() },
                .primary(String(localized: "Choose Location…")) { choose() },
            ],
        ) {
            if machines.count == 1 {
                DKSection(footnote: densest
                    ? String(localized: "Creates a smaller .txz archive. Export takes much longer.")
                    : String(localized: "Creates a .tzst archive."))
                {
                    VPhoneLaunchpadSwitchRow(isOn: $densest) {
                        Text("Maximum compression")
                    }
                    VPhoneLaunchpadSwitchRow(isOn: $includeIPSW) {
                        Text("Include the restore IPSW directory")
                    }
                }
            } else {
                DKSection(footnote: String(localized: "Creates a .tzst archive for each machine in the folder you choose.")) {
                    ForEach(machines, id: \.self) { machine in
                        VPhoneLaunchpadCardRow {
                            Text(verbatim: "\(machine.name).tzst")
                                .font(DK.Typeface.mono)
                        }
                    }
                }
            }
        }
        .vphoneLaunchpadSheetChrome()
    }

    private func choose() {
        let library = model.machines
        if machines.count == 1 {
            let machine = machines[0]
            let panel = NSSavePanel()
            panel.title = String(localized: "Export \(machine.name)")
            panel.nameFieldStringValue = "\(machine.name).\(densest ? "txz" : "tzst")"
            let densest = densest
            let includeIPSW = includeIPSW
            panel.present { url in
                Task { await library.export([(machine, url)], densest: densest, includeIPSW: includeIPSW) }
                dismiss()
            }
            return
        }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Export \(machines.count) Machines")
        panel.prompt = String(localized: "Export")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        let machines = machines
        panel.present { folder in
            let items = machines.map { ($0, folder.appendingPathComponent("\($0.name).tzst")) }
            Task { await library.export(items, densest: false, includeIPSW: false) }
            dismiss()
        }
    }
}
