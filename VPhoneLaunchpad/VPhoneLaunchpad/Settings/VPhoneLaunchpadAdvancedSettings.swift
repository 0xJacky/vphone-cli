import AppKit
import SwiftUI
import VPhoneDesignKit

/// The privileged helper, the host checks the user skipped, and where the
/// command-line client lives.
struct VPhoneLaunchpadAdvancedSettings: View {
    @Environment(VPhoneLaunchpadModel.self) private var model

    private var host: VPhoneLaunchpadHostSetup {
        model.host
    }

    var body: some View {
        VPhoneLaunchpadSettingsPage {
            DKSection(
                String(localized: "Privileged Helper"),
                footnote: String(localized: "\(VPhoneLaunchpadHelperIdentity.label) installs Core Bundles, allows each bundle’s vphone-vm to run, installs custom firmware and releases old guest addresses. Host Setup installs and updates it."),
            ) {
                DKFormRow(String(localized: "Status"), fill: true) {
                    let (text, tone) = helperStatus
                    DKStatusDot(tone)
                    Text(text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
            skippedChecks
            DKSection(
                String(localized: "Command Line"),
                footnote: String(localized: "vphone-launchpad-cli talks to the running app over this socket, as the same user."),
            ) {
                DKListRow(DKListItem(
                    "vphone-launchpad-cli",
                    monospacedTitle: true,
                    lines: [DKListItem.Line(Self.cliPath)],
                    actions: [DKButtonSpec(String(localized: "Copy Path"), glyph: .copy) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.cliPath, forType: .string)
                    }],
                ))
                DKKeyValueRow(DKKeyValue(
                    String(localized: "Socket"),
                    VPhoneLaunchpadHostSetup.abbreviated(URL(fileURLWithPath: VPhoneLaunchpadControl.socketPath)),
                    monospaced: true,
                ))
            }
        }
    }

    // MARK: - Host checks

    @ViewBuilder
    private var skippedChecks: some View {
        let skipped = host.checks.filter { host.skipped.contains($0.kind) }
        DKSection(
            String(localized: "Host Checks"),
            footnote: String(localized: "A skipped check does not hold up setup; the Core Bundle still runs its own checks. Check Again counts it again."),
        ) {
            if skipped.isEmpty {
                Text("No host checks are skipped.")
                    .font(DK.Typeface.body)
                    .foregroundStyle(DK.Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 14)
            } else {
                ForEach(skipped) { check in
                    DKListRow(DKListItem(
                        check.title,
                        lines: [DKListItem.Line(
                            check.status == .passed ? String(localized: "Passes now") : check.detail,
                            tone: check.status == .passed ? nil : check.status.settingsTone,
                        )],
                        actions: [DKButtonSpec(String(localized: "Check Again"), isEnabled: !host.isChecking) {
                            host.setSkipped(check.kind, false)
                            Task { await host.refresh() }
                        }],
                        id: check.kind.rawValue,
                    ))
                }
            }
        }
    }

    // MARK: - Helper

    private var helperStatus: (String, DKTone) {
        switch model.helper.state {
        case .unknown:
            (String(localized: "Checking…"), .idle)
        case .notInstalled:
            (String(localized: "Not installed"), .warning)
        case let .outdated(installed, bundled):
            (String(localized: "Version \(installed) installed, \(bundled) available"), .warning)
        case let .ready(version):
            (String(localized: "Version \(version) installed"), .success)
        case .unconfigured:
            (String(localized: "Not available in this build"), .danger)
        }
    }

    /// The client is a tool beside the app's own executable.
    static var cliPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/vphone-launchpad-cli").path
    }
}
