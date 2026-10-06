import SwiftUI

// MARK: - Settings tab

/// One page of a settings window: its name and the glyph drawn above it.
public struct DKSettingsTab<ID: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    public var id: ID
    public var title: String
    public var glyph: DKGlyph

    public init(id: ID, title: String, glyph: DKGlyph) {
        self.id = id
        self.title = title
        self.glyph = glyph
    }
}

public extension Array {
    /// The selected tab's name, which a settings window shows as its title.
    /// Empty when the selection is not one of the tabs.
    func settingsTitle<ID>(for selection: ID) -> String where Element == DKSettingsTab<ID> {
        first { $0.id == selection }?.title ?? ""
    }
}

// MARK: - Settings tab bar

/// The header band of a settings window that draws its own chrome: the window
/// buttons at the top left, the selected tab's name centered as the title, and
/// under it a row of tabs, each a glyph over its name. The selected tab sits on
/// the accent tint in accent ink. The band is on the sidebar ground with a
/// hairline below, and dragging any part of it that is not a control moves the
/// window.
///
/// ```swift
/// VStack(spacing: 0) {
///     DKSettingsTabBar(tabs: tabs, selection: $tab, label: "Settings")
///     page(tab)
/// }
/// .dkWindowChrome()
/// ```
public struct DKSettingsTabBar<ID: Hashable & Sendable>: View {
    let tabs: [DKSettingsTab<ID>]
    @Binding var selection: ID
    let label: String
    let windowControls: Bool

    @State private var hovered: ID?

    /// - Parameters:
    ///   - label: What VoiceOver calls the row of tabs ("Settings").
    ///   - windowControls: Draws the window buttons; leave it on for a window
    ///     whose title bar this band replaces.
    public init(tabs: [DKSettingsTab<ID>], selection: Binding<ID>, label: String, windowControls: Bool = true) {
        self.tabs = tabs
        _selection = selection
        self.label = label
        self.windowControls = windowControls
    }

    public var body: some View {
        VStack(spacing: DKSettingsTabBarMetrics.titleGap) {
            Text(tabs.settingsTitle(for: selection))
                .font(DKSettingsTabBarMetrics.titleFont)
                .foregroundStyle(DK.Palette.ink)
                .lineLimit(1)
                .frame(height: DKSettingsTabBarMetrics.titleHeight)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: DKSettingsTabBarMetrics.tabGap) {
                ForEach(tabs) { tab in
                    tabButton(tab)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
        }
        .padding(.top, DKSettingsTabBarMetrics.topPadding)
        .padding(.bottom, DKSettingsTabBarMetrics.bottomPadding)
        .padding(.horizontal, DK.Space.s4)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            if windowControls {
                DKWindowControls()
                    .padding(.leading, DKSettingsTabBarMetrics.windowControlsLeading)
                    .padding(.top, DKSettingsTabBarMetrics.windowControlsTop)
            }
        }
        .background {
            DK.Palette.sidebar
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(DK.Palette.divider).frame(height: DK.Metric.hairline)
        }
    }

    private func tabButton(_ tab: DKSettingsTab<ID>) -> some View {
        let isSelected = tab.id == selection
        return Button {
            selection = tab.id
        } label: {
            VStack(spacing: DKSettingsTabBarMetrics.glyphGap) {
                DKIcon(tab.glyph, size: DKSettingsTabBarMetrics.glyphSize)
                Text(tab.title)
                    .font(DKSettingsTabBarMetrics.labelFont)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(DKSettingsTabBarMetrics.ink(isSelected: isSelected))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(minWidth: DKSettingsTabBarMetrics.tabMinWidth)
            .background(
                DKSettingsTabBarMetrics.ground(isSelected: isSelected, isHovered: hovered == tab.id),
                in: RoundedRectangle(cornerRadius: DKSettingsTabBarMetrics.tabRadius, style: .continuous),
            )
            .contentShape(RoundedRectangle(cornerRadius: DKSettingsTabBarMetrics.tabRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hovered = tab.id
            } else if hovered == tab.id {
                hovered = nil
            }
        }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The band's measures, from the design's settings header.
enum DKSettingsTabBarMetrics {
    static let topPadding: CGFloat = 10
    static let bottomPadding: CGFloat = 8
    static let titleHeight: CGFloat = 18
    static let titleGap: CGFloat = 6
    static let titleFont = Font.system(size: 13, weight: .semibold)
    static let tabGap: CGFloat = 4
    static let tabMinWidth: CGFloat = 72
    static let tabRadius = DK.Radius.control
    static let glyphSize: CGFloat = 22
    static let glyphGap: CGFloat = 3
    static let labelFont = Font.system(size: 11)
    /// The window buttons' centers sit 20pt in and 20pt down, level with the
    /// title.
    static let windowControlsLeading: CGFloat = 20 - 7
    static let windowControlsTop: CGFloat = 20 - 7

    static func ink(isSelected: Bool) -> Color {
        isSelected ? DK.Palette.accent : DK.Palette.inkSecondary
    }

    static func ground(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return DK.Palette.accentTint
        }
        return isHovered ? DK.Palette.selectionNeutral : .clear
    }
}

// MARK: - Previews

#if DEBUG
    private struct DKSettingsTabBarPreview: View {
        @State private var tab = "general"

        var body: some View {
            VStack(spacing: 0) {
                DKSettingsTabBar(
                    tabs: [
                        DKSettingsTab(id: "general", title: "General", glyph: .gear),
                        DKSettingsTab(id: "library", title: "Library", glyph: .folder),
                        DKSettingsTab(id: "bundles", title: "Bundles", glyph: .bundle),
                        DKSettingsTab(id: "advanced", title: "Advanced", glyph: .sliders),
                    ],
                    selection: $tab,
                    label: "Settings",
                )
                DK.Palette.page.frame(height: 120)
            }
            .frame(width: 672)
        }
    }

    #Preview("Settings tab bar") {
        DKSettingsTabBarPreview()
    }
#endif
