import AppKit
import VPhoneDesignKit

// MARK: - Panels

/// The guest inspection tools the Diagnostics and Device menus open, in the
/// order those menus list them.
enum VPhoneGuestPanel: CaseIterable {
    case deviceInfo
    case processes
    case console
    case crashLogs
    case services
    case controls

    /// The `/v1/health` capability an agent must report before the panel can
    /// talk to it. Older agents answer "Unknown method" for everything else.
    var capability: String {
        switch self {
        case .deviceInfo: "device_info"
        case .processes: "processes"
        case .console, .crashLogs: "logs"
        case .services: "services"
        case .controls: "display"
        }
    }

    /// The Guest Tools page that shows this panel.
    var tool: DKGuestTool {
        switch self {
        case .deviceInfo: .deviceInfo
        case .processes: .processes
        case .console: .console
        case .crashLogs: .crashLogs
        case .services: .services
        case .controls: .controls
        }
    }
}

// MARK: - Window Controller

/// Opens the Guest Tools window on a panel. The window keeps each panel's
/// model, so reopening a panel shows its last loaded state.
@MainActor
final class VPhoneGuestPanelsWindowController {
    let shell: VPhoneGuestToolsShell

    init(control: VPhoneGuestControl) {
        shell = .shared(for: control)
    }

    func show(_ panel: VPhoneGuestPanel) {
        shell.show(panel.tool)
    }
}
