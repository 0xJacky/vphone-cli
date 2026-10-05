import AppKit
import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// One tracker per list: rows by frame, two boxes per hover move, one tracking area.
@MainActor
@Suite("DesignKit row tracker")
struct DKRowTrackerTests {
    // MARK: State

    @Test
    func `the row under a point is the one whose frame holds it`() {
        let tracker = DKRowTracker()
        for index in 0 ..< 5 {
            tracker.setFrame(CGRect(x: 0, y: CGFloat(index) * 30, width: 200, height: 30), for: index)
        }
        #expect(tracker.rowID(at: CGPoint(x: 10, y: 5)) == AnyHashable(0))
        #expect(tracker.rowID(at: CGPoint(x: 10, y: 95)) == AnyHashable(3))
        #expect(tracker.rowID(at: CGPoint(x: 10, y: 151)) == nil)
        #expect(tracker.rowID(at: CGPoint(x: 250, y: 5)) == nil)
        tracker.setFrame(nil, for: 3)
        #expect(tracker.rowID(at: CGPoint(x: 10, y: 95)) == nil)
    }

    @Test
    func `the smaller of two frames holding a point wins`() {
        let tracker = DKRowTracker()
        tracker.setFrame(CGRect(x: 0, y: 0, width: 200, height: 36), for: "tab")
        tracker.setFrame(CGRect(x: 170, y: 7, width: 22, height: 22), for: "close")
        #expect(tracker.rowID(at: CGPoint(x: 180, y: 15)) == AnyHashable("close"))
        #expect(tracker.rowID(at: CGPoint(x: 20, y: 15)) == AnyHashable("tab"))
    }

    @Test
    func `moving the hover flips only the two boxes involved`() {
        let tracker = DKRowTracker()
        let boxes = (0 ..< 5).map { tracker.box(for: $0) }
        tracker.setHovered(2)
        #expect(boxes[2].isHovered)
        #expect(boxes.filter(\.isHovered).count == 1)
        tracker.setHovered(3)
        #expect(!boxes[2].isHovered)
        #expect(boxes[3].isHovered)
        #expect(boxes.filter(\.isHovered).count == 1)
        tracker.setHovered(nil)
        #expect(boxes.allSatisfy { !$0.isHovered })
        #expect(tracker.hoveredID == nil)
    }

    @Test
    func `a box keeps its identity and starts hovered when its row already is`() {
        let tracker = DKRowTracker()
        #expect(tracker.box(for: "a") === tracker.box(for: "a"))
        #expect(tracker.box(for: "a") !== tracker.box(for: "b"))
        tracker.setHovered("c")
        #expect(tracker.box(for: "c").isHovered)
    }

    @Test
    func `forgetting the hovered row clears the hover`() {
        let tracker = DKRowTracker()
        tracker.setFrame(CGRect(x: 0, y: 0, width: 10, height: 10), for: 1)
        tracker.setHovered(1)
        tracker.setFrame(nil, for: 1)
        #expect(tracker.hoveredID == nil)
    }

    @Test
    func `trackers have coordinate spaces of their own`() {
        #expect(DKRowTracker().coordinateSpace != DKRowTracker().coordinateSpace)
    }

    // MARK: Tracking view

    private func makeView(gate: DKScrollHoverGate? = nil, tracksHover: Bool = true) -> (DKRowTrackerView, DKRowTracker, NSWindow) {
        let tracker = DKRowTracker()
        for index in 0 ..< 10 {
            tracker.setFrame(CGRect(x: 0, y: CGFloat(index) * 40, width: 300, height: 40), for: index)
        }
        let view = DKRowTrackerView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        view.tracker = tracker
        view.gate = gate
        view.tracksHover = tracksHover
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        host.addSubview(view)
        window.contentView = host
        return (view, tracker, window)
    }

    /// A window point over `row`; the window's origin is at the bottom, the view's at the top.
    private func point(row: Int) -> NSPoint {
        NSPoint(x: 150, y: 400 - (CGFloat(row) * 40 + 20))
    }

    @Test
    func `a list has exactly one tracking area, kept across resizes`() throws {
        let (view, _, window) = makeView()
        defer { window.contentView = nil }
        #expect(view.trackingAreas.count == 1)
        let options = try #require(view.trackingAreas.first).options
        #expect(options.contains(.mouseMoved))
        #expect(options.contains(.inVisibleRect))
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 800)
        view.updateTrackingAreas()
        #expect(view.trackingAreas.count == 1)
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }

    @Test
    func `a list without hover tracking has no tracking area`() {
        let (view, _, window) = makeView(tracksHover: false)
        defer { window.contentView = nil }
        #expect(view.trackingAreas.isEmpty)
        view.update(atWindowPoint: point(row: 2))
        #expect(view.tracker?.hoveredID == nil)
    }

    @Test
    func `the pointer maps to the row under it`() {
        let (view, tracker, window) = makeView()
        defer { window.contentView = nil }
        view.update(atWindowPoint: point(row: 3))
        #expect(tracker.hoveredID == AnyHashable(3))
        view.update(atWindowPoint: point(row: 7))
        #expect(tracker.hoveredID == AnyHashable(7))
        view.update(atWindowPoint: NSPoint(x: 150, y: -20))
        #expect(tracker.hoveredID == nil)
    }

    @Test
    func `hover holds still while the list scrolls and resumes when it stops`() {
        let gate = DKScrollHoverGate()
        let (view, tracker, window) = makeView(gate: gate)
        defer { window.contentView = nil }
        view.update(atWindowPoint: point(row: 4))
        #expect(tracker.hoveredID == AnyHashable(4))
        gate.noteActivity()
        view.suspend()
        #expect(tracker.hoveredID == nil)
        view.update(atWindowPoint: point(row: 6))
        #expect(tracker.hoveredID == nil)
        gate.settle()
        view.update(atWindowPoint: point(row: 6))
        #expect(tracker.hoveredID == AnyHashable(6))
    }

    @Test
    func `the mouse-down monitor follows the window and the request`() {
        let (view, _, window) = makeView()
        defer { window.contentView = nil }
        #expect(!view.isObservingPointerDown)
        view.observesPointerDown = true
        #expect(view.isObservingPointerDown)
        view.removeFromSuperview()
        #expect(!view.isObservingPointerDown)
    }

    @Test
    func `only the visible part of a list counts`() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 38)
        let viewport = CGRect(x: -200, y: -10, width: 900, height: 200)
        #expect(!DKRowTrackerView.contains(CGPoint(x: 300, y: 10), bounds: bounds, visibleRect: viewport))
        #expect(DKRowTrackerView.contains(CGPoint(x: 50, y: 10), bounds: bounds, visibleRect: viewport))
        #expect(!DKRowTrackerView.contains(CGPoint(x: 50, y: 10), bounds: bounds, visibleRect: .zero))
        let half = CGRect(x: 0, y: 0, width: 50, height: 38)
        #expect(DKRowTrackerView.contains(CGPoint(x: 25, y: 10), bounds: bounds, visibleRect: half))
        #expect(!DKRowTrackerView.contains(CGPoint(x: 75, y: 10), bounds: bounds, visibleRect: half))
    }

    @Test
    func `the pointer-down view watches only while in a window`() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let probe = DKPointerDownView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        #expect(!probe.isObserving)
        window.contentView?.addSubview(probe)
        #expect(probe.isObserving)
        probe.removeFromSuperview()
        #expect(!probe.isObserving)
        #expect(probe.hitTest(NSPoint(x: 50, y: 50)) == nil)
    }

    // MARK: Hosted

    @Test
    func `rows report their frames in the list's coordinate space`() {
        let tracker = DKRowTracker()
        let list = VStack(spacing: 0) {
            ForEach(0 ..< 4, id: \.self) { index in
                Color.clear
                    .frame(width: 200, height: index == 0 ? 50 : 30)
                    .dkTrackedRow(tracker, id: index)
            }
        }
        .dkRowTracking(tracker)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 140), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil }
        let host = NSHostingView(rootView: list)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        #expect(tracker.frameCount == 4)
        #expect(tracker.rowID(at: CGPoint(x: 100, y: 25)) == AnyHashable(0))
        #expect(tracker.rowID(at: CGPoint(x: 100, y: 65)) == AnyHashable(1))
        #expect(tracker.rowID(at: CGPoint(x: 100, y: 135)) == AnyHashable(3))
    }
}

/// The gate that holds hover back while a list scrolls.
@MainActor
@Suite("DesignKit scroll hover gate")
struct DKScrollHoverGateTests {
    @Test
    func `activity closes the gate and settling opens it`() {
        let gate = DKScrollHoverGate()
        #expect(!gate.isScrolling)
        #expect(!gate.suspendsHover)
        gate.noteActivity()
        #expect(gate.isScrolling)
        #expect(gate.suspendsHover)
        gate.settle()
        #expect(!gate.isScrolling)
        #expect(!gate.suspendsHover)
    }

    @Test
    func `the gate opens by itself once the list is quiet`() {
        let gate = DKScrollHoverGate(quietInterval: 0.05)
        gate.noteActivity()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        #expect(!gate.isScrolling)
    }

    @Test
    func `a scroll origin that moved since the list was still holds hover back`() {
        let gate = DKScrollHoverGate()
        let clip = NSClipView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        gate.observe(clipView: clip)
        #expect(!gate.suspendsHover)
        clip.setBoundsOrigin(NSPoint(x: 0, y: 40))
        #expect(gate.suspendsHover)
        gate.settle()
        #expect(!gate.suspendsHover)
    }
}
