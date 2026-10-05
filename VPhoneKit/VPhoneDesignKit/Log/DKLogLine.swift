import SwiftUI

/// One line of a `DKLog`: an optional timestamp, the message as styled runs,
/// and a tone that colors whatever the runs leave uncolored.
public struct DKLogLine: Identifiable, Sendable, Hashable {
    /// How a whole line reads, after `.dk-log__line--*` in the design.
    public enum Tone: String, Sendable, CaseIterable, Hashable {
        /// Ordinary output in the terminal foreground.
        case plain
        /// A command that was run: blue, semibold.
        case command
        /// Secondary output: boot noise, placeholders, timestamps.
        case dim
        /// A step that finished: green, semibold.
        case success
        /// Something to look at: yellow, semibold.
        case warning
        /// A failure: red, semibold.
        case error

        /// The text color on the terminal background.
        public var color: Color {
            switch self {
            case .plain: DK.Palette.terminalForeground
            case .command: DK.Palette.terminalBlue
            case .dim: DK.Palette.terminalDim
            case .success: DK.Palette.terminalGreen
            case .warning: DK.Palette.terminalYellow
            case .error: DK.Palette.terminalRed
            }
        }

        /// Whether the line is set semibold, as command, result and failure lines are.
        public var isEmphasized: Bool {
            switch self {
            case .plain, .dim: false
            case .command, .success, .warning, .error: true
            }
        }

        /// The shared status tone, for a badge or a dot that describes the line.
        public var statusTone: DKTone {
            switch self {
            case .plain: .neutral
            case .command: .info
            case .dim: .idle
            case .success: .success
            case .warning: .warning
            case .error: .danger
            }
        }

        /// The line tone for a shared status tone.
        public init(_ tone: DKTone) {
            switch tone {
            case .neutral: self = .plain
            case .idle: self = .dim
            case .success: self = .success
            case .warning: self = .warning
            case .danger: self = .error
            case .info, .accent: self = .command
            }
        }

        /// The tone for a unified log level as `log stream` prints it: `Fault` is an
        /// error, `Error` a warning, `Debug` dim, and anything else plain. Case is ignored.
        public init(logLevel: String) {
            switch logLevel.lowercased() {
            case "fault": self = .error
            case "error": self = .warning
            case "debug": self = .dim
            default: self = .plain
            }
        }
    }

    public let id: UUID
    /// The timestamp split off the front of the line, as written (brackets kept).
    public var timestamp: String?
    /// The message as styled runs, with no escape sequences.
    public var runs: [DKLogRun]
    public var tone: Tone

    /// A line of plain text. The text is shown as given.
    public init(_ text: String, tone: Tone = .plain, timestamp: String? = nil) {
        self.init(runs: text.isEmpty ? [] : [DKLogRun(text)], tone: tone, timestamp: timestamp)
    }

    /// A line of styled runs.
    public init(runs: [DKLogRun], tone: Tone = .plain, timestamp: String? = nil) {
        self.init(id: UUID(), runs: runs, tone: tone, timestamp: timestamp)
    }

    /// A line of terminal output: ANSI colors become runs, other escape sequences
    /// are removed, and with `splitsTimestamp` a leading timestamp moves to `timestamp`.
    /// Line breaks in `ansi` are kept in the text; use `DKLogBuffer` to split a stream.
    public init(ansi: String, tone: Tone = .plain, splitsTimestamp: Bool = false) {
        self.init(id: UUID(), parsedRuns: DKANSIParser.runs(in: ansi), tone: tone, splitsTimestamp: splitsTimestamp)
    }

    init(id: UUID, runs: [DKLogRun], tone: Tone, timestamp: String?) {
        self.id = id
        self.runs = runs
        self.tone = tone
        self.timestamp = timestamp
    }

    init(id: UUID, parsedRuns: [DKLogRun], tone: Tone, splitsTimestamp: Bool) {
        var runs = parsedRuns
        var timestamp: String?
        if splitsTimestamp, let split = Self.timestampPrefix(of: runs.plainText) {
            timestamp = split.timestamp
            runs = runs.droppingPrefix(scalars: split.length)
        }
        self.init(id: id, runs: runs, tone: tone, timestamp: timestamp)
    }

    /// The message with no styling and no timestamp.
    public var text: String {
        runs.plainText
    }

    /// Whether the timestamp or the message contains `query`, ignoring case and
    /// diacritics. An empty query matches every line.
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return true
        }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return text.range(of: query, options: options) != nil
            || timestamp?.range(of: query, options: options) != nil
    }

    // MARK: Rendering

    /// The line as the log draws it: the timestamp dim, then each run in its
    /// ANSI color, or the line's tone color where the run has none.
    public var attributedText: AttributedString {
        var result = AttributedString()
        if let timestamp {
            var stamp = AttributedString(timestamp + "  ")
            stamp.swiftUI.foregroundColor = DK.Palette.terminalDim
            stamp.swiftUI.font = DK.Typeface.log
            result.append(stamp)
        }
        for run in runs {
            var piece = AttributedString(run.text)
            piece.swiftUI.foregroundColor = color(for: run.style)
            piece.swiftUI.font = font(for: run.style)
            result.append(piece)
        }
        return result
    }

    func color(for style: DKLogStyle) -> Color {
        if let color = style.color {
            return color.terminalColor
        }
        return style.isFaint ? DK.Palette.terminalDim : tone.color
    }

    func font(for style: DKLogStyle) -> Font {
        if style.isBold {
            return DK.Typeface.log.weight(.bold)
        }
        return tone.isEmphasized ? DK.Typeface.log.weight(.semibold) : DK.Typeface.log
    }
}

// MARK: - Colors

public extension DKLogColor {
    /// The color an SGR code draws with on the terminal background. Black and
    /// gray are dim so they stay readable on the dark terminal; white is the
    /// terminal foreground so it stays readable on the light one.
    var terminalColor: Color {
        switch self {
        case .black, .gray: DK.Palette.terminalDim
        case .red: DK.Palette.terminalRed
        case .green: DK.Palette.terminalGreen
        case .yellow: DK.Palette.terminalYellow
        case .blue: DK.Palette.terminalBlue
        case .magenta: DK.Palette.terminalMagenta
        case .cyan: DK.Palette.terminalCyan
        case .white: DK.Palette.terminalForeground
        }
    }
}

// MARK: - Timestamps

public extension DKLogLine {
    /// Splits a leading timestamp off `text`. Recognized forms, optionally in
    /// square brackets: `09:41:19`, `9:41:19.204`, `2026-10-05 09:41:19.204123+0800`,
    /// `2026-10-05T09:41:19Z`, `2026-10-05T09:41:19,5-07:00`. The timestamp
    /// must be followed by whitespace or the end of the line; that whitespace
    /// is dropped. Text without one comes back whole with a nil timestamp.
    static func splitTimestamp(_ text: String) -> (timestamp: String?, message: String) {
        guard let split = timestampPrefix(of: text) else {
            return (nil, text)
        }
        return (split.timestamp, String(text.unicodeScalars.dropFirst(split.length)))
    }

    /// The timestamp at the front of `text` and how many Unicode scalars it and the
    /// whitespace after it span. Everything matched is ASCII, so the byte count
    /// is also the scalar count.
    internal static func timestampPrefix(of text: String) -> (timestamp: String, length: Int)? {
        var scanner = TimestampScanner(Array(text.utf8.prefix(64)))
        let bracketed = scanner.take(UInt8(ascii: "["))
        let start = scanner.index
        if scanner.date() {
            guard scanner.take(UInt8(ascii: "T")) || scanner.take(UInt8(ascii: " ")) else {
                return nil
            }
        } else {
            scanner.index = start
        }
        guard scanner.time() else {
            return nil
        }
        scanner.zone()
        if bracketed, !scanner.take(UInt8(ascii: "]")) {
            return nil
        }
        let end = scanner.index
        guard scanner.atEnd || scanner.whitespace() else {
            return nil
        }
        let stamp = String(decoding: scanner.bytes[0 ..< end], as: UTF8.self)
        return (stamp, scanner.index)
    }
}

private struct TimestampScanner {
    let bytes: [UInt8]
    var index = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var atEnd: Bool {
        index >= bytes.count
    }

    mutating func take(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else {
            return false
        }
        index += 1
        return true
    }

    /// Takes between `minimum` and `maximum` ASCII digits.
    mutating func digits(_ minimum: Int, _ maximum: Int) -> Bool {
        var count = 0
        while count < maximum, index < bytes.count, (0x30 ... 0x39).contains(bytes[index]) {
            index += 1
            count += 1
        }
        return count >= minimum
    }

    /// `YYYY-MM-DD`
    mutating func date() -> Bool {
        digits(4, 4) && take(UInt8(ascii: "-")) && digits(2, 2) && take(UInt8(ascii: "-")) && digits(2, 2)
    }

    /// `H:MM:SS` or `HH:MM:SS`, with an optional `.fraction` or `,fraction`.
    mutating func time() -> Bool {
        guard digits(1, 2), take(UInt8(ascii: ":")), digits(2, 2), take(UInt8(ascii: ":")), digits(2, 2) else {
            return false
        }
        let beforeFraction = index
        if take(UInt8(ascii: ".")) || take(UInt8(ascii: ",")) {
            if !digits(1, 9) {
                index = beforeFraction
            }
        }
        return true
    }

    /// `Z`, `+HH`, `+HHMM` or `+HH:MM` (or with `-`); nothing is taken when absent.
    mutating func zone() {
        if take(UInt8(ascii: "Z")) {
            return
        }
        let start = index
        guard take(UInt8(ascii: "+")) || take(UInt8(ascii: "-")) else {
            return
        }
        guard digits(2, 2) else {
            index = start
            return
        }
        let afterHours = index
        if take(UInt8(ascii: ":")) {
            if !digits(2, 2) {
                index = afterHours
            }
        } else {
            _ = digits(2, 2)
        }
    }

    /// One or more spaces or tabs.
    mutating func whitespace() -> Bool {
        let start = index
        while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x09 {
            index += 1
        }
        return index > start
    }
}

// MARK: - Run slicing

extension [DKLogRun] {
    /// The runs with their first `count` Unicode scalars removed.
    func droppingPrefix(scalars count: Int) -> [DKLogRun] {
        var remaining = count
        var result: [DKLogRun] = []
        for run in self {
            if remaining == 0 {
                result.append(run)
                continue
            }
            let length = run.text.unicodeScalars.count
            if length <= remaining {
                remaining -= length
            } else {
                result.append(DKLogRun(String(run.text.unicodeScalars.dropFirst(remaining)), style: run.style))
                remaining = 0
            }
        }
        return result
    }
}
