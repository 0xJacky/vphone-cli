import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Payload

/// A dragged tab's id in an `NSItemProvider`, for reordering and for dropping
/// on a group. The type is the app's own: `UTType(exportedAs:)` needs the app's
/// Info.plist, and a private type keeps text drop targets from taking the drag.
public enum DKPaneTabDragPayload {
    public static func itemProvider(tabID: UUID, type: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
            completion(Data(tabID.uuidString.utf8), nil)
            return nil
        }
        return provider
    }

    public static func load(
        from provider: NSItemProvider,
        type: UTType,
        completion: @escaping @Sendable (UUID?) -> Void,
    ) {
        _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            completion(data.flatMap { String(data: $0, encoding: .utf8) }.flatMap(UUID.init(uuidString:)))
        }
    }
}

// MARK: - Session

/// One tab drag in a pane area: the tab, its group and the zone under the
/// pointer. The dragged tab is kept here so a drop resolves it at once,
/// without waiting for the item provider.
@MainActor
@Observable
public final class DKPaneDragState {
    public internal(set) var draggingTabID: UUID?
    public internal(set) var draggingSourceGroupID: UUID?
    public internal(set) var hover: DKPaneDragHoverTarget?

    /// Each group's size in its own coordinates, kept current by the group.
    /// A drop delegate reads it here: SwiftUI keeps the delegate it registered
    /// first, so a size captured in it would go stale when the window resizes.
    @ObservationIgnored public var groupBounds: [UUID: CGRect] = [:]
    @ObservationIgnored private var endPoll: Task<Void, Never>?

    public init() {}

    /// Writes only a change: drop delegates report every frame, and each
    /// write would re-evaluate every reader.
    public func setHover(_ target: DKPaneDragHoverTarget?) {
        if hover != target {
            hover = target
        }
    }

    /// Starts a drag. `onDrag` has no end callback, so a poll of the mouse
    /// button ends the session once it is released.
    public func begin(tabID: UUID, groupID: UUID) {
        draggingTabID = tabID
        draggingSourceGroupID = groupID
        hover = nil
        endPoll?.cancel()
        endPoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(30))
                guard !Task.isCancelled else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    // Let a drop target run first; a drop ends the session itself.
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                    self?.end()
                    return
                }
            }
        }
    }

    public func end() {
        draggingTabID = nil
        draggingSourceGroupID = nil
        hover = nil
        endPoll?.cancel()
        endPoll = nil
    }
}

// MARK: - Group Drop

/// A group's drop target: classifies the pointer into a zone, records it as
/// the hover, and moves the dragged tab on drop.
struct DKPaneGroupDropDelegate: DropDelegate {
    let targetID: UUID
    let dragState: DKPaneDragState
    let dragType: UTType
    /// Where this target sits in the whole group: the content layer starts
    /// below the tab strip, and zones are measured over the whole group.
    var locationOffset: CGSize = .zero
    let onDrop: @MainActor (_ tabID: UUID, _ zone: DKPaneDropZone) -> Void

    private var bounds: CGRect {
        dragState.groupBounds[targetID] ?? .zero
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [dragType])
    }

    func dropEntered(info: DropInfo) {
        updateHover(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateHover(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info _: DropInfo) {
        // A neighbor may already have taken the hover.
        if dragState.hover?.groupID == targetID {
            dragState.setHover(nil)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let zone = DKPaneDropZone.at(location(info), in: bounds) ?? .center
        let onDrop = onDrop
        if let tabID = dragState.draggingTabID {
            dragState.end()
            onDrop(tabID, zone)
            return true
        }
        dragState.end()
        guard let provider = info.itemProviders(for: [dragType]).first else { return false }
        DKPaneTabDragPayload.load(from: provider, type: dragType) { tabID in
            guard let tabID else { return }
            Task { @MainActor in onDrop(tabID, zone) }
        }
        return true
    }

    private func updateHover(_ info: DropInfo) {
        if let zone = DKPaneDropZone.at(location(info), in: bounds) {
            dragState.setHover(DKPaneDragHoverTarget(groupID: targetID, zone: zone))
        }
    }

    private func location(_ info: DropInfo) -> CGPoint {
        CGPoint(x: info.location.x + locationOffset.width, y: info.location.y + locationOffset.height)
    }
}

// MARK: - Tab Drop

/// A tab's own drop target: the dragged tab takes its slot, in this group or
/// coming from another.
struct DKPaneTabReorderDropDelegate: DropDelegate {
    let targetTabID: UUID
    let dragState: DKPaneDragState
    let dragType: UTType
    let onReorder: @MainActor (_ tabID: UUID, _ targetTabID: UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [dragType])
    }

    func dropEntered(info _: DropInfo) {
        // Over a tab, no split zone applies.
        dragState.setHover(nil)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        dragState.setHover(nil)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let onReorder = onReorder
        let target = targetTabID
        if let tabID = dragState.draggingTabID {
            dragState.end()
            if tabID != target {
                onReorder(tabID, target)
            }
            return true
        }
        dragState.end()
        guard let provider = info.itemProviders(for: [dragType]).first else { return false }
        DKPaneTabDragPayload.load(from: provider, type: dragType) { tabID in
            guard let tabID, tabID != target else { return }
            Task { @MainActor in onReorder(tabID, target) }
        }
        return true
    }
}

// MARK: - AppKit Drop Catcher

/// A group's drop target over AppKit content.
///
/// SwiftUI gives each `onDrop` an AppKit view of its own beside the content,
/// and AppKit hands a drag to the frontmost view under the pointer registered
/// for it. Over an embedded AppKit view such as a terminal, that view wins and
/// is registered for nothing, so the content's `onDrop` never hears the drag
/// and a tab dropped on a terminal does nothing. This view lies over the
/// group's content instead, registered for the tab type only. It answers a
/// hit test only while a tab is being dragged, so clicks, scrolling and the
/// keyboard still reach the content.
struct DKPaneDropCatcher: NSViewRepresentable {
    let targetID: UUID
    let dragState: DKPaneDragState
    let dragType: UTType
    /// Where this view sits in the whole group: it starts below the tab
    /// strip, and zones are measured over the whole group.
    var locationOffset: CGSize = .zero
    let onDrop: @MainActor (_ tabID: UUID, _ zone: DKPaneDropZone) -> Void

    func makeNSView(context _: Context) -> DKPaneDropCatcherView {
        let view = DKPaneDropCatcherView()
        view.registerForDraggedTypes([NSPasteboard.PasteboardType(dragType.identifier)])
        return view
    }

    func updateNSView(_ view: DKPaneDropCatcherView, context _: Context) {
        view.catcher = self
        let type = NSPasteboard.PasteboardType(dragType.identifier)
        if view.registeredDraggedTypes != [type] {
            view.registerForDraggedTypes([type])
        }
    }

    /// The zone under `point`, given in this view's flipped coordinates.
    @MainActor
    func zone(at point: CGPoint) -> DKPaneDropZone? {
        let location = CGPoint(x: point.x + locationOffset.width, y: point.y + locationOffset.height)
        return DKPaneDropZone.at(location, in: dragState.groupBounds[targetID] ?? .zero)
    }
}

final class DKPaneDropCatcherView: NSView {
    var catcher: DKPaneDropCatcher?

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard catcher?.dragState.draggingTabID != nil else { return nil }
        return super.hitTest(point)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        hover(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        hover(sender)
    }

    override func draggingExited(_: (any NSDraggingInfo)?) {
        // A neighbor may already have taken the hover.
        guard let catcher, catcher.dragState.hover?.groupID == catcher.targetID else { return }
        catcher.dragState.setHover(nil)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let catcher else { return false }
        let zone = catcher.zone(at: location(of: sender)) ?? .center
        let dragState = catcher.dragState
        let onDrop = catcher.onDrop
        if let tabID = dragState.draggingTabID {
            dragState.end()
            onDrop(tabID, zone)
            return true
        }
        dragState.end()
        let type = NSPasteboard.PasteboardType(catcher.dragType.identifier)
        guard let data = sender.draggingPasteboard.data(forType: type),
              let tabID = UUID(uuidString: String(decoding: data, as: UTF8.self))
        else { return false }
        onDrop(tabID, zone)
        return true
    }

    private func hover(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let catcher else { return [] }
        if let zone = catcher.zone(at: location(of: sender)) {
            catcher.dragState.setHover(DKPaneDragHoverTarget(groupID: catcher.targetID, zone: zone))
        }
        return .move
    }

    private func location(of sender: any NSDraggingInfo) -> CGPoint {
        convert(sender.draggingLocation, from: nil)
    }
}
