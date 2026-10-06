import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Area

/// Tab groups in a split tree, drawn from a `DKPaneGroupsModel`: each group is
/// a `DKTabStrip` over the front tab's content. Tabs move by dragging: onto
/// another tab to take its slot, onto the center of a group to join it, onto a
/// group's edge band to split it on that side. Splitters resize; a group whose
/// last tab closes collapses.
///
/// The tree is laid out flat (`DKPaneLayout.frames(in:)`) in four layers, in
/// this order:
/// 1. each group's chrome: its strip, the empty placeholder and a drop target;
/// 2. every mounted tab's content, identified by tab id, front tabs on top;
/// 3. the drop highlights, and the focus ring when shown;
/// 4. the splitters.
///
/// Layer 2 is why: nested in split containers, a split, a merge or a move to
/// another group changes a pane's place in the view tree and SwiftUI rebuilds
/// it (a terminal would lose its screen). Flat, those only change frames.
///
/// Each mounted pane gets a `DKActivePaneGate` in the environment; act on
/// broadcast commands only while it is active, since hidden panes stay
/// mounted. Ported from uAppKit's `UPaneGroupArea`.
public struct DKPaneGroupArea<Payload, Content: View, EmptyGroup: View>: View {
    private let model: DKPaneGroupsModel<Payload>
    private let dragType: UTType
    private let label: String
    private let newTabLabel: String
    private let showsActiveGroupRing: Bool
    private let tab: (DKPaneTab<Payload>) -> DKTab<UUID>
    private let onNewTab: ((UUID) -> Void)?
    private let onRequestClose: (DKPaneTab<Payload>) -> Void
    private let content: (DKPaneTab<Payload>, Bool) -> Content
    private let emptyGroup: (UUID) -> EmptyGroup

    @State private var dragState = DKPaneDragState()

    /// The tab strip's height, its bottom hairline included.
    public static var stripHeight: CGFloat {
        36
    }

    /// - Parameters:
    ///   - dragType: The app's own type for dragged tabs, declared in its
    ///     Info.plist or used only within the process.
    ///   - label: What VoiceOver calls each group's strip.
    ///   - newTabLabel: The tooltip of each strip's "+" button.
    ///   - showsActiveGroupRing: Outlines the active group while there are several.
    ///   - tab: How a tab looks on its strip; its `id` is replaced by the tab's.
    ///   - onNewTab: Shows a "+" on each strip; runs with that group's id.
    ///   - onRequestClose: A tab's close button was pressed. The area does not
    ///     close tabs itself, so the app can ask first.
    ///   - content: A tab's content, and whether it is its group's front tab.
    ///     Tabs behind stay mounted, hidden.
    ///   - emptyGroup: What an empty group shows.
    public init(
        model: DKPaneGroupsModel<Payload>,
        dragType: UTType,
        label: String = "Tabs",
        newTabLabel: String = "New Tab",
        showsActiveGroupRing: Bool = false,
        tab: @escaping (DKPaneTab<Payload>) -> DKTab<UUID>,
        onNewTab: ((UUID) -> Void)? = nil,
        onRequestClose: @escaping (DKPaneTab<Payload>) -> Void,
        @ViewBuilder content: @escaping (DKPaneTab<Payload>, _ isFront: Bool) -> Content,
        @ViewBuilder emptyGroup: @escaping (_ groupID: UUID) -> EmptyGroup,
    ) {
        self.model = model
        self.dragType = dragType
        self.label = label
        self.newTabLabel = newTabLabel
        self.showsActiveGroupRing = showsActiveGroupRing
        self.tab = tab
        self.onNewTab = onNewTab
        self.onRequestClose = onRequestClose
        self.content = content
        self.emptyGroup = emptyGroup
    }

    public var body: some View {
        GeometryReader { geometry in
            let layout = model.root.frames(in: CGRect(origin: .zero, size: geometry.size))
            ZStack(alignment: .topLeading) {
                ForEach(layout.panes, id: \.paneID) { pane in
                    DKPaneGroupChrome(
                        model: model, dragState: dragState, groupID: pane.paneID, dragType: dragType,
                        label: label, newTabLabel: newTabLabel, tab: tab, onNewTab: onNewTab,
                        onRequestClose: onRequestClose, emptyGroup: emptyGroup,
                    )
                    .frame(width: pane.rect.width, height: pane.rect.height)
                    .offset(x: pane.rect.minX, y: pane.rect.minY)
                }
                ForEach(Self.mountedTabs(model: model, layout: layout)) { item in
                    DKPaneContentHost(model: model, dragState: dragState, item: item, dragType: dragType, content: content)
                        .frame(width: item.rect.width, height: item.rect.height)
                        .offset(x: item.rect.minX, y: item.rect.minY)
                        .zIndex(item.isFront ? 1 : 0)
                }
                if showsActiveGroupRing, layout.panes.count > 1 {
                    ForEach(layout.panes, id: \.paneID) { pane in
                        DKPaneFocusRing(groupID: pane.paneID, model: model)
                            .frame(width: pane.rect.width, height: pane.rect.height)
                            .offset(x: pane.rect.minX, y: pane.rect.minY)
                            .zIndex(2)
                    }
                }
                ForEach(layout.panes, id: \.paneID) { pane in
                    DKPaneDropOverlay(groupID: pane.paneID, dragState: dragState)
                        .frame(width: pane.rect.width, height: pane.rect.height)
                        .offset(x: pane.rect.minX, y: pane.rect.minY)
                        .zIndex(2)
                }
                ForEach(layout.splitters, id: \.splitID) { splitter in
                    DKPaneSplitter(
                        orientation: splitter.direction == .horizontal ? .vertical : .horizontal,
                        fraction: Binding(
                            get: { splitter.fraction },
                            set: { model.setFraction($0, splitID: splitter.splitID) },
                        ),
                        totalLength: splitter.totalLength,
                    )
                    .frame(width: splitter.rect.width, height: splitter.rect.height)
                    .offset(x: splitter.rect.minX, y: splitter.rect.minY)
                    .zIndex(3)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .background(DK.Palette.window)
    }

    /// The tabs to mount, each with its content rectangle (its group's,
    /// below the strip), as `policy.keepAlive` says.
    static func mountedTabs(model: DKPaneGroupsModel<Payload>, layout: DKPaneLayoutFrames) -> [DKMountedPaneTab<Payload>] {
        let keepAlive = model.policy.keepAlive
        let activeGroupID = model.activeGroupID ?? model.root.firstLeafID
        return layout.panes.flatMap { pane -> [DKMountedPaneTab<Payload>] in
            guard let group = model.groups[pane.paneID], !group.tabs.isEmpty else { return [] }
            let isActiveGroup = pane.paneID == activeGroupID
            if keepAlive == .activeGroupOnly, !isActiveGroup {
                return []
            }
            let rect = CGRect(
                x: pane.rect.minX,
                y: pane.rect.minY + stripHeight,
                width: pane.rect.width,
                height: max(0, pane.rect.height - stripHeight),
            )
            return group.tabs.enumerated().compactMap { index, tab in
                let isFront = index == group.activeIndex
                if keepAlive != .allTabs, !isFront {
                    return nil
                }
                return DKMountedPaneTab(
                    tab: tab, groupID: pane.paneID, rect: rect, isFront: isFront,
                    isActivePane: isFront && isActiveGroup,
                )
            }
        }
    }
}

// MARK: - Mounted Tab

/// A mounted tab, the group it is in now and the rectangle it fills.
struct DKMountedPaneTab<Payload>: Identifiable {
    let tab: DKPaneTab<Payload>
    let groupID: UUID
    let rect: CGRect
    let isFront: Bool
    /// The front tab of the active group.
    let isActivePane: Bool

    var id: UUID {
        tab.id
    }
}

/// One tab's content. A tab behind stays in the tree, transparent and out of
/// hit testing, so switching tabs only changes opacity.
private struct DKPaneContentHost<Payload, Content: View>: View {
    let model: DKPaneGroupsModel<Payload>
    let dragState: DKPaneDragState
    let item: DKMountedPaneTab<Payload>
    let dragType: UTType
    let content: (DKPaneTab<Payload>, Bool) -> Content

    @State private var gate = DKActivePaneGate(isActive: false)

    var body: some View {
        content(item.tab, item.isFront)
            // Without a zero minimum the content can grow past its pane and be
            // centered over its neighbors, and the clip below would not stop it.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .opacity(item.isFront ? 1 : 0)
            .environment(\.dkActivePaneGate, gate)
            .onChange(of: item.isActivePane, initial: true) { _, isActive in
                gate.isActive = isActive
            }
            // The content covers its group's chrome, so it carries the group's
            // drop target too, offset by the strip: zones are the whole group's.
            .onDrop(of: [dragType], delegate: DKPaneGroupDropDelegate(
                targetID: item.groupID,
                dragState: dragState,
                dragType: dragType,
                locationOffset: CGSize(width: 0, height: DKPaneGroupArea<Payload, EmptyView, EmptyView>.stripHeight),
                onDrop: { tabID, zone in model.moveTab(tabID, toGroup: item.groupID, zone: zone) },
            ))
            // AppKit content (a terminal, a text view) takes its own mouse-downs,
            // which a SwiftUI tap gesture never sees; the probe sees them all.
            .dkOnPointerDown { _ in
                if item.isFront {
                    model.focusGroup(item.groupID)
                }
            }
            .allowsHitTesting(item.isFront)
            .accessibilityHidden(!item.isFront)
    }
}

// MARK: - Overlays

/// Draws the drop hint. The only view that reads the drag state, so a drag
/// re-evaluates nothing else.
private struct DKPaneDropOverlay: View {
    let groupID: UUID
    let dragState: DKPaneDragState

    var body: some View {
        if let zone = dkPaneDropHighlightZone(
            groupID: groupID,
            draggingTabID: dragState.draggingTabID,
            draggingSourceGroupID: dragState.draggingSourceGroupID,
            hover: dragState.hover,
        ) {
            DKPaneDropHighlight(zone: zone)
        }
    }
}

/// The active group's accent outline.
private struct DKPaneFocusRing<Payload>: View {
    let groupID: UUID
    let model: DKPaneGroupsModel<Payload>

    var body: some View {
        let isActive = (model.activeGroupID ?? model.root.firstLeafID) == groupID
        RoundedRectangle(cornerRadius: DK.Radius.menuItem, style: .continuous)
            .strokeBorder(isActive ? DK.Palette.accent : .clear, lineWidth: 1.5)
            .allowsHitTesting(false)
    }
}

// MARK: - Group Chrome

/// A group's strip, its empty placeholder and its drop target.
private struct DKPaneGroupChrome<Payload, EmptyGroup: View>: View {
    let model: DKPaneGroupsModel<Payload>
    let dragState: DKPaneDragState
    let groupID: UUID
    let dragType: UTType
    let label: String
    let newTabLabel: String
    let tab: (DKPaneTab<Payload>) -> DKTab<UUID>
    let onNewTab: ((UUID) -> Void)?
    let onRequestClose: (DKPaneTab<Payload>) -> Void
    let emptyGroup: (UUID) -> EmptyGroup

    private var group: DKPaneGroup<Payload>? {
        model.groups[groupID]
    }

    var body: some View {
        VStack(spacing: 0) {
            DKTabStrip(
                tabs: tabs,
                selection: selection,
                label: label,
                newTabLabel: newTabLabel,
                isFocused: (model.activeGroupID ?? model.root.firstLeafID) == groupID,
                drag: drag,
                onNewTab: onNewTab.map { onNewTab in { onNewTab(groupID) } },
                onClose: { id in
                    if let closed = model.tab(id) {
                        onRequestClose(closed)
                    }
                },
            )
            .frame(height: DKPaneGroupArea<Payload, EmptyView, EmptyView>.stripHeight)
            Group {
                if group?.tabs.isEmpty ?? true {
                    emptyGroup(groupID)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DK.Palette.window)
        // The group's size, current, for its drop targets' zones.
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { dragState.groupBounds[groupID] = CGRect(origin: .zero, size: geometry.size) }
                    .onChange(of: geometry.size) { _, size in
                        dragState.groupBounds[groupID] = CGRect(origin: .zero, size: size)
                    }
            }
        }
        .onDrop(of: [dragType], delegate: DKPaneGroupDropDelegate(
            targetID: groupID,
            dragState: dragState,
            dragType: dragType,
            onDrop: { tabID, zone in model.moveTab(tabID, toGroup: groupID, zone: zone) },
        ))
        .dkOnPointerDown { _ in model.focusGroup(groupID) }
    }

    /// The strip edits its own copy on close; the area only asks
    /// (`onRequestClose`), so writes are ignored.
    private var tabs: Binding<[DKTab<UUID>]> {
        Binding(
            get: {
                (group?.tabs ?? []).map { paneTab in
                    var item = tab(paneTab)
                    item.id = paneTab.id
                    return item
                }
            },
            set: { _ in },
        )
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { group?.activeTab?.id },
            set: { id in
                guard let id, let index = group?.tabs.firstIndex(where: { $0.id == id }) else { return }
                model.activateTab(groupID: groupID, index: index)
            },
        )
    }

    private var drag: DKTabStripDrag<UUID> {
        DKTabStripDrag(
            type: dragType,
            begin: { id in
                dragState.begin(tabID: id, groupID: groupID)
                return DKPaneTabDragPayload.itemProvider(tabID: id, type: dragType)
            },
            enterTab: { _ in dragState.setHover(nil) },
            dropOnTab: { target, info in
                DKPaneTabReorderDropDelegate(
                    targetTabID: target,
                    dragState: dragState,
                    dragType: dragType,
                    onReorder: { tabID, target in model.reorderTab(tabID, before: target) },
                ).performDrop(info: info)
            },
        )
    }
}
