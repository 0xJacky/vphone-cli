import SwiftUI
import VPhoneDesignKit

/// The menu bar's own items: File creates and imports machines, the View
/// menu picks a page (⌘1 to ⌘6) and hides the sidebar and the Machines
/// inspector, and the Machine menu acts on the selected machines. Settings…
/// (⌘,) comes with the Settings scene.
///
/// The sidebar is DesignKit's, not a split view's, so Hide Sidebar is this
/// menu's own item rather than `SidebarCommands`, with the same ⌃⌘S.
struct VPhoneLaunchpadCommands: Commands {
    let model: VPhoneLaunchpadModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // New Machine… and Import… take File › New's place; there is one window.
        CommandGroup(replacing: .newItem) {
            DKMenuContent(Self.fileItems(model) { openWindow(id: "main") })
        }
        CommandGroup(before: .toolbar) {
            DKMenuContent(Self.pageItems(model) { openWindow(id: "main") })
            Divider()
        }
        CommandGroup(replacing: .sidebar) {
            DKMenuContent([Self.sidebarItem(model), Self.inspectorItem(model)])
        }
        CommandMenu("Machine") {
            DKMenuContent(VPhoneLaunchpadMachineActions(model: model).menuBarItems())
        }
    }

    /// New Machine… and Import…, from any page: each shows the Machines page,
    /// bringing the window back when it was closed to the menu bar.
    static func fileItems(_ model: VPhoneLaunchpadModel, open: @escaping @MainActor () -> Void) -> [DKMenuItem] {
        let actions = VPhoneLaunchpadMachineActions(model: model)
        return [
            DKMenuItem(String(localized: "New Machine…"), shortcut: "⌘N", isEnabled: actions.canCreate) {
                open()
                actions.newMachine()
            },
            DKMenuItem(String(localized: "Import…"), shortcut: "⌘O", isEnabled: actions.canImport) {
                open()
                model.show(.machines)
                actions.chooseImport()
            },
        ]
    }

    /// One checked row per page, in sidebar order. Picking one also brings
    /// the window back when it was closed to the menu bar.
    static func pageItems(_ model: VPhoneLaunchpadModel, open: @escaping @MainActor () -> Void) -> [DKMenuItem] {
        DKLaunchpadDestination.allCases.map { destination in
            DKMenuItem(destination.title, shortcut: destination.shortcut) {
                model.show(destination)
                open()
            }
            .checked(model.destination == destination)
        }
    }

    /// Shows and hides the sidebar, as `SidebarCommands` would for a split view.
    static func sidebarItem(_ model: VPhoneLaunchpadModel) -> DKMenuItem {
        DKMenuItem(
            model.showsSidebar ? String(localized: "Hide Sidebar") : String(localized: "Show Sidebar"),
            shortcut: DKShortcut("s", [.control, .command]),
        ) {
            model.showsSidebar.toggle()
        }
    }

    /// Only the Machines page has an inspector.
    static func inspectorItem(_ model: VPhoneLaunchpadModel) -> DKMenuItem {
        DKMenuItem(
            model.showsInspector ? String(localized: "Hide Inspector") : String(localized: "Show Inspector"),
            shortcut: DKShortcut("i", [.option, .command]),
        ) {
            model.showsInspector.toggle()
        }
        .disabled(model.destination != .machines)
    }
}
