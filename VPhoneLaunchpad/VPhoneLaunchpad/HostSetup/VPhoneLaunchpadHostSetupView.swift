import SwiftUI
import VPhoneDesignKit

/// The Host Setup page: a summary of whether this Mac can run machines, the
/// required and advisory checks with their fixes, and the DHCP addresses old
/// guests still hold.
struct VPhoneLaunchpadHostSetupView: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var showsSkillInstall = false
    @State private var confirmsRelease = false

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
        @Bindable var leases = model.leases
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
                    leasesSection
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
        .errorAlert($leases.actionError)
        .task { await model.leases.refresh() }
        .confirmationDialog(
            "Release \(model.leases.orphans.count) Addresses?",
            isPresented: $confirmsRelease,
        ) {
            Button("Release") {
                Task { await model.leases.releaseFromUI() }
            }
        } message: {
            Text("Their leases have run out and no machine in your libraries has their MAC. A guest that comes back with one of these MACs gets a new address.")
        }
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
        let passed = String(localized: "\(host.passedRequiredCount) of \(host.required.count) required passed")
        let warnings = advisoryWarnings.count
        guard warnings > 0 else {
            return passed
        }
        return warnings == 1
            ? String(localized: "\(passed) · 1 advisory warning")
            : String(localized: "\(passed) · \(warnings) advisory warnings")
    }

    private var advisoryWarnings: [VPhoneLaunchpadHostCheck] {
        host.advisory.filter { $0.status == .warning || $0.status == .failed }
    }

    // MARK: - Summary

    private var summary: DKListItem {
        let failing = host.required.filter { !host.isSatisfied($0) }
        let warnings = advisoryWarnings.map { $0.title.localizedLowercase }
        if host.isChecking, !failing.isEmpty {
            return DKListItem(
                String(localized: "Checking this Mac…"),
                glyph: .pending,
                glyphTone: .idle,
                lines: [.init(String(localized: "The helper and the network are checked last."))],
            )
        }
        if failing.isEmpty {
            var line = String(localized: "Every required check passed.")
            if !warnings.isEmpty {
                line += " " + String(localized: "Advisory checks that need a look: \(warnings.formatted(.list(type: .and))).")
            }
            return DKListItem(
                String(localized: "This Mac can run machines."),
                glyph: .check,
                glyphTone: .success,
                lines: [.init(line)],
            )
        }
        var lines: [DKListItem.Line] = [
            .init(String(localized: "Needs a look: \(failing.map { $0.title }.formatted(.list(type: .and))).")),
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
        DKSection(
            String(localized: "Required"),
            note: String(localized: "\(host.passedRequiredCount) of \(host.required.count) passed"),
        ) {
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
        let text = String(localized: "Low disk space on the library volume: \(check.detail). A new machine’s disk may not fit once the guest fills it.")
        guard let onReviewDisks else {
            return DKBanner(text)
        }
        return DKBanner(text, actionLabel: String(localized: "Review Disks"), action: onReviewDisks)
    }

    // MARK: - NAT leases

    private var leasesSection: some View {
        let leases = model.leases
        let (status, detail) = leasesStatus
        return DKSection(
            String(localized: "NAT Network"),
            footnote: String(localized: "The Mac’s DHCP server keeps an address for every guest MAC it has seen, even after the lease runs out. Release frees the addresses of iOS guests no machine uses any more, such as deleted machines. It needs an administrator."),
        ) {
            VPhoneLaunchpadHostCheckRow(
                title: String(localized: "Addresses held by old guests"),
                value: detail,
                status: status,
                action: leases.orphans.isEmpty ? nil : DKButtonSpec(
                    String(localized: "Release…"),
                    isEnabled: !leases.isReleasing && model.canReleaseLeases,
                ) {
                    confirmsRelease = true
                },
            )
        }
    }

    private var leasesStatus: (VPhoneLaunchpadStatus, String) {
        let leases = model.leases
        if leases.isReleasing {
            return (.running, String(localized: "Waiting for administrator approval…"))
        }
        switch leases.state {
        case .unknown, .checking:
            return (.running, String(localized: "Checking…"))
        case let .unavailable(reason):
            return (.pending, reason)
        case let .failed(reason):
            return (.warning, reason)
        case .listed:
            let count = leases.orphans.count
            return count == 0
                ? (.passed, String(localized: "None"))
                : (.warning, String(localized: "\(count) addresses no machine uses"))
        }
    }
}

// MARK: - Check row

/// A key-value row (`DKKeyValueRow`) with a status dot and an optional small
/// button after the value, for checks that offer a fix. The kit's row takes no
/// action, so this draws the same row with one.
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
