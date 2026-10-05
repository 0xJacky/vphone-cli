import SwiftUI

// MARK: - Form row

/// A settings row (`.dk-form-row`): a fixed-width label column in secondary ink
/// and the control beside it, at least 44pt tall. Used inside a `DKCard` or a
/// `DKSection` in sheets, Settings and Machine Settings; the card draws the
/// dividers between rows.
///
/// By default the control hugs the trailing edge, as a switch or a stepper
/// does. In `fill` mode it starts at the label column and stretches, as a text
/// field or a path does.
///
/// ```swift
/// DKSection("General") {
///     DKFormRow("Name", fill: true) { TextField("Name", text: $name) }
///     DKFormRow("Rotation Lock") { Toggle("Rotation Lock", isOn: $locked).labelsHidden() }
/// }
/// ```
///
/// The label is the control's accessibility label: the row is a
/// `LabeledContent`.
public struct DKFormRow<Control: View>: View {
    let label: String
    let fill: Bool
    let labelWidth: CGFloat
    let control: Control

    /// - Parameters:
    ///   - label: The text in the label column.
    ///   - fill: Stretch the control across the row instead of hugging the trailing edge.
    ///   - labelWidth: The label column's width; 110pt in the design.
    public init(_ label: String, fill: Bool = false, labelWidth: CGFloat = 110, @ViewBuilder control: () -> Control) {
        self.label = label
        self.fill = fill
        self.labelWidth = labelWidth
        self.control = control()
    }

    public var body: some View {
        LabeledContent {
            control
        } label: {
            Text(label)
        }
        .labeledContentStyle(DKSectionsFormRowStyle(fill: fill, labelWidth: labelWidth))
    }
}

/// Lays a `LabeledContent` out as a DesignKit form row.
struct DKSectionsFormRowStyle: LabeledContentStyle {
    var fill: Bool
    var labelWidth: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DK.Space.s3) {
            configuration.label
                .foregroundStyle(DK.Palette.inkSecondary)
                .frame(width: labelWidth, alignment: .leading)
            HStack(spacing: 10) {
                configuration.content
            }
            .frame(maxWidth: .infinity, alignment: fill ? .leading : .trailing)
        }
        .font(DK.Typeface.body)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 14)
    }
}
