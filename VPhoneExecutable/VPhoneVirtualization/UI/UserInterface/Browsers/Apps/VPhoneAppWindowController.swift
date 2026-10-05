import AppKit

/// Opens the Guest Tools window on Apps.
@MainActor
final class VPhoneAppWindowController: NSObject {
    /// Opens the File Browser at a guest path, such as an app's data
    /// container. Without it, the Guest Tools window switches to Files itself.
    var onRevealPath: ((String) -> Void)? {
        didSet { shell?.onRevealPath = onRevealPath }
    }

    private var shell: VPhoneGuestToolsShell?

    var isKeyWindow: Bool {
        shell?.isKey(showing: .apps) == true
    }

    func showWindow(control: VPhoneGuestControl) {
        bind(control).show(.apps)
    }

    func focusSearch() {
        shell?.appsModel.isSearchFocusRequested = true
        shell?.focusSearchField()
    }

    private func bind(_ control: VPhoneGuestControl) -> VPhoneGuestToolsShell {
        if let shell, shell.control === control {
            return shell
        }
        let shell = VPhoneGuestToolsShell.shared(for: control)
        if let onRevealPath {
            shell.onRevealPath = onRevealPath
        }
        self.shell = shell
        return shell
    }
}
