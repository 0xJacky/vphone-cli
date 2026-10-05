import AppKit
import SwiftUI
import VPhoneDesignKit

// MARK: - Inspector

/// The trailing inspector for the selected machine: a header with the
/// machine's state and its run actions, then its Core Bundle layers,
/// patches, firmware, hardware, network, identity and console. Long values
/// truncate in the middle, since the column is narrow.
struct VPhoneLaunchpadMachineInspector: View {
    let machine: VPhoneLaunchpadMachine
    let onShowProgress: (VPhoneLaunchpadMachinePath) -> Void
    let onOpenConsole: (VPhoneLaunchpadMachinePath) -> Void
    /// Opens one of the Machines page's sheets from the more menu.
    var onPresent: (VPhoneLaunchpadMachinesView.Sheet) -> Void = { _ in }
    /// Asks the page to confirm deleting the machine.
    var onDelete: ([VPhoneLaunchpadMachinePath]) -> Void = { _ in }
    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var showsCommands = false
    @State private var patchCatalog: VPhoneLaunchpadPatchCatalog?
    @State private var patchCatalogError: String?
    /// The machine the catalogue above was read for, so another machine's
    /// patches never show while its own are read.
    @State private var patchCatalogMachine: VPhoneLaunchpadMachinePath?
    /// The choice the patch editor opens with, set when it is shown.
    @State private var editedPatches: VPhoneLaunchpadPatchSelection?
    /// Bumped after a save or an update, so the patches are read again.
    @State private var patchRevision = 0

    private var library: VPhoneLaunchpadMachineLibrary {
        model.machines
    }

    private var actions: VPhoneLaunchpadMachineActions {
        VPhoneLaunchpadMachineActions(model: model, present: onPresent, delete: onDelete)
    }

    private var isStopped: Bool {
        library.state(of: machine.path) == .stopped
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: DK.Space.s4) {
                    if let creation = library.creations[machine.path] {
                        creationSummary(creation)
                    }
                    mixedBanner
                    coreBundleSection
                    patchesSection
                    firmwareSection
                    hardwareSection
                    networkSection
                    identitySection
                    consoleSection
                }
                .padding(.horizontal, DK.Space.s5)
                .padding(.top, DK.Space.s4)
                .padding(.bottom, DK.Space.s6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DK.Palette.window)
        .task(id: patchReadKey) {
            await loadPatches()
        }
        .sheet(isPresented: $showsCommands) {
            VPhoneLaunchpadCommandHistoryView()
                .environment(model)
        }
        .sheet(item: $editedPatches) { initial in
            let path = machine.path
            VPhoneLaunchpadPatchSettingsView(
                initial: initial,
                bundleVersion: library.bundleVersion(for: path),
                machine: path,
            ) { selection in
                Task {
                    await library.setPatches(selection, for: path)
                    patchRevision += 1
                }
            }
            .environment(model)
        }
    }

    static var mixedHelp: String {
        String(localized: "The host programs and the guest environment come from different Core Bundles. Update the guest environment to match.")
    }

    // MARK: - Header

    /// The device glyph, name, device and OS, the state chip, and Start or
    /// Stop with the console and the more menu.
    private var header: some View {
        let status = VPhoneLaunchpadMachineStatus(machine.path, library: library)
        let identity = HStack(alignment: .top, spacing: 14) {
            DKIcon(machine.glyph, size: 26)
                .foregroundStyle(DK.Palette.inkSecondary)
                .frame(width: 48, height: 48)
                .background(DK.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DK.Radius.window, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DK.Radius.window, style: .continuous).strokeBorder(DK.Palette.line, lineWidth: DK.Metric.hairline))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: machine.name)
                    .font(DK.Typeface.sheetTitle)
                    .foregroundStyle(DK.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: subtitle)
                    .font(DK.Typeface.body)
                    .foregroundStyle(DK.Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(subtitle)
                DKBadge(status.text, tone: status.tone)
                    .help(status.text)
                    .padding(.top, 6)
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DK.Space.s3) {
                identity
                Spacer(minLength: 0)
                headerActions
            }
            VStack(alignment: .leading, spacing: DK.Space.s3) {
                identity
                headerActions
            }
        }
        .padding(.horizontal, DK.Space.s5)
        .padding(.top, DK.Space.s5)
        .padding(.bottom, DK.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DK.Palette.divider).frame(height: DK.Metric.hairline)
        }
    }

    /// "iPhone17,3 · iOS 26.6.2 (23G90)"; a machine not yet restored has
    /// neither.
    private var subtitle: String {
        let parts = [machine.restoreInfo?.device, machine.osDescription].compactMap(\.self)
        return parts.isEmpty ? String(localized: "Not restored") : parts.joined(separator: " · ")
    }

    private var headerActions: some View {
        let path = machine.path
        let state = library.state(of: path)
        let isCreating = library.creations[path]?.isRunning == true
        let actions = actions
        return HStack(spacing: 6) {
            if isCreating {
                DKButton(DKButtonSpec(String(localized: "Show Progress"), variant: .primary) {
                    onShowProgress(path)
                })
            } else if state == .running {
                DKButton(DKButtonSpec(
                    String(localized: "Stop"),
                    glyph: .stop,
                    help: String(localized: "Stop \(machine.name)"),
                ) { actions.stop([machine]) })
            } else {
                DKButton(DKButtonSpec(
                    String(localized: "Start"),
                    glyph: .play,
                    variant: .primary,
                    isEnabled: state == .stopped,
                    help: String(localized: "Start the selected machine"),
                ) { actions.start([machine]) })
            }
            if !isCreating {
                DKButton(DKButtonSpec(String(localized: "Open Console"), glyph: .terminal, size: .icon) {
                    onOpenConsole(path)
                })
            }
            VPhoneLaunchpadMachineMoreButton(items: actions.items(for: [machine]))
        }
        .fixedSize()
    }

    // MARK: - Creation

    @ViewBuilder
    private func creationSummary(_ creation: VPhoneLaunchpadCreationPipeline) -> some View {
        if creation.isRunning {
            let steps = VPhoneLaunchpadCreationPipeline.Step.allCases.count
            let step = creation.current
            DKCard(.padded) {
                HStack(alignment: .firstTextBaseline, spacing: DK.Space.s3) {
                    Text(step.map { String(localized: "Step \($0.rawValue + 1) of \(steps) · \($0.title)") } ?? String(localized: "Creating \(creation.options.name)"))
                        .font(DK.Typeface.bodyStrong)
                        .foregroundStyle(DK.Palette.ink)
                    Spacer(minLength: 0)
                    if let fraction = creation.downloadFraction {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .font(DK.Typeface.body)
                            .monospacedDigit()
                            .foregroundStyle(DK.Palette.muted)
                    }
                }
                // Only the IPSW download reports how far it has come.
                if let fraction = creation.downloadFraction {
                    DKProgress(value: fraction, tone: .warning, label: step?.title)
                } else {
                    DKProgress.indeterminate(tone: .warning, label: step?.title)
                }
            }
        } else if creation.isFinished {
            DKBanner(String(localized: "Created"), tone: .info, actionLabel: String(localized: "View Details")) {
                onShowProgress(creation.machine)
            }
        } else {
            DKBanner(
                creation.failure?.message ?? String(localized: "Creation stopped"),
                tone: .danger,
                actionLabel: String(localized: "View Details"),
            ) {
                onShowProgress(creation.machine)
            }
        }
    }

    // MARK: - Core Bundle

    /// The host programs and the guest environment from different bundles.
    /// The banner's button updates the guest environment, under the rules of
    /// the menu item of that name.
    @ViewBuilder
    private var mixedBanner: some View {
        if library.bindings[machine.path]?.hasMixedVersions == true {
            let path = machine.path
            let library = library
            DKBanner(Self.mixedHelp, action: DKButtonSpec(
                String(localized: "Update Guest Environment"),
                size: .small,
                isEnabled: isStopped && machine.restoreInfo != nil && machine.customFirmwareInstalled != false,
            ) {
                Task { await library.updateGuestEnvironment(path) }
            })
        }
    }

    /// The three layers a bundle provides, each from the bundle that last
    /// wrote it. A new binding reaches the host programs at the next start
    /// and the guest environment when it is updated, never the boot chain.
    private var coreBundleSection: some View {
        let binding = library.bindings[machine.path]
        let version = library.bundleVersion(for: machine.path)
        let isInstalled = version.map(model.bundles.selectableVersions.contains) ?? false
        let unknown = String(localized: "Unknown")
        return DKSection(
            String(localized: "Core Bundle"),
            accessory: DKButtonSpec(
                String(localized: "Change…"),
                isEnabled: actions.canChangeBundle([machine]),
            ) { onPresent(.changeBundle([machine])) },
            items: [
                layer(
                    String(localized: "Host Programs"),
                    version ?? unknown,
                    help: String(localized: "vphone-cli and vphone-vm come from this bundle at every start."),
                    warning: isInstalled ? nil : version.map { String(localized: "VPhone.bundle \($0) is not installed.") },
                ),
                layer(
                    String(localized: "Guest Environment"),
                    binding?.guestEnvironment ?? unknown,
                    help: String(localized: "vphoned and the hook libraries in the guest."),
                    warns: binding?.hasMixedVersions == true,
                ),
                layer(
                    String(localized: "Boot Chain"),
                    binding?.bootChain ?? unknown,
                    help: String(localized: "The Core Bundle that built the boot chain when the machine was created."),
                ),
            ],
        )
    }

    /// One layer: its version as a badge, in the warning tone when `warns`,
    /// what it is, and a warning line when there is one to spell out.
    private func layer(_ title: String, _ version: String, help: String, warning: String? = nil, warns: Bool = false) -> DKListItem {
        var lines: [DKListItem.Line] = [DKListItem.Line(help)]
        if let warning {
            lines.append(DKListItem.Line(warning, tone: .warning))
        }
        return DKListItem(
            title,
            badges: [DKListItem.Badge(version, tone: warns || warning != nil ? .warning : .neutral)],
            lines: lines,
        )
    }

    // MARK: - Patches

    /// What a patch read depends on: the machine, the bundle that reads it,
    /// and the run state, so a finished update or install is read again.
    private struct PatchReadKey: Equatable {
        let machine: VPhoneLaunchpadMachinePath
        let bundle: String?
        let state: VPhoneLaunchpadMachineLibrary.RunState
        let revision: Int
    }

    private var patchReadKey: PatchReadKey {
        PatchReadKey(
            machine: machine.path,
            bundle: library.bundleVersion(for: machine.path),
            state: library.state(of: machine.path),
            revision: patchRevision,
        )
    }

    /// The machine's patch choice: the preset, how many boxes differ from
    /// it, and, when the machine's bundle reports it, how many patches have
    /// not reached the guest yet. An older bundle does not report the last,
    /// and the row is left out. Edit opens the patch editor on this machine;
    /// Apply to Guest updates the guest environment, which is what brings
    /// guest patches in line. Boot-chain patches only a restore changes.
    @ViewBuilder
    private var patchesSection: some View {
        if library.creations[machine.path]?.isRunning != true {
            VStack(alignment: .leading, spacing: DK.Space.s2) {
                if let catalog = patchCatalog, patchCatalogMachine == machine.path {
                    DKSection(String(localized: "Patches")) {
                        DKKeyValueRow(DKKeyValue(
                            String(localized: "Preset"),
                            catalog.preset(catalog.activePreset)?.displayTitle ?? catalog.activePreset,
                        ))
                        DKKeyValueRow(DKKeyValue(
                            String(localized: "Overrides"),
                            catalog.overrideCount == 0
                                ? String(localized: "None")
                                : String(localized: "\(catalog.overrideCount) changed from the preset"),
                        ))
                        .help(overridesHelp(catalog))
                        if catalog.installed == true, let pending = catalog.pendingPatches {
                            DKKeyValueRow(DKKeyValue(
                                String(localized: "Not Applied"),
                                pending == 0 ? String(localized: "None") : Self.inflected("^[\(pending) patch](inflect: true)"),
                                tone: pending == 0 ? .success : .warning,
                            ))
                            .help(pendingHelp(catalog, pending: pending))
                        }
                    }
                    // The kernelcache has its own button below; only the
                    // restore-only patches need this spelled-out dead-end.
                    if catalog.installed == true, catalog.pendingPatches != nil, catalog.pendingRestorePatches > 0 {
                        footnote(Text("Boot chain: ^[\(catalog.pendingRestorePatches) patch](inflect: true) (TXM, device tree, LLB) not applied; only a restore applies them, which erases the data. Run `vphone-cli fw patches \(machine.name)` for each."))
                    }
                    patchActions(catalog)
                } else if let patchCatalogError {
                    DKSection(String(localized: "Patches")) {
                        Text("Unavailable")
                            .font(DK.Typeface.body)
                            .foregroundStyle(DK.Palette.muted)
                            .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight, alignment: .leading)
                            .padding(.horizontal, 14)
                            .help(patchCatalogError)
                    }
                } else {
                    DKSection(String(localized: "Patches")) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight)
                    }
                }
            }
        }
    }

    /// Update Kernel and Apply to Guest while patches are pending, then
    /// Edit. A running machine says why the first two are dimmed.
    private func patchActions(_ catalog: VPhoneLaunchpadPatchCatalog) -> some View {
        let showsKernel = catalog.installed == true && catalog.pendingKernelPatches > 0
        let showsGuest = catalog.installed == true && catalog.pendingGuestPatches > 0
        return VStack(alignment: .leading, spacing: 6) {
            if !isStopped, showsKernel || showsGuest {
                footnote(Text("Stop the machine to apply."))
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                patchButtons(catalog, showsKernel: showsKernel, showsGuest: showsGuest)
            }
        }
    }

    @ViewBuilder
    private func patchButtons(_ catalog: VPhoneLaunchpadPatchCatalog, showsKernel: Bool, showsGuest: Bool) -> some View {
        let path = machine.path
        let library = library
        let isStopped = isStopped
        Group {
            if showsKernel {
                DKButton(DKButtonSpec(
                    String(localized: "Update Kernel"),
                    size: .small,
                    isEnabled: isStopped,
                    help: isStopped
                        ? String(localized: "Swaps the Preboot kernelcache for the one this machine's patches resolve to, keeping the data (no restore).")
                        : String(localized: "Stop the machine to update its kernel."),
                ) {
                    Task {
                        await library.updateKernel(path)
                        patchRevision += 1
                    }
                })
            }
            if showsGuest {
                DKButton(DKButtonSpec(
                    String(localized: "Apply to Guest"),
                    size: .small,
                    isEnabled: isStopped,
                    help: isStopped
                        ? String(localized: "Updates the guest environment, which turns guest patches on or off to match this machine’s choice.")
                        : String(localized: "Stop the machine to apply its patch choice to the guest."),
                ) {
                    Task {
                        await library.updateGuestEnvironment(path)
                        patchRevision += 1
                    }
                })
            }
            DKButton(DKButtonSpec(String(localized: "Edit…"), size: .small) {
                editedPatches = catalog.selection
            })
        }
        .fixedSize()
    }

    private func pendingHelp(_ catalog: VPhoneLaunchpadPatchCatalog, pending: Int) -> String {
        guard pending > 0 else {
            return String(localized: "The guest has every patch this machine is set to.")
        }
        var lines: [String] = []
        if catalog.pendingGuestPatches > 0 {
            lines.append(String(localized: "^[\(catalog.pendingGuestPatches) guest patch](inflect: true) to apply with Apply to Guest."))
        }
        if catalog.pendingKernelPatches > 0 {
            lines.append(String(localized: "^[\(catalog.pendingKernelPatches) kernel patch](inflect: true) to apply with Update Kernel (keeps the data)."))
        }
        if catalog.pendingRestorePatches > 0 {
            lines.append(String(localized: "^[\(catalog.pendingRestorePatches) boot chain patch](inflect: true) that only a restore applies."))
        }
        lines.append(String(localized: "vphone-cli fw patches \(machine.name) lists each one."))
        return lines.joined(separator: "\n")
    }

    private func overridesHelp(_ catalog: VPhoneLaunchpadPatchCatalog) -> String {
        var lines: [String] = []
        if !catalog.blockedPatches.isEmpty {
            lines.append(String(localized: "Off: \(catalog.blockedPatches.joined(separator: ", "))"))
        }
        if !catalog.allowedPatches.isEmpty {
            lines.append(String(localized: "On: \(catalog.allowedPatches.joined(separator: ", "))"))
        }
        return lines.joined(separator: "\n")
    }

    private func loadPatches() async {
        let path = machine.path
        if patchCatalogMachine != path {
            patchCatalog = nil
            patchCatalogError = nil
            patchCatalogMachine = path
        }
        guard library.creations[path]?.isRunning != true else { return }
        do {
            let catalog = try await VPhoneLaunchpadPatchCatalog.read(
                using: library.commandLine(for: path),
                machine: path,
                preset: nil,
            )
            guard path == machine.path else { return }
            patchCatalog = catalog
            patchCatalogError = nil
        } catch is CancellationError {
            return
        } catch {
            guard path == machine.path else { return }
            patchCatalog = nil
            patchCatalogError = VPhoneLaunchpadError.message(for: error)
        }
    }

    // MARK: - Facts

    private var firmwareSection: some View {
        DKSection(String(localized: "Firmware")) {
            if let info = machine.restoreInfo {
                factRow(DKKeyValue(machine.osName, "\(info.ios.version) (\(info.ios.build))"))
                factRow(DKKeyValue("cloudOS", "\(info.cloudOS.version) (\(info.cloudOS.build))"))
                if let firmwareName = machine.firmwareName {
                    // An unfinished install cannot boot.
                    factRow(DKKeyValue(
                        String(localized: "Variant"),
                        firmwareName,
                        tone: machine.customFirmwareInstalled == false ? .warning : nil,
                    ))
                }
            } else {
                Text("Not restored")
                    .font(DK.Typeface.body)
                    .foregroundStyle(DK.Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight, alignment: .leading)
                    .padding(.horizontal, 14)
            }
        }
    }

    private var hardwareSection: some View {
        var rows = [
            DKKeyValue(String(localized: "CPU"), String(localized: "\(machine.cpuCount) cores")),
            DKKeyValue(String(localized: "Memory"), VPhoneLaunchpadMachinesView.memory(machine.memoryMB)),
            DKKeyValue(String(localized: "Disk"), VPhoneLaunchpadMachinesView.disk(machine.diskSizeBytes)),
        ]
        if machine.unlocksAtStartup == true {
            rows.append(DKKeyValue(String(localized: "Unlock at Startup"), String(localized: "On")))
        }
        return facts(String(localized: "Hardware"), rows)
    }

    private var networkSection: some View {
        var rows = [DKKeyValue(String(localized: "Mode"), machine.networkDescription)]
        if let address = machine.addressDescription {
            rows.append(DKKeyValue(String(localized: "IPv4 Address"), address, monospaced: true))
        }
        if !machine.network.macAddress.isEmpty {
            rows.append(DKKeyValue(String(localized: "MAC Address"), machine.network.macAddress, monospaced: true))
        }
        if let name = machine.network.localHostName {
            rows.append(DKKeyValue(String(localized: "mDNS Name"), "\(name).local", monospaced: true))
        }
        for (index, forward) in (machine.network.portForwards ?? []).enumerated() {
            rows.append(DKKeyValue(
                String(localized: "Port Forward"),
                "\(forward.transport.uppercased()) \(forward.hostAddress ?? "127.0.0.1"):\(forward.hostPort) → \(forward.guestPort)",
                monospaced: true,
                id: "forward-\(index)",
            ))
        }
        return facts(String(localized: "Network"), rows)
    }

    private var identitySection: some View {
        var rows: [DKKeyValue] = []
        if let udid = machine.udid {
            rows.append(DKKeyValue("UDID", udid, monospaced: true))
        }
        rows.append(DKKeyValue(String(localized: "Location"), VPhoneLaunchpadHostSetup.abbreviated(machine.path.url), monospaced: true))
        return facts(String(localized: "Identity"), rows)
    }

    private func facts(_ title: String, _ rows: [DKKeyValue]) -> some View {
        DKSection(title) {
            ForEach(rows) { factRow($0) }
        }
    }

    /// A key-value row whose full value is its help tag, since long values
    /// truncate.
    private func factRow(_ row: DKKeyValue) -> some View {
        DKKeyValueRow(row)
            .help(row.value)
    }

    // MARK: - Console

    /// The tail of the machine's console log, following it while the machine
    /// runs, with the full console and the recent commands a click away.
    private var consoleSection: some View {
        let path = machine.path
        let isRunning = library.state(of: path) == .running
        return DKSection(
            String(localized: "Console"),
            accessory: DKButtonSpec(String(localized: "Open Console")) { onOpenConsole(path) },
            card: false,
        ) {
            VStack(alignment: .trailing, spacing: DK.Space.s2) {
                VPhoneLaunchpadConsoleTail(url: VPhoneLaunchpadMachineLibrary.consoleLog(path), following: isRunning)
                    .frame(height: 150)
                DKButton(DKButtonSpec(String(localized: "Recent Commands"), size: .small) { showsCommands = true })
            }
        }
    }

    // MARK: - Helpers

    private func footnote(_ text: Text) -> some View {
        text
            .font(DK.Typeface.caption)
            .lineSpacing(3)
            .foregroundStyle(DK.Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DK.Space.s1)
    }

    /// A string with an inflection rule applied: "1 patch", "2 patches".
    private static func inflected(_ resource: LocalizedStringResource) -> String {
        String(AttributedString(localized: resource).characters)
    }
}
