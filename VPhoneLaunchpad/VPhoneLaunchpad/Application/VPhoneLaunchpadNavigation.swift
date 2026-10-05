import Foundation
import VPhoneDesignKit

// MARK: - Pages

extension DKLaunchpadDestination {
    /// ⌘1 to ⌘6, in sidebar order.
    var shortcut: DKShortcut {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return DKShortcut(Character("\(index + 1)"), .command)
    }
}

// MARK: - Panels

/// What `VPhoneLaunchpadModel.present(_:)` asks for. Host Setup and Core
/// Bundle are pages of the window; only a bundle install is a sheet.
enum VPhoneLaunchpadPanel: String, Identifiable {
    case hostSetup
    case coreBundle
    case bundleInstall

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .hostSetup: String(localized: "Host Setup")
        case .coreBundle: String(localized: "Core Bundle")
        case .bundleInstall: String(localized: "Core Bundle Install")
        }
    }

    /// The page that shows it; nil for the install, which is a sheet.
    var destination: DKLaunchpadDestination? {
        switch self {
        case .hostSetup: .hostSetup
        case .coreBundle: .bundles
        case .bundleInstall: nil
        }
    }
}

/// Where the window goes once the launch checks have answered: the first
/// stage that is not ready, or the install sheet of an install that did not
/// finish.
enum VPhoneLaunchpadLaunchRoute: Equatable {
    case stay
    case page(DKLaunchpadDestination)
    case installSheet

    static func after(requiredPassed: Bool, bundlesReady: Bool, installUnfinished: Bool) -> Self {
        if installUnfinished {
            return .installSheet
        }
        if !requiredPassed {
            return .page(.hostSetup)
        }
        if !bundlesReady {
            return .page(.bundles)
        }
        return .stay
    }
}

// MARK: - Sidebar

/// The sidebar's rows and their warnings.
enum VPhoneLaunchpadSidebarMeta {
    /// The rows `DKLaunchpadSidebar` draws, from what Launchpad knows so far.
    /// Machines reads "1/4" with a green dot while one runs, and nothing
    /// until `vm list` has answered, so it does not read 0/0 first.
    /// Firmwares counts the downloaded IPSWs, and shows nothing before the
    /// cache was read or when it holds none. Bundles shows the default Core
    /// Bundle's version. The warning glyph is read out in the user's language.
    static func sections(
        listed: Bool,
        running: Int,
        total: Int,
        firmwareCount: Int?,
        bundleVersion: String?,
        hostWarning: Bool,
        bundleWarning: Bool,
    ) -> [DKSidebarSection<DKLaunchpadDestination>] {
        let warningLabel = String(localized: "Needs attention")
        return DKLaunchpadSidebar.sections(
            runningMachines: listed ? running : nil,
            machineCount: listed ? total : nil,
            firmwareCount: firmwareCount.flatMap { $0 > 0 ? $0 : nil },
            bundleVersion: bundleVersion,
            hostSetupNeedsAttention: hostWarning,
            bundlesNeedAttention: bundleWarning,
        ).map { section in
            var section = section
            for index in section.items.indices {
                section.items[index].warningLabel = warningLabel
            }
            return section
        }
    }

    /// Host Setup warns when a required check fails or an advisory one warns,
    /// once the checks have answered.
    static func hostWarning(isChecking: Bool, requiredPassed: Bool, advisoryWarnings: Int) -> Bool {
        !isChecking && (!requiredPassed || advisoryWarnings > 0)
    }

    /// Bundles warns once the host is ready but no usable bundle is, unless an
    /// install is under way or stopped at checks the user may skip.
    static func bundleWarning(requiredPassed: Bool, isReady: Bool, isInstalling: Bool, canSkip: Bool) -> Bool {
        requiredPassed && !isReady && !isInstalling && !canSkip
    }
}
