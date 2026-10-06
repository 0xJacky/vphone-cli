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

/// Close, minimize and zoom, drawn and handled by the content, for a window
/// that draws its own chrome.
///
/// Placing them in a window takes the buttons over: the window's system
/// buttons are hidden while these are in it. In full screen the system
/// buttons come back, since they show with the menu bar there, and these
/// take no room; they return when the window leaves full screen.
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
    @State private var reference = DKWindowReference()
    @State private var isHovering = false
    @State private var isOptionDown = false
    @State private var pressed: DKWindowButton?

    public init() {}

    /// The width of the three buttons and the gaps between them.
    public static var width: CGFloat {
        DKWindowControlsMetrics.diameter * 3 + DKWindowControlsMetrics.gap * 2
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            DKWindowReader(reference: reference)
                .frame(width: 0, height: 0)
            if !reference.isFullScreen {
                lights
            }
        }
    }

    private var lights: some View {
        HStack(spacing: DKWindowControlsMetrics.gap) {
            ForEach(DKWindowButton.allCases, id: \.self) { button in
                light(button)
            }
        }
        .frame(width: Self.width, height: DKWindowControlsMetrics.diameter)
        .contentShape(Rectangle())
        // Like the system buttons, these work in a window behind others: the
        // click that brings the window forward also closes or minimizes it.
        .allowsWindowActivationEvents(true)
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
        guard let window = reference.window, DKWindowButton.isAvailable(button, styleMask: window.styleMask) else {
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

/// The window the controls are in. Setting it hides that window's system
/// buttons, and follows the window in and out of full screen; letting go of
/// it shows them again.
@MainActor
@Observable
final class DKWindowReference {
    private(set) var isFullScreen = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored weak var window: NSWindow? {
        didSet {
            guard window !== oldValue else { return }
            release(oldValue)
            adopt(window)
        }
    }

    private func adopt(_ window: NSWindow?) {
        guard let window else { return }
        let fullScreen = window.styleMask.contains(.fullScreen)
        if isFullScreen != fullScreen {
            isFullScreen = fullScreen
        }
        Self.setSystemButtons(hidden: !isFullScreen, in: window)
        let center = NotificationCenter.default
        let entering: (Notification) -> Void = { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = note.object as? NSWindow, window === self.window else { return }
                self.isFullScreen = true
                Self.setSystemButtons(hidden: false, in: window)
            }
        }
        let leaving: (Notification) -> Void = { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = note.object as? NSWindow, window === self.window else { return }
                self.isFullScreen = false
                Self.setSystemButtons(hidden: true, in: window)
            }
        }
        let resync: (Notification) -> Void = { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = note.object as? NSWindow, window === self.window,
                      !window.styleMask.contains(.fullScreen), self.isFullScreen,
                      !window.inLiveResize
                else { return }
                leaving(note)
            }
        }
        observers = [
            center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main, using: entering),
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main, using: leaving),
            // A failed entry posts no notification of its own; the next resize
            // or key change puts the state back from the style mask.
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: resync),
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main, using: resync),
        ]
    }

    private func release(_ window: NSWindow?) {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        if let window {
            Self.setSystemButtons(hidden: false, in: window)
        }
    }

    static func setSystemButtons(hidden: Bool, in window: NSWindow) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = hidden
        }
    }
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
    }

    static func dismantleNSView(_ view: DKWindowReaderView, coordinator _: ()) {
        view.reference?.window = nil
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

// MARK: - Window Style

public extension View {
    /// Gives the window this view is in a content-drawn title bar: the title
    /// hidden, the system title bar transparent with no separator, and the
    /// content running under it. Put `DKWindowControls` (through `DKTitleBar`
    /// or a sidebar's `windowControls`) where the buttons go.
    func dkWindowChrome() -> some View {
        background(DKWindowStyler().frame(width: 0, height: 0))
    }
}

private struct DKWindowStyler: NSViewRepresentable {
    func makeNSView(context _: Context) -> DKWindowStylerView {
        DKWindowStylerView()
    }

    func updateNSView(_ view: DKWindowStylerView, context _: Context) {
        view.applyStyle()
    }
}

private final class DKWindowStylerView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyStyle()
    }

    func applyStyle() {
        guard let window else { return }
        DKWindowChromeStyle.apply(to: window)
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

/// The window settings a content-drawn title bar needs. AppKit windows made
/// in code call `apply(to:)` directly; SwiftUI scenes use `dkWindowChrome()`.
@MainActor
public enum DKWindowChromeStyle {
    public static func apply(to window: NSWindow) {
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
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
