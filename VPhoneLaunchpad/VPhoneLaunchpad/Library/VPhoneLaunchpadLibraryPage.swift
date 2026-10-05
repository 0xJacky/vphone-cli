import SwiftUI
import VPhoneDesignKit

// MARK: - Page

/// The frame of a Library page: the DesignKit header, then the sections in a
/// scrolling column on the window ground (`.dk-content`, or with `roomy`,
/// `.dk-content--roomy`).
struct VPhoneLaunchpadLibraryPage<Tools: View, Content: View>: View {
    let title: String
    let subtitle: String?
    let roomy: Bool
    let tools: Tools
    let content: Content

    init(
        _ title: String,
        subtitle: String?,
        roomy: Bool = false,
        @ViewBuilder tools: () -> Tools,
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.roomy = roomy
        self.tools = tools()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            DKPageHeader(title, subtitle: subtitle) {
                tools
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: roomy ? DK.Space.s8 : DK.Space.s6) {
                    content
                }
                .padding(roomy ? DK.Space.s6 : DK.Space.s5)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .font(DK.Typeface.body)
        .foregroundStyle(DK.Palette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DK.Palette.window)
    }
}

// MARK: - Placeholder

/// A muted line inside a card while the page reads the disk, or when a list
/// is empty.
struct VPhoneLaunchpadLibraryNote: View {
    let text: String
    var isWorking = false

    var body: some View {
        HStack(spacing: DK.Space.s2) {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Text(text)
                .foregroundStyle(DK.Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DK.Space.s3)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight, alignment: .leading)
    }
}

// MARK: - Figures

/// A caption over a large figure: "Used by ~/.vphone/machines" over "166 GB".
struct VPhoneLaunchpadUsageFigure: View {
    let caption: String
    let value: String
    var alignment: HorizontalAlignment = .leading
    var tone: DKTone?

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(caption)
                .font(DK.Typeface.caption)
                .foregroundStyle(DK.Palette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tone?.text ?? DK.Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }
}
