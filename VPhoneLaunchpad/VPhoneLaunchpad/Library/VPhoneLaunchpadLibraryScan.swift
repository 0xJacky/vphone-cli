import Foundation
import Synchronization

// MARK: - Results

/// What the Library pages read from disk: the IPSW cache, and each machine
/// folder's disk image, restore files and total. Reading is read-only and
/// follows no symbolic link.
nonisolated struct VPhoneLaunchpadLibraryScan: Sendable {
    struct IPSWFile: Identifiable, Hashable, Sendable {
        var url: URL
        /// The name the file will have; for a download in progress, the name
        /// it gets once it finishes.
        var name: String
        var size: Int64
        var allocatedSize: Int64
        /// Read from the manifest, else guessed from the name; nil when neither works.
        var facts: VPhoneLaunchpadIPSW?
        var isDownloading: Bool

        var id: String {
            url.path
        }
    }

    struct Machine: Identifiable, Hashable, Sendable {
        /// The machine folder.
        var folder: URL
        var libraryRoot: String
        var name: String
        /// `guestProductType` from config.plist; nil in older configs.
        var productType: String?
        var diskImageSize: Int64?
        var diskImageAllocated: Int64?
        /// The `iPhone*_Restore` trees `fw prepare` extracts, by name.
        var restoreTrees: [String]
        var restoreAllocated: Int64
        /// Everything in the folder, the disk image and restore trees included.
        var totalAllocated: Int64

        var id: String {
            folder.path
        }

        var otherAllocated: Int64 {
            max(0, totalAllocated - (diskImageAllocated ?? 0) - restoreAllocated)
        }
    }

    struct Volume: Identifiable, Hashable, Sendable {
        var name: String
        var available: Int64?
        /// The library folders and caches on this volume.
        var paths: [String]

        var id: String {
            name + paths.joined(separator: "\n")
        }
    }

    var cacheDirectories: [URL] = []
    var ipsws: [IPSWFile] = []
    var machines: [Machine] = []
    var volumes: [Volume] = []

    var completeIPSWs: [IPSWFile] {
        ipsws.filter { !$0.isDownloading }
    }

    var cacheAllocated: Int64 {
        ipsws.reduce(0) { $0 + $1.allocatedSize }
    }
}

// MARK: - Scanner

/// Reads the library off the main actor. Each read checks for cancellation,
/// so leaving the page stops it. IPSW manifests are remembered by path, size
/// and modification date, so the second visit reads only the directory.
nonisolated enum VPhoneLaunchpadLibraryScanner {
    /// `$VPHONE_ROOT/ipsws`, else `~/.vphone/ipsws`: where `fw prepare`
    /// downloads (`VPhoneResources.ipswCacheDirectory()`).
    static var ipswCacheDirectory: URL {
        let environment = ProcessInfo.processInfo.environment["VPHONE_ROOT"].flatMap { $0.isEmpty ? nil : $0 }
        let root = environment.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vphone", isDirectory: true)
        return root.appendingPathComponent("ipsws", isDirectory: true)
    }

    /// The shared cache, then the `ipsws` folder beside each library that has
    /// one, as `VPhoneBoardDeviceTree.searchDirectories` looks.
    static func cacheDirectories(libraryRoots: [String]) -> [URL] {
        var directories = [ipswCacheDirectory]
        for root in libraryRoots {
            let beside = URL(fileURLWithPath: root, isDirectory: true)
                .deletingLastPathComponent()
                .appendingPathComponent("ipsws", isDirectory: true)
            let path = beside.standardizedFileURL.path
            guard !directories.contains(where: { $0.standardizedFileURL.path == path }),
                  isDirectory(beside)
            else {
                continue
            }
            directories.append(beside)
        }
        return directories
    }

    /// One machine to measure: its folder and library.
    struct MachineFolder: Hashable, Sendable {
        var libraryRoot: String
        var name: String

        var url: URL {
            URL(fileURLWithPath: libraryRoot, isDirectory: true).appendingPathComponent(name, isDirectory: true)
        }
    }

    @concurrent
    static func scan(
        libraryRoots: [String],
        machines: [MachineFolder],
        includeIPSWs: Bool = true,
        includeMachines: Bool = true,
    ) async throws -> VPhoneLaunchpadLibraryScan {
        var scan = VPhoneLaunchpadLibraryScan()
        scan.cacheDirectories = cacheDirectories(libraryRoots: libraryRoots)
        if includeIPSWs {
            for directory in scan.cacheDirectories {
                scan.ipsws += try ipsws(in: directory)
            }
        }
        if includeMachines {
            for machine in machines {
                try Task.checkCancellation()
                if let measured = try measure(machine) {
                    scan.machines.append(measured)
                }
            }
        }
        scan.volumes = volumes(for: libraryRoots + scan.cacheDirectories.map(\.path))
        return scan
    }

    // MARK: IPSWs

    private struct ManifestKey: Hashable {
        var path: String
        var size: Int64
        var modified: Date?
    }

    private static let manifests = Mutex<[ManifestKey: VPhoneLaunchpadIPSW?]>([:])

    static func ipsws(in directory: URL) throws -> [VPhoneLaunchpadLibraryScan.IPSWFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var files: [VPhoneLaunchpadLibraryScan.IPSWFile] = []
        for name in names.sorted() {
            try Task.checkCancellation()
            let partial = VPhoneLaunchpadIPSW.finalName(ofPartial: name)
            guard partial != nil || (!name.hasPrefix(".") && name.lowercased().hasSuffix(".ipsw")) else {
                continue
            }
            let url = directory.appendingPathComponent(name, isDirectory: false)
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else {
                continue
            }
            let size = Int64(values.fileSize ?? 0)
            let facts: VPhoneLaunchpadIPSW?
            if let partial {
                facts = VPhoneLaunchpadIPSW(fileName: partial)
            } else {
                facts = manifestFacts(url, size: size, modified: values.contentModificationDate)
                    ?? VPhoneLaunchpadIPSW(fileName: name)
            }
            files.append(VPhoneLaunchpadLibraryScan.IPSWFile(
                url: url,
                name: partial ?? name,
                size: size,
                allocatedSize: Int64(values.totalFileAllocatedSize ?? Int(size)),
                facts: facts,
                isDownloading: partial != nil,
            ))
        }
        return files
    }

    private static func manifestFacts(_ url: URL, size: Int64, modified: Date?) -> VPhoneLaunchpadIPSW? {
        let key = ManifestKey(path: url.path, size: size, modified: modified)
        if let known = manifests.withLock({ $0[key] }) {
            return known
        }
        let facts = try? VPhoneLaunchpadIPSW.read(url)
        manifests.withLock { $0[key] = .some(facts) }
        return facts
    }

    // MARK: Machines

    static func measure(_ machine: MachineFolder) throws -> VPhoneLaunchpadLibraryScan.Machine? {
        let folder = machine.url
        guard isDirectory(folder) else {
            return nil
        }
        let config = NSDictionary(contentsOf: folder.appendingPathComponent("config.plist"))
        let diskName = (config?["diskImage"] as? String).flatMap(plainFileName) ?? "Disk.img"
        var result = VPhoneLaunchpadLibraryScan.Machine(
            folder: folder,
            libraryRoot: machine.libraryRoot,
            name: machine.name,
            productType: config?["guestProductType"] as? String ?? originalsProductType(folder),
            diskImageSize: nil,
            diskImageAllocated: nil,
            restoreTrees: [],
            restoreAllocated: 0,
            totalAllocated: 0,
        )
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
            return result
        }
        var top: String?
        var topIsRestore = false
        var counted = 0
        while let item = enumerator.nextObject() as? URL {
            counted += 1
            if counted % 256 == 0 {
                try Task.checkCancellation()
            }
            let values = try? item.resourceValues(forKeys: Set(keys))
            if enumerator.level == 1 {
                top = item.lastPathComponent
                topIsRestore = values?.isDirectory == true && values?.isSymbolicLink != true
                    && isRestoreTree(item.lastPathComponent)
                if topIsRestore {
                    result.restoreTrees.append(item.lastPathComponent)
                }
            }
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                continue
            }
            let allocated = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            result.totalAllocated += allocated
            if topIsRestore {
                result.restoreAllocated += allocated
            } else if enumerator.level == 1, top == diskName {
                result.diskImageAllocated = allocated
                result.diskImageSize = Int64(values?.fileSize ?? 0)
            }
        }
        result.restoreTrees.sort()
        return result
    }

    /// The product type a machine was patched for, from the restore tree name
    /// `FirmwareOriginals` mirrors (`iPhoneOS_iPad17,3_26.6.2_23G90_Restore`),
    /// for a config.plist from before `guestProductType` was recorded.
    static func originalsProductType(_ folder: URL) -> String? {
        let originals = folder.appendingPathComponent("FirmwareOriginals", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: originals.path)) ?? []
        for name in names.sorted() where isRestoreTree(name) {
            if let type = VPhoneLaunchpadIPSW(fileName: name)?.productTypes.first {
                return type
            }
        }
        return nil
    }

    /// `fw prepare`'s restore tree: `iPhone17,3_…_Restore`, or for an iPad
    /// `iPhoneOS_iPad16,1_…_Restore`. The pipeline removes the same names
    /// after first boot. `FirmwareOriginals` never matches.
    static func isRestoreTree(_ name: String) -> Bool {
        name.hasPrefix("iPhone") && name.hasSuffix("_Restore")
    }

    /// `name` when it is one path component, otherwise nil.
    static func plainFileName(_ name: String) -> String? {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            return nil
        }
        return name
    }

    // MARK: Volumes

    /// The volumes holding `paths`, each once, with the space left on it for
    /// important use (what the Finder reports as available).
    static func volumes(for paths: [String]) -> [VPhoneLaunchpadLibraryScan.Volume] {
        var volumes: [VPhoneLaunchpadLibraryScan.Volume] = []
        var identifiers: [String] = []
        for path in paths {
            let url = existingAncestor(of: URL(fileURLWithPath: path, isDirectory: true))
            let values = try? url.resourceValues(forKeys: [
                .volumeIdentifierKey, .volumeLocalizedNameKey, .volumeAvailableCapacityForImportantUsageKey, .volumeURLKey,
            ])
            let identifier = values?.volume?.path ?? url.path
            if let index = identifiers.firstIndex(of: identifier) {
                if !volumes[index].paths.contains(path) {
                    volumes[index].paths.append(path)
                }
                continue
            }
            identifiers.append(identifier)
            volumes.append(VPhoneLaunchpadLibraryScan.Volume(
                name: values?.volumeLocalizedName ?? VPhoneLaunchpadLibraryFormat.abbreviated(url.path),
                available: values?.volumeAvailableCapacityForImportantUsage,
                paths: [path],
            ))
        }
        return volumes
    }

    static func existingAncestor(of url: URL) -> URL {
        var candidate = url
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: Removal

    enum RemovalError: LocalizedError {
        case notRestoreTree(String)

        var errorDescription: String? {
            switch self {
            case let .notRestoreTree(name): "\(name) is not a restore tree."
            }
        }
    }

    /// Removes a machine's restore trees, each only when it is still a real
    /// folder directly inside the machine folder with a restore tree's name.
    /// `FirmwareOriginals`, which `fw patch` patches from, is never touched.
    @concurrent
    static func removeRestoreTrees(_ names: [String], in folder: URL) async throws {
        let manager = FileManager.default
        for name in names {
            try Task.checkCancellation()
            guard isRestoreTree(name), plainFileName(name) != nil,
                  name != "FirmwareOriginals"
            else {
                throw RemovalError.notRestoreTree(name)
            }
            let url = folder.appendingPathComponent(name, isDirectory: true)
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values?.isDirectory == true, values?.isSymbolicLink == false else {
                continue
            }
            try manager.removeItem(at: url)
        }
    }
}
