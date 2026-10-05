import AppKit

/// Opens the Guest Tools window on Keychain. The page carries its own item
/// type filter, search field and actions.
@MainActor
class VPhoneKeychainWindowController: NSObject {
    private var shell: VPhoneGuestToolsShell?

    var isKeyWindow: Bool {
        shell?.isKey(showing: .keychain) == true
    }

    func showWindow(control: VPhoneGuestControl) {
        bind(control).show(.keychain)
    }

    func focusSearch() {
        shell?.focusSearchField()
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
