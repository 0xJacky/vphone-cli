import SwiftUI

/// The Launchpad window's layout without `NavigationSplitView`: a fixed-width
/// sidebar, the page, and an optional inspector on the trailing side, each
/// behind a one-point divider.
///
/// Use it where a split view does not fit, such as a window of fixed layout or
/// a standalone preview of a page. The page sits on `background`, the window
/// color by default; put `DK.Palette.page` there for pages that group cards on
/// the page ground. An inspector of `EmptyView` takes no room and no line.
public struct DKWindowShell<Sidebar: View, Content: View, Inspector: View>: View {
    public var sidebarWidth: CGFloat
    public var inspectorWidth: CGFloat
    /// The ground behind the page.
    public var background: Color
    let sidebar: Sidebar
    let content: Content
    let inspector: Inspector

    /// The inspector's default width, after the Files window's selection pane.
    public static var defaultInspectorWidth: CGFloat { 300 }

    public init(
        sidebarWidth: CGFloat = DK.Metric.sidebarWidth,
        inspectorWidth: CGFloat = DKWindowShell.defaultInspectorWidth,
        background: Color = DK.Palette.window,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder inspector: () -> Inspector,
    ) {
        self.sidebarWidth = sidebarWidth
        self.inspectorWidth = inspectorWidth
        self.background = background
        self.sidebar = sidebar()
        self.content = content()
        self.inspector = inspector()
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(DK.Palette.sidebar)
            DKChromeRule(axis: .vertical)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(background)
            if Inspector.self != EmptyView.self {
                DKChromeRule(axis: .vertical)
                inspector
                    .frame(width: inspectorWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(DK.Palette.window)
            }
        }
    }
}

public extension DKWindowShell where Inspector == EmptyView {
    init(
        sidebarWidth: CGFloat = DK.Metric.sidebarWidth,
        background: Color = DK.Palette.window,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
    ) {
        self.init(
            sidebarWidth: sidebarWidth,
            inspectorWidth: 0,
            background: background,
            sidebar: sidebar,
            content: content,
            inspector: { EmptyView() },
        )
    }
}
