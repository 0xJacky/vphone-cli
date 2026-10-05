import SwiftUI

/// The title bar of a VM window: the machine's name over a status line (a status
/// dot, the guest OS and its address), with the window's actions on the trailing
/// side.
///
/// The bar leaves room for the traffic lights on its leading side, because the
/// real window draws them over it. Set `trafficLightInset` to the room the
/// window needs, or to 0 for a bar without them. The display window uses the
/// roomy bar; Workspace, Terminal and Files use `compact`, which centers the
/// title and halves the padding. `init(machine:kind:…)` picks both for a
/// `DKVMWindowKind`.
///
/// Dragging the bar's background moves the window.
public struct DKTitleBar<Accessory: View>: View {
    /// The window title: the machine's name, or "name — Workspace".
    public var title: String
    /// The machine's state, drawn as the status dot.
    public var tone: DKTone
    /// What the dot means, for VoiceOver ("Running"); the dot is silent without it.
    public var status: String?
    /// The guest OS, such as "iOS 26.6.2". Hidden when empty.
    public var os: String
    /// The guest's address, in monospace. Hidden when nil or empty.
    public var address: String?
    /// The window's actions, usually ghost icon buttons.
    public var actions: [DKButtonSpec]
    /// The centered, tighter variant for the Workspace, Terminal and Files windows.
    public var compact: Bool
    /// Room left on the leading side, after the padding, for the traffic lights.
    public var trafficLightInset: CGFloat
    /// Draws the traffic lights itself, for previews and mockups. The real window
    /// draws its own.
    public var drawsTrafficLights: Bool
    let accessory: Accessory

    /// Room for the three traffic lights (52pt) and the gap after them.
    public static var defaultTrafficLightInset: CGFloat { 68 }

    public init(
        _ title: String,
        tone: DKTone,
        status: String? = nil,
        os: String,
        address: String? = nil,
        actions: [DKButtonSpec] = [],
        compact: Bool = false,
        trafficLightInset: CGFloat = DKTitleBar.defaultTrafficLightInset,
        drawsTrafficLights: Bool = false,
        @ViewBuilder accessory: () -> Accessory,
    ) {
        self.title = title
        self.tone = tone
        self.status = status
        self.os = os
        self.address = address
        self.actions = actions
        self.compact = compact
        self.trafficLightInset = trafficLightInset
        self.drawsTrafficLights = drawsTrafficLights
        self.accessory = accessory()
    }

    /// A title bar for one of a machine's windows: the title and the variant
    /// follow from `kind`.
    public init(
        machine: String,
        kind: DKVMWindowKind,
        tone: DKTone,
        status: String? = nil,
        os: String,
        address: String? = nil,
        actions: [DKButtonSpec] = [],
        trafficLightInset: CGFloat = DKTitleBar.defaultTrafficLightInset,
        drawsTrafficLights: Bool = false,
        @ViewBuilder accessory: () -> Accessory,
    ) {
        self.init(
            kind.title(machine: machine),
            tone: tone,
            status: status,
            os: os,
            address: address,
            actions: actions,
            compact: kind.usesCompactTitleBar,
            trafficLightInset: trafficLightInset,
            drawsTrafficLights: drawsTrafficLights,
            accessory: accessory,
        )
    }

    public var body: some View {
        HStack(spacing: DK.Space.s4) {
            leadingRoom
            titles
            trailing
        }
        .padding(.horizontal, compact ? DK.Space.s3 : DK.Space.s4)
        .padding(.vertical, compact ? 6 : 14)
        .frame(maxWidth: .infinity)
        .background {
            DK.Palette.window
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
        .overlay(alignment: .bottom) {
            DK.Palette.divider.frame(height: DK.Metric.hairline)
        }
    }

    // MARK: - Parts

    @ViewBuilder
    private var leadingRoom: some View {
        if drawsTrafficLights {
            DKTitleBarTrafficLights()
                .frame(width: max(trafficLightInset - DK.Space.s4, 0), alignment: .leading)
        } else if trafficLightInset > DK.Space.s4 {
            Color.clear.frame(width: trafficLightInset - DK.Space.s4, height: 1)
        }
    }

    private var titles: some View {
        VStack(alignment: compact ? .center : .leading, spacing: DK.Space.s1) {
            Text(title)
                .font(DK.Typeface.pageTitle)
                .foregroundStyle(DK.Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)
            statusLine
        }
        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
    }

    private var statusLine: some View {
        HStack(spacing: DK.Space.s2) {
            DKStatusDot(tone, label: status)
            if !os.isEmpty {
                Text(os)
            }
            if let address, !address.isEmpty {
                Text(address)
                    .font(DK.Typeface.mono)
                    .textSelection(.enabled)
            }
        }
        .font(DK.Typeface.caption)
        .foregroundStyle(DK.Palette.muted)
        .lineLimit(1)
    }

    private var trailing: some View {
        HStack(spacing: 6) {
            ForEach(actions) { spec in
                DKButton(spec)
            }
            accessory
        }
        .fixedSize()
    }
}

public extension DKTitleBar where Accessory == EmptyView {
    init(
        _ title: String,
        tone: DKTone,
        status: String? = nil,
        os: String,
        address: String? = nil,
        actions: [DKButtonSpec] = [],
        compact: Bool = false,
        trafficLightInset: CGFloat = DKTitleBar.defaultTrafficLightInset,
        drawsTrafficLights: Bool = false,
    ) {
        self.init(
            title,
            tone: tone,
            status: status,
            os: os,
            address: address,
            actions: actions,
            compact: compact,
            trafficLightInset: trafficLightInset,
            drawsTrafficLights: drawsTrafficLights,
            accessory: { EmptyView() },
        )
    }

    init(
        machine: String,
        kind: DKVMWindowKind,
        tone: DKTone,
        status: String? = nil,
        os: String,
        address: String? = nil,
        actions: [DKButtonSpec] = [],
        trafficLightInset: CGFloat = DKTitleBar.defaultTrafficLightInset,
        drawsTrafficLights: Bool = false,
    ) {
        self.init(
            machine: machine,
            kind: kind,
            tone: tone,
            status: status,
            os: os,
            address: address,
            actions: actions,
            trafficLightInset: trafficLightInset,
            drawsTrafficLights: drawsTrafficLights,
            accessory: { EmptyView() },
        )
    }
}

// MARK: - Traffic lights

/// The three window buttons as the design draws them, for previews.
private struct DKTitleBarTrafficLights: View {
    var body: some View {
        HStack(spacing: DK.Space.s2) {
            Circle().fill(Self.close)
            Circle().fill(Self.minimize)
            Circle().fill(Self.zoom)
        }
        .frame(width: 52, height: 12)
        .accessibilityHidden(true)
    }

    private static let close = Color(nsColor: NSColor(rgb: 0xFF5F57, alpha: 1))
    private static let minimize = Color(nsColor: NSColor(rgb: 0xFEBC2E, alpha: 1))
    private static let zoom = Color(nsColor: NSColor(rgb: 0x28C840, alpha: 1))
}
