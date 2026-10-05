import AppKit

// MARK: - Simulate Menu

/// Sensors the host simulates for the guest: location, battery and camera.
/// Each is a titled section of this menu rather than a submenu, so every
/// control is one level down from the menu bar. The battery and camera
/// headers carry their status.
extension VPhoneMenuController {
    func buildSimulateMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Simulate", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Simulate")
        menu.autoenablesItems = false
        addLocationItems(to: menu)
        menu.addItem(NSMenuItem.separator())
        addBatteryItems(to: menu)
        menu.addItem(NSMenuItem.separator())
        addCameraItems(to: menu)
        item.submenu = menu
        return item
    }

    /// "Battery — 100%, charging": a section name and its status, each localized.
    func sectionHeaderTitle(_ name: String, status: String?) -> String {
        guard let status, !status.isEmpty else { return VPhoneLocalization.text(name) }
        return "\(VPhoneLocalization.text(name)) — \(status)"
    }
}
