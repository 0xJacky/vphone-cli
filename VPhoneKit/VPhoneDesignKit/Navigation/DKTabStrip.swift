import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tab strip

/// The document tab strip of the VM Workspace and Files windows: 36pt tall on
/// the sidebar ground, each tab with its leading dot or glyph, title and close
/// button, and a trailing "+" when `onNewTab` is set. Scrolls sideways when the
/// tabs overflow and keeps the selected tab in view.
///
/// The strip edits `tabs` and `selection` itself: pressing a tab selects it on
/// mouse-down, as native tabs do, the close button removes the tab and selects
/// its neighbor, double-clicking a transient tab keeps it. `onClose` runs after
/// a tab is removed, for cleanup such as ending its session. Hover is tracked
/// once for the whole strip (see `DKRowTracker`) and holds still while the strip
/// scrolls.
///
/// With `drag`, tabs can be dragged out of the strip and dropped on another
/// tab (see `DKPaneGroupArea`, which uses it to move tabs between split
/// panes). A strip that is not `isFocused` draws its selected tab without the
/// accent bar, so that among several strips only the focused one has it.
public struct DKTabStrip<ID: Hashable & Sendable>: View {
    @Binding var tabs: [DKTab<ID>]
    @Binding var selection: ID?
    let label: String
    let newTabLabel: String
    let isFocused: Bool
    let drag: DKTabStripDrag<ID>?
    let onNewTab: (() -> Void)?
    let onClose: ((ID) -> Void)?

    @State private var tabTracker = DKRowTracker()
    @State private var closeTracker = DKRowTracker()

    /// - Parameters:
    ///   - label: What VoiceOver calls the strip ("Terminal tabs").
    ///   - newTabLabel: The "+" button's tooltip and accessibility label.
    ///   - isFocused: Whether the selected tab carries the accent bar.
    ///   - drag: Makes the tabs draggable and drop targets for each other.
    ///   - onNewTab: Shows the "+" button and runs when it is clicked.
    ///   - onClose: Runs after the strip removes a closed tab.
    public init(
        tabs: Binding<[DKTab<ID>]>,
        selection: Binding<ID?>,
        label: String = "Tabs",
        newTabLabel: String = "New Tab",
        isFocused: Bool = true,
        drag: DKTabStripDrag<ID>? = nil,
        onNewTab: (() -> Void)? = nil,
        onClose: ((ID) -> Void)? = nil,
    ) {
        _tabs = tabs
        _selection = selection
        self.label = label
        self.newTabLabel = newTabLabel
        self.isFocused = isFocused
        self.drag = drag
        self.onNewTab = onNewTab
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(tabs) { tab in
                            DKTabView(
                                tab: tab,
                                isSelected: tab.id == selection,
                                isFocused: isFocused,
                                drag: drag,
                                tabTracker: tabTracker,
                                closeTracker: closeTracker,
                                select: { selection = tab.id },
                                keep: { tabs.keepTab(tab.id) },
                                close: { close(tab.id) },
                            )
                            .id(tab.id)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .dkRowTracking(tabTracker) { id, _ in
                        // A press on a close button closes; it does not select first.
                        guard closeTracker.hoveredID != id, let id = id.base as? ID,
                              selection != id, tabs.contains(where: { $0.id == id })
                        else {
                            return
                        }
                        selection = id
                    }
                    .dkRowTracking(closeTracker)
                    .dkScrollHoverGate()
                }
                .scrollIndicators(.never)
                .onChange(of: selection) { _, selected in
                    if let selected {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(selected)
                        }
                    }
                }
            }
            if let onNewTab {
                DKTabStripAddButton(label: newTabLabel, action: onNewTab)
            }
        }
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(DK.Palette.sidebar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DK.Palette.divider).frame(height: DK.Metric.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func close(_ id: ID) {
        guard tabs.contains(where: { $0.id == id && $0.isClosable }) else {
            return
        }
        selection = tabs.closeTab(id, selection: selection)
        onClose?(id)
    }
}

// MARK: - Tab

struct DKTabView<ID: Hashable & Sendable>: View {
    let tab: DKTab<ID>
    let isSelected: Bool
    var isFocused = true
    var drag: DKTabStripDrag<ID>?
    var tabTracker: DKRowTracker?
    var closeTracker: DKRowTracker?
    let select: () -> Void
    let keep: () -> Void
    let close: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 7) {
                    if let tone = tab.statusTone {
                        DKNavigationDot(tone: tone, size: 6)
                    }
                    if let glyph = tab.glyph {
                        DKIcon(glyph, size: 13)
                            .foregroundStyle(isSelected && isFocused ? DK.Palette.accent : DK.Palette.muted)
                    }
                    Text(tab.title)
                        .font(.system(size: 12.5))
                        .italic(tab.isTransient)
                        .lineLimit(1)
                    if tab.isDirty {
                        Circle()
                            .fill(DK.Palette.accent)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.leading, DK.Space.s3)
                .padding(.trailing, tab.isClosable ? 7 : DK.Space.s3)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                if tab.isTransient {
                    keep()
                }
            })
            .accessibilityLabel(tab.isDirty ? "\(tab.title), unsaved" : tab.title)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)

            if tab.isClosable {
                DKTabCloseButton(title: tab.title, id: tab.id, tracker: closeTracker, action: close)
                    .padding(.trailing, 7)
            }
        }
        .foregroundStyle(isSelected ? (isFocused ? DK.Palette.ink : DK.Palette.inkSecondary) : DK.Palette.muted)
        .frame(maxHeight: .infinity)
        .background(background)
        .overlay(alignment: .top) {
            if isSelected, isFocused {
                Rectangle().fill(DK.Palette.accent).frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(DK.Palette.divider).frame(width: DK.Metric.hairline)
        }
        .dkTrackedRow(tabTracker, id: tab.id) { isHovered = $0 }
        .modifier(DKTabDragModifier(id: tab.id, drag: drag))
        .help(tab.help ?? tab.title)
        .contextMenu {
            if tab.isTransient {
                Button("Keep Open", action: keep)
            }
            if tab.isClosable {
                Button("Close Tab", action: close)
            }
        }
    }

    private var background: Color {
        if isSelected {
            return DK.Palette.window
        }
        return isHovered ? DK.Palette.selectionNeutral : .clear
    }
}

// MARK: - Dragging

/// What dragging does on a `DKTabStrip`: `begin` makes the dragged tab's
/// provider, and a drop on a tab of type `type` calls `dropOnTab` with that
/// tab's id. `enterTab` runs while a drag is over a tab.
public struct DKTabStripDrag<ID: Hashable & Sendable> {
    public var type: UTType
    public var begin: (ID) -> NSItemProvider
    public var enterTab: (ID) -> Void
    public var dropOnTab: (ID, DropInfo) -> Bool

    public init(
        type: UTType,
        begin: @escaping (ID) -> NSItemProvider,
        enterTab: @escaping (ID) -> Void = { _ in },
        dropOnTab: @escaping (ID, DropInfo) -> Bool,
    ) {
        self.type = type
        self.begin = begin
        self.enterTab = enterTab
        self.dropOnTab = dropOnTab
    }
}

private struct DKTabDragModifier<ID: Hashable & Sendable>: ViewModifier {
    let id: ID
    let drag: DKTabStripDrag<ID>?

    func body(content: Content) -> some View {
        if let drag {
            content
                .onDrag { drag.begin(id) }
                .onDrop(of: [drag.type], delegate: DKTabDropDelegate(id: id, drag: drag))
        } else {
            content
        }
    }
}

private struct DKTabDropDelegate<ID: Hashable & Sendable>: DropDelegate {
    let id: ID
    let drag: DKTabStripDrag<ID>

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [drag.type])
    }

    func dropEntered(info _: DropInfo) {
        drag.enterTab(id)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        drag.enterTab(id)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.dropOnTab(id, info)
    }
}

struct DKTabCloseButton<ID: Hashable & Sendable>: View {
    let title: String
    let id: ID
    var tracker: DKRowTracker?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            // DKGlyph has no plain cross; the design draws "✕".
            Image(systemName: DKGlyph.close.symbolName)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 22, height: 22)
                .foregroundStyle(DK.Palette.muted)
                .background(
                    RoundedRectangle(cornerRadius: DK.Radius.menuItem, style: .continuous)
                        .fill(isHovered ? DK.Palette.selectionNeutral : .clear),
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dkTrackedRow(tracker, id: id) { isHovered = $0 }
        .help("Close Tab")
        .accessibilityLabel("Close \(title)")
    }
}

struct DKTabStripAddButton: View {
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            DKIcon(.plus, size: 14)
                .foregroundStyle(isHovered ? DK.Palette.ink : DK.Palette.muted)
                .frame(width: 34)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Previews

private struct DKTabStripPreview: View {
    @State private var tabs: [DKTab<String>] = [
        DKTab(id: "display", title: "Display", glyph: .phone, isClosable: false),
        DKTab(id: "shell", title: "ssh research-26", glyph: .terminal, statusTone: .success),
        DKTab(id: "plist", title: "Info.plist", glyph: .doc, isDirty: true, help: "/var/mobile/Library/Info.plist"),
        DKTab(id: "notes", title: "notes.md", glyph: .doc, isTransient: true),
    ]
    @State private var selection: String? = "display"
    @State private var opened = 0

    var body: some View {
        VStack(spacing: 0) {
            DKTabStrip(tabs: $tabs, selection: $selection, label: "Workspace tabs", newTabLabel: "New Terminal Tab") {
                opened += 1
                selection = tabs.openTab(DKTab(id: "shell-\(opened)", title: "ssh research-26 (\(opened + 1))", glyph: .terminal, statusTone: .success))
            }
            DK.Palette.window
        }
        .frame(width: 640, height: 160)
    }
}

#Preview("Tab strip, light") {
    DKTabStripPreview().preferredColorScheme(.light)
}

#Preview("Tab strip, dark") {
    DKTabStripPreview().preferredColorScheme(.dark)
}
