import SwiftUI

// MARK: - Slider

/// The DesignKit slider (`.dk-range`): a 6pt track filled in the accent up to
/// the value, and an 18pt round knob on the window ground with a hairline
/// border. Optional glyphs at both ends say what the ends mean (a quiet and a
/// loud speaker for a volume).
///
/// It drags from anywhere on the track, follows the arrow keys, Page Up/Down,
/// Home and End when focused, and reads to VoiceOver as an adjustable value.
/// `onEditingChanged` fires `true` when a drag or key adjustment starts and
/// `false` when it ends, so a caller can commit once instead of per frame.
public struct DKSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let label: String
    let minimumGlyph: DKGlyph?
    let maximumGlyph: DKGlyph?
    let valueText: ((Double) -> String)?
    let onEditingChanged: (Bool) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    @State private var isDragging = false

    /// - Parameters:
    ///   - label: What the slider sets; the VoiceOver label.
    ///   - value: The value, kept within `range` and snapped to `step`.
    ///   - range: The values the ends stand for.
    ///   - step: The increment; nil moves continuously (keys move a twentieth).
    ///   - minimumGlyph: A glyph before the track, for the low end.
    ///   - maximumGlyph: A glyph after the track, for the high end.
    ///   - valueText: How VoiceOver reads the value; a percentage of the range by default.
    ///   - onEditingChanged: `true` when an adjustment starts, `false` when it ends.
    public init(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0 ... 1,
        step: Double? = nil,
        minimumGlyph: DKGlyph? = nil,
        maximumGlyph: DKGlyph? = nil,
        valueText: ((Double) -> String)? = nil,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
    ) {
        _value = value
        self.range = range
        self.step = step
        self.label = label
        self.minimumGlyph = minimumGlyph
        self.maximumGlyph = maximumGlyph
        self.valueText = valueText
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let minimumGlyph {
                DKIcon(minimumGlyph, size: 16).foregroundStyle(DK.Palette.muted)
            }
            track
            if let maximumGlyph {
                DKIcon(maximumGlyph, size: 16).foregroundStyle(DK.Palette.muted)
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(by: 1)
            case .decrement: adjust(by: -1)
            @unknown default: break
            }
        }
    }

    // MARK: Track

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = Self.fraction(of: value, in: range)
            let travel = max(0, width - DKSliderMetrics.knob)
            ZStack(alignment: .leading) {
                Capsule(style: .circular)
                    .fill(DK.Palette.track)
                    .frame(height: DKSliderMetrics.track)
                Capsule(style: .circular)
                    .fill(DK.Palette.accent)
                    .frame(width: DKSliderMetrics.knob / 2 + travel * fraction, height: DKSliderMetrics.track)
                Circle()
                    .fill(DK.Palette.window)
                    .overlay(Circle().strokeBorder(isFocused ? DK.Palette.accent : DK.Palette.lineStrong, lineWidth: DK.Metric.hairline))
                    .background(Circle().fill(DK.Palette.accentTint).padding(-3).opacity(isFocused ? 1 : 0))
                    .frame(width: DKSliderMetrics.knob, height: DKSliderMetrics.knob)
                    .offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        value = Self.value(atX: drag.location.x, width: width, range: range, step: step)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    },
            )
        }
        .frame(height: DKSliderMetrics.height)
        .frame(minWidth: 80)
        .focusable(isEnabled)
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .downArrow]) { _ in keyAdjust(by: -1) }
        .onKeyPress(keys: [.rightArrow, .upArrow]) { _ in keyAdjust(by: 1) }
        .onKeyPress(keys: [.pageDown]) { _ in keyAdjust(by: -5) }
        .onKeyPress(keys: [.pageUp]) { _ in keyAdjust(by: 5) }
        .onKeyPress(keys: [.home]) { _ in keyJump(to: range.lowerBound) }
        .onKeyPress(keys: [.end]) { _ in keyJump(to: range.upperBound) }
    }

    // MARK: Adjusting

    private var spokenValue: String {
        if let valueText {
            return valueText(value)
        }
        return Self.fraction(of: value, in: range).formatted(.percent.precision(.fractionLength(0)))
    }

    private func adjust(by steps: Double) {
        value = Self.stepped(value, by: steps, step: step, in: range)
    }

    private func keyAdjust(by steps: Double) -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        onEditingChanged(true)
        adjust(by: steps)
        onEditingChanged(false)
        return .handled
    }

    private func keyJump(to target: Double) -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        onEditingChanged(true)
        value = Self.clamped(target, in: range)
        onEditingChanged(false)
        return .handled
    }

    // MARK: Math

    /// How far along the range a value sits, 0...1; a degenerate range is 0.
    nonisolated static func fraction(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0, value.isFinite else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    nonisolated static func clamped(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    /// Snaps a value to the nearest step counted from the range's lower bound.
    nonisolated static func snapped(_ value: Double, step: Double?, in range: ClosedRange<Double>) -> Double {
        let value = clamped(value, in: range)
        guard let step, step > 0 else { return value }
        let snapped = range.lowerBound + ((value - range.lowerBound) / step).rounded() * step
        return clamped(snapped, in: range)
    }

    /// The value under a point on the track, where the knob's center travels
    /// from half a knob in to half a knob before the end.
    nonisolated static func value(atX x: CGFloat, width: CGFloat, range: ClosedRange<Double>, step: Double?) -> Double {
        let travel = max(1, width - DKSliderMetrics.knob)
        let fraction = min(1, max(0, (x - DKSliderMetrics.knob / 2) / travel))
        let raw = range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
        return snapped(raw, step: step, in: range)
    }

    /// A value moved by a number of steps; without a step, a twentieth of the range each.
    nonisolated static func stepped(_ value: Double, by steps: Double, step: Double?, in range: ClosedRange<Double>) -> Double {
        let increment = step ?? (range.upperBound - range.lowerBound) / 20
        return snapped(clamped(value, in: range) + steps * increment, step: step, in: range)
    }
}

enum DKSliderMetrics {
    static let track: CGFloat = 6
    static let knob: CGFloat = 18
    static let height: CGFloat = 22
}

// MARK: - Previews

#if DEBUG
private struct DKSliderPreview: View {
    @State private var media = 0.6
    @State private var ringer = 0.4

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DKSlider("Media volume", value: $media, step: 0.05, minimumGlyph: .speaker, maximumGlyph: .speakerLoud)
            DKSlider("Ringer volume", value: $ringer)
            DKSlider("Disabled", value: .constant(0.3), minimumGlyph: .speaker, maximumGlyph: .speakerLoud)
                .disabled(true)
        }
        .padding(20)
        .frame(width: 360)
        .background(DK.Palette.surfaceRaised)
    }
}

#Preview("Slider — light") {
    DKSliderPreview().preferredColorScheme(.light)
}

#Preview("Slider — dark") {
    DKSliderPreview().preferredColorScheme(.dark)
}
#endif
