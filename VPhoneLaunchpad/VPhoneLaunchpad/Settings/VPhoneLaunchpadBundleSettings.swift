import SwiftUI
import VPhoneDesignKit

/// The default Core Bundle, and each installed bundle's preflight on this
/// Mac, with the ones kept in use without it.
struct VPhoneLaunchpadBundleSettings: View {
    @Environment(VPhoneLaunchpadModel.self) private var model

    private var bundles: VPhoneLaunchpadCoreBundle {
        model.bundles
    }

    var body: some View {
        let versions = bundles.selectableVersions
        let checked = bundles.installed.filter { VPhoneLaunchpadNames.isCompatibleBundleVersion($0.version) }
        VPhoneLaunchpadSettingsPage {
            DKSection(String(localized: "Default")) {
                VStack(spacing: 0) {
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
                    VPhoneLaunchpadSettingsHelp(String(localized: "New machines are bound to this bundle, and commands that belong to no machine run with it. Each machine keeps its own bundle until you change it."))
                }
            }
            if !checked.isEmpty {
                DKSection(
                    String(localized: "Preflight"),
                    footnote: String(localized: "A bundle used without preflight runs it again before use once you choose Require Preflight."),
                ) {
                    ForEach(checked) { bundle in
                        DKListRow(preflightItem(bundle))
                    }
                }
            }
        }
    }

    private func preflightItem(_ bundle: VPhoneLaunchpadCoreBundle.Installed) -> DKListItem {
        let isAccepted = bundles.isAccepted(bundle.version)
        let tone: DKTone? = if isAccepted, bundle.preflight != .passed {
            .warning
        } else if bundle.preflight == .failed || bundle.preflight == .warning {
            .danger
        } else {
            nil
        }
        var actions: [DKButtonSpec] = []
        if isAccepted {
            actions.append(DKButtonSpec(String(localized: "Require Preflight")) {
                bundles.setAccepted(bundle.version, false)
            })
        }
        return DKListItem(
            bundle.version,
            monospacedTitle: true,
            lines: [DKListItem.Line(
                VPhoneLaunchpadBundleText.preflightSummary(
                    preflight: bundle.preflight,
                    detail: bundle.preflightDetail,
                    isAccepted: isAccepted,
                ),
                tone: tone,
            )],
            actions: actions,
            id: bundle.version,
        )
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
}
