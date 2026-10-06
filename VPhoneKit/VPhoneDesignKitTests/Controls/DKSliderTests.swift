import CoreGraphics
import Testing
@testable import VPhoneDesignKit

/// The value math behind the slider: where the knob sits, what a point on the
/// track means, and how steps and keys move the value.
@Suite("DesignKit slider")
struct DKSliderTests {
    // MARK: - Fraction

    @Test
    func `the fraction is how far along the range a value sits`() {
        #expect(DKSlider.fraction(of: 0.6, in: 0 ... 1) == 0.6)
        #expect(DKSlider.fraction(of: 75, in: 50 ... 100) == 0.5)
    }

    @Test
    func `a value outside the range pins the knob to an end`() {
        #expect(DKSlider.fraction(of: -1, in: 0 ... 1) == 0)
        #expect(DKSlider.fraction(of: 2, in: 0 ... 1) == 1)
    }

    @Test
    func `a degenerate range or a non-finite value sits at the start`() {
        #expect(DKSlider.fraction(of: 5, in: 5 ... 5) == 0)
        #expect(DKSlider.fraction(of: .nan, in: 0 ... 1) == 0)
    }

    // MARK: - Snapping

    @Test
    func `a value snaps to the nearest step from the lower bound`() {
        #expect(abs(DKSlider.snapped(0.62, step: 0.05, in: 0 ... 1) - 0.6) < 1e-9)
        #expect(abs(DKSlider.snapped(0.63, step: 0.05, in: 0 ... 1) - 0.65) < 1e-9)
        #expect(DKSlider.snapped(13, step: 5, in: 2 ... 30) == 12)
    }

    @Test
    func `without a step a value is only clamped`() {
        #expect(DKSlider.snapped(0.123, step: nil, in: 0 ... 1) == 0.123)
        #expect(DKSlider.snapped(1.5, step: nil, in: 0 ... 1) == 1)
        #expect(DKSlider.snapped(.infinity, step: nil, in: 0 ... 1) == 0)
    }

    @Test
    func `a step that overshoots the upper bound stays inside the range`() {
        #expect(DKSlider.snapped(0.99, step: 0.3, in: 0 ... 1) <= 1)
    }

    // MARK: - Track position

    @Test
    func `the knob center travels from half a knob in to half a knob before the end`() {
        let width: CGFloat = 218
        let half = DKSliderMetrics.knob / 2
        #expect(DKSlider.value(atX: half, width: width, range: 0 ... 1, step: nil) == 0)
        #expect(DKSlider.value(atX: width - half, width: width, range: 0 ... 1, step: nil) == 1)
        #expect(DKSlider.value(atX: width / 2, width: width, range: 0 ... 1, step: nil) == 0.5)
    }

    @Test
    func `a point past either end of the track reads as that end`() {
        #expect(DKSlider.value(atX: -40, width: 200, range: 0 ... 1, step: nil) == 0)
        #expect(DKSlider.value(atX: 400, width: 200, range: 0 ... 1, step: nil) == 1)
    }

    @Test
    func `a point on the track snaps to the step`() {
        let value = DKSlider.value(atX: 9 + 200 * 0.61, width: 218, range: 0 ... 1, step: 0.05)
        #expect(abs(value - 0.6) < 1e-9)
    }

    @Test
    func `a track narrower than the knob does not divide by zero`() {
        let value = DKSlider.value(atX: 5, width: 4, range: 0 ... 1, step: nil)
        #expect(value.isFinite)
    }

    // MARK: - Stepping

    @Test
    func `a key moves the value by one step`() {
        #expect(abs(DKSlider.stepped(0.6, by: 1, step: 0.05, in: 0 ... 1) - 0.65) < 1e-9)
        #expect(abs(DKSlider.stepped(0.6, by: -5, step: 0.05, in: 0 ... 1) - 0.35) < 1e-9)
    }

    @Test
    func `without a step a key moves a twentieth of the range`() {
        #expect(DKSlider.stepped(0, by: 1, step: nil, in: 0 ... 100) == 5)
    }

    @Test
    func `stepping stops at the ends`() {
        #expect(DKSlider.stepped(0.98, by: 1, step: 0.05, in: 0 ... 1) == 1)
        #expect(DKSlider.stepped(0.02, by: -1, step: 0.05, in: 0 ... 1) == 0)
    }

    @Test
    func `stepping from an off-step value lands on a step`() {
        #expect(abs(DKSlider.stepped(0.62, by: 1, step: 0.05, in: 0 ... 1) - 0.65) < 1e-9)
    }
}
