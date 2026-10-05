import AppKit
import SwiftUI

// MARK: - Metrics

/// The look shared by form text fields and pop-up menus (`.dk-field`): 28pt tall,
/// a 1pt strong border on the window ground, the field radius. `mono` switches
/// to 12pt monospace for paths, addresses and identifiers.
enum DKFieldMetrics {
    static let height: CGFloat = 28
    static let horizontalPadding: CGFloat = DK.Space.s2

    static func font(mono: Bool) -> Font {
        mono ? DK.Typeface.mono : DK.Typeface.body
    }
}

private struct DKFieldChrome<Content: View>: View {
    let mono: Bool
    let isFocused: Bool
    let content: Content

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DK.Radius.field, style: .continuous)
        content
            .font(DKFieldMetrics.font(mono: mono))
            .foregroundStyle(isEnabled ? DK.Palette.ink : DK.Palette.inkDisabled)
            .padding(.horizontal, DKFieldMetrics.horizontalPadding)
            .frame(minHeight: DKFieldMetrics.height)
            .background(shape.fill(DK.Palette.window))
            .overlay(shape.strokeBorder(isFocused ? DK.Palette.accent : DK.Palette.lineStrong, lineWidth: DK.Metric.hairline))
    }
}

// MARK: - Text field style

/// Styles a `TextField` as a DesignKit form field. Typing, selection, focus and
/// submit stay native; the field draws its own accent border when focused in place
/// of the system focus ring. The whole field takes the click: the AppKit text
/// field inside is only a line of text tall and stops short of the padding, so a
/// click on the field's edge would otherwise land on nothing and seem to need a
/// second try.
///
///     TextField("Name", text: $name).textFieldStyle(DKFieldStyle())
///     TextField("Address", text: $address).textFieldStyle(DKFieldStyle(mono: true))
public struct DKFieldStyle: TextFieldStyle {
    public var mono: Bool

    public init(mono: Bool = false) {
        self.mono = mono
    }

    public func _body(configuration: TextField<_Label>) -> some View {
        configuration.modifier(DKFieldTextFieldModifier(mono: mono))
    }
}

private struct DKFieldTextFieldModifier: ViewModifier {
    let mono: Bool

    @FocusState private var isFocused: Bool

    nonisolated init(mono: Bool) {
        self.mono = mono
    }

    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        DKFieldChrome(
            mono: mono,
            isFocused: isFocused,
            content: content
                .textFieldStyle(.plain)
                .focused($isFocused)
                .focusEffectDisabled()
                .clipShape(DKInputContentClip(verticalOutset: DKFieldMetrics.height / 2)),
        )
        .contentShape(RoundedRectangle(cornerRadius: DK.Radius.field, style: .continuous))
        .onTapGesture {
            if isEnabled {
                isFocused = true
            }
        }
    }
}

// MARK: - Focus out on an outside click

public extension View {
    /// Ends editing when the user clicks anywhere outside this view.
    ///
    /// A text field on macOS keeps the field editor until another responder
    /// takes it; a click on empty space, a row or a card does not, so the caret
    /// and the focus border stay. Apply this to the field, bound to its
    /// `@FocusState`.
    ///
    /// The check runs after the click has been dispatched, not when the event
    /// monitor first sees it. Clearing the focus at once would land on the next
    /// update, after the click had already focused another field, and take that
    /// focus away too: the other field would need a second click. By then the
    /// first responder shows what the click did; the focus is cleared only if it
    /// is still on this field. Ported from uAppKit's `UDInputFocusDismissMonitor`.
    func dkDismissFocusOnOutsideClick(_ isFocused: FocusState<Bool>.Binding) -> some View {
        overlay(DKInputFocusDismissMonitor(isFocused: isFocused))
    }
}

enum DKInputFocusDismissal {
    /// Whether a click at `location` should end the editing of an input whose
    /// frame is `inputFrame`: only a click in the input's own window, outside it.
    static func shouldDismissFocus(eventWindow: NSWindow?, inputWindow: NSWindow?, location: NSPoint, inputFrame: NSRect) -> Bool {
        guard let eventWindow, let inputWindow, eventWindow === inputWindow else {
            return false
        }
        return !inputFrame.contains(location)
    }

    /// The view behind the first responder: the text field a field editor works for.
    @MainActor
    static func responderView(of window: NSWindow) -> NSView? {
        guard let responder = window.firstResponder as? NSView else {
            return nil
        }
        if let editor = responder as? NSTextView, editor.isFieldEditor {
            return editor.delegate as? NSView ?? editor
        }
        return responder
    }
}

struct DKInputFocusDismissMonitor: NSViewRepresentable {
    var isFocused: FocusState<Bool>.Binding

    func makeNSView(context _: Context) -> MonitorView {
        MonitorView()
    }

    func updateNSView(_ view: MonitorView, context _: Context) {
        view.isFocused = isFocused.wrappedValue
        view.onDismiss = { isFocused.wrappedValue = false }
        view.updateMonitor()
    }

    static func dismantleNSView(_ view: MonitorView, coordinator _: ()) {
        view.removeMonitor()
    }

    final class MonitorView: NSView {
        var isFocused = false
        var onDismiss: () -> Void = {}
        private var monitor: Any?

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateMonitor()
        }

        func updateMonitor() {
            if window != nil, isFocused {
                guard monitor == nil else {
                    return
                }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    self?.mouseDownSeen(event)
                    return event
                }
            } else {
                removeMonitor()
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func mouseDownSeen(_ event: NSEvent) {
            guard isFocused, let window else {
                return
            }
            let frame = convert(bounds, to: nil)
            guard DKInputFocusDismissal.shouldDismissFocus(eventWindow: event.window, inputWindow: window, location: event.locationInWindow, inputFrame: frame) else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, isFocused, let window = self.window else {
                    return
                }
                // Another view took the focus: leave it alone.
                if let taken = DKInputFocusDismissal.responderView(of: window), taken.window === window,
                   !taken.convert(taken.bounds, to: nil).intersects(convert(bounds, to: nil))
                {
                    return
                }
                onDismiss()
            }
        }
    }
}

public extension TextFieldStyle where Self == DKFieldStyle {
    /// The DesignKit form field.
    static var dkField: DKFieldStyle {
        DKFieldStyle()
    }

    /// The DesignKit form field in monospace, for paths, addresses and identifiers.
    static var dkFieldMono: DKFieldStyle {
        DKFieldStyle(mono: true)
    }
}

// MARK: - Pop-up menu

/// Styles a menu `Picker` (a pop-up button) as a DesignKit form field. The menu,
/// keyboard handling and accessibility are the system's; only the bezel changes.
/// The field hugs the selected title unless `fill` stretches it across the width
/// it is offered, as in a form row whose control column fills. The system draws
/// the menu title in the system face, so there is no monospace variant.
public struct DKFieldPickerModifier: ViewModifier {
    public var fill: Bool

    public init(fill: Bool = false) {
        self.fill = fill
    }

    public func body(content: Content) -> some View {
        DKFieldChrome(
            mono: false,
            isFocused: false,
            content: content
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .labelsHidden()
                .tint(DK.Palette.ink)
                .frame(maxWidth: fill ? .infinity : nil, alignment: .leading),
        )
        .fixedSize(horizontal: !fill, vertical: false)
    }
}

public extension View {
    /// Draws a menu `Picker` as a DesignKit form field. The picker's label is
    /// hidden, as in form rows, but still names the control for VoiceOver.
    func dkFieldPicker(fill: Bool = false) -> some View {
        modifier(DKFieldPickerModifier(fill: fill))
    }
}

// MARK: - Previews

private struct DKFieldPreview: View {
    @State private var name = "research-26"
    @State private var address = "192.168.64.12"
    @State private var empty = ""
    @State private var mode = "NAT"
    @State private var preset = "jb"

    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s3) {
            TextField("Name", text: $name).textFieldStyle(.dkField)
            TextField("Address", text: $address).textFieldStyle(.dkFieldMono)
            TextField("Placeholder", text: $empty).textFieldStyle(.dkField)
            TextField("Disabled", text: $name).textFieldStyle(.dkField).disabled(true)
            Picker("Network mode", selection: $mode) {
                Text("NAT").tag("NAT")
                Text("Bridged").tag("Bridged")
                Text("Host only").tag("Host only")
            }
            .dkFieldPicker()
            Picker("Patch preset", selection: $preset) {
                Text("jb").tag("jb")
                Text("jb-minimal").tag("jb-minimal")
            }
            .dkFieldPicker(fill: true)
            .frame(width: 160)
        }
        .padding(DK.Space.s4)
        .frame(width: 320)
        .background(DK.Palette.window)
    }
}

#Preview("Fields, light") {
    DKFieldPreview().preferredColorScheme(.light)
}

#Preview("Fields, dark") {
    DKFieldPreview().preferredColorScheme(.dark)
}
