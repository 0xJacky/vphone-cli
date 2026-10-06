import SwiftUI

/// What a button looks like. `primary` is the one default action of a view;
/// `danger` is destructive; `plain` reads as a link; `ghost` sits in toolbars and
/// title bars; `ghostOn` is a ghost toggle that is on; `recording` is the live
/// recording timer.
public enum DKButtonVariant: String, Sendable, CaseIterable, Hashable {
    case secondary, primary, danger, plain, ghost, ghostOn, pressed, recording
}

/// How big a button is. `icon` and `largeIcon` are square and show only the
/// glyph (the label becomes the accessibility label and tooltip); `tile` is the
/// 64pt hardware-button tile with the glyph above the label.
public enum DKButtonSize: String, Sendable, CaseIterable, Hashable {
    case regular, small, icon, largeIcon, tile
}

/// A button described as data, for components that take a list of actions
/// (headers, detail bars, sheets, control bars).
public struct DKButtonSpec: Identifiable {
    public var id: String
    public var label: String
    public var glyph: DKGlyph?
    public var variant: DKButtonVariant
    public var size: DKButtonSize
    public var isEnabled: Bool
    public var help: String?
    public var action: () -> Void

    public init(
        _ label: String,
        glyph: DKGlyph? = nil,
        variant: DKButtonVariant = .secondary,
        size: DKButtonSize = .regular,
        isEnabled: Bool = true,
        help: String? = nil,
        id: String? = nil,
        action: @escaping () -> Void = {},
    ) {
        self.id = id ?? label
        self.label = label
        self.glyph = glyph
        self.variant = variant
        self.size = size
        self.isEnabled = isEnabled
        self.help = help
        self.action = action
    }
}

/// The DesignKit button: a pill with an optional leading glyph.
public struct DKButton: View {
    let spec: DKButtonSpec

    public init(_ spec: DKButtonSpec) {
        self.spec = spec
    }

    public init(
        _ label: String,
        glyph: DKGlyph? = nil,
        variant: DKButtonVariant = .secondary,
        size: DKButtonSize = .regular,
        action: @escaping () -> Void,
    ) {
        spec = DKButtonSpec(label, glyph: glyph, variant: variant, size: size, action: action)
    }

    public var body: some View {
        Button(action: spec.action) {
            content
        }
        .buttonStyle(DKButtonStyle(variant: spec.variant, size: spec.size))
        .disabled(!spec.isEnabled)
        .help(spec.help ?? (isIconOnly ? spec.label : ""))
        .accessibilityLabel(spec.label)
    }

    private var isIconOnly: Bool {
        spec.size == .icon || spec.size == .largeIcon
    }

    @ViewBuilder
    private var content: some View {
        switch spec.size {
        case .icon, .largeIcon:
            DKIcon(spec.glyph ?? .ellipsis, size: spec.size == .largeIcon ? 20 : 15)
        case .tile:
            VStack(spacing: 6) {
                if let glyph = spec.glyph {
                    DKIcon(glyph, size: 18).foregroundStyle(DK.Palette.accent)
                }
                Text(spec.label).font(DK.Typeface.caption).lineLimit(1)
            }
        case .regular, .small:
            HStack(spacing: 6) {
                if let glyph = spec.glyph {
                    DKIcon(glyph, size: 14)
                }
                Text(spec.label).lineLimit(1)
            }
        }
    }
}

/// A pill, or the rounded square of a tile. A capsule rather than a huge corner
/// radius, which leaves flat spots at the ends of a stroked pill.
struct DKButtonShape: InsettableShape {
    var isTile: Bool
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        return isTile
            ? RoundedRectangle(cornerRadius: max(0, DK.Radius.control - inset), style: .continuous).path(in: r)
            : Capsule(style: .circular).path(in: r)
    }

    func inset(by amount: CGFloat) -> DKButtonShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

/// The style behind `DKButton`; usable on any `Button` that wants the look.
public struct DKButtonStyle: ButtonStyle {
    public var variant: DKButtonVariant
    public var size: DKButtonSize
    /// Draws the pressed look while true, as a menu button does while its menu is open.
    var isHighlighted = false

    @Environment(\.isEnabled) private var isEnabled

    public init(variant: DKButtonVariant = .secondary, size: DKButtonSize = .regular) {
        self.variant = variant
        self.size = size
    }

    init(variant: DKButtonVariant, size: DKButtonSize, isHighlighted: Bool) {
        self.variant = variant
        self.size = size
        self.isHighlighted = isHighlighted
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = DKButtonShape(isTile: size == .tile)
        configuration.label
            .font(font)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(width: fixedWidth, height: height)
            .frame(maxWidth: size == .tile ? .infinity : nil)
            .background(shape.fill(background(pressed: configuration.isPressed || isHighlighted)))
            .overlay(shape.strokeBorder(border, lineWidth: border == .clear ? 0 : 1))
            .contentShape(shape)
    }

    // MARK: Geometry

    private var height: CGFloat? {
        if variant == .plain, size == .regular || size == .small {
            return nil
        }
        return switch size {
        case .regular, .icon: DK.Metric.controlHeight
        case .small: 28
        case .largeIcon: 40
        case .tile: 64
        }
    }

    private var fixedWidth: CGFloat? {
        switch size {
        case .icon: DK.Metric.controlHeight
        case .largeIcon: 40
        default: nil
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .icon, .largeIcon: 0
        case .tile: 8
        default: variant == .plain ? 2 : DK.Space.s3
        }
    }

    private var font: Font {
        switch variant {
        case .primary: .system(size: 13, weight: .medium)
        case .recording: .system(size: 12, design: .monospaced)
        default: .system(size: 13)
        }
    }

    // MARK: Color

    private var foreground: Color {
        guard isEnabled else {
            return DK.Palette.inkDisabled
        }
        switch variant {
        case .primary: return DK.Palette.onAccent
        case .danger, .recording: return DK.Palette.danger
        case .plain: return DK.Palette.link
        case .ghost: return DK.Palette.muted
        case .ghostOn: return DK.Palette.accent
        case .secondary, .pressed: return DK.Palette.ink
        }
    }

    /// A disabled button drops its variant's look: bordered and filled
    /// variants become a flat gray well with no border, so a disabled Remove
    /// shows no red and a disabled primary no accent; borderless ones only
    /// gray their text. Every variant then reads as unavailable the same way.
    nonisolated static func disabledShowsWell(_ variant: DKButtonVariant) -> Bool {
        switch variant {
        case .secondary, .primary, .danger, .pressed, .recording: true
        case .ghost, .ghostOn, .plain: false
        }
    }

    private func background(pressed: Bool) -> Color {
        guard isEnabled else {
            return Self.disabledShowsWell(variant) ? DK.Palette.surfaceSunken : .clear
        }
        switch variant {
        case .primary:
            return pressed ? DK.Palette.accentPressed : DK.Palette.accent
        case .recording:
            return DK.Palette.dangerSurface
        case .ghost:
            return pressed ? DK.Palette.selectionNeutral : .clear
        case .ghostOn:
            return DK.Palette.accentTint
        case .plain:
            return .clear
        case .pressed:
            return DK.Palette.surfaceSunken
        case .secondary, .danger:
            return pressed ? DK.Palette.surfaceSunken : DK.Palette.window
        }
    }

    private var border: Color {
        guard isEnabled else { return .clear }
        return switch variant {
        case .primary, .ghost, .ghostOn, .plain: .clear
        case .danger, .recording: DK.Palette.dangerLine
        case .secondary, .pressed: DK.Palette.lineStrong
        }
    }
}
