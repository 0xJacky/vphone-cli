import Foundation

// MARK: - Status

nonisolated enum VPhoneLaunchpadStatus: String, Codable, Sendable {
    case passed
    case warning
    case failed
    case pending
    case running
}
