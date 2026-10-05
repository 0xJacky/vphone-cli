import SwiftUI
import VPhoneDesignKit

/// The menu bar's own items: the View menu picks a page (⌘1 to ⌘6) and hides
/// the sidebar and the Machines inspector. Settings… (⌘,) comes with the
/// Settings scene.
struct VPhoneLaunchpadCommands: Commands {
    let model: VPhoneLaunchpadModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Machines are created from the Machines page, not File › New.
        CommandGroup(replacing: .newItem) {}
        SidebarCommands()
        CommandGroup(before: .toolbar) {
            DKMenuContent(Self.pageItems(model) { openWindow(id: "main") })
            Divider()
        }
        CommandGroup(after: .sidebar) {
            DKMenuContent([Self.inspectorItem(model)])
        }
    }

    /// One checked row per page, in sidebar order. Picking one also brings
    /// the window back when it was closed to the menu bar.
    static func pageItems(_ model: VPhoneLaunchpadModel, open: @escaping @MainActor () -> Void) -> [DKMenuItem] {
        DKLaunchpadDestination.allCases.map { destination in
            DKMenuItem(destination.localizedTitle, shortcut: destination.shortcut) {
                model.show(destination)
                open()
            }
            .checked(model.destination == destination)
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
