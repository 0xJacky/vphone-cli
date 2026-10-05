import SwiftUI

/// The status vocabulary every component shares: a dot, a badge, a banner and a
/// table cell all mean the same thing by `.warning`.
public enum DKTone: String, Sendable, CaseIterable, Hashable {
    case neutral
    case idle
    case success
    case warning
    case danger
    case info
    case accent

    /// Strong color: dots, icons, bars.
    public var color: Color {
        switch self {
        case .neutral: DK.Palette.inkSecondary
        case .idle: DK.Palette.dotIdle
        case .success: DK.Palette.success
        case .warning: DK.Palette.warning
        case .danger: DK.Palette.danger
        case .info: DK.Palette.link
        case .accent: DK.Palette.accent
        }
    }

    /// Text on the tone's surface, and text that carries the tone on a plain ground.
    public var ink: Color {
        switch self {
        case .neutral: DK.Palette.inkSecondary
        case .idle: DK.Palette.muted
        case .success: DK.Palette.successInk
        case .warning: DK.Palette.warningInk
        case .danger: DK.Palette.danger
        case .info: DK.Palette.link
        case .accent: DK.Palette.onAccent
        }
    }

    /// The tinted fill behind badges, banners and highlighted rows.
    public var surface: Color {
        switch self {
        case .neutral, .idle: DK.Palette.surfaceSunken
        case .success: DK.Palette.successSurface
        case .warning: DK.Palette.warningSurface
        case .danger: DK.Palette.dangerSurface
        case .info: DK.Palette.accentTint
        case .accent: DK.Palette.accent
        }
    }

    /// The border of a tinted container.
    public var line: Color {
        switch self {
        case .neutral, .idle: DK.Palette.line
        case .success: DK.Palette.success.opacity(0.35)
        case .warning: DK.Palette.warningLine
        case .danger: DK.Palette.dangerLine
        case .info, .accent: DK.Palette.accentSoft
        }
    }
}
