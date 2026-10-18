import Darwin
import Foundation

// MARK: - Saved machine state

/// A machine's memory and device state saved by `vm save-state`, for restoring
/// on the same Mac (`vm restore-state`).
///
/// It is a directory:
///
/// - `MachineState.vzvmsave` — what `VZVirtualMachine.saveMachineStateTo(url:)`
///   wrote. Virtualization encrypts it with a key tied to the Mac that wrote
///   it, so it can only be restored there, and may be refused after a macOS
///   update.
/// - `binding.plist` — what the state belongs to (`VPhoneSavedStateBinding`).
///   vphone checks it before handing the file to Virtualization, so a state
///   from another machine, another Mac or an older disk is refused with a
///   reason instead of resuming a guest whose memory does not match its disk.
///
/// The default place is `SavedState/` in the machine folder. It is host-bound,
/// so it is not part of `MachineState/`, and clones and exports leave it out.
///
/// A saved state is good for one restore: once the guest runs again its disk
/// moves on, so a successful restore, and any cold boot of the machine,
/// invalidates the state in the default place (`invalidated` in the binding).
public enum VPhoneSavedMachineState {
    public static let defaultDirectoryName = "SavedState"
    public static let stateFileName = "MachineState.vzvmsave"
    public static let bindingFileName = "binding.plist"

    public static func defaultDirectory(of bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent(defaultDirectoryName, isDirectory: true)
    }

    public static func stateFile(in directory: URL) -> URL {
        directory.appendingPathComponent(stateFileName)
    }

    public static func bindingFile(in directory: URL) -> URL {
        directory.appendingPathComponent(bindingFileName)
    }

    /// Whether `directory` holds a saved state that has not been used or
    /// invalidated.
    public static func hasUsableState(in directory: URL) -> Bool {
        guard let binding = try? VPhoneSavedStateBinding.load(from: bindingFile(in: directory)) else {
            return false
        }
        return binding.invalidated == nil
            && VPhoneVirtualMachineManifest.fileKind(at: stateFile(in: directory)) == .regularFile
    }

    /// Marks the state in `directory` as used, so it is never restored again.
    /// The file stays for its owner to remove: it can be several GB.
    public static func invalidate(in directory: URL, reason: String, now: Date = Date()) throws {
        let url = bindingFile(in: directory)
        guard var binding = try VPhoneSavedStateBinding.load(from: url), binding.invalidated == nil else {
            return
        }
        binding.invalidated = .init(reason: reason, at: now)
        try binding.write(to: url)
    }
}

// MARK: - Disk fingerprint

/// Identifies one version of a disk image file: the same file (device and
/// inode), not written since (size and modification time to the nanosecond).
/// Any write by a guest booted in between changes it.
public struct VPhoneDiskFingerprint: Codable, Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64

    public init(device: UInt64, inode: UInt64, size: Int64, modifiedSeconds: Int64, modifiedNanoseconds: Int64) {
        self.device = device
        self.inode = inode
        self.size = size
        self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds
    }

    public init?(of url: URL) {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        device = UInt64(bitPattern: Int64(info.st_dev))
        inode = UInt64(info.st_ino)
        size = Int64(info.st_size)
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
    }
}

// MARK: - Binding

/// `binding.plist`: everything a saved state is bound to.
public struct VPhoneSavedStateBinding: Codable, Equatable, Sendable {
    public static let currentFormat = 1

    public struct Invalidation: Codable, Equatable, Sendable {
        public let reason: String
        public let at: Date

        public init(reason: String, at: Date) {
            self.reason = reason
            self.at = at
        }
    }

    public let format: Int
    /// `VZMacHardwareModel.dataRepresentation` of the saving VM.
    public let hardwareModel: Data
    /// `VZMacMachineIdentifier.dataRepresentation` of the saving VM.
    public let machineIdentifier: Data
    /// What else the restoring configuration must match; see
    /// `VPhoneSavedStateConfiguration`.
    public let configuration: VPhoneSavedStateConfiguration
    /// IOPlatformUUID of the Mac that saved it. Virtualization refuses a state
    /// from another Mac anyway ("permission denied"); checking first gives the
    /// reason before any attempt.
    public let hostUUID: String
    public let hostName: String
    /// `kern.osversion` of the saving Mac, for the message when a macOS update
    /// makes Virtualization refuse the file.
    public let hostOSBuild: String
    public let vphoneVersion: String
    /// The disk file as it was when the state was saved; nil for an NBD disk,
    /// whose server vphone cannot ask.
    public let disk: VPhoneDiskFingerprint?
    public let stateFileSize: Int64
    public let saved: Date
    /// What the VM did after saving: `stop`, `pause` or `resume`. After
    /// `resume` the disk moves on, so such a state only restores when the disk
    /// has been put back to the saved moment by other means.
    public let after: String
    public var invalidated: Invalidation?

    public init(
        hardwareModel: Data,
        machineIdentifier: Data,
        configuration: VPhoneSavedStateConfiguration,
        hostUUID: String,
        hostName: String,
        hostOSBuild: String,
        vphoneVersion: String,
        disk: VPhoneDiskFingerprint?,
        stateFileSize: Int64,
        saved: Date,
        after: String,
        invalidated: Invalidation? = nil,
    ) {
        format = Self.currentFormat
        self.hardwareModel = hardwareModel
        self.machineIdentifier = machineIdentifier
        self.configuration = configuration
        self.hostUUID = hostUUID
        self.hostName = hostName
        self.hostOSBuild = hostOSBuild
        self.vphoneVersion = vphoneVersion
        self.disk = disk
        self.stateFileSize = stateFileSize
        self.saved = saved
        self.after = after
        self.invalidated = invalidated
    }

    public static func load(from url: URL) throws -> VPhoneSavedStateBinding? {
        switch VPhoneVirtualMachineManifest.fileKind(at: url) {
        case .missing: return nil
        case .other: throw VPhoneManifestError.notRegularFile(path: url.path)
        case .regularFile: break
        }
        let binding: VPhoneSavedStateBinding
        do {
            binding = try PropertyListDecoder().decode(Self.self, from: Data(contentsOf: url))
        } catch {
            throw VPhoneSavedStateError.unreadableBinding(path: url.path)
        }
        guard binding.format == Self.currentFormat else {
            throw VPhoneSavedStateError.unreadableBinding(path: url.path)
        }
        return binding
    }

    public func write(to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(self).write(to: url, options: .atomic)
        try VPhoneHostFilePermissions.makeAccessible(at: url)
    }

    /// What the restoring side has, to check this binding against.
    public struct Current: Sendable {
        public let hardwareModel: Data
        public let machineIdentifier: Data
        public let configuration: VPhoneSavedStateConfiguration
        public let hostUUID: String
        public let hostOSBuild: String
        public let disk: VPhoneDiskFingerprint?

        public init(
            hardwareModel: Data,
            machineIdentifier: Data,
            configuration: VPhoneSavedStateConfiguration,
            hostUUID: String,
            hostOSBuild: String,
            disk: VPhoneDiskFingerprint?,
        ) {
            self.hardwareModel = hardwareModel
            self.machineIdentifier = machineIdentifier
            self.configuration = configuration
            self.hostUUID = hostUUID
            self.hostOSBuild = hostOSBuild
            self.disk = disk
        }
    }

    public struct Verification: Equatable, Sendable {
        /// Reasons the state must not be restored.
        public var refusals: [String] = []
        /// Reasons it may still fail, for the log.
        public var warnings: [String] = []

        public var isRestorable: Bool {
            refusals.isEmpty
        }
    }

    /// `allowOtherHost` only skips vphone's own host check, and the disk
    /// fingerprint, which a copy on another Mac never matches (another device
    /// and inode), so PoC F2 can see Virtualization's answer; it never makes a
    /// restore on another Mac work.
    public func verify(against current: Current, allowOtherHost: Bool = false) -> Verification {
        var result = Verification()
        if let invalidated {
            result.refusals.append("it was already used or overtaken: \(invalidated.reason)")
        }
        if machineIdentifier != current.machineIdentifier {
            result.refusals.append("it was saved by another machine (machine identifier differs)")
        }
        if hardwareModel != current.hardwareModel {
            result.refusals.append("it was saved with another hardware model")
        }
        result.refusals += configuration.differences(from: current.configuration)
        if hostUUID != current.hostUUID {
            let reason = "it was saved on another Mac (\(hostName)); Virtualization only restores a state on the Mac that saved it"
            if allowOtherHost {
                result.warnings.append(reason)
            } else {
                result.refusals.append(reason)
            }
        }
        if hostOSBuild != current.hostOSBuild {
            result.warnings.append("macOS changed since it was saved (\(hostOSBuild) -> \(current.hostOSBuild)); Virtualization may refuse it")
        }
        switch (disk, current.disk) {
        case let (saved?, now?) where saved != now:
            let reason = "the disk image changed since it was saved; the guest's memory would no longer match its disk"
            if allowOtherHost {
                result.warnings.append(reason)
            } else {
                result.refusals.append(reason)
            }
        case (_?, nil):
            result.refusals.append("the disk image it was saved with is gone")
        case (nil, _):
            result.warnings.append("the disk is not a local file, so vphone cannot check it is unchanged since the save")
        default:
            break
        }
        if after == "resume", disk == nil {
            result.warnings.append("the VM kept running after this save, so its disk has probably moved on")
        }
        return result
    }
}

/// The parts of a machine's configuration a saved state depends on, beyond
/// what Virtualization checks itself. Compared field by field so a refusal
/// says which one changed.
public struct VPhoneSavedStateConfiguration: Codable, Equatable, Sendable {
    public let cpuCount: Int
    public let memorySize: UInt64
    public let disk: String
    public let macAddress: String
    public let networkMode: String
    public let screen: String
    public let hardwareKeyboard: Bool
    public let guestProductType: String

    public init(
        cpuCount: Int,
        memorySize: UInt64,
        disk: String,
        macAddress: String,
        networkMode: String,
        screen: String,
        hardwareKeyboard: Bool,
        guestProductType: String,
    ) {
        self.cpuCount = cpuCount
        self.memorySize = memorySize
        self.disk = disk
        self.macAddress = macAddress
        self.networkMode = networkMode
        self.screen = screen
        self.hardwareKeyboard = hardwareKeyboard
        self.guestProductType = guestProductType
    }

    public init(manifest: VPhoneVirtualMachineManifest, effectiveCPUCount: Int, effectiveMemorySize: UInt64) {
        let screen = manifest.screenConfig
        self.init(
            cpuCount: effectiveCPUCount,
            memorySize: effectiveMemorySize,
            disk: manifest.diskLocation.manifestValue,
            macAddress: manifest.networkConfig.macAddress,
            networkMode: manifest.networkConfig.mode.rawValue,
            screen: "\(screen.width)x\(screen.height)@\(screen.pixelsPerInch)",
            hardwareKeyboard: manifest.usesHardwareKeyboard,
            guestProductType: manifest.guestDevice.productType,
        )
    }

    public func differences(from other: Self) -> [String] {
        var changes: [String] = []
        func check<T: Equatable & CustomStringConvertible>(_ name: String, _ a: T, _ b: T) {
            if a != b {
                changes.append("\(name) changed since it was saved (\(a) -> \(b))")
            }
        }
        check("the CPU count", cpuCount, other.cpuCount)
        check("the memory size", memorySize, other.memorySize)
        check("the disk", disk, other.disk)
        check("the MAC address", macAddress, other.macAddress)
        check("the network mode", networkMode, other.networkMode)
        check("the screen", screen, other.screen)
        check("the hardware keyboard setting", hardwareKeyboard, other.hardwareKeyboard)
        check("the guest device", guestProductType, other.guestProductType)
        return changes
    }
}

public enum VPhoneSavedStateError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case unreadableBinding(path: String)
    case missing(path: String)
    case notRestorable(path: String, reasons: [String])
    case alreadyExists(path: String)

    public var description: String {
        switch self {
        case let .unreadableBinding(path):
            "\(path) is not a vphone saved-state binding."
        case let .missing(path):
            "No saved state at \(path)."
        case let .notRestorable(path, reasons):
            "The saved state at \(path) cannot be restored: \(reasons.joined(separator: "; "))."
        case let .alreadyExists(path):
            "\(path) already exists. Choose another path, or remove it first."
        }
    }

    public var errorDescription: String? {
        description
    }
}

// MARK: - Save/restore support diagnosis

/// Finds which parts of a configuration make
/// `validateSaveRestoreSupport()` fail.
///
/// Virtualization's error names only the first unsupported part it meets
/// ("Unsupported multi-touch device in configuration."), so on its own it
/// cannot say whether removing that part would be enough. Each candidate is
/// therefore tried alone: everything removable is removed, then that one part
/// is put back. A part whose presence alone fails is a blocker. If the
/// configuration still fails with every candidate removed, the reason is in
/// something that is not a candidate, and `remainder` says so.
public enum VPhoneSaveRestoreDiagnosis {
    public struct Report: Equatable, Sendable {
        /// Candidates that fail validation on their own, with the message.
        public var blockers: [(name: String, message: String)]
        /// The message when the configuration fails even without every candidate.
        public var remainder: String?

        public static func == (lhs: Report, rhs: Report) -> Bool {
            lhs.blockers.map(\.name) == rhs.blockers.map(\.name)
                && lhs.blockers.map(\.message) == rhs.blockers.map(\.message)
                && lhs.remainder == rhs.remainder
        }

        public var summary: String {
            var parts = blockers.map { "\($0.name) (\($0.message))" }
            if let remainder {
                parts.append("the configuration without any of the checked devices (\(remainder))")
            }
            return parts.isEmpty ? "no single device; only the combination fails" : parts.joined(separator: ", ")
        }
    }

    /// `validate(kept)` validates the configuration with only the candidates
    /// in `kept` present (and everything that is not a candidate), returning
    /// nil when it passes and the failure message otherwise.
    public static func diagnose(candidates: [String], validate: (Set<String>) -> String?) -> Report {
        var report = Report(blockers: [], remainder: nil)
        if let message = validate([]) {
            report.remainder = message
            return report
        }
        for candidate in candidates {
            if let message = validate([candidate]) {
                report.blockers.append((candidate, message))
            }
        }
        return report
    }
}

// MARK: - Host identity

/// Which Mac this is, for `VPhoneSavedStateBinding`.
public enum VPhoneHostIdentity {
    /// `gethostuuid(2)`: the hardware UUID System Information shows
    /// (IOPlatformUUID). Empty if the call fails.
    public static func platformUUID() -> String {
        var raw = [UInt8](repeating: 0, count: 16)
        var wait = timespec(tv_sec: 1, tv_nsec: 0)
        let result = raw.withUnsafeMutableBufferPointer { buffer in
            gethostuuid(buffer.baseAddress!, &wait)
        }
        guard result == 0 else { return "" }
        return UUID(uuid: (
            raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15],
        )).uuidString
    }

    /// `kern.osversion`, the macOS build such as 27A5321.
    public static func osBuild() -> String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    public static func hostName() -> String {
        ProcessInfo.processInfo.hostName
    }

    /// The running vphone build's version.
    public static var vphoneVersion: String {
        VPhoneRuntimeVersion.current
    }
}
