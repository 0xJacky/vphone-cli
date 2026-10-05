import AppKit
import SwiftUI

// SwiftUI on macOS installs no gesture recognizers: `onTapGesture` and its kin
// run from the hosting view's own mouse handling. When the area under the
// pointer is an `NSViewRepresentable` whose view handles `mouseDown` itself (a
// table, a text view, a terminal), hit testing lands on that view and a gesture
// on an ancestor never fires. Any gesture that responds on press also takes over
// the mouse, so the same view can no longer start a drag.
//
// `dkOnPointerDown` watches left mouse-downs with a local event monitor instead:
// it never consumes the event and takes no part in hit testing, so the content
// keeps its clicks, drags and first responder, and the SwiftUI side still learns
// that the area was pressed. Ported from uAppKit's `PointerDownProbe`.

/// The transparent view behind `dkOnPointerDown`.
final class DKPointerDownView: NSView {
    var onPointerDown: ((NSEvent.ModifierFlags) -> Void)?
    private var monitor: Any?

    /// Whether the monitor is installed; it follows membership of a window.
    var isObserving: Bool {
        monitor != nil
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.pointerDown(event)
                return event // Watch only; never consume.
            }
        }
    }

    func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func pointerDown(_ event: NSEvent) {
        guard let window, event.window === window else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if DKRowTrackerView.contains(point, bounds: bounds, visibleRect: visibleRect) {
            onPointerDown?(event.modifierFlags)
        }
    }
}

private struct DKPointerDownProbe: NSViewRepresentable {
    let action: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context _: Context) -> DKPointerDownView {
        let view = DKPointerDownView()
        view.onPointerDown = action
        return view
    }

    func updateNSView(_ view: DKPointerDownView, context _: Context) {
        view.onPointerDown = action
    }

    static func dismantleNSView(_ view: DKPointerDownView, coordinator _: ()) {
        view.removeMonitor()
    }
}

public extension View {
    /// Runs `action` when the left mouse button goes down inside this view's
    /// visible area, even over AppKit content that handles its own clicks, where
    /// `onTapGesture` never fires. It runs on press, as native tabs and lists
    /// select, before the content sees the event, and with the event's modifier
    /// keys. The event is never consumed.
    ///
    /// Overlapping areas each see the press; filter in `action` (by whether the
    /// area is in front, for instance).
    func dkOnPointerDown(perform action: @escaping (NSEvent.ModifierFlags) -> Void) -> some View {
        background(DKPointerDownProbe(action: action))
    }
}
