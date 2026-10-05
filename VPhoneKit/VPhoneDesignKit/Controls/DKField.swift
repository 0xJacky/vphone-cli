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
/// of the system focus ring.
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

    func body(content: Content) -> some View {
        DKFieldChrome(
            mono: mono,
            isFocused: isFocused,
            content: content
                .textFieldStyle(.plain)
                .focused($isFocused)
                .focusEffectDisabled(),
        )
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
