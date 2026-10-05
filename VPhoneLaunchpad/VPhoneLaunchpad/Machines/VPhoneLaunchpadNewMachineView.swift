import AppKit
import SwiftUI
import VPhoneDesignKit

/// Name, location, Core Bundle, guest device and firmware pairing from
/// `fw catalog`, hardware and options, on three pages. Every page has
/// defaults, so Create works from any of them.
/// Create hands off to the pipeline sheet.
struct VPhoneLaunchpadNewMachineView: View {
    let onCreate: (VPhoneLaunchpadMachinePath) -> Void
    @Environment(VPhoneLaunchpadModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    /// The Core Bundle picked here; nil follows the default version.
    @State private var chosenVersion: String?
    /// The canonical library the machine is created in.
    @State private var location = VPhoneLaunchpadMachineLocations.defaultRoot
    /// A folder chosen with Other… that is not one of the library's locations.
    @State private var chosenLocation: String?
    @State private var catalog: VPhoneLaunchpadFirmwareCatalog?
    @State private var catalogError: String?
    /// The guest device's product type.
    @State private var guest: String?
    @State private var pairing: String?
    @State private var usesCustomSources = false
    @State private var iphoneSource = ""
    @State private var cloudOSSource = ""
    @State private var cpu = 8
    @State private var memoryMB = 8192
    @State private var diskSizeGB = 64
    @State private var network = "nat"
    @State private var patches = VPhoneLaunchpadPatchSelection()
    @State private var patchCatalog: VPhoneLaunchpadPatchCatalog?
    @State private var patchCatalogError: String?
    @State private var keepArtifacts = false
    @State private var page = Page.general

    enum Page: Hashable {
        case general, hardware, advanced
    }

    private var selectedGuest: VPhoneLaunchpadFirmwareCatalog.Device? {
        catalog?.guests.first { $0.id == guest }
    }

    /// The version every step of the creation runs with, and the one the
    /// firmware and patch catalogs are read from.
    private var bundleVersion: String? {
        let selectable = model.bundles.selectableVersions
        if let chosenVersion, selectable.contains(chosenVersion) {
            return chosenVersion
        }
        return model.bundles.defaultVersion ?? selectable.first
    }

    private var selectedPairing: VPhoneLaunchpadFirmwareCatalog.Pairing? {
        selectedGuest?.pairings.first { $0.id == pairing }
    }

    private var sources: (String, String)? {
        if usesCustomSources {
            let iphone = iphoneSource.trimmingCharacters(in: .whitespaces)
            let cloudOS = cloudOSSource.trimmingCharacters(in: .whitespaces)
            return iphone.isEmpty || cloudOS.isEmpty ? nil : (iphone, cloudOS)
        }
        return selectedPairing.map { ($0.ios.url, $0.recommendedCloudOS.url) }
    }

    private var effectiveName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var machine: VPhoneLaunchpadMachinePath {
        VPhoneLaunchpadMachinePath(libraryRoot: location, name: effectiveName)
    }

    private func isTaken(_ machine: VPhoneLaunchpadMachinePath) -> Bool {
        model.machines.machines.contains(where: { $0.path == machine })
            || model.machines.creations[machine] != nil
            || FileManager.default.fileExists(atPath: machine.url.path)
    }

    /// The first `pcc-research-NN` free in `root`, filled into the field when
    /// the sheet opens.
    private func suggestedName(in root: String) -> String {
        let names = (1 ... 99).lazy.map { String(format: "pcc-research-%02d", $0) }
        return names.first { !isTaken(VPhoneLaunchpadMachinePath(libraryRoot: root, name: $0)) } ?? "pcc-research"
    }

    private var nameProblem: String? {
        if !VPhoneLaunchpadNames.isValidMachineName(effectiveName) {
            return String(localized: "Use letters, numbers, periods, hyphens, and underscores.")
        }
        if model.machines.machines.contains(where: { $0.path == machine }) || model.machines.creations[machine]?.isRunning == true {
            return String(localized: "A machine with this name already exists.")
        }
        if FileManager.default.fileExists(atPath: machine.url.path) {
            return String(localized: "A folder with this name already exists in this location.")
        }
        if !VPhoneLaunchpadMachineLocations.socketPathFits(root: location, name: effectiveName) {
            return String(localized: "The path is too long. Use a shorter name, or a location with a shorter path.")
        }
        return nil
    }

    private var locationProblem: String? {
        VPhoneLaunchpadMachineLocations.problem(with: location)
    }

    private var canCreate: Bool {
        nameProblem == nil && locationProblem == nil && sources != nil && bundleVersion != nil
    }

    var body: some View {
        DKSheet(
            String(localized: "New Machine"),
            subtitle: String(localized: "Downloads firmware, patches the boot chain, restores and boots — in one run."),
            width: DKSheetMetrics.defaultWidth,
            note: footerNote,
            trailing: [
                .cancel(String(localized: "Cancel")) { dismiss() },
                .primary(String(localized: "Create"), isEnabled: canCreate) { create() },
            ],
        ) {
            switch page {
            case .general:
                generalPage
            case .hardware:
                hardwarePage
            case .advanced:
                VPhoneLaunchpadNewMachineAdvancedView(
                    network: $network,
                    patches: $patches,
                    keepArtifacts: $keepArtifacts,
                    patchCatalog: patchCatalog,
                    patchCatalogError: patchCatalogError,
                    reloadPatches: { Task { await loadPatchCatalog() } },
                    bundleVersion: bundleVersion,
                )
            }
        } pages: {
            DKSegmented(String(localized: "Page"), selection: $page, options: [
                DKSegmentOption(String(localized: "General"), value: Page.general),
                DKSegmentOption(String(localized: "Hardware"), value: Page.hardware),
                DKSegmentOption(String(localized: "Advanced"), value: Page.advanced),
            ])
        }
        .vphoneLaunchpadSheetChrome()
        // Each bundle version has its own firmware pairings and patch sets.
        .task(id: bundleVersion) { await loadCatalog() }
        .task(id: bundleVersion) { await loadPatchCatalog() }
        .onAppear {
            let root = model.machines.preferredRoot
            location = root
            name = suggestedName(in: root)
            #if DEBUG
                if VPhoneLaunchpadPreview.isActive {
                    page = VPhoneLaunchpadPreview.newMachinePage
                }
            #endif
        }
    }

    /// Why Create is off, from the pages that do not show the field at fault,
    /// or that the disk may not fit the volume.
    private var footerNote: DKSheetNote? {
        if page != .general, let problem = nameProblem ?? locationProblem {
            return DKSheetNote(problem, tone: .danger)
        }
        if freeGB < neededGB {
            return DKSheetNote(spaceNote, tone: .warning)
        }
        return nil
    }

    // MARK: - Pages

    @ViewBuilder
    private var generalPage: some View {
        VStack(alignment: .leading, spacing: DK.Space.s2) {
            DKCard {
                DKFormRow(String(localized: "Name"), fill: true) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.dkField)
                }
                DKFormRow(String(localized: "Location"), fill: true) {
                    locationPicker
                }
            }
            if let problem = nameProblem ?? locationProblem {
                VPhoneLaunchpadFieldProblem(text: problem)
            }
        }

        bundleSection

        firmware
    }

    private var hardwarePage: some View {
        DKSection(footnote: spaceNote) {
            VPhoneLaunchpadStepperRow(
                label: String(localized: "CPU"),
                value: String(localized: "\(cpu) cores"),
                number: $cpu,
                range: 1 ... ProcessInfo.processInfo.activeProcessorCount,
            )
            VPhoneLaunchpadStepperRow(label: String(localized: "Memory"), value: "\(memoryMB) MB", number: $memoryMB, range: 2048 ... 65536, step: 1024)
            VPhoneLaunchpadStepperRow(label: String(localized: "Disk"), value: "\(diskSizeGB) GB", number: $diskSizeGB, range: 32 ... 512, step: 16)
        }
    }

    // MARK: - Core Bundle

    private var bundleSection: some View {
        DKSection(footnote: String(localized: "The boot chain is built when the machine is created. Host programs, the guest environment and guest patches can be changed later.")) {
            if model.bundles.selectableVersions.isEmpty {
                VPhoneLaunchpadCardMessage(text: Text("No Core Bundle is installed. Install one in Core Bundle."), isWarning: true)
            } else {
                DKFormRow(String(localized: "Core Bundle"), fill: true) {
                    Picker("Core Bundle", selection: versionBinding) {
                        ForEach(model.bundles.selectableVersions, id: \.self) { version in
                            // Store names keep their `-local.` and `-ci.` suffixes,
                            // so a build that is not a release reads as one.
                            if version == model.bundles.defaultVersion {
                                Text("\(version) (Default)").tag(Optional(version))
                            } else {
                                Text(verbatim: version).tag(Optional(version))
                            }
                        }
                    }
                    .dkFieldPicker(fill: true)
                }
            }
        }
    }

    /// A new version clears what was read from the old one, so Create cannot
    /// use a pairing or a preset that version never offered.
    private var versionBinding: Binding<String?> {
        Binding(
            get: { bundleVersion },
            set: { version in
                guard version != bundleVersion else {
                    return
                }
                chosenVersion = version
                catalog = nil
                catalogError = nil
                patchCatalog = nil
                patchCatalogError = nil
            },
        )
    }

    // MARK: - Location

    /// The library's locations that are mounted, the default one first, and
    /// a folder chosen with Other….
    private var locations: [String] {
        var roots = model.machines.roots.filter { $0 == model.machines.libraryRoot || VPhoneLaunchpadMachineLocations.isAvailable($0) }
        for root in [chosenLocation, location].compactMap(\.self) where !roots.contains(root) {
            roots.append(root)
        }
        return roots
    }

    private var locationPicker: some View {
        Picker("Location", selection: Binding(
            get: { location },
            set: { root in
                if root.isEmpty {
                    // Let the menu close before the open panel runs.
                    Task { @MainActor in chooseLocation() }
                } else {
                    location = root
                }
            },
        )) {
            ForEach(locations, id: \.self) { root in
                Text(verbatim: VPhoneLaunchpadHostSetup.abbreviated(URL(fileURLWithPath: root, isDirectory: true)))
                    .tag(root)
            }
            Divider()
            // Library roots are absolute, so an empty tag cannot be one.
            Text("Other…").tag("")
        }
        .dkFieldPicker(fill: true)
        .help(location)
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a Location")
        panel.message = String(localized: "The machine is created in a folder with its name inside the folder you choose.")
        panel.prompt = String(localized: "Choose")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: location, isDirectory: true)
        panel.present { url in
            useLocation(url)
        }
    }

    private func useLocation(_ url: URL) {
        let root = VPhoneLaunchpadMachineLocations.canonical(url)
        if !model.machines.roots.contains(root) {
            chosenLocation = root
        }
        location = root
        // Machines already in the folder join the list; a folder that cannot
        // hold machines is only shown here, with the reason.
        if VPhoneLaunchpadMachineLocations.problem(with: root) == nil {
            model.machines.addLocation(root)
        }
    }

    // MARK: - Firmware

    private var firmware: some View {
        VPhoneLaunchpadSheetSection(String(localized: "Firmware")) {
            DKSegmented(String(localized: "Source"), selection: $usesCustomSources, options: [
                DKSegmentOption(String(localized: "Catalog"), value: false),
                DKSegmentOption(String(localized: "Custom IPSWs"), value: true),
            ])
        } content: {
            if usesCustomSources {
                DKFormRow(String(localized: "iPhone IPSW"), fill: true) {
                    sourceField("iPhone IPSW", $iphoneSource)
                }
                DKFormRow(String(localized: "cloudOS IPSW"), fill: true) {
                    sourceField("cloudOS IPSW", $cloudOSSource)
                }
            } else if let catalog {
                if catalog.guests.count > 1 {
                    DKFormRow(String(localized: "Device"), fill: true) {
                        Picker("Device", selection: Binding(
                            get: { guest },
                            set: { choose($0) },
                        )) {
                            ForEach(catalog.guests) { guest in
                                Text(verbatim: guest.detailedName).tag(Optional(guest.id))
                            }
                        }
                        .dkFieldPicker(fill: true)
                    }
                }
                VPhoneLaunchpadPairingList(
                    label: selectedGuest?.isPad == true ? "iPadOS" : String(localized: "iOS"),
                    pairings: (selectedGuest?.pairings ?? []).reversed(),
                    selection: $pairing,
                )
                DKFormRow(String(localized: "cloudOS"), fill: true) {
                    Text(verbatim: selectedPairing?.recommendedCloudOS.name ?? "—")
                        .textSelection(.enabled)
                }
            } else if let catalogError {
                VPhoneLaunchpadCardMessage(text: Text(verbatim: catalogError), isWarning: true)
            } else {
                VPhoneLaunchpadCardLoading(text: Text("Loading firmware catalog…"))
            }
        } footnote: {
            if !usesCustomSources, let selectedGuest {
                Text("Recommended firmware pairings for \(selectedGuest.detailedName).")
            }
        }
    }

    private static func isIPSWFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return path.hasPrefix("/") && path.lowercased().hasSuffix(".ipsw")
            && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    @ViewBuilder
    private func sourceField(_ title: LocalizedStringKey, _ text: Binding<String>) -> some View {
        // A chosen file shows only its name; a URL or a path still
        // being typed stays editable.
        if Self.isIPSWFile(text.wrappedValue) {
            Text(verbatim: URL(fileURLWithPath: text.wrappedValue).lastPathComponent)
                .font(DK.Typeface.mono)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(text.wrappedValue)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                text.wrappedValue = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DK.Palette.muted)
            .help("Clear")
            .accessibilityLabel(Text("Clear"))
        } else {
            TextField(title, text: text, prompt: Text("URL or path"))
                .textFieldStyle(.dkFieldMono)
                .labelsHidden()
        }
        DKButton(String(localized: "Choose…"), size: .small) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.present { url in
                text.wrappedValue = url.path
            }
        }
    }

    /// Disk plus roughly 20 GB of IPSWs and the prepared restore tree.
    private var neededGB: Int {
        diskSizeGB + 20
    }

    private var freeGB: Int {
        let root = VPhoneLaunchpadHostSetup.existingAncestor(of: URL(fileURLWithPath: location, isDirectory: true))
        let free = (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        return Int(free / 1_000_000_000)
    }

    private var spaceNote: String {
        String(localized: "Needs about \(neededGB) GB; \(freeGB) GB free.")
    }

    // MARK: - Actions

    private func loadCatalog() async {
        #if DEBUG
            if VPhoneLaunchpadPreview.isActive {
                catalog = VPhoneLaunchpadPreview.catalog
                choose(catalog?.guests.first?.id)
                return
            }
        #endif
        let version = bundleVersion
        guard let commandLine = version.flatMap(model.bundles.commandLine(version:)) else {
            return
        }
        do {
            let result = try await commandLine.run(["fw", "catalog", "--json"], recordInHistory: false)
            // Another version may have been chosen meanwhile.
            guard version == bundleVersion else {
                return
            }
            guard result.succeeded, let data = result.jsonData else {
                catalogError = result.tail
                return
            }
            let catalog = try JSONDecoder().decode(VPhoneLaunchpadFirmwareCatalog.self, from: data)
            self.catalog = catalog
            // The guest and pairing chosen under the previous version stay
            // when this one offers them too.
            if !catalog.guests.contains(where: { $0.id == guest }) {
                choose(catalog.guests.first?.id)
            } else if selectedGuest?.pairings.contains(where: { $0.id == pairing }) != true {
                pairing = selectedGuest?.defaultPairing?.id
            }
        } catch {
            guard version == bundleVersion else {
                return
            }
            catalogError = error.localizedDescription
        }
    }

    /// Select a guest device and its newest release.
    private func choose(_ productType: String?) {
        guest = productType
        pairing = selectedGuest?.defaultPairing?.id
    }

    /// Read again whenever the preset or the version changes: `inPreset`, which
    /// the note and the editor read the checkmarks against, is reported per
    /// preset, and each version declares its own patches.
    private func loadPatchCatalog() async {
        let version = bundleVersion
        let requested = patches.preset
        do {
            let catalog = try await VPhoneLaunchpadPatchCatalog.read(
                using: version.flatMap(model.bundles.commandLine(version:)),
                machine: nil,
                preset: requested,
            )
            // A second switch may have overtaken this read.
            guard requested == patches.preset, version == bundleVersion else {
                return
            }
            // Overrides naming a patch this version does not declare are dropped.
            patches.normalize(against: catalog)
            patchCatalog = catalog
            patchCatalogError = nil
        } catch {
            guard requested == patches.preset, version == bundleVersion else {
                return
            }
            // The first read after a version change: that version may not
            // have the chosen preset, so fall back to the default one.
            if patchCatalog == nil, requested != VPhoneLaunchpadPatchSelection.defaultPreset {
                patches = VPhoneLaunchpadPatchSelection()
                await loadPatchCatalog()
                return
            }
            patchCatalogError = VPhoneLaunchpadError.message(for: error)
        }
    }

    private func create() {
        guard let (iphone, cloudOS) = sources, let bundleVersion else {
            return
        }
        let options = VPhoneLaunchpadCreationPipeline.Options(
            name: effectiveName,
            libraryRoot: location,
            bundleVersion: bundleVersion,
            iphoneSource: iphone,
            cloudOSSource: cloudOS,
            // An iPad IPSW often covers two sizes; name the one chosen.
            device: usesCustomSources ? nil : selectedGuest.flatMap { $0.isPad ? $0.productType : nil },
            cpuCount: cpu,
            memoryMB: memoryMB,
            diskSizeGB: diskSizeGB,
            network: network,
            patches: patches,
            keepArtifacts: keepArtifacts,
        )
        let pipeline = model.machines.create(options)
        model.machines.selection = [pipeline.machine]
        onCreate(pipeline.machine)
    }
}

// MARK: - Pairings

/// The catalog's firmware pairings for one device, newest first, as a radio
/// list in the Firmware card. A long catalog scrolls inside the card, with
/// the chosen pairing brought into view.
private struct VPhoneLaunchpadPairingList: View {
    let label: String
    let pairings: [VPhoneLaunchpadFirmwareCatalog.Pairing]
    @Binding var selection: String?

    private static let rowHeight: CGFloat = 36
    private static let visibleRows = 6

    var body: some View {
        if pairings.count > Self.visibleRows {
            ScrollViewReader { proxy in
                ScrollView {
                    rows
                }
                .frame(height: Self.rowHeight * (CGFloat(Self.visibleRows) + 0.5))
                .onAppear {
                    if let selection {
                        proxy.scrollTo(selection, anchor: .center)
                    }
                }
            }
        } else {
            rows
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(pairings.enumerated()), id: \.element.id) { index, pairing in
                if index > 0 {
                    DK.Palette.dividerSoft.frame(height: DK.Metric.hairline)
                }
                row(pairing)
                    .id(pairing.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: label))
        .onMoveCommand { direction in
            let step = switch direction {
            case .up: -1
            case .down: 1
            default: 0
            }
            guard step != 0, let index = pairings.firstIndex(where: { $0.id == selection }) else {
                return
            }
            let next = min(max(index + step, 0), pairings.count - 1)
            selection = pairings[next].id
        }
    }

    private func row(_ pairing: VPhoneLaunchpadFirmwareCatalog.Pairing) -> some View {
        let isSelected = pairing.id == selection
        return Button {
            selection = pairing.id
        } label: {
            HStack(spacing: DK.Space.s3) {
                Circle()
                    .strokeBorder(isSelected ? DK.Palette.accent : DK.Palette.inkDisabled, lineWidth: isSelected ? 5 : 1.5)
                    .frame(width: 16, height: 16)
                Text(verbatim: pairing.ios.name)
                    .foregroundStyle(DK.Palette.ink)
                if !pairing.build.isEmpty {
                    Text(verbatim: pairing.build)
                        .font(DK.Typeface.mono)
                        .foregroundStyle(DK.Palette.muted)
                }
                Spacer(minLength: 0)
            }
            .font(DK.Typeface.body)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            .background(isSelected ? DK.Palette.accentTint : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pairing.ios.url)
        .accessibilityLabel(Text(verbatim: pairing.build.isEmpty ? pairing.ios.name : "\(pairing.ios.name) (\(pairing.build))"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Pipeline

/// The pipeline, which keeps running when this sheet closes. A failure shows
/// on its step and in the footer; the end of the log is shown under the
/// steps, and the whole log opens in its own sheet.
struct VPhoneLaunchpadCreationView: View {
    let creation: VPhoneLaunchpadCreationPipeline
    @Environment(\.dismiss) private var dismiss
    @State private var showsLog = false

    private typealias Step = VPhoneLaunchpadCreationPipeline.Step

    var body: some View {
        DKSheet(
            String(localized: "Creating \(creation.options.name)"),
            subtitle: subtitle,
            width: DKSheetMetrics.defaultWidth,
            note: failureNote,
            leading: leadingActions,
            trailing: trailingActions,
        ) {
            DKStepStrip(segments: Step.allCases.map(segment))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Step.allCases) { step in
                    stepRow(step)
                }
            }
            VPhoneLaunchpadTerminalPane(
                url: creation.logFile,
                style: .creation,
                replayBytes: VPhoneLaunchpadTerminalPane.tailBytes,
            )
            .frame(height: 120)
            .accessibilityLabel(Text("\(creation.options.name) Creation Log"))
        }
        .vphoneLaunchpadSheetChrome()
        .sheet(isPresented: $showsLog) {
            VPhoneLaunchpadConsoleView(title: "\(creation.options.name) Creation Log", url: creation.logFile, style: .creation)
        }
    }

    /// Which step runs, and that closing the sheet does not stop it.
    private var subtitle: String? {
        guard creation.isRunning else {
            return nil
        }
        let note = String(localized: "Creation continues if you close this window.")
        guard let number = VPhoneLaunchpadMachineFormat.currentStepNumber(Step.allCases.map(formatState)) else {
            return note
        }
        return String(localized: "Step \(number) of \(Step.allCases.count)") + " · " + note
    }

    private var leadingActions: [DKSheetAction] {
        var actions = [DKSheetAction(String(localized: "Open Log"), role: .plain) { showsLog = true }]
        if creation.isRunning {
            actions.append(DKSheetAction(String(localized: "Stop Creating"), variant: .danger, role: .plain) { creation.cancel() })
        }
        return actions
    }

    private var trailingActions: [DKSheetAction] {
        var actions: [DKSheetAction] = []
        if !creation.isRunning, let step = creation.failedStep {
            actions.append(DKSheetAction(String(localized: "Retry from \(step.title)"), role: .plain) { creation.start(from: step) })
        }
        actions.append(DKSheetAction(String(localized: "Close"), variant: .primary, role: .cancel) { dismiss() })
        return actions
    }

    private var failureNote: DKSheetNote? {
        guard !creation.isRunning, let failure = creation.failure else {
            return nil
        }
        return DKSheetNote(failure.message, tone: .danger)
    }

    // MARK: - Steps

    private func stepStatus(_ step: Step) -> DKStepStatus {
        switch creation.status(step) {
        case .passed, .warning: .done
        case .running: .active
        case .failed: .failed
        case .pending: .pending
        }
    }

    /// The download is the only step that reports how far along it is.
    private func progress(_ step: Step) -> Double? {
        step == .prepare && creation.status(step) == .running ? creation.downloadFraction : nil
    }

    private func formatState(_ step: Step) -> VPhoneLaunchpadMachineFormat.StepState {
        switch stepStatus(step) {
        case .done: .done
        case .active: .active
        case .failed: .failed
        case .pending: .pending
        }
    }

    private func segment(_ step: Step) -> DKStepSegment {
        let segment = VPhoneLaunchpadMachineFormat.segment(formatState(step), progress: progress(step))
        let tone: DKTone = switch segment.tone {
        case .success: .success
        case .warning: .warning
        case .danger: .danger
        }
        return DKStepSegment(fraction: segment.fraction, tone: tone)
    }

    private func stepRow(_ step: Step) -> some View {
        let status = stepStatus(step)
        let command = creation.command(for: step)
        return HStack(alignment: .top, spacing: DK.Space.s3) {
            mark(status)
                .frame(width: 18, height: 18)
                .padding(.top, 1)
                .accessibilityLabel(Text(verbatim: status.accessibilityText))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DK.Space.s1) {
                    Text(verbatim: step.title)
                        .font(status == .active ? DK.Typeface.bodyStrong : DK.Typeface.body)
                        .foregroundStyle(status == .pending ? DK.Palette.muted : DK.Palette.ink)
                    if step.needsRoot {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(DK.Palette.muted)
                            .help("Runs as root through the privileged helper")
                    }
                }
                Text(verbatim: command)
                    .font(DK.Typeface.mono)
                    .foregroundStyle(DK.Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(command)
                if let fraction = progress(step) {
                    HStack(spacing: DK.Space.s2) {
                        DKProgress(value: fraction, tone: .warning, thin: true, label: step.title)
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .font(DK.Typeface.caption)
                            .monospacedDigit()
                            .foregroundStyle(DK.Palette.muted)
                    }
                    .padding(.top, DK.Space.s1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let duration = creation.durations[step] {
                Text(Self.duration(duration))
                    .font(DK.Typeface.caption)
                    .monospacedDigit()
                    .foregroundStyle(DK.Palette.muted)
                    .padding(.top, 1)
            }
            VPhoneLaunchpadCommandInfoButton(command: "vphone-cli \(command)")
        }
        .padding(DK.Space.s2)
        .background {
            if status == .active {
                RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                    .fill(DK.Palette.warningSurface)
            }
        }
    }

    @ViewBuilder
    private func mark(_ status: DKStepStatus) -> some View {
        if status == .active {
            VPhoneLaunchpadSpinner()
        } else {
            DKIcon(status.glyph, size: 18)
                .foregroundStyle(Self.markColor(status))
        }
    }

    private static func markColor(_ status: DKStepStatus) -> Color {
        switch status {
        case .done: DK.Palette.success
        case .active: DK.Palette.muted
        case .pending: DK.Palette.inkDisabled
        case .failed: DK.Palette.danger
        }
    }

    static func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(interval).formatted(.time(pattern: interval >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}
