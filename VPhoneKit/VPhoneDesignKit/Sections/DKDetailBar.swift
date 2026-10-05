import SwiftUI

// MARK: - Layout

/// How a detail bar arranges its parts.
///
/// `column` stacks head, facts, extra content and actions top to bottom and never
/// wraps: the bar under the Processes, Services and Crash Logs tables.
///
/// `row` sets them side by side and wraps onto further lines when they do not
/// fit: the one-line bar under the Keychain and Preferences tables. The head
/// starts at 260pt and takes one share of the spare width, the facts start at
/// 360pt and take two, extra content starts at 420pt and takes three, and the
/// actions keep their natural width.
public enum DKDetailBarLayout: String, Sendable, CaseIterable, Hashable {
    case row
    case column

    /// Whether parts move onto a further line when the bar is too narrow.
    public var wraps: Bool {
        self == .row
    }

    /// The gap between parts on one line (row) or between stacked parts (column).
    public var spacing: CGFloat {
        self == .row ? DK.Space.s4 : 10
    }

    /// The gap between wrapped lines.
    public var lineSpacing: CGFloat {
        self == .row ? DK.Space.s2 : 10
    }

    static let headFlex = DKSectionsFlexItem(basis: 260, grow: 1)
    static let factsFlex = DKSectionsFlexItem(basis: 360, grow: 2)
    static let contentFlex = DKSectionsFlexItem(basis: 420, grow: 3)
}

// MARK: - Detail bar

/// The bar under a table that describes the selected item (`.dk-detail`): a
/// title with a monospaced subtitle, a muted note, a grid of facts, optional
/// extra content, and trailing actions. It sits on the raised surface with a
/// divider along its top edge.
///
/// ```swift
/// DKDetailBar(
///     "SpringBoard", subtitle: "pid 61",
///     facts: [DKKeyValue("Bundle ID", "com.apple.springboard"), DKKeyValue("PPID", "1")]
/// )
///
/// DKDetailBar(
///     "Password", subtitle: account, note: "Value is protected.",
///     actions: [DKButtonSpec("Delete…", glyph: .trash, variant: .danger)],
///     layout: .row
/// )
/// ```
///
/// Facts are identifiers and figures, so their values are always monospaced; a
/// fact with a tone gets a status dot. With no title, a note alone still shows,
/// as the hint of a bar with nothing selected:
/// `DKDetailBar(note: "Select an item to copy, reveal, edit or delete it.")`.
public struct DKDetailBar<Content: View>: View {
    let title: String?
    let subtitle: String?
    let note: String?
    let facts: [DKKeyValue]
    let actions: [DKButtonSpec]
    let layout: DKDetailBarLayout
    let content: Content

    /// - Parameters:
    ///   - title: The selected item's name.
    ///   - subtitle: A monospaced, muted identifier after the title: "pid 61".
    ///   - note: A muted line under the title.
    ///   - facts: Key-value facts, laid out in columns at least 180pt wide.
    ///   - actions: Buttons at the end of the bar.
    ///   - layout: Stacked (`column`, the default) or side by side (`row`).
    ///   - content: Anything else the bar shows, placed between the facts and the actions.
    public init(
        _ title: String? = nil,
        subtitle: String? = nil,
        note: String? = nil,
        facts: [DKKeyValue] = [],
        actions: [DKButtonSpec] = [],
        layout: DKDetailBarLayout = .column,
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.note = note
        self.facts = facts
        self.actions = actions
        self.layout = layout
        self.content = content()
    }

    public var body: some View {
        DKZeroWidthProbeLayout {
            arranged
        }
        .font(DK.Typeface.body)
            .foregroundStyle(DK.Palette.ink)
            .padding(.vertical, 14)
            .padding(.horizontal, DK.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DK.Palette.surfaceRaised)
            .overlay(alignment: .top) {
                DKSectionsDivider(color: DK.Palette.divider)
            }
    }

    @ViewBuilder
    private var arranged: some View {
        switch layout {
        case .row:
            DKSectionsFlexLayout(horizontalSpacing: layout.spacing, verticalSpacing: layout.lineSpacing) {
                if hasHead {
                    head.dkSectionsFlex(basis: DKDetailBarLayout.headFlex.basis, grow: DKDetailBarLayout.headFlex.grow)
                }
                if !facts.isEmpty {
                    factsGrid.dkSectionsFlex(basis: DKDetailBarLayout.factsFlex.basis, grow: DKDetailBarLayout.factsFlex.grow)
                }
                if hasContent {
                    content.dkSectionsFlex(basis: DKDetailBarLayout.contentFlex.basis, grow: DKDetailBarLayout.contentFlex.grow)
                }
                if !actions.isEmpty {
                    actionButtons
                }
            }
        case .column:
            VStack(alignment: .leading, spacing: layout.spacing) {
                if hasHead {
                    head
                }
                if !facts.isEmpty {
                    factsGrid
                }
                if hasContent {
                    content
                }
                if !actions.isEmpty {
                    actionButtons
                }
            }
        }
    }

    /// A note alone makes a head too: the hint a bar shows with nothing selected.
    private var hasHead: Bool {
        !(title ?? "").isEmpty || !(note ?? "").isEmpty
    }

    private var hasContent: Bool {
        Content.self != EmptyView.self
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title, !title.isEmpty {
                DKSectionsFlexLayout(horizontalSpacing: 10, verticalSpacing: DK.Space.s1) {
                    Text(title)
                        .font(DK.Typeface.bodyStrong)
                        .textSelection(.enabled)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(DK.Typeface.mono)
                            .foregroundStyle(DK.Palette.muted)
                            .textSelection(.enabled)
                    }
                }
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var factsGrid: some View {
        DKSectionsFactsLayout {
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.key)
                        .font(DK.Typeface.caption)
                        .foregroundStyle(DK.Palette.muted)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let tone = fact.dotTone {
                            DKStatusDot(tone)
                        }
                        Text(fact.value)
                            .font(DK.Typeface.mono)
                            .foregroundStyle(fact.valueTone?.sectionsTextColor ?? DK.Palette.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(fact.help ?? "")
                        if let action = fact.action {
                            DKButton(DKListRow.small(action))
                        }
                    }
                    if let progress = fact.visibleProgress {
                        DKProgress(value: progress, tone: fact.tone ?? .accent, thin: true, label: fact.key)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var actionButtons: some View {
        DKSectionsFlexLayout(horizontalSpacing: DK.Space.s2, verticalSpacing: DK.Space.s2) {
            ForEach(actions) { DKButton($0) }
        }
    }
}

public extension DKDetailBar where Content == EmptyView {
    /// A detail bar without extra content.
    init(
        _ title: String? = nil,
        subtitle: String? = nil,
        note: String? = nil,
        facts: [DKKeyValue] = [],
        actions: [DKButtonSpec] = [],
        layout: DKDetailBarLayout = .column,
    ) {
        self.init(title, subtitle: subtitle, note: note, facts: facts, actions: actions, layout: layout) {
            EmptyView()
        }
    }
}
