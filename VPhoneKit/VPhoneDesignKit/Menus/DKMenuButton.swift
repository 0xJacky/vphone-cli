import AppKit
import SwiftUI

/// A button that opens a menu: a `DKButton` in any variant and size, with a
/// small chevron after its label, whose menu is a real `NSMenu` built from
/// `DKMenuItem`s. The menu opens on mouse-down under the button, as a pull-down
/// button's does, and can be chosen from in the same press; the whole button is
/// the hit area. Keyboard and VoiceOver activation open it too.
///
/// The items are built when the menu opens, so checkmarks and enabled states
/// are read then.
///
/// ```swift
/// DKMenuButton("Signal", glyph: .bolt) {
///     DKMenuItem("Terminate (SIGTERM)") { send(.term) }
///     DKMenuItem("Kill (SIGKILL)") { send(.kill) }.destructive()
/// }
/// ```
public struct DKMenuButton: View {
    let spec: DKButtonSpec
    let showsIndicator: Bool
    let items: @MainActor () -> [DKMenuItem]

    @State private var isOpen = false
    @State private var anchor = DKMenuButtonAnchorHandle()

    /// - Parameters:
    ///   - showsIndicator: Draws the chevron after the label. Icon-only sizes never do.
    ///   - items: The menu's rows, built each time it opens.
    public init(
        _ label: String,
        glyph: DKGlyph? = nil,
        variant: DKButtonVariant = .secondary,
        size: DKButtonSize = .regular,
        isEnabled: Bool = true,
        help: String? = nil,
        showsIndicator: Bool = true,
        @DKMenuBuilder items: @escaping @MainActor () -> [DKMenuItem],
    ) {
        spec = DKButtonSpec(label, glyph: glyph, variant: variant, size: size, isEnabled: isEnabled, help: help)
        self.showsIndicator = showsIndicator
        self.items = items
    }

    /// A menu button drawn from a button spec; the spec's action is not used.
    public init(_ spec: DKButtonSpec, showsIndicator: Bool = true, @DKMenuBuilder items: @escaping @MainActor () -> [DKMenuItem]) {
        self.spec = spec
        self.showsIndicator = showsIndicator
        self.items = items
    }

    /// A menu button with a fixed list of rows.
    public init(_ spec: DKButtonSpec, showsIndicator: Bool = true, items: [DKMenuItem]) {
        self.spec = spec
        self.showsIndicator = showsIndicator
        self.items = { items }
    }

    public var body: some View {
        Button(action: open) {
            label
        }
        .buttonStyle(DKButtonStyle(variant: spec.variant, size: spec.size, isHighlighted: isOpen))
        .overlay {
            DKMenuButtonAnchor(handle: anchor, isEnabled: spec.isEnabled, onMouseDown: open)
        }
        .disabled(!spec.isEnabled)
        .help(spec.help ?? (isIconOnly ? spec.label : ""))
        .accessibilityLabel(spec.label)
        .accessibilityHint(String(localized: "Opens a menu", bundle: .main, comment: "VoiceOver hint for a button that opens a menu"))
    }

    private var isIconOnly: Bool {
        spec.size == .icon || spec.size == .largeIcon
    }

    @ViewBuilder
    private var label: some View {
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
                if showsIndicator {
                    Image(systemName: DKGlyph.chevronDown.symbolName)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.leading, -1)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func open() {
        guard spec.isEnabled, !isOpen else {
            return
        }
        let menu = Self.makeMenu(items(), title: spec.label)
        isOpen = true
        if let view = anchor.view, view.window != nil {
            // Under the button, its leading edge on the button's; the anchor
            // view is flipped, so y grows downward.
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        isOpen = false
    }

    /// The menu the button opens.
    static func makeMenu(_ items: [DKMenuItem], title: String) -> NSMenu {
        items.makeNSMenu(title: title)
    }
}

// MARK: - Anchor

@MainActor
final class DKMenuButtonAnchorHandle {
    weak var view: DKMenuButtonAnchorView?
}

/// The transparent view over a menu button: it positions the menu and takes the
/// mouse-down, so the menu opens on press rather than on release.
final class DKMenuButtonAnchorView: NSView {
    var isEnabled = true
    var onMouseDown: (() -> Void)?

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isEnabled ? super.hitTest(point) : nil
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with _: NSEvent) {
        onMouseDown?()
    }
}

private struct DKMenuButtonAnchor: NSViewRepresentable {
    let handle: DKMenuButtonAnchorHandle
    let isEnabled: Bool
    let onMouseDown: () -> Void

    func makeNSView(context _: Context) -> DKMenuButtonAnchorView {
        let view = DKMenuButtonAnchorView()
        handle.view = view
        return view
    }

    func updateNSView(_ view: DKMenuButtonAnchorView, context _: Context) {
        handle.view = view
        view.isEnabled = isEnabled
        view.onMouseDown = onMouseDown
    }
}

// MARK: - Previews

private struct DKMenuButtonPreview: View {
    @State private var autoRefresh = true

    var body: some View {
        HStack(spacing: DK.Space.s2) {
            DKMenuButton("Signal", glyph: .bolt) {
                DKMenuItem("Terminate (SIGTERM)") {}
                DKMenuItem("Kill (SIGKILL)") {}.destructive()
            }
            DKMenuButton("More Actions", glyph: .ellipsis, size: .icon) {
                DKMenuItem("Auto Refresh") { autoRefresh.toggle() }.checked(autoRefresh)
                DKMenuItem.separator
                DKMenuItem("Copy Path", glyph: .copy) {}
            }
            DKMenuButton("New", glyph: .plus, variant: .primary) {
                DKMenuItem("Machine…") {}
                DKMenuItem("Disk…") {}
            }
            DKMenuButton("Disabled", isEnabled: false) {
                DKMenuItem("Never") {}
            }
        }
        .padding(DK.Space.s4)
        .background(DK.Palette.window)
    }
}

#Preview("Menu button, light") {
    DKMenuButtonPreview().preferredColorScheme(.light)
}

#Preview("Menu button, dark") {
    DKMenuButtonPreview().preferredColorScheme(.dark)
}
