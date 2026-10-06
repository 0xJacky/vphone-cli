import AppKit
import SwiftUI

// MARK: - Window Buttons

/// The three window buttons, for a window whose title bar is drawn by its
/// content and whose system buttons are hidden.
public enum DKWindowButton: String, Sendable, CaseIterable, Hashable {
    case close
    case minimize
    case zoom

    /// The button's name, looked up in `bundle`'s string catalog. DesignKit has
    /// no resources of its own; a missing key reads as the English name.
    public func title(bundle: Bundle) -> String {
        switch self {
        case .close: String(localized: "Close", bundle: bundle, comment: "Window button")
        case .minimize: String(localized: "Minimize", bundle: bundle, comment: "Window button")
        case .zoom: String(localized: "Full Screen", bundle: bundle, comment: "Window button")
        }
    }

    /// The symbol shown on the button while the pointer is over the group.
    /// Option turns the full screen arrows into the zoom plus.
    nonisolated static func symbolName(_ button: DKWindowButton, option: Bool) -> String {
        switch button {
        case .close: "xmark"
        case .minimize: "minus"
        case .zoom: option ? "plus" : "arrow.up.left.and.arrow.down.right"
        }
    }

    /// What a click on the zoom button does: full screen when the window can
    /// take it and Option is up, otherwise the standard zoom.
    nonisolated static func zoomTogglesFullScreen(option: Bool, behavior: NSWindow.CollectionBehavior, styleMask: NSWindow.StyleMask) -> Bool {
        guard !option, styleMask.contains(.resizable) else { return false }
        if behavior.contains(.fullScreenNone) || behavior.contains(.fullScreenAuxiliary) {
            return false
        }
        return true
    }

    /// Whether the window offers the button at all.
    nonisolated static func isAvailable(_ button: DKWindowButton, styleMask: NSWindow.StyleMask) -> Bool {
        switch button {
        case .close: styleMask.contains(.closable)
        case .minimize: styleMask.contains(.miniaturizable)
        case .zoom: styleMask.contains(.resizable)
        }
    }
}

// MARK: - Controls

/// Close, minimize and zoom, drawn and handled by the content: a window that
/// draws its own title bar hides the system buttons and puts these on it.
///
/// They follow the system buttons of macOS 26 and later: 14pt circles 9pt
/// apart, colored while the window is active and gray behind it, with their
/// symbols shown while the pointer is over any of them. Close and minimize go
/// through `performClose` and `performMiniaturize`, so the window's delegate
/// still decides; zoom enters full screen, or zooms with Option.
public struct DKWindowControls: View {
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dkLocalizationBundle) private var bundle
    @State private var window = DKWindowReference()
    @State private var isHovering = false
    @State private var isOptionDown = false
    @State private var pressed: DKWindowButton?

    public init() {}

    /// The width of the three buttons and the gaps between them.
    public static var width: CGFloat {
        DKWindowControlsMetrics.diameter * 3 + DKWindowControlsMetrics.gap * 2
    }

    public var body: some View {
        HStack(spacing: DKWindowControlsMetrics.gap) {
            ForEach(DKWindowButton.allCases, id: \.self) { button in
                light(button)
            }
        }
        .frame(width: Self.width, height: DKWindowControlsMetrics.diameter)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
                isOptionDown = NSEvent.modifierFlags.contains(.option)
            case .ended:
                isHovering = false
                isOptionDown = false
            }
        }
        .background(DKWindowReader(reference: window))
        .accessibilityElement(children: .contain)
    }

    private func light(_ button: DKWindowButton) -> some View {
        let showsColor = appearsActive || isHovering
        let dark = colorScheme == .dark
        return ZStack {
            Circle()
                .fill(showsColor ? DKWindowControlsPalette.fill(button) : DKWindowControlsPalette.inactive(dark: dark))
            Circle()
                .strokeBorder(showsColor ? DKWindowControlsPalette.rim(button) : DKWindowControlsPalette.inactiveRim(dark: dark), lineWidth: 0.5)
            if pressed == button {
                Circle().fill(DKWindowControlsPalette.pressed)
            }
            if isHovering {
                Image(systemName: DKWindowButton.symbolName(button, option: isOptionDown))
                    .font(.system(size: button == .zoom && !isOptionDown ? 6.5 : 8, weight: .bold))
                    .foregroundStyle(DKWindowControlsPalette.glyph(button))
            }
        }
        .frame(width: DKWindowControlsMetrics.diameter, height: DKWindowControlsMetrics.diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = button }
                .onEnded { drag in
                    pressed = nil
                    let inside = CGRect(origin: .zero, size: CGSize(width: DKWindowControlsMetrics.diameter, height: DKWindowControlsMetrics.diameter))
                        .insetBy(dx: -4, dy: -4)
                        .contains(drag.location)
                    if inside {
                        perform(button)
                    }
                },
        )
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(button.title(bundle: bundle))
        .accessibilityAction { perform(button) }
    }

    private func perform(_ button: DKWindowButton) {
        guard let window = window.window, DKWindowButton.isAvailable(button, styleMask: window.styleMask) else {
            NSSound.beep()
            return
        }
        switch button {
        case .close:
            window.performClose(nil)
        case .minimize:
            window.performMiniaturize(nil)
        case .zoom:
            let option = NSEvent.modifierFlags.contains(.option)
            if DKWindowButton.zoomTogglesFullScreen(option: option, behavior: window.collectionBehavior, styleMask: window.styleMask) {
                window.toggleFullScreen(nil)
            } else {
                window.performZoom(nil)
            }
        }
    }
}

enum DKWindowControlsMetrics {
    static let diameter: CGFloat = 14
    static let gap: CGFloat = 9
}

/// The system buttons' colors. They are the same in both appearances except
/// for the gray an inactive window shows.
enum DKWindowControlsPalette {
    static let close = DK.Palette.dynamic(0xFF5F57, 0xFF5F57)
    static let closeRim = DK.Palette.dynamic(0xE2463F, 0xE2463F)
    static let closeGlyph = DK.Palette.dynamic(0x4D0000, 0x4D0000)
    static let minimize = DK.Palette.dynamic(0xFEBC2E, 0xFEBC2E)
    static let minimizeRim = DK.Palette.dynamic(0xE1A116, 0xE1A116)
    static let minimizeGlyph = DK.Palette.dynamic(0x995700, 0x995700)
    static let zoom = DK.Palette.dynamic(0x28C840, 0x28C840)
    static let zoomRim = DK.Palette.dynamic(0x12AC28, 0x12AC28)
    static let zoomGlyph = DK.Palette.dynamic(0x006500, 0x006500)
    static let inactiveLight = DK.Palette.dynamic(0xD1D1D3, 0xD1D1D3)
    static let inactiveRimLight = DK.Palette.dynamic(0xBDBDBF, 0xBDBDBF)
    static let inactiveDark = DK.Palette.dynamic(0x505052, 0x505052)
    static let inactiveRimDark = DK.Palette.dynamic(0x47474A, 0x47474A)
    static let pressed = DK.Palette.dynamic(0x000000, 0x000000, lightAlpha: 0.22, darkAlpha: 0.22)

    static func fill(_ button: DKWindowButton) -> Color {
        switch button {
        case .close: close
        case .minimize: minimize
        case .zoom: zoom
        }
    }

    static func rim(_ button: DKWindowButton) -> Color {
        switch button {
        case .close: closeRim
        case .minimize: minimizeRim
        case .zoom: zoomRim
        }
    }

    static func glyph(_ button: DKWindowButton) -> Color {
        switch button {
        case .close: closeGlyph
        case .minimize: minimizeGlyph
        case .zoom: zoomGlyph
        }
    }

    static func inactive(dark: Bool) -> Color {
        dark ? inactiveDark : inactiveLight
    }

    static func inactiveRim(dark: Bool) -> Color {
        dark ? inactiveRimDark : inactiveRimLight
    }
}

// MARK: - Window Reference

/// The window a SwiftUI view is in, read from an AppKit view placed behind it.
@MainActor
final class DKWindowReference {
    weak var window: NSWindow?
}

private struct DKWindowReader: NSViewRepresentable {
    let reference: DKWindowReference

    func makeNSView(context _: Context) -> DKWindowReaderView {
        let view = DKWindowReaderView()
        view.reference = reference
        return view
    }

    func updateNSView(_ view: DKWindowReaderView, context _: Context) {
        view.reference = reference
        reference.window = view.window
    }
}

private final class DKWindowReaderView: NSView {
    var reference: DKWindowReference?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reference?.window = window
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

// MARK: - Localization

public extension EnvironmentValues {
    /// The bundle whose string catalog holds DesignKit's own labels, such as
    /// the window buttons' names. The VM passes its localization bundle.
    @Entry var dkLocalizationBundle: Bundle = .main
}

// MARK: - Previews

#if DEBUG
#Preview("Window controls") {
    VStack(spacing: 16) {
        DKWindowControls()
        DKWindowControls().environment(\.appearsActive, false)
    }
    .padding(20)
}
#endif
