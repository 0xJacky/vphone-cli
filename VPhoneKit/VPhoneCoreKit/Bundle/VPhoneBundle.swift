import Foundation

// MARK: - Bundle

public struct VPhoneBundle: Sendable {
    public let url: URL
    public let manifest: VPhoneVirtualMachineManifest

    public init(url: URL, manifest: VPhoneVirtualMachineManifest) {
        self.url = url
        self.manifest = manifest
    }

    public var name: String {
        url.lastPathComponent
    }

    public var configURL: URL {
        url.appendingPathComponent("config.plist")
    }

    /// Zero for an NBD disk, whose size only its server knows.
    public var diskSizeBytes: Int64 {
        guard let name = manifest.diskLocation.fileName else { return 0 }
        let disk = url.appendingPathComponent(name)
        let attrs = try? FileManager.default.attributesOfItem(atPath: disk.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Throws for a machine whose disk is on an NBD server. Copying,
    /// snapshotting, rebasing, exporting or patching a machine takes its disk
    /// together with its SEP storage; with the disk on a server vphone would
    /// take only half of the pair, or make two machines write one disk.
    public func requireLocalDisk(for operation: String) throws {
        if case let .networkBlockDevice(location) = manifest.diskLocation {
            throw VPhoneBundleDiskError.networkDisk(machine: name, url: location.urlString, operation: operation)
        }
    }

    public static func load(at url: URL) throws -> VPhoneBundle {
        let manifest = try VPhoneVirtualMachineManifest.load(
            from: url.appendingPathComponent("config.plist"),
        )
        return VPhoneBundle(url: url, manifest: manifest)
    }
}

public enum VPhoneBundleDiskError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case networkDisk(machine: String, url: String, operation: String)

    public var description: String {
        switch self {
        case let .networkDisk(machine, url, operation):
            "\(machine)'s disk is on an NBD server (\(url)), so vphone cannot \(operation) it: that needs the disk and its SEP storage together. Do it on the storage side, or switch the machine back to a local disk with `vphone-cli vm storage \(machine) --disk Disk.img`."
        }
    }

    public var errorDescription: String? {
        description
    }
}
