import SwiftUI
import VPhoneDesignKit

/// The Host Setup page: a summary of whether this Mac can run machines, and
/// the required and advisory checks with their fixes. The DHCP addresses old
/// guests still hold are on the Network page.
struct VPhoneLaunchpadHostSetupView: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var showsSkillInstall = false

    /// Opens the Disks page from the low disk space banner. Without it the
    /// banner has no button.
    private let onReviewDisks: (() -> Void)?

    init(onReviewDisks: (() -> Void)? = nil) {
        self.onReviewDisks = onReviewDisks
    }

    private var host: VPhoneLaunchpadHostSetup {
        model.host
    }

    var body: some View {
        @Bindable var host = host
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: DK.Space.s6) {
                    DKSection {
                        DKListRow(summary)
                    }
                    requiredSection
                    advisorySection
                    if let banner = diskBanner {
                        banner
                    }
                }
                .padding(DK.Space.s5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DK.Palette.window)
        .sheet(isPresented: $showsSkillInstall) {
            VPhoneLaunchpadSkillInstallView()
        }
        .errorAlert($host.actionError)
    }

    // MARK: - Header

    private var header: some View {
        DKPageHeader(String(localized: "Host Setup"), subtitle: subtitle) {
            DKButton(DKButtonSpec(
                String(localized: "Install Skill…"),
                help: String(localized: "Give your coding agent the vphone skill"),
            ) {
                showsSkillInstall = true
            })
            DKButton(DKButtonSpec(
                String(localized: "Check Again"),
                glyph: .refresh,
                isEnabled: !host.isChecking,
                help: String(localized: "Run every check again"),
            ) {
                Task { await model.refreshHost() }
            })
            // Straight on to the next stage while it is not ready.
            if host.requiredPassed, !model.bundles.isReady {
                DKButton(String(localized: "Continue"), glyph: .right, variant: .primary) {
                    model.present(.coreBundle)
                }
            }
        }
    }

    /// Checks that passed or were skipped, and the advisory ones that warn.
    private var subtitle: String {
        VPhoneLaunchpadHostSetupText.subtitle(
            passed: host.passedRequiredCount,
            required: host.required.count,
            advisoryWarnings: advisoryWarnings.count,
        )
    }

    private var advisoryWarnings: [VPhoneLaunchpadHostCheck] {
        host.advisory.filter { $0.status == .warning || $0.status == .failed }
    }

    // MARK: - Summary

    private var summary: DKListItem {
        let failing = host.required.filter { !host.isSatisfied($0) }
        if host.isChecking, !failing.isEmpty {
            return DKListItem(
                String(localized: "Checking this Mac…"),
                glyph: .pending,
                glyphTone: .idle,
                lines: [.init(String(localized: "The helper and the network are checked last."))],
            )
        }
        if failing.isEmpty {
            return DKListItem(
                String(localized: "This Mac can run machines."),
                glyph: .check,
                glyphTone: .success,
                lines: [.init(VPhoneLaunchpadHostSetupText.passedLine(advisoryWarnings: advisoryWarnings.map(\.title)))],
            )
        }
        var lines: [DKListItem.Line] = [
            .init(VPhoneLaunchpadHostSetupText.failingLine(failing.map(\.title))),
        ]
        if failing.contains(where: { $0.kind == .developerTools }) {
            lines.append(.init(String(localized: "Allow vphone-launchpad in Privacy & Security → Developer Tools, then come back to Launchpad.")))
        }
        lines.append(.init(String(localized: "A Core Bundle can be installed once every required check passes.")))
        return DKListItem(
            String(localized: "This Mac is not ready yet."),
            glyph: .warning,
            glyphTone: .warning,
            lines: lines,
        )
    }

    // MARK: - Checks

    private var requiredSection: some View {
        DKSection(String(localized: "Required")) {
            ForEach(host.required) { check in
                checkRow(check)
            }
        }
    }

    private var advisorySection: some View {
        DKSection(
            String(localized: "Advisory"),
            note: String(localized: "Advisory checks do not block setup."),
        ) {
            ForEach(host.advisory) { check in
                checkRow(check)
            }
        }
    }

    private func checkRow(_ check: VPhoneLaunchpadHostCheck) -> some View {
        let isSkipped = host.isSkipped(check)
        return VPhoneLaunchpadHostCheckRow(
            title: check.title,
            value: isSkipped ? String(localized: "Skipped · \(check.detail)") : check.detail,
            status: isSkipped ? .warning : check.status,
            monospaced: check.kind == .libraryVolume || check.kind == .network,
            action: action(for: check),
        )
    }

    private func action(for check: VPhoneLaunchpadHostCheck) -> DKButtonSpec? {
        switch check.kind {
        case .developerTools where check.status != .passed:
            guard host.canRequestDeveloperTools else {
                return nil
            }
            return DKButtonSpec(String(localized: "Open Settings")) {
                Task { await host.requestDeveloperTools() }
            }
        case .helper where check.status == .pending:
            let label = host.helper.state == .notInstalled ? String(localized: "Install…") : String(localized: "Update…")
            return DKButtonSpec(label, variant: .primary) {
                Task {
                    await host.installHelper()
                    await model.refreshHost()
                }
            }
        default:
            if host.isSkipped(check) {
                return DKButtonSpec(String(localized: "Don’t Skip")) {
                    host.setSkipped(check.kind, false)
                }
            }
            if host.canSkip(check) {
                return DKButtonSpec(
                    String(localized: "Skip"),
                    help: String(localized: "Continue without this check. The Core Bundle still runs its own checks."),
                ) {
                    host.setSkipped(check.kind, true)
                }
            }
            return nil
        }
    }

    // MARK: - Disk space

    /// The free disk space check warns below 100 GB. Its detail already says
    /// how much is free; an unknown amount is no reason for a banner.
    private var diskBanner: DKBanner? {
        guard let check = host.advisory.first(where: { $0.kind == .diskSpace }),
              check.status == .warning, check.detail != String(localized: "Unknown")
        else {
            return nil
        }
        let text = VPhoneLaunchpadHostSetupText.lowDiskText(check.detail)
        guard let onReviewDisks else {
            return DKBanner(text)
        }
        return DKBanner(text, actionLabel: String(localized: "Review Disks"), action: onReviewDisks)
    }
}

// MARK: - Check row

/// A key-value row (`DKKeyValueRow`) with a status dot and an optional small
/// button after the value, for checks that offer a fix. The kit's row takes the
/// button but has no in-progress state: a check that is still running shows a
/// spinner in place of the dot, and the row reads out its state.
struct VPhoneLaunchpadHostCheckRow: View {
    let title: String
    let value: String
    let status: VPhoneLaunchpadStatus
    var monospaced = false
    var action: DKButtonSpec?

    var body: some View {
        HStack(spacing: DK.Space.s3) {
            label
            if let action {
                DKButton(Self.small(action))
                    .fixedSize()
            }
        }
        .font(DK.Typeface.body)
        .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight)
        .padding(.horizontal, 14)
        .padding(.vertical, action == nil ? 0 : 3)
    }

    /// The title, dot and value, read by VoiceOver as one element with the
    /// state as its value.
    private var label: some View {
        HStack(spacing: DK.Space.s3) {
            Text(title)
                .foregroundStyle(DK.Palette.muted)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: DK.Space.s4)
            HStack(spacing: DK.Space.s2) {
                if status == .running {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: DK.Metric.dot, height: DK.Metric.dot)
                } else {
                    DKStatusDot(Self.tone(status))
                }
                Text(value)
                    .font(monospaced ? DK.Typeface.mono : DK.Typeface.body)
                    .foregroundStyle(Self.valueColor(status))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(value)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Self.statusText(status))
    }

    static func small(_ spec: DKButtonSpec) -> DKButtonSpec {
        var spec = spec
        spec.size = .small
        return spec
    }

    static func tone(_ status: VPhoneLaunchpadStatus) -> DKTone {
        switch status {
        case .passed: .success
        case .warning: .warning
        case .failed: .danger
        case .pending: .idle
        case .running: .info
        }
    }

    /// Warnings and failures color the value as `DKKeyValue` does; passed
    /// checks keep the body ink so a column of them does not turn green.
    static func valueColor(_ status: VPhoneLaunchpadStatus) -> Color {
        switch status {
        case .warning: DKTone.warning.text
        case .failed: DKTone.danger.text
        default: DK.Palette.ink
        }
    }

    static func statusText(_ status: VPhoneLaunchpadStatus) -> String {
        switch status {
        case .passed: String(localized: "Passed")
        case .warning: String(localized: "Warning")
        case .failed: String(localized: "Failed")
        case .pending: String(localized: "Not checked")
        case .running: String(localized: "Checking…")
        }
    }
}
