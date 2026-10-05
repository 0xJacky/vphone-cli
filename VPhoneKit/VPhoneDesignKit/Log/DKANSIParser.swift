import Foundation

// MARK: - Run style

/// The eight terminal hues an SGR color code can name, plus `gray` for bright
/// black (`90`). The other bright codes (`91`–`97`) fold onto their base hue:
/// the log draws them with the same terminal color.
public enum DKLogColor: String, Sendable, CaseIterable, Hashable {
    case black, red, green, yellow, blue, magenta, cyan, white, gray
}

/// How a run of log text is drawn: an explicit terminal color (nil takes the
/// line's tone), bold (`SGR 1`) and faint (`SGR 2`).
public struct DKLogStyle: Sendable, Hashable {
    public var color: DKLogColor?
    public var isBold: Bool
    public var isFaint: Bool

    public init(color: DKLogColor? = nil, isBold: Bool = false, isFaint: Bool = false) {
        self.color = color
        self.isBold = isBold
        self.isFaint = isFaint
    }

    /// No color, regular weight: the line's tone draws it.
    public static let plain = DKLogStyle()
}

/// A stretch of log text in one style. Escape sequences never appear in `text`.
public struct DKLogRun: Sendable, Hashable {
    public var text: String
    public var style: DKLogStyle

    public init(_ text: String, style: DKLogStyle = .plain) {
        self.text = text
        self.style = style
    }
}

extension [DKLogRun] {
    /// Appends a run, merging it into the last one when the styles match and
    /// dropping it when it is empty.
    mutating func appendMerging(_ run: DKLogRun) {
        guard !run.text.isEmpty else {
            return
        }
        if let last = indices.last, self[last].style == run.style {
            self[last].text += run.text
        } else {
            append(run)
        }
    }

    /// The runs' text with no styling.
    var plainText: String {
        map(\.text).joined()
    }
}

// MARK: - Parser

/// Turns terminal output into styled runs. SGR codes for the foreground color
/// (`30`–`37`, `90`–`97`, `39`), bold (`1`), faint (`2`), normal intensity
/// (`22`) and reset (`0` or empty) set the style; 256-color and true-color
/// arguments (`38;5;n`, `38;2;r;g;b`) are skipped whole, and every other
/// escape sequence (cursor movement, erase, OSC titles and hyperlinks, DCS,
/// charset selection) is removed. Other control characters are removed too,
/// except tab, line feed and carriage return, which pass through for the line
/// splitter in `DKLogBuffer`.
///
/// The parser is a state machine, so a sequence split across two `feed(_:)`
/// calls is still recognized; the one-shot `runs(in:)` drops a sequence left
/// open at the end. A string sequence (OSC, DCS, APC, PM, SOS) ends at a line
/// feed even without its terminator, so a stray `ESC ]` cannot swallow the rest
/// of a log.
public struct DKANSIParser: Sendable {
    /// The style the next printed character takes.
    public private(set) var style: DKLogStyle
    private var state = State.ground

    private enum State: Sendable, Hashable {
        case ground
        /// After ESC.
        case escape
        /// After ESC and one or more intermediate bytes (charset selection and the like).
        case escapeIntermediate
        /// Inside a control sequence: the parameter bytes so far, and whether an
        /// intermediate byte or a private marker makes it one we do not apply.
        case controlSequence(parameters: String, isPlain: Bool)
        /// Inside OSC, DCS, SOS, PM or APC, which ends at BEL or ST.
        case string
        /// ESC seen inside a string: `\` completes ST.
        case stringEscape
    }

    public init(style: DKLogStyle = .plain) {
        self.style = style
    }

    /// The runs in `text`, starting unstyled. A sequence left open at the end is dropped.
    public static func runs(in text: String) -> [DKLogRun] {
        var parser = DKANSIParser()
        return parser.feed(text)
    }

    /// The plain text of `text` with every escape sequence and control character
    /// removed except tab, line feed and carriage return.
    public static func strip(_ text: String) -> String {
        runs(in: text).plainText
    }

    /// True while a sequence is open, waiting for the rest of it in the next chunk.
    public var isInsideSequence: Bool {
        state != .ground
    }

    /// Parses the next chunk of a stream. Style and an unfinished sequence carry
    /// over to the next call.
    public mutating func feed(_ chunk: String) -> [DKLogRun] {
        var runs: [DKLogRun] = []
        var text = String.UnicodeScalarView()

        func flush() {
            if !text.isEmpty {
                runs.appendMerging(DKLogRun(String(text), style: style))
                text = String.UnicodeScalarView()
            }
        }

        for scalar in chunk.unicodeScalars {
            var pending: Unicode.Scalar? = scalar
            while let current = pending {
                pending = nil
                let value = current.value
                switch state {
                case .ground:
                    switch value {
                    case 0x1B:
                        state = .escape
                    case 0x9B:
                        state = .controlSequence(parameters: "", isPlain: true)
                    case 0x90, 0x98, 0x9D, 0x9E, 0x9F:
                        state = .string
                    case 0x09, 0x0A, 0x0D:
                        text.append(current)
                    case 0x00 ... 0x1F, 0x7F ... 0x9F:
                        break
                    default:
                        text.append(current)
                    }

                case .escape:
                    switch value {
                    case 0x5B: // [
                        state = .controlSequence(parameters: "", isPlain: true)
                    case 0x5D, 0x50, 0x58, 0x5E, 0x5F: // ] P X ^ _
                        state = .string
                    case 0x1B:
                        break
                    case 0x20 ... 0x2F:
                        state = .escapeIntermediate
                    case 0x30 ... 0x7E:
                        state = .ground
                    default:
                        state = .ground
                        pending = current
                    }

                case .escapeIntermediate:
                    switch value {
                    case 0x20 ... 0x2F:
                        break
                    case 0x30 ... 0x7E:
                        state = .ground
                    default:
                        state = .ground
                        pending = current
                    }

                case let .controlSequence(parameters, isPlain):
                    switch value {
                    case 0x30 ... 0x3B: // digits, : and ;
                        state = .controlSequence(parameters: parameters + String(current), isPlain: isPlain)
                    case 0x3C ... 0x3F: // < = > ? private markers
                        state = .controlSequence(parameters: parameters, isPlain: false)
                    case 0x20 ... 0x2F:
                        state = .controlSequence(parameters: parameters, isPlain: false)
                    case 0x40 ... 0x7E:
                        state = .ground
                        if value == 0x6D, isPlain { // m
                            flush()
                            applySelectGraphicRendition(parameters)
                        }
                    default:
                        // A control character or a non-ASCII scalar breaks the
                        // sequence; the scalar is handled as ordinary input.
                        state = .ground
                        pending = current
                    }

                case .string:
                    switch value {
                    case 0x07, 0x9C:
                        state = .ground
                    case 0x1B:
                        state = .stringEscape
                    case 0x0A:
                        state = .ground
                        pending = current
                    default:
                        break
                    }

                case .stringEscape:
                    if value == 0x5C { // \
                        state = .ground
                    } else {
                        state = .escape
                        pending = current
                    }
                }
            }
        }
        flush()
        return runs
    }

    /// Forgets the style and any open sequence.
    public mutating func reset() {
        style = .plain
        state = .ground
    }

    // MARK: SGR

    private mutating func applySelectGraphicRendition(_ parameters: String) {
        let fields = parameters.split(separator: ";", omittingEmptySubsequences: false)
        var index = fields.startIndex
        while index < fields.endIndex {
            let field = fields[index]
            index += 1
            // A colon form (`38:2::r:g:b`) carries its own arguments in one field.
            let hasSubparameters = field.contains(":")
            let head = field.split(separator: ":", omittingEmptySubsequences: false).first ?? ""
            let code = head.isEmpty ? 0 : Int(head) ?? -1
            switch code {
            case 0:
                style = .plain
            case 1:
                style.isBold = true
            case 2:
                style.isFaint = true
            case 22:
                style.isBold = false
                style.isFaint = false
            case 30 ... 37:
                style.color = Self.baseColors[code - 30]
            case 39:
                style.color = nil
            case 90:
                style.color = .gray
            case 91 ... 97:
                style.color = Self.baseColors[code - 90]
            case 38, 48, 58:
                // Extended color: skip `5;n` or `2;r;g;b`, which are not codes of their own.
                if !hasSubparameters, index < fields.endIndex {
                    switch fields[index] {
                    case "5": index = Swift.min(index + 2, fields.endIndex)
                    case "2": index = Swift.min(index + 4, fields.endIndex)
                    default: break
                    }
                }
            default:
                break
            }
        }
    }

    private static let baseColors: [DKLogColor] = [.black, .red, .green, .yellow, .blue, .magenta, .cyan, .white]
}
