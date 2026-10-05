import AppKit
import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// The Core Animation behind spinners, breathing dots and indeterminate bars.
@MainActor
@Suite("DesignKit motion")
struct DKMotionTests {
    @Test
    func `a ramp may run downward, which a closed range would trap on`() {
        let ramp = DKMotionRamp(from: 1.0, to: 0.35)
        #expect(ramp.from > ramp.to)
        let dot = DKBreathingDot(.success)
        #expect(dot.motion.opacity == DKMotionRamp(from: 1, to: 0.35))
        #expect(dot.motion.autoreverses)
        #expect(dot.motion.restingOpacity == 1)
    }

    @Test
    func `the spinner turns once a second without reversing`() {
        #expect(DKSpinner.motion.spins)
        #expect(DKSpinner.motion.duration == 1)
        #expect(!DKSpinner.motion.autoreverses)
    }

    @Test
    func `the indeterminate segment slides across the track and back`() {
        let motion = DKProgress.indeterminateMotion(width: 200)
        #expect(motion.translationX == DKMotionRamp(from: 0, to: 140))
        #expect(motion.autoreverses)
        #expect(DKProgress.indeterminateMotion(width: 0).translationX == DKMotionRamp(from: 0, to: 0))
    }

    @Test
    func `a motion view runs its animation on its layer and drops it without one`() {
        let view = DKMotionView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        let black = CGColor(gray: 0, alpha: 1)
        view.configure(content: .arc(trim: 0.7, lineWidth: 2), motion: DKSpinner.motion, color: black)
        #expect(view.isAnimating)
        view.configure(content: .arc(trim: 0.7, lineWidth: 2), motion: nil, color: black)
        #expect(!view.isAnimating)
        #expect(view.hitTest(NSPoint(x: 8, y: 8)) == nil)
    }

    @Test
    func `an unchanged motion is not restarted on update`() throws {
        let view = DKMotionView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        let color = CGColor(gray: 0, alpha: 1)
        let motion = DKBreathingDot(.success).motion
        view.configure(content: .fill(cornerRadius: nil, size: nil), motion: motion, color: color)
        let first = try #require(view.shape.animation(forKey: DKMotionView.animationKey))
        view.configure(content: .fill(cornerRadius: nil, size: nil), motion: motion, color: CGColor(gray: 1, alpha: 1))
        let second = try #require(view.shape.animation(forKey: DKMotionView.animationKey))
        #expect(first === second)
    }
}
