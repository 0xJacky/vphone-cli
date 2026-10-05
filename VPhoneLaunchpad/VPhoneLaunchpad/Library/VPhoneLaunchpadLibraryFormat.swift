import Foundation

// MARK: - Sizes

/// How the Library pages write sizes: decimal units, as the Finder does, with
/// one decimal below 100 GB ("9.4 GB", "13.9 GB") and none above ("166 GB").
nonisolated enum VPhoneLaunchpadLibraryFormat {
    static func size(_ bytes: Int64) -> String {
        let value = Double(max(0, bytes))
        let units: [(Double, String)] = [(1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB")]
        for (scale, unit) in units where value >= scale {
            let scaled = value / scale
            // 99.96 GB rounds to "100.0 GB" with one decimal; write it as 100.
            let text = scaled >= 99.95 || unit == "KB" || unit == "MB"
                ? String(format: "%.0f", scaled.rounded())
                : String(format: "%.1f", scaled)
            return "\(text) \(unit)"
        }
        return "\(Int64(value)) bytes"
    }

    /// A size short enough for a usage bar's value: whole units from 10 up
    /// ("31 GB"), one decimal below ("2.4 GB").
    static func compactSize(_ bytes: Int64) -> String {
        let value = Double(max(0, bytes))
        for (scale, unit) in [(1e12, "TB"), (1e9, "GB"), (1e6, "MB")] where value >= scale {
            let scaled = value / scale
            return scaled >= 9.95 ? "\(Int(scaled.rounded())) \(unit)" : "\(String(format: "%.1f", scaled)) \(unit)"
        }
        return size(bytes)
    }

    /// A machine's disk as `vm new --disk-size` set it: whole gigabytes.
    static func diskSize(_ bytes: Int64) -> String {
        let gigabytes = Double(max(0, bytes)) / 1e9
        return gigabytes.rounded() == gigabytes || gigabytes >= 10
            ? "\(Int(gigabytes.rounded())) GB"
            : size(bytes)
    }

    /// A path with the home folder written as `~`.
    static func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// `2222 → 22`, with the protocol after the guest port when it is not TCP
    /// and the host address before the host port when it is not loopback.
    static func portForward(transport: String, hostAddress: String?, hostPort: Int, guestPort: Int) -> String {
        let host = hostAddress.flatMap { $0.isEmpty || $0 == "127.0.0.1" ? nil : $0 }
        let from = host.map { "\($0):\(hostPort)" } ?? "\(hostPort)"
        let kind = transport.lowercased()
        return kind == "tcp" || kind.isEmpty ? "\(from) → \(guestPort)" : "\(from) → \(guestPort)/\(kind)"
    }

    /// A MAC address in a form two spellings of the same address share:
    /// bootpd drops leading zeros (`2:8b:…`), configs keep them.
    static func normalizedMAC(_ mac: String) -> String? {
        let octets = mac.split(separator: ":")
        guard octets.count == 6 else {
            return nil
        }
        var parts: [String] = []
        for octet in octets {
            guard let value = UInt8(octet, radix: 16) else {
                return nil
            }
            parts.append(String(format: "%02x", value))
        }
        return parts.joined(separator: ":")
    }
}
