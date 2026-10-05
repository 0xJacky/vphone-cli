import SwiftUI
import VPhoneDesignKit

/// A monospaced multi-line text field in the DesignKit field look, for values
/// typed for the guest: clipboard text, a keychain value. DesignKit's
/// `DKFieldStyle` covers one-line `TextField`s only. `bordered: false` drops
/// the field chrome for an editor that fills a card.
struct VPhoneGuestTextEditor: View {
    @Binding var text: String
    var placeholder: String?
    let accessibilityLabel: String
    var bordered = true
    var focus: FocusState<Bool>.Binding?

    @FocusState private var ownFocus: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DK.Radius.field, style: .continuous)
        let isFocused = focus?.wrappedValue ?? ownFocus
        editor
            .font(DK.Typeface.mono)
            .foregroundStyle(DK.Palette.ink)
            .scrollContentBackground(.hidden)
            .focusEffectDisabled()
            .padding(.horizontal, bordered ? 3 : 11)
            .padding(.vertical, bordered ? 4 : 6)
            .background(alignment: .topLeading) {
                if text.isEmpty, let placeholder {
                    Text(placeholder)
                        .font(DK.Typeface.mono)
                        .foregroundStyle(DK.Palette.muted)
                        .padding(.horizontal, bordered ? 8 : 16)
                        .padding(.vertical, bordered ? 4 : 6)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background {
                if bordered {
                    shape.fill(DK.Palette.window)
                }
            }
            .overlay {
                if bordered {
                    shape.strokeBorder(isFocused ? DK.Palette.accent : DK.Palette.lineStrong, lineWidth: DK.Metric.hairline)
                }
            }
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var editor: some View {
        if let focus {
            TextEditor(text: $text).focused(focus)
        } else {
            TextEditor(text: $text).focused($ownFocus)
        }
    }
}
