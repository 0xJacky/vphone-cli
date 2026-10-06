import SwiftUI

// MARK: - Page header

/// The header at the top of a Launchpad page or a Guest Tools page
/// (`.dk-header`): the page title over a muted subtitle on the left, the page's
/// tools on the right, and a divider along the bottom edge.
///
/// Tools are any views, usually buttons, a segmented control and a search
/// field. When the page is narrow the tools wrap under the title, and onto
/// further lines among themselves.
///
/// In a window that draws its own chrome, the header runs to the window's top
/// edge and serves as its title bar: set `dkPageHeaderIsTitleBar` on the
/// window's content. Dragging the header's background then moves the window,
/// and the header keeps its subtitle line even while there is no subtitle,
/// so the title stays in line with the window buttons and the header does not
/// change height when the subtitle arrives.
///
/// ```swift
/// DKPageHeader("Machines", subtitle: "4 machines · 1 running") {
///     DKButton("New Machine", glyph: .plus, variant: .primary) { create() }
///     DKButton("Import", glyph: .download) { importMachine() }
/// }
///
/// DKPageHeader("Host Setup", subtitle: summary, actions: [
///     DKButtonSpec("Check Again", glyph: .refresh) { recheck() },
/// ])
/// ```
public struct DKPageHeader<Tools: View>: View {
    let title: String
    let subtitle: String?
    let tools: Tools

    @Environment(\.dkPageHeaderIsTitleBar) private var isTitleBar

    /// - Parameters:
    ///   - title: The page's name.
    ///   - subtitle: A muted summary line under the title: counts, the current state.
    ///   - tools: The page's actions and filters, in order from left to right.
    public init(_ title: String, subtitle: String? = nil, @ViewBuilder tools: () -> Tools) {
        self.title = title
        self.subtitle = subtitle
        self.tools = tools()
    }

    /// The design's line heights (`.dk-header__title`, `.dk-header__subtitle`).
    /// With the 12pt top padding they center the title 22pt below the
    /// header's top edge, in line with the window buttons when the header
    /// runs to the window's top.
    static var titleLineHeight: CGFloat { 20 }
    static var subtitleLineHeight: CGFloat { 16 }

    /// Whether the header shows a line under its title: the subtitle, or,
    /// in a title bar, the room for it.
    static func showsSubtitleLine(_ subtitle: String?, isTitleBar: Bool) -> Bool {
        isTitleBar || !(subtitle ?? "").isEmpty
    }

    public var body: some View {
        DKSectionsFlexLayout(horizontalSpacing: DK.Space.s2, verticalSpacing: 10) {
            titles
                .dkSectionsFlex(grow: 1)
            if Tools.self != EmptyView.self {
                DKSectionsFlexLayout(horizontalSpacing: DK.Space.s2, verticalSpacing: DK.Space.s2) {
                    tools
                }
            }
        }
        .padding(.vertical, DK.Space.s3)
        .padding(.horizontal, DK.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isTitleBar {
                // The header is the window's title bar, and drags the window
                // even while it is behind others.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
            }
        }
        .overlay(alignment: .bottom) {
            DKSectionsDivider(color: DK.Palette.divider)
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(DK.Typeface.pageTitle)
                .foregroundStyle(DK.Palette.ink)
                .lineLimit(1)
                .frame(minHeight: Self.titleLineHeight)
                .accessibilityAddTraits(.isHeader)
            if Self.showsSubtitleLine(subtitle, isTitleBar: isTitleBar) {
                Text(subtitle ?? "")
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)
                    .lineLimit(1)
                    .frame(minHeight: Self.subtitleLineHeight)
                    .accessibilityHidden((subtitle ?? "").isEmpty)
            }
        }
        .padding(.leading, DK.Space.s1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension EnvironmentValues {
    /// Whether page headers are their window's title bar: the window draws
    /// its own chrome and each page's header runs to its top edge, beside
    /// the window buttons. Such a header drags the window and keeps its
    /// title in line with the buttons. Guest Tools sets it.
    @Entry var dkPageHeaderIsTitleBar = false
}

public extension DKPageHeader where Tools == EmptyView {
    /// A header without tools.
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

public extension DKPageHeader where Tools == ForEach<[DKButtonSpec], String, DKButton> {
    /// A header whose tools are buttons.
    init(_ title: String, subtitle: String? = nil, actions: [DKButtonSpec]) {
        self.init(title, subtitle: subtitle) {
            ForEach(actions) { DKButton($0) }
        }
    }
}
