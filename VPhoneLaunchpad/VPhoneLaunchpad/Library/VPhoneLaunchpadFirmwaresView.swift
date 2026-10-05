import AppKit
import SwiftUI
import VPhoneDesignKit

/// The Firmwares page. The IPSWs Launchpad has downloaded, and the restore files prepared for each machine.
///
/// The IPSWs are the files in the cache `fw prepare` downloads into, named by
/// their BuildManifest and, when the default Core Bundle's `fw catalog` lists
/// them, by the catalog. A machine uses an IPSW when its restore-info.json
/// names that release (and its config.plist's product type is among the
/// IPSW's), or when a creation under way was given it as a source.
struct VPhoneLaunchpadFirmwaresView: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var filter = VPhoneLaunchpadFirmwareFilter.all
    @State private var scan: VPhoneLaunchpadLibraryScan?
    @State private var catalog: VPhoneLaunchpadFirmwareCatalogIndex?
    @State private var removal: VPhoneLaunchpadRestoreFilesItem?
    @State private var isRemoving = false
    @State private var removalError: VPhoneLaunchpadError?

    var body: some View {
        VPhoneLaunchpadFirmwaresPage(
            rows: rows,
            restoreItems: restoreItems,
            isLoading: scan == nil,
            filter: $filter,
            onShowCache: showCache,
            onRemove: { removal = $0 },
        )
        .navigationTitle("Firmwares")
        // Again whenever the machines listed change: a creation's download,
        // a machine stopping, one deleted elsewhere.
        .task(id: scanKey) { await rescan() }
        .task(id: model.bundles.defaultVersion) { await loadCatalog() }
        .confirmationDialog(
            removal.map { String(localized: "Remove the Restore Files of \($0.machine)?") } ?? "",
            isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
            presenting: removal,
        ) { item in
            Button(String(localized: "Remove \(VPhoneLaunchpadLibraryFormat.size(item.size))"), role: .destructive) {
                Task { await remove(item) }
            }
        } message: { item in
            Text(String(localized: "\(item.trees.joined(separator: ", ")) will be deleted. The machine starts from its disk without them. Restoring it again prepares the firmware anew, from the IPSW cache while the IPSWs are still there."))
        }
        .errorAlert($removalError)
    }

    // MARK: - Data

    private var library: VPhoneLaunchpadMachineLibrary {
        model.machines
    }

    private var machineFolders: [VPhoneLaunchpadLibraryScanner.MachineFolder] {
        var folders = library.machines.map { VPhoneLaunchpadLibraryScanner.MachineFolder(libraryRoot: $0.libraryRoot, name: $0.name) }
        for path in library.creations.keys where !folders.contains(where: { $0.libraryRoot == path.libraryRoot && $0.name == path.name }) {
            folders.append(VPhoneLaunchpadLibraryScanner.MachineFolder(libraryRoot: path.libraryRoot, name: path.name))
        }
        return folders
    }

    /// Changes when a scan would read something different.
    private var scanKey: [String] {
        VPhoneLaunchpadLibraryScanKey.key(library)
    }

    private func rescan() async {
        // `vm list` has to answer first, or every machine looks missing.
        guard library.hasListed else {
            return
        }
        do {
            scan = try await VPhoneLaunchpadLibraryScanner.scan(libraryRoots: library.roots, machines: machineFolders)
        } catch {
            // Cancelled: the page went away or the machines changed again.
        }
    }

    private var rows: [VPhoneLaunchpadFirmwareRow] {
        guard let scan else {
            return []
        }
        return VPhoneLaunchpadFirmwareRows.rows(scan.ipsws, catalog: catalog, uses: uses(scan))
    }

    private func uses(_ scan: VPhoneLaunchpadLibraryScan) -> [VPhoneLaunchpadFirmwareUse] {
        var uses: [VPhoneLaunchpadFirmwareUse] = []
        for machine in library.machines {
            let measured = scan.machines.first { $0.libraryRoot == machine.libraryRoot && $0.name == machine.name }
            let creation = library.creations[machine.path]
            uses.append(VPhoneLaunchpadFirmwareUse(
                machine: machine.name,
                productType: measured?.productType,
                ios: machine.restoreInfo.map { .init(version: $0.ios.version, build: $0.ios.build) },
                cloudOS: machine.restoreInfo.map { .init(version: $0.cloudOS.version, build: $0.cloudOS.build) },
                sources: creation.map { [$0.options.iphoneSource, $0.options.cloudOSSource] } ?? [],
                isCreating: creation?.isRunning == true,
            ))
        }
        for (path, creation) in library.creations where !library.machines.contains(where: { $0.path == path }) {
            uses.append(VPhoneLaunchpadFirmwareUse(
                machine: path.name,
                sources: [creation.options.iphoneSource, creation.options.cloudOSSource],
                isCreating: creation.isRunning,
            ))
        }
        return uses
    }

    private var restoreItems: [VPhoneLaunchpadRestoreFilesItem] {
        guard let scan else {
            return []
        }
        let spans = Set(scan.machines.map(\.libraryRoot)).count > 1
        return scan.machines.filter { !$0.restoreTrees.isEmpty }.map { measured in
            let path = VPhoneLaunchpadMachinePath(libraryRoot: measured.libraryRoot, name: measured.name)
            return VPhoneLaunchpadFirmwareRows.restoreItem(measured, owner: owner(path), showsLibrary: spans)
        }
    }

    private func owner(_ path: VPhoneLaunchpadMachinePath) -> VPhoneLaunchpadRestoreOwner {
        let listed = library.machines.first { $0.path == path }
        let activity: VPhoneLaunchpadRestoreOwner.Activity = switch library.state(of: path) {
        case .stopped: .stopped
        case .running: .running
        case .busy: .busy
        }
        let creation: VPhoneLaunchpadRestoreOwner.Creation = switch library.creations[path] {
        case nil: .none
        case let pipeline? where pipeline.isRunning: .running
        case let pipeline? where pipeline.isFinished: .finished
        default: .unfinished
        }
        let firmware = listed?.restoreInfo.map { info in
            String(localized: "iOS \(info.ios.version) (\(info.ios.build)) + cloudOS \(info.cloudOS.version) (\(info.cloudOS.build))")
        }
        return VPhoneLaunchpadRestoreOwner(
            activity: activity,
            creation: creation,
            customFirmwareInstalled: listed?.customFirmwareInstalled,
            firmware: firmware,
        )
    }

    // MARK: - Catalog

    /// The catalog of each Core Bundle version, read once per session.
    private static var catalogs: [String: VPhoneLaunchpadFirmwareCatalogIndex] = [:]

    private func loadCatalog() async {
        guard let version = model.bundles.defaultVersion,
              let commandLine = model.bundles.commandLine(version: version)
        else {
            return
        }
        if let known = Self.catalogs[version] {
            catalog = known
            return
        }
        guard let result = try? await commandLine.run(["fw", "catalog", "--json"], recordInHistory: false),
              result.succeeded, let data = result.jsonData,
              let report = try? JSONDecoder().decode(VPhoneLaunchpadFirmwareCatalog.self, from: data)
        else {
            return
        }
        let entries = report.guests.flatMap { device in
            device.pairings.flatMap { pairing in
                [
                    VPhoneLaunchpadFirmwareCatalogIndex.Entry(name: pairing.ios.name, url: pairing.ios.url, isCloudOS: false),
                    VPhoneLaunchpadFirmwareCatalogIndex.Entry(name: pairing.recommendedCloudOS.name, url: pairing.recommendedCloudOS.url, isCloudOS: true),
                ]
            }
        }
        let index = VPhoneLaunchpadFirmwareCatalogIndex(entries: entries)
        Self.catalogs[version] = index
        catalog = index
    }

    // MARK: - Actions

    private func showCache() {
        let directory = scan?.cacheDirectories.first ?? VPhoneLaunchpadLibraryScanner.ipswCacheDirectory
        let shown = VPhoneLaunchpadLibraryScanner.isDirectory(directory)
            ? directory
            : VPhoneLaunchpadLibraryScanner.existingAncestor(of: directory)
        NSWorkspace.shared.activateFileViewerSelecting([shown])
    }

    /// Checks the machine again at the moment of removal: the list the
    /// dialog was opened from may be seconds old.
    private func remove(_ item: VPhoneLaunchpadRestoreFilesItem) async {
        guard !isRemoving, let measured = scan?.machines.first(where: { $0.id == item.id }) else {
            return
        }
        let path = VPhoneLaunchpadMachinePath(libraryRoot: measured.libraryRoot, name: measured.name)
        let current = VPhoneLaunchpadFirmwareRows.restoreItem(measured, owner: owner(path), showsLibrary: false)
        if let reason = current.blockedReason {
            removalError = VPhoneLaunchpadError(String(localized: "Unable to Remove the Restore Files of \(item.machine)"), detail: reason)
            return
        }
        isRemoving = true
        defer { isRemoving = false }
        do {
            try await VPhoneLaunchpadLibraryScanner.removeRestoreTrees(measured.restoreTrees, in: measured.folder)
        } catch {
            removalError = VPhoneLaunchpadError(
                String(localized: "Unable to Remove the Restore Files of \(item.machine)"),
                detail: error.localizedDescription,
            )
        }
        await rescan()
    }
}

// MARK: - Scan key

/// What the Library pages' scans depend on: the library folders, each listed
/// machine with its state, and each creation. A change starts a new scan.
enum VPhoneLaunchpadLibraryScanKey {
    static func key(_ library: VPhoneLaunchpadMachineLibrary) -> [String] {
        let states = library.machines.map { machine in
            let state = switch library.state(of: machine.path) {
            case .stopped: "stopped"
            case .running: "running"
            case let .busy(text): text
            }
            return "\(machine.libraryRoot)/\(machine.name):\(state)"
        }
        let creations = library.creations.map { "\($0.key.libraryRoot)/\($0.key.name):\($0.value.isRunning)" }.sorted()
        return [library.hasListed ? "listed" : "unlisted"] + library.roots + states + creations
    }
}
