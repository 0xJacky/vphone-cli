import Foundation

// MARK: - Disk location

/// Where a machine's disk is: a file in the machine folder, or an export on a
/// Network Block Device server.
///
/// The manifest's `diskImage` holds either a plain file name (`Disk.img`) or an
/// `nbd://host[:port]/export` URL. A URL is never a plain file name, so a
/// vphone build from before NBD refuses such a manifest instead of booting a
/// stale `Disk.img` beside it, which could run the same machine twice.
public enum VPhoneDiskLocation: Equatable, Sendable, CustomStringConvertible {
    case file(name: String)
    case networkBlockDevice(VPhoneNBDLocation)

    /// Parses the manifest's `diskImage`.
    public init(manifestValue value: String) throws {
        if value.contains("://") {
            self = try .networkBlockDevice(VPhoneNBDLocation(parsing: value))
        } else if VPhoneVirtualMachineManifest.isPlainFileName(value) {
            self = .file(name: value)
        } else {
            throw VPhoneDiskLocationError.notAFileName(value)
        }
    }

    public var manifestValue: String {
        switch self {
        case let .file(name): name
        case let .networkBlockDevice(location): location.urlString
        }
    }

    public var isNetwork: Bool {
        if case .networkBlockDevice = self { true } else { false }
    }

    public var fileName: String? {
        if case let .file(name) = self { name } else { nil }
    }

    public var description: String {
        switch self {
        case let .file(name): "file \(name)"
        case let .networkBlockDevice(location): "nbd \(location.urlString)"
        }
    }
}

/// An `nbd://` export, as the NBD URI specification spells it
/// (https://github.com/NetworkBlockDevice/nbd/blob/master/doc/uri.md),
/// narrowed to what vphone accepts: TCP, a host, an optional port and a
/// non-empty export name.
///
/// TLS is not supported: Virtualization.framework's NBD client refuses
/// `nbds://` ("The URL is not supported", macOS 27), and its API takes no
/// certificates. The export must therefore be served on a link the host
/// trusts — loopback, a private VLAN, or a tunnel set up outside vphone.
/// Unix-socket and vsock forms are refused as well, to keep the one transport
/// the fleet uses.
public struct VPhoneNBDLocation: Equatable, Sendable {
    public static let defaultPort = 10809

    public let host: String
    public let port: Int
    public let exportName: String

    public init(host: String, port: Int = Self.defaultPort, exportName: String) throws {
        guard !host.isEmpty else { throw VPhoneDiskLocationError.missingHost }
        guard (1 ... 65535).contains(port) else { throw VPhoneDiskLocationError.invalidPort(port) }
        guard !exportName.isEmpty else { throw VPhoneDiskLocationError.missingExportName }
        guard exportName.utf8.count <= 4096, !exportName.contains("\0") else {
            throw VPhoneDiskLocationError.invalid("the export name is too long or contains NUL")
        }
        self.host = host
        self.port = port
        self.exportName = exportName
    }

    public init(parsing value: String) throws {
        guard let schemeEnd = value.range(of: "://") else {
            throw VPhoneDiskLocationError.invalid(value)
        }
        let scheme = value[..<schemeEnd.lowerBound].lowercased()
        switch scheme {
        case "nbd":
            break
        case "nbds", "nbds+unix", "nbds+vsock":
            throw VPhoneDiskLocationError.tlsUnsupported(value)
        default:
            throw VPhoneDiskLocationError.unsupportedScheme(scheme)
        }
        guard let components = URLComponents(string: value) else {
            throw VPhoneDiskLocationError.invalid(value)
        }
        guard components.user == nil, components.password == nil else {
            throw VPhoneDiskLocationError.invalid("credentials are not part of an NBD URL")
        }
        guard components.query == nil, components.fragment == nil else {
            // The query is where the URI spec puts TLS certificates and a
            // socket path, neither of which applies here.
            throw VPhoneDiskLocationError.invalid("an NBD URL here takes no query or fragment")
        }
        guard let host = components.host, !host.isEmpty else {
            throw VPhoneDiskLocationError.missingHost
        }
        let path = components.percentEncodedPath
        let export = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let decoded = export.removingPercentEncoding else {
            throw VPhoneDiskLocationError.invalid(value)
        }
        try self.init(host: host, port: components.port ?? Self.defaultPort, exportName: decoded)
    }

    /// The URL handed to `VZNetworkBlockDeviceStorageDeviceAttachment`, always
    /// with an explicit port.
    public var urlString: String {
        var components = URLComponents()
        components.scheme = "nbd"
        components.host = host
        components.port = port
        components.path = "/" + exportName
        return components.string ?? "nbd://\(host):\(port)/\(exportName)"
    }

    public var url: URL {
        URL(string: urlString)!
    }
}

public enum VPhoneDiskLocationError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case notAFileName(String)
    case tlsUnsupported(String)
    case unsupportedScheme(String)
    case missingHost
    case invalidPort(Int)
    case missingExportName
    case invalid(String)

    public var description: String {
        switch self {
        case let .notAFileName(value):
            "The disk \"\(value)\" is neither a file name inside the VM folder nor an nbd:// URL."
        case let .tlsUnsupported(value):
            "\(value) asks for NBD over TLS, which Virtualization.framework's NBD client does not support. Use nbd:// on a trusted link (loopback, a private network, or a tunnel set up outside vphone)."
        case let .unsupportedScheme(scheme):
            "Disk URLs must be nbd://host[:port]/export; \(scheme):// is not supported."
        case .missingHost:
            "An NBD disk URL needs a host: nbd://host[:port]/export."
        case let .invalidPort(port):
            "NBD port \(port) is outside 1-65535."
        case .missingExportName:
            "An NBD disk URL needs an export name: nbd://host[:port]/export."
        case let .invalid(reason):
            "Invalid NBD disk URL: \(reason)."
        }
    }

    public var errorDescription: String? {
        description
    }
}

// MARK: - NBD options

extension VPhoneVirtualMachineManifest {
    /// How vphone-vm attaches an NBD disk. Ignored for a file disk.
    public struct NBDOptions: Codable, Equatable, Sendable {
        /// Virtualization's own default when nothing is given (macOS 14–27).
        public static let defaultTimeoutSeconds: Double = 5
        public static let timeoutRange: ClosedRange<Double> = 1 ... 600

        /// Seconds the NBD client waits on the connection before it
        /// reconnects. Reconnects are transparent to the guest; a request
        /// stalls meanwhile. Nil means `defaultTimeoutSeconds`.
        public let timeoutSeconds: Double?
        /// Nil means `full`: the guest's flush and barrier commands reach the
        /// server. `none` acknowledges them at once and risks the guest's data
        /// on a host crash, so it is only for throwaway machines.
        public let synchronization: Synchronization?

        public enum Synchronization: String, Codable, Sendable, CaseIterable {
            case full
            case none
        }

        public init(timeoutSeconds: Double? = nil, synchronization: Synchronization? = nil) {
            self.timeoutSeconds = timeoutSeconds
            self.synchronization = synchronization
        }

        public var effectiveTimeout: Double {
            timeoutSeconds ?? Self.defaultTimeoutSeconds
        }

        public var effectiveSynchronization: Synchronization {
            synchronization ?? .full
        }

        public func validate() throws {
            if let timeoutSeconds, !Self.timeoutRange.contains(timeoutSeconds) {
                throw VPhoneDiskLocationError.invalid(
                    "the NBD timeout must be \(Int(Self.timeoutRange.lowerBound))-\(Int(Self.timeoutRange.upperBound)) seconds, not \(timeoutSeconds)",
                )
            }
        }
    }

    /// The disk this manifest names. A manifest that `load(from:)` accepted
    /// always parses; one built in code with a bad value reads as a file.
    public var diskLocation: VPhoneDiskLocation {
        (try? VPhoneDiskLocation(manifestValue: diskImage)) ?? .file(name: diskImage)
    }
}
