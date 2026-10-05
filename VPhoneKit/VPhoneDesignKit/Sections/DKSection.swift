import SwiftUI

// MARK: - Section

/// A titled group of a page (`.dk-section`): a 12pt semibold muted title with an
/// optional note, accessory view and accessory button on the right, a card body,
/// and an optional footnote under the card.
///
/// The body is key-value rows, list items, or any content:
///
/// ```swift
/// DKSection("Hardware", rows: [DKKeyValue("CPU", "8 cores"), DKKeyValue("Memory", "8 GB")])
///
/// DKSection("Installed", note: "New machines use the default.", items: bundles)
///
/// DKSection("Display") {
///     DKFormRow("Scale") { Picker(...) }
/// }
///
/// DKSection("Processes") {
///     ProcessRows()
/// } headAccessory: {
///     DKSegmented("Show", selection: $filter, options: filters)
/// }
/// ```
///
/// Custom content goes into a `DKCard` with dividers between its rows; pass
/// `card: false` to place it bare (a log, a banner, a padded card of your own).
///
/// A footnote is plain text, or an `AttributedString` for emphasis and links;
/// `DKSection.markdown(_:)` builds one from inline Markdown.
public struct DKSection<Content: View>: View {
    let title: String?
    let note: String?
    let accessory: DKButtonSpec?
    let footnote: AttributedString?
    let grow: Bool
    let card: Bool
    let headAccessory: AnyView?
    let content: Content

    /// - Parameters:
    ///   - title: The section title; nil or empty hides the head unless a note or accessory is set.
    ///   - note: Muted text at the right of the head.
    ///   - accessory: A button at the right of the head, drawn as a plain link: "Change…".
    ///   - footnote: Muted text under the card.
    ///   - attributedFootnote: Muted styled text under the card, with links in
    ///     the link color; used in place of `footnote` when both are set.
    ///   - grow: Take the height left in the parent; the card stretches with it.
    ///   - card: Put the content in a divided `DKCard` (the default) or place it bare.
    public init(
        _ title: String? = nil,
        note: String? = nil,
        accessory: DKButtonSpec? = nil,
        footnote: String? = nil,
        attributedFootnote: AttributedString? = nil,
        grow: Bool = false,
        card: Bool = true,
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        self.note = note
        self.accessory = accessory
        self.footnote = attributedFootnote ?? footnote.map { AttributedString($0) }
        self.grow = grow
        self.card = card
        headAccessory = nil
        self.content = content()
    }

    /// A section with a view at the right of its head, before the note and
    /// the accessory button: a segmented control, a switch, a menu button.
    public init(
        _ title: String? = nil,
        note: String? = nil,
        accessory: DKButtonSpec? = nil,
        footnote: String? = nil,
        attributedFootnote: AttributedString? = nil,
        grow: Bool = false,
        card: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder headAccessory: () -> some View,
    ) {
        self.title = title
        self.note = note
        self.accessory = accessory
        self.footnote = attributedFootnote ?? footnote.map { AttributedString($0) }
        self.grow = grow
        self.card = card
        self.headAccessory = AnyView(headAccessory())
        self.content = content()
    }

    /// Inline Markdown as a footnote: emphasis, code and links, whitespace kept.
    /// Text that does not parse comes back as it is.
    public nonisolated static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    public var body: some View {
        DKZeroWidthProbeLayout {
            VStack(alignment: .leading, spacing: DK.Space.s2) {
                if hasHead {
                    head
                }
                if card {
                    DKCard(fillsHeight: grow) {
                        content
                    }
                } else {
                    content
                        .frame(maxWidth: .infinity, maxHeight: grow ? .infinity : nil, alignment: .topLeading)
                }
                if let footnote, !footnote.characters.isEmpty {
                    Text(footnote)
                        .font(DK.Typeface.caption)
                        .lineSpacing(3)
                        .foregroundStyle(DK.Palette.muted)
                        .tint(DK.Palette.link)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DK.Space.s1)
                        .padding(.top, DK.Space.s1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: grow ? .infinity : nil, alignment: .topLeading)
    }

    private var hasHead: Bool {
        !(title ?? "").isEmpty || !(note ?? "").isEmpty || accessory != nil || headAccessory != nil
    }

    private var head: some View {
        DKSectionsFlexLayout(horizontalSpacing: DK.Space.s3, verticalSpacing: DK.Space.s1) {
            Text(title ?? "")
                .font(DK.Typeface.sectionTitle)
                .foregroundStyle(DK.Palette.muted)
                .accessibilityAddTraits(.isHeader)
                .dkSectionsFlex(grow: 1)
            if let headAccessory {
                headAccessory
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)
            }
            if let accessory {
                DKButton(Self.plain(accessory))
                    .frame(height: 16)
            }
        }
        .padding(.horizontal, DK.Space.s1)
    }

    static func plain(_ spec: DKButtonSpec) -> DKButtonSpec {
        var spec = spec
        spec.variant = .plain
        return spec
    }
}

public extension DKSection where Content == ForEach<[DKKeyValue], String, DKKeyValueRow> {
    /// A section of key-value rows.
    init(
        _ title: String? = nil,
        note: String? = nil,
        accessory: DKButtonSpec? = nil,
        footnote: String? = nil,
        attributedFootnote: AttributedString? = nil,
        grow: Bool = false,
        rows: [DKKeyValue],
    ) {
        self.init(title, note: note, accessory: accessory, footnote: footnote, attributedFootnote: attributedFootnote, grow: grow) {
            ForEach(rows) { DKKeyValueRow($0) }
        }
    }
}

public extension DKSection where Content == ForEach<[DKListItem], String, DKListRow> {
    /// A section of list items.
    init(
        _ title: String? = nil,
        note: String? = nil,
        accessory: DKButtonSpec? = nil,
        footnote: String? = nil,
        attributedFootnote: AttributedString? = nil,
        grow: Bool = false,
        items: [DKListItem],
    ) {
        self.init(title, note: note, accessory: accessory, footnote: footnote, attributedFootnote: attributedFootnote, grow: grow) {
            ForEach(items) { DKListRow($0) }
        }
    }
}

// MARK: - Key-value row

/// A key-value row (`.dk-kv__row`): the muted key on the left, the value on the
/// right, 32pt tall, with a status dot when the row has a tone, a thin bar under
/// the value when it has progress, and a small button after it when it has an
/// action.
public struct DKKeyValueRow: View {
    let row: DKKeyValue

    public init(_ row: DKKeyValue) {
        self.row = row
    }

    public var body: some View {
        HStack(spacing: DK.Space.s3) {
            Text(row.key)
                .foregroundStyle(DK.Palette.muted)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: DK.Space.s1) {
                HStack(spacing: DK.Space.s2) {
                    if let tone = row.dotTone {
                        DKStatusDot(tone)
                    }
                    Text(row.value)
                        .font(row.monospaced ? DK.Typeface.mono : DK.Typeface.body)
                        .foregroundStyle(row.valueTone?.sectionsTextColor ?? DK.Palette.ink)
                        .lineLimit(1)
                        .truncationMode(row.monospaced ? .middle : .tail)
                        .textSelection(.enabled)
                        .help(row.help ?? "")
                }
                if let progress = row.visibleProgress {
                    DKProgress(value: progress, tone: row.tone ?? .accent, thin: true, label: row.key)
                        .frame(width: DKKeyValueRow.progressWidth)
                }
            }
            .padding(.vertical, row.visibleProgress == nil ? 0 : 6)
            if let action = row.action {
                DKButton(DKListRow.small(action))
            }
        }
        .font(DK.Typeface.body)
        .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    /// The width of a row's progress bar.
    static let progressWidth: CGFloat = 140
}

// MARK: - List row

/// A list row (`.dk-list__row`): glyph tile, title with badges, detail lines,
/// trailing value and actions. The text takes the spare width; the value and
/// the actions wrap under it when the row is narrow.
public struct DKListRow: View {
    let item: DKListItem

    public init(_ item: DKListItem) {
        self.item = item
    }

    public var body: some View {
        DKSectionsFlexLayout(horizontalSpacing: DK.Space.s4, verticalSpacing: DK.Space.s3) {
            if let glyph = item.glyph {
                DKIcon(glyph, size: 20)
                    .foregroundStyle(item.glyphTone?.color ?? DK.Palette.inkSecondary)
                    .frame(width: 36, height: 36)
                    .background(DK.Palette.window, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(DK.Palette.line, lineWidth: DK.Metric.hairline))
            }
            text
                .dkSectionsFlex(basis: 240, grow: 1)
            if let value = item.value, !value.isEmpty {
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(DK.Palette.inkSecondary)
            }
            if !item.actions.isEmpty {
                DKSectionsFlexLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(item.actions) { DKButton(Self.small($0)) }
                }
            }
        }
        .font(DK.Typeface.body)
        .foregroundStyle(DK.Palette.ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: DK.Space.s1) {
            DKSectionsFlexLayout(horizontalSpacing: DK.Space.s2, verticalSpacing: DK.Space.s1) {
                Text(item.title)
                    .font(item.monospacedTitle ? .system(size: 12, weight: .semibold, design: .monospaced) : DK.Typeface.bodyStrong)
                    .textSelection(.enabled)
                ForEach(Array(item.badges.enumerated()), id: \.offset) { _, badge in
                    DKBadge(badge.text, tone: badge.tone)
                }
            }
            ForEach(Array(item.lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(line.monospaced ? DK.Typeface.mono : DK.Typeface.caption)
                    .foregroundStyle(line.tone?.sectionsTextColor ?? DK.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func small(_ spec: DKButtonSpec) -> DKButtonSpec {
        var spec = spec
        if spec.size == .regular {
            spec.size = .small
        }
        return spec
    }
}
