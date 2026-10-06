import Foundation

// MARK: - Log style

/// How a log file's lines are drawn in a terminal.
nonisolated enum VPhoneLaunchpadLogStyle: Hashable, Sendable {
    /// As written: a console, whose guest output carries its own colours.
    case plain
    /// A creation log, whose commands, results, warnings and failures stand
    /// out by the mark `VPhoneLaunchpadLogWriter`'s callers start them with.
    case creation

    /// A line's tone in a creation log.
    enum Tone: Hashable, Sendable {
        case command, success, warning, error
    }

    /// The tone a creation log line is drawn in, or nil for plain text.
    static func creationTone(of line: some StringProtocol) -> Tone? {
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
        return nil
    }

    /// The SGR sequence that starts a tone, in the terminal theme's ANSI
    /// palette.
    static func escape(_ tone: Tone) -> String {
        switch tone {
        case .command: "\u{1B}[34m"
        case .success: "\u{1B}[32m"
        case .warning: "\u{1B}[33m"
        case .error: "\u{1B}[31m"
        }
    }

    static let reset = "\u{1B}[0m"
}

// MARK: - Translator

/// Turns what a log file holds into what a terminal shows.
///
/// Log files end lines with a bare line feed, which a terminal treats as
/// "down one row" without returning to the first column; each one gains a
/// carriage return. A creation log is also coloured line by line, so it
/// holds back a partial line until its end arrives.
///
/// A console can print thousands of lines a second, so both styles copy the
/// runs between line feeds whole and make one pass over each chunk.
nonisolated struct VPhoneLaunchpadLogTranslator {
    let style: VPhoneLaunchpadLogStyle
    private var previous: UInt8 = 0
    private var pending = Data()

    init(style: VPhoneLaunchpadLogStyle = .plain) {
        self.style = style
    }

    mutating func translate(_ data: Data) -> Data {
        switch style {
        case .plain:
            return returnLines(data)
        case .creation:
            return colourLines(data)
        }
    }

    private mutating func returnLines(_ data: Data) -> Data {
        guard let last = data.last else {
            return Data()
        }
        var output = Data(capacity: data.count + data.count / 32)
        let previous = previous
        data.withUnsafeBytes { bytes in
            var start = 0
            while let end = Self.lineFeed(in: bytes, from: start) {
                let before = end > 0 ? bytes[end - 1] : previous
                output.append(contentsOf: UnsafeRawBufferPointer(rebasing: bytes[start ..< end]))
                if before != 0x0D {
                    output.append(0x0D)
                }
                output.append(0x0A)
                start = end + 1
            }
            output.append(contentsOf: UnsafeRawBufferPointer(rebasing: bytes[start...]))
        }
        self.previous = last
        return output
    }

    private mutating func colourLines(_ data: Data) -> Data {
        pending.append(data)
        var output = Data()
        let consumed = pending.withUnsafeBytes { bytes -> Int in
            var start = 0
            while let end = Self.lineFeed(in: bytes, from: start) {
                var line = UnsafeRawBufferPointer(rebasing: bytes[start ..< end])
                if line.last == 0x0D {
                    line = UnsafeRawBufferPointer(rebasing: line.dropLast())
                }
                // Each tone's mark starts with `$`, `w` or the lead byte of
                // `✕` and `●`; other lines are copied without decoding.
                if let first = line.first, first == 0x24 || first == 0x77 || first == 0xE2 {
                    let text = String(decoding: line, as: UTF8.self)
                    if let tone = VPhoneLaunchpadLogStyle.creationTone(of: text) {
                        output.append(contentsOf: (VPhoneLaunchpadLogStyle.escape(tone) + text + VPhoneLaunchpadLogStyle.reset).utf8)
                    } else {
                        output.append(contentsOf: line)
                    }
                } else {
                    output.append(contentsOf: line)
                }
                output.append(contentsOf: [0x0D, 0x0A])
                start = end + 1
            }
            return start
        }
        if consumed == pending.count {
            pending.removeAll(keepingCapacity: true)
        } else if consumed > 0 {
            pending = Data(pending.dropFirst(consumed))
        }
        return output
    }

    /// The offset of the next line feed at or after `start`.
    private static func lineFeed(in bytes: UnsafeRawBufferPointer, from start: Int) -> Int? {
        guard start < bytes.count, let base = bytes.baseAddress,
              let found = memchr(base + start, 0x0A, bytes.count - start)
        else {
            return nil
        }
        return base.distance(to: UnsafeRawPointer(found))
    }
}
