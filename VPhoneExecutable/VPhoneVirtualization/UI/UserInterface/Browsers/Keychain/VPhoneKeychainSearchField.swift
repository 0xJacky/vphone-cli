import AppKit
import SwiftUI
import VPhoneDesignKit

/// The Keychain page's search field: an `NSSearchField` in the DesignKit
/// search pill. `DKSearchField` is a SwiftUI `TextField`; the Keychain window
/// controller's Find command focuses the first `NSSearchField` in the window,
/// so this one has to be a real one.
struct VPhoneKeychainSearchField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat = 160

    @State private var isEditing = false

    var body: some View {
        let shape = Capsule(style: .circular)
        Field(placeholder: placeholder, text: $text, isEditing: $isEditing)
            .padding(.horizontal, 6)
            .frame(width: width, height: DK.Metric.controlHeight)
            .background(shape.fill(DK.Palette.window))
            .overlay(shape.strokeBorder(isEditing ? DK.Palette.accent : DK.Palette.lineStrong, lineWidth: DK.Metric.hairline))
            .accessibilityLabel(placeholder)
    }

    private struct Field: NSViewRepresentable {
        let placeholder: String
        @Binding var text: String
        @Binding var isEditing: Bool

        func makeNSView(context: Context) -> NSSearchField {
            let field = NSSearchField()
            field.placeholderString = placeholder
            field.isBezeled = false
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.font = .systemFont(ofSize: 13)
            field.sendsSearchStringImmediately = true
            field.delegate = context.coordinator
            field.target = context.coordinator
            field.action = #selector(Coordinator.changed(_:))
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            return field
        }

        func updateNSView(_ field: NSSearchField, context: Context) {
            context.coordinator.parent = self
            if field.stringValue != text {
                field.stringValue = text
            }
            field.placeholderString = placeholder
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        @MainActor
        final class Coordinator: NSObject, NSSearchFieldDelegate {
            var parent: Field

            init(parent: Field) {
                self.parent = parent
            }

            @objc func changed(_ sender: NSSearchField) {
                parent.text = sender.stringValue
            }

            func controlTextDidChange(_ notification: Notification) {
                guard let field = notification.object as? NSSearchField else { return }
                parent.text = field.stringValue
            }

            func controlTextDidBeginEditing(_: Notification) {
                parent.isEditing = true
            }

            func controlTextDidEndEditing(_: Notification) {
                parent.isEditing = false
            }
        }
    }
}
