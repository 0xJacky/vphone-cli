import AppKit
import IOKit.ps

// MARK: - Battery Menu

extension VPhoneMenuController {
    /// The Simulate menu's Battery section. Its header carries the state the
    /// guest was last given.
    func addBatteryItems(to menu: NSMenu) {
        let header = NSMenuItem.sectionHeader(title: sectionHeaderTitle("Battery", status: nil))
        batteryHeaderItem = header
        menu.addItem(header)

        let syncItem = makeItem("Sync with Host", action: #selector(toggleBatterySync(_:)))
        syncItem.state = .off
        menu.addItem(syncItem)

        // Charge level presets
        let levelItem = NSMenuItem(title: "Level", action: nil, keyEquivalent: "")
        let levelMenu = NSMenu(title: "Level")
        levelMenu.autoenablesItems = false
        batteryLevelMenuItems = []
        for level in [100, 75, 50, 25, 10, 5] {
            let mi = makeItem("\(level)%", action: #selector(setBatteryLevel(_:)))
            mi.tag = level
            mi.state = level == 100 ? .on : .off
            levelMenu.addItem(mi)
            batteryLevelMenuItems.append(mi)
        }
        levelItem.submenu = levelMenu
        batteryLevelItem = levelItem
        menu.addItem(levelItem)

        // Connectivity: 1=charging, 2=disconnected
        let charging = makeItem("Charging", action: #selector(setBatteryConnectivity(_:)))
        charging.tag = 1
        charging.state = .on
        let disconnected = makeItem("Not Charging", action: #selector(setBatteryConnectivity(_:)))
        disconnected.tag = 2

        menu.addItem(charging)
        menu.addItem(disconnected)
        batteryConnectivityMenuItems = [charging, disconnected]

        // Enable sync by default
        syncItem.state = .on
        batterySyncEnabled = true
        setManualBatteryControlsEnabled(false)
        syncBatteryFromHost()
        syncLowPowerModeFromHost()
        startPowerSourceMonitoring()
        startLowPowerMonitoring()
    }

    private func setManualBatteryControlsEnabled(_ enabled: Bool) {
        batteryLevelItem?.isEnabled = enabled
        batteryLevelMenuItems.forEach { $0.isEnabled = enabled }
        batteryConnectivityMenuItems.forEach { $0.isEnabled = enabled }
    }

    @objc func setBatteryLevel(_ sender: NSMenuItem) {
        batteryLevelMenuItems.forEach { $0.state = $0 === sender ? .on : .off }
        let charge = Double(sender.tag)
        let connectivity = currentBatteryConnectivity()
        vm?.setBattery(charge: charge, connectivity: connectivity)
        updateStatusLabel(charge: charge, connectivity: connectivity, lowPowerMode: false)
        print("[battery] set \(sender.tag)%, connectivity=\(connectivity)")
    }

    @objc func setBatteryConnectivity(_ sender: NSMenuItem) {
        batteryConnectivityMenuItems.forEach { $0.state = $0 === sender ? .on : .off }
        let charge = currentBatteryCharge()
        vm?.setBattery(charge: charge, connectivity: sender.tag)
        updateStatusLabel(charge: charge, connectivity: sender.tag, lowPowerMode: false)
        print("[battery] set \(Int(charge))%, connectivity=\(sender.tag)")
    }

    // MARK: - Host Sync

    /// Release the run-loop context before replacing this VM's controllers.
    func stopBatteryMonitoring() {
        batterySyncEnabled = false
        stopPowerSourceMonitoring()
        stopLowPowerMonitoring()
    }

    @objc func toggleBatterySync(_ sender: NSMenuItem) {
        batterySyncEnabled.toggle()
        sender.state = batterySyncEnabled ? .on : .off
        setManualBatteryControlsEnabled(!batterySyncEnabled)

        if batterySyncEnabled {
            syncBatteryFromHost()
            syncLowPowerModeFromHost()
            startPowerSourceMonitoring()
            startLowPowerMonitoring()
        } else {
            stopPowerSourceMonitoring()
            stopLowPowerMonitoring()
        }
        print("[battery] host sync \(batterySyncEnabled ? "enabled" : "disabled")")
    }

    // MARK: - Battery State Sync

    func syncBatteryFromHost() {
        guard batterySyncEnabled else { return }
        guard let (charge, connectivity) = hostBatteryState() else {
            batteryHeaderItem?.title = sectionHeaderTitle("Battery", status: VPhoneLocalization.text("no host battery"))
            return
        }
        vm?.setBattery(charge: charge, connectivity: connectivity)
        updateStatusLabel(
            charge: charge,
            connectivity: connectivity,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
        )
        print("[battery] sync \(Int(charge))%, connectivity=\(connectivity)")
    }

    private func hostBatteryState() -> (charge: Double, connectivity: Int)? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard
                let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any]
            else { continue }
            guard let type = info[kIOPSTypeKey as String] as? String,
                  type == kIOPSInternalBatteryType
            else { continue }
            let capacity = info[kIOPSCurrentCapacityKey as String] as? Int ?? 100
            let state = info[kIOPSPowerSourceStateKey as String] as? String ?? kIOPSACPowerValue
            let connectivity = (state == kIOPSACPowerValue) ? 1 : 2
            return (Double(capacity), connectivity)
        }
        return nil
    }

    // MARK: - Low Power Mode Sync

    func syncLowPowerModeFromHost() {
        guard batterySyncEnabled else { return }
        let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        Task {
            do {
                try await control.lowPowerMode(enabled: enabled)
                syncBatteryFromHost() // refresh status label with updated LPM state
                print("[battery] sync LPM: \(enabled)")
            } catch {
                print("[battery] sync LPM failed: \(error)")
            }
        }
    }

    // MARK: - IOKit Power Source Monitoring

    private func startPowerSourceMonitoring() {
        stopPowerSourceMonitoring()
        let rawPtr = Unmanaged.passRetained(self).toOpaque()
        powerSourceRetainedPtr = rawPtr
        let source = IOPSNotificationCreateRunLoopSource(
            { rawContext in
                guard let ctx = rawContext else { return }
                Task { @MainActor in
                    Unmanaged<VPhoneMenuController>.fromOpaque(ctx)
                        .takeUnretainedValue()
                        .syncBatteryFromHost()
                }
            }, rawPtr,
        )
        guard let runLoopSource = source?.takeRetainedValue() else { return }
        powerSourceRunLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
    }

    private func stopPowerSourceMonitoring() {
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSourceRunLoopSource = nil
        }
        if let ptr = powerSourceRetainedPtr {
            Unmanaged<VPhoneMenuController>.fromOpaque(ptr).release()
            powerSourceRetainedPtr = nil
        }
    }

    // MARK: - Low Power Mode Monitoring

    private func startLowPowerMonitoring() {
        stopLowPowerMonitoring()
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("NSProcessInfoPowerStateDidChangeNotification"),
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in self?.syncLowPowerModeFromHost() }
        }
    }

    private func stopLowPowerMonitoring() {
        if let observer = lowPowerObserver {
            NotificationCenter.default.removeObserver(observer)
            lowPowerObserver = nil
        }
    }

    // MARK: - Status Label

    /// "Battery — 75%, charging", with the host's Low Power Mode while synced.
    private func updateStatusLabel(charge: Double, connectivity: Int, lowPowerMode: Bool) {
        var parts = [
            "\(Int(charge))%",
            VPhoneLocalization.text(connectivity == 1 ? "charging" : "not charging"),
        ]
        if lowPowerMode {
            parts.append(VPhoneLocalization.text("Low Power Mode"))
        }
        batteryHeaderItem?.title = sectionHeaderTitle("Battery", status: parts.joined(separator: ", "))
    }

    // MARK: - Helpers

    private func currentBatteryCharge() -> Double {
        Double(batteryLevelMenuItems.first(where: { $0.state == .on })?.tag ?? 100)
    }

    private func currentBatteryConnectivity() -> Int {
        batteryConnectivityMenuItems.first(where: { $0.state == .on })?.tag ?? 1
    }
}
