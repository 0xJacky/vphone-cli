import SwiftUI

/// The Guest Tools panel: a fixed-width sidebar beside a column of the page
/// header, the page's content and a status bar, on the window background.
///
/// Every part is a slot, so the panel takes the guest sidebar, the page header
/// and the status bar from their own components. The panel draws the lines
/// between the parts; set `drawsDividers` to false when the slots draw their own
/// edges. A header or status bar of `EmptyView` takes no room and no line.
public struct DKPanel<Sidebar: View, Header: View, Content: View, StatusBar: View>: View {
    /// The sidebar's width. The guest and Launchpad sidebars are 232pt.
    public var sidebarWidth: CGFloat
    /// Whether the panel draws the lines between sidebar, header, content and status bar.
    public var drawsDividers: Bool
    let sidebar: Sidebar
    let header: Header
    let content: Content
    let statusBar: StatusBar

    public init(
        sidebarWidth: CGFloat = DK.Metric.sidebarWidth,
        drawsDividers: Bool = true,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder statusBar: () -> StatusBar,
    ) {
        self.sidebarWidth = sidebarWidth
        self.drawsDividers = drawsDividers
        self.sidebar = sidebar()
        self.header = header()
        self.content = content()
        self.statusBar = statusBar()
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(DK.Palette.sidebar)
            if drawsDividers {
                DKChromeRule(axis: .vertical)
            }
            VStack(spacing: 0) {
                if Header.self != EmptyView.self {
                    header
                    if drawsDividers {
                        DKChromeRule(axis: .horizontal)
                    }
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if StatusBar.self != EmptyView.self {
                    if drawsDividers {
                        DKChromeRule(axis: .horizontal)
                    }
                    statusBar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DK.Palette.window)
    }
}

public extension DKPanel where StatusBar == EmptyView {
    init(
        sidebarWidth: CGFloat = DK.Metric.sidebarWidth,
        drawsDividers: Bool = true,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
    ) {
        self.init(
            sidebarWidth: sidebarWidth,
            drawsDividers: drawsDividers,
            sidebar: sidebar,
            header: header,
            content: content,
            statusBar: { EmptyView() },
        )
    }
}

// MARK: - Rule

/// A one-point line in the divider color, between the parts of a window.
struct DKChromeRule: View {
    var axis: Axis

    var body: some View {
        switch axis {
        case .horizontal:
            DK.Palette.divider.frame(height: DK.Metric.hairline).frame(maxWidth: .infinity)
        case .vertical:
            DK.Palette.divider.frame(width: DK.Metric.hairline).frame(maxHeight: .infinity)
        }
    }
}
