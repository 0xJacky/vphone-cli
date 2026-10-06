import SwiftUI

// MARK: - Sidebar

/// A source-list sidebar: optional header, titled sections of rows, optional
/// footer pinned to the bottom. Full height, `DK.Metric.sidebarWidth` wide, on
/// the sidebar ground with a divider on its trailing edge.
///
/// Row glyphs take the accent; the selected row gets the accent tint behind it
/// and a semibold label. A row selects on mouse-down, as a source list does.
/// With keyboard focus, the up and down arrow keys move the selection, past
/// disabled rows. One tracker serves the hover of every row (see `DKRowTracker`).
///
/// The sidebar does not scroll: its rows are a short, fixed list, and their
/// height is the sidebar's minimum, so a window sized by its content (a
/// SwiftUI scene, or a hosting controller with `.minSize`) cannot be made
/// shorter than its rows and footer.
///
/// ```swift
/// DKSidebar(sections: sections, selection: $selection) {
///     DKSidebarMachineHeader("research-26", tone: .success, facts: facts)
/// } footer: {
///     DKSidebarFooter(lines)
/// }
/// ```
///
/// With only a header or only a footer, label the closure
/// (`DKSidebar(sections:selection:footer:)`); a bare trailing closure would
/// fit either.
public struct DKSidebar<ID: Hashable & Sendable, Header: View, Footer: View>: View {
    let sections: [DKSidebarSection<ID>]
    @Binding var selection: ID?
    let header: Header
    let footer: Footer
    /// Draws the window buttons in a band at the top, for a window whose
    /// sidebar runs to its top edge.
    let windowControls: Bool

    @State private var tracker = DKRowTracker()

    public init(
        sections: [DKSidebarSection<ID>],
        selection: Binding<ID?>,
        windowControls: Bool = false,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer,
    ) {
        self.sections = sections
        _selection = selection
        self.windowControls = windowControls
        self.header = header()
        self.footer = footer()
    }

    /// A sidebar that always has a selection.
    public init(
        sections: [DKSidebarSection<ID>],
        selection: Binding<ID>,
        windowControls: Bool = false,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer,
    ) {
        self.init(sections: sections, selection: Binding(selection), windowControls: windowControls, header: header, footer: footer)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if windowControls {
                DKSidebarWindowBand()
            }
            VStack(alignment: .leading, spacing: DK.Space.s4) {
                if Header.self != EmptyView.self {
                    header
                        .padding(.horizontal, 10)
                        .padding(.top, DK.Space.s1)
                        .padding(.bottom, 6)
                }
                ForEach(sections) { section in
                    DKSidebarSectionView(section: section, selection: $selection, tracker: tracker)
                }
            }
            .dkRowTracking(tracker) { id, _ in
                select(id)
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, DK.Space.s3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            if Footer.self != EmptyView.self {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(DK.Palette.line).frame(height: DK.Metric.hairline)
                    footer
                        .padding(.horizontal, 10)
                        .padding(.top, DK.Space.s3)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, DK.Space.s3)
            }
        }
        .frame(width: DK.Metric.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DK.Palette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DK.Palette.divider).frame(width: DK.Metric.hairline)
        }
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand { direction in
            switch direction {
            case .up: move(by: -1)
            case .down: move(by: 1)
            default: break
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func move(by offset: Int) {
        if let next = sections.sidebarItemID(from: selection, offset: offset) {
            selection = next
        }
    }

    /// Selects the row pressed, if it is an enabled row of this sidebar.
    private func select(_ id: AnyHashable) {
        guard let id = id.base as? ID,
              sections.allSidebarItems().contains(where: { $0.id == id && $0.isEnabled })
        else {
            return
        }
        if selection != id {
            selection = id
        }
    }
}

public extension DKSidebar where Header == EmptyView {
    init(
        sections: [DKSidebarSection<ID>],
        selection: Binding<ID?>,
        windowControls: Bool = false,
        @ViewBuilder footer: () -> Footer,
    ) {
        self.init(sections: sections, selection: selection, windowControls: windowControls, header: { EmptyView() }, footer: footer)
    }

    init(
        sections: [DKSidebarSection<ID>],
        selection: Binding<ID>,
        windowControls: Bool = false,
        @ViewBuilder footer: () -> Footer,
    ) {
        self.init(sections: sections, selection: selection, windowControls: windowControls, header: { EmptyView() }, footer: footer)
    }
}

public extension DKSidebar where Footer == EmptyView {
    init(
        sections: [DKSidebarSection<ID>],
        selection: Binding<ID?>,
        windowControls: Bool = false,
        @ViewBuilder header: () -> Header,
    ) {
        self.init(sections: sections, selection: selection, windowControls: windowControls, header: header, footer: { EmptyView() })
    }

    init(
        sections: [DKSidebarSection<ID>],
        selection: Binding<ID>,
        windowControls: Bool = false,
        @ViewBuilder header: () -> Header,
    ) {
        self.init(sections: sections, selection: selection, windowControls: windowControls, header: header, footer: { EmptyView() })
    }
}

public extension DKSidebar where Header == EmptyView, Footer == EmptyView {
    init(sections: [DKSidebarSection<ID>], selection: Binding<ID?>, windowControls: Bool = false) {
        self.init(sections: sections, selection: selection, windowControls: windowControls, header: { EmptyView() }, footer: { EmptyView() })
    }

    init(sections: [DKSidebarSection<ID>], selection: Binding<ID>, windowControls: Bool = false) {
        self.init(sections: sections, selection: selection, windowControls: windowControls, header: { EmptyView() }, footer: { EmptyView() })
    }
}

// MARK: - Section and row

/// The band at the top of a sidebar that holds the window buttons, where the
/// system title bar would put them: 16pt in, centered 22pt from the top, in
/// line with the page header's title. Dragging it moves the window.
struct DKSidebarWindowBand: View {
    static let height: CGFloat = 36

    var body: some View {
        DKWindowControls()
            .padding(.leading, DK.Space.s4)
            .padding(.top, 22 - 7)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .topLeading)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
            }
    }
}

struct DKSidebarSectionView<ID: Hashable & Sendable>: View {
    let section: DKSidebarSection<ID>
    @Binding var selection: ID?
    var tracker: DKRowTracker?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let title = section.title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DK.Palette.muted)
                    .padding(.horizontal, 10)
                    .padding(.bottom, DK.Space.s1)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(section.items) { item in
                DKSidebarRow(item: item, isSelected: item.id == selection, tracker: tracker) {
                    selection = item.id
                }
            }
        }
    }
}

struct DKSidebarRow<ID: Hashable & Sendable>: View {
    let item: DKSidebarItem<ID>
    let isSelected: Bool
    var tracker: DKRowTracker?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                DKIcon(item.glyph, size: 16)
                    .foregroundStyle(item.isEnabled ? DK.Palette.accent : DK.Palette.inkDisabled)
                Text(item.label)
                    .font(isSelected ? DK.Typeface.bodyStrong : DK.Typeface.body)
                    .foregroundStyle(item.isEnabled ? DK.Palette.ink : DK.Palette.inkDisabled)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let text = item.trailingText {
                    HStack(spacing: 5) {
                        if let tone = item.metaTone {
                            DKNavigationDot(tone: tone, size: 6)
                        }
                        Text(text)
                            .font(item.isMetaMonospaced ? DK.Typeface.mono : DK.Typeface.caption.monospacedDigit())
                            .foregroundStyle(DK.Palette.muted)
                            .lineLimit(1)
                    }
                    .fixedSize()
                }
                if item.isWarning {
                    DKIcon(.warning, size: 14)
                        .foregroundStyle(DK.Palette.warning)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.row, style: .continuous)
                    .fill(background),
            )
            .contentShape(RoundedRectangle(cornerRadius: DK.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!item.isEnabled)
        .help(item.isEnabled ? "" : item.disabledReason ?? "")
        .dkTrackedRow(tracker, id: item.id) { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The design marks the current row with the neutral selection fill, not the
    /// accent (its glyph already carries the accent); hover is a lighter wash.
    private var background: Color {
        if isSelected {
            return DK.Palette.selectionNeutral
        }
        return isHovered && item.isEnabled ? DKSidebarFill.hover : .clear
    }

}

/// A status dot at a size other than the 8pt of `DKStatusDot`, for sidebar meta, footers and tabs.
struct DKNavigationDot: View {
    let tone: DKTone
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(tone == .neutral ? DK.Palette.dotIdle : tone.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Header

/// The Guest Tools sidebar header: the machine name after a status dot, then
/// key-value facts (iOS version, address). No card behind it.
public struct DKSidebarMachineHeader: View {
    public let name: String
    public var tone: DKTone
    public var stateLabel: String?
    public var facts: [DKSidebarFact]

    /// `stateLabel` is what VoiceOver reads for the dot ("Guest connected").
    public init(_ name: String, tone: DKTone = .success, stateLabel: String? = nil, facts: [DKSidebarFact] = []) {
        self.name = name
        self.tone = tone
        self.stateLabel = stateLabel
        self.facts = facts
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s3) {
            HStack(spacing: DK.Space.s2) {
                DKStatusDot(tone, label: stateLabel)
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DK.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !facts.isEmpty {
                VStack(alignment: .leading, spacing: DK.Space.s2) {
                    ForEach(facts) { fact in
                        HStack(spacing: DK.Space.s3) {
                            Text(fact.label)
                                .foregroundStyle(DK.Palette.muted)
                            Spacer(minLength: 0)
                            Text(fact.value)
                                .font(fact.isMonospaced ? DK.Typeface.mono : DK.Typeface.caption)
                                .foregroundStyle(DK.Palette.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        .font(DK.Typeface.caption)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Footer

/// The Launchpad sidebar footer: short muted lines, a status dot before the
/// first ("● Helper 2.6.0 ready"), the library path in monospace.
public struct DKSidebarFooter: View {
    public var lines: [DKSidebarFooterLine]

    public init(_ lines: [DKSidebarFooterLine]) {
        self.lines = lines
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                HStack(spacing: 6) {
                    if let tone = line.tone {
                        DKNavigationDot(tone: tone, size: 7)
                    }
                    Text(line.text)
                        .font(line.isMonospaced ? DK.Typeface.mono : DK.Typeface.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .foregroundStyle(DK.Palette.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

private enum DKSidebarPreviewID: String, Hashable, Sendable {
    case all, recent, starred, shared, trash
}

private struct DKSidebarPreview: View {
    @State private var selection: DKSidebarPreviewID? = .recent

    var body: some View {
        DKSidebar(
            sections: [
                DKSidebarSection("Library", items: [
                    DKSidebarItem(id: .all, label: "All Machines", glyph: .machines, meta: "2/5", metaTone: .success),
                    DKSidebarItem(id: .recent, label: "Recent", glyph: .timer, count: 3),
                    DKSidebarItem(id: .starred, label: "Starred", glyph: .seal, meta: "2.6.0", isMetaMonospaced: true),
                ]),
                DKSidebarSection("Other", items: [
                    DKSidebarItem(id: .shared, label: "Shared", glyph: .network, isWarning: true),
                    DKSidebarItem(id: .trash, label: "Trash", glyph: .trash),
                ]),
            ],
            selection: $selection,
        ) {
            DKSidebarMachineHeader("research-26", tone: .success, facts: [
                DKSidebarFact("iOS", "26.6.2"),
                DKSidebarFact("Address", "192.168.64.12", isMonospaced: true),
            ])
        } footer: {
            DKSidebarFooter([
                DKSidebarFooterLine("Helper 2.6.0 ready", tone: .success),
                DKSidebarFooterLine("~/VPhone", isMonospaced: true),
            ])
        }
        .frame(height: 560)
    }
}

#Preview("Sidebar, light") {
    DKSidebarPreview().preferredColorScheme(.light)
}

#Preview("Sidebar, dark") {
    DKSidebarPreview().preferredColorScheme(.dark)
}

/// Cached sidebar fills, kept out of the generic row type.
enum DKSidebarFill {
    static let hover = DK.Palette.dynamic(0x000000, 0xFFFFFF, lightAlpha: 0.035, darkAlpha: 0.05)
}
