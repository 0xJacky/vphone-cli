import SwiftUI

// MARK: - Model

/// What sits before a title cell's text: a design glyph, or a status dot.
public enum DKTableCellLeading: Hashable, Sendable {
    /// An 18pt glyph, in the tone's color or the row's ink when `tone` is nil.
    case glyph(DKGlyph, tone: DKTone? = nil)
    /// A status dot.
    case dot(DKTone)
}

/// The design's table cell kinds. Render one with `DKTableCellView`, inside a
/// `DKDataTable` or a system `TableColumn`:
///
/// ```swift
/// TableColumn("State") { machine in
///     DKTableCellView(.status(.success, "Running since 09:41"))
/// }
/// ```
public enum DKTableCell: Hashable, Sendable {
    /// Body text.
    case text(String)
    /// Monospaced text: versions, identifiers, paths.
    case mono(String)
    /// Secondary text: resources, counts, notes.
    case muted(String)
    /// Semibold body text.
    case strong(String)
    /// A title over an optional subtitle, with an optional leading glyph or dot.
    /// The title is semibold unless `strong` is false.
    case title(
        String,
        subtitle: String? = nil,
        subtitleMonospaced: Bool = false,
        leading: DKTableCellLeading? = nil,
        strong: Bool = true
    )
    /// A status dot and its text, with an optional progress fraction drawn as a thin
    /// bar under the text. Let the text carry the number ("Downloading 63%").
    case status(DKTone, String, progress: Double? = nil)
    /// A badge.
    case badge(DKTone, String)
    /// A glyph alone. `label` is what VoiceOver reads and the tooltip shows.
    case icon(DKGlyph, tone: DKTone? = nil, label: String)
    /// A usage bar filled to `fraction` (clamped to 0...1) with its value after it ("38 GB").
    case bar(Double, tone: DKTone = .accent, value: String)
    /// Any cell with a small warning triangle after it; `warning` is the tooltip.
    indirect case warned(DKTableCell, warning: String)

    /// This cell with a warning triangle after it, or unchanged when `message` is nil.
    public func warning(_ message: String?) -> DKTableCell {
        guard let message else {
            return self
        }
        return .warned(self, warning: message)
    }

    /// The warning this cell carries, if any.
    public var warningMessage: String? {
        if case let .warned(_, warning) = self {
            return warning
        }
        return nil
    }

    /// What VoiceOver reads for the cell. Also usable as the cell's sort or copy text.
    public var accessibilityText: String {
        switch self {
        case let .text(text), let .mono(text), let .muted(text), let .strong(text), let .badge(_, text):
            return text
        case let .title(title, subtitle, _, _, _):
            return [title, subtitle].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: ", ")
        case let .status(_, text, progress):
            guard let progress, !text.contains("%") else {
                return text
            }
            return "\(text), \(Self.percent(progress))%"
        case let .icon(_, _, label):
            return label
        case let .bar(fraction, _, value):
            return "\(value), \(Self.percent(fraction))%"
        case let .warned(cell, warning):
            return "\(cell.accessibilityText), \(warning)"
        }
    }

    /// `fraction` limited to 0...1; NaN reads as empty.
    public static func clampedFraction(_ fraction: Double) -> Double {
        guard !fraction.isNaN else {
            return 0
        }
        return min(max(fraction, 0), 1)
    }

    /// `fraction` as a whole percent, after clamping.
    static func percent(_ fraction: Double) -> Int {
        Int((clampedFraction(fraction) * 100).rounded())
    }
}

// MARK: - View

/// Draws one `DKTableCell`. Text truncates at the tail; the cell fills the width
/// its column gives it only as far as its content needs, so align it with a frame
/// (`DKDataTable` does).
public struct DKTableCellView: View {
    public let cell: DKTableCell

    public init(_ cell: DKTableCell) {
        self.cell = cell
    }

    public var body: some View {
        DKTableCellContent(cell: cell)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cell.accessibilityText)
    }
}

/// The drawing behind `DKTableCellView`, without the accessibility wrapper, so a
/// warned cell can draw the cell it wraps.
struct DKTableCellContent: View {
    let cell: DKTableCell

    var body: some View {
        switch cell {
        case let .text(text):
            line(text, font: DK.Typeface.body, color: DK.Palette.ink)
        case let .mono(text):
            line(text, font: DK.Typeface.mono, color: DK.Palette.ink)
        case let .muted(text):
            line(text, font: DK.Typeface.body, color: DK.Palette.inkSecondary)
        case let .strong(text):
            line(text, font: DK.Typeface.bodyStrong, color: DK.Palette.ink)
        case let .title(title, subtitle, subtitleMonospaced, leading, strong):
            DKTableTitleCell(
                title: title,
                subtitle: subtitle,
                subtitleMonospaced: subtitleMonospaced,
                leading: leading,
                strong: strong,
            )
        case let .status(tone, text, progress):
            DKTableStatusCell(tone: tone, text: text, progress: progress)
        case let .badge(tone, text):
            DKBadge(text, tone: tone)
        case let .icon(glyph, tone, label):
            DKIcon(glyph, size: 15)
                .foregroundStyle(tone?.color ?? DK.Palette.ink)
                .help(label)
        case let .bar(fraction, tone, value):
            HStack(spacing: 10) {
                DKTableMeter(fraction: fraction, tone: tone, height: 6)
                    .frame(minWidth: 40)
                Text(value)
                    .font(DK.Typeface.body)
                    .monospacedDigit()
                    .foregroundStyle(DK.Palette.ink)
                    .lineLimit(1)
                    .frame(width: 48, alignment: .trailing)
            }
        case let .warned(inner, warning):
            HStack(spacing: DK.Space.s1) {
                DKTableCellContent(cell: inner)
                DKIcon(.warning, size: 13)
                    .foregroundStyle(DK.Palette.warning)
                    .help(warning)
            }
        }
    }

    private func line(_ text: String, font: Font, color: Color) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

// MARK: - Parts

struct DKTableTitleCell: View {
    let title: String
    let subtitle: String?
    let subtitleMonospaced: Bool
    let leading: DKTableCellLeading?
    let strong: Bool

    var body: some View {
        HStack(spacing: DK.Space.s3) {
            switch leading {
            case let .glyph(glyph, tone):
                DKIcon(glyph, size: 18)
                    .foregroundStyle(tone?.color ?? DK.Palette.ink)
            case let .dot(tone):
                DKStatusDot(tone)
            case nil:
                EmptyView()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(strong ? DK.Typeface.bodyStrong : DK.Typeface.body)
                    .foregroundStyle(DK.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(subtitleMonospaced ? DK.Typeface.mono : DK.Typeface.caption)
                        .foregroundStyle(DK.Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}

struct DKTableStatusCell: View {
    let tone: DKTone
    let text: String
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s1) {
            HStack(spacing: 6) {
                DKStatusDot(tone)
                Text(text)
                    .font(DK.Typeface.body)
                    .foregroundStyle(DK.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if let progress {
                DKTableMeter(fraction: progress, tone: tone, height: 4)
            }
        }
    }
}

/// A rounded track filled to a fraction: the usage bar and the status cell's progress.
struct DKTableMeter: View {
    let fraction: Double
    let tone: DKTone
    let height: CGFloat

    var body: some View {
        let fill = DKTableCell.clampedFraction(fraction)
        Capsule()
            .fill(DK.Palette.track)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tone.color)
                        .frame(width: proxy.size.width * fill)
                }
            }
            .clipShape(Capsule())
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
