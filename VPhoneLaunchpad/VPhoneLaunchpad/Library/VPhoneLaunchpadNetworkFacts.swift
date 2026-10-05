import Foundation

/// The Mac's shared NAT network, as vmnet runs it for every NAT guest.
///
/// vmnet keeps a moved network in `Shared_Net_Address` and `Shared_Net_Mask`
/// of its preferences (`VPhoneNetworkHost.current` reads the same keys). The
/// file is readable by root only once vmnet has written it, so its facts are
/// known when the file is missing (vmnet's default, 192.168.64.1/24) or
/// readable, and unknown otherwise.
nonisolated struct VPhoneLaunchpadSharedNAT: Hashable, Sendable {
    /// `192.168.64.0/24`.
    var subnet: String
    /// The Mac's own address on it: the guests' gateway and DNS proxy.
    var gateway: String
    /// True when the facts are vmnet's default because it has no preferences.
    var isDefault: Bool

    static let preferences = URL(fileURLWithPath: "/Library/Preferences/SystemConfiguration/com.apple.vmnet.plist")

    static func current(preferences: URL = preferences) -> VPhoneLaunchpadSharedNAT? {
        guard FileManager.default.fileExists(atPath: preferences.path) else {
            return make(address: "192.168.64.1", mask: "255.255.255.0", isDefault: true)
        }
        guard let data = try? Data(contentsOf: preferences),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return make(
            address: values["Shared_Net_Address"] as? String ?? "192.168.64.1",
            mask: values["Shared_Net_Mask"] as? String ?? "255.255.255.0",
            isDefault: values["Shared_Net_Address"] == nil,
        )
    }

    static func make(address: String, mask: String, isDefault: Bool) -> VPhoneLaunchpadSharedNAT? {
        guard let host = parse(address), let netmask = parse(mask) else {
            return nil
        }
        // A mask is ones then zeros.
        let prefix = netmask.nonzeroBitCount
        guard netmask == (prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix)) else {
            return nil
        }
        return VPhoneLaunchpadSharedNAT(
            subnet: "\(format(host & netmask))/\(prefix)",
            gateway: format(host),
            isDefault: isDefault,
        )
    }

    static func parse(_ dotted: String) -> UInt32? {
        let parts = dotted.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return nil
        }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else {
                return nil
            }
            value = value << 8 | UInt32(octet)
        }
        return value
    }

    static func format(_ value: UInt32) -> String {
        [24, 16, 8, 0].map { String((value >> UInt32($0)) & 0xFF) }.joined(separator: ".")
    }
}
