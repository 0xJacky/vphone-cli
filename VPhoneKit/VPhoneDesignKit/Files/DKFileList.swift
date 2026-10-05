import SwiftUI

// MARK: - Item

/// One row of a `DKFileList`.
public struct DKFileListItem: Identifiable, Hashable, Sendable {
    /// A stable identity, usually the entry's full path.
    public var id: String
    public var name: String
    public var kind: DKFileKind
    /// Trailing muted text: a size, a count, a date. Empty shows nothing.
    public var detail: String

    public init(id: String, name: String, kind: DKFileKind, detail: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.detail = detail
    }

    /// An item classified from its name and `stat` result.
    public init(id: String, name: String, isDirectory: Bool, isSymlink: Bool = false, detail: String = "") {
        self.init(id: id, name: name, kind: DKFileKind(name: name, isDirectory: isDirectory, isSymlink: isSymlink), detail: detail)
    }
}

// MARK: - List

/// The file column of the Workspace and Files windows: a header with the
/// current path (monospaced, truncated in the middle) between two control
/// slots, then compact rows of icon, name and muted detail.
///
/// Clicking selects. Double-clicking or Return calls `onOpen` with the
/// selected row. The context menu is built for the row it was opened on.
/// Arrow keys and type-to-select come from the underlying `List`.
public struct DKFileList<Leading: View, Trailing: View, RowMenu: View>: View {
    public let path: String
    public let items: [DKFileListItem]
    @Binding public var selection: DKFileListItem.ID?
    public var onOpen: (DKFileListItem) -> Void
    let leading: Leading
    let trailing: Trailing
    let rowMenu: (DKFileListItem) -> RowMenu

    /// - Parameters:
    ///   - path: The folder the rows belong to, shown in the header.
    ///   - leading: Controls before the path, such as back and up.
    ///   - trailing: Controls after the path, such as sort, refresh and upload.
    ///   - contextMenu: The menu for a row.
    public init(
        path: String,
        items: [DKFileListItem],
        selection: Binding<DKFileListItem.ID?>,
        onOpen: @escaping (DKFileListItem) -> Void = { _ in },
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder contextMenu: @escaping (DKFileListItem) -> RowMenu,
    ) {
        self.path = path
        self.items = items
        _selection = selection
        self.onOpen = onOpen
        self.leading = leading()
        self.trailing = trailing()
        rowMenu = contextMenu
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DK.Palette.divider)
            List(selection: $selection) {
                ForEach(items) { item in
                    DKFileListRow(item: item)
                        .listRowInsets(EdgeInsets(top: 0, leading: DK.Space.s1, bottom: 0, trailing: DK.Space.s1))
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, DKFileListRow.height)
            .contextMenu(forSelectionType: DKFileListItem.ID.self) { ids in
                if let item = item(for: ids) {
                    rowMenu(item)
                }
            } primaryAction: { ids in
                if let item = item(for: ids) {
                    onOpen(item)
                }
            }
            .accessibilityLabel("Files")
        }
    }

    private var header: some View {
        HStack(spacing: DK.Space.s1) {
            leading
            Text(path)
                .font(DK.Typeface.monoSmall)
                .foregroundStyle(DK.Palette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(path)
                .accessibilityLabel("Path")
                .accessibilityValue(path)
            trailing
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 36)
    }

    private func item(for ids: Set<DKFileListItem.ID>) -> DKFileListItem? {
        guard ids.count == 1, let id = ids.first else {
            return nil
        }
        return items.first { $0.id == id }
    }
}

// MARK: Convenience

public extension DKFileList where Leading == EmptyView, Trailing == EmptyView, RowMenu == EmptyView {
    /// A list with no header controls and no context menu.
    init(
        path: String,
        items: [DKFileListItem],
        selection: Binding<DKFileListItem.ID?>,
        onOpen: @escaping (DKFileListItem) -> Void = { _ in },
    ) {
        self.init(path: path, items: items, selection: selection, onOpen: onOpen) {
            EmptyView()
        } trailing: {
            EmptyView()
        } contextMenu: { _ in
            EmptyView()
        }
    }
}

public extension DKFileList where Leading == EmptyView, RowMenu == EmptyView {
    /// A list with trailing header controls and no context menu.
    init(
        path: String,
        items: [DKFileListItem],
        selection: Binding<DKFileListItem.ID?>,
        onOpen: @escaping (DKFileListItem) -> Void = { _ in },
        @ViewBuilder trailing: () -> Trailing,
    ) {
        self.init(path: path, items: items, selection: selection, onOpen: onOpen) {
            EmptyView()
        } trailing: {
            trailing()
        } contextMenu: { _ in
            EmptyView()
        }
    }
}

// MARK: - Row

struct DKFileListRow: View {
    static let height: CGFloat = 26

    let item: DKFileListItem

    var body: some View {
        HStack(spacing: 9) {
            DKFileIcon(item.kind, size: 16)
            Text(item.name)
                .font(DK.Typeface.body)
                .foregroundStyle(item.kind == .parent ? DK.Palette.inkSecondary : DK.Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !item.detail.isEmpty {
                Text(item.detail)
                    .font(DK.Typeface.monoSmall)
                    .foregroundStyle(DK.Palette.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.kind == .parent ? "Enclosing Folder" : item.name)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        item.detail.isEmpty ? item.kind.typeDescription : "\(item.kind.typeDescription), \(item.detail)"
    }
}

// MARK: - Preview

private let previewItems: [DKFileListItem] = [
    DKFileListItem(id: "/var", name: "..", kind: .parent),
    DKFileListItem(id: "/var/mobile/Containers", name: "Containers", isDirectory: true),
    DKFileListItem(id: "/var/mobile/Documents", name: "Documents", isDirectory: true),
    DKFileListItem(id: "/var/mobile/Library", name: "Library", isDirectory: true),
    DKFileListItem(id: "/var/mobile/Media", name: "Media", isDirectory: true),
    DKFileListItem(id: "/var/mobile/Downloads", name: "Downloads", isDirectory: false, isSymlink: true),
    DKFileListItem(id: "/var/mobile/notes.md", name: "notes.md", isDirectory: false, detail: "2 KB"),
    DKFileListItem(id: "/var/mobile/hook.py", name: "hook.py", isDirectory: false, detail: "6 KB"),
    DKFileListItem(id: "/var/mobile/config.yaml", name: "config.yaml", isDirectory: false, detail: "1 KB"),
    DKFileListItem(id: "/var/mobile/backup.tar.gz", name: "backup.tar.gz", isDirectory: false, detail: "48 MB"),
    DKFileListItem(id: "/var/mobile/Info.plist", name: "Info.plist", isDirectory: false, detail: "3 KB"),
]

private struct DKFileListPreview: View {
    @State private var selection: DKFileListItem.ID? = "/var/mobile/Info.plist"

    var body: some View {
        DKFileList(path: "/var/mobile", items: previewItems, selection: $selection) {
            DKButton(DKButtonSpec("Up", glyph: .left, variant: .ghost, size: .icon))
        } trailing: {
            DKButton(DKButtonSpec("Sort", glyph: .list, variant: .ghost, size: .icon))
            DKButton(DKButtonSpec("Refresh", glyph: .refresh, variant: .ghost, size: .icon))
            DKButton(DKButtonSpec("Upload to this folder", glyph: .upload, variant: .ghost, size: .icon))
        } contextMenu: { item in
            Button("Open \(item.name)") {}
            Button("Download") {}
            Divider()
            Button("Delete", role: .destructive) {}
        }
        .frame(width: 268, height: 420)
        .background(DK.Palette.sidebar)
    }
}

#Preview("File list") {
    DKFileListPreview()
        .preferredColorScheme(.light)
}

#Preview("File list, dark") {
    DKFileListPreview()
        .preferredColorScheme(.dark)
}
