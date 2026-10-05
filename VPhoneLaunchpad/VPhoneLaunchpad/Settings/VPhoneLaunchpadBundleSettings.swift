import SwiftUI
import VPhoneDesignKit

/// The default Core Bundle, and the bundles kept in use without preflight.
struct VPhoneLaunchpadBundleSettings: View {
    @Environment(VPhoneLaunchpadModel.self) private var model

    private var bundles: VPhoneLaunchpadCoreBundle {
        model.bundles
    }

    var body: some View {
        let versions = bundles.selectableVersions
        let accepted = bundles.installed.map(\.version).filter(bundles.isAccepted)
        VPhoneLaunchpadSettingsPage {
            DKSection(
                String(localized: "Default"),
                footnote: String(localized: "New machines are bound to this bundle, and commands that belong to no machine run with it. Each machine keeps its own bundle until you change it."),
            ) {
                DKFormRow(String(localized: "Core Bundle")) {
                    if versions.isEmpty {
                        Text("None installed")
                            .foregroundStyle(DK.Palette.muted)
                    } else {
                        Picker(String(localized: "Core Bundle"), selection: defaultVersion) {
                            ForEach(versions, id: \.self) { version in
                                Text(verbatim: version)
                                    .font(DK.Typeface.mono)
                                    .tag(version)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(bundles.isInstalling)
                    }
                }
                if let bundle = bundles.defaultBundle {
                    DKKeyValueRow(DKKeyValue(
                        String(localized: "Host Preflight"),
                        preflightSummary(bundle),
                        tone: bundles.isAccepted(bundle.version) && bundle.preflight != .passed
                            ? .warning
                            : bundle.preflight.settingsTone,
                    ))
                }
            }
            if !accepted.isEmpty {
                DKSection(
                    String(localized: "Used Without Preflight"),
                    footnote: String(localized: "These bundles may be used although host preflight failed. Require Preflight checks them again before use."),
                ) {
                    ForEach(accepted, id: \.self) { version in
                        DKListRow(DKListItem(
                            version,
                            glyph: .bundle,
                            monospacedTitle: true,
                            actions: [DKButtonSpec(String(localized: "Require Preflight")) {
                                bundles.setAccepted(version, false)
                            }],
                        ))
                    }
                }
            }
        }
    }

    private var defaultVersion: Binding<String> {
        Binding(
            get: { bundles.defaultVersion ?? "" },
            set: { version in
                guard version != bundles.defaultVersion else { return }
                Task { await bundles.setDefault(version) }
            },
        )
    }

    private func preflightSummary(_ bundle: VPhoneLaunchpadCoreBundle.Installed) -> String {
        if bundle.preflight != .passed, bundles.isAccepted(bundle.version) {
            return String(localized: "Used without preflight")
        }
        switch bundle.preflight {
        case .passed: return String(localized: "Passed")
        case .running: return String(localized: "Checking…")
        case .pending: return String(localized: "Not run yet")
        case .warning, .failed:
            return bundle.preflightDetail.isEmpty ? String(localized: "Failed") : bundle.preflightDetail
        }
    }
}
