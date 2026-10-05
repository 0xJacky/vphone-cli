import Foundation
import SwiftUI
import VPhoneDesignKit

// Rows the machine sheets share, built from DesignKit parts: a stepper laid
// out as the design draws it, a switch row whose label takes the width, a
// section head with a control beside the title, and a log that follows a file.

// MARK: - Stepper row

/// A form row with the value and a minus and a plus button, as the design draws
/// hardware. VoiceOver and the keyboard see one native stepper.
struct VPhoneLaunchpadStepperRow: View {
    let label: String
    let value: String
    @Binding var number: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        DKFormRow(label) {
            Text(verbatim: value)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            DKButton(DKButtonSpec("−", glyph: .minus, size: .icon, isEnabled: number - step >= range.lowerBound, help: "") {
                number = max(range.lowerBound, number - step)
            })
            DKButton(DKButtonSpec("+", glyph: .plus, size: .icon, isEnabled: number + step <= range.upperBound, help: "") {
                number = min(range.upperBound, number + step)
            })
        }
        .accessibilityRepresentation {
            Stepper(value: $number, in: range, step: step) {
                Text(verbatim: label)
            }
            .accessibilityValue(Text(verbatim: value))
        }
    }
}

// MARK: - Switch row

/// A card row with its label across the width and a DesignKit switch at the
/// trailing edge, for labels longer than a form row's label column.
struct VPhoneLaunchpadSwitchRow<Label: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder let label: Label

    var body: some View {
        HStack(spacing: DK.Space.s3) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            Toggle(isOn: $isOn) {
                label
            }
            .toggleStyle(DKSwitchToggleStyle())
            .labelsHidden()
        }
        .font(DK.Typeface.body)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 14)
    }
}

// MARK: - Plain card row

/// A card row of free content, inset as a form row is: a loading line, an
/// error, an explanation.
struct VPhoneLaunchpadCardRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: DK.Space.s2) {
            content
        }
        .font(DK.Typeface.body)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, DK.Space.s1)
    }
}

/// A muted line in a card row, with an optional warning glyph.
struct VPhoneLaunchpadCardMessage: View {
    let text: Text
    var isWarning = false

    var body: some View {
        VPhoneLaunchpadCardRow {
            if isWarning {
                DKIcon(.warning, size: 14)
                    .foregroundStyle(DK.Palette.warning)
            }
            text
                .foregroundStyle(DK.Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// A spinner and a muted line, while something is read.
struct VPhoneLaunchpadCardLoading: View {
    let text: Text

    var body: some View {
        VPhoneLaunchpadCardRow {
            ProgressView().controlSize(.small)
            text.foregroundStyle(DK.Palette.muted)
        }
    }
}

// MARK: - Section

/// A `DKSection` whose head carries a control beside the title, as the
/// Firmware section's source switch, and whose footnote may be any view.
struct VPhoneLaunchpadSheetSection<Content: View, Trailing: View, Footnote: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content
    @ViewBuilder let footnote: Footnote

    init(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footnote: () -> Footnote,
    ) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
        self.footnote = footnote()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s2) {
            HStack(spacing: DK.Space.s3) {
                Text(verbatim: title)
                    .font(DK.Typeface.sectionTitle)
                    .foregroundStyle(DK.Palette.muted)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.horizontal, DK.Space.s1)
            DKCard {
                content
            }
            VStack(alignment: .leading, spacing: DK.Space.s1) {
                footnote
            }
            .font(DK.Typeface.caption)
            .lineSpacing(3)
            .foregroundStyle(DK.Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DK.Space.s1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension VPhoneLaunchpadSheetSection where Trailing == EmptyView {
    init(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footnote: () -> Footnote,
    ) {
        self.init(title, trailing: { EmptyView() }, content: content, footnote: footnote)
    }
}

/// A red line under a field: why the sheet cannot go ahead.
struct VPhoneLaunchpadFieldProblem: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(DK.Typeface.caption)
            .foregroundStyle(DK.Palette.danger)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DK.Space.s1)
    }
}

// MARK: - Log tail

/// The end of a log file in a `DKLog`, followed while the view is on screen.
/// The file is the only source, as for the console terminal: the view replays
/// the last part of it when it appears and polls for what is appended.
struct VPhoneLaunchpadLogTailView: View {
    let url: URL
    var minHeight: CGFloat = 120
    let label: String
    @State private var buffer = DKLogBuffer(limit: 500)

    var body: some View {
        DKLog(buffer.lines, following: true, wrapsLines: true, minHeight: minHeight, label: label)
            .frame(height: minHeight)
            .task(id: url) {
                buffer.clear()
                #if DEBUG
                    if VPhoneLaunchpadPreview.isActive {
                        for line in VPhoneLaunchpadPreview.log(for: url) {
                            buffer.append(line: DKLogLine(line, tone: Self.tone(of: line)))
                        }
                        return
                    }
                #endif
                await follow()
            }
    }

    /// How a creation log line reads: the commands it ran, its result and its
    /// failure stand out.
    static func tone(of line: String) -> DKLogLine.Tone {
        if line.hasPrefix("$ ") {
            return .command
        }
        if line.hasPrefix("✕") {
            return .error
        }
        if line.hasPrefix("●") {
            return .success
        }
        if line.hasPrefix("warning:") {
            return .warning
        }
        return .plain
    }

    private func follow() async {
        var file: UInt64?
        var offset: UInt64 = 0
        var pending = ""
        while !Task.isCancelled {
            let read = await Self.read(url, file: file, offset: offset)
            if let read {
                if read.file != file || read.restarted {
                    buffer.clear()
                    pending = ""
                }
                file = read.file
                offset = read.offset
                pending += read.text
                var lines = pending.components(separatedBy: "\n")
                pending = lines.removeLast()
                for line in lines {
                    buffer.append(line: DKLogLine(ansi: line, tone: Self.tone(of: line)))
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private nonisolated struct Read: Sendable {
        let file: UInt64
        let offset: UInt64
        let text: String
        let restarted: Bool
    }

    /// How much of an existing log the view replays when it opens.
    private nonisolated static let replayBytes: UInt64 = 64 << 10

    /// What was appended to the file since `offset`. A new file, or one shorter
    /// than `offset`, is read again from its last `replayBytes`, skipping the
    /// partial line that cut leaves at the start.
    @concurrent
    private nonisolated static func read(_ url: URL, file: UInt64?, offset: UInt64) async -> Read? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            return nil
        }
        defer { try? handle.close() }
        var start = offset
        var restarted = false
        if file != number || size < offset {
            start = size > replayBytes ? size - replayBytes : 0
            restarted = true
        }
        guard size > start || restarted else {
            return Read(file: number, offset: start, text: "", restarted: false)
        }
        try? handle.seek(toOffset: start)
        var data = (try? handle.readToEnd()) ?? Data()
        let end = start + UInt64(data.count)
        if restarted, start > 0, let newline = data.firstIndex(of: 0x0A) {
            data = data[data.index(after: newline)...]
        }
        return Read(file: number, offset: end, text: String(decoding: data, as: UTF8.self), restarted: restarted)
    }
}
