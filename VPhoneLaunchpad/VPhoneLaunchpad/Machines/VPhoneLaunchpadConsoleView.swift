import SwiftUI
import VPhoneDesignKit

// MARK: - Console sheet

/// A sheet for a machine's console, which `vm launch` writes, or a creation log.
struct VPhoneLaunchpadConsoleView: View {
    let title: LocalizedStringKey
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VPhoneLaunchpadSheet(Text(title)) {
            VPhoneLaunchpadLogTerminal(url: url)
                .frame(minWidth: 900, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
                .padding(DK.Space.s2)
                .background(DK.Palette.terminalBackground)
                .clipShape(RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                        .strokeBorder(DK.Palette.line, lineWidth: DK.Metric.hairline),
                )
                .padding(.horizontal, DK.Space.s4)
                .padding(.vertical, DK.Space.s3)
        } actions: {
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }
}

// MARK: - Console tail

/// The last lines of a console log, for the inspector. Reads only the end
/// of the file, once a second and only when it has changed, so a chatty
/// guest costs a small read rather than a view update per line. The full
/// log is the console sheet's.
struct VPhoneLaunchpadConsoleTail: View {
    let url: URL
    /// Follows new lines while the machine runs.
    var following: Bool
    @State private var lines: [DKLogLine] = []

    var body: some View {
        DKLog(lines, following: following, label: String(localized: "Console"))
            // DKLog takes whether it follows only when it is made.
            .id(following)
            .task(id: url) {
                await follow()
            }
    }

    private func follow() async {
        lines = []
        #if DEBUG
            if VPhoneLaunchpadPreview.isActive {
                var buffer = DKLogBuffer(limit: Self.lineLimit)
                buffer.append(VPhoneLaunchpadPreview.log(for: url).joined(separator: "\n"))
                lines = buffer.lines
                return
            }
        #endif
        var stamp: Tail.Stamp?
        while !Task.isCancelled {
            let tail = await Tail.read(url, unless: stamp)
            if let tail {
                stamp = tail.stamp
                lines = tail.lines
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    nonisolated static let lineLimit = 60

    /// The end of a log file, read off the main actor.
    nonisolated enum Tail {
        struct Stamp: Equatable, Sendable {
            let file: UInt64
            let size: UInt64
            let modified: Date?
        }

        /// How much of the file's end is read.
        static let bytes: UInt64 = 16 << 10

        /// The file's last lines, or nil when it has not changed since
        /// `previous`. A missing file reads as one dim line.
        @concurrent
        static func read(_ url: URL, unless previous: Stamp?) async -> (stamp: Stamp, lines: [DKLogLine])? {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.uint64Value,
                  let handle = try? FileHandle(forReadingFrom: url)
            else {
                let missing = Stamp(file: 0, size: 0, modified: nil)
                guard previous != missing else { return nil }
                return (missing, [DKLogLine(String(localized: "No output yet."), tone: .dim)])
            }
            defer { try? handle.close() }
            let stamp = Stamp(
                file: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                size: size,
                modified: attributes[.modificationDate] as? Date,
            )
            guard stamp != previous else { return nil }
            let offset = size > bytes ? size - bytes : 0
            try? handle.seek(toOffset: offset)
            var data = (try? handle.read(upToCount: Int(bytes))) ?? Data()
            // A read from the middle of the file starts mid-line.
            if offset > 0, let end = data.firstIndex(of: 0x0A) {
                data = data[data.index(after: end)...]
            }
            var buffer = DKLogBuffer(limit: VPhoneLaunchpadConsoleTail.lineLimit)
            buffer.append(String(decoding: data, as: UTF8.self))
            return (stamp, buffer.lines)
        }
    }
}
