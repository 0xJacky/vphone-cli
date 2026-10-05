import SwiftUI

/// The DesignKit progress bar: a rounded track with a tinted fill. `thin` is the
/// 4pt bar under a table cell or a step; the regular bar is 6pt. A bar made with
/// `indeterminate` slides a short fill back and forth until work can be measured.
/// The bar stretches to the width it is offered, down to 40pt.
public struct DKProgress: View {
    /// The fraction done, already clamped to 0...1; nil when indeterminate.
    public let value: Double?
    public var tone: DKTone
    public var thin: Bool
    public var label: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - value: The fraction done. Values outside 0...1, and NaN, are clamped.
    ///   - tone: The fill color. `.neutral` and `.idle` draw the muted fill.
    ///   - thin: The 4pt bar instead of the 6pt one.
    ///   - label: What VoiceOver calls the bar ("Restore", "Downloading").
    public init(value: Double, tone: DKTone = .accent, thin: Bool = false, label: String? = nil) {
        self.value = Self.clamped(value)
        self.tone = tone
        self.thin = thin
        self.label = label
    }

    private init(indeterminateTone tone: DKTone, thin: Bool, label: String?) {
        value = nil
        self.tone = tone
        self.thin = thin
        self.label = label
    }

    /// A bar for work whose size is not known yet.
    public static func indeterminate(tone: DKTone = .accent, thin: Bool = false, label: String? = nil) -> DKProgress {
        DKProgress(indeterminateTone: tone, thin: thin, label: label)
    }

    public var body: some View {
        let height = Self.height(thin: thin)
        let shape = Capsule(style: .circular)
        shape
            .fill(DK.Palette.track)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    fill(width: proxy.size.width)
                }
            }
            .clipShape(shape)
            .frame(minWidth: Self.minimumWidth, maxWidth: .infinity)
            .frame(height: height)
            .accessibilityRepresentation {
                if let value {
                    ProgressView(label ?? "Progress", value: value)
                } else {
                    ProgressView(label ?? "Progress")
                }
            }
    }

    @ViewBuilder
    private func fill(width: CGFloat) -> some View {
        if let value {
            Rectangle()
                .fill(Self.fillColor(for: tone))
                .frame(width: width * value)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: value)
        } else {
            // The sliding segment runs on Core Animation (see DKMotion.swift): a
            // SwiftUI `repeatForever` would redraw the whole window every frame
            // for as long as the bar is on screen.
            let segment = width * Self.indeterminateFraction
            DKMotionShape(
                color: Self.fillColor(for: tone),
                content: .fill(cornerRadius: nil, size: CGSize(width: segment, height: Self.height(thin: thin))),
                motion: reduceMotion ? nil : Self.indeterminateMotion(width: width),
            )
        }
    }

    /// The indeterminate segment's slide from the leading edge to the trailing
    /// one and back.
    static func indeterminateMotion(width: CGFloat) -> DKMotion {
        let travel = max(0, width - width * indeterminateFraction)
        return DKMotion(translationX: DKMotionRamp(from: 0, to: travel), duration: 0.9, autoreverses: true, timing: .easeInEaseOut)
    }

    // MARK: - Geometry and color

    static let minimumWidth: CGFloat = 40
    /// How much of the track the indeterminate fill covers.
    static let indeterminateFraction: CGFloat = 0.3

    static func height(thin: Bool) -> CGFloat {
        thin ? 4 : 6
    }

    /// Clamps to 0...1; NaN counts as no progress.
    static func clamped(_ value: Double) -> Double {
        guard !value.isNaN else {
            return 0
        }
        return min(max(value, 0), 1)
    }

    /// The fill for a tone. The design's muted fill stands for `.neutral` and `.idle`.
    static func fillColor(for tone: DKTone) -> Color {
        switch tone {
        case .neutral, .idle: DK.Palette.inkDisabled
        default: tone.color
        }
    }
}

// MARK: - Previews

private struct DKProgressPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s3) {
            DKProgress(value: 0.42, label: "Restore")
            DKProgress(value: 0.63, tone: .warning, thin: true, label: "Downloading")
            DKProgress(value: 1, tone: .success, label: "Done")
            DKProgress(value: 0.3, tone: .neutral, label: "Paused")
            DKProgress.indeterminate(label: "Preparing")
            DKProgress.indeterminate(tone: .warning, thin: true, label: "Waiting")
        }
        .padding(DK.Space.s4)
        .frame(width: 300)
        .background(DK.Palette.window)
    }
}

#Preview("Progress, light") {
    DKProgressPreview().preferredColorScheme(.light)
}

#Preview("Progress, dark") {
    DKProgressPreview().preferredColorScheme(.dark)
}
