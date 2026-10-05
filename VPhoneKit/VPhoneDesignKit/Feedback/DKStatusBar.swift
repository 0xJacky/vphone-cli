import SwiftUI

// MARK: - Connection

/// Whether the guest control connection is up, shown at the leading end of a
/// status bar.
public enum DKConnectionState: String, Sendable, CaseIterable, Hashable {
    case connected, disconnected

    public init(isConnected: Bool) {
        self = isConnected ? .connected : .disconnected
    }

    /// The dot's tone: green when connected, amber when not.
    public var tone: DKTone {
        self == .connected ? .success : .warning
    }

    /// The text shown when the caller gives none.
    public var defaultText: String {
        self == .connected ? "Connected" : "Guest not connected"
    }

    /// What VoiceOver says for the dot.
    public var accessibilityLabel: String {
        self == .connected ? "Guest connected" : "Guest not connected"
    }
}

// MARK: - Item

/// One metric in a status bar: an optional glyph, short text, and a tooltip
/// title that names what the text is ("CPU", "Address").
public struct DKStatusItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var glyph: DKGlyph?
    public var text: String
    public var title: String?

    public init(_ text: String, glyph: DKGlyph? = nil, title: String? = nil, id: String? = nil) {
        self.id = id ?? title ?? text
        self.glyph = glyph
        self.text = text
        self.title = title
    }

    /// The spoken form: "CPU: 12%" when there is a title, else the text.
    public var accessibilityText: String {
        guard let title, !title.isEmpty else {
            return text
        }
        return "\(title): \(text)"
    }
}

// MARK: - Status bar

/// The bar along the bottom of a Guest Tools panel or a VM window: connection
/// state at the leading end, then metric items, then trailing detail text.
/// Everything is set in small monospaced type, so numbers line up as they change.
/// A `textTone` colors the leading text, for a result that should stand out:
/// an error in the danger ink, a finished copy in the success ink.
public struct DKStatusBar: View {
    public var connection: DKConnectionState
    public var text: String?
    public var items: [DKStatusItem]
    public var detail: String?
    public var compact: Bool
    public var textTone: DKTone?

    public init(
        connection: DKConnectionState = .connected,
        text: String? = nil,
        items: [DKStatusItem] = [],
        detail: String? = nil,
        compact: Bool = false,
        textTone: DKTone? = nil,
    ) {
        self.connection = connection
        self.text = text
        self.items = items
        self.detail = detail
        self.compact = compact
        self.textTone = textTone
    }

    public init(
        isConnected: Bool,
        text: String? = nil,
        items: [DKStatusItem] = [],
        detail: String? = nil,
        compact: Bool = false,
        textTone: DKTone? = nil,
    ) {
        self.init(connection: DKConnectionState(isConnected: isConnected), text: text, items: items, detail: detail, compact: compact, textTone: textTone)
    }

    /// The leading text's color: the tone's text color, or the bar's muted ink.
    nonisolated static func textColor(for tone: DKTone?) -> Color {
        tone?.text ?? DK.Palette.muted
    }

    /// The bar's height: `DK.Metric.statusBarHeight`, or 22pt when compact.
    public nonisolated static func height(compact: Bool) -> CGFloat {
        compact ? 22 : DK.Metric.statusBarHeight
    }

    public var body: some View {
        HStack(spacing: DK.Space.s2) {
            HStack(spacing: DK.Space.s2) {
                DKStatusDot(connection.tone)
                Text(text ?? connection.defaultText)
                    .foregroundStyle(Self.textColor(for: textTone))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text ?? connection.accessibilityLabel)

            Spacer(minLength: DK.Space.s2)

            ForEach(items) { item in
                HStack(spacing: DK.Space.s1) {
                    if let glyph = item.glyph {
                        DKIcon(glyph, size: 12)
                    }
                    Text(item.text).lineLimit(1)
                }
                .help(item.title ?? "")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.accessibilityText)
            }

            if let detail, !detail.isEmpty {
                Text(detail).lineLimit(1)
            }
        }
        .font(DK.Typeface.monoSmall)
        .monospacedDigit()
        .foregroundStyle(DK.Palette.muted)
        .padding(.horizontal, DK.Space.s3)
        .frame(maxWidth: .infinity, minHeight: Self.height(compact: compact))
        .background(DK.Palette.sidebar)
        .overlay(alignment: .top) {
            DK.Palette.divider.frame(height: DK.Metric.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status")
    }
}

// MARK: - Previews

private struct DKStatusBarPreviewBoard: View {
    private let metrics = [
        DKStatusItem("iPhone17,3 · iOS 26.6.2", glyph: .phone, title: "Device"),
        DKStatusItem("192.168.64.12", glyph: .network, title: "Address"),
        DKStatusItem("12%", glyph: .cpu, title: "CPU"),
        DKStatusItem("31 / 64 GB", glyph: .disk, title: "Guest storage"),
    ]

    var body: some View {
        VStack(spacing: DK.Space.s4) {
            DKStatusBar(detail: "5 items")
            DKStatusBar(isConnected: false)
            DKStatusBar(items: metrics, detail: "vphoned 2.6.0", compact: true)
        }
        .padding(DK.Space.s4)
        .frame(width: 760)
        .background(DK.Palette.window)
    }
}

#Preview("Status Bar – Light") {
    DKStatusBarPreviewBoard().preferredColorScheme(.light)
}

#Preview("Status Bar – Dark") {
    DKStatusBarPreviewBoard().preferredColorScheme(.dark)
}
