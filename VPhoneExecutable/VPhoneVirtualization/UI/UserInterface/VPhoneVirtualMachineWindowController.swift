import AppKit
import Foundation
import Virtualization
import VPhoneCoreKit
import VPhoneDesignKit

@MainActor
class VPhoneVirtualMachineWindowController: NSObject, NSWindowDelegate {
    private var windowController: NSWindowController?
    private weak var control: VPhoneGuestControl?
    private weak var virtualMachineView: VPhoneVirtualMachineView?
    private(set) var touchIDMonitor: VPhoneTouchIDMonitor?
    private let chrome = VPhoneDisplayChromeModel()
    private weak var content: VPhoneDisplayWindowContentView?
    private var timers: [Timer] = []
    private var keyStateObservers: [NSObjectProtocol] = []
    private var frameRateTimer: Timer?
    private var frameRateSampledAt: CFTimeInterval = 0

    var captureView: VPhoneVirtualMachineView? {
        virtualMachineView
    }

    func showWindow(
        for vm: VZVirtualMachine,
        screenWidth: Int,
        screenHeight: Int,
        screenScale: Double,
        hardwareKeyboardEnabled: Bool,
        keySender: VPhoneVirtualMachineKeySender,
        control: VPhoneGuestControl,
        name: String,
        sceneIdentifier: String,
    ) {
        self.control = control

        let view = VPhoneVirtualMachineView()
        view.virtualMachine = vm
        view.hardwareKeyboardEnabled = hardwareKeyboardEnabled
        view.capturesSystemKeys = hardwareKeyboardEnabled
        view.keySender = keySender
        view.control = control
        view.clipboardSync = VPhoneClipboardSync(control: control)
        virtualMachineView = view
        let container = VPhoneDisplayContainerView(displayView: view)
        displayContainer = container

        // The guest display opens at one Mac point per panel point; the
        // window adds the bars above and below it.
        let scale = CGFloat(screenScale)
        panelSize = NSSize(
            width: CGFloat(screenWidth) / scale,
            height: CGFloat(screenHeight) / scale,
        )
        container.panelSize = panelSize

        chrome.machineName = name
        chrome.onHome = { [weak self] in self?.homePressed() }
        chrome.onGuestTools = { [weak self] in self?.press(.guestTools) }
        chrome.onRotateLeft = { [weak self] in self?.press(.rotateLeft) }
        chrome.onCopyScreenshot = { [weak self] in self?.press(.copyScreenshot) }
        chrome.onToggleRecording = { [weak self] in self?.press(.toggleRecording) }
        let content = VPhoneDisplayWindowContentView(display: container, chrome: chrome)
        self.content = content

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: panelSize).outset(by: content.chromeInsets),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )

        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .normal
        VPhoneAlert.hostWindow = window
        window.title = name
        // The chrome is the content's own, window buttons included: the
        // system title bar is transparent and its buttons hidden. `window.title`
        // and `window.subtitle` are still set for the Window menu and
        // accessibility.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.contentView = content
        setSystemWindowButtonsHidden(true, in: window)

        // The scene belongs to the VM, not to the app: every VM directory keeps
        // its own window frame, and a newly created VM opens centered instead
        // of inheriting the last frame another VM saved.
        let sceneName = "vphone-scene-\(sceneIdentifier)"
        window.identifier = NSUserInterfaceItemIdentifier(sceneName)
        if !window.setFrameUsingName(sceneName) {
            window.center()
        }
        window.setFrameAutosaveName(sceneName)
        observeKeyState(of: window)
        observeRecording()
        // A frame saved while the guest was sideways, or before the window
        // had its bars, is reshaped: the guest boots in portrait, and the
        // orientation poll turns it again if not.
        applyOrientation(.portrait, to: window, force: true)

        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        windowController = controller

        keySender.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        let monitor = VPhoneTouchIDMonitor()
        monitor.start(control: control, window: window)
        touchIDMonitor = monitor

        // Poll vphoned status for the bars and the subtitle.
        updateStatus(control: control)
        timers.append(Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let control = self.control else { return }
                self.updateStatus(control: control)
                self.captureView?.clipboardSync?.connectionChanged(connected: control.isConnected)
            }
        })

        // The menu sets the orientation before the guest turns, and the poll
        // after; either way the window follows it.
        control.observeInterfaceOrientation { [weak self, weak window] orientation in
            guard let self, let window else { return }
            applyOrientation(orientation ?? .portrait, to: window)
        }
        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOrientation() }
        })
        setFrameRateDisplay(VPhoneFrameRateDisplay.isEnabled)
    }

    // MARK: - Close

    /// Closing the display window stops the VM, so the close button asks the
    /// same question as ⌘Q, with the window still up, instead of closing
    /// first. `closeForRestart` closes without asking.
    func windowShouldClose(_: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    /// Disconnect the old display and input devices before rebuilding the VM.
    func closeForRestart() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        frameRateTimer?.invalidate()
        frameRateTimer = nil
        keyStateObservers.forEach { NotificationCenter.default.removeObserver($0) }
        keyStateObservers.removeAll()
        NotificationCenter.default.removeObserver(self)
        touchIDMonitor?.stop()
        touchIDMonitor = nil
        captureView?.virtualMachine = nil
        captureView?.keySender = nil
        captureView?.control = nil
        captureView?.clipboardSync = nil
        windowController?.close()
        windowController = nil
        VPhoneHostHotKeys.shared.resume()
    }

    // MARK: - Orientation

    private weak var displayContainer: VPhoneDisplayContainerView?
    private var panelSize: NSSize = .zero
    private var orientationPollInFlight = false

    /// Asks vphoned for the interface orientation once a second. Guests
    /// without `display.orientation` stay portrait. A read that overlaps a
    /// rotation the menu started is dropped: it may predate the turn.
    private func pollOrientation() {
        guard !orientationPollInFlight,
              let control, control.isConnected, !control.isChangingOrientation,
              control.guestCapabilities.contains("display_orientation")
        else { return }
        orientationPollInFlight = true
        Task {
            defer { orientationPollInFlight = false }
            guard let result = try? await control.call("display.orientation"),
                  !control.isChangingOrientation,
                  let degrees = (result["degrees"] as? NSNumber)?.intValue,
                  let orientation = VPhoneDisplayOrientation(degrees: degrees)
            else { return }
            control.interfaceOrientation = orientation
        }
    }

    /// Turns the VM view and gives the guest display the turned panel's
    /// aspect ratio, in one animation. A windowed VM reshapes around the
    /// display's center while the bars keep their size; a
    /// full-screen one keeps the screen and letterboxes the turned panel.
    private func applyOrientation(_ orientation: VPhoneDisplayOrientation, to window: NSWindow, force: Bool = false) {
        guard let container = displayContainer, let content,
              force || container.orientation != orientation
        else { return }
        var frame: NSRect?
        if !window.styleMask.contains(.fullScreen) {
            let insets = content.chromeInsets
            let current = window.contentRect(forFrameRect: window.frame)
            let visible = window.screen.map { window.contentRect(forFrameRect: $0.visibleFrame).inset(by: insets) }
            let display = orientation.contentRect(
                from: current.inset(by: insets),
                panel: panelSize,
                within: visible ?? .zero,
            )
            let target = display.outset(by: insets)
            if target != current {
                frame = window.frameRect(forContentRect: target)
            }
        }
        container.turn(to: orientation, windowFrame: frame, animated: !force)
    }

    // MARK: - Sizing

    /// The guest display's shortest side, so the bars keep room for their buttons.
    private static let minimumDisplaySide: CGFloat = 260

    /// Keeps the guest display at the panel's aspect ratio while the bars
    /// keep their size; `contentAspectRatio` would hold the
    /// whole content, bars included, to the ratio. The side the drag changes
    /// more leads.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard !sender.styleMask.contains(.fullScreen), let content, let container = displayContainer else {
            return frameSize
        }
        let displayed = container.orientation.displayedSize(panel: panelSize)
        guard displayed.width > 0, displayed.height > 0 else { return frameSize }
        let insets = content.chromeInsets
        let proposed = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).inset(by: insets).size
        let current = sender.contentRect(forFrameRect: sender.frame).inset(by: insets).size
        let ratio = displayed.width / displayed.height
        var size = proposed
        if abs(proposed.width - current.width) >= abs(proposed.height - current.height) {
            size.height = size.width / ratio
        } else {
            size.width = size.height * ratio
        }
        let minimumScale = Self.minimumDisplaySide / min(displayed.width, displayed.height)
        if size.width < displayed.width * minimumScale {
            size = NSSize(width: displayed.width * minimumScale, height: displayed.height * minimumScale)
        }
        let display = NSRect(origin: .zero, size: NSSize(width: size.width.rounded(), height: size.height.rounded()))
        return sender.frameRect(forContentRect: display.outset(by: insets)).size
    }

    /// Zoom gives the guest display the most of the screen it can take at its
    /// aspect ratio.
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        guard let content, let container = displayContainer else { return newFrame }
        let insets = content.chromeInsets
        let displayed = container.orientation.displayedSize(panel: panelSize)
        let available = window.contentRect(forFrameRect: newFrame).inset(by: insets)
        guard displayed.width > 0, displayed.height > 0, available.width > 0, available.height > 0 else {
            return newFrame
        }
        let scale = min(available.width / displayed.width, available.height / displayed.height)
        let size = NSSize(width: (displayed.width * scale).rounded(), height: (displayed.height * scale).rounded())
        let display = NSRect(
            x: (available.midX - size.width / 2).rounded(),
            y: available.maxY - size.height,
            width: size.width,
            height: size.height,
        )
        return window.frameRect(forContentRect: display.outset(by: insets))
    }

    // MARK: - Mac Shortcuts

    /// The Mac's own shortcuts on keys the guest uses are off while this window
    /// is key; see `VPhoneHostHotKeys`.
    private func observeKeyState(of window: NSWindow) {
        let center = NotificationCenter.default
        keyStateObservers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.captureView?.hardwareKeyboardEnabled == true {
                    VPhoneHostHotKeys.shared.suspend()
                }
            }
        })
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            keyStateObservers.append(center.addObserver(forName: name, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { VPhoneHostHotKeys.shared.resume() }
            })
        }
        if window.isKeyWindow, captureView?.hardwareKeyboardEnabled == true {
            VPhoneHostHotKeys.shared.suspend()
        }

        // A guest copy made while this window is key reaches the Mac when it
        // resigns key; see `VPhoneClipboardSync`.
        keyStateObservers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureView?.clipboardSync?.adoptGuestClipboard() }
        })
        keyStateObservers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureView?.clipboardSync?.bringGuestCopyToMac() }
        })
    }

    // MARK: - Window Buttons

    /// The title bar draws close, minimize and zoom itself. In full screen
    /// the system's buttons come back, since they show with the menu bar
    /// there and the title bar's would sit on the screen's edge.
    func windowWillEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        chrome.showsWindowControls = false
        setSystemWindowButtonsHidden(false, in: window)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        setSystemWindowButtonsHidden(true, in: window)
        chrome.showsWindowControls = true
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        setSystemWindowButtonsHidden(true, in: window)
        chrome.showsWindowControls = true
    }

    private func setSystemWindowButtonsHidden(_ hidden: Bool, in window: NSWindow) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    // MARK: - Status

    /// The title bar's status line from vphoned's health report, which picks
    /// the IPv4 address first and falls back to IPv6. `window.subtitle` keeps
    /// the old `iOS <version> - <address>` line for the Window menu and
    /// accessibility.
    private func updateStatus(control: VPhoneGuestControl) {
        let connected = control.isConnected
        if chrome.isAgentConnected != connected {
            chrome.isAgentConnected = connected
        }
        if chrome.iosVersion != control.guestIOSVersion {
            chrome.iosVersion = control.guestIOSVersion
        }
        if chrome.address != control.guestIPAddress {
            chrome.address = control.guestIPAddress
        }
        updateButtons(connected: connected)

        guard let window = windowController?.window else { return }
        var parts: [String] = []
        if connected {
            if let version = control.guestIOSVersion, !version.isEmpty {
                parts.append("iOS \(version)")
            }
            if let address = control.guestIPAddress, !address.isEmpty {
                parts.append(address)
            }
        }
        if let frameRate = chrome.frameRate {
            parts.append(VPhoneLocalization.format("%ld fps", frameRate))
        }
        let subtitle = parts.joined(separator: " - ")
        if window.subtitle != subtitle {
            window.subtitle = subtitle
        }
    }

    /// Home presses through vphoned, so it waits for the connection, as does a
    /// screenshot. The other buttons follow their menu items.
    private func updateButtons(connected: Bool) {
        let states: [(ReferenceWritableKeyPath<VPhoneDisplayChromeModel, Bool>, Bool)] = [
            (\.canPressHome, connected),
            (\.canOpenGuestTools, VPhoneMenuCommand.guestTools.isEnabled),
            (\.canRotate, VPhoneMenuCommand.rotateLeft.isEnabled),
            (\.canTakeScreenshot, connected && VPhoneMenuCommand.copyScreenshot.isEnabled),
        ]
        for (keyPath, enabled) in states where chrome[keyPath: keyPath] != enabled {
            chrome[keyPath: keyPath] = enabled
        }
    }

    // MARK: - Recording

    /// The Capture menu says when a recording starts and stops; the control
    /// bar shows its timer meanwhile.
    private func observeRecording() {
        keyStateObservers.append(NotificationCenter.default.addObserver(
            forName: .vphoneScreenRecordingDidChange, object: nil, queue: .main,
        ) { [weak self] notification in
            let start = notification.userInfo?[VPhoneScreenRecordingStatus.startedAtKey] as? Date
            MainActor.assumeIsolated { self?.chrome.recordingStartedAt = start }
        })
    }

    // MARK: - Frame Rate

    /// Shows the guest's frame rate on the title bar's status line, sampled once a second.
    func setFrameRateDisplay(_ enabled: Bool) {
        frameRateTimer?.invalidate()
        frameRateTimer = nil
        chrome.frameRate = nil
        if enabled, VPhoneFrameRateMeter.isAvailable {
            _ = VPhoneFrameRateMeter.takeFrameCount()
            frameRateSampledAt = CACurrentMediaTime()
            chrome.frameRate = 0
            frameRateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.sampleFrameRate() }
            }
        }
        if let control {
            updateStatus(control: control)
        }
    }

    private func sampleFrameRate() {
        guard chrome.frameRate != nil, let control else { return }
        let now = CACurrentMediaTime()
        let elapsed = now - frameRateSampledAt
        guard elapsed > 0 else { return }
        chrome.frameRate = Int((Double(VPhoneFrameRateMeter.takeFrameCount()) / elapsed).rounded())
        frameRateSampledAt = now
        updateStatus(control: control)
    }

    // MARK: - Actions

    private func homePressed() {
        control?.sendHIDPress(page: 0x0C, usage: 0x40)
        returnKeyboardToGuest()
    }

    /// Presses a bar button's menu item, then gives the keyboard back to the
    /// guest.
    private func press(_ command: VPhoneMenuCommand) {
        command.perform()
        if let control {
            updateButtons(connected: control.isConnected)
        }
        returnKeyboardToGuest()
    }

    private func returnKeyboardToGuest() {
        guard let window = windowController?.window, let view = virtualMachineView,
              window.firstResponder !== view
        else { return }
        window.makeFirstResponder(view)
    }
}
