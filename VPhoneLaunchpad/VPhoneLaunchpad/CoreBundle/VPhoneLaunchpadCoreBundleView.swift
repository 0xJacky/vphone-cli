import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VPhoneDesignKit

/// The Core Bundles page: the installed versions with the default, their
/// checks and the machines bound to each, and the releases and GitHub Actions
/// builds that can be installed.
struct VPhoneLaunchpadCoreBundleView: View {
    enum Source: Hashable {
        case releases
        case actions
    }

    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var removal: String?
    @State private var source = Source.releases
    @State private var token = ""

    private var bundles: VPhoneLaunchpadCoreBundle {
        model.bundles
    }

    private var notInstalled: [VPhoneLaunchpadRelease] {
        bundles.releases.filter { release in !bundles.installed.contains { $0.version == release.version } }
    }

    private static var installHelp: String {
        String(localized: "Installing needs the privileged helper and Developer Tools access.")
    }

    var body: some View {
        @Bindable var bundles = bundles
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: DK.Space.s6) {
                    if let banner = installBanner {
                        banner
                    }
                    if !bundles.installed.isEmpty {
                        installedSection
                    }
                    availableSection
                }
                .padding(DK.Space.s5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DK.Palette.window)
        .errorAlert($bundles.actionError)
        .confirmationDialog(
            "Remove VPhone.bundle \(removal ?? "")?",
            isPresented: Binding(get: { removal != nil }, set: {
                if !$0 {
                    removal = nil
                }
            }),
        ) {
            Button("Remove", role: .destructive) {
                if let version = removal {
                    Task { await model.removeBundle(version) }
                }
            }
        } message: {
            Text("Machines are not affected. You can install this version again later.")
        }
        #if DEBUG
        .onAppear {
            if VPhoneLaunchpadPreview.isActive {
                source = VPhoneLaunchpadPreview.coreBundleSource
            }
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        DKPageHeader(String(localized: "Core Bundles"), subtitle: subtitle) {
            DKButton(DKButtonSpec(
                String(localized: "Check for Updates"),
                glyph: .refresh,
                isEnabled: !bundles.isInstalling,
                help: String(localized: "Reload releases and builds, and run host preflight again."),
            ) {
                Task { await bundles.refresh() }
            })
            DKButton(DKButtonSpec(
                String(localized: "Install Local Build…"),
                glyph: .bundle,
                isEnabled: model.canInstallBundles,
                help: model.canInstallBundles
                    ? String(localized: "Install a VPhone.bundle folder or .zip built on this Mac.")
                    : Self.installHelp,
                action: chooseLocalBuild,
            ))
        }
    }

    private var subtitle: String {
        let count = bundles.installed.count
        guard count > 0 else {
            return String(localized: "No Core Bundle installed")
        }
        guard let version = bundles.defaultVersion else {
            return String(localized: "\(count) installed · no default")
        }
        return String(localized: "\(count) installed · default \(version)")
    }

    /// The last install, while it runs or after it stopped short. Its sheet
    /// may have been hidden; this brings it back.
    private var installBanner: DKBanner? {
        guard let progress = bundles.progress, !progress.isFinished else {
            return nil
        }
        let name = progress.version.map { "VPhone.bundle \($0)" } ?? progress.name
        let show = DKButtonSpec(String(localized: "Show Progress"), size: .small) {
            model.present(.bundleInstall)
        }
        if bundles.isInstalling {
            return DKBanner(String(localized: "Installing \(name)…"), tone: .info, action: show)
        }
        return DKBanner(
            progress.error?.message ?? String(localized: "The install of \(name) did not finish."),
            tone: progress.canSkip ? .warning : .danger,
            action: show,
        )
    }

    // MARK: - Installed

    private var installedSection: some View {
        DKSection(
            String(localized: "Installed"),
            note: String(localized: "New machines use the default. Each machine keeps its own."),
            footnote: String(localized: "Stored in \(VPhoneLaunchpadBundleStore.root.path) and managed by the helper."),
        ) {
            ForEach(bundles.installed) { bundle in
                installedRow(bundle)
                    .contextMenu { installedMenu(bundle) }
            }
        }
    }

    /// A row with the actions the design shows, Show in Finder and Remove…,
    /// and the ⋯ menu that held every action in Launchpad 2.6.0 for the rest.
    private func installedRow(_ bundle: VPhoneLaunchpadCoreBundle.Installed) -> some View {
        let more = moreItems(bundle)
        return HStack(spacing: 0) {
            DKListRow(installedItem(bundle))
            if more.contains(where: \.isEnabled) {
                DKMenuButton(DKButtonSpec(String(localized: "More"), glyph: .ellipsis, size: .icon), items: more)
                    .padding(.leading, -8)
                    .padding(.trailing, 14)
            }
        }
    }

    private func installedItem(_ bundle: VPhoneLaunchpadCoreBundle.Installed) -> DKListItem {
        let isDefault = bundle.version == bundles.defaultVersion
        let isCompatible = VPhoneLaunchpadNames.isCompatibleBundleVersion(bundle.version)
        let users = model.machines.machineNames(boundTo: bundle.version)
        let status = checkStatus(bundle)

        var badges: [DKListItem.Badge] = []
        if isDefault {
            badges.append(.init(String(localized: "Default"), tone: .accent))
        }
        if let variant = bundle.variant {
            badges.append(.init(variant, tone: .neutral))
        }
        badges.append(VPhoneLaunchpadBundleText.checkBadge(
            version: bundle.version,
            status: status,
            policyPassed: bundle.policy == .passed,
        ))

        var lines: [DKListItem.Line] = [
            .init(VPhoneLaunchpadBundleText.provenance(
                VPhoneLaunchpadBundleText.Origin(version: bundle.version),
                installedAt: bundle.receipt.installedAt,
                sha256: bundle.receipt.sha256,
            )),
            .init(VPhoneLaunchpadBundleText.users(users)),
        ]
        if isCompatible, status == .failed || status == .warning, let detail = failureDetail(bundle) {
            lines.append(.init(detail, tone: status == .failed ? .danger : .warning))
        }

        var actions = [DKButtonSpec(String(localized: "Show in Finder"), id: "finder") {
            Self.showInFinder(bundle.version)
        }]
        // A bound version stays: the store refuses to remove it, and the
        // context menu says why.
        if users.isEmpty {
            actions.append(DKButtonSpec(
                String(localized: "Remove…"),
                variant: .danger,
                isEnabled: !bundles.isInstalling,
                id: "remove",
            ) {
                removal = bundle.version
            })
        }

        return DKListItem(
            bundle.version,
            glyph: .bundle,
            monospacedTitle: true,
            badges: badges,
            lines: lines,
            actions: actions,
            id: bundle.version,
        )
    }

    /// The default and preflight actions, as Launchpad 2.6.0's ⋯ menu had them.
    private func moreItems(_ bundle: VPhoneLaunchpadCoreBundle.Installed) -> [DKMenuItem] {
        let isDefault = bundle.version == bundles.defaultVersion
        let isCompatible = VPhoneLaunchpadNames.isCompatibleBundleVersion(bundle.version)
        var items = [
            DKMenuItem(String(localized: "Set as Default"), isEnabled: !isDefault && isCompatible) {
                Task { await bundles.setDefault(bundle.version) }
            },
            DKMenuItem(String(localized: "Run Preflight Again"), isEnabled: isCompatible) {
                Task { await bundles.verify(bundle.version) }
            },
        ]
        if bundles.isAccepted(bundle.version) {
            items.append(DKMenuItem(String(localized: "Require Preflight")) {
                bundles.setAccepted(bundle.version, false)
            })
        } else if bundle.preflight == .failed, isCompatible {
            items.append(DKMenuItem(String(localized: "Use Without Preflight")) {
                bundles.setAccepted(bundle.version, true)
            })
        }
        return items
    }

    /// Every action of a row, including those the row leaves out.
    @ViewBuilder
    private func installedMenu(_ bundle: VPhoneLaunchpadCoreBundle.Installed) -> some View {
        let users = model.machines.machineNames(boundTo: bundle.version)
        DKMenuContent(moreItems(bundle))
        Button("Show in Finder") { Self.showInFinder(bundle.version) }
        Divider()
        Button("Remove…", role: .destructive) { removal = bundle.version }
            .disabled(bundles.isInstalling || !users.isEmpty)
            .help(users.isEmpty ? "" : "Choose another Core Bundle for its machines first.")
    }

    private static func showInFinder(_ version: String) {
        NSWorkspace.shared.activateFileViewerSelecting([VPhoneLaunchpadBundleStore.bundle(version: version)])
    }

    private func checkStatus(_ bundle: VPhoneLaunchpadCoreBundle.Installed) -> VPhoneLaunchpadStatus {
        VPhoneLaunchpadBundleText.checkStatus(
            policy: bundle.policy,
            preflight: bundle.preflight,
            isAccepted: bundles.isAccepted(bundle.version),
        )
    }

    /// The first lines of what the failed check said.
    private func failureDetail(_ bundle: VPhoneLaunchpadCoreBundle.Installed) -> String? {
        var parts: [String] = []
        if bundle.policy == .failed {
            parts.append(String(localized: "Not allowed to run."))
        }
        let detail = bundle.preflightDetail
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(3)
            .joined(separator: "\n")
        if bundle.preflight == .failed, !detail.isEmpty {
            parts.append(detail)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    // MARK: - Available

    /// A section whose head carries the source switch.
    private var availableSection: some View {
        DKSection(String(localized: "Available")) {
            switch source {
            case .releases:
                releaseRows
            case .actions:
                actionRows
            }
        } headAccessory: {
            DKSegmented(String(localized: "Source"), selection: $source, options: [
                DKSegmentOption(String(localized: "Releases"), value: .releases),
                DKSegmentOption(String(localized: "GitHub Actions"), value: .actions),
            ])
        }
    }

    @ViewBuilder
    private var releaseRows: some View {
        if let error = bundles.releasesError, bundles.releases.isEmpty {
            message(error, glyph: .warning, tone: .warning)
        } else if bundles.releases.isEmpty {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading releases…").foregroundStyle(DK.Palette.muted)
            }
            .padding(DK.Space.s4)
        } else if notInstalled.isEmpty {
            message(String(localized: "Every release is installed."), glyph: .check, tone: .success)
        } else {
            ForEach(notInstalled) { release in
                DKListRow(releaseItem(release, prominent: release == bundles.availableUpdate))
            }
        }
    }

    private func releaseItem(_ release: VPhoneLaunchpadRelease, prominent: Bool) -> DKListItem {
        var badges: [DKListItem.Badge] = []
        if prominent {
            badges.append(.init(String(localized: "Latest"), tone: .accent))
        }
        if release.isPrerelease {
            badges.append(.init(String(localized: "Pre-release"), tone: .warning))
        }
        let date = release.publishedAt.formatted(date: .abbreviated, time: .omitted)
        return DKListItem(
            release.version,
            glyph: .bundle,
            monospacedTitle: true,
            badges: badges,
            lines: [.init("\(date) · \(Self.size(release.size)) · SHA-256 \(Self.shortDigest(release.sha256))")],
            actions: [DKButtonSpec(
                String(localized: "Download and Install"),
                glyph: .download,
                variant: prominent ? .primary : .secondary,
                isEnabled: model.canInstallBundles,
                help: model.canInstallBundles ? nil : Self.installHelp,
            ) {
                Task { await model.installBundle(release) }
            }],
            id: release.version,
        )
    }

    /// A one-line state in place of a list: an error, or nothing to install.
    private func message(_ text: String, glyph: DKGlyph, tone: DKTone) -> some View {
        HStack(alignment: .top, spacing: 10) {
            DKIcon(glyph, size: 18)
                .foregroundStyle(tone.color)
            Text(text)
                .foregroundStyle(DK.Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(DK.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - GitHub Actions

    @ViewBuilder
    private var actionRows: some View {
        VStack(alignment: .leading, spacing: DK.Space.s3) {
            Text("Builds from GitHub Actions, kept for 7 days. To download them, add a token that can read Actions for Lakr233/vphone-cli. The token is stored in your keychain.")
                .foregroundStyle(DK.Palette.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            tokenRow
        }
        .padding(DK.Space.s4)
        if let error = bundles.artifactsError, bundles.artifacts.isEmpty {
            message(error, glyph: .warning, tone: .warning)
        } else if bundles.artifacts.isEmpty {
            message(String(localized: "No GitHub Actions builds are available."), glyph: .info, tone: .neutral)
        } else {
            ForEach(bundles.artifacts) { artifact in
                DKListRow(artifactItem(artifact))
            }
        }
    }

    private var tokenRow: some View {
        HStack(spacing: DK.Space.s2) {
            Text("GitHub Token")
                .foregroundStyle(DK.Palette.muted)
                .frame(width: 96, alignment: .leading)
            if bundles.hasGitHubToken {
                Text("Saved in the keychain")
                    .foregroundStyle(DK.Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DKButton(String(localized: "Remove")) {
                    bundles.setGitHubToken("")
                }
            } else {
                SecureField("GitHub Token", text: $token, prompt: Text(verbatim: "github_pat_…"))
                    .labelsHidden()
                    .textFieldStyle(.dkFieldMono)
                    .onSubmit(saveToken)
                DKButton(DKButtonSpec(
                    String(localized: "Save"),
                    variant: .primary,
                    isEnabled: !token.trimmingCharacters(in: .whitespaces).isEmpty,
                    action: saveToken,
                ))
            }
        }
    }

    private func saveToken() {
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        bundles.setGitHubToken(token)
        token = ""
        Task { await bundles.fetchArtifacts() }
    }

    private func artifactItem(_ artifact: VPhoneLaunchpadArtifact) -> DKListItem {
        let isInstalled = bundles.installed.contains { $0.version.hasSuffix(artifact.versionSuffix) }
        let canInstall = model.canInstallBundles && bundles.hasGitHubToken
        let created = artifact.createdAt.formatted(date: .abbreviated, time: .shortened)
        let expires = artifact.expiresAt.formatted(.relative(presentation: .named))
        var actions = [DKButtonSpec(
            String(localized: "Open Run"),
            glyph: .link,
            help: String(localized: "Open the workflow run on GitHub"),
        ) {
            NSWorkspace.shared.open(artifact.runURL)
        }]
        if !isInstalled {
            actions.append(DKButtonSpec(
                String(localized: "Download and Install"),
                glyph: .download,
                isEnabled: canInstall,
                help: canInstall ? nil
                    : model.canInstallBundles ? String(localized: "Add a GitHub token to download builds from GitHub Actions.")
                    : Self.installHelp,
            ) {
                Task { await model.installArtifact(artifact) }
            })
        }
        return DKListItem(
            artifact.branch.isEmpty ? artifact.shortCommit : "\(artifact.branch) @ \(artifact.shortCommit)",
            glyph: .bundle,
            monospacedTitle: true,
            badges: isInstalled ? [.init(String(localized: "Installed"), tone: .success)] : [],
            lines: [.init(String(localized: "\(created) · \(Self.size(artifact.size)) · Expires \(expires)"))],
            actions: actions,
            id: String(artifact.id),
        )
    }

    // MARK: - Local build

    private func chooseLocalBuild() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Install Local Build")
        panel.message = String(localized: "Choose a VPhone.bundle folder or a .zip that contains one.")
        panel.prompt = String(localized: "Install")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .bundle]
        panel.present { url in
            Task { await model.installLocalBundle(url) }
        }
    }

    // MARK: - Formatting

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func shortDigest(_ digest: String) -> String {
        VPhoneLaunchpadBundleText.shortDigest(digest)
    }
}
