import SwiftUI
import VPhoneDesignKit

/// The frame every sheet shares, drawn as DesignKit's `DKSheet` is: a title on
/// the sheet's white, the content, and a footer of buttons under a rule. A
/// sheet's toolbar only lays its buttons along the bottom and shows no title,
/// so the sheet had no head.
///
/// Sheets whose buttons are `DKSheetAction`s use `DKSheet` itself, which also
/// sizes to its content and scrolls past a maximum height. This one keeps a
/// `Text` title and view-builder buttons for sheets that lay out their own
/// content and controls.
struct VPhoneLaunchpadSheet<Content: View, Accessory: View, Actions: View>: View {
    let title: Text
    /// A line under the title, as `DKSheet`'s subtitle.
    var subtitle: Text?
    /// A line in the footer before the trailing buttons: what the primary
    /// action will do, or why it cannot.
    var note: DKSheetNote?
    @ViewBuilder let content: Content
    /// Secondary buttons or status, on the leading side of the footer.
    @ViewBuilder let accessory: Accessory
    /// Cancel and confirm, on the trailing side of the footer.
    @ViewBuilder let actions: Actions

    init(
        _ title: Text,
        subtitle: Text? = nil,
        note: DKSheetNote? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder actions: () -> Actions,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.note = note
        self.content = content()
        self.accessory = accessory()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(DK.Typeface.sheetTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    subtitle
                        .foregroundStyle(DK.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .padding(.horizontal, DKSheetMetrics.horizontalPadding)
            .padding(.bottom, DK.Space.s3)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: DK.Space.s2) {
                accessory
                if let note, !note.text.isEmpty {
                    Text(verbatim: note.text)
                        .font(DK.Typeface.caption)
                        .foregroundStyle(note.tone.color)
                        .lineLimit(2)
                }
                Spacer(minLength: DK.Space.s4)
                actions
            }
            .padding(.horizontal, DKSheetMetrics.horizontalPadding)
            .padding(.vertical, DK.Space.s3)
            .overlay(alignment: .top) {
                VPhoneLaunchpadSheetRule()
            }
        }
        .background(DK.Palette.window)
        .vphoneLaunchpadSheetChrome()
    }
}

extension VPhoneLaunchpadSheet where Accessory == EmptyView {
    init(
        _ title: Text,
        subtitle: Text? = nil,
        note: DKSheetNote? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions,
    ) {
        self.init(title, subtitle: subtitle, note: note, content: content, accessory: { EmptyView() }, actions: actions)
    }
}

/// The one-point line between a sheet's body and its footer, in the divider
/// color `DKSheet` draws it in.
struct VPhoneLaunchpadSheetRule: View {
    var body: some View {
        DK.Palette.divider
            .frame(height: DK.Metric.hairline)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// A segmented control over a sheet's form that shows one page of it at a
/// time, so a sheet with several groups of settings stays short instead of
/// growing past the screen. The sheet resizes to the page, as a settings
/// window does. A `DKSheet` puts a `DKSegmented` in its pages slot instead.
struct VPhoneLaunchpadSheetPages<Page: Hashable, Labels: View>: View {
    @Binding var selection: Page
    @ViewBuilder let labels: Labels

    var body: some View {
        Picker(selection: $selection) {
            labels
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .padding(.top, 16)
    }
}

// MARK: - DKSheet

extension View {
    /// What every sheet in Launchpad shares beyond `DKSheet`: cards on the
    /// sheet's own white, as the design draws them inside sheets.
    func vphoneLaunchpadSheetChrome() -> some View {
        dkCardFill(DK.Palette.window)
    }
}
