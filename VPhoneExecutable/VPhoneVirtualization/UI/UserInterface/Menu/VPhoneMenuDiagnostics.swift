import AppKit

// MARK: - Diagnostics Menu

/// Read-mostly inspection of the running guest. Each panel item opens its
/// panel; Developer Mode Status and the agent items answer in an alert.
extension VPhoneMenuController {
    func buildDiagnosticsMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Diagnostics")
        menu.autoenablesItems = false

        menu.addItem(makePanelItem(.deviceInfo, "Device Info", keyEquivalent: "i", symbol: "info.circle"))
        menu.addItem(makePanelItem(.processes, "Processes", keyEquivalent: "p", symbol: "cpu"))
        menu.addItem(makePanelItem(.services, "Services", keyEquivalent: "s", symbol: "gearshape.2"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makePanelItem(.console, "Console", keyEquivalent: "l", symbol: "terminal"))
        menu.addItem(makePanelItem(.crashLogs, "Crash Logs", keyEquivalent: "c", symbol: "exclamationmark.triangle"))
        menu.addItem(NSMenuItem.separator())

        // Off unless asked for: the display window's status line then carries
        // the frames the guest presented in the last second.
        let frameRateItem = makeItem("Show Frame Rate", action: #selector(toggleFrameRateDisplay))
        frameRateItem.state = VPhoneFrameRateDisplay.isEnabled ? .on : .off
        frameRateItem.isEnabled = VPhoneFrameRateMeter.isSupported
        menu.addItem(frameRateItem)

        let devModeStatus = makeItem(
            "Developer Mode Status",
            action: #selector(devModeStatus),
            symbol: "hammer",
        )
        devModeStatus.isEnabled = false
        connectDevModeStatusItem = devModeStatus
        menu.addItem(devModeStatus)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: "Guest Agent"))

        let ping = makeItem("Ping", action: #selector(sendPing), symbol: "dot.radiowaves.left.and.right")
        ping.isEnabled = false
        connectPingItem = ping
        menu.addItem(ping)

        let guestHash = makeItem("Guest Agent Hash", action: #selector(queryGuestHash), symbol: "number")
        guestHash.isEnabled = false
        connectGuestHashItem = guestHash
        menu.addItem(guestHash)

        item.submenu = menu
        return item
    }

    /// A menu item that opens one guest panel with ⌥⌘ plus the given key.
    func makePanelItem(
        _ panel: VPhoneGuestPanel,
        _ title: String,
        keyEquivalent: String,
        symbol: String,
    ) -> NSMenuItem {
        let item = makeItem(
            title,
            action: #selector(openPanel(_:)),
            keyEquivalent: keyEquivalent,
            modifiers: [.command, .option],
            symbol: symbol,
        )
        item.representedObject = panel
        item.isEnabled = false
        panelMenuItems[panel] = item
        return item
    }

    /// The app menu's Machine Details… (⌘I): Guest Tools on Device Info, where
    /// the machine's details are. The display window's title bar holds only
    /// Home, so this is the way in from the window. Available while the guest
    /// agent is connected, as Guest Tools is.
    func makeMachineDetailsItem() -> NSMenuItem {
        makeValidatedItem(
            "Machine Details…",
            keyEquivalent: "i",
            symbol: "info.circle",
            isEnabled: { [weak self] in self?.guestToolsAvailable == true },
            action: { [weak self] in self?.guestPanelsWindowController.shell.show(.deviceInfo) },
        )
    }

    /// Window > Guest Tools. It opens Guest Tools on the tool it showed last,
    /// Device Info the first time, and is available while the guest agent is
    /// connected.
    /// The Window menu enables its items itself, so this one validates.
    func makeGuestToolsItem() -> NSMenuItem {
        makeValidatedItem(
            "Guest Tools",
            symbol: "sidebar.trailing",
            isEnabled: { [weak self] in self?.guestToolsAvailable == true },
            action: { [weak self] in self?.guestPanelsWindowController.shell.showLastTool() },
        )
        .command(.guestTools)
    }

    /// Enables the panels the connected agent can serve, and Guest Tools while
    /// it reports any capability. An empty list, as on disconnect, disables
    /// them all.
    func updatePanelAvailability(capabilities: [String]) {
        guestToolsAvailable = !capabilities.isEmpty
        updateTerminalAvailability(capabilities: capabilities)
        for (panel, item) in panelMenuItems {
            item.isEnabled = capabilities.contains(panel.capability)
        }
        for item in rotateMenuItems {
            item.isEnabled = capabilities.contains("display")
        }
    }

    @objc func openPanel(_ sender: NSMenuItem) {
        guard let panel = sender.representedObject as? VPhoneGuestPanel else { return }
        guestPanelsWindowController.show(panel)
    }

    /// Shows the guest's frame rate on the display window's status line. Persisted.
    @objc func toggleFrameRateDisplay(_ sender: NSMenuItem) {
        let enabled = !VPhoneFrameRateDisplay.isEnabled
        VPhoneFrameRateDisplay.isEnabled = enabled
        sender.state = enabled ? .on : .off
        onFrameRateDisplayChange?(enabled)
    }

    @objc func devModeStatus() {
        Task {
            do {
                let enabled = try await control.isDeveloperModeEnabled()
                VPhoneAlert.present(
                    title: "Developer Mode",
                    message: enabled ? "Developer Mode is enabled." : "Developer Mode is disabled.",
                    style: .informational,
                )
            } catch {
                VPhoneAlert.present(
                    title: "Developer Mode",
                    message: "Unable to read Developer Mode status. Check that the guest agent is connected, then try again.",
                    style: .warning,
                )
            }
        }
    }

    @objc func sendPing() {
        Task {
            do {
                try await control.sendPing()
                VPhoneAlert.present(title: "Ping", message: "The guest responded.", style: .informational)
            } catch {
                VPhoneAlert.present(
                    title: "Ping",
                    message: "The guest did not respond. Check that the guest agent is connected, then try again.",
                    style: .warning,
                )
            }
        }
    }

    @objc func queryGuestHash() {
        Task {
            do {
                let hash = try await control.guestBinaryHash()
                VPhoneAlert.present(title: "Guest Agent Hash", message: "SHA-256: \(hash)", style: .informational)
            } catch {
                VPhoneAlert.present(
                    title: "Guest Agent Hash",
                    message: "Unable to read the guest agent hash. Check that the guest agent is connected, then try again.",
                    style: .warning,
                )
            }
        }
    }
}
