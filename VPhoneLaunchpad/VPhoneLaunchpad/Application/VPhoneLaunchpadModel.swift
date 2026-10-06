import Foundation
import Observation
import VPhoneDesignKit

/// Owns the host checks, the installed bundles and the machine library. The
/// window shows one page at a time, picked in the sidebar: the machines, and
/// beside them Host Setup and Bundles. On launch the first stage that is not
/// ready opens by itself, and the sidebar marks a stage that regresses later.
@MainActor
@Observable
final class VPhoneLaunchpadModel {
    typealias Panel = VPhoneLaunchpadPanel

    let history = VPhoneLaunchpadCommandHistory()
    let helper = VPhoneLaunchpadHelperClient()
    let libraryRoot: URL
    let host: VPhoneLaunchpadHostSetup
    let bundles: VPhoneLaunchpadCoreBundle
    let machines: VPhoneLaunchpadMachineLibrary
    let leases: VPhoneLaunchpadLeases

    /// The page the window shows.
    var destination: DKLaunchpadDestination = .machines
    /// The sheet over the window: only ever `.bundleInstall`.
    var panel: Panel?
    private(set) var isStarted = false

    init() {
        libraryRoot = URL(fileURLWithPath: VPhoneLaunchpadMachineLocations.defaultRoot, isDirectory: true)
        host = VPhoneLaunchpadHostSetup(helper: helper, libraryRoot: libraryRoot)
        bundles = VPhoneLaunchpadCoreBundle(helper: helper, history: history)
        machines = VPhoneLaunchpadMachineLibrary(bundles: bundles, helper: helper)
        leases = VPhoneLaunchpadLeases(bundles: bundles, machines: machines, helper: helper)
        bundles.boundMachines = { [machines] version in machines.machineNames(boundTo: version) }
    }

    // MARK: - Pages

    /// Opens `next`: Host Setup and Core Bundle select their page, a bundle
    /// install opens its sheet.
    func present(_ next: Panel) {
        if let destination = next.destination {
            show(destination)
        } else {
            panel = next
        }
    }

    /// Selects a page. The install sheet, when it is open, steps aside so
    /// the page is not hidden behind it; the install carries on.
    func show(_ destination: DKLaunchpadDestination) {
        if panel != nil {
            panel = nil
        }
        self.destination = destination
    }

    // MARK: - Attention

    /// A required check fails, or an advisory one warns.
    var hostNeedsAttention: Bool {
        VPhoneLaunchpadSidebarMeta.hostWarning(
            isChecking: host.isChecking,
            requiredPassed: host.requiredPassed,
            advisoryWarnings: host.advisory.count { $0.status == .warning || $0.status == .failed },
        )
    }

    var bundleNeedsAttention: Bool {
        VPhoneLaunchpadSidebarMeta.bundleWarning(
            requiredPassed: host.requiredPassed,
            isReady: bundles.isReady,
            isInstalling: bundles.isInstalling,
            canSkip: bundles.progress?.canSkip == true,
        )
    }

    /// The IPSWs in the cache, for the sidebar. Nil until the cache is read.
    var firmwareCount: Int?

    /// Installing a bundle needs the helper (root-owned store) and Developer
    /// Tools access (the execution policy exception).
    var canInstallBundles: Bool {
        guard case .ready = helper.state else {
            return false
        }
        return host.isDeveloperToolAuthorized && !bundles.isInstalling
    }

    /// Releasing DHCP leases runs through the helper; an outdated one is
    /// replaced on the way.
    var canReleaseLeases: Bool {
        switch helper.state {
        case .ready, .outdated: true
        default: false
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard !isStarted else {
            return
        }
        isStarted = true
        #if DEBUG
            if VPhoneLaunchpadPreview.isActive {
                await VPhoneLaunchpadPreview.run(self)
                return
            }
        #endif
        startControl()
        // Host checks, installed bundles and the helper state were read at
        // init. These confirm them without holding up the machine list; the
        // network probe and the GitHub lists come last.
        machines.startMonitoring()
        async let listed: Void = machines.refresh()
        async let hostChecked: Void = host.refresh()
        await bundles.checkDefault()
        await hostChecked
        if case .outdated = helper.state {
            await host.installHelper()
            await host.refresh()
            await bundles.checkDefault()
        }
        await listed
        // An unfinished install reopens its own sheet instead.
        if panel == nil {
            switch VPhoneLaunchpadLaunchRoute.after(
                requiredPassed: host.requiredPassed,
                bundlesReady: bundles.isReady,
                installUnfinished: bundles.progress.map { !$0.isFinished } ?? false,
            ) {
            case .stay: break
            case let .page(page): destination = page
            case .installSheet: panel = .bundleInstall
            }
        }
        await bundles.fetchReleases()
        await bundles.fetchArtifacts()
    }

    // MARK: - Command line

    /// Serves `vphone-launchpad-cli` for as long as the app runs. Without the
    /// socket the window works as before; the CLI then says it cannot connect.
    private var control: VPhoneLaunchpadControlServer?

    private func startControl() {
        let commands = VPhoneLaunchpadControlCommands(model: self)
        let server = VPhoneLaunchpadControlServer { request, emit in
            await commands.handle(request, emit: emit)
        }
        do {
            try server.start()
            control = server
        } catch {
            print("[control] \(VPhoneLaunchpadError.message(for: error))")
        }
    }

    func refreshHost() async {
        await host.refresh()
        await leases.refresh()
    }

    // MARK: - Bundle install

    /// An install shows its progress in a sheet of its own, over the page it
    /// started from.
    /// `keepsDefault` leaves the default version as it is, as
    /// `vphone-launchpad-cli bundle install-* --keep-default` asks.
    func installBundle(_ release: VPhoneLaunchpadRelease, keepsDefault: Bool = false) async {
        revealInstall()
        await bundles.install(release, keepsDefault: keepsDefault)
        await machines.refresh()
    }

    func installArtifact(_ artifact: VPhoneLaunchpadArtifact) async {
        revealInstall()
        await bundles.installArtifact(artifact)
        await machines.refresh()
    }

    func installLocalBundle(_ source: URL, keepsDefault: Bool = false) async {
        revealInstall()
        await bundles.installLocal(source, keepsDefault: keepsDefault)
        await machines.refresh()
    }

    func retryInstall() async {
        await bundles.retry()
        await machines.refresh()
    }

    private func revealInstall() {
        present(.bundleInstall)
    }

    // MARK: - Sidebar and Inspector

    /// View › Hide Sidebar (⌃⌘S). The window has no toolbar toggle for it.
    var showsSidebar = true
    var showsInspector = true

    /// Refused while a machine is bound to the version; the error lands in
    /// `bundles.actionError`.
    func removeBundle(_ version: String) async {
        await machines.refresh()
        await bundles.remove(version)
        if let fallback = bundles.defaultVersion, bundles.defaultBundle?.preflight == .pending {
            await bundles.verify(fallback)
        }
    }
}
