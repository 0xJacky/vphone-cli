import SwiftUI

/// A menu drawn flat, the way the design's artboards draw one: a title and
/// note over a menu panel, with a submenu's rows indented under it. For the
/// gallery and documentation only; a Mac app's menus are real menus built with
/// `DKMenuContent` or `makeNSMenu()`.
public struct DKMenuPreview: View {
    let menu: DKMenu
    let note: String?
    let expandsSubmenus: Bool

    /// - Parameters:
    ///   - note: A line under the title, such as "Acts on the selection".
    ///   - expandsSubmenus: Draw a submenu's rows indented under it.
    public init(_ menu: DKMenu, note: String? = nil, expandsSubmenus: Bool = true) {
        self.menu = menu
        self.note = note
        self.expandsSubmenus = expandsSubmenus
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s2) {
            if !menu.title.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(menu.title).font(DK.Typeface.bodyStrong)
                    if let note, !note.isEmpty {
                        Text(note).font(DK.Typeface.caption).foregroundStyle(DK.Palette.muted)
                    }
                }
                .padding(.horizontal, 6)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    DKMenuPreviewRow(row: row)
                }
            }
            .padding(5)
            .frame(minWidth: 220, alignment: .leading)
            .background(DK.Palette.window, in: shape)
            .overlay(shape.strokeBorder(DK.Palette.lineStrong, lineWidth: DK.Metric.hairline))
            .shadow(color: Self.menuShadow, radius: 10, y: 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(menu.title)
        }
        .foregroundStyle(DK.Palette.ink)
        .font(DK.Typeface.body)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
    }

    /// The design's `--dk-shadow-menu`: menus and popovers are the only things with a shadow.
    static let menuShadow = DK.Palette.dynamic(0x000000, 0x000000, lightAlpha: 0.08, darkAlpha: 0.45)

    var rows: [Row] {
        var rows: [Row] = []
        append(menu.items, depth: 0, to: &rows)
        return rows
    }

    private func append(_ items: [DKMenuItem], depth: Int, to rows: inout [Row]) {
        for section in DKMenuLayout(items).sections {
            if section.separatorBefore {
                rows.append(.separator)
            }
            if let header = section.header {
                rows.append(.header(header, depth: depth))
            }
            for row in section.rows {
                rows.append(.item(row.item, trailing: trailing(row.item, row.shortcut), depth: depth))
                if let alternate = row.alternate {
                    let text = alternate.shortcut?.description ?? alternate.modifiers.symbols
                    rows.append(.item(alternate.item, trailing: .shortcut(text), depth: depth))
                }
                if row.item.kind == .submenu, expandsSubmenus {
                    append(row.item.children, depth: depth + 1, to: &rows)
                }
            }
        }
    }

    private func trailing(_ item: DKMenuItem, _ shortcut: DKShortcut?) -> Trailing {
        if item.kind == .submenu { return .submenu }
        return shortcut.map { .shortcut($0.description) } ?? .none
    }

    enum Trailing: Equatable {
        case none
        case shortcut(String)
        case submenu
    }

    enum Row {
        case separator
        case header(String, depth: Int)
        case item(DKMenuItem, trailing: Trailing, depth: Int)
    }
}

/// One drawn row of `DKMenuPreview`.
struct DKMenuPreviewRow: View {
    let row: DKMenuPreview.Row

    var body: some View {
        switch row {
        case .separator:
            Rectangle()
                .fill(DK.Palette.divider)
                .frame(height: DK.Metric.hairline)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .accessibilityHidden(true)
        case let .header(title, depth):
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DK.Palette.muted)
                .padding(.leading, leading(depth))
                .padding(.trailing, 10)
                .padding(.top, 5)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
        case let .item(item, trailing, depth):
            itemRow(item, trailing: trailing, depth: depth)
        }
    }

    private func itemRow(_ item: DKMenuItem, trailing: DKMenuPreview.Trailing, depth: Int) -> some View {
        let ink = item.isEnabled ? (item.isDestructive ? DK.Palette.danger : DK.Palette.ink) : DK.Palette.inkDisabled
        let detail = item.isEnabled ? DK.Palette.muted : DK.Palette.inkDisabled
        return HStack(spacing: DK.Space.s4) {
            Text(item.title).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            switch trailing {
            case .none:
                EmptyView()
            case let .shortcut(text):
                Text(text).monospacedDigit().foregroundStyle(detail)
            case .submenu:
                DKIcon(.right, size: 12).foregroundStyle(detail)
            }
        }
        .foregroundStyle(ink)
        .frame(height: 24)
        .padding(.leading, leading(depth))
        .padding(.trailing, 10)
        .overlay(alignment: .leading) {
            if let mark = checkMark(item.state) {
                Text(mark).font(.system(size: 12)).foregroundStyle(ink).padding(.leading, 10).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityState(item.state))
    }

    private func leading(_ depth: Int) -> CGFloat {
        28 + CGFloat(depth) * 16
    }

    private func checkMark(_ state: DKMenuItem.State?) -> String? {
        switch state {
        case .on: "✓"
        case .mixed: "–"
        case .off, nil: nil
        }
    }

    private func accessibilityState(_ state: DKMenuItem.State?) -> Text {
        switch state {
        case .on: Text("Checked")
        case .mixed: Text("Mixed")
        case .off: Text("Unchecked")
        case nil: Text(verbatim: "")
        }
    }
}

// MARK: - Previews

@MainActor private let previewMachineMenu = DKMenu("Machine") {
    DKMenuItem("Start", glyph: .play, shortcut: "⌘R")
    DKMenuItem("Start Headless", shortcut: "⌥⌘R")
    DKMenuItem("Stop", glyph: .stop, shortcut: "⌘.").disabled()
    DKMenuItem.separator
    DKMenuItem("Open in Terminal", glyph: .terminal, shortcut: "⇧⌘C")
    DKMenuItem("Show in Finder", glyph: .folder)
    DKMenuItem.submenu("Logs", glyph: .doc) {
        DKMenuItem("Console Log")
        DKMenuItem("Patch Log")
    }
    DKMenuItem.separator
    DKMenuItem("Settings…", glyph: .sliders, shortcut: "⌘I")
    DKMenuItem("Rename…", glyph: .pencil)
    DKMenuItem("Clone…", glyph: .copy, shortcut: "⌘D")
    DKMenuItem("Export…", glyph: .upload, shortcut: "⇧⌘E")
    DKMenuItem.separator
    DKMenuItem.submenu("Core Bundle", glyph: .bundle) {
        DKMenuItem("Change Core Bundle…")
        DKMenuItem("Update Guest Environment")
        DKMenuItem("Install Custom Firmware")
    }
    DKMenuItem.separator
    DKMenuItem("Delete…", glyph: .trash, shortcut: "⌘⌫").destructive()
}

@MainActor private let previewWindowMenu = DKMenu("Window") {
    DKMenuItem.header("research-26")
    DKMenuItem("Display", shortcut: "⌥⌘1").checked(true)
    DKMenuItem("Workspace", shortcut: "⌥⌘2").checked(false)
    DKMenuItem("Terminal", shortcut: "⌥⌘3").checked(false)
    DKMenuItem("Files", shortcut: "⌥⌘4").checked(false)
    DKMenuItem.separator
    DKMenuItem("New Terminal Tab", shortcut: "⌘T")
    DKMenuItem.separator
    DKMenuItem("Minimize", shortcut: "⌘M")
    DKMenuItem("Zoom")
    DKMenuItem.separator
    DKMenuItem("Bring All to Front")
}

#Preview("Launchpad Machine menu") {
    HStack(alignment: .top, spacing: DK.Space.s6) {
        DKMenuPreview(previewMachineMenu, note: "Acts on the selection")
        Menu("Machine") { DKMenuContent(previewMachineMenu.items) }
            .fixedSize()
    }
    .padding(DK.Space.s8)
    .background(DK.Palette.page)
}

#Preview("VM Window menu") {
    HStack(alignment: .top, spacing: DK.Space.s6) {
        DKMenuPreview(previewWindowMenu, note: "Four independent windows per machine")
        Menu("Window") { DKMenuContent(previewWindowMenu.items) }
            .fixedSize()
    }
    .padding(DK.Space.s8)
    .background(DK.Palette.page)
}
