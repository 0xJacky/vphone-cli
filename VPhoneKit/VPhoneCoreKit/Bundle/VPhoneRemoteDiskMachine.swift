import Darwin
import Foundation

// MARK: - Remote-disk machine

/// A machine whose disk is an NBD export and whose `MachineState/` is a
/// volume someone else already mounted (a storage-backed machine of a Mac
/// fleet): `vm create --remote-disk`.
///
/// The template the machine comes from is not on this Mac, so it is not
/// cloned. Its `config.plist` and the state files a clone starts from
/// (`nvram.bin`, `SEPStorage`) are handed over instead, the state files
/// already in the mounted directory, and the folder is completed around
/// them with what a clone from a template gets: a new identity
/// (``VPhoneBundleOperations/resetIdentity(of:clonedFrom:)``) and this
/// bundle's boot and SEP ROMs.
public struct VPhoneRemoteDiskMachine: Sendable {
    /// PoC F3 of the fleet's storage-backed machines: the client rides out a
    /// server stall shorter than its timeout, and a reconnect stops the VM
    /// for good, so the timeout must outlast the stalls a storage node has
    /// (a DRBD resync, a busy pool), not Virtualization's 5 seconds.
    public static let minimumTimeoutSeconds: Double = 60

    public let name: String
    public let disk: VPhoneNBDLocation
    public let timeoutSeconds: Double
    /// The template's `config.plist`. Only read.
    public let manifestSource: URL

    public init(name: String, disk: VPhoneNBDLocation, timeoutSeconds: Double, manifestSource: URL) {
        self.name = name
        self.disk = disk
        self.timeoutSeconds = timeoutSeconds
        self.manifestSource = manifestSource
    }

    public func validate() throws {
        guard timeoutSeconds >= Self.minimumTimeoutSeconds else {
            throw VPhoneRemoteDiskMachineError.timeoutTooShort(timeoutSeconds)
        }
        try VPhoneVirtualMachineManifest.NBDOptions(timeoutSeconds: timeoutSeconds).validate()
    }
}

public enum VPhoneRemoteDiskMachineError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case timeoutTooShort(Double)
    case missingFolder(path: String)
    case unexpectedEntries(path: String, entries: [String])
    case missingStateFile(path: String)
    case stateNotWritable(path: String, reason: String)
    case customStateNames(path: String)

    public var description: String {
        switch self {
        case let .timeoutTooShort(seconds):
            "A remote-disk machine's NBD timeout must be at least \(Int(VPhoneRemoteDiskMachine.minimumTimeoutSeconds)) seconds, not \(seconds): a reconnect stops the VM, so the client must wait out a storage node's stalls instead."
        case let .missingFolder(path):
            "\(path) does not exist or is not a real directory. Make the machine folder and mount its MachineState first."
        case let .unexpectedEntries(path, entries):
            "\(path) holds \(entries.joined(separator: ", ")) besides MachineState: a remote-disk machine is completed only around an otherwise empty folder."
        case let .missingStateFile(path):
            "\(path) is missing or not a regular file. MachineState must hold the template's nvram.bin and SEPStorage: empty ones would no longer match the disk, and an empty SEP storage panics the guest's SEP."
        case let .stateNotWritable(path, reason):
            "\(path) cannot be written (\(reason)). vphone-vm writes NVRAM, SEP storage and the identity record there."
        case let .customStateNames(path):
            "\(path) names its NVRAM or SEP storage something other than nvram.bin and SEPStorage, which a remote-disk machine's MachineState does not hold."
        }
    }

    public var errorDescription: String? {
        description
    }
}

extension VPhoneBundleOperations {
    /// Completes `<library>/<name>/` into a machine on the NBD disk `spec`
    /// names, with its state in the `MachineState/` already there.
    ///
    /// Only checked, never made here: the folder exists and holds nothing but
    /// `MachineState`, a real directory (a mount point is one) that this
    /// account can write and that holds `nvram.bin` and `SEPStorage`.
    /// `MachineState/identity.plist` is removed when present, or the first
    /// boot would take the template's identity back.
    ///
    /// On failure only what this call added to the folder is removed; the
    /// folder and `MachineState/` are left as they were, so a retry starts
    /// from the same place.
    @discardableResult
    public static func createOnRemoteDisk(
        _ spec: VPhoneRemoteDiskMachine,
        in library: VPhoneLibrary,
        romSource: URL = defaultROMSource(),
        sepromSource: URL = defaultSEPROMSource(),
    ) throws -> VPhoneBundle {
        try requireValidName(spec.name)
        try spec.validate()
        let template = try VPhoneVirtualMachineManifest.load(from: spec.manifestSource)
        guard template.nvramStorage == VPhoneMachineStateLayout.defaultNVRAMName,
              template.sepStorage == VPhoneMachineStateLayout.defaultSEPStorageName
        else {
            throw VPhoneRemoteDiskMachineError.customStateNames(path: spec.manifestSource.path)
        }

        let dir = library.url(forName: spec.name)
        guard isRealDirectory(dir) else {
            throw VPhoneRemoteDiskMachineError.missingFolder(path: dir.path)
        }
        let before = try entries(of: dir)
        let unexpected = before.subtracting([VPhoneMachineStateLayout.directoryName, ".DS_Store"])
        if !unexpected.isEmpty {
            if unexpected.contains("config.plist") {
                throw VPhoneLibraryError.alreadyExists(name: spec.name)
            }
            throw VPhoneRemoteDiskMachineError.unexpectedEntries(path: dir.path, entries: unexpected.sorted())
        }
        let state = dir.appendingPathComponent(VPhoneMachineStateLayout.directoryName, isDirectory: true)
        try VPhoneMachineStateLayout.requireRealDirectory(state, machine: spec.name)
        for name in [VPhoneMachineStateLayout.defaultNVRAMName, VPhoneMachineStateLayout.defaultSEPStorageName] {
            let file = state.appendingPathComponent(name)
            guard VPhoneVirtualMachineManifest.fileKind(at: file) == .regularFile else {
                throw VPhoneRemoteDiskMachineError.missingStateFile(path: file.path)
            }
        }
        try requireWritable(state)

        do {
            let manifest = template
                .updating(diskImage: spec.disk.urlString, nbd: .some(.init(timeoutSeconds: spec.timeoutSeconds)))
                .updating(
                    nvramStorage: "\(VPhoneMachineStateLayout.directoryName)/\(VPhoneMachineStateLayout.defaultNVRAMName)",
                    sepStorage: "\(VPhoneMachineStateLayout.directoryName)/\(VPhoneMachineStateLayout.defaultSEPStorageName)",
                )
            let configURL = dir.appendingPathComponent("config.plist")
            try manifest.write(to: configURL)
            // The template's folder name is not known here, so an mDNS name
            // derived from it is cleared like a hand-set one.
            var bundle = try resetIdentity(of: VPhoneBundle(url: dir, manifest: manifest), clonedFrom: "")
            // The template's ROMs are not on this Mac; a clone from a template
            // gets this bundle's too.
            bundle = try installBootROM(from: romSource, in: bundle)
            bundle = try installSEPROM(from: sepromSource, in: bundle)
            // Stops at MachineState: a mounted volume is on another device.
            try VPhoneHostFilePermissions.makeAccessible(at: dir)
            return try VPhoneBundle.load(at: dir)
        } catch {
            for entry in (try? entries(of: dir)) ?? [] where !before.contains(entry) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(entry))
            }
            throw error
        }
    }

    /// Undoes ``createOnRemoteDisk(_:in:)`` for a caller whose own step after
    /// it failed: everything in the folder but `MachineState` goes, the
    /// folder and the state stay.
    public static func removeRemoteDiskMachineFiles(named name: String, in library: VPhoneLibrary) throws {
        try requireValidName(name)
        let dir = library.url(forName: name)
        guard isRealDirectory(dir) else { return }
        for entry in try entries(of: dir) where entry != VPhoneMachineStateLayout.directoryName {
            try FileManager.default.removeItem(at: dir.appendingPathComponent(entry))
        }
    }

    private static func isRealDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    private static func entries(of url: URL) throws -> Set<String> {
        try Set(FileManager.default.contentsOfDirectory(atPath: url.path))
    }

    /// Writes and removes a file: `access(2)` answers for the local
    /// permission bits, and an NFS export that squashes this account decides
    /// on the server.
    private static func requireWritable(_ directory: URL) throws {
        let probe = directory.appendingPathComponent(".vphone-write-check.\(UUID().uuidString)")
        let descriptor = open(probe.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw VPhoneRemoteDiskMachineError.stateNotWritable(path: directory.path, reason: String(cString: strerror(errno)))
        }
        close(descriptor)
        guard unlink(probe.path) == 0 else {
            throw VPhoneRemoteDiskMachineError.stateNotWritable(path: directory.path, reason: String(cString: strerror(errno)))
        }
    }
}
