import AppKit
import SwiftUI
import VPhoneDesignKit

/// An (i) button that keeps a command out of the row and shows it, with a
/// copy button, in a popover.
struct VPhoneLaunchpadCommandInfoButton: View {
    let command: String
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            DKIcon(.info, size: 15)
                .foregroundStyle(DK.Palette.muted)
        }
        .buttonStyle(.borderless)
        .help("Show the command")
        .accessibilityLabel(Text("Show the command"))
        .popover(isPresented: $isShown, arrowEdge: .trailing) {
            HStack(alignment: .firstTextBaseline, spacing: DK.Space.s2) {
                Text(verbatim: command)
                    .font(DK.Typeface.mono)
                    .foregroundStyle(DK.Palette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480, alignment: .leading)
                DKButton(DKButtonSpec(String(localized: "Copy Command"), glyph: .copy, size: .small) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                })
            }
            .padding(DK.Space.s3)
        }
    }
}
