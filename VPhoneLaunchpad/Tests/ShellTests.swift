import Foundation
import VPhoneDesignKit

/// The window shell's logic: page order and shortcuts, panel and launch
/// routing, the sidebar's meta text and warnings, and the words the Host
/// Setup, Core Bundles, Settings and Library pages build from their data.
/// Run with an English locale (`ShellTests.sh` passes one).
@main
struct ShellTests {
    static func expect(_ condition: Bool, _ message: @autoclosure () -> String, line: Int = #line) {
        precondition(condition, "line \(line): \(message())")
    }

    static func expectEqual<T: Equatable>(_ value: T, _ expected: T, line: Int = #line) {
        precondition(value == expected, "line \(line): \(value) is not \(expected)")
    }

    @MainActor
    static func main() {
        destinations()
        routing()
        sidebar()
        windowSize()
        buildVariant()
        hostSetup()
        bundles()
        settings()
        pages()
        print("ShellTests passed")
    }

    // MARK: - Pages and shortcuts

    static func destinations() {
        let all = DKLaunchpadDestination.allCases
        expectEqual(all, [.machines, .firmwares, .disks, .bundles, .network, .hostSetup])
        // ⌘1 to ⌘6 in sidebar order, all with Command alone.
        for (index, destination) in all.enumerated() {
            expectEqual(destination.shortcut, DKShortcut(Character("\(index + 1)"), .command))
        }
        expectEqual(Set(all.map(\.shortcut)).count, all.count)
        expectEqual(all.map(\.title), ["Machines", "Firmwares", "Disks", "Bundles", "Network", "Host Setup"])
        // The two sections split the pages between them, in order.
        expectEqual(DKLaunchpadSection.allCases.flatMap(\.destinations), all)
        expectEqual(DKLaunchpadSection.allCases.map(\.title), ["Library", "System"])
    }

    static func routing() {
        expectEqual(VPhoneLaunchpadPanel.hostSetup.destination, .hostSetup)
        expectEqual(VPhoneLaunchpadPanel.coreBundle.destination, .bundles)
        expectEqual(VPhoneLaunchpadPanel.bundleInstall.destination, nil)

        typealias Route = VPhoneLaunchpadLaunchRoute
        expectEqual(Route.after(requiredPassed: true, bundlesReady: true, installUnfinished: false), .stay)
        expectEqual(Route.after(requiredPassed: false, bundlesReady: true, installUnfinished: false), .page(.hostSetup))
        expectEqual(Route.after(requiredPassed: false, bundlesReady: false, installUnfinished: false), .page(.hostSetup))
        expectEqual(Route.after(requiredPassed: true, bundlesReady: false, installUnfinished: false), .page(.bundles))
        // An install that stopped short reopens its sheet before anything else.
        expectEqual(Route.after(requiredPassed: false, bundlesReady: false, installUnfinished: true), .installSheet)
    }

    // MARK: - Sidebar

    static func buildVariant() {
        typealias Variant = VPhoneLaunchpadBuildVariant
        // Upstream's builds carry none; the version alone names them.
        expectEqual(Variant.of(info: ["CFBundleShortVersionString": "2.6.1"]), nil)
        expectEqual(Variant.of(info: ["VPhoneBuildVariant": ""]), nil)
        expectEqual(Variant.of(info: nil), nil)
        expectEqual(Variant.of(info: ["VPhoneBuildVariant": "ui"]), "ui")
        // About: the build number, then the variant.
        expectEqual(Variant.aboutBuildLine(info: ["CFBundleVersion": "13", "VPhoneBuildVariant": "ui"]), "13, ui")
        expectEqual(Variant.aboutBuildLine(info: ["VPhoneBuildVariant": "ui"]), "ui")
        expectEqual(Variant.aboutBuildLine(info: ["CFBundleVersion": "13"]), nil)
        // The variant never reaches the version, so series matching is unchanged.
        expectEqual(VPhoneLaunchpadNames.isCompatibleBundleVersion("2.6.1-local.ab12cd34"), true)
    }

    static func windowSize() {
        typealias Size = VPhoneLaunchpadWindowSize
        // A 1512×982 MacBook Pro (visible 1512×949): most of the screen.
        expectEqual(Size.ideal(forVisible: CGSize(width: 1512, height: 949)), CGSize(width: 1210, height: 807))
        // A 5K display: capped, not a wall of empty columns.
        expectEqual(Size.ideal(forVisible: CGSize(width: 2560, height: 1415)), CGSize(width: 1680, height: 1080))
        // A small screen: the minimum, as long as it fits.
        expectEqual(Size.ideal(forVisible: CGSize(width: 1280, height: 777)), CGSize(width: 1080, height: 680))
        // A screen smaller than the minimum: the screen.
        expectEqual(Size.ideal(forVisible: CGSize(width: 1024, height: 640)), CGSize(width: 1024, height: 640))
        // No screen known: the minimum.
        expectEqual(Size.ideal(forVisible: .zero), Size.minimum)
    }

    static func sidebar() {
        typealias Meta = VPhoneLaunchpadSidebarMeta
        func row(
            _ destination: DKLaunchpadDestination,
            listed: Bool = true,
            running: Int = 0,
            total: Int = 0,
            firmwares: Int? = nil,
            hostWarning: Bool = false,
            bundleWarning: Bool = false,
        ) -> DKSidebarItem<DKLaunchpadDestination> {
            let sections = Meta.sections(
                listed: listed,
                running: running,
                total: total,
                firmwareCount: firmwares,
                hostWarning: hostWarning,
                bundleWarning: bundleWarning,
            )
            return sections.allSidebarItems().first { $0.id == destination }!
        }
        // The kit's rows, sections and order.
        let sections = Meta.sections(listed: true, running: 0, total: 0, firmwareCount: nil, hostWarning: false, bundleWarning: false)
        expectEqual(sections.map(\.title), ["Library", "System"])
        expectEqual(sections.allSidebarItems().map(\.id), DKLaunchpadDestination.allCases)

        // Machines: nothing until `vm list` has answered, then running/total with a dot.
        expectEqual(row(.machines, listed: false, running: 0, total: 3).trailingText, nil)
        expectEqual(row(.machines, running: 0, total: 0).trailingText, "0/0")
        expectEqual(row(.machines, running: 0, total: 0).metaTone, .idle)
        expectEqual(row(.machines, running: 1, total: 4).trailingText, "1/4")
        expectEqual(row(.machines, running: 1, total: 4).metaTone, .success)

        // Firmwares: nothing before the cache is read or when it holds none.
        expectEqual(row(.firmwares, firmwares: nil).trailingText, nil)
        expectEqual(row(.firmwares, firmwares: 0).trailingText, nil)
        expectEqual(row(.firmwares, firmwares: 4).trailingText, "4")

        // Bundles shows no version: a local build's name crowds out the label.
        expectEqual(row(.bundles).trailingText, nil)

        // The warning glyphs, read out from the app's catalog.
        expect(!row(.bundles).isWarning && !row(.hostSetup).isWarning, "no warnings")
        expect(row(.bundles, bundleWarning: true).isWarning, "bundles warning")
        expect(row(.hostSetup, hostWarning: true).isWarning, "host warning")
        expectEqual(row(.hostSetup, hostWarning: true).warningLabel, "Needs attention")

        // Host Setup: quiet while checking, then a failed required check or an advisory warning.
        expect(!Meta.hostWarning(isChecking: true, requiredPassed: false, advisoryWarnings: 1), "checking")
        expect(!Meta.hostWarning(isChecking: false, requiredPassed: true, advisoryWarnings: 0), "all passed")
        expect(Meta.hostWarning(isChecking: false, requiredPassed: false, advisoryWarnings: 0), "required failed")
        expect(Meta.hostWarning(isChecking: false, requiredPassed: true, advisoryWarnings: 1), "advisory warning")

        // Bundles: only once the host is ready, and not while an install runs or waits on a skip.
        expect(!Meta.bundleWarning(requiredPassed: false, isReady: false, isInstalling: false, canSkip: false), "host not ready")
        expect(Meta.bundleWarning(requiredPassed: true, isReady: false, isInstalling: false, canSkip: false), "no bundle")
        expect(!Meta.bundleWarning(requiredPassed: true, isReady: true, isInstalling: false, canSkip: false), "ready")
        expect(!Meta.bundleWarning(requiredPassed: true, isReady: false, isInstalling: true, canSkip: false), "installing")
        expect(!Meta.bundleWarning(requiredPassed: true, isReady: false, isInstalling: false, canSkip: true), "skippable")
    }

    // MARK: - Host Setup

    static func hostSetup() {
        typealias Text = VPhoneLaunchpadHostSetupText
        expectEqual(Text.subtitle(passed: 6, required: 6, advisoryWarnings: 0), "6 of 6 required passed")
        expectEqual(Text.subtitle(passed: 6, required: 6, advisoryWarnings: 1), "6 of 6 required passed · 1 advisory warning")
        expectEqual(Text.subtitle(passed: 4, required: 6, advisoryWarnings: 2), "4 of 6 required passed · 2 advisory warnings")

        expectEqual(Text.passedLine(advisoryWarnings: []), "Every required check passed.")
        expectEqual(
            Text.passedLine(advisoryWarnings: ["Free disk space"]),
            "Every required check passed. One advisory check needs a look: free disk space.",
        )
        expectEqual(
            Text.passedLine(advisoryWarnings: ["Free disk space", "Network"]),
            "Every required check passed. 2 advisory checks need a look: free disk space and network.",
        )
        expectEqual(
            Text.failingLine(["Developer Tools access", "Privileged helper"]),
            "Needs a look: Developer Tools access and Privileged helper.",
        )
        expectEqual(
            Text.lowDiskText("41 GB free"),
            "Low disk space: 41 GB free. A new machine’s 64 GB disk may not fit once the guest fills it.",
        )
    }

    // MARK: - Core Bundles

    static func bundles() {
        typealias Text = VPhoneLaunchpadBundleText
        expectEqual(Text.Origin(version: "2.6.0"), .release)
        expectEqual(Text.Origin(version: "2.6.0-ci.3013d16"), .actionsBuild)
        expectEqual(Text.Origin(version: "2.6.0-local.3013d16d"), .local(build: "3013d16d"))
        expectEqual(Text.Origin(version: "2.6.0-local"), .local(build: nil))
        expectEqual(Text.localBuild("2.6.0"), nil)

        let digest = "98daa4d0b00a6188f87c698e73018d497ca34396f31f95e9e872dd93e488322f"
        expectEqual(Text.shortDigest(digest), "98daa4d0…")
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let day = date.formatted(date: .abbreviated, time: .omitted)
        let minute = date.formatted(date: .abbreviated, time: .shortened)
        expectEqual(Text.provenance(.release, installedAt: date, sha256: digest), "Release · Installed \(day) · SHA-256 98daa4d0…")
        expectEqual(Text.provenance(.actionsBuild, installedAt: date, sha256: digest), "GitHub Actions build · Installed \(minute) · SHA-256 98daa4d0…")
        expectEqual(Text.provenance(.local(build: "3013d16d"), installedAt: date, sha256: digest), "Local build 3013d16d · Installed \(minute) · SHA-256 98daa4d0…")
        expectEqual(Text.provenance(.local(build: nil), installedAt: date, sha256: digest), "Local build · Installed \(minute) · SHA-256 98daa4d0…")

        expectEqual(Text.users([]), "Not used by any machine")
        expectEqual(Text.users(["research-26", "ipad-lab"]), "Used by research-26 and ipad-lab")
        expectEqual(Text.users(["a", "b", "c", "d", "e"]), "Used by 5 machines")

        expectEqual(Text.checkStatus(policy: .passed, preflight: .passed, isAccepted: false), .passed)
        expectEqual(Text.checkStatus(policy: .running, preflight: .passed, isAccepted: false), .running)
        expectEqual(Text.checkStatus(policy: .passed, preflight: .failed, isAccepted: true), .warning)
        expectEqual(Text.checkStatus(policy: .passed, preflight: .failed, isAccepted: false), .failed)
        expectEqual(Text.checkStatus(policy: .pending, preflight: .pending, isAccepted: false), .pending)

        func badge(_ version: String, _ status: VPhoneLaunchpadStatus, policyPassed: Bool = true) -> DKListItem.Badge {
            Text.checkBadge(version: version, status: status, policyPassed: policyPassed)
        }
        expectEqual(badge("2.6.0", .passed), DKListItem.Badge("Preflight passed", tone: .success))
        expectEqual(badge("2.6.0", .warning), DKListItem.Badge("Preflight skipped", tone: .warning))
        expectEqual(badge("2.6.0", .pending), DKListItem.Badge("Not checked", tone: .neutral))
        expectEqual(badge("2.6.0", .running), DKListItem.Badge("Checking…", tone: .info))
        expectEqual(badge("2.6.0", .failed), DKListItem.Badge("Preflight failed", tone: .danger))
        expectEqual(badge("2.6.0", .failed, policyPassed: false), DKListItem.Badge("Not allowed to run", tone: .danger))
        // An older series is never checked here; its badge names the Launchpad it needs.
        expectEqual(badge("2.4.0", .pending), DKListItem.Badge("Needs Launchpad 2.4", tone: .neutral))
        expectEqual(badge("2.5.0-local.3013d16d", .passed), DKListItem.Badge("Needs Launchpad 2.5", tone: .neutral))

        expectEqual(Text.preflightSummary(preflight: .passed, detail: "", isAccepted: false), "Passed preflight on this Mac")
        expectEqual(Text.preflightSummary(preflight: .failed, detail: "", isAccepted: true), "Used without preflight")
        expectEqual(Text.preflightSummary(preflight: .failed, detail: "SIP is on\nmore", isAccepted: false), "SIP is on")
        expectEqual(Text.preflightSummary(preflight: .failed, detail: "", isAccepted: false), "Failed")
        expectEqual(Text.preflightSummary(preflight: .pending, detail: "", isAccepted: false), "Not run yet")
    }

    // MARK: - Settings

    static func settings() {
        typealias Text = VPhoneLaunchpadLibrarySettingsText
        expectEqual(
            Text.folderDetail(isDefault: true, isAvailable: true, machines: 4, freeBytes: 41_000_000_000),
            "Default · 4 machines · 41 GB free",
        )
        expectEqual(
            Text.folderDetail(isDefault: false, isAvailable: true, machines: 1, freeBytes: 812_000_000_000),
            "Added · 1 machine · 812 GB free",
        )
        expectEqual(Text.folderDetail(isDefault: false, isAvailable: true, machines: 2, freeBytes: nil), "Added · 2 machines")
        expectEqual(Text.folderDetail(isDefault: false, isAvailable: false, machines: 2, freeBytes: 1), "Added · Not available")
        // The default library is counted even before its folder exists.
        expectEqual(Text.folderDetail(isDefault: true, isAvailable: false, machines: 0, freeBytes: nil), "Default · 0 machines")
    }

    // MARK: - Library pages

    @MainActor
    static func pages() {
        func row(_ id: String, size: Int64, downloading: Bool = false) -> VPhoneLaunchpadFirmwareRow {
            VPhoneLaunchpadFirmwareRow(
                id: id, title: id, fileName: id, kind: .iPhone, kindLabel: "iPhone",
                size: size, usedBy: [], status: nil, isDownloading: downloading,
            )
        }
        expectEqual(VPhoneLaunchpadFirmwaresPage.subtitle([]), "0 IPSWs")
        expectEqual(VPhoneLaunchpadFirmwaresPage.subtitle([row("a", size: 9_400_000_000)]), "1 IPSW · 9.4 GB")
        // A download in progress counts once it finishes.
        expectEqual(
            VPhoneLaunchpadFirmwaresPage.subtitle([
                row("a", size: 9_400_000_000), row("b", size: 28_700_000_000), row("c", size: 1, downloading: true),
            ]),
            "2 IPSWs · 38.1 GB",
        )

        var summary = VPhoneLaunchpadDiskSummary(
            usedCaption: "", machineDisks: 0, restoreFiles: 0, otherMachineFiles: 0, ipswCache: 0,
            volumes: [], removableRestoreFiles: [], ipswCount: 4,
        )
        let low = VPhoneLaunchpadDiskSummary.Volume(name: "Macintosh HD", available: 41_000_000_000, isLow: true)
        expectEqual(
            VPhoneLaunchpadDisksPage.lowSpaceText(low, summary: summary),
            "41 GB free on Macintosh HD. A new machine’s 64 GB disk may not fit. Unused IPSWs can be removed in Firmwares.",
        )
        summary.removableRestoreFiles = ["ios27-hooks (13.9 GB)"]
        expectEqual(
            VPhoneLaunchpadDisksPage.lowSpaceText(low, summary: summary),
            "41 GB free on Macintosh HD. A new machine’s 64 GB disk may not fit. Restore files kept for ios27-hooks (13.9 GB) and unused IPSWs can be removed in Firmwares.",
        )
        expectEqual(VPhoneLaunchpadDisksPage.cacheLine(ipswCount: 4), "4 downloaded images. A second machine from the same image downloads nothing.")
        expectEqual(VPhoneLaunchpadDisksPage.cacheLine(ipswCount: 1), "1 downloaded image. A second machine from the same image downloads nothing.")

        expectEqual(VPhoneLaunchpadNetworkPage.subtitle(machines: 4), "4 machines · NAT, Tunnel, Bridged or None for each")
        expectEqual(VPhoneLaunchpadNetworkPage.subtitle(machines: 1), "1 machine · NAT, Tunnel, Bridged or None for each")

        expectEqual(VPhoneLaunchpadLeaseSummary(.listed(0), canRelease: false).title, "None")
        expectEqual(VPhoneLaunchpadLeaseSummary(.listed(1), canRelease: true).title, "1 address")
        let three = VPhoneLaunchpadLeaseSummary(.listed(3), canRelease: true)
        expectEqual(three.title, "3 addresses")
        // The addresses themselves are not listed on the page.
        expectEqual(three.detail, nil)
        let failed = VPhoneLaunchpadLeaseSummary(.failed("bootpd is not running"), canRelease: false)
        expectEqual(failed.title, "Unable to list leases")
        expectEqual(failed.detail, "bootpd is not running")
        expectEqual(VPhoneLaunchpadLeaseSummary(.releasing, canRelease: false).detail, "Waiting for administrator approval…")
    }
}
