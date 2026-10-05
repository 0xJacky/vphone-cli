import Foundation
import VPhoneDesignKit

// MARK: - Pages

extension DKLaunchpadDestination {
    /// The page's name in the sidebar, the View menu and the window title.
    /// The kit's own `title` is not localized.
    var localizedTitle: String {
        switch self {
        case .machines: String(localized: "Machines")
        case .firmwares: String(localized: "Firmwares")
        case .disks: String(localized: "Disks")
        case .bundles: String(localized: "Bundles")
        case .network: String(localized: "Network")
        case .hostSetup: String(localized: "Host Setup")
        }
    }

    /// ⌘1 to ⌘6, in sidebar order.
    var shortcut: DKShortcut {
        let index = Self.allCases.firstIndex(of: self) ?? 0
        return DKShortcut(Character("\(index + 1)"), .command)
    }
}

extension DKLaunchpadSection {
    var localizedTitle: String {
        switch self {
        case .library: String(localized: "Library")
        case .system: String(localized: "System")
        }
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

/// The trailing text and warnings of the sidebar rows.
enum VPhoneLaunchpadSidebarMeta {
    struct Meta: Equatable {
        var text: String
        var tone: DKTone?
        var isMonospaced = false
    }

    /// "1/4" with a green dot while one runs. Nothing until `vm list` has
    /// answered, so it does not read 0/0 first.
    static func machines(listed: Bool, running: Int, total: Int) -> Meta? {
        guard listed else {
            return nil
        }
        return Meta(text: "\(running)/\(total)", tone: running > 0 ? .success : .idle)
    }

    /// The downloaded IPSWs; nothing before the cache was read or when it
    /// holds none.
    static func firmwares(count: Int?) -> Meta? {
        guard let count, count > 0 else {
            return nil
        }
        return Meta(text: "\(count)")
    }

    /// The default Core Bundle's version.
    static func bundles(defaultVersion: String?) -> Meta? {
        guard let defaultVersion, !defaultVersion.isEmpty else {
            return nil
        }
        return Meta(text: defaultVersion, isMonospaced: true)
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
