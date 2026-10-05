import AppKit

/// Opens the Guest Tools window on Files.
@MainActor
class VPhoneFileWindowController {
    private var shell: VPhoneGuestToolsShell?

    /// Shows Files at a guest directory, such as an app's data container.
    func showWindow(control: VPhoneGuestControl, path: String) {
        bind(control).showFiles(at: path)
    }

    func showWindow(control: VPhoneGuestControl) {
        bind(control).show(.files)
    }

    private func bind(_ control: VPhoneGuestControl) -> VPhoneGuestToolsShell {
        if let shell, shell.control === control {
            return shell
        }
        let shell = VPhoneGuestToolsShell.shared(for: control)
        self.shell = shell
        return shell
    }
}
