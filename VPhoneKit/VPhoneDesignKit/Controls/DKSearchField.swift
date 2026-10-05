import SwiftUI

/// The DesignKit search field: a pill with a magnifying glass, a placeholder that
/// doubles as the accessibility label, and a clear button once there is text.
/// Escape clears the text, as in a native search field. Pass `width: nil` to let
/// the field take the width it is offered.
public struct DKSearchField: View {
    let placeholder: String
    @Binding var text: String
    let width: CGFloat?

    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(_ placeholder: String, text: Binding<String>, width: CGFloat? = 180) {
        self.placeholder = placeholder
        _text = text
        self.width = width
    }

    public var body: some View {
        let shape = Capsule(style: .circular)
        HStack(spacing: 6) {
            DKIcon(.search, size: 14)
                .foregroundStyle(DK.Palette.muted)
            TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(DK.Palette.muted))
                .textFieldStyle(.plain)
                .font(DK.Typeface.body)
                .foregroundStyle(isEnabled ? DK.Palette.ink : DK.Palette.inkDisabled)
                .focused($isFocused)
                .focusEffectDisabled()
                .accessibilityLabel(placeholder)
                .onExitCommand(perform: clear)
            if Self.showsClearButton(for: text) {
                Button(action: clear) {
                    DKIcon(.xCircle, size: 13)
                        .foregroundStyle(DK.Palette.inkDisabled)
                }
                .buttonStyle(.plain)
                .help("Clear")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: DK.Metric.controlHeight)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(shape.fill(DK.Palette.window))
        .overlay(shape.strokeBorder(isFocused ? DK.Palette.accent : DK.Palette.lineStrong, lineWidth: DK.Metric.hairline))
        .contentShape(shape)
        .onTapGesture { isFocused = true }
    }

    /// The clear button shows only while there is something to clear.
    static func showsClearButton(for text: String) -> Bool {
        !text.isEmpty
    }

    private func clear() {
        text = ""
    }
}

// MARK: - Previews

private struct DKSearchFieldPreview: View {
    @State private var empty = ""
    @State private var filled = "research"

    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s3) {
            DKSearchField("Search machines", text: $empty)
            DKSearchField("Search machines", text: $filled)
            DKSearchField("Filter processes", text: $empty, width: nil)
            DKSearchField("Disabled", text: .constant(""), width: 140).disabled(true)
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
