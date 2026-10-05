import AppKit
import UniformTypeIdentifiers

// MARK: - Camera Menu

extension VPhoneMenuController {
    /// The Simulate menu's Camera section. Its header carries the camera
    /// server's connection.
    func addCameraItems(to menu: NSMenu) {
        let header = NSMenuItem.sectionHeader(title: cameraHeaderTitle(connected: false))
        cameraStatusItem = header
        menu.addItem(header)

        let sourceItem = NSMenuItem(title: "Source", action: nil, keyEquivalent: "")
        let sourceMenu = NSMenu(title: "Source")

        let off = makeItem("Off", action: #selector(setCameraSourceOff))
        off.state = .on
        cameraSourceOffItem = off
        sourceMenu.addItem(off)

        let testPattern = makeItem(
            "Test Pattern",
            action: #selector(setCameraSourceTestPattern),
        )
        cameraSourceTestPatternItem = testPattern
        sourceMenu.addItem(testPattern)

        let videoFile = makeItem(
            "Video File…",
            action: #selector(setCameraSourceVideoFile),
        )
        cameraSourceVideoFileItem = videoFile
        sourceMenu.addItem(videoFile)

        sourceItem.submenu = sourceMenu
        menu.addItem(sourceItem)

        let startStop = makeItem(
            "Start Streaming",
            action: #selector(toggleCameraStreaming),
            symbol: "play",
        )
        startStop.isEnabled = false
        cameraStartStopItem = startStop
        menu.addItem(startStop)
    }

    /// "Camera — connected"
    private func cameraHeaderTitle(connected: Bool) -> String {
        sectionHeaderTitle("Camera", status: VPhoneLocalization.text(connected ? "connected" : "disconnected"))
    }

    func updateCameraConnectionState(connected: Bool) {
        cameraStatusItem?.title = cameraHeaderTitle(connected: connected)
        cameraStartStopItem?.isEnabled = connected && (cameraServer?.sourceKind ?? .off) != .off
    }

    private func refreshCameraSourceCheckmarks() {
        let kind = cameraServer?.sourceKind ?? .off
        cameraSourceOffItem?.state = (kind == .off) ? .on : .off
        cameraSourceTestPatternItem?.state =
            (kind == .testPattern) ? .on : .off
        cameraSourceVideoFileItem?.state =
            (kind == .videoFile) ? .on : .off
    }

    @objc func setCameraSourceOff() {
        cameraServer?.stopStreaming()
        cameraServer?.setSource(.off)
        refreshCameraSourceCheckmarks()
        cameraStartStopItem?.isEnabled = false
        cameraStartStopItem?.title = VPhoneLocalization.text("Start Streaming")
        cameraStartStopItem?.image = menuSymbol("play")
    }

    @objc func setCameraSourceTestPattern() {
        cameraServer?.setSource(.testPattern)
        refreshCameraSourceCheckmarks()
        cameraStartStopItem?.isEnabled = (cameraServer?.isConnected ?? false)
    }

    @objc func setCameraSourceVideoFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // AVFoundation's natively-decodable containers on macOS. Anything
        // beyond these (.mkv/.webm/.avi) would need external conversion to
        // .mov / .mp4 first.
        panel.allowedContentTypes = [
            UTType(filenameExtension: "mov") ?? .movie,
            UTType(filenameExtension: "mp4") ?? .movie,
            UTType(filenameExtension: "m4v") ?? .movie,
        ]
        panel.prompt = VPhoneLocalization.text("Use as Camera Source")
        panel.title = VPhoneLocalization.text("Choose Video File")
        VPhoneAlert.present(panel) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            cameraServer?.setSource(.videoFile, videoURL: url)
            refreshCameraSourceCheckmarks()
            cameraStartStopItem?.isEnabled =
                (cameraServer?.isConnected ?? false) &&
                (cameraServer?.sourceKind ?? .off) == .videoFile
        }
    }

    @objc func toggleCameraStreaming() {
        guard let server = cameraServer else { return }
        if cameraStartStopItem?.title == VPhoneLocalization.text("Start Streaming") {
            server.startStreaming()
            cameraStartStopItem?.title = VPhoneLocalization.text("Stop Streaming")
            cameraStartStopItem?.image = menuSymbol("stop")
        } else {
            server.stopStreaming()
            cameraStartStopItem?.title = VPhoneLocalization.text("Start Streaming")
            cameraStartStopItem?.image = menuSymbol("play")
        }
    }
}
