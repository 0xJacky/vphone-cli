import AppKit
import SwiftUI
import VPhoneDesignKit

// MARK: - Setting

/// Menu bar mode: closing the window keeps Launchpad running in the menu bar,
/// and the Dock icon follows what is on screen.
enum VPhoneLaunchpadMenuBar {
    static let key = "VPhoneLaunchpadShowsInMenuBar"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}

// MARK: - Menu

/// The menu bar icon's menu: Open Launchpad, then the machines grouped by
/// what they are doing (Running, Stopped, Busy), then Quit.
struct VPhoneLaunchpadMenuBarMenu: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        DKMenuContent(Self.items(model) {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            NSApp.activate()
        })
    }

    static func items(_ model: VPhoneLaunchpadModel, open: @escaping @MainActor () -> Void) -> [DKMenuItem] {
        let library = model.machines
        var running: [DKMenuItem] = []
        var stopped: [DKMenuItem] = []
        var busy: [DKMenuItem] = []
        for machine in library.machines {
            let path = machine.path
            switch library.state(of: path) {
            case .running:
                running.append(.submenu(machine.name, items: [
                    DKMenuItem(String(localized: "Stop")) { Task { await library.stop(path) } },
                ]))
            case .stopped:
                stopped.append(.submenu(machine.name, items: [
                    DKMenuItem(String(localized: "Start")) { Task { await library.start(path) } },
                    DKMenuItem(String(localized: "Start Headless")) { Task { await library.start(path, headless: true) } },
                ]))
            case let .busy(activity):
                busy.append(DKMenuItem(String(localized: "\(machine.name) — \(activity)")).disabled())
            }
        }

        var items = [DKMenuItem(String(localized: "Open Launchpad"), action: open)]
        if library.machines.isEmpty {
            items += [.separator, DKMenuItem(String(localized: "No Machines")).disabled()]
        }
        for (title, group) in [
            (String(localized: "Running"), running),
            (String(localized: "Stopped"), stopped),
            (String(localized: "Busy"), busy),
        ] where !group.isEmpty {
            items += [.separator, .header(title)] + group
        }
        items += [
            .separator,
            DKMenuItem(String(localized: "Quit"), shortcut: DKShortcut("q", .command)) { NSApp.terminate(nil) },
        ]
        return items
    }
}

// MARK: - Dock icon

/// Shows the Dock icon while a window, minimized or not, or a menu is open,
/// and hides it otherwise. Checked once a second, in every run loop mode so
/// it also runs while a menu is tracking.
@MainActor
final class VPhoneLaunchpadDockPolicy {
    private var timer: Timer?
    private var menusOpen = 0

    func start() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menusOpen += 1
                self?.update()
            }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menusOpen = max(0, self.menusOpen - 1)
            }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func update() {
        guard VPhoneLaunchpadMenuBar.isEnabled else {
            setPolicy(.regular)
            return
        }
        // Titled windows only: the status item and open menus are windows too.
        let hasWindow = NSApp.windows.contains { window in
            window.styleMask.contains(.titled) && (window.isVisible || window.isMiniaturized)
        }
        setPolicy(hasWindow || menusOpen > 0 ? .regular : .accessory)
    }

    private func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}
