import Foundation
import SwiftUI
import VPhoneDesignKit

// Rows the machine sheets share, built from DesignKit parts: a stepper laid
// out as the design draws it, a switch row whose label takes the width, and a
// section whose footnote may be any view.

// MARK: - Stepper row

/// A form row with the value and a minus and a plus button, as the design draws
/// hardware. VoiceOver and the keyboard see one native stepper.
struct VPhoneLaunchpadStepperRow: View {
    let label: String
    let value: String
    @Binding var number: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        DKFormRow(label) {
            Text(verbatim: value)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            DKButton(DKButtonSpec("−", glyph: .minus, size: .icon, isEnabled: number - step >= range.lowerBound, help: "") {
                number = max(range.lowerBound, number - step)
            })
            DKButton(DKButtonSpec("+", glyph: .plus, size: .icon, isEnabled: number + step <= range.upperBound, help: "") {
                number = min(range.upperBound, number + step)
            })
        }
        .accessibilityRepresentation {
            Stepper(value: $number, in: range, step: step) {
                Text(verbatim: label)
            }
            .accessibilityValue(Text(verbatim: value))
        }
    }
}

// MARK: - Switch row

/// A card row with its label across the width and a DesignKit switch at the
/// trailing edge, for labels longer than a form row's label column.
struct VPhoneLaunchpadSwitchRow<Label: View>: View {
    @Binding var isOn: Bool
    @ViewBuilder let label: Label

    var body: some View {
        HStack(spacing: DK.Space.s3) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            Toggle(isOn: $isOn) {
                label
            }
            .toggleStyle(DKSwitchToggleStyle())
            .labelsHidden()
        }
        .font(DK.Typeface.body)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 14)
    }
}

// MARK: - Plain card row

/// A card row of free content, inset as a form row is: a loading line, an
/// error, an explanation.
struct VPhoneLaunchpadCardRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: DK.Space.s2) {
            content
        }
        .font(DK.Typeface.body)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, DK.Space.s1)
    }
}

/// A muted line in a card row, with an optional warning glyph.
struct VPhoneLaunchpadCardMessage: View {
    let text: Text
    var isWarning = false

    var body: some View {
        VPhoneLaunchpadCardRow {
            if isWarning {
                DKIcon(.warning, size: 14)
                    .foregroundStyle(DK.Palette.warning)
            }
            text
                .foregroundStyle(DK.Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// A spinner and a muted line, while something is read.
struct VPhoneLaunchpadCardLoading: View {
    let text: Text

    var body: some View {
        VPhoneLaunchpadCardRow {
            ProgressView().controlSize(.small)
            text.foregroundStyle(DK.Palette.muted)
        }
    }
}

// MARK: - Section

/// A `DKSection`, with a control beside the title as the Firmware section's
/// source switch, whose footnote may be any view: a warning with its glyph.
struct VPhoneLaunchpadSheetSection<Content: View, Trailing: View, Footnote: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content
    @ViewBuilder let footnote: Footnote

    init(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footnote: () -> Footnote,
    ) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
        self.footnote = footnote()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DK.Space.s2) {
            DKSection(title) {
                content
            } headAccessory: {
                trailing
            }
            VStack(alignment: .leading, spacing: DK.Space.s1) {
                footnote
            }
            .font(DK.Typeface.caption)
            .lineSpacing(3)
            .foregroundStyle(DK.Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DK.Space.s1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension VPhoneLaunchpadSheetSection where Trailing == EmptyView {
    init(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footnote: () -> Footnote,
    ) {
        self.init(title, trailing: { EmptyView() }, content: content, footnote: footnote)
    }
}

/// A red line under a field: why the sheet cannot go ahead.
struct VPhoneLaunchpadFieldProblem: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(DK.Typeface.caption)
            .foregroundStyle(DK.Palette.danger)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DK.Space.s1)
    }
}
