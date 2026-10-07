import SwiftUI
import VPhoneDesignKit

/// The patch editor: a preset, and a switch for every patch the bundle
/// declares. New Machine opens it for a machine that does not exist yet, and
/// the inspector for one that does.
///
/// For an existing machine the choice is read from and saved to that machine
/// (`fw patches <vm>`, `fw set-patches <vm>`) with its own Core Bundle. The
/// rows whose wanted state has not reached the guest are highlighted, and
/// grouped above the table by the step that delivers them (Apply to Guest,
/// Update Kernel, `fw patch` for AVPBooter, or only a restore), as the bundle
/// reports them and as the edit in progress changes them. The steps
/// themselves stay in the Machines inspector.
///
/// The list is never a copy of the catalogue — it is whatever
/// `vphone-cli fw patches --json` reports, so a patch set added to the bundle
/// shows up here without a change to Launchpad. Only the switches that differ
/// from the preset are kept, and switching preset re-bases them, since a
/// difference from the preset that is no longer active means nothing.
struct VPhoneLaunchpadPatchSettingsView: View {
    typealias Catalog = VPhoneLaunchpadPatchCatalog

    /// What the switches start from.
    let initial: VPhoneLaunchpadPatchSelection
    /// The Core Bundle New Machine creates with; its `vphone-cli` lists the
    /// patches. Nil reads the default version's.
    let bundleVersion: String?
    /// The existing machine being edited, or nil in New Machine.
    let machine: VPhoneLaunchpadMachinePath?
    /// Hands the edited choice back; New Machine holds it until the VM exists,
    /// the inspector saves it to the machine.
    let onSave: (VPhoneLaunchpadPatchSelection) -> Void

    @Environment(VPhoneLaunchpadModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selection: VPhoneLaunchpadPatchSelection
    @State private var catalog: Catalog?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var search = ""
    @State private var filter = Filter.all
    /// The row whose summary the detail card reads.
    @State private var highlighted: String?
    @State private var confirmsBootEssential = false
    /// What was on when the editor opened, so the status line can count what
    /// an edit to an existing machine changes. Taken from the first read.
    @State private var initiallyOn: Set<String>?
    /// The table's height, settled so the sheet's content fills the sheet
    /// whatever the sections above and below the table take.
    @State private var tableHeight: CGFloat = 340
    /// The heights `settleTable()` works from: the sheet's content and the
    /// table in it as last laid out, the sheet's head and footer, and the
    /// sheet itself.
    @State private var contentHeight: CGFloat = 0
    @State private var renderedTableHeight: CGFloat = 0
    @State private var chromeHeight: CGFloat = 0
    @State private var availableHeight: CGFloat = 0

    private static let minimumTableHeight: CGFloat = 160

    init(
        initial: VPhoneLaunchpadPatchSelection,
        bundleVersion: String? = nil,
        machine: VPhoneLaunchpadMachinePath? = nil,
        onSave: @escaping (VPhoneLaunchpadPatchSelection) -> Void,
    ) {
        self.initial = initial
        self.bundleVersion = bundleVersion
        self.machine = machine
        self.onSave = onSave
        _selection = State(initialValue: initial)
    }

    private var essentialOff: [Catalog.Patch] {
        catalog.map { selection.bootEssentialOff(in: $0) } ?? []
    }

    private var saveLabel: String {
        machine == nil ? String(localized: "Done") : String(localized: "Save")
    }

    var body: some View {
        DKSheet(
            title,
            subtitle: subtitle,
            width: nil,
            maxHeight: availableHeight > 0 ? availableHeight : .infinity,
            note: DKSheetNote(status),
            trailing: [
                .cancel(String(localized: "Cancel")) { dismiss() },
                .primary(saveLabel, isEnabled: catalog != nil) { commit() },
            ],
        ) {
            VStack(alignment: .leading, spacing: DK.Space.s4) {
                controls
                if let catalog, showsStatus {
                    pendingSection(catalog)
                }
                list
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                        renderedTableHeight = height
                        settleTable()
                    }
                if !essentialOff.isEmpty {
                    DKBanner(essentialOffText, tone: .warning)
                }
                detail
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                contentHeight = height
                settleTable()
            }
        }
        .background(alignment: .top) { chrome }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
            availableHeight = height
            settleTable()
        }
        // Opens at the ideal size; the sheet can be made larger, or as small
        // as the editor this one replaced.
        .frame(
            minWidth: 920, idealWidth: 1040, maxWidth: 1280,
            minHeight: 680, idealHeight: 800, maxHeight: 1040,
        )
        .background(DK.Palette.window)
        .confirmationDialog(
            "Leave ^[\(essentialOff.count) boot-essential patch](inflect: true) off?",
            isPresented: $confirmsBootEssential,
        ) {
            Button("Leave Them Off", role: .destructive) { finish() }
        } message: {
            Text("The machine may not boot without \(essentialOff.map(\.identifier).joined(separator: ", ")).")
        }
        .task { await load(preset: initial.preset) }
    }

    private var title: String {
        guard let machine else {
            return String(localized: "Patches")
        }
        return String(localized: "Patches — \(machine.name)")
    }

    /// The machine's OS pairing and the Core Bundle whose catalogue this is.
    private var subtitle: String? {
        var parts: [String] = []
        if let machine, let listed = model.machines.machines.first(where: { $0.path == machine }), let restoreInfo = listed.restoreInfo {
            parts.append("\(listed.osName) \(restoreInfo.ios.version) (\(restoreInfo.ios.build))")
            parts.append(String(localized: "cloudOS \(restoreInfo.cloudOS.version)"))
        }
        if let version = bundleVersion ?? model.bundles.defaultVersion {
            parts.append(String(localized: "Core Bundle \(version)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Controls

    /// The preset and what it is, then the filter and the search: on one
    /// line while they fit, as the design lays them out, else on two.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DK.Space.s3) {
                presetControls
                Spacer(minLength: DK.Space.s2)
                filterControls
            }
            VStack(alignment: .leading, spacing: DK.Space.s3) {
                HStack(spacing: DK.Space.s3) {
                    presetControls
                    Spacer(minLength: 0)
                }
                HStack(spacing: DK.Space.s3) {
                    Spacer(minLength: 0)
                    filterControls
                }
            }
        }
    }

    private var presetControls: some View {
        HStack(spacing: DK.Space.s3) {
            Text("Preset")
                .foregroundStyle(DK.Palette.inkSecondary)
            // The label sits beside the menu, so the picker's own is hidden.
            Picker("Preset", selection: presetBinding) {
                ForEach(catalog?.presets ?? []) { preset in
                    Text(verbatim: preset.displayTitle).tag(preset.identifier)
                }
            }
            .dkFieldPicker()
            .disabled(catalog == nil || isLoading)
            if isLoading {
                ProgressView().controlSize(.small)
            }
            if let summary = catalog?.preset(selection.preset)?.displaySummary, !summary.isEmpty {
                Text(verbatim: summary)
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)
                    .lineLimit(2)
                    .frame(maxWidth: 360, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var filterControls: some View {
        HStack(spacing: DK.Space.s3) {
            DKSegmented(String(localized: "Show"), selection: $filter, options: filterOptions)
                .disabled(catalog == nil)
                .fixedSize()
            DKSearchField(String(localized: "Filter patches"), text: $search, width: 200)
        }
    }

    /// Switching preset clears both override lists: the switches are read as a
    /// difference from the preset, so a difference from the one just left behind
    /// would silently change meaning.
    private var presetBinding: Binding<String> {
        Binding(
            get: { selection.preset },
            set: { identifier in
                guard identifier != selection.preset else {
                    return
                }
                selection = VPhoneLaunchpadPatchSelection(preset: identifier)
                Task { await load(preset: identifier) }
            },
        )
    }

    private var filterOptions: [DKSegmentOption<Filter>] {
        let tally = tally
        var options = [DKSegmentOption(String(localized: "All"), value: Filter.all, count: tally?.total ?? 0)]
        if let pending = tally?.pending {
            options.append(DKSegmentOption(String(localized: "Not Applied"), value: .notApplied, count: pending))
        }
        options.append(DKSegmentOption(String(localized: "Changed"), value: .changed, count: tally?.changed ?? 0))
        options.append(DKSegmentOption(String(localized: "Off"), value: .off, count: (tally?.total ?? 0) - (tally?.on ?? 0)))
        return options
    }

    /// The counts the filters, the not-applied groups and the status line
    /// show, once the catalogue is read.
    private var tally: VPhoneLaunchpadPatchTally? {
        catalog.map {
            VPhoneLaunchpadPatchTally(catalog: $0, selection: selection, initiallyOn: initiallyOn, isMachine: machine != nil)
        }
    }

    // MARK: - Not applied

    private func pendingSection(_ catalog: Catalog) -> some View {
        let tally = VPhoneLaunchpadPatchTally(catalog: catalog, selection: selection, initiallyOn: initiallyOn, isMachine: machine != nil)
        let count = tally.pending ?? 0
        let title = machine.map {
            String(AttributedString(localized: "^[\(count) patch](inflect: true) not applied to \($0.name)").characters)
        } ?? ""
        return Group {
            if count > 0 {
                VPhoneLaunchpadPatchPendingGroups(
                    title: title,
                    installed: catalog.installed != false,
                    pending: tally.pendingByDelivery,
                )
            }
        }
    }

    // MARK: - Patches

    @ViewBuilder
    private var list: some View {
        Group {
            if let catalog {
                DKCard {
                    DKDataTable(
                        String(localized: "Patches"),
                        columns: columns.map(\.column),
                        groups: groups(catalog),
                        selection: $highlighted,
                        rowStyle: .plain,
                        emptyText: String(localized: "No patch matches."),
                        highlight: { isPending($0) == true ? .warning : nil },
                    ) { patch, index in
                        cell(patch, columns[index])
                    }
                }
            } else if let loadError {
                DKCard(.padded, fillsHeight: true) {
                    Label {
                        Text("No Patch List").font(DK.Typeface.bodyStrong)
                    } icon: {
                        DKIcon(.warning, size: 15).foregroundStyle(DK.Palette.warning)
                    }
                    Text(verbatim: loadError)
                        .foregroundStyle(DK.Palette.muted)
                        .textSelection(.enabled)
                }
            } else {
                DKCard(.padded, fillsHeight: true) {
                    HStack(spacing: DK.Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Reading the bundle's patches…").foregroundStyle(DK.Palette.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: tableHeight)
    }

    /// One group per patch set, in the order the bundle applies them, with the
    /// rows the filter and search leave.
    private func groups(_ catalog: Catalog) -> [DKTableGroup<Catalog.Patch>] {
        let rows = catalog.patches(matching: search).filter(matchesFilter)
        let order = Dictionary(catalog.patches.enumerated().map { ($1.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        var sets: [String] = []
        var bySet: [String: [Catalog.Patch]] = [:]
        for patch in catalog.patches where bySet[patch.patchSet] == nil {
            sets.append(patch.patchSet)
            bySet[patch.patchSet] = []
        }
        for patch in rows {
            bySet[patch.patchSet, default: []].append(patch)
        }
        return sets.compactMap { set in
            guard let members = bySet[set], let first = members.first else {
                return nil
            }
            let total = catalog.patches.count { $0.patchSet == set }
            return DKTableGroup(
                id: set,
                title: first.patchSetName,
                detail: set,
                trailing: String(AttributedString(localized: "^[\(total) patch](inflect: true)").characters),
                rows: members.sorted { (order[$0.identifier] ?? 0) < (order[$1.identifier] ?? 0) },
            )
        }
    }

    private func matchesFilter(_ patch: Catalog.Patch) -> Bool {
        switch filter {
        case .all: true
        case .notApplied: isPending(patch) == true
        case .changed: isChanged(patch)
        case .off: !selection.isOn(patch)
        }
    }

    /// The table's columns. Status needs to know what the guest runs, so it
    /// shows only for a machine whose bundle records that.
    private var columns: [Column] {
        Column.allCases.filter { $0 != .status || showsStatus }
    }

    @ViewBuilder
    private func cell(_ patch: Catalog.Patch, _ column: Column) -> some View {
        switch column {
        case .on:
            DKSwitch(patch.title, isOn: Binding(
                get: { selection.isOn(patch) },
                set: {
                    selection.set(patch, on: $0)
                    highlighted = patch.identifier
                },
            ))
        case .patch:
            patchCell(patch)
        case .part:
            Text(verbatim: Self.partLabel(patch))
                .font(DK.Typeface.mono)
                .foregroundStyle(DK.Palette.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(patch.part ?? patch.target)
        case .delivery:
            DKBadge(patch.deliveryKind.label, tone: patch.deliveryKind.tone)
        case .status:
            statusCell(patch)
        case .appliesTo:
            Text(verbatim: patch.isVersionGated ? patch.applicability : String(localized: "All"))
                .font(DK.Typeface.caption)
                .foregroundStyle(DK.Palette.muted)
                .lineLimit(1)
                .help(patch.isVersionGated ? patch.applicability : "")
        }
    }

    // Most patches are boot-essential, so a mark on each would say nothing.
    // It shows only on one that is off.
    private func patchCell(_ patch: Catalog.Patch) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(verbatim: patch.title)
                    .font(isPending(patch) == true ? DK.Typeface.bodyStrong : DK.Typeface.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if patch.bootEssential, !selection.isOn(patch) {
                    DKIcon(.warning, size: 13)
                        .foregroundStyle(DK.Palette.warning)
                        .help(String(localized: "The machine may not boot without this patch."))
                }
            }
            Text(verbatim: patch.identifier)
                .font(DK.Typeface.monoSmall)
                .foregroundStyle(DK.Palette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(patch.summary)
    }

    private func statusCell(_ patch: Catalog.Patch) -> some View {
        let isOn = selection.isOn(patch)
        let (text, color, pending): (String, Color, Bool) = switch isPending(patch) {
        case true?:
            (isOn ? String(localized: "Not applied · turns on") : String(localized: "Not applied · turns off"), DK.Palette.warningInk, true)
        case false?:
            isOn ? (String(localized: "Applied"), DK.Palette.successInk, false) : (String(localized: "Off"), DK.Palette.muted, false)
        case nil:
            (isOn ? String(localized: "On") : String(localized: "Off"), DK.Palette.muted, false)
        }
        return Text(verbatim: text)
            .font(pending ? DK.Typeface.captionStrong : DK.Typeface.caption)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        DKCard(.padded) {
            if let patch = catalog?.patch(highlighted) {
                VStack(alignment: .leading, spacing: DK.Space.s1) {
                    HStack(alignment: .firstTextBaseline, spacing: DK.Space.s2) {
                        Text(verbatim: patch.title)
                            .font(DK.Typeface.bodyStrong)
                            .lineLimit(1)
                        Text(verbatim: patch.identifier)
                            .font(DK.Typeface.monoSmall)
                            .foregroundStyle(DK.Palette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Text(verbatim: patch.summary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: facts(patch).joined(separator: " · "))
                        .font(DK.Typeface.caption)
                        .foregroundStyle(DK.Palette.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            } else {
                Text("Select a patch to see what it changes.")
                    .foregroundStyle(DK.Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            }
        }
    }

    /// The line under a patch's summary: where it comes from and lands, how a
    /// change reaches an installed guest, what it applies to, and whether the
    /// machine boots without it.
    private func facts(_ patch: Catalog.Patch) -> [String] {
        var facts = [patch.patchSetName]
        if let part = patch.part, part != patch.target {
            facts.append("\(part) (\(patch.target))")
        } else {
            facts.append(patch.target)
        }
        facts.append(Self.reach(patch))
        facts.append(patch.isVersionGated ? patch.applicability : String(localized: "Every release"))
        if machine != nil, patch.isGatedOut {
            facts.append(String(localized: "Not for this machine’s OS"))
        }
        if patch.bootEssential {
            facts.append(String(localized: "Required to boot"))
        }
        return facts
    }

    private static func reach(_ patch: Catalog.Patch) -> String {
        switch patch.deliveryKind {
        case .updateEnvironment: String(localized: "Apply to Guest turns it on or off in place")
        case .updateKernel: String(localized: "Update Kernel swaps it into Preboot, keeping the data")
        case .firmwarePatch: String(localized: "fw patch rewrites AVPBooter in the machine folder; it takes effect at the next boot")
        case .restore where patch.isRestoreOnlyStage: String(localized: "Used only while restoring; a change matters at the next restore")
        case .restore: String(localized: "Only a restore applies it, which erases the data")
        }
    }

    /// The part column: the component a boot-chain patch lands in, or the last
    /// path component of a guest file, so the column stays narrow.
    private static func partLabel(_ patch: Catalog.Patch) -> String {
        let target = patch.target
        guard target.hasPrefix("/") else {
            return target
        }
        return (target as NSString).lastPathComponent
    }

    private var essentialOffText: String {
        let names = essentialOff.prefix(6).map(\.identifier).joined(separator: ", ")
        let rest = essentialOff.count - min(essentialOff.count, 6)
        let list = rest > 0 ? String(localized: "\(names) and \(rest) more") : names
        let count = String(AttributedString(localized: "^[\(essentialOff.count) boot-essential patch](inflect: true) off").characters)
        return String(localized: "\(count): \(list). The machine may not boot without them.")
    }

    // MARK: - State

    /// Whether the bundle reports what this machine's guest runs, which the
    /// status column and the not-applied groups need.
    private var showsStatus: Bool {
        catalog.map { VPhoneLaunchpadPatchTally.showsStatus($0, isMachine: machine != nil) } ?? false
    }

    /// Whether the switch as it stands has still to reach the guest.
    private func isPending(_ patch: Catalog.Patch) -> Bool? {
        VPhoneLaunchpadPatchTally.isPending(patch, selection: selection, initiallyOn: initiallyOn, isMachine: machine != nil)
    }

    /// Whether the switch differs from the preset.
    private func isChanged(_ patch: Catalog.Patch) -> Bool {
        selection.isOn(patch) != patch.inPreset
    }

    /// What is on, what differs from the preset, and where the choice stands.
    private var status: String {
        guard let catalog, let tally else {
            return ""
        }
        var parts = [String(localized: "\(tally.on) of \(tally.total) on")]
        if tally.changed > 0 {
            let preset = catalog.preset(selection.preset)?.displayTitle ?? selection.preset
            parts.append(String(localized: "\(tally.changed) changed from \(preset)"))
        }
        if machine == nil {
            parts.append(String(localized: "Applied when the machine is installed"))
        } else {
            if let pending = tally.pending {
                parts.append(pending == 0 ? String(localized: "Everything applied") : String(localized: "\(pending) not applied"))
            }
            if tally.edited > 0 {
                parts.append(String(AttributedString(localized: "^[\(tally.edited) change](inflect: true) to save").characters))
            } else if tally.pending == nil {
                parts.append(String(localized: "No change"))
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Gives the table whatever height makes the content fill the sheet.
    ///
    /// `DKSheet` is as tall as its content, and the content is the table plus
    /// sections whose height depends on their text. The table takes what is
    /// left of the sheet after the sheet's own head and footer (`chrome`) and
    /// the rest of the content, both measured apart from the table, so the
    /// result does not depend on the table's last height and one step settles
    /// it. (Steering by the sheet's measured height instead oscillates:
    /// `DKSheet` sizes its body a layout pass after its content changes.)
    /// Below the minimum the sheet's body scrolls.
    private func settleTable() {
        guard contentHeight > 0, chromeHeight > 0, availableHeight > 0 else {
            return
        }
        let others = contentHeight - renderedTableHeight
        let next = max(Self.minimumTableHeight, (availableHeight - chromeHeight - others).rounded(.down))
        if abs(next - tableHeight) > 0.5 {
            tableHeight = next
        }
    }

    /// The sheet with nothing in its body, laid out unseen behind the real one
    /// to measure its head, footer and body padding. Its buttons answer no key.
    private var chrome: some View {
        DKSheet(
            title,
            subtitle: subtitle,
            width: nil,
            note: DKSheetNote(status),
            trailing: [
                DKSheetAction(String(localized: "Cancel"), role: .plain) {},
                DKSheetAction(saveLabel, variant: .primary, role: .plain) {},
            ],
        ) {
            EmptyView()
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
            chromeHeight = height
            settleTable()
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    private func load(preset: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let catalog = try await Catalog.read(
                using: bundleVersion.map(model.bundles.commandLine(version:)) ?? model.bundles.commandLine(),
                machine: machine,
                preset: preset,
            )
            // A second switch of the picker may have overtaken this read.
            guard preset == selection.preset else {
                return
            }
            selection.preset = catalog.activePreset
            selection.normalize(against: catalog)
            if initiallyOn == nil {
                initiallyOn = Set(catalog.patches.filter { selection.isOn($0) }.map(\.identifier))
            }
            self.catalog = catalog
            if filter == .notApplied, !showsStatus {
                filter = .all
            }
            // The detail card reserves its space either way, so it starts with
            // something to read rather than a gap.
            highlighted = highlighted ?? catalog.patches.first?.identifier
            loadError = nil
        } catch {
            loadError = VPhoneLaunchpadError.message(for: error)
        }
    }

    private func commit() {
        if essentialOff.isEmpty {
            finish()
        } else {
            confirmsBootEssential = true
        }
    }

    private func finish() {
        onSave(selection)
        dismiss()
    }
}

// MARK: - Table model

extension VPhoneLaunchpadPatchSettingsView {
    /// Which rows the table shows.
    enum Filter: Hashable {
        case all
        case notApplied
        case changed
        case off
    }

    enum Column: CaseIterable {
        case on, patch, part, delivery, status, appliesTo

        var column: DKTableColumn {
            switch self {
            case .on: DKTableColumn(String(localized: "On"), width: .fixed(44))
            case .patch: DKTableColumn(String(localized: "Patch"), width: .flexible(min: 240, weight: 2.4))
            case .part: DKTableColumn(String(localized: "Part"), width: .fixed(130))
            case .delivery: DKTableColumn(String(localized: "Reaches the guest by"), width: .fixed(130))
            case .status: DKTableColumn(String(localized: "Status"), width: .fixed(156))
            case .appliesTo: DKTableColumn(String(localized: "Applies To"), width: .flexible(min: 96, weight: 0.6))
            }
        }
    }
}
