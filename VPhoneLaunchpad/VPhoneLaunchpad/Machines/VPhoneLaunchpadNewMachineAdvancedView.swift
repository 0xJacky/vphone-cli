import SwiftUI
import VPhoneDesignKit

/// New Machine's Advanced page: network, restore options and patches, as
/// sections of New Machine's sheet. It edits New Machine's own state.
struct VPhoneLaunchpadNewMachineAdvancedView: View {
    @Binding var network: String
    @Binding var patches: VPhoneLaunchpadPatchSelection
    @Binding var keepArtifacts: Bool
    let patchCatalog: VPhoneLaunchpadPatchCatalog?
    let patchCatalogError: String?
    /// New Machine owns the catalog, which is read again for each preset.
    let reloadPatches: () -> Void
    /// The Core Bundle chosen in New Machine, whose patches the editor lists.
    /// Nil reads the default version's.
    var bundleVersion: String?

    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var showsPatchSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s4) {
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
                if network == "tunnel" {
                    VPhoneLaunchpadCardMessage(text: Text("Traffic leaves through this Mac's own connections, so it follows the Mac's VPN."))
                }
            }

            DKSection(String(localized: "Options")) {
                VPhoneLaunchpadSwitchRow(isOn: $keepArtifacts) {
                    Text("Keep prepared restore files")
                }
            }

            patchSection
        }
    }

    // MARK: - Patches

    private var patchSection: some View {
        VPhoneLaunchpadSheetSection(String(localized: "Patches")) {
            if let patchCatalog {
                DKFormRow(String(localized: "Preset"), fill: true) {
                    Picker("Preset", selection: presetBinding) {
                        ForEach(patchCatalog.presets) { preset in
                            Text(verbatim: preset.displayTitle).tag(preset.identifier)
                        }
                    }
                    .dkFieldPicker(fill: true)
                }
                DKFormRow(String(localized: "Patches"), fill: true) {
                    Text("Differs from the preset: \(patches.blocked.count) off, \(patches.allowed.count) on.")
                        .foregroundStyle(DK.Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    DKButton(String(localized: "Patch Settings…"), size: .small) { showsPatchSettings = true }
                        .sheet(isPresented: $showsPatchSettings) {
                            VPhoneLaunchpadPatchSettingsView(initial: patches, bundleVersion: bundleVersion) { selection in
                                patches = selection
                                reloadPatches()
                            }
                            .environment(model)
                        }
                }
            } else if let patchCatalogError {
                VPhoneLaunchpadCardMessage(text: Text(verbatim: patchCatalogError), isWarning: true)
            } else {
                VPhoneLaunchpadCardLoading(text: Text("Reading the bundle's patches…"))
            }
        } footnote: {
            patchNote
        }
    }

    @ViewBuilder
    private var patchNote: some View {
        let essentialOff = patchCatalog.map { patches.bootEssentialOff(in: $0) } ?? []
        if let summary = patchCatalog?.preset(patches.preset)?.displaySummary, !summary.isEmpty {
            Text(verbatim: summary)
        }
        if !essentialOff.isEmpty {
            Label {
                Text("^[\(essentialOff.count) boot-essential patch](inflect: true) off: \(essentialOff.map(\.identifier).joined(separator: ", "))")
            } icon: {
                DKIcon(.warning, size: 12)
            }
            .foregroundStyle(DK.Palette.warningInk)
        }
    }

    /// Switching preset here re-bases the overrides for the same reason the editor
    /// does: they are read as a difference from whichever preset is active.
    private var presetBinding: Binding<String> {
        Binding(
            get: { patches.preset },
            set: { identifier in
                guard identifier != patches.preset else {
                    return
                }
                patches = VPhoneLaunchpadPatchSelection(preset: identifier)
                reloadPatches()
            },
        )
    }
}
