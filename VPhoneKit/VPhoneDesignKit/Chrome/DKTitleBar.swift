import SwiftUI

/// The title bar of a VM window: the machine's name over a status line (a status
/// dot, the guest OS and its address), with the window's actions on the trailing
/// side.
///
/// The bar draws the window buttons on its leading side (`DKWindowControls`):
/// the window hides its system buttons, so they sit centered on this bar
/// rather than on the shorter system title bar. Pass `showsWindowControls:
/// false` in full screen, where the system shows its own with the menu bar.
/// The display window uses the
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
    /// Draws close, minimize and zoom on the leading side.
    public var showsWindowControls: Bool
    let accessory: Accessory

    public init(
        _ title: String,
        tone: DKTone,
        status: String? = nil,
        os: String,
        address: String? = nil,
        actions: [DKButtonSpec] = [],
        compact: Bool = false,
        showsWindowControls: Bool = true,
        @ViewBuilder accessory: () -> Accessory,
    ) {
        self.title = title
        self.tone = tone
        self.status = status
        self.os = os
        self.address = address
        self.actions = actions
        self.compact = compact
        self.showsWindowControls = showsWindowControls
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
        showsWindowControls: Bool = true,
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
            showsWindowControls: showsWindowControls,
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
                .allowsWindowActivationEvents(true)
        }
        .overlay(alignment: .bottom) {
            DK.Palette.divider.frame(height: DK.Metric.hairline)
        }
    }

    // MARK: - Parts

    @ViewBuilder
    private var leadingRoom: some View {
        if showsWindowControls {
            DKWindowControls()
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
        showsWindowControls: Bool = true,
    ) {
        self.init(
            title,
            tone: tone,
            status: status,
            os: os,
            address: address,
            actions: actions,
            compact: compact,
            showsWindowControls: showsWindowControls,
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
        showsWindowControls: Bool = true,
    ) {
        self.init(
            machine: machine,
            kind: kind,
            tone: tone,
            status: status,
            os: os,
            address: address,
            actions: actions,
            showsWindowControls: showsWindowControls,
            accessory: { EmptyView() },
        )
    }
}
