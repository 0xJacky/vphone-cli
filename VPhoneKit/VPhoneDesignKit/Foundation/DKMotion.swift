import AppKit
import SwiftUI

// Persistent animations (a spinner, a breathing dot, an indeterminate bar) run
// on Core Animation, never on SwiftUI's `repeatForever`.
//
// A `repeatForever` animation pins the whole hosting view in a loop of render,
// display-list diff and commit on every frame. The cost scales with the size of
// the view tree, not of the animated element, and it does not stop when the
// window is on another Space or the app is hidden. Measured on uTerm (the same
// author's app, 2304×1296 at 120 Hz): two breathing dots on an idle welcome page
// held the app above 30% CPU and WindowServer at 61% with no window on a visible
// Space; text was re-rasterized every frame because SwiftUI had flattened it into
// the same drawing layer. A `CABasicAnimation` interpolates in the render server
// instead, costs the main thread nothing per frame and is not composited at all
// while the window is hidden.
//
// The primitives here stay internal; the components below are the public face.

// MARK: - Description

/// What a motion view draws.
enum DKMotionContent: Equatable {
    /// A filled rounded rectangle. A nil `cornerRadius` rounds the short side
    /// fully (a circle or a capsule). A nil `size` fills the bounds; a given
    /// size sits at the leading edge, centered vertically, as a sliding segment.
    case fill(cornerRadius: CGFloat?, size: CGSize?)
    /// A stroked arc of a circle; `trim` is the arc's share of the full turn.
    case arc(trim: CGFloat, lineWidth: CGFloat)
}

/// The two ends of an animated value. Not a `ClosedRange`: the ends are often
/// in descending order (an opacity from 1 down to 0.35), which a range traps on.
struct DKMotionRamp<Value: Equatable>: Equatable {
    var from: Value
    var to: Value
}

/// An endless animation. Equatable so an unchanged one is not restarted every
/// time the parent view updates, which would read as a stutter.
struct DKMotion: Equatable {
    var opacity: DKMotionRamp<Double>?
    var scale: DKMotionRamp<CGFloat>?
    /// Horizontal travel in points.
    var translationX: DKMotionRamp<CGFloat>?
    /// One full turn about the center per cycle.
    var spins = false
    var duration: TimeInterval
    var autoreverses: Bool
    var timing: CAMediaTimingFunctionName

    /// The opacity a layer rests at when this motion animates it: the ramp's
    /// start, so the layer never flashes at full opacity before the animation runs.
    var restingOpacity: Float {
        opacity.map { Float($0.from) } ?? 1
    }
}

// MARK: - Layer view

/// The platform view behind a motion: draws the shape, colors it and owns the
/// animation.
final class DKMotionView: NSView {
    static let animationKey = "dk.motion"

    let shape = CAShapeLayer()
    private var content: DKMotionContent?
    /// Outer nil: not configured yet. Inner nil: no animation (Reduce Motion).
    private var motion: DKMotion??
    private var color: CGColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(shape)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("DKMotionView is built in code")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        syncGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A layer that leaves the layer tree loses its animations; put it back.
        if window != nil {
            restartAnimation()
        }
    }

    func configure(content: DKMotionContent, motion: DKMotion?, color: CGColor) {
        if self.content != content {
            self.content = content
            syncGeometry()
        }
        if self.color != color {
            self.color = color
            applyColor()
        }
        if self.motion == nil || self.motion! != motion {
            self.motion = .some(motion)
            withoutImplicitAnimations {
                shape.opacity = motion?.restingOpacity ?? 1
            }
            restartAnimation()
        }
    }

    /// Whether the endless animation is attached, for tests.
    var isAnimating: Bool {
        shape.animation(forKey: Self.animationKey) != nil
    }

    /// Geometry and color changes run without implicit animations, which would
    /// otherwise fight the endless one.
    private func withoutImplicitAnimations(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    private func syncGeometry() {
        guard let content, bounds.width > 0, bounds.height > 0 else {
            return
        }
        withoutImplicitAnimations {
            switch content {
            case let .fill(cornerRadius, size):
                let box = size.map { CGRect(x: 0, y: (bounds.height - $0.height) / 2, width: $0.width, height: $0.height) } ?? bounds
                shape.frame = box
                let radius = cornerRadius ?? min(box.width, box.height) / 2
                shape.path = CGPath(roundedRect: CGRect(origin: .zero, size: box.size), cornerWidth: radius, cornerHeight: radius, transform: nil)
                shape.fillColor = color
                shape.strokeColor = nil
                shape.lineWidth = 0
            case let .arc(trim, lineWidth):
                shape.frame = bounds
                // Inset by half the line so the stroke is not clipped at the bounds.
                let rect = CGRect(origin: .zero, size: bounds.size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                shape.path = CGPath(ellipseIn: rect, transform: nil)
                shape.fillColor = nil
                shape.strokeColor = color
                shape.lineWidth = lineWidth
                shape.lineCap = .round
                shape.strokeStart = 0
                shape.strokeEnd = trim
            }
        }
    }

    private func applyColor() {
        guard let content else {
            return
        }
        withoutImplicitAnimations {
            switch content {
            case .fill: shape.fillColor = color
            case .arc: shape.strokeColor = color
            }
        }
    }

    private func restartAnimation() {
        shape.removeAnimation(forKey: Self.animationKey)
        guard let motion = motion ?? nil else {
            return
        }
        var animations: [CABasicAnimation] = []
        if let opacity = motion.opacity {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = opacity.from
            fade.toValue = opacity.to
            animations.append(fade)
        }
        if let scale = motion.scale {
            let zoom = CABasicAnimation(keyPath: "transform.scale")
            zoom.fromValue = scale.from
            zoom.toValue = scale.to
            animations.append(zoom)
        }
        if let shift = motion.translationX {
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = shift.from
            slide.toValue = shift.to
            animations.append(slide)
        }
        if motion.spins {
            // AppKit layers are not flipped, so a clockwise turn is negative.
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            animations.append(spin)
        }
        guard !animations.isEmpty else {
            return
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = motion.duration
        group.autoreverses = motion.autoreverses
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: motion.timing)
        // An endless animation never completes; this keeps Core Animation from
        // snapping the layer back to its model values if it ends one early.
        group.isRemovedOnCompletion = false
        shape.add(group, forKey: Self.animationKey)
    }
}

/// A shape that runs an endless Core Animation. Size it with `.frame`. The color
/// resolves in the view's environment, so a change of appearance recolors it.
struct DKMotionShape: NSViewRepresentable {
    let color: Color
    let content: DKMotionContent
    let motion: DKMotion?

    func makeNSView(context _: Context) -> DKMotionView {
        DKMotionView(frame: .zero)
    }

    func updateNSView(_ view: DKMotionView, context: Context) {
        let resolved = color.resolve(in: context.environment)
        view.configure(
            content: content,
            motion: motion,
            color: CGColor(srgbRed: CGFloat(resolved.red), green: CGFloat(resolved.green), blue: CGFloat(resolved.blue), alpha: CGFloat(resolved.opacity)),
        )
    }
}

// MARK: - Spinner

/// An activity spinner: a three-quarter arc turning once a second. It runs on
/// Core Animation, so it keeps turning inside a `Table` or `Form` row that is
/// redrawn around it (the system spinner's `NSProgressIndicator` stops there)
/// and costs nothing per frame. With Reduce Motion it stands still.
public struct DKSpinner: View {
    public var size: CGFloat
    public var lineWidth: CGFloat
    public var color: Color
    public var label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - size: The spinner's diameter; 18pt fits a step mark, 14pt a table cell.
    ///   - color: The arc's color; muted ink by default.
    ///   - label: What VoiceOver says.
    public init(size: CGFloat = 16, lineWidth: CGFloat = 2, color: Color = DK.Palette.muted, label: String = "In progress") {
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
        self.label = label
    }

    public var body: some View {
        DKMotionShape(color: color, content: .arc(trim: 0.72, lineWidth: lineWidth), motion: reduceMotion ? nil : Self.motion)
            .padding(lineWidth / 2)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.updatesFrequently)
    }

    static let motion = DKMotion(spins: true, duration: 1, autoreverses: false, timing: .linear)
}

// MARK: - Breathing dot

/// A status dot that breathes: the whole dot fades between full and `dimOpacity`
/// and back, for a state that lasts (a stream that is live, a guest that is
/// being watched). It runs on Core Animation; with `breathes: false` or Reduce
/// Motion it is a plain dot and creates no layer at all.
public struct DKBreathingDot: View {
    public var tone: DKTone
    public var size: CGFloat
    public var dimOpacity: Double
    public var duration: TimeInterval
    public var breathes: Bool
    public var label: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - tone: The dot's color; `.neutral` draws the idle gray, as `DKStatusDot` does.
    ///   - size: 8pt like `DKStatusDot`; 6pt for sidebar meta and tabs.
    ///   - dimOpacity: How faint the dot gets at the bottom of a breath.
    ///   - duration: One way of a breath, in seconds.
    ///   - breathes: false draws a still dot.
    ///   - label: What VoiceOver says; without one the dot is decoration.
    public init(
        _ tone: DKTone,
        size: CGFloat = DK.Metric.dot,
        dimOpacity: Double = 0.35,
        duration: TimeInterval = 0.9,
        breathes: Bool = true,
        label: String? = nil,
    ) {
        self.tone = tone
        self.size = size
        self.dimOpacity = dimOpacity
        self.duration = duration
        self.breathes = breathes
        self.label = label
    }

    public var body: some View {
        let color = tone == .neutral ? DK.Palette.dotIdle : tone.color
        Group {
            if breathes, !reduceMotion {
                DKMotionShape(color: color, content: .fill(cornerRadius: nil, size: nil), motion: motion)
            } else {
                Circle().fill(color)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
    }

    var motion: DKMotion {
        DKMotion(opacity: DKMotionRamp(from: 1, to: dimOpacity), duration: duration, autoreverses: true, timing: .easeInEaseOut)
    }
}
