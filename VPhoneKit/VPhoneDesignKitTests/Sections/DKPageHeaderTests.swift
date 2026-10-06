import AppKit
import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// A page header that is its window's title bar keeps its title in line with
/// the window buttons.
@MainActor
@Suite("DesignKit page header")
struct DKPageHeaderTests {
    private func height(_ view: some View, width: CGFloat = 900) -> CGFloat {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 0)).height
    }

    private func header(subtitle: String?) -> some View {
        DKPageHeader("Controls", subtitle: subtitle) {
            DKButton("Refresh", glyph: .refresh) {}
        }
    }

    @Test
    func `a header shows a subtitle line for a subtitle, or for the room a title bar keeps`() {
        #expect(DKPageHeader<EmptyView>.showsSubtitleLine("Values read at 09:41:22", isTitleBar: false))
        #expect(!DKPageHeader<EmptyView>.showsSubtitleLine(nil, isTitleBar: false))
        #expect(!DKPageHeader<EmptyView>.showsSubtitleLine("", isTitleBar: false))
        #expect(DKPageHeader<EmptyView>.showsSubtitleLine(nil, isTitleBar: true))
        #expect(DKPageHeader<EmptyView>.showsSubtitleLine("", isTitleBar: true))
    }

    @Test
    func `the header is as tall as the design's: padding, a 20pt title and a 16pt subtitle`() {
        // 12 + 20 + 16 + 12, the divider drawn over the bottom edge.
        #expect(height(header(subtitle: "Values read from the guest at 09:41:22")) == 60)
    }

    @Test
    func `a title bar header keeps its height before the subtitle arrives`() {
        let titleBar = { (subtitle: String?) in
            header(subtitle: subtitle).environment(\.dkPageHeaderIsTitleBar, true)
        }
        #expect(height(titleBar(nil)) == height(titleBar("Values read from the guest at 09:41:22")))
        #expect(height(titleBar(nil)) == 60)
        // Elsewhere a header without a subtitle only fits its tools.
        #expect(height(header(subtitle: nil)) < 60)
    }
}
