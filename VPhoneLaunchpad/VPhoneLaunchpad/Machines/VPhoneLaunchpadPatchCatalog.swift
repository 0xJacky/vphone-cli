import Foundation

// MARK: - fw patches --json

/// Mirrors the payload `vphone-cli fw patches --json` prints.
///
/// The app declares no patch of its own. Everything the editor lists comes from
/// the Core Bundle it is read from, so a patch set this build of Launchpad has
/// never heard of still appears, with its own patches and version gates.
nonisolated struct VPhoneLaunchpadPatchCatalog: Decodable, Sendable {
    struct Preset: Decodable, Hashable, Identifiable, Sendable {
        let identifier: String
        let title: String
        let summary: String

        var id: String {
            identifier
        }

        /// The bundle writes its built-in presets in English. Launchpad
        /// translates those two; any other preset shows its own text.
        var displayTitle: String {
            switch identifier {
            case "standard": String(localized: "Standard", comment: "The built-in patch preset")
            case "experimental": String(localized: "Experimental", comment: "The built-in patch preset")
            default: title
            }
        }

        var displaySummary: String {
            switch identifier {
            case "standard": String(localized: "Patches every machine needs to start, with a working display and camera.")
            case "experimental": String(localized: "Every patch in this bundle, including advanced ones that may stop a newly restored 26.4 machine from starting.")
            default: summary
            }
        }
    }

    struct Patch: Decodable, Hashable, Identifiable, Sendable {
        let identifier: String
        let title: String
        let summary: String
        let patchSet: String
        let patchSetName: String
        let target: String
        /// The OS versions the patch is declared for, or `any`.
        let applicability: String
        let bootEssential: Bool
        /// Whether the preset the report was made against turns it on. What the
        /// checkmarks are a difference from.
        let inPreset: Bool
        /// Whether the machine's wanted state for this patch has not reached its
        /// guest yet. Reported only for a named machine, by a bundle that
        /// compares its records; nil otherwise.
        let pending: Bool?
        /// Where the patch lives in a machine: a boot-chain component's name,
        /// or `Guest`. Reported only for a named machine; nil otherwise.
        let part: String?
        /// The step that delivers this patch to an installed guest, reported by
        /// the machine's own bundle only for a pending patch:
        /// `update-environment`, `update-kernel`, `fw-patch` or
        /// `restore`. A bundle without `cfw update-kernel` never reports
        /// `update-kernel`, so the kernel button keyed on it simply
        /// does not appear there. Nil when not pending or not reported.
        let delivery: String?
        /// Whether the machine's saved choice leaves the patch on, before any
        /// version gate. Absent from an older bundle.
        let enabled: Bool?
        /// Whether the machine's saved choice wants the patch once the version
        /// gate has run against its OS pairing. Reported only for a named
        /// machine, alongside `pending`; nil otherwise.
        let wanted: Bool?

        var id: String {
            identifier
        }

        /// Whether the patch is in the boot chain, which only a restore
        /// changes on a machine that exists. Read from `part` when the bundle
        /// reports it, else from `target`, which names the component the same
        /// way for a boot-chain patch.
        var isBootChain: Bool {
            Self.bootChainParts.contains(part ?? target)
        }

        /// The kernelcache, which `cfw update-kernel` changes without a restore.
        var isKernel: Bool {
            (part ?? target) == "kernelcache"
        }

        private static let bootChainParts: Set<String> = [
            "AVPBooter", "iBSS", "iBEC", "LLB", "TXM", "kernelcache", "DeviceTree",
        ]

        /// False when the patch applies to every version, which is not worth a
        /// column entry.
        var isVersionGated: Bool {
            applicability != "any"
        }

        /// What the patch changes: `kernel`, `dyld`, `system-seputil`.
        var component: String {
            parts.component
        }

        /// Why it is there: `boot`, `cfw` or `exp`.
        var effect: String {
            parts.effect
        }

        /// The patch's own name within its component and effect.
        var name: String {
            parts.name
        }

        /// Splits `{component}-{effect}-{name}`, read from the right: the name
        /// holds no hyphen, and a component may (`system-seputil`). Every
        /// bundled patch follows this; an outside set that names its patches
        /// another way keeps its identifier whole as the name.
        private var parts: (component: String, effect: String, name: String) {
            let segments = identifier.split(separator: "-", omittingEmptySubsequences: false)
            guard segments.count >= 3,
                  Self.effects.contains(String(segments[segments.count - 2]))
            else {
                return ("", "", identifier)
            }
            return (
                segments.dropLast(2).joined(separator: "-"),
                String(segments[segments.count - 2]),
                String(segments[segments.count - 1]),
            )
        }

        private static let effects: Set<String> = ["boot", "cfw", "exp"]
    }

    /// The preset this report was made against: the VM's own, or the one `--preset`
    /// asked for.
    let activePreset: String
    let blockedPatches: [String]
    let allowedPatches: [String]
    let presets: [Preset]
    let patches: [Patch]

    // Reported only for a named machine, and only by a bundle that compares a
    // machine's records. An older bundle leaves them out, and every reader
    // treats their absence as "not known".

    /// Whether `cfw install` finished on the machine; nil when unknown.
    let installed: Bool?
    /// Whether the machine has a receipt saying what its guest runs.
    let receiptRecorded: Bool?
    /// How many patches differ from what the machine's guest has, or nil when
    /// nothing records what it has.
    let pendingPatches: Int?

    /// The overrides the machine's choice makes on its preset.
    var overrideCount: Int {
        blockedPatches.count + allowedPatches.count
    }

    /// The machine's own choice, as the editor starts from it.
    var selection: VPhoneLaunchpadPatchSelection {
        VPhoneLaunchpadPatchSelection(
            preset: activePreset,
            blocked: Set(blockedPatches),
            allowed: Set(allowedPatches),
        )
    }

    /// Pending patches `cfw update-environment` brings in line (the bundle's
    /// own classification; falls back to the part for a bundle that does not
    /// report delivery).
    var pendingGuestPatches: Int {
        patches.count { $0.pending == true && ($0.delivery ?? (!$0.isBootChain ? "update-environment" : "")) == "update-environment" }
    }

    /// Pending kernelcache patches `cfw update-kernel` applies without a
    /// restore. Keyed on the delivery the machine's bundle reports, so a bundle
    /// without the verb never counts any here and the button stays hidden.
    var pendingKernelPatches: Int {
        patches.count { $0.pending == true && $0.delivery == "update-kernel" }
    }

    /// Pending boot-chain patches that only an erasing restore applies.
    var pendingRestorePatches: Int {
        patches.count { $0.pending == true && ($0.delivery ?? (($0.isBootChain && !$0.isKernel) ? "restore" : "")) == "restore" }
    }

    func preset(_ identifier: String) -> Preset? {
        presets.first { $0.identifier == identifier }
    }

    func patch(_ identifier: String?) -> Patch? {
        identifier.flatMap { needle in patches.first { $0.identifier == needle } }
    }

    /// The patches matching `filter`, in the order the bundle applies them, which
    /// already runs one set after another.
    func patches(matching filter: String) -> [Patch] {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else {
            return patches
        }
        return patches.filter { Self.matches($0, needle) }
    }

    private static func matches(_ patch: Patch, _ needle: String) -> Bool {
        [patch.title, patch.identifier, patch.summary, patch.patchSetName, patch.target]
            .contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

// MARK: - Delivery

nonisolated extension VPhoneLaunchpadPatchCatalog {
    /// The step that carries a change to a patch into an installed guest,
    /// mirroring `FirmwarePatchDelivery` in the bundle. The order is the
    /// order the editor lists them in, cheapest first.
    enum Delivery: String, CaseIterable, Identifiable, Sendable {
        case updateEnvironment = "update-environment"
        case updateKernel = "update-kernel"
        case firmwarePatch = "fw-patch"
        case restore

        var id: String {
            rawValue
        }
    }
}

nonisolated extension VPhoneLaunchpadPatchCatalog.Patch {
    /// The step that delivers this patch: the bundle's own word for a pending
    /// patch, else the bundle's rule read from where the patch lands, so a
    /// patch that is not pending (or a catalogue read for New Machine) still
    /// says how a change to it would arrive.
    var deliveryKind: VPhoneLaunchpadPatchCatalog.Delivery {
        if let delivery, let reported = VPhoneLaunchpadPatchCatalog.Delivery(rawValue: delivery) {
            return reported
        }
        switch part ?? target {
        case "AVPBooter": return .firmwarePatch
        case "kernelcache": return .updateKernel
        default: return isBootChain ? .restore : .updateEnvironment
        }
    }

    /// Whether iBSS or iBEC carries it: used only while restoring, so a change
    /// matters at the next restore and not to the guest already installed.
    var isRestoreOnlyStage: Bool {
        ["iBSS", "iBEC"].contains(part ?? target)
    }

    /// What the guest is believed to run for this patch (the receipt, else
    /// the last `fw patch`), recovered from the bundle's `pending` and what
    /// the saved choice wants. `savedOn` stands in for `wanted` from a bundle
    /// that does not report it. Nil when nothing records what the guest runs.
    func isLive(savedOn: Bool) -> Bool? {
        pending.map { pending in
            let wanted = wanted ?? savedOn
            return pending ? !wanted : wanted
        }
    }

    /// Whether the machine's saved choice turns the patch on but its version
    /// gate leaves it out for this machine's OS pairing, so turning it on
    /// changes nothing in the guest.
    var isGatedOut: Bool {
        enabled == true && wanted == false
    }

    /// Whether a choice that leaves this patch `on` still has to reach the
    /// guest, given what the saved choice had (`savedOn`). Nil when nothing
    /// records what the guest runs. A patch the saved choice never turned on
    /// has an unknown gate and is taken to pass it.
    func isPending(on: Bool, savedOn: Bool) -> Bool? {
        isLive(savedOn: savedOn).map { $0 != (on && !isGatedOut) }
    }
}

// MARK: - Tally

/// What the patch editor counts for its filters, its status line and its
/// not-applied groups, from a catalogue and the switches as they stand.
nonisolated struct VPhoneLaunchpadPatchTally: Equatable, Sendable {
    typealias Catalog = VPhoneLaunchpadPatchCatalog

    let total: Int
    let on: Int
    /// Switches that differ from the preset.
    let changed: Int
    /// Switches that differ from what was on when the editor opened.
    let edited: Int
    /// Patches whose switch has still to reach the guest; nil when nothing
    /// records what the guest runs (New Machine, or an older bundle).
    let pending: Int?
    /// The pending patches by the step that delivers them, in catalogue order.
    let pendingByDelivery: [Catalog.Delivery: [String]]

    /// `initiallyOn` is what was on when the editor opened; nil before the
    /// first read, when nothing is edited yet. `isMachine` is false in New
    /// Machine, which has no guest to compare with.
    init(catalog: Catalog, selection: VPhoneLaunchpadPatchSelection, initiallyOn: Set<String>?, isMachine: Bool) {
        let patches = catalog.patches
        total = patches.count
        on = patches.count { selection.isOn($0) }
        changed = patches.count { selection.isOn($0) != $0.inPreset }
        edited = initiallyOn.map { initiallyOn in
            patches.count { selection.isOn($0) != initiallyOn.contains($0.identifier) }
        } ?? 0
        if Self.showsStatus(catalog, isMachine: isMachine) {
            let pendingPatches = patches.filter {
                Self.isPending($0, selection: selection, initiallyOn: initiallyOn, isMachine: isMachine) == true
            }
            pending = pendingPatches.count
            pendingByDelivery = Dictionary(grouping: pendingPatches, by: \.deliveryKind).mapValues { $0.map(\.identifier) }
        } else {
            pending = nil
            pendingByDelivery = [:]
        }
    }

    /// Whether the bundle reports what this machine's guest runs, which the
    /// status column and the not-applied groups need.
    static func showsStatus(_ catalog: Catalog, isMachine: Bool) -> Bool {
        isMachine && catalog.patches.contains { $0.pending != nil }
    }

    /// Whether the switch as it stands has still to reach the guest. A patch
    /// counts as saved on as it was when the editor opened.
    static func isPending(
        _ patch: Catalog.Patch,
        selection: VPhoneLaunchpadPatchSelection,
        initiallyOn: Set<String>?,
        isMachine: Bool,
    ) -> Bool? {
        guard isMachine else {
            return nil
        }
        let on = selection.isOn(patch)
        return patch.isPending(on: on, savedOn: initiallyOn?.contains(patch.identifier) ?? on)
    }
}

// MARK: - Selection

/// A VM's patch choice: a preset, plus only the boxes that differ from it.
///
/// This is what `vphone-cli fw set-patches` stores in `<vm>/PatchSelection.plist`.
/// Storing differences rather than a full list is what lets a later preset
/// revision reach a VM whose boxes were never touched.
nonisolated struct VPhoneLaunchpadPatchSelection: Hashable, Sendable {
    /// The preset `vphone-cli` uses when `--preset` is absent, mirroring
    /// `VPhonePatchPreset.standardIdentifier`. Naming it on the command line would
    /// only add noise, so the pipeline omits the flag for this one value.
    static let defaultPreset = "standard"

    var preset = defaultPreset
    /// Patches the preset turns on that this VM leaves off.
    var blocked: Set<String> = []
    /// Patches the preset leaves off that this VM turns on.
    var allowed: Set<String> = []

    var hasOverrides: Bool {
        !blocked.isEmpty || !allowed.isEmpty
    }

    var isDefault: Bool {
        preset == Self.defaultPreset && !hasOverrides
    }

    /// `fw set-patches` arguments, without the VM name or library root. Each run
    /// writes the whole record, so an empty list clears that half of it.
    var setPatchesArguments: [String] {
        ["--preset", preset]
            + blocked.sorted().flatMap { ["--block", $0] }
            + allowed.sorted().flatMap { ["--allow", $0] }
    }

    /// The `--preset` flag `fw patch` and `fw patches` carry, if any.
    var presetArguments: [String] {
        preset == Self.defaultPreset ? [] : ["--preset", preset]
    }

    func isOn(_ patch: VPhoneLaunchpadPatchCatalog.Patch) -> Bool {
        patch.inPreset ? !blocked.contains(patch.identifier) : allowed.contains(patch.identifier)
    }

    /// Records a box the way it differs from the preset, so a patch that agrees
    /// with the preset again lands in neither list.
    mutating func set(_ patch: VPhoneLaunchpadPatchCatalog.Patch, on: Bool) {
        let identifier = patch.identifier
        blocked.remove(identifier)
        allowed.remove(identifier)
        switch (patch.inPreset, on) {
        case (true, false): blocked.insert(identifier)
        case (false, true): allowed.insert(identifier)
        default: break
        }
    }

    /// Drops overrides this catalogue makes meaningless: one the preset already
    /// agrees with, and one naming a patch the bundle no longer declares. A
    /// hand-edited plist, or a bundle whose presets have since changed, would
    /// otherwise show a checkmark that stores nothing.
    mutating func normalize(against catalog: VPhoneLaunchpadPatchCatalog) {
        let inPreset = Set(catalog.patches.filter(\.inPreset).map(\.identifier))
        let declared = Set(catalog.patches.map(\.identifier))
        blocked = blocked.intersection(inPreset)
        allowed = allowed.intersection(declared).subtracting(inPreset)
    }

    /// The boot-essential patches this choice turns off, in catalogue order.
    func bootEssentialOff(in catalog: VPhoneLaunchpadPatchCatalog) -> [VPhoneLaunchpadPatchCatalog.Patch] {
        catalog.patches.filter { $0.bootEssential && !isOn($0) }
    }
}

/// So the inspector can present the editor with the choice it opens on.
extension VPhoneLaunchpadPatchSelection: Identifiable {
    var id: Self {
        self
    }
}
