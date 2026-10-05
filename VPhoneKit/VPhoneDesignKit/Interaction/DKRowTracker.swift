import AppKit
import SwiftUI

// MARK: - Tracker

/// One hover and pointer-down tracker for a whole list, in place of an
/// `onHover` and a tap gesture on every row.
///
/// SwiftUI already serves every `onHover` of a window from one tracking area
/// and a table of hover regions; each region it adds lengthens the table that
/// is walked whenever the pointer or the geometry moves, and each hit writes
/// state and re-evaluates its row. uAppKit measured scrolling with the pointer
/// over three lists at 1.31× to 2.18× the cost of the same scroll with the
/// pointer outside them; with one tracker per list the ratio fell to 0.88× to
/// 1.03×, and hover events while scrolling from about 300 to 0.
///
/// The container carries one transparent `NSView` with one tracking area. The
/// rows report their frames in the container's coordinate space once per
/// layout (scrolling does not move a row within its own list), and the tracker
/// finds the row under the pointer from those frames. Each row has its own
/// observable `DKRowHoverBox`; the tracker itself is not observable, so moving
/// the pointer from one row to the next re-evaluates those two rows and no
/// other.
///
/// The same view watches left mouse-downs in its bounds, so a list can select
/// on press, as native lists and tabs do, without a gesture that would compete
/// with the rows' own buttons or drags.
///
/// ```swift
/// @State private var tracker = DKRowTracker()
///
/// LazyVStack {
///     ForEach(rows) { row in
///         RowView(row).dkTrackedRow(tracker, id: row.id) { isHovered = $0 }
///     }
/// }
/// .dkRowTracking(tracker) { id, _ in select(id) }
/// .dkScrollHoverGate()
/// ```
///
/// Ported from uAppKit's `RowHoverTracker` and `PointerDownProbe`. uAppKit maps
/// the pointer to a row with fixed row-height arithmetic; DesignKit's rows vary
/// in height (group headers, two-line rows, sidebar section titles), so rows
/// report their frames instead.
@MainActor
public final class DKRowTracker {
    /// The name of the container's coordinate space, unique to this tracker.
    public let coordinateSpace: String

    /// The row under the pointer. A plain property: writing it invalidates nothing.
    public private(set) var hoveredID: AnyHashable?

    private var frames: [AnyHashable: CGRect] = [:]
    private var boxes: [AnyHashable: DKRowHoverBox] = [:]

    /// Runs on a left mouse-down over a row, before the event is dispatched.
    var onPointerDown: ((AnyHashable, NSEvent.ModifierFlags) -> Void)?

    public nonisolated init() {
        coordinateSpace = "dk.rows." + UUID().uuidString
    }

    /// The hover box of a row; the same box for the same id every time.
    public func box(for id: AnyHashable) -> DKRowHoverBox {
        if let box = boxes[id] {
            return box
        }
        let box = DKRowHoverBox()
        box.isHovered = hoveredID == id
        boxes[id] = box
        return box
    }

    /// Moves the hover to `id`, or clears it. Flips at most two boxes.
    public func setHovered(_ id: AnyHashable?) {
        guard hoveredID != id else {
            return
        }
        if let old = hoveredID, let box = boxes[old], box.isHovered {
            box.isHovered = false
        }
        hoveredID = id
        if let id, let box = boxes[id], !box.isHovered {
            box.isHovered = true
        }
    }

    /// Records where a row is in the container, or forgets it with nil.
    public func setFrame(_ frame: CGRect?, for id: AnyHashable) {
        frames[id] = frame
        if frame == nil, hoveredID == id {
            setHovered(nil)
        }
    }

    /// The row whose frame contains `point`, in the container's coordinate
    /// space. Rows do not overlap; should two frames hold the point, the smaller wins.
    public func rowID(at point: CGPoint) -> AnyHashable? {
        var best: (id: AnyHashable, area: CGFloat)?
        for (id, frame) in frames where frame.contains(point) {
            let area = frame.width * frame.height
            if best == nil || area < best!.area {
                best = (id, area)
            }
        }
        return best?.id
    }

    /// How many rows have reported a frame, for tests.
    var frameCount: Int {
        frames.count
    }
}

/// Whether one row is under the pointer. Each row reads its own box, so a hover
/// change re-evaluates only the rows whose box flipped.
@MainActor
@Observable
public final class DKRowHoverBox {
    public internal(set) var isHovered = false

    nonisolated init() {}
}

// MARK: - Tracking view

/// The transparent layer behind a list: one tracking area, a mouse-down
/// monitor, no drawing, no part in hit testing.
final class DKRowTrackerView: NSView {
    var tracker: DKRowTracker?
    var gate: DKScrollHoverGate?
    var tracksHover = true
    var observesPointerDown = false {
        didSet {
            updateMonitor()
        }
    }

    private var trackingArea: NSTrackingArea?
    private var monitor: Any?
    private var refreshScheduled = false

    /// Top-left origin, like SwiftUI's coordinate spaces.
    override var isFlipped: Bool {
        true
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitor()
        guard let window else {
            tracker?.setHovered(nil)
            return
        }
        guard tracksHover else {
            return
        }
        window.acceptsMouseMovedEvents = true
        installTrackingAreaIfNeeded()
        refreshSoon()
    }

    /// Installed once: `.inVisibleRect` keeps the area on the visible rect, so
    /// it never has to be torn down and rebuilt.
    private func installTrackingAreaIfNeeded() {
        guard trackingArea == nil else {
            return
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil,
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private func updateMonitor() {
        if window != nil, observesPointerDown {
            guard monitor == nil else {
                return
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.pointerDown(event)
                return event // Watch only; never consume.
            }
        } else if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// Whether a mouse-down monitor is installed, for tests.
    var isObservingPointerDown: Bool {
        monitor != nil
    }

    func detach() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = nil
        observesPointerDown = false
        tracker?.setHovered(nil)
    }

    /// Recomputes the hovered row on the next turn of the run loop. The pointer
    /// may rest over a different row after the list appears, its rows change or
    /// it stops scrolling, and AppKit sends no event for any of those.
    func refreshSoon() {
        guard tracksHover, !refreshScheduled else {
            return
        }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            refreshScheduled = false
            refreshFromWindow()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        update(atWindowPoint: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        update(atWindowPoint: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        tracker?.setHovered(nil)
    }

    /// Scrolling started: clear the hovered row so it does not stay lit.
    func suspend() {
        tracker?.setHovered(nil)
    }

    /// Recomputes the hovered row from where the pointer is now.
    func refreshFromWindow() {
        guard tracksHover, let window, gate?.suspendsHover != true else {
            return
        }
        tracker?.setHovered(rowID(atWindowPoint: window.mouseLocationOutsideOfEventStream))
    }

    func update(atWindowPoint point: NSPoint) {
        guard tracksHover, gate?.suspendsHover != true else {
            return
        }
        tracker?.setHovered(rowID(atWindowPoint: point))
    }

    private func pointerDown(_ event: NSEvent) {
        guard let window, event.window === window, let tracker, let id = rowID(atWindowPoint: event.locationInWindow) else {
            return
        }
        tracker.onPointerDown?(id, event.modifierFlags)
    }

    func rowID(atWindowPoint point: NSPoint) -> AnyHashable? {
        let local = convert(point, from: nil)
        // Only the part of the list that shows: `visibleRect` alone is the whole
        // scroll viewport, `bounds` alone includes rows scrolled out of view.
        guard Self.contains(local, bounds: bounds, visibleRect: visibleRect) else {
            return nil
        }
        return tracker?.rowID(at: local)
    }

    static func contains(_ point: CGPoint, bounds: CGRect, visibleRect: CGRect) -> Bool {
        bounds.intersection(visibleRect).contains(point)
    }
}

/// Lets the SwiftUI side reach the tracking view when the gate opens or closes.
@MainActor
final class DKRowTrackerHandle {
    weak var view: DKRowTrackerView?
}

private struct DKRowTrackerLayer: NSViewRepresentable {
    let tracker: DKRowTracker
    let gate: DKScrollHoverGate?
    let tracksHover: Bool
    let observesPointerDown: Bool
    let handle: DKRowTrackerHandle

    func makeNSView(context _: Context) -> DKRowTrackerView {
        let view = DKRowTrackerView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: DKRowTrackerView, context _: Context) {
        apply(to: view)
    }

    static func dismantleNSView(_ view: DKRowTrackerView, coordinator _: ()) {
        view.detach()
    }

    private func apply(to view: DKRowTrackerView) {
        view.tracker = tracker
        view.gate = gate
        view.tracksHover = tracksHover
        view.observesPointerDown = observesPointerDown
        handle.view = view
        // The rows may have changed under a pointer that has not moved.
        view.refreshSoon()
    }
}

// MARK: - Modifiers

struct DKRowTrackingModifier: ViewModifier {
    let tracker: DKRowTracker
    let tracksHover: Bool
    let onPointerDown: ((AnyHashable, NSEvent.ModifierFlags) -> Void)?

    @Environment(\.dkScrollHoverGate) private var gate
    @State private var handle = DKRowTrackerHandle()

    func body(content: Content) -> some View {
        tracker.onPointerDown = onPointerDown
        return content
            .coordinateSpace(.named(tracker.coordinateSpace))
            .background(DKRowTrackerLayer(tracker: tracker, gate: gate, tracksHover: tracksHover, observesPointerDown: onPointerDown != nil, handle: handle))
            .onChange(of: gate?.isScrolling ?? false) { _, scrolling in
                if scrolling {
                    handle.view?.suspend()
                } else {
                    handle.view?.refreshFromWindow()
                }
            }
    }
}

struct DKTrackedRowModifier: ViewModifier {
    let tracker: DKRowTracker?
    let id: AnyHashable
    let onHover: ((Bool) -> Void)?

    func body(content: Content) -> some View {
        if let tracker {
            let space = tracker.coordinateSpace
            let id = id
            content
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(space))
                } action: { frame in
                    tracker.setFrame(frame, for: id)
                }
                .onDisappear {
                    tracker.setFrame(nil, for: id)
                }
                .modifier(DKRowHoverObserver(box: tracker.box(for: id), onHover: onHover))
        } else if let onHover {
            content.dkHoverGated(onHover)
        } else {
            content
        }
    }
}

private struct DKRowHoverObserver: ViewModifier {
    let box: DKRowHoverBox
    let onHover: ((Bool) -> Void)?

    func body(content: Content) -> some View {
        if let onHover {
            // Reading the box here observes it for this row alone.
            content
                .onChange(of: box.isHovered) { _, hovering in
                    onHover(hovering)
                }
                .onAppear {
                    // A row built under the pointer, as a lazy list scrolls.
                    if box.isHovered {
                        onHover(true)
                    }
                }
        } else {
            content
        }
    }
}

public extension View {
    /// Makes this view the container of a row tracker: one tracking area and,
    /// with `onPointerDown`, one mouse-down monitor for all its rows. Apply it to
    /// the stack that holds the rows, and put `dkScrollHoverGate()` outside it so
    /// the tracker sees the gate.
    ///
    /// - Parameters:
    ///   - tracksHover: false leaves out the tracking area, for a list that
    ///     only needs press-to-select.
    ///   - onPointerDown: Runs on a left mouse-down over a row with the row's id
    ///     and the event's modifier keys, before the row's own controls see the
    ///     event. The event is never consumed.
    func dkRowTracking(
        _ tracker: DKRowTracker,
        tracksHover: Bool = true,
        onPointerDown: ((AnyHashable, NSEvent.ModifierFlags) -> Void)? = nil,
    ) -> some View {
        modifier(DKRowTrackingModifier(tracker: tracker, tracksHover: tracksHover, onPointerDown: onPointerDown))
    }

    /// Registers this view as a row of `tracker`'s container and reports when
    /// the pointer enters and leaves it. Without a tracker it falls back to
    /// `dkHoverGated`, so a row can use it unconditionally.
    func dkTrackedRow(_ tracker: DKRowTracker?, id: some Hashable, onHover: ((Bool) -> Void)? = nil) -> some View {
        modifier(DKTrackedRowModifier(tracker: tracker, id: AnyHashable(id), onHover: onHover))
    }
}
