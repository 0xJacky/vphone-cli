import SwiftUI

// MARK: - Sidebar

/// A source-list sidebar: optional header, titled sections of rows, optional
/// footer pinned to the bottom. Full height, `DK.Metric.sidebarWidth` wide, on
/// the sidebar ground with a divider on its trailing edge.
///
/// Row glyphs take the accent; the selected row gets the accent tint behind it
/// and a semibold label. With keyboard focus, the up and down arrow keys move
/// the selection.
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

    public init(
        sections: [DKSidebarSection<ID>],
        selection: Binding<ID?>,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer,
    ) {
        self.sections = sections
        _selection = selection
        self.header = header()
        self.footer = footer()
    }

    /// A sidebar that always has a selection.
    public init(
        sections: [DKSidebarSection<ID>],
        selection: Binding<ID>,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer,
    ) {
        self.init(sections: sections, selection: Binding(selection), header: header, footer: footer)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: DK.Space.s4) {
                    if Header.self != EmptyView.self {
                        header
                            .padding(.horizontal, 10)
                            .padding(.top, DK.Space.s1)
                            .padding(.bottom, 6)
                    }
                    ForEach(sections) { section in
                        DKSidebarSectionView(section: section, selection: $selection)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, DK.Space.s3)
            }
            .scrollIndicators(.automatic)

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
}

public extension DKSidebar where Header == EmptyView {
    init(
        sections: [DKSidebarSection<ID>],
        selection: Binding<ID?>,
        @ViewBuilder footer: () -> Footer,
    ) {
        self.init(sections: sections, selection: selection, header: { EmptyView() }, footer: footer)
    }

    init(
        sections: [DKSidebarSection<ID>],
        selection: Binding<ID>,
        @ViewBuilder footer: () -> Footer,
    ) {
        self.init(sections: sections, selection: selection, header: { EmptyView() }, footer: footer)
    }
}

public extension DKSidebar where Footer == EmptyView {
    init(
        sections: [DKSidebarSection<ID>],
        selection: Binding<ID?>,
        @ViewBuilder header: () -> Header,
    ) {
        self.init(sections: sections, selection: selection, header: header, footer: { EmptyView() })
    }

    init(
        sections: [DKSidebarSection<ID>],
        selection: Binding<ID>,
        @ViewBuilder header: () -> Header,
    ) {
        self.init(sections: sections, selection: selection, header: header, footer: { EmptyView() })
    }
}

public extension DKSidebar where Header == EmptyView, Footer == EmptyView {
    init(sections: [DKSidebarSection<ID>], selection: Binding<ID?>) {
        self.init(sections: sections, selection: selection, header: { EmptyView() }, footer: { EmptyView() })
    }

    init(sections: [DKSidebarSection<ID>], selection: Binding<ID>) {
        self.init(sections: sections, selection: selection, header: { EmptyView() }, footer: { EmptyView() })
    }
}

// MARK: - Section and row

struct DKSidebarSectionView<ID: Hashable & Sendable>: View {
    let section: DKSidebarSection<ID>
    @Binding var selection: ID?

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
                DKSidebarRow(item: item, isSelected: item.id == selection) {
                    selection = item.id
                }
            }
        }
    }
}

struct DKSidebarRow<ID: Hashable & Sendable>: View {
    let item: DKSidebarItem<ID>
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                DKIcon(item.glyph, size: 16)
                    .foregroundStyle(DK.Palette.accent)
                Text(item.label)
                    .font(isSelected ? DK.Typeface.bodyStrong : DK.Typeface.body)
                    .foregroundStyle(DK.Palette.ink)
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
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var background: Color {
        if isSelected {
            return DK.Palette.accentTint
        }
        return isHovered ? DK.Palette.selectionNeutral : .clear
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
