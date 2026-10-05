import SwiftUI

// MARK: - Status dot

/// An 8pt dot that says a machine's or a service's state at a glance. Pair it with
/// text; the dot alone is decoration for VoiceOver unless `label` is set.
public struct DKStatusDot: View {
    public let tone: DKTone
    public var label: String?

    public init(_ tone: DKTone, label: String? = nil) {
        self.tone = tone
        self.label = label
    }

    public var body: some View {
        Circle()
            .fill(tone == .neutral ? DK.Palette.dotIdle : tone.color)
            .frame(width: DK.Metric.dot, height: DK.Metric.dot)
            .accessibilityHidden(label == nil)
            .accessibilityLabel(label ?? "")
    }
}

// MARK: - Badge

/// A short pill of status text: "Supported", "Default", "Not applied".
public struct DKBadge: View {
    public let text: String
    public var tone: DKTone

    public init(_ text: String, tone: DKTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(tone.ink)
            .background(Capsule().fill(tone.surface))
            .fixedSize()
    }
}
