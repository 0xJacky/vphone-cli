import SwiftUI
import VPhoneDesignKit

/// Measures its content at no less than `minimumWidth`.
///
/// A row-layout `DKDetailBar` with a note, measured at the zero width an
/// `NSHostingView` uses for its minimum size, wraps the note one character per
/// line and reports a minimum height of a thousand points or more; the window
/// then grows to it. Measuring at a sane width keeps the minimum height to the
/// bar's real height. The content is still placed at the width it is given.
struct VPhoneGuestDetailBarSizing: Layout {
    var minimumWidth: CGFloat = 360

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        guard let width = proposal.width, width.isFinite else {
            return content.sizeThatFits(proposal)
        }
        let measured = content.sizeThatFits(ProposedViewSize(width: max(width, minimumWidth), height: proposal.height))
        return CGSize(width: width, height: measured.height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height),
        )
    }
}

extension View {
    /// Keeps a row-layout `DKDetailBar` from reporting a runaway minimum height.
    func guestDetailBarSizing() -> some View {
        VPhoneGuestDetailBarSizing { self }
    }
}

// MARK: - Note Without a Selection

/// The muted line a row-layout `DKDetailBar` shows when nothing is selected.
/// `DKDetailBar` draws its `note` only under a title, so a bar without one
/// passes this as its content instead.
struct VPhoneGuestDetailNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(DK.Typeface.caption)
            .foregroundStyle(DK.Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
