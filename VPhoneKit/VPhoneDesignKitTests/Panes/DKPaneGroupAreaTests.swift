import AppKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import VPhoneDesignKit

/// What the area view does that can be observed: content is mounted flat,
/// once per tab, so splitting, moving and collapsing keep each pane's view.
/// A marker NSView stands in for the content, so mounted panes can be counted
/// and their identity compared across a change.
///
/// Not testable here: a real drag session (`onDrag` and the drop delegates run
/// only in AppKit's drag loop under a real mouse) and the pointer-down probe.
/// Ported from uAppKit's UPaneGroupAreaViewTests.
@MainActor
@Suite("Pane group area", .serialized)
struct DKPaneGroupAreaTests {
    final class MarkerView: NSView {
        let tabID: UUID

        init(tabID: UUID) {
            self.tabID = tabID
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }
    }

    struct Marker: NSViewRepresentable {
        let tabID: UUID

        func makeNSView(context _: Context) -> MarkerView {
            MarkerView(tabID: tabID)
        }

        func updateNSView(_: MarkerView, context _: Context) {}
    }

    private func markers(in view: NSView) -> [MarkerView] {
        (view as? MarkerView).map { [$0] } ?? view.subviews.flatMap { markers(in: $0) }
    }

    /// The view has to be in a window and the run loop has to turn before
    /// representables exist.
    private func host(_ view: some View) -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view)
        window.contentView = host
        settle(host, window)
        return (window, host)
    }

    private func settle(_ host: NSView, _ window: NSWindow) {
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    private func tab(_ name: String) -> DKPaneTab<String> {
        DKPaneTab(payload: name)
    }

    private func area(_ model: DKPaneGroupsModel<String>) -> some View {
        DKPaneGroupArea(
            model: model,
            dragType: .plainText,
            tab: { DKTab(id: $0.id, title: $0.payload, glyph: .terminal) },
            onRequestClose: { model.closeTab($0.id) },
            content: { tab, _ in Marker(tabID: tab.id) },
            emptyGroup: { _ in Color.clear },
        )
    }

    // MARK: Mounting

    @Test
    func `every tab is mounted once, behind tabs included`() throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        let b = model.openTab { tab("b") }
        model.splitGroup(try #require(model.activeGroupID))
        let c = model.openTab { tab("c") }
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        let mounted = markers(in: host)
        #expect(Set(mounted.map(\.tabID)) == [a, b, c])
        #expect(mounted.count == 3)
    }

    @Test
    func `keeping only front tabs mounts one per group`() throws {
        let model = DKPaneGroupsModel<String>(policy: .init(keepAlive: .activeTabPerGroup))
        model.openTab { tab("a") }
        let b = model.openTab { tab("b") }
        model.splitGroup(try #require(model.activeGroupID))
        let c = model.openTab { tab("c") }
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        #expect(Set(markers(in: host).map(\.tabID)) == [b, c])
    }

    @Test
    func `keeping only the active group mounts one tab`() throws {
        let model = DKPaneGroupsModel<String>(policy: .init(keepAlive: .activeGroupOnly))
        model.openTab { tab("a") }
        model.splitGroup(try #require(model.activeGroupID))
        let c = model.openTab { tab("c") }
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        #expect(markers(in: host).map(\.tabID) == [c])
    }

    @Test
    func `an empty group mounts nothing`() {
        let model = DKPaneGroupsModel<String>()
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        #expect(markers(in: host).isEmpty)
    }

    // MARK: Identity Across Changes

    @Test
    func `splitting keeps the mounted pane`() throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        let group = try #require(model.activeGroupID)
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        let before = try #require(markers(in: host).first { $0.tabID == a })
        model.splitGroup(group)
        settle(host, window)
        let after = try #require(markers(in: host).first { $0.tabID == a })
        #expect(before === after)
    }

    @Test
    func `moving a tab to another group keeps its pane`() throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        model.openTab { tab("b") }
        model.splitGroup(try #require(model.activeGroupID))
        let target = try #require(model.activeGroupID)
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        let before = try #require(markers(in: host).first { $0.tabID == a })
        model.moveTab(a, toGroup: target, zone: .center)
        settle(host, window)
        let after = try #require(markers(in: host).first { $0.tabID == a })
        #expect(before === after)
        #expect(model.locateTab(a)?.groupID == target)
    }

    @Test
    func `collapsing a split keeps the surviving pane`() throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        model.splitGroup(try #require(model.activeGroupID))
        let b = model.openTab { tab("b") }
        let (window, host) = host(area(model))
        defer { window.contentView = nil }
        let before = try #require(markers(in: host).first { $0.tabID == a })
        model.closeTab(b)
        settle(host, window)
        #expect(model.groupCount == 1)
        let remaining = markers(in: host)
        #expect(remaining.map(\.tabID) == [a])
        #expect(remaining.first === before)
    }

    @Test
    func `content wider than its pane stays inside it`() throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        model.splitGroup(try #require(model.activeGroupID))
        let b = model.openTab { tab("b") }
        let view = DKPaneGroupArea(
            model: model,
            dragType: .plainText,
            tab: { DKTab(id: $0.id, title: $0.payload) },
            onRequestClose: { _ in },
            content: { tab, _ in Marker(tabID: tab.id).frame(minWidth: 600) },
            emptyGroup: { _ in Color.clear },
        )
        let (window, host) = host(view.frame(width: 800, height: 600))
        defer { window.contentView = nil }
        let frames = Dictionary(uniqueKeysWithValues: markers(in: host).map { ($0.tabID, $0.convert($0.bounds, to: nil)) })
        let left = try #require(frames[a])
        let right = try #require(frames[b])
        #expect(abs(left.width - 600) < 0.5)
        #expect(abs(left.minX) < 0.5)
        #expect(right.minX >= 400 - 4)
    }

    // MARK: Active Pane Gate

    @Test
    func `each pane's gate follows the active tab`() throws {
        final class Seen: @unchecked Sendable {
            var gates: [UUID: DKActivePaneGate] = [:]
        }
        struct Probe: View {
            let tabID: UUID
            let seen: Seen
            @Environment(\.dkActivePaneGate) private var gate

            var body: some View {
                Color.clear.onAppear {
                    if let gate {
                        seen.gates[tabID] = gate
                    }
                }
            }
        }
        let seen = Seen()
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        let b = model.openTab { tab("b") }
        let group = try #require(model.activeGroupID)
        let view = DKPaneGroupArea(
            model: model,
            dragType: .plainText,
            tab: { DKTab(id: $0.id, title: $0.payload) },
            onRequestClose: { _ in },
            content: { tab, _ in Probe(tabID: tab.id, seen: seen) },
            emptyGroup: { _ in Color.clear },
        )
        let (window, host) = host(view)
        defer { window.contentView = nil }
        let gateA = try #require(seen.gates[a])
        let gateB = try #require(seen.gates[b])
        #expect(gateA !== gateB)
        #expect(!gateA.isActive)
        #expect(gateB.isActive)

        model.activateTab(groupID: group, index: 0)
        settle(host, window)
        #expect(gateA.isActive)
        #expect(!gateB.isActive)
        #expect(seen.gates[a] === gateA)

        // A front tab in a group without focus is not the active pane.
        model.splitGroup(group)
        model.openTab { tab("c") }
        settle(host, window)
        #expect(!gateA.isActive)
    }

}

// MARK: - Drops

/// A drag as AppKit hands it to a drop target: a location in the window and
/// a pasteboard carrying the dragged tab's id. Fed to the hosting view's
/// `NSDraggingDestination` methods, it runs SwiftUI's `onDrop` dispatch, the
/// area's drop delegates, the zone classification and the model's move,
/// everything a mouse drop runs after AppKit's drag loop.
@MainActor
final class DKFakeDraggingInfo: NSObject, @preconcurrency NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    let draggingLocation: NSPoint
    let draggingPasteboard: NSPasteboard
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    let springLoadingHighlight: NSSpringLoadingHighlight = .none
    private let item: NSPasteboardItem

    init(window: NSWindow, location: NSPoint, tabID: UUID, type: UTType) {
        draggingDestinationWindow = window
        draggingLocation = location
        draggingPasteboard = NSPasteboard(name: NSPasteboard.Name("dk.pane.test.\(UUID().uuidString)"))
        draggingPasteboard.clearContents()
        item = NSPasteboardItem()
        item.setData(Data(tabID.uuidString.utf8), forType: NSPasteboard.PasteboardType(type.identifier))
        draggingPasteboard.writeObjects([item])
    }

    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }

    func slideDraggedImage(to _: NSPoint) {}

    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions = [],
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void,
    ) {
        // SwiftUI builds the drop's item providers from these items.
        var stop: ObjCBool = false
        block(NSDraggingItem(pasteboardWriter: item), 0, &stop)
    }

    func resetSpringLoading() {}
}

@MainActor private var dropTrace = ""

extension DKPaneGroupAreaTests {
    /// The view AppKit sends a drag to: it follows the frontmost subview under
    /// the pointer down the tree, and takes the deepest view on that path that
    /// is registered for drags. A frontmost AppKit view registered for nothing,
    /// such as a terminal, hides every drop target behind it, so the content
    /// markers here stand in for one.
    static func dragDestination(in view: NSView, at windowPoint: NSPoint) -> NSView? {
        guard !view.isHidden, view.bounds.contains(view.convert(windowPoint, from: nil)) else { return nil }
        let registered = view.registeredDraggedTypes.isEmpty ? nil : view
        guard let front = view.subviews.reversed().first(where: { !$0.isHidden && $0.bounds.contains($0.convert(windowPoint, from: nil)) }) else {
            return registered
        }
        return dragDestination(in: front, at: windowPoint) ?? registered
    }
}

extension DKPaneGroupAreaTests {
    /// Drops `tabID` at `point` (top-left origin, in the area) the way AppKit
    /// would, and waits for the item provider the delegate falls back on
    /// when no drag began in this process.
    private func drop(_ tabID: UUID, at point: CGPoint, on host: NSView, in window: NSWindow) async {
        let location = host.convert(NSPoint(x: point.x, y: host.isFlipped ? point.y : host.bounds.height - point.y), to: nil)
        let info = DKFakeDraggingInfo(window: window, location: location, tabID: tabID, type: .plainText)
        func targets(_ view: NSView) -> [NSView] {
            (view.registeredDraggedTypes.isEmpty ? [] : [view]) + view.subviews.flatMap(targets)
        }
        let all = targets(host)
        let destination = Self.dragDestination(in: host, at: location) ?? host
        let entered = destination.draggingEntered(info)
        let updated = destination.draggingUpdated(info)
        let prepared = destination.prepareForDragOperation(info)
        let performed = destination.performDragOperation(info)
        destination.concludeDragOperation(info)
        // The delegate loads the tab id from the item provider and moves it on
        // the main actor, which this test holds until it suspends.
        try? await Task.sleep(for: .milliseconds(300))
        settle(host, window)
        dropTrace = "targets=\(all.map { String(describing: type(of: $0)) + "\($0.registeredDraggedTypes.map(\.rawValue))" }) dest=\(type(of: destination)) entered=\(entered.rawValue) updated=\(updated.rawValue) prepared=\(prepared) performed=\(performed)"
    }

    @Test
    func `a drop on a pane's edge splits it, and on its center joins it`() async throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        let b = model.openTab { tab("b") }
        let (window, host) = host(area(model).frame(width: 800, height: 600))
        defer { window.contentView = nil }

        // The right quarter of the only pane, below the strip: a split beside.
        await drop(a, at: CGPoint(x: 780, y: 300), on: host, in: window)
        #expect(model.groupCount == 2)
        guard case let .split(split) = model.root else {
            Issue.record("expected a split, got \(model.root); \(dropTrace)")
            return
        }
        #expect(split.direction == .horizontal)
        let right = try #require(model.locateTab(a)?.groupID)
        #expect(split.second == .leaf(paneID: right))
        #expect(model.locateTab(b)?.groupID != right)

        // The center of the right pane takes b too; the left pane collapses.
        await drop(b, at: CGPoint(x: 600, y: 330), on: host, in: window)
        #expect(model.groupCount == 1)
        #expect(model.groups[right]?.tabs.map(\.id) == [a, b])
    }

    @Test
    func `a drop over AppKit content reaches the group, and clicks still reach the content`() throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        let (window, host) = host(area(model).frame(width: 800, height: 600))
        defer { window.contentView = nil }
        let point = host.convert(NSPoint(x: 400, y: 300), to: nil)
        // Over the AppKit content the catcher takes the drag...
        let destination = try #require(Self.dragDestination(in: host, at: point))
        #expect(destination is DKPaneDropCatcherView)
        // ...but while no tab is dragged, a click goes to the content.
        let hit = host.hitTest(host.superview?.convert(point, from: nil) ?? point)
        #expect((hit as? MarkerView)?.tabID == a)
    }

    @Test
    func `a drop on a pane's bottom band stacks the panes`() async throws {
        let model = DKPaneGroupsModel<String>()
        let a = model.openTab { tab("a") }
        model.openTab { tab("b") }
        let (window, host) = host(area(model).frame(width: 800, height: 600))
        defer { window.contentView = nil }
        await drop(a, at: CGPoint(x: 400, y: 590), on: host, in: window)
        guard case let .split(split) = model.root else {
            Issue.record("expected a split, got \(model.root); \(dropTrace)")
            return
        }
        #expect(split.direction == .vertical)
        #expect(split.second == .leaf(paneID: try #require(model.locateTab(a)?.groupID)))
    }
}

