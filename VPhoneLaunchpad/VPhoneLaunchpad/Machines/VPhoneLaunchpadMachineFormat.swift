import Foundation

// MARK: - Machine formatting

/// How the Machines page and its sheets write and read a machine's values:
/// sizes, port forwards, MAC addresses, mDNS names and the creation step
/// strip. Free of SwiftUI so the standalone tests can run it.
nonisolated enum VPhoneLaunchpadMachineFormat {
    // MARK: - Sizes

    /// "8 GB" for whole gigabytes, else "3000 MB".
    static func memory(_ megabytes: Int) -> String {
        megabytes % 1024 == 0 ? "\(megabytes / 1024) GB" : "\(megabytes) MB"
    }

    /// Decimal, as iOS and the creation stepper count it.
    static func disk(_ bytes: Int64) -> String {
        "\(bytes / 1_000_000_000) GB"
    }

    // MARK: - Port forwards

    /// The `--forward` argument for a new forward,
    /// `tcp:127.0.0.1:8022:22`, or nil while either port is not a port.
    static func forwardArgument(transport: String, hostPort: String, guestPort: String, onAllAddresses: Bool) -> String? {
        guard let host = Int(hostPort.trimmingCharacters(in: .whitespaces)), (1 ... 65535).contains(host),
              let guest = Int(guestPort.trimmingCharacters(in: .whitespaces)), (1 ... 65535).contains(guest)
        else { return nil }
        return "\(transport):\(onAllAddresses ? "0.0.0.0" : "127.0.0.1"):\(host):\(guest)"
    }

    /// `tcp:127.0.0.1:8022:22` as `TCP 8022 → 22`; the address it listens
    /// on is `forwardHost(_:)`. Anything else is shown as it is.
    static func forwardLabel(_ argument: String) -> String {
        let parts = argument.split(separator: ":")
        guard parts.count == 4 else { return argument }
        return "\(parts[0].uppercased()) \(parts[2]) → \(parts[3])"
    }

    /// The address a forward listens on: `127.0.0.1` for this Mac only,
    /// `0.0.0.0` for other devices too. Nil when the argument is not a
    /// forward.
    static func forwardHost(_ argument: String) -> String? {
        let parts = argument.split(separator: ":")
        return parts.count == 4 ? String(parts[1]) : nil
    }

    // MARK: - Network names

    /// A unicast, locally administered address, the kind no vendor assigns.
    static func randomMACAddress() -> String {
        var bytes = (0 ..< 6).map { _ in UInt8.random(in: 0 ... 255) }
        bytes[0] = (bytes[0] & 0xFC) | 0x02
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    /// Six colon-separated pairs of hex digits.
    static func isMACAddress(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 6 && parts.allSatisfy { $0.count == 2 && $0.allSatisfy(\.isHexDigit) }
    }

    /// The mDNS name `--mdns on` gives a machine: its name with everything
    /// but ASCII letters and digits turned into single hyphens, trimmed of
    /// hyphens and cut to one DNS label.
    static func localHostName(for name: String) -> String {
        var label = ""
        for character in name {
            if character.isASCII, character.isLetter || character.isNumber {
                label.append(character)
            } else if !label.hasSuffix("-") {
                label.append("-")
            }
        }
        label = String(label.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(63))
        label = label.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return label.isEmpty ? "vphone" : label
    }

    // MARK: - Creation steps

    /// A creation step as the step strip draws it.
    enum StepState: Hashable, Sendable {
        case done, active, failed, pending
    }

    /// The tone of one segment of the strip.
    enum SegmentTone: Hashable, Sendable {
        case success, warning, danger
    }

    /// One segment of the step strip: full and green once the step is done,
    /// full and red when it failed, filled as far as the download has come
    /// while it runs, and empty before.
    static func segment(_ state: StepState, progress: Double?) -> (fraction: Double, tone: SegmentTone) {
        switch state {
        case .done: (1, .success)
        case .failed: (1, .danger)
        case .active: (min(max(progress ?? 0, 0), 1), .warning)
        case .pending: (0, .warning)
        }
    }

    /// The number of the step that runs, or failed, counting from one; nil
    /// when every step is done or none has started.
    static func currentStepNumber(_ states: [StepState]) -> Int? {
        states.firstIndex { $0 == .active || $0 == .failed }.map { $0 + 1 }
    }
}

// MARK: - Terminal

/// Why the VM's Terminal window did not open, from the error vphone-vm
/// answered on vphone.sock. Nil for an error with nothing to add, which is
/// then shown as it came.
nonisolated enum VPhoneLaunchpadTerminalFailure {
    static func reason(forDetail detail: String?) -> String? {
        guard let detail else { return nil }
        if detail.hasPrefix("unknown command") {
            return String(localized: "This machine runs a Core Bundle without the Terminal. Change it to a newer bundle, then start the machine again.")
        }
        if detail.contains("headless") {
            return String(localized: "The machine was started without a window. Stop it and start it with its window to use the Terminal.")
        }
        return nil
    }
}
