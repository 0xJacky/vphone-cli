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
            pending.append(data)
            var output = Data()
            while let end = pending.firstIndex(of: 0x0A) {
                var line = pending[pending.startIndex ..< end]
                if line.last == 0x0D {
                    line = line.dropLast()
                }
                let text = String(decoding: line, as: UTF8.self)
                if let tone = VPhoneLaunchpadLogStyle.creationTone(of: text) {
                    output.append(Data((VPhoneLaunchpadLogStyle.escape(tone) + text + VPhoneLaunchpadLogStyle.reset).utf8))
                } else {
                    output.append(line)
                }
                output.append(contentsOf: [0x0D, 0x0A])
                pending = Data(pending[pending.index(after: end)...])
            }
            return output
        }
    }

    private mutating func returnLines(_ data: Data) -> Data {
        var output = Data(capacity: data.count + data.count / 32)
        for byte in data {
            if byte == 0x0A, previous != 0x0D {
                output.append(0x0D)
            }
            output.append(byte)
            previous = byte
        }
        return output
    }
}
