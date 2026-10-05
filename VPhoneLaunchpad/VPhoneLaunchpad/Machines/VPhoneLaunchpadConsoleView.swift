import SwiftUI
import VPhoneDesignKit

// MARK: - Console sheet

/// A sheet for a machine's console, which `vm launch` writes, or a creation log.
struct VPhoneLaunchpadConsoleView: View {
    let title: LocalizedStringKey
    let url: URL
    var style = VPhoneLaunchpadLogStyle.plain
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VPhoneLaunchpadSheet(Text(title)) {
            VPhoneLaunchpadTerminalPane(url: url, style: style)
                .frame(minWidth: 900, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
                .padding(.horizontal, DK.Space.s4)
                .padding(.vertical, DK.Space.s3)
        } actions: {
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }
}

// MARK: - Terminal pane

/// A log file in the embedded Ghostty terminal, framed as a card: the console
/// sheet, the inspector's Console section and the creation sheet's log. Read
/// only; it follows the file as it grows.
struct VPhoneLaunchpadTerminalPane: View {
    let url: URL
    var style = VPhoneLaunchpadLogStyle.plain
    /// How much of an existing log is replayed. The inspector and the
    /// creation sheet show the end of it; the console sheet shows more.
    var replayBytes = VPhoneLaunchpadLogTail.replayBytes

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
        VPhoneLaunchpadLogTerminal(url: url, style: style, replayBytes: replayBytes)
            // A terminal of its own per file, so another machine's console
            // never shows under this one's.
            .id(url)
            .padding(DK.Space.s2)
            .background(DK.Palette.terminalBackground)
            .clipShape(shape)
            .overlay(shape.strokeBorder(DK.Palette.line, lineWidth: DK.Metric.hairline))
    }

    /// The replay for a pane that shows only the end of a log.
    static let tailBytes: UInt64 = 64 << 10
}
