import AppKit
import SwiftUI

// MARK: - Gate

/// Turns hover off while a list scrolls.
///
/// When the pointer rests over a list and the content scrolls under it, every
/// row that passes the pointer gets a real enter and exit: AppKit recomputes
/// tracking areas against the window's mouse location whenever geometry
/// changes. Each one writes hover state, redraws the row's hover fill and
/// re-evaluates its body, so a scroll with the pointer over the list costs far
/// more than the same scroll with the pointer outside it, and the pointer is
/// over the list in exactly the case that matters: the user just scrolled it.
///
/// The gate watches the nearest `NSScrollView`. Live-scroll notifications cover
/// dragging the scroller and momentum; the clip view's bounds changes cover the
/// wheel, programmatic scrolls and keyboard paging, which post no live-scroll
/// notification. Either one sets `isScrolling` and pushes a 150 ms quiet timer
/// back; when it fires, `isScrolling` returns to false.
///
/// Rows do not hit-test to recover: `dkHoverGated` keeps passing every enter and
/// exit into a plain box while it holds them back, and hands the last value on
/// when the gate opens. The row under the pointer necessarily saw an enter last
/// and every other row an exit, which is AppKit's own answer and costs nothing.
///
/// ```swift
/// ScrollView {
///     LazyVStack { ForEach(rows) { Row($0) } }
///         .dkScrollHoverGate() // on the content, not on the ScrollView
/// }
/// // In a row:
/// .dkHoverGated { isHovered = $0 } // instead of .onHover
/// ```
///
/// Ported from uAppKit's `ScrollHoverGate`.
@MainActor
@Observable
public final class DKScrollHoverGate {
    /// Whether the list is scrolling now.
    public private(set) var isScrolling = false

    /// How long after the last scroll activity the list counts as still. 150 ms
    /// is shorter than the pause between two flicks of the wheel would allow
    /// without reopening mid-scroll, and long enough not to feel late.
    @ObservationIgnored public var quietInterval: TimeInterval

    /// A `Timer` rather than a task per activity: activity arrives every frame
    /// while scrolling, and moving a fire date costs nothing. It runs in the
    /// common modes, or it would never fire during live scrolling, which runs the
    /// main run loop in the event-tracking mode.
    @ObservationIgnored private var quietTimer: Timer?
    @ObservationIgnored private weak var observedClip: NSClipView?
    @ObservationIgnored private var settledOrigin: NSPoint?

    public nonisolated init(quietInterval: TimeInterval = 0.15) {
        self.quietInterval = quietInterval
    }

    /// Whether hover should be held back right now. Read this, not `isScrolling`:
    /// AppKit delivers the tracking-area events of a bounds change before it posts
    /// the bounds notification, so the first enter of a programmatic scroll would
    /// slip past `isScrolling`. A scroll origin that differs from the one last
    /// seen at rest catches it.
    public var suspendsHover: Bool {
        if isScrolling {
            return true
        }
        if let observedClip, let settledOrigin, observedClip.bounds.origin != settledOrigin {
            return true
        }
        return false
    }

    /// Watches this clip view's scroll origin.
    func observe(clipView: NSClipView?) {
        observedClip = clipView
        settledOrigin = clipView?.bounds.origin
    }

    /// The list just scrolled.
    public func noteActivity() {
        if !isScrolling {
            isScrolling = true
        }
        let deadline = Date(timeIntervalSinceNow: quietInterval)
        if let quietTimer, quietTimer.isValid {
            quietTimer.fireDate = deadline
        } else {
            let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.settle()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            quietTimer = timer
        }
    }

    /// Treats the list as still from now on.
    public func settle() {
        quietTimer?.invalidate()
        quietTimer = nil
        settledOrigin = observedClip?.bounds.origin
        if isScrolling {
            isScrolling = false
        }
    }
}

// MARK: - Scroll observer

/// A transparent view inside the scrolled content that feeds the gate. It
/// draws nothing and takes no part in hit testing.
final class DKScrollActivityObserverView: NSView {
    var gate: DKScrollHoverGate? {
        didSet {
            gate?.observe(clipView: observedClip)
        }
    }

    private weak var observedScrollView: NSScrollView?
    private weak var observedClip: NSClipView?
    private var didRetryAttach = false

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            detach()
        } else {
            attach()
        }
    }

    /// Subscribes to the nearest scroll view. SwiftUI sometimes inserts a
    /// background view before it moves it into the document view, so a miss
    /// tries once more on the next turn of the run loop.
    func attach() {
        guard let scrollView = enclosingScrollView else {
            guard !didRetryAttach else {
                return
            }
            didRetryAttach = true
            DispatchQueue.main.async { [weak self] in
                guard let self, window != nil else {
                    return
                }
                attach()
            }
            return
        }
        guard scrollView !== observedScrollView else {
            return
        }
        detach()
        observedScrollView = scrollView
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        observedClip = clip
        gate?.observe(clipView: clip)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(scrollActivity(_:)), name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        center.addObserver(self, selector: #selector(scrollActivity(_:)), name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        // The wheel, programmatic scrolls and paging post only this one.
        center.addObserver(self, selector: #selector(scrollActivity(_:)), name: NSView.boundsDidChangeNotification, object: clip)
    }

    /// Unsubscribes. Runs when the view leaves its window or is torn down.
    func detach() {
        guard observedScrollView != nil || observedClip != nil else {
            return
        }
        NotificationCenter.default.removeObserver(self)
        observedScrollView = nil
        observedClip = nil
        gate?.observe(clipView: nil)
        // The gate may be closed at this moment; do not leave it that way.
        gate?.settle()
    }

    @objc private func scrollActivity(_: Notification) {
        gate?.noteActivity()
    }
}

private struct DKScrollActivityProbe: NSViewRepresentable {
    let gate: DKScrollHoverGate

    func makeNSView(context _: Context) -> DKScrollActivityObserverView {
        let view = DKScrollActivityObserverView()
        view.gate = gate
        return view
    }

    func updateNSView(_ view: DKScrollActivityObserverView, context _: Context) {
        if view.gate !== gate {
            view.gate = gate
        }
    }

    static func dismantleNSView(_ view: DKScrollActivityObserverView, coordinator _: ()) {
        view.detach()
    }
}

// MARK: - Environment and modifiers

public extension EnvironmentValues {
    /// The gate of the scrolling list this view is in, or nil outside one.
    /// `dkHoverGated` then behaves exactly like `onHover`, so a row can use it
    /// whether or not it sits in a gated list.
    @Entry var dkScrollHoverGate: DKScrollHoverGate? = nil
}

struct DKScrollHoverGateModifier: ViewModifier {
    let external: DKScrollHoverGate?
    @State private var owned = DKScrollHoverGate()

    func body(content: Content) -> some View {
        let gate = external ?? owned
        content
            .background(DKScrollActivityProbe(gate: gate))
            .environment(\.dkScrollHoverGate, gate)
    }
}

/// The value a gated hover last saw and last delivered. A plain class kept in
/// `@State`: writing it while the gate holds hover back must not re-evaluate the
/// row, which is the cost the gate exists to avoid.
final class DKHoverGateBox {
    var pending = false
    var delivered = false
}

struct DKHoverGatedModifier: ViewModifier {
    let action: (Bool) -> Void
    @Environment(\.dkScrollHoverGate) private var gate
    @State private var box = DKHoverGateBox()

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                box.pending = hovering
                if gate?.suspendsHover == true {
                    return
                }
                deliver(hovering)
            }
            .onChange(of: gate?.isScrolling ?? false) { _, scrolling in
                if scrolling {
                    // Remember the current value, then go dark while scrolling.
                    box.pending = box.delivered
                    deliver(false)
                } else {
                    // Hand on the last value AppKit reported while scrolling.
                    deliver(box.pending)
                }
            }
    }

    private func deliver(_ value: Bool) {
        guard box.delivered != value else {
            return
        }
        box.delivered = value
        action(value)
    }
}

public extension View {
    /// Installs a hover gate on a scrolling list. Apply it to the content that
    /// holds the rows (the `LazyVStack`), not to the `ScrollView`: the gate finds
    /// its scroll view by looking up from inside.
    ///
    /// - Parameter gate: A gate to share or drive from a test; by default the
    ///   modifier owns one.
    func dkScrollHoverGate(_ gate: DKScrollHoverGate? = nil) -> some View {
        modifier(DKScrollHoverGateModifier(external: gate))
    }

    /// `onHover` that holds still while the enclosing list scrolls and delivers
    /// the last true value once it stops. Outside a gated list it is `onHover`.
    func dkHoverGated(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(DKHoverGatedModifier(action: action))
    }
}
