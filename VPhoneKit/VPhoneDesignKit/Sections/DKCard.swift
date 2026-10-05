import SwiftUI

// MARK: - Card

/// How a card arranges what it holds. `rows` stacks full-width rows with a soft
/// divider between each pair (`.dk-card` holding `.dk-kv`, `.dk-list` or form
/// rows); `padded` insets free content by 12 by 14 points and spaces it by 10
/// (`.dk-card__pad`).
public enum DKCardLayout: String, Sendable, CaseIterable, Hashable {
    case rows
    case padded
}

/// The raised card every section body sits in: the raised surface, a 1pt line
/// border and the card radius, with its contents clipped to the rounded shape.
///
/// In the `rows` layout each direct child is a row: `DKKeyValueRow`,
/// `DKListRow`, `DKFormRow` or any view. Children of a `ForEach` count one by
/// one, so a divider lands between every row.
///
/// ```swift
/// DKCard {
///     DKFormRow("Name") { TextField("Name", text: $name) }
///     DKFormRow("Rotation Lock") { Toggle("", isOn: $locked) }
/// }
/// ```
///
/// Inside a sheet the card takes the window color instead; set it with
/// `dkCardFill(_:)`.
public struct DKCard<Content: View>: View {
    let layout: DKCardLayout
    let fillsHeight: Bool
    let content: Content

    @Environment(\.dkCardFill) private var fill

    /// - Parameters:
    ///   - layout: Divided rows (the default) or padded free content.
    ///   - fillsHeight: Stretch to the height offered, as a growing section's card does.
    public init(_ layout: DKCardLayout = .rows, fillsHeight: Bool = false, @ViewBuilder content: () -> Content) {
        self.layout = layout
        self.fillsHeight = fillsHeight
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
        arranged
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background(fill)
            .clipShape(shape)
            .overlay(shape.strokeBorder(DK.Palette.line, lineWidth: DK.Metric.hairline))
    }

    @ViewBuilder
    private var arranged: some View {
        switch layout {
        case .rows:
            Group(subviews: content) { rows in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            DKSectionsDivider()
                        }
                        row.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .padded:
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.vertical, DK.Space.s3)
            .padding(.horizontal, 14)
        }
    }
}

// MARK: - Fill

public extension EnvironmentValues {
    /// The ground of `DKCard`s below this view: the raised surface by default,
    /// the window color inside sheets.
    @Entry var dkCardFill: Color = DK.Palette.surfaceRaised
}

public extension View {
    /// Sets the ground of the `DKCard`s inside this view. Sheets pass
    /// `DK.Palette.window` so their cards read against the sheet chrome.
    func dkCardFill(_ fill: Color) -> some View {
        environment(\.dkCardFill, fill)
    }
}

// MARK: - Divider

/// The soft 1pt line between a card's rows.
struct DKSectionsDivider: View {
    var color: Color = DK.Palette.dividerSoft

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: DK.Metric.hairline)
            .accessibilityHidden(true)
    }
}
