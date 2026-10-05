import SwiftUI

// MARK: - Key-value row

/// One key-value row of a section (`.dk-kv__row`) or one fact of a detail bar:
/// "CPU — 8 cores", "IPv4 Address — 192.168.64.12".
///
/// A `tone` marks the row as a check, as on Host Setup: a status dot in the
/// tone's color sits before the value. Warning and danger values also take the
/// tone's ink so a failing check reads without the dot; success and neutral
/// values stay in the body ink, so a column of passed checks does not turn green.
///
/// A row can also carry a tooltip on its value (`help`), a thin progress bar
/// under the value (`progress`, as a disk's fill), and one small trailing
/// button (`action`, as "Reveal" or "Copy").
public struct DKKeyValue: Identifiable, Hashable, Sendable {
    /// Stable identity in a `ForEach`; the key unless given.
    public var id: String
    public var key: String
    public var value: String
    /// Set identifiers, addresses and paths in monospace.
    public var monospaced: Bool
    /// The check state this row reports, if it is a check.
    public var tone: DKTone?
    /// The value's tooltip: the full text of a truncated path, what a figure means.
    public var help: String?
    /// A fraction of 0...1 drawn as a thin bar under the value, in the row's
    /// tone or the accent; nil draws none.
    public var progress: Double?
    private var actionBox: DKKeyValueAction?

    public init(
        _ key: String,
        _ value: String,
        monospaced: Bool = false,
        tone: DKTone? = nil,
        id: String? = nil,
        help: String? = nil,
        progress: Double? = nil,
        action: DKButtonSpec? = nil,
    ) {
        self.id = id ?? key
        self.key = key
        self.value = value
        self.monospaced = monospaced
        self.tone = tone
        self.help = help
        self.progress = progress
        actionBox = action.map(DKKeyValueAction.init)
    }

    /// A button after the value, drawn small.
    public var action: DKButtonSpec? {
        get { actionBox?.spec }
        set { actionBox = newValue.map(DKKeyValueAction.init) }
    }

    /// `progress` clamped to 0...1, or nil when the row has no bar.
    public var visibleProgress: Double? {
        progress.map { $0.isNaN ? 0 : min(max($0, 0), 1) }
    }

    /// The tone of the status dot before the value; nil draws no dot.
    public var dotTone: DKTone? {
        tone
    }

    /// The tone whose ink colors the value; nil keeps the body ink.
    public var valueTone: DKTone? {
        switch tone {
        case .warning, .danger: tone
        default: nil
        }
    }
}

/// A key-value row's button, kept so the row stays `Hashable` and `Sendable`.
/// Two actions are equal when they look the same (the closure is not compared).
/// The closure only ever runs on the main actor, from the button that draws it.
struct DKKeyValueAction: Hashable, @unchecked Sendable {
    let spec: DKButtonSpec

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.spec.id == rhs.spec.id && lhs.spec.label == rhs.spec.label && lhs.spec.glyph == rhs.spec.glyph
            && lhs.spec.variant == rhs.spec.variant && lhs.spec.size == rhs.spec.size
            && lhs.spec.isEnabled == rhs.spec.isEnabled && lhs.spec.help == rhs.spec.help
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(spec.id)
        hasher.combine(spec.label)
        hasher.combine(spec.isEnabled)
    }
}

// MARK: - List item

/// One row of a section list (`.dk-list__row`): an installed Core Bundle, a
/// prepared restore file, the Host Setup summary. A glyph tile, a title with
/// badges, lines of detail under it, a trailing value and trailing actions,
/// all optional but the title.
public struct DKListItem: Identifiable {
    /// A status pill after the title.
    public struct Badge: Hashable, Sendable {
        public var text: String
        public var tone: DKTone

        public init(_ text: String, tone: DKTone = .neutral) {
            self.text = text
            self.tone = tone
        }
    }

    /// A line of detail under the title: muted 12pt text, optionally monospaced
    /// or carrying a tone. A string literal is a plain line.
    public struct Line: Hashable, Sendable, ExpressibleByStringLiteral {
        public var text: String
        public var monospaced: Bool
        public var tone: DKTone?

        public init(_ text: String, monospaced: Bool = false, tone: DKTone? = nil) {
            self.text = text
            self.monospaced = monospaced
            self.tone = tone
        }

        public init(stringLiteral value: String) {
            self.init(value)
        }
    }

    /// Stable identity in a `ForEach`; the title unless given. Give one when two
    /// rows can share a title.
    public var id: String
    public var glyph: DKGlyph?
    /// Colors the glyph; nil keeps it secondary ink.
    public var glyphTone: DKTone?
    public var title: String
    /// Set the title in monospace, as bundle versions are.
    public var monospacedTitle: Bool
    public var badges: [Badge]
    public var lines: [Line]
    /// Trailing figure, such as a size: "38.1 GB".
    public var value: String?
    /// Trailing buttons, drawn small.
    public var actions: [DKButtonSpec]

    public init(
        _ title: String,
        glyph: DKGlyph? = nil,
        glyphTone: DKTone? = nil,
        monospacedTitle: Bool = false,
        badges: [Badge] = [],
        lines: [Line] = [],
        value: String? = nil,
        actions: [DKButtonSpec] = [],
        id: String? = nil,
    ) {
        self.id = id ?? title
        self.glyph = glyph
        self.glyphTone = glyphTone
        self.title = title
        self.monospacedTitle = monospacedTitle
        self.badges = badges
        self.lines = lines
        self.value = value
        self.actions = actions
    }
}

// MARK: - Tone text

extension DKTone {
    /// The color of text that carries this tone on a plain ground. `ink` is the
    /// text on the tone's own surface, which for `accent` is white.
    var sectionsTextColor: Color {
        self == .accent ? color : ink
    }
}
