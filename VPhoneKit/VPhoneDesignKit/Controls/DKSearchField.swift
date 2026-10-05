import AppKit
import SwiftUI

/// The DesignKit search field (`.dk-search`): a pill around a real
/// `NSSearchField`, with its magnifying glass, its placeholder (also the
/// accessibility label) and its clear button. Escape clears the text, as in any
/// native search field. Pass `width: nil` to let the field take the width it is
/// offered.
///
/// Because the field is an `NSSearchField`, AppKit code finds it: a window
/// controller's Find command can walk the view tree for the first
/// `NSSearchField` and make it first responder. From SwiftUI, bind `isFocused`
/// to read and move the focus; setting it to true focuses the field once it is
/// in a window. The whole pill is clickable, not only the text.
public struct DKSearchField: View {
    let placeholder: String
    @Binding var text: String
    let width: CGFloat?
    let focus: Binding<Bool>?

    @State private var isEditing = false
    @Environment(\.isEnabled) private var isEnabled

    public init(_ placeholder: String, text: Binding<String>, width: CGFloat? = 180) {
        self.placeholder = placeholder
        _text = text
        self.width = width
        focus = nil
    }

    /// A search field whose keyboard focus is bound to `isFocused`.
    public init(_ placeholder: String, text: Binding<String>, isFocused: Binding<Bool>, width: CGFloat? = 180) {
        self.placeholder = placeholder
        _text = text
        self.width = width
        focus = isFocused
    }

    public var body: some View {
        let shape = Capsule(style: .circular)
        DKNativeSearchField(
            placeholder: placeholder,
            text: $text,
            isFocused: focusBinding,
            isEnabled: isEnabled,
        )
        .frame(height: Self.fieldHeight)
        // AppKit lays a text field, and the field editor that draws it while
        // focused, a few points wider than the slot SwiftUI gives it; keep long
        // text out of the pill's padding.
        .clipShape(DKInputContentClip(verticalOutset: DK.Metric.controlHeight / 2))
        .padding(.horizontal, 6)
        .frame(width: width, height: DK.Metric.controlHeight)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(shape.fill(DK.Palette.window))
        .overlay(shape.strokeBorder(isFocusedNow ? DK.Palette.accent : DK.Palette.lineStrong, lineWidth: DK.Metric.hairline))
        .contentShape(shape)
        .onTapGesture {
            if isEnabled {
                focusBinding.wrappedValue = true
            }
        }
    }

    private var isFocusedNow: Bool {
        focus?.wrappedValue ?? isEditing
    }

    private var focusBinding: Binding<Bool> {
        Binding(
            get: { focus?.wrappedValue ?? isEditing },
            set: { value in
                if isEditing != value {
                    isEditing = value
                }
                if let focus, focus.wrappedValue != value {
                    focus.wrappedValue = value
                }
            },
        )
    }

    /// The text slot's height inside the 30pt pill.
    static let fieldHeight: CGFloat = 22

    /// The clear button shows only while there is something to clear.
    static func showsClearButton(for text: String) -> Bool {
        !text.isEmpty
    }
}

// MARK: - Native field

/// The `NSSearchField` inside `DKSearchField`, borderless so the pill draws the
/// chrome.
struct DKNativeSearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    let isEnabled: Bool

    func makeNSView(context: Context) -> DKSearchFieldView {
        let field = DKSearchFieldView()
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        // The clear button and Escape send the action, not a text change.
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        return field
    }

    func updateNSView(_ field: DKSearchFieldView, context: Context) {
        context.coordinator.parent = self
        field.onFocusChange = { [coordinator = context.coordinator] focused in
            coordinator.focusChanged(focused)
        }
        if field.stringValue != text {
            field.stringValue = text
        }
        if field.appliedPlaceholder != placeholder {
            field.appliedPlaceholder = placeholder
            field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
                .foregroundColor: NSColor(DK.Palette.muted),
                .font: NSFont.systemFont(ofSize: 13),
            ])
            field.setAccessibilityLabel(placeholder)
        }
        if field.isEnabled != isEnabled {
            field.isEnabled = isEnabled
        }
        // Act on a change of the binding only. Re-applying the same value on
        // every update would fight a focus change the user just made, before
        // it has reached the binding.
        if field.wantsFocus != isFocused {
            field.wantsFocus = isFocused
            field.applyWantedFocusSoon()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: DKNativeSearchField

        init(parent: DKNativeSearchField) {
            self.parent = parent
        }

        @objc func searchChanged(_ field: NSSearchField) {
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField {
                searchChanged(field)
            }
        }

        func focusChanged(_ focused: Bool) {
            if parent.isFocused != focused {
                parent.isFocused = focused
            }
        }
    }
}

/// An `NSSearchField` that reports when it gains and loses the keyboard focus
/// and takes the focus SwiftUI asks for once it is in a window.
final class DKSearchFieldView: NSSearchField {
    var onFocusChange: ((Bool) -> Void)?
    /// What the SwiftUI side last asked for; applied after the update that
    /// changed it, or when the field reaches a window.
    var wantsFocus = false
    /// The placeholder last applied, so an update with the same text does nothing.
    var appliedPlaceholder: String?
    private var applyScheduled = false
    private var responderObservation: NSKeyValueObservation?

    /// Whether the field, or the field editor working for it, is first responder.
    var hasKeyboardFocus: Bool {
        guard let responder = window?.firstResponder else {
            return false
        }
        if responder === self {
            return true
        }
        if let editor = responder as? NSTextView, editor.isFieldEditor, editor.delegate === self {
            return true
        }
        return false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The window's first responder is observable; following it catches
        // every way focus moves (clicks, Tab, a Find command, code), which the
        // field's own responder callbacks do not.
        responderObservation = window?.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            // Focusing a text field changes the first responder twice (the
            // field, then its field editor, whose delegate is set in between);
            // look once the change has settled.
            DispatchQueue.main.async {
                self?.reportFocus()
            }
        }
        applyWantedFocusSoon()
    }

    /// Tells the SwiftUI side where the focus is; it writes the binding only
    /// when the value differs, so a change elsewhere in the window costs a compare.
    private func reportFocus() {
        onFocusChange?(hasKeyboardFocus)
    }

    /// Moves the focus to match `wantsFocus` on the next turn of the run loop,
    /// outside SwiftUI's update, and only when it differs.
    func applyWantedFocusSoon() {
        guard !applyScheduled, wantsFocus != hasKeyboardFocus, window != nil else {
            return
        }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            applyScheduled = false
            applyWantedFocus()
        }
    }

    func applyWantedFocus() {
        guard let window, wantsFocus != hasKeyboardFocus else {
            return
        }
        if wantsFocus {
            window.makeFirstResponder(self)
        } else {
            window.makeFirstResponder(nil)
        }
        reportFocus()
    }
}

// MARK: - Content clip

/// Clips a text field across, to its slot, and leaves it room up and down.
///
/// An AppKit text field sits about 2pt wider on each side than the slot SwiftUI
/// gives it, and its field editor another 2.5pt while focused, so long text
/// draws into the padding of the control around it. Clipping both axes to a
/// one-line slot would cut the ascenders of some scripts and emoji, so the clip
/// reaches `verticalOutset` above and below. Ported from uAppKit's
/// `UDInputContentClip`.
struct DKInputContentClip: Shape {
    var horizontalInset: CGFloat = 0
    var verticalOutset: CGFloat = 0

    nonisolated func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: horizontalInset, dy: -verticalOutset))
    }
}

// MARK: - Previews

private struct DKSearchFieldPreview: View {
    @State private var empty = ""
    @State private var filled = "research"
    @State private var focused = false

    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s3) {
            DKSearchField("Search machines", text: $empty, isFocused: $focused)
            DKSearchField("Search machines", text: $filled)
            DKSearchField("Filter processes", text: $empty, width: nil)
            DKSearchField("Disabled", text: .constant(""), width: 140).disabled(true)
            DKButton(focused ? "Focused" : "Focus Search") {
                focused = true
            }
        }
        .padding(DK.Space.s4)
        .frame(width: 320)
        .background(DK.Palette.window)
    }
}

#Preview("Search field, light") {
    DKSearchFieldPreview().preferredColorScheme(.light)
}

#Preview("Search field, dark") {
    DKSearchFieldPreview().preferredColorScheme(.dark)
}
