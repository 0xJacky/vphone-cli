import SwiftUI
import VPhoneDesignKit

// MARK: - Columns

/// Two independent columns of sections (`.dk-columns`): each column stacks its
/// own sections without lining them up with the other's, and the last section
/// of each column can grow so both end together. Below two column widths the
/// trailing column moves under the leading one.
struct VPhoneGuestToolColumns<Leading: View, Trailing: View>: View {
    /// The narrowest a column gets before the page drops to one column.
    var minimumColumnWidth: CGFloat = 360
    var spacing: CGFloat = DK.Space.s5
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @State private var width: CGFloat = 0

    var body: some View {
        Group {
            if width == 0 || width >= minimumColumnWidth * 2 + spacing {
                HStack(alignment: .top, spacing: spacing) {
                    column { leading }
                    column { trailing }
                }
                // Both columns take the taller one's height, so a growing
                // section at the end of either fills down to the same line.
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: spacing) {
                    column { leading }
                    column { trailing }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func column(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Page Content

/// The scrolling body of a Guest Tools page (`.dk-content`): 20pt of padding
/// on the window ground.
struct VPhoneGuestToolContent<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DK.Space.s6) {
                content
            }
            .padding(DK.Space.s5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
        .background(DK.Palette.window)
    }
}
