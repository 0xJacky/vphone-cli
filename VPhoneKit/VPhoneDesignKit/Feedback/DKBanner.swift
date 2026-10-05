import SwiftUI

// MARK: - Tone

/// What a banner is about. `warning` asks for attention, `danger` reports
/// something that failed or will fail, `info` is a neutral note.
public enum DKBannerTone: String, Sendable, CaseIterable, Hashable {
    case warning, danger, info

    /// The shared tone the banner's colors come from.
    public var tone: DKTone {
        switch self {
        case .warning: .warning
        case .danger: .danger
        case .info: .info
        }
    }

    /// The leading glyph: the warning triangle, or the info circle for notes.
    public var glyph: DKGlyph {
        self == .info ? .info : .warning
    }

    /// What VoiceOver says before the banner's text.
    public var accessibilityName: String {
        switch self {
        case .warning: "Warning"
        case .danger: "Error"
        case .info: "Note"
        }
    }

    var surface: Color {
        switch self {
        case .warning: DK.Palette.warningSurface
        case .danger: DK.Palette.dangerSurface
        case .info: DK.Palette.accentTint
        }
    }

    var line: Color {
        switch self {
        case .warning: DK.Palette.warningLine
        case .danger: DK.Palette.dangerLine
        case .info: DK.Palette.line
        }
    }

    var ink: Color {
        switch self {
        case .warning: DK.Palette.warningInk
        case .danger: DK.Palette.danger
        case .info: DK.Palette.ink
        }
    }

    var iconColor: Color {
        switch self {
        case .warning: DK.Palette.warning
        case .danger: DK.Palette.danger
        case .info: DK.Palette.ink
        }
    }
}

// MARK: - Banner

/// An inline banner: a tinted card with a leading glyph, a sentence, and an
/// optional action button under the sentence.
///
///     DKBanner(
///         "41 GB free on Macintosh HD. A new machine's 64 GB disk may not fit.",
///         actionLabel: "Review Disks"
///     ) { openDisks() }
public struct DKBanner: View {
    public let text: String
    public var tone: DKBannerTone
    public var action: DKButtonSpec?

    /// A banner whose action is described by a full button spec.
    public init(_ text: String, tone: DKBannerTone = .warning, action: DKButtonSpec? = nil) {
        self.text = text
        self.tone = tone
        self.action = action
    }

    /// A banner with one small secondary action button.
    public init(
        _ text: String,
        tone: DKBannerTone = .warning,
        actionLabel: String,
        action: @escaping () -> Void,
    ) {
        self.init(text, tone: tone, action: DKButtonSpec(actionLabel, size: .small, action: action))
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
        HStack(alignment: .top, spacing: 10) {
            DKIcon(tone.glyph, size: 18)
                .foregroundStyle(tone.iconColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: DK.Space.s2) {
                Text(text)
                    .font(DK.Typeface.body)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(tone.ink)
                if let action {
                    DKButton(action)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DK.Space.s3)
        .padding(.horizontal, 14)
        .background(shape.fill(tone.surface))
        .overlay(shape.strokeBorder(tone.line, lineWidth: DK.Metric.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tone.accessibilityName)
    }
}

// MARK: - Previews

private struct DKBannerPreviewBoard: View {
    var body: some View {
        VStack(spacing: DK.Space.s3) {
            DKBanner(
                "The host programs and the guest environment come from different Core Bundles. Update the guest environment to match.",
                actionLabel: "Update Guest Environment",
            ) {}
            DKBanner("The restore failed: the device did not enter DFU within 60 seconds.", tone: .danger, actionLabel: "Open Log") {}
            DKBanner("Changes apply the next time research-26 starts.", tone: .info)
        }
        .padding(DK.Space.s4)
        .frame(width: 520)
        .background(DK.Palette.window)
    }
}

#Preview("Banner – Light") {
    DKBannerPreviewBoard().preferredColorScheme(.light)
}

#Preview("Banner – Dark") {
    DKBannerPreviewBoard().preferredColorScheme(.dark)
}
