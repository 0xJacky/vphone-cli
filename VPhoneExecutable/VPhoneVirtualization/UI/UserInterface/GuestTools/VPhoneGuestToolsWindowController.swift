import AppKit

// MARK: - Entry Points

/// The Data menu items that open a guest tool.
enum VPhoneGuestToolAction {
    case getClipboard
    case setClipboard
    case readSetting
    case writeSetting
}

// MARK: - Window Controller

/// Routes the Data menu's clipboard and preference items to the Guest Tools
/// window, setting up the tool for what the item asked for.
@MainActor
final class VPhoneGuestToolsWindowController {
    let shell: VPhoneGuestToolsShell

    var clipboardModel: VPhoneGuestClipboardModel {
        shell.clipboardModel
    }

    var preferencesModel: VPhoneGuestPreferencesModel {
        shell.preferencesModel
    }

    init(control: VPhoneGuestControl) {
        shell = .shared(for: control)
    }

    func show(_ action: VPhoneGuestToolAction) {
        switch action {
        case .getClipboard:
            clipboardModel.mode = .read
            shell.show(.clipboard)
            Task { await clipboardModel.refresh() }
        case .setClipboard:
            clipboardModel.mode = .write
            clipboardModel.focusComposeRequested = true
            shell.show(.clipboard)
        case .readSetting:
            preferencesModel.mode = .read
            preferencesModel.focusRequest = .domain
            shell.show(.preferences)
        case .writeSetting:
            preferencesModel.mode = .write
            preferencesModel.focusRequest = preferencesModel.trimmedDomain.isEmpty ? .domain : .writeKey
            shell.show(.preferences)
        }
    }
}
