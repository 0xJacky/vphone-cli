import SwiftUI
import VPhoneDesignKit

/// The last Core Bundle install, as a sheet of its own. It opens when an
/// install starts and again on launch if the last one did not finish. Hiding
/// it leaves the install running; Core Bundles offers it again until then.
struct VPhoneLaunchpadInstallView: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var bundles: VPhoneLaunchpadCoreBundle {
        model.bundles
    }

    var body: some View {
        VPhoneLaunchpadSheet(Text("Core Bundle Install")) {
            ScrollView {
                VStack(alignment: .leading, spacing: DK.Space.s4) {
                    if let progress = bundles.progress {
                        DKSection {
                            summary(progress)
                        }
                        if let error = progress.error {
                            DKBanner(error.message, tone: progress.canSkip ? .warning : .danger)
                            if let detail = error.detail, !detail.isEmpty {
                                DKSection(String(localized: "Details"), card: false) {
                                    DKCard(.padded) {
                                        Text(detail)
                                            .font(DK.Typeface.mono)
                                            .foregroundStyle(DK.Palette.inkSecondary)
                                            .lineLimit(8)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        DKSection(String(localized: "Steps"), card: false) {
                            DKSteps(steps(progress), label: String(localized: "Steps"))
                        }
                    } else {
                        Text("No install to show.")
                            .foregroundStyle(DK.Palette.muted)
                    }
                }
                .padding(DKSheetMetrics.horizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .dkCardFill(DK.Palette.window)
        } accessory: {
            if let progress = bundles.progress, !bundles.isInstalling {
                if progress.canSkip {
                    DKButton(DKButtonSpec(
                        String(localized: "Skip"),
                        help: String(localized: "Use this version without the failed checks."),
                    ) {
                        bundles.skipFailedChecks()
                    })
                }
                if progress.error != nil {
                    DKButton(DKButtonSpec(
                        String(localized: "Retry"),
                        glyph: .restart,
                        isEnabled: model.canInstallBundles || progress.status(.install) == .passed,
                    ) {
                        Task { await model.retryInstall() }
                    })
                }
            }
        } actions: {
            if bundles.isInstalling {
                DKButton(DKButtonSpec(
                    String(localized: "Hide"),
                    help: String(localized: "The install keeps running. Core Bundles shows it again."),
                ) {
                    dismiss()
                })
                .keyboardShortcut(.cancelAction)
            } else {
                DKButton(String(localized: "Done"), variant: .primary) {
                    bundles.dismissProgress()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 520, height: 460)
        .background(DK.Palette.window)
        .interactiveDismissDisabled(bundles.isInstalling)
    }

    // MARK: - Summary

    private func summary(_ progress: VPhoneLaunchpadCoreBundle.InstallProgress) -> some View {
        let (state, tone) = state(progress)
        return DKListRow(DKListItem(
            progress.version.map { "VPhone.bundle \($0)" } ?? progress.name,
            glyph: .bundle,
            glyphTone: tone == .neutral ? nil : tone,
            badges: [.init(state, tone: tone)],
            lines: [.init(progress.name, monospaced: true)],
        ))
    }

    private func state(_ progress: VPhoneLaunchpadCoreBundle.InstallProgress) -> (String, DKTone) {
        switch progress.overall {
        case .running: (String(localized: "Installing…"), .info)
        case .failed where progress.status(.install) == .passed: (String(localized: "Checks failed"), .warning)
        case .failed: (String(localized: "Not installed"), .danger)
        case .warning: (String(localized: "Checks skipped"), .warning)
        default: (String(localized: "Installed"), .success)
        }
    }

    // MARK: - Steps

    /// A check the user skipped (`.warning`) draws as a skipped step, with
    /// "Skipped" under it.
    private func steps(_ progress: VPhoneLaunchpadCoreBundle.InstallProgress) -> [DKStep] {
        progress.plan.map { step in
            let status = progress.status(step)
            var note: String?
            var fraction: Double?
            if step == .download, status == .running {
                let received = VPhoneLaunchpadCoreBundleView.size(progress.received)
                let size = VPhoneLaunchpadCoreBundleView.size(progress.size)
                note = String(localized: "\(received) of \(size)")
                fraction = progress.size > 0 ? Double(progress.received) / Double(progress.size) : nil
            } else if status == .warning {
                note = String(localized: "Skipped")
            }
            return DKStep(
                step.title,
                command: note,
                status: Self.stepStatus(status),
                progress: fraction,
                id: step.rawValue,
            )
        }
    }

    static func stepStatus(_ status: VPhoneLaunchpadStatus) -> DKStepStatus {
        switch status {
        case .passed: .done
        case .warning: .skipped
        case .running: .active
        case .failed: .failed
        case .pending: .pending
        }
    }
}
