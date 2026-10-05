import Foundation
import VPhoneDesignKit

// MARK: - Host Setup

/// The words of the Host Setup page that depend on the checks' results.
enum VPhoneLaunchpadHostSetupText {
    /// "6 of 6 required passed · 1 advisory warning".
    static func subtitle(passed: Int, required: Int, advisoryWarnings: Int) -> String {
        let summary = String(localized: "\(passed) of \(required) required passed")
        switch advisoryWarnings {
        case 0: return summary
        case 1: return String(localized: "\(summary) · 1 advisory warning")
        default: return String(localized: "\(summary) · \(advisoryWarnings) advisory warnings")
        }
    }

    /// Under "This Mac can run machines.": the advisory checks that warn, by
    /// their titles in lower case.
    static func passedLine(advisoryWarnings titles: [String]) -> String {
        let passed = String(localized: "Every required check passed.")
        let names = titles.map(\.localizedLowercase).formatted(.list(type: .and))
        switch titles.count {
        case 0: return passed
        case 1: return passed + " " + String(localized: "One advisory check needs a look: \(names).")
        default: return passed + " " + String(localized: "\(titles.count) advisory checks need a look: \(names).")
        }
    }

    /// Under "This Mac is not ready yet.": the required checks that fail.
    static func failingLine(_ titles: [String]) -> String {
        String(localized: "Needs a look: \(titles.formatted(.list(type: .and))).")
    }

    /// The low disk space banner, from the check's detail ("41 GB free").
    static func lowDiskText(_ detail: String) -> String {
        String(localized: "Low disk space: \(detail). A new machine’s 64 GB disk may not fit once the guest fills it.")
    }
}

// MARK: - Core Bundles

/// The words of an installed bundle's row on the Core Bundles page.
enum VPhoneLaunchpadBundleText {
    /// Where an installed bundle came from.
    enum Origin: Equatable {
        case release
        case actionsBuild
        /// Built on this Mac; `build` is nil for the bare `-local` an older
        /// Launchpad used.
        case local(build: String?)

        /// Told apart by the store name's suffix.
        init(version: String) {
            if VPhoneLaunchpadNames.isLocalBuild(version) {
                self = .local(build: VPhoneLaunchpadBundleText.localBuild(version))
            } else if version != VPhoneLaunchpadNames.bundleVersion(of: version) {
                self = .actionsBuild
            } else {
                self = .release
            }
        }
    }

    /// The build identifier of a `-local.<build>` version; nil for the bare
    /// `-local` an older Launchpad used, and for any other version.
    static func localBuild(_ version: String) -> String? {
        guard VPhoneLaunchpadNames.isLocalBuild(version),
              let marker = version.range(of: "-local.", options: .backwards)
        else { return nil }
        return String(version[marker.upperBound...])
    }

    /// "Release · Installed Oct 5, 2026 · SHA-256 98daa4d0…". A release shows
    /// the day it was installed, a build the minute too.
    static func provenance(_ origin: Origin, installedAt: Date, sha256: String) -> String {
        let digest = shortDigest(sha256)
        switch origin {
        case let .local(build):
            let date = installedAt.formatted(date: .abbreviated, time: .shortened)
            if let build {
                return String(localized: "Local build \(build) · Installed \(date) · SHA-256 \(digest)")
            }
            return String(localized: "Local build · Installed \(date) · SHA-256 \(digest)")
        case .actionsBuild:
            let date = installedAt.formatted(date: .abbreviated, time: .shortened)
            return String(localized: "GitHub Actions build · Installed \(date) · SHA-256 \(digest)")
        case .release:
            let date = installedAt.formatted(date: .abbreviated, time: .omitted)
            return String(localized: "Release · Installed \(date) · SHA-256 \(digest)")
        }
    }

    static func shortDigest(_ digest: String) -> String {
        "\(digest.prefix(8))…"
    }

    /// Names a few machines; past that, a count.
    static func users(_ names: [String]) -> String {
        if names.isEmpty {
            return String(localized: "Not used by any machine")
        }
        if names.count <= 4 {
            return String(localized: "Used by \(names.formatted(.list(type: .and)))")
        }
        return String(localized: "Used by \(names.count) machines")
    }

    /// Policy exception and preflight folded into one status: the worst of
    /// the two, with a preflight the user chose to skip shown as a warning.
    static func checkStatus(
        policy: VPhoneLaunchpadStatus,
        preflight: VPhoneLaunchpadStatus,
        isAccepted: Bool,
    ) -> VPhoneLaunchpadStatus {
        if policy == .running || preflight == .running {
            return .running
        }
        if policy == .passed, preflight == .passed {
            return .passed
        }
        if isAccepted {
            return .warning
        }
        return policy == .pending && preflight == .pending ? .pending : .failed
    }

    /// The badge after the version. A bundle of an older series runs only
    /// with that series' Launchpad, so it is never checked here and its badge
    /// names the series instead.
    static func checkBadge(
        version: String,
        status: VPhoneLaunchpadStatus,
        policyPassed: Bool,
    ) -> DKListItem.Badge {
        guard VPhoneLaunchpadNames.isCompatibleBundleVersion(version) else {
            let parts = VPhoneLaunchpadNames.bundleVersion(of: version).split(separator: ".")
            guard parts.count >= 2 else {
                return .init(String(localized: "Not supported"), tone: .neutral)
            }
            return .init(String(localized: "Needs Launchpad \(parts[0]).\(parts[1])"), tone: .neutral)
        }
        switch status {
        case .running: return .init(String(localized: "Checking…"), tone: .info)
        case .passed: return .init(String(localized: "Preflight passed"), tone: .success)
        case .warning: return .init(String(localized: "Preflight skipped"), tone: .warning)
        case .pending: return .init(String(localized: "Not checked"), tone: .neutral)
        case .failed:
            return policyPassed
                ? .init(String(localized: "Preflight failed"), tone: .danger)
                : .init(String(localized: "Not allowed to run"), tone: .danger)
        }
    }

    /// The Settings › Bundles row under Preflight.
    static func preflightSummary(preflight: VPhoneLaunchpadStatus, detail: String, isAccepted: Bool) -> String {
        if preflight != .passed, isAccepted {
            return String(localized: "Used without preflight")
        }
        switch preflight {
        case .passed: return String(localized: "Passed preflight on this Mac")
        case .running: return String(localized: "Checking…")
        case .pending: return String(localized: "Not run yet")
        case .warning, .failed:
            let first = detail.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
            return first ?? String(localized: "Failed")
        }
    }
}

// MARK: - Settings

/// The words of the Settings window's library folder rows.
enum VPhoneLaunchpadLibrarySettingsText {
    /// "Default · 4 machines · 41 GB free", "Added · 2 machines · 812 GB free",
    /// or "Added · Not available" for a folder on a volume that is gone.
    static func folderDetail(isDefault: Bool, isAvailable: Bool, machines: Int, freeBytes: Int64?) -> String {
        var parts = [isDefault ? String(localized: "Default") : String(localized: "Added")]
        if isAvailable || isDefault {
            parts.append(machines == 1 ? String(localized: "1 machine") : String(localized: "\(machines) machines"))
            if let freeBytes {
                parts.append(String(localized: "\(VPhoneLaunchpadLibraryFormat.compactSize(freeBytes)) free"))
            }
        } else {
            parts.append(String(localized: "Not available"))
        }
        return parts.joined(separator: " · ")
    }
}
