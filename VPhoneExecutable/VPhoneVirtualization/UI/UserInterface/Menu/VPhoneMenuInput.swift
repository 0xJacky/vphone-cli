import AppKit
import LocalAuthentication
import VPhoneCoreKit

// MARK: - Input Menu

/// How the Mac drives the guest: the Controls panel, the hardware keyboard,
/// trackpad gestures and Touch ID, and the guest keys the Mac keyboard lacks.
extension VPhoneMenuController {
    func buildInputMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Input", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Input")
        menu.autoenablesItems = false
        menu.addItem(makePanelItem(.controls, "Controls", keyEquivalent: "k", symbol: "slider.horizontal.3"))
        menu.addItem(NSMenuItem.separator())
        let keyboardItem = makeItem(
            "Use Hardware Keyboard",
            action: #selector(toggleHardwareKeyboard),
            keyEquivalent: "k",
            modifiers: [.command, .shift],
            symbol: "keyboard",
        )
        keyboardItem.isEnabled = false
        keyboardItem.toolTip = VPhoneLocalization.text("Changing the hardware keyboard requires restarting the virtual machine.")
        hardwareKeyboardItem = keyboardItem
        menu.addItem(keyboardItem)
        // Trackpad scroll and pinch arrive as ordinary NSEvents; the view turns
        // them into guest touches. Off hands both back to AppKit untouched.
        let trackpadItem = makeItem(
            "Trackpad Scroll & Pinch to Touch",
            action: #selector(toggleTrackpadGestures),
            symbol: "hand.draw",
        )
        trackpadItem.state = VPhoneTrackpadGestures.isEnabled ? .on : .off
        trackpadGesturesItem = trackpadItem
        menu.addItem(trackpadItem)
        let tidItem = makeItem("Touch ID Home Forwarding", action: #selector(toggleTouchIDForwarding))
        if hasTouchID {
            let tidEnabled = !UserDefaults.standard.bool(forKey: "touchIDForwardingDisabled")
            tidItem.state = tidEnabled ? .on : .off
        } else {
            tidItem.isEnabled = false
            tidItem.state = .off
        }
        touchIDMenuItem = tidItem
        menu.addItem(tidItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem("Open Guest Spotlight", action: #selector(sendSpotlight), symbol: "magnifyingglass"))
        menu.addItem(makeItem("Switch Guest Input Source", action: #selector(sendGlobe), symbol: "globe"))
        item.submenu = menu
        return item
    }

    @objc func sendSpotlight() {
        keySender.sendSpotlight()
    }

    @objc func sendGlobe() {
        keySender.sendGlobe()
    }

    @objc func toggleHardwareKeyboard() {
        guard let vm, let change = onHardwareKeyboardChange,
              hardwareKeyboardItem?.isEnabled == true else { return }
        guard screenRecorder?.isRecording != true else {
            VPhoneAlert.present(
                title: "Recording in Progress",
                message: "Stop the screen recording before changing the hardware keyboard.",
                style: .warning,
            )
            return
        }
        let enabled = !vm.usesHardwareKeyboard
        hardwareKeyboardItem?.isEnabled = false
        VPhoneAlert.present(
            title: enabled ? "Enable Hardware Keyboard?" : "Disable Hardware Keyboard?",
            message: "Changing the hardware keyboard requires restarting the virtual machine. Save your work in the guest first. The setting is saved for this machine. With the hardware keyboard disabled, tap a text field to use the guest's software keyboard.",
            style: .warning,
            buttons: ["Restart and Apply", "Cancel"],
        ) { [weak self] response in
            guard let self else { return }
            guard response == .alertFirstButtonReturn else {
                hardwareKeyboardItem?.isEnabled = true
                return
            }
            Task { [weak self] in
                do {
                    try await change(enabled)
                } catch {
                    self?.hardwareKeyboardItem?.isEnabled = true
                    VPhoneAlert.present(
                        title: "Unable to Change Hardware Keyboard",
                        message: error.localizedDescription,
                        style: .warning,
                    )
                }
            }
        }
    }

    /// Replays trackpad scroll and pinch inside the guest instead of letting
    /// AppKit scroll the window. Persisted, so the choice survives relaunches.
    @objc func toggleTrackpadGestures() {
        let enabled = !VPhoneTrackpadGestures.isEnabled
        VPhoneTrackpadGestures.isEnabled = enabled
        trackpadGesturesItem?.state = enabled ? .on : .off
        captureView?.trackpadGesturesEnabled = enabled
    }

    @objc func toggleTouchIDForwarding() {
        guard let monitor = touchIDMonitor, let item = touchIDMenuItem else { return }
        monitor.isEnabled.toggle()
        item.state = monitor.isEnabled ? .on : .off
        UserDefaults.standard.set(!monitor.isEnabled, forKey: "touchIDForwardingDisabled")
    }
}

private extension VPhoneMenuController {
    var hasTouchID: Bool {
        let ctx = LAContext()
        ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType == .touchID
    }
}
