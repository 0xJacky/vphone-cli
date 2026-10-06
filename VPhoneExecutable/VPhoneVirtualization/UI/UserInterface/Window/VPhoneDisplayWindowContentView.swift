import AppKit
import SwiftUI
import VPhoneCoreKit
import VPhoneDesignKit

// MARK: - Display Window Content

/// The display window's content view: the title bar, the guest display
/// edge to edge between the bars, and the control bar. A margin of display
/// ground around the guest would read as a black frame round the screen. The window uses a full-size content view, so the title bar sits under
/// the transparent system title bar, whose buttons are hidden; the title bar
/// draws its own.
///
/// The bars have fixed heights, measured once. Everything else goes to the
/// display, which `VPhoneDisplayContainerView` fits at the panel's aspect
/// ratio; the window controller sizes the window so that it fits exactly.
final class VPhoneDisplayWindowContentView: NSView {
    let display: VPhoneDisplayContainerView
    private let titleBar: NSView
    private let controlBar: NSView
    let titleBarHeight: CGFloat
    let controlBarHeight: CGFloat

    init(display: VPhoneDisplayContainerView, chrome: VPhoneDisplayChromeModel) {
        self.display = display
        let titleBar = VPhoneChromeHostingView(rootView: VPhoneDisplayTitleBar(model: chrome))
        let controlBar = VPhoneChromeHostingView(rootView: VPhoneDisplayControlBar(model: chrome))
        self.titleBar = titleBar
        self.controlBar = controlBar
        titleBarHeight = ceil(titleBar.fittingSize.height)
        controlBarHeight = ceil(controlBar.fittingSize.height)
        titleBar.sizingOptions = []
        controlBar.sizingOptions = []
        // The bars sit at the window's edges by design, so the title bar
        // safe area must not push the title bar's content down.
        titleBar.safeAreaRegions = []
        controlBar.safeAreaRegions = []
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        for view in [display, titleBar, controlBar] as [NSView] {
            view.autoresizingMask = []
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The room around the guest display: the bars above and below it.
    var chromeInsets: NSEdgeInsets {
        NSEdgeInsets(top: titleBarHeight, left: 0, bottom: controlBarHeight, right: 0)
    }

    override func layout() {
        super.layout()
        let insets = chromeInsets
        titleBar.frame = NSRect(x: 0, y: bounds.maxY - titleBarHeight, width: bounds.width, height: titleBarHeight)
        controlBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: controlBarHeight)
        display.frame = NSRect(
            x: insets.left,
            y: insets.bottom,
            width: max(0, bounds.width - insets.left - insets.right),
            height: max(0, bounds.height - insets.top - insets.bottom),
        )
    }
}

// MARK: - Geometry

extension NSRect {
    /// This rect with `insets` taken off each side.
    func inset(by insets: NSEdgeInsets) -> NSRect {
        NSRect(
            x: minX + insets.left,
            y: minY + insets.bottom,
            width: width - insets.left - insets.right,
            height: height - insets.top - insets.bottom,
        )
    }

    /// This rect with `insets` added to each side: the inverse of `inset(by:)`.
    func outset(by insets: NSEdgeInsets) -> NSRect {
        NSRect(
            x: minX - insets.left,
            y: minY - insets.bottom,
            width: width + insets.left + insets.right,
            height: height + insets.top + insets.bottom,
        )
    }
}

// MARK: - Hosting View

/// Hosts a bar without taking first responder from the VM view, so a click
/// on a bar button leaves the keyboard with the guest.
private final class VPhoneChromeHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool {
        false
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}
