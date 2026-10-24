import Darwin
import Foundation

// MARK: - Machine state layout

/// Where a machine keeps the state that makes it *this* machine, and that has
/// to travel with it when it is cold-started on another Mac:
///
/// | State | File | Notes |
/// | --- | --- | --- |
/// | Machine identifier (ECID, so the UDID) | `config.plist` `machineIdentifier`, mirrored in `identity.plist` | Generated on first boot |
/// | MAC address | `config.plist` `networkConfig.macAddress`, mirrored | Generated on first boot |
/// | Hardware model | `identity.plist` `hardwareModel` | Fixed PV=3 descriptor; recorded to detect a mismatch |
/// | NVRAM / auxiliary storage | `nvramStorage` | `VZMacAuxiliaryStorage`; the same file |
/// | SEP storage | `sepStorage` | Moves in step with the disk: anti-replay counters |
///
/// Two layouts exist. The legacy one, every bundle made so far, keeps
/// `nvram.bin` and `SEPStorage` at the folder root. The state-directory layout
/// keeps them in `MachineState/` with `identity.plist` beside them, so that one
/// directory can be a mount of a shared volume. The manifest then names them
/// `MachineState/nvram.bin` and `MachineState/SEPStorage`, which vphone builds
/// from before this layout refuse to load: they would otherwise create a fresh
/// NVRAM and SEP storage at the root and boot a guest whose keys no longer
/// match its disk.
///
/// The layout is opt-in (`vm storage --state-dir on`) and reversible. Nothing
/// changes for a legacy bundle.
///
/// Host-bound things stay out of `MachineState/`: the control socket, the
/// staged vphoned, snapshots, and saved machine state (`SavedState/`), whose
/// encryption key is tied to the Mac that wrote it.
public enum VPhoneMachineStateLayout {
    public static let directoryName = "MachineState"
    public static let identityFileName = "identity.plist"
    public static let defaultNVRAMName = "nvram.bin"
    public static let defaultSEPStorageName = "SEPStorage"

    public enum Kind: String, Codable, Sendable {
        case legacy
        case stateDirectory = "state-directory"
    }

    /// Nil when one of the two files is in `MachineState/` and the other is not.
    public static func kind(of manifest: VPhoneVirtualMachineManifest) -> Kind? {
        let prefix = directoryName + "/"
        switch (manifest.nvramStorage.hasPrefix(prefix), manifest.sepStorage.hasPrefix(prefix)) {
        case (false, false): return .legacy
        case (true, true): return .stateDirectory
        default: return nil
        }
    }

    public static func directory(of bundle: VPhoneBundle) -> URL {
        bundle.url.appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func identityURL(of bundle: VPhoneBundle) -> URL {
        directory(of: bundle).appendingPathComponent(identityFileName)
    }

    // MARK: Checks

    /// What a launch must refuse before Virtualization creates any file.
    ///
    /// - In the state-directory layout `MachineState` must be a real
    ///   directory (a mount point is one), never a symbolic link: the files in
    ///   it are opened, created and overwritten, and a link would take them
    ///   outside the folder.
    /// - A machine that has booted (it has a machine identifier), or any
    ///   machine on an NBD disk, must find its NVRAM and SEP storage. Missing
    ///   ones would be created empty, and the guest's keys would no longer
    ///   match its disk; in this layout that is what an unmounted state
    ///   volume looks like.
    /// - A half-done move between layouts leaves the files where the manifest
    ///   does not look; that is refused too, in both layouts.
    public static func requireLaunchable(_ bundle: VPhoneBundle) throws {
        guard let kind = kind(of: bundle.manifest) else {
            throw VPhoneMachineStateError.mixedLayout(machine: bundle.name)
        }
        let stateDirectory = directory(of: bundle)
        switch kind {
        case .legacy:
            for name in [defaultNVRAMName, defaultSEPStorageName] {
                let live = bundle.url.appendingPathComponent(name)
                let moved = stateDirectory.appendingPathComponent(name)
                if VPhoneVirtualMachineManifest.fileKind(at: live) == .missing,
                   VPhoneVirtualMachineManifest.fileKind(at: moved) != .missing
                {
                    throw VPhoneMachineStateError.interruptedMove(machine: bundle.name, file: "\(directoryName)/\(name)")
                }
            }
        case .stateDirectory:
            try requireRealDirectory(stateDirectory, machine: bundle.name)
            // A machine on an NBD disk starts from state files it was given
            // (`vm create --remote-disk`), never from empty ones: on its first
            // boot too, a missing file is an unmounted state volume.
            let hasBooted = !bundle.manifest.machineIdentifier.isEmpty || bundle.manifest.diskLocation.isNetwork
            for name in [bundle.manifest.nvramStorage, bundle.manifest.sepStorage] {
                let live = bundle.url.appendingPathComponent(name)
                let kind = VPhoneVirtualMachineManifest.fileKind(at: live)
                if kind == .missing {
                    let root = bundle.url.appendingPathComponent((name as NSString).lastPathComponent)
                    if VPhoneVirtualMachineManifest.fileKind(at: root) != .missing {
                        throw VPhoneMachineStateError.interruptedMove(machine: bundle.name, file: root.lastPathComponent)
                    }
                    if hasBooted {
                        throw VPhoneMachineStateError.missingStateFile(machine: bundle.name, file: name)
                    }
                }
            }
        }
    }

    static func requireRealDirectory(_ url: URL, machine: String) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw VPhoneMachineStateError.missingDirectory(machine: machine, path: url.path)
        }
        guard info.st_mode & S_IFMT == S_IFDIR else {
            throw VPhoneMachineStateError.notADirectory(path: url.path)
        }
    }

    // MARK: Moving between layouts

    /// Moves NVRAM and SEP storage into `MachineState/` and records the
    /// identity there. The machine must be stopped.
    ///
    /// The files move by `rename(2)`, so `MachineState` must be on the
    /// bundle's volume while this runs; mount a shared volume over it only
    /// after copying the directory there. The manifest is written last, and a
    /// launch refuses the half-moved state (`requireLaunchable`), so an
    /// interrupted move is finished by running this again.
    @discardableResult
    public static func moveToStateDirectory(_ bundle: VPhoneBundle) throws -> VPhoneBundle {
        guard let kind = kind(of: bundle.manifest) else {
            throw VPhoneMachineStateError.mixedLayout(machine: bundle.name)
        }
        if kind == .stateDirectory { return bundle }
        try requireUnchangedNames(bundle)
        try VPhoneBundleActivity.requireStopped(bundle)

        let fm = FileManager.default
        let stateDirectory = directory(of: bundle)
        if VPhoneVirtualMachineManifest.fileKind(at: stateDirectory) == .missing {
            try fm.createDirectory(at: stateDirectory, withIntermediateDirectories: false)
        }
        try requireRealDirectory(stateDirectory, machine: bundle.name)

        var moved: [(from: URL, to: URL)] = []
        do {
            for name in [defaultNVRAMName, defaultSEPStorageName] {
                let from = bundle.url.appendingPathComponent(name)
                let to = stateDirectory.appendingPathComponent(name)
                switch VPhoneVirtualMachineManifest.fileKind(at: from) {
                case .missing:
                    // Already moved by an interrupted run, or never created.
                    continue
                case .other:
                    throw VPhoneManifestError.notRegularFile(path: from.path)
                case .regularFile:
                    guard VPhoneVirtualMachineManifest.fileKind(at: to) == .missing else {
                        throw VPhoneMachineStateError.bothCopiesExist(machine: bundle.name, file: name)
                    }
                    try renameExclusive(from, to)
                    moved.append((from, to))
                }
            }
            if !bundle.manifest.machineIdentifier.isEmpty {
                let record = VPhoneMachineIdentityRecord(
                    machineIdentifier: bundle.manifest.machineIdentifier,
                    macAddress: bundle.manifest.networkConfig.macAddress,
                    hardwareModel: Data(),
                    machineName: bundle.name,
                )
                try record.write(to: identityURL(of: bundle))
            }
            let updated = bundle.manifest.updating(
                nvramStorage: "\(directoryName)/\(defaultNVRAMName)",
                sepStorage: "\(directoryName)/\(defaultSEPStorageName)",
            )
            try updated.write(to: bundle.configURL)
            try VPhoneHostFilePermissions.makeAccessible(at: bundle.url)
            return VPhoneBundle(url: bundle.url, manifest: updated)
        } catch {
            for step in moved.reversed() {
                _ = rename(step.to.path, step.from.path)
            }
            throw error
        }
    }

    /// Moves NVRAM and SEP storage back to the folder root, so a vphone build
    /// from before the state-directory layout can boot the machine again.
    /// `identity.plist` is removed, and `MachineState` with it when empty.
    @discardableResult
    public static func moveToLegacyLayout(_ bundle: VPhoneBundle) throws -> VPhoneBundle {
        guard let kind = kind(of: bundle.manifest) else {
            throw VPhoneMachineStateError.mixedLayout(machine: bundle.name)
        }
        if kind == .legacy { return bundle }
        try VPhoneBundleActivity.requireStopped(bundle)
        let stateDirectory = directory(of: bundle)
        try requireRealDirectory(stateDirectory, machine: bundle.name)

        var moved: [(from: URL, to: URL)] = []
        do {
            for name in [bundle.manifest.nvramStorage, bundle.manifest.sepStorage] {
                let base = (name as NSString).lastPathComponent
                let from = bundle.url.appendingPathComponent(name)
                let to = bundle.url.appendingPathComponent(base)
                switch VPhoneVirtualMachineManifest.fileKind(at: from) {
                case .missing:
                    continue
                case .other:
                    throw VPhoneManifestError.notRegularFile(path: from.path)
                case .regularFile:
                    guard VPhoneVirtualMachineManifest.fileKind(at: to) == .missing else {
                        throw VPhoneMachineStateError.bothCopiesExist(machine: bundle.name, file: base)
                    }
                    try renameExclusive(from, to)
                    moved.append((from, to))
                }
            }
            let updated = bundle.manifest.updating(
                nvramStorage: (bundle.manifest.nvramStorage as NSString).lastPathComponent,
                sepStorage: (bundle.manifest.sepStorage as NSString).lastPathComponent,
            )
            try updated.write(to: bundle.configURL)
            try? FileManager.default.removeItem(at: identityURL(of: bundle))
            _ = rmdir(stateDirectory.path)
            return VPhoneBundle(url: bundle.url, manifest: updated)
        } catch {
            for step in moved.reversed() {
                _ = rename(step.to.path, step.from.path)
            }
            throw error
        }
    }

    /// Only the names vphone itself gives these files are moved; a manifest
    /// edited to other names is left for its owner to sort out.
    private static func requireUnchangedNames(_ bundle: VPhoneBundle) throws {
        guard bundle.manifest.nvramStorage == defaultNVRAMName,
              bundle.manifest.sepStorage == defaultSEPStorageName
        else {
            throw VPhoneMachineStateError.customNames(machine: bundle.name)
        }
    }

    private static func renameExclusive(_ from: URL, _ to: URL) throws {
        guard renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            if code == EXDEV {
                throw VPhoneMachineStateError.crossVolume(path: to.deletingLastPathComponent().path)
            }
            throw VPhoneMachineStateError.moveFailed(path: from.path, reason: String(cString: strerror(code)))
        }
    }
}

// MARK: - Identity record

/// `MachineState/identity.plist`: the identity the state files beside it
/// belong to. vphone-vm writes it on every boot in the state-directory
/// layout and checks it against `config.plist` first, so a state volume
/// mounted under the wrong machine is refused instead of booted with another
/// machine's SEP storage, and a `config.plist` recreated on another Mac with
/// no identity takes this one instead of generating a new ECID.
public struct VPhoneMachineIdentityRecord: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public let format: Int
    public let machineIdentifier: Data
    public let macAddress: String
    /// `VZMacHardwareModel.dataRepresentation`; empty until vphone-vm fills it.
    public let hardwareModel: Data
    public let ecid: String?
    public let udid: String?
    public let machineName: String?
    public let updated: Date

    public init(
        machineIdentifier: Data,
        macAddress: String,
        hardwareModel: Data,
        ecid: String? = nil,
        udid: String? = nil,
        machineName: String? = nil,
        updated: Date = Date(),
    ) {
        format = Self.currentFormat
        self.machineIdentifier = machineIdentifier
        self.macAddress = macAddress
        self.hardwareModel = hardwareModel
        self.ecid = ecid
        self.udid = udid
        self.machineName = machineName
        self.updated = updated
    }

    /// Nil when there is no record; throws when there is one that cannot be
    /// read, which a launch must not treat as "no record".
    public static func load(from url: URL) throws -> VPhoneMachineIdentityRecord? {
        switch VPhoneVirtualMachineManifest.fileKind(at: url) {
        case .missing: return nil
        case .other: throw VPhoneManifestError.notRegularFile(path: url.path)
        case .regularFile: break
        }
        let data = try Data(contentsOf: url)
        let record: VPhoneMachineIdentityRecord
        do {
            record = try PropertyListDecoder().decode(Self.self, from: data)
        } catch {
            throw VPhoneMachineStateError.unreadableIdentity(path: url.path)
        }
        guard record.format == Self.currentFormat else {
            throw VPhoneMachineStateError.unreadableIdentity(path: url.path)
        }
        return record
    }

    public func write(to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(self).write(to: url, options: .atomic)
        try VPhoneHostFilePermissions.makeAccessible(at: url)
    }

    /// Identity fields equal; the timestamp and derived fields are not compared.
    public func sameIdentity(as other: VPhoneMachineIdentityRecord) -> Bool {
        machineIdentifier == other.machineIdentifier
            && macAddress == other.macAddress
            && hardwareModel == other.hardwareModel
    }
}

/// The decision vphone-vm makes before it builds the platform, in the
/// state-directory layout.
public enum VPhoneMachineIdentityReconciliation: Equatable, Sendable {
    /// Use `config.plist` as it is; the record is written afterwards.
    case useManifest
    /// `config.plist` has no identity and the state directory has one: take
    /// it, so a machine cold-started from a shared volume keeps its ECID.
    case adopt(machineIdentifier: Data, macAddress: String)
    /// Refuse to boot.
    case mismatch(String)

    public static func reconcile(
        manifestIdentifier: Data,
        manifestMAC: String,
        hardwareModel: Data,
        record: VPhoneMachineIdentityRecord?,
    ) -> Self {
        guard let record else { return .useManifest }
        if !record.hardwareModel.isEmpty, !hardwareModel.isEmpty, record.hardwareModel != hardwareModel {
            return .mismatch(
                "MachineState/identity.plist was written for another hardware model. Its NVRAM and SEP storage belong to a different kind of machine.",
            )
        }
        if manifestIdentifier.isEmpty {
            guard !record.machineIdentifier.isEmpty else { return .useManifest }
            return .adopt(
                machineIdentifier: record.machineIdentifier,
                macAddress: manifestMAC.isEmpty ? record.macAddress : manifestMAC,
            )
        }
        if !record.machineIdentifier.isEmpty, record.machineIdentifier != manifestIdentifier {
            let name = record.machineName.map { " (\($0))" } ?? ""
            return .mismatch(
                "config.plist and MachineState/identity.plist\(name) name different machines. The state directory holds another machine's NVRAM and SEP storage; mount the right one, or clear machineIdentifier in config.plist to adopt this one.",
            )
        }
        return .useManifest
    }
}

// MARK: - Errors

public enum VPhoneMachineStateError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case mixedLayout(machine: String)
    case interruptedMove(machine: String, file: String)
    case missingStateFile(machine: String, file: String)
    case missingDirectory(machine: String, path: String)
    case notADirectory(path: String)
    case bothCopiesExist(machine: String, file: String)
    case customNames(machine: String)
    case crossVolume(path: String)
    case moveFailed(path: String, reason: String)
    case unreadableIdentity(path: String)
    case identityMismatch(machine: String, reason: String)
    case mountedStateDirectory(machine: String, path: String)

    public var description: String {
        switch self {
        case let .mixedLayout(machine):
            "\(machine)'s config.plist puts one of nvram.bin and SEPStorage in MachineState/ and the other at the folder root. Both must be in the same place."
        case let .interruptedMove(machine, file):
            "\(machine) has \(file) where its config.plist does not look for it: a move between layouts was interrupted. Run `vphone-cli vm storage \(machine) --state-dir on` (or off) again to finish it."
        case let .missingStateFile(machine, file):
            "\(machine) has booted before but \(file) is missing. If MachineState is a shared volume, mount it first; starting now would create an empty one and the guest could no longer read its data."
        case let .missingDirectory(machine, path):
            "\(machine)'s state directory \(path) does not exist. Mount or restore it first."
        case let .notADirectory(path):
            "\(path) is a symbolic link or not a directory. The state directory must be a real directory (a mount point is fine)."
        case let .bothCopiesExist(machine, file):
            "\(machine) has \(file) both at the folder root and in MachineState/. Keep the one that belongs to the disk and remove the other by hand."
        case let .customNames(machine):
            "\(machine)'s config.plist names its NVRAM or SEP storage something other than nvram.bin and SEPStorage, so it is not moved automatically."
        case let .crossVolume(path):
            "\(path) is on another volume than the machine folder. Move the files while MachineState is on the same volume, then copy it to the shared volume and mount that over it."
        case let .moveFailed(path, reason):
            "Could not move \(path): \(reason)."
        case let .unreadableIdentity(path):
            "\(path) cannot be read as a vphone identity record. Restore it from a backup, or remove it to have the next boot write a new one from config.plist."
        case let .identityMismatch(machine, reason):
            "\(machine): \(reason)"
        case let .mountedStateDirectory(machine, path):
            "\(machine)'s state directory \(path) is a mounted volume. Unmount it first: deleting the machine would delete the files on it."
        }
    }

    public var errorDescription: String? {
        description
    }
}
