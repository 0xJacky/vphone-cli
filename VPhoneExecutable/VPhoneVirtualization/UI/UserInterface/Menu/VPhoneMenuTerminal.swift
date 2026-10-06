import AppKit

// MARK: - Terminal

extension VPhoneMenuController {
    /// Window › Terminal (⌥⌘3) and New Terminal Tab (⌘T). Both validate
    /// themselves: Terminal needs an agent that reports the `terminal`
    /// capability and says why not in its tooltip; New Terminal Tab also needs
    /// the Terminal window to be key, so ⌘T in the display window still
    /// reaches the guest.
    func makeTerminalItems() -> [NSMenuItem] {
        let terminal = makeValidatedItem(
            "Terminal",
            keyEquivalent: "3",
            modifiers: [.option, .command],
            symbol: "terminal",
            isEnabled: { [weak self] in self?.terminalAvailability.isAvailable == true },
            action: { [weak self] in self?.terminalWindowController.show() },
        )
        terminalItem = terminal
        let newTab = makeValidatedItem(
            "New Terminal Tab",
            keyEquivalent: "t",
            isEnabled: { [weak self] in
                guard let self else { return false }
                return terminalAvailability.isAvailable && terminalWindowController.isKey
            },
            action: { [weak self] in self?.terminalWindowController.newTab() },
        )
        updateTerminalAvailability(capabilities: [])
        return [terminal, .separator(), newTab]
    }

    /// Follows the agent's capabilities; an empty list means disconnected.
    func updateTerminalAvailability(capabilities: [String]) {
        terminalAvailability = VPhoneTerminalAvailability(capabilities: capabilities)
        terminalItem?.toolTip = terminalAvailability.reason
    }
}
