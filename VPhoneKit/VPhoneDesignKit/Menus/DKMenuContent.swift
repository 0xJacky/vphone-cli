import SwiftUI

/// Menu rows for SwiftUI's real menus. Put it inside `Menu { }`,
/// `.contextMenu { }` or `CommandMenu`:
///
/// ```swift
/// Menu("Machine") { DKMenuContent(machineItems) }
/// row.contextMenu { DKMenuContent(machineItems) }
/// ```
///
/// Shortcuts become `keyboardShortcut`s, checkable items become toggles (a
/// checkmark), destructive items take the destructive role, headers become
/// sections, and alternates appear while Option is held.
public struct DKMenuContent: View {
    let layout: DKMenuLayout

    public init(_ items: [DKMenuItem]) {
        layout = DKMenuLayout(items)
    }

    public init(@DKMenuBuilder _ items: () -> [DKMenuItem]) {
        layout = DKMenuLayout(items())
    }

    public var body: some View {
        ForEach(Array(layout.sections.enumerated()), id: \.offset) { _, section in
            if section.separatorBefore {
                Divider()
            }
            if let header = section.header {
                Section(header) {
                    rows(section.rows)
                }
            } else {
                rows(section.rows)
            }
        }
    }

    private func rows(_ rows: [DKMenuLayout.Row]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            if let alternate = row.alternate {
                DKMenuRow(item: row.item, shortcut: row.shortcut)
                    .modifierKeyAlternate(alternate.modifiers.eventModifiers) {
                        DKMenuRow(item: alternate.item, shortcut: alternate.shortcut)
                    }
            } else {
                DKMenuRow(item: row.item, shortcut: row.shortcut)
            }
        }
    }
}

/// One SwiftUI menu row.
struct DKMenuRow: View {
    let item: DKMenuItem
    let shortcut: DKShortcut?

    var body: some View {
        control
            .keyboardShortcut(shortcut?.keyboardShortcut)
            .disabled(!item.isEnabled)
    }

    @ViewBuilder
    private var control: some View {
        switch (item.kind, item.state) {
        case (.submenu, _):
            Menu {
                DKMenuContent(item.children)
            } label: {
                label
            }
        case (_, .on), (_, .off):
            Toggle(isOn: Binding(get: { item.state == .on }, set: { _ in item.action?() })) {
                label
            }
        case (_, .mixed):
            Button(role: item.isDestructive ? .destructive : nil) {
                item.action?()
            } label: {
                Label(item.title, systemImage: "minus")
            }
            .accessibilityValue(Text("Mixed"))
        default:
            Button(role: item.isDestructive ? .destructive : nil) {
                item.action?()
            } label: {
                label
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        if let glyph = item.glyph {
            Label(item.title, systemImage: glyph.symbolName)
        } else {
            Text(item.title)
        }
    }
}

/// A menu-bar menu for a SwiftUI `App`'s `commands`:
///
/// ```swift
/// .commands { DKCommandMenu(machineMenu) }
/// ```
public struct DKCommandMenu: Commands {
    let menu: DKMenu

    public init(_ menu: DKMenu) {
        self.menu = menu
    }

    public var body: some Commands {
        CommandMenu(menu.title) {
            DKMenuContent(menu.items)
        }
    }
}
