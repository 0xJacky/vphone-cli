import Foundation
import SwiftUI
import VPhoneDesignKit

// MARK: - JSON Values

/// vphoned answers with JSONSerialization objects. These readers accept the
/// NSNumber and string spellings the guest uses for the same field.
extension [String: Any] {
    func string(_ key: String) -> String? {
        switch self[key] {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: nil
        }
    }

    func int(_ key: String) -> Int? {
        switch self[key] {
        case let value as NSNumber: value.intValue
        case let value as String: Int(value)
        default: nil
        }
    }

    func double(_ key: String) -> Double? {
        switch self[key] {
        case let value as NSNumber: value.doubleValue
        case let value as String: Double(value)
        default: nil
        }
    }

    func bool(_ key: String) -> Bool? {
        switch self[key] {
        case let value as NSNumber: value.boolValue
        case let value as String: ["1", "true", "yes", "on"].contains(value.lowercased())
        default: nil
        }
    }

    func object(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func objects(_ key: String) -> [[String: Any]] {
        self[key] as? [[String: Any]] ?? []
    }
}

// MARK: - Formatting

enum VPhonePanelFormat {
    /// Bytes in powers of 1024 at three significant digits (`DKFormat.bytes`).
    static func bytes(_ value: Int64?) -> String {
        DKFormat.bytes(value)
    }

    static func bytes(_ value: Int?) -> String {
        DKFormat.bytes(value.map(Int64.init))
    }

    /// A duration in whole seconds, such as `41 s`, `3h 12m`, `2d 04h`.
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return DKFormat.placeholder }
        // Whole seconds under a minute; from a minute up the two-unit form.
        return seconds < 60
            ? DKFormat.duration(wholeSeconds: Int64(seconds))
            : DKFormat.duration(seconds: seconds)
    }

    /// CPU time, with three significant digits under a minute for
    /// short-lived processes (`3.30 s`).
    static func cpuTime(_ seconds: Double?) -> String {
        guard let seconds else { return DKFormat.placeholder }
        return DKFormat.duration(seconds: seconds)
    }

    /// A date and time to the second, with today and yesterday named, as
    /// "Today at 09:41:02".
    static func date(_ epoch: Double?, locale: Locale = .current) -> String {
        guard let epoch, epoch > 0 else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: Date(timeIntervalSince1970: epoch))
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return DKFormat.placeholder }
        return DKFormat.percent(fraction)
    }
}

// MARK: - Empty State

/// The centered placeholder a panel shows before its first load or when a
/// filter matches nothing.
struct VPhonePanelEmptyState: View {
    let title: LocalizedStringKey
    let systemImage: String
    var message: LocalizedStringKey?

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title, bundle: VPhoneLocalization.bundle)
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            if let message {
                Text(message, bundle: VPhoneLocalization.bundle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Monospaced Cell

/// A single-line table cell in the research-instrument monospace style.
struct VPhonePanelMonoText: View {
    let value: String
    var secondary = false

    init(_ value: String, secondary: Bool = false) {
        self.value = value
        self.secondary = secondary
    }

    var body: some View {
        Text(value)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(secondary ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(value)
    }
}
