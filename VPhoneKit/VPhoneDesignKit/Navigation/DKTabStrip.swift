import SwiftUI

// MARK: - Tab strip

/// The document tab strip of the VM Workspace and Files windows: 36pt tall on
/// the sidebar ground, each tab with its leading dot or glyph, title and close
/// button, and a trailing "+" when `onNewTab` is set. Scrolls sideways when the
/// tabs overflow and keeps the selected tab in view.
///
/// The strip edits `tabs` and `selection` itself: clicking selects, the close
/// button removes the tab and selects its neighbor, double-clicking a
/// transient tab keeps it. `onClose` runs after a tab is removed, for cleanup
/// such as ending its session.
public struct DKTabStrip<ID: Hashable & Sendable>: View {
    @Binding var tabs: [DKTab<ID>]
    @Binding var selection: ID?
    let label: String
    let newTabLabel: String
    let onNewTab: (() -> Void)?
    let onClose: ((ID) -> Void)?

    /// - Parameters:
    ///   - label: What VoiceOver calls the strip ("Terminal tabs").
    ///   - newTabLabel: The "+" button's tooltip and accessibility label.
    ///   - onNewTab: Shows the "+" button and runs when it is clicked.
    ///   - onClose: Runs after the strip removes a closed tab.
    public init(
        tabs: Binding<[DKTab<ID>]>,
        selection: Binding<ID?>,
        label: String = "Tabs",
        newTabLabel: String = "New Tab",
        onNewTab: (() -> Void)? = nil,
        onClose: ((ID) -> Void)? = nil,
    ) {
        _tabs = tabs
        _selection = selection
        self.label = label
        self.newTabLabel = newTabLabel
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
                                select: { selection = tab.id },
                                keep: { tabs.keepTab(tab.id) },
                                close: { close(tab.id) },
                            )
                            .id(tab.id)
                        }
                    }
                    .frame(maxHeight: .infinity)
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
                            .foregroundStyle(isSelected ? DK.Palette.accent : DK.Palette.muted)
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
                DKTabCloseButton(title: tab.title, action: close)
                    .padding(.trailing, 7)
            }
        }
        .foregroundStyle(isSelected ? DK.Palette.ink : DK.Palette.muted)
        .frame(maxHeight: .infinity)
        .background(background)
        .overlay(alignment: .top) {
            if isSelected {
                Rectangle().fill(DK.Palette.accent).frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(DK.Palette.divider).frame(width: DK.Metric.hairline)
        }
        .onHover { isHovered = $0 }
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

struct DKTabCloseButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            // DKGlyph has no plain cross; the design draws "✕".
            Image(systemName: "xmark")
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
        .onHover { isHovered = $0 }
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
