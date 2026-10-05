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

    /// - Parameters:
    ///   - title: The page's name.
    ///   - subtitle: A muted summary line under the title: counts, the current state.
    ///   - tools: The page's actions and filters, in order from left to right.
    public init(_ title: String, subtitle: String? = nil, @ViewBuilder tools: () -> Tools) {
        self.title = title
        self.subtitle = subtitle
        self.tools = tools()
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
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)
                    .lineLimit(1)
            }
        }
        .padding(.leading, DK.Space.s1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
