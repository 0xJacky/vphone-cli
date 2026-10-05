import AppKit
import SwiftUI
import VPhoneDesignKit

// Pieces shared by the Apps, Processes, Services, Console and Crash Logs
// pages, which draw their own page header and status bar.

// MARK: - Status Bar

/// The page's bottom bar: the connection dot, then the running activity, the
/// last successful result, or the idle text, then the page's counts.
/// Failures show as a banner under the header instead (`VPhoneSystemPageBanner`).
struct VPhoneSystemPageStatusBar: View {
    let isConnected: Bool
    var activity: String?
    var status: VPhoneGuestToolStatus?
    /// What the bar says while connected and idle: "Connected" unless given.
    var idleText: String?
    var items: [DKStatusItem] = []
    var detail: String?

    var body: some View {
        DKStatusBar(isConnected: isConnected, text: text, items: items, detail: detail)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var text: String {
        if let activity {
            return activity
        }
        guard isConnected else {
            return VPhoneLocalization.text("Guest not connected")
        }
        if let status, !status.isError {
            return status.message
        }
        return idleText ?? VPhoneLocalization.text("Connected")
    }
}

// MARK: - Banner

/// The last failure, under the page header, until the page's next result
/// replaces it.
struct VPhoneSystemPageBanner: View {
    let status: VPhoneGuestToolStatus?

    var body: some View {
        if let status, status.isError {
            DKBanner(status.message, tone: .warning)
                .textSelection(.enabled)
                .padding(.horizontal, DK.Space.s4)
                .padding(.top, DK.Space.s3)
                .padding(.bottom, DK.Space.s1)
        }
    }
}

// MARK: - Search Field

/// The design's pill search field (`DKSearchField`) with a focus binding, so a
/// page can focus it from a shortcut or the Find command and know when it is
/// being edited.
struct VPhoneSystemSearchField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat = 180
    var focus: FocusState<Bool>.Binding

    var body: some View {
        let shape = Capsule(style: .circular)
        HStack(spacing: 6) {
            DKIcon(.search, size: 14)
                .foregroundStyle(DK.Palette.muted)
            TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(DK.Palette.muted))
                .textFieldStyle(.plain)
                .font(DK.Typeface.body)
                .foregroundStyle(DK.Palette.ink)
                .focused(focus)
                .focusEffectDisabled()
                .accessibilityLabel(placeholder)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    DKIcon(.xCircle, size: 13)
                        .foregroundStyle(DK.Palette.inkDisabled)
                }
                .buttonStyle(.plain)
                .help(VPhoneLocalization.text("Clear"))
                .accessibilityLabel(VPhoneLocalization.text("Clear Search"))
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: DK.Metric.controlHeight)
        .background(shape.fill(DK.Palette.window))
        .overlay(shape.strokeBorder(focus.wrappedValue ? DK.Palette.accent : DK.Palette.lineStrong, lineWidth: DK.Metric.hairline))
        .contentShape(shape)
        .onTapGesture { focus.wrappedValue = true }
    }
}

// MARK: - Menu Button

/// A header button that opens a menu: Signal, More Actions. DesignKit has no
/// menu button, so this is a `DKButton` that pops up the items as an
/// `NSMenu` (`DKMenuItem.makeNSMenu`) at the pointer.
struct VPhoneSystemMenuButton: View {
    let label: String
    let glyph: DKGlyph
    var size: DKButtonSize = .regular
    var isEnabled = true
    var help: String?
    /// The rows, built when the menu opens.
    let items: () -> [DKMenuItem]

    var body: some View {
        DKButton(DKButtonSpec(label, glyph: glyph, size: size, isEnabled: isEnabled, help: help) {
            items().makeNSMenu(title: label).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        })
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(VPhoneLocalization.text("Opens a menu")))
    }
}

// MARK: - Toggle Button

/// A header button that stays pressed while its setting is on: Auto Refresh,
/// Auto-Scroll, App Info.
struct VPhoneSystemToggleButton: View {
    let label: String
    let glyph: DKGlyph
    @Binding var isOn: Bool
    var size: DKButtonSize = .regular
    var help: String?

    var body: some View {
        DKButton(DKButtonSpec(
            label,
            glyph: glyph,
            variant: isOn ? .pressed : .secondary,
            size: size,
            help: help,
        ) { isOn.toggle() })
            .accessibilityValue(Text(VPhoneLocalization.text(isOn ? "On" : "Off")))
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Table

extension View {
    /// The look of a page's main table, as `DKDataTable` draws rows: inset
    /// rows on the window ground, the accent tint behind selected rows and no
    /// row separators. A header click still sorts, and its mark stays: it is
    /// the only sign of the order, and SwiftUI draws it in its own header.
    func systemPageTable() -> some View {
        tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .background(DK.Palette.window)
            .background(VPhoneTableChrome())
    }
}

/// Finds the `NSTableView` behind a SwiftUI `Table` and gives it the
/// design's rows. SwiftUI has no API for the selection color or the row
/// separators, and puts them back when it updates the table, so they are set
/// again after each update, scroll and selection.
private struct VPhoneTableChrome: NSViewRepresentable {
    func makeNSView(context _: Context) -> VPhoneTableChromeView {
        VPhoneTableChromeView()
    }

    func updateNSView(_ view: VPhoneTableChromeView, context _: Context) {
        view.setNeedsRestyle()
    }
}

/// Sits behind the table, with the table's frame, and styles it.
private final class VPhoneTableChromeView: NSView {
    private weak var tableView: NSTableView?
    private var observers: [NSObjectProtocol] = []
    private var isRestylePending = false
    private var pendingRowRetries = 0

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    /// The table may not have its frame yet when this view joins the window;
    /// this view gets the same frame, so it looks again then.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if tableView == nil {
            setNeedsRestyle()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            detach()
        } else {
            setNeedsRestyle()
        }
    }

    /// Restyles once the current SwiftUI update has reached the table.
    func setNeedsRestyle() {
        guard !isRestylePending else { return }
        isRestylePending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isRestylePending = false
                self.attach()
                self.restyle()
            }
        }
    }

    // MARK: Table

    private func attach() {
        guard tableView == nil, window != nil, let table = findTable() else { return }
        tableView = table
        let center = NotificationCenter.default
        let restyle: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.restyle() }
        }
        table.postsFrameChangedNotifications = true
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: table, queue: .main, using: restyle))
        observers.append(center.addObserver(forName: NSTableView.selectionDidChangeNotification, object: table, queue: .main, using: restyle))
        if let clipView = table.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main, using: restyle))
        }
    }

    private func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        tableView = nil
    }

    /// The table whose scroll view this view lies behind: the page's own
    /// table, not one elsewhere in the window.
    private func findTable() -> NSTableView? {
        guard let root = window?.contentView else { return nil }
        let frame = convert(bounds, to: nil)
        func search(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView, let scrollView = table.enclosingScrollView {
                let scrollFrame = scrollView.convert(scrollView.bounds, to: nil)
                if abs(scrollFrame.midX - frame.midX) < 2, abs(scrollFrame.midY - frame.midY) < 2 {
                    return table
                }
            }
            for subview in view.subviews {
                if let table = search(subview) {
                    return table
                }
            }
            return nil
        }
        return search(root)
    }

    private func restyle() {
        guard let table = tableView else { return }
        if table.selectionHighlightStyle != .none {
            table.selectionHighlightStyle = .none
        }
        if table.highlightedTableColumn != nil {
            table.highlightedTableColumn = nil
        }
        var styled = 0
        table.enumerateAvailableRowViews { rowView, _ in
            Self.style(rowView)
            styled += 1
        }
        // SwiftUI adds row views after the update that changed the rows,
        // with no notification; look again until the visible rows have them.
        let visible = table.rows(in: table.visibleRect).length
        if styled < visible, pendingRowRetries < 20 {
            pendingRowRetries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                MainActor.assumeIsolated { self?.restyle() }
            }
        } else if styled >= visible {
            pendingRowRetries = 0
        }
    }

    private static let setSeparatorColor = NSSelectorFromString("setSeparatorColor:")

    /// Clears SwiftUI's row separator and shows the selection tint behind a
    /// selected row.
    private static func style(_ rowView: NSTableRowView) {
        if rowView.responds(to: setSeparatorColor) {
            rowView.setValue(NSColor.clear, forKey: "separatorColor")
        }
        let selection = rowView.subviews.lazy.compactMap { $0 as? VPhoneTableSelectionView }.first ?? {
            let view = VPhoneTableSelectionView(frame: rowView.bounds)
            view.autoresizingMask = [.width, .height]
            rowView.addSubview(view, positioned: .below, relativeTo: nil)
            return view
        }()
        selection.isHidden = !rowView.isSelected
    }
}

/// The selection tint behind a selected row (`DKTableRowBackground`).
private final class VPhoneTableSelectionView: NSView {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func draw(_: NSRect) {
        let rect = bounds.insetBy(dx: DK.Space.s2, dy: 1)
        NSColor(DK.Palette.accentTint).setFill()
        NSBezierPath(roundedRect: rect, xRadius: DK.Radius.field, yRadius: DK.Radius.field).fill()
    }
}

/// A table cell drawn by DesignKit. Should a table draw the system's
/// emphasized selection, as before `systemPageTable()` has styled it, the
/// cell's ink would sit on the accent fill, so text cells switch to the
/// selection's own foreground there.
struct VPhoneSystemCell: View {
    let cell: DKTableCell
    var alignment: Alignment = .leading
    var help: String?

    @Environment(\.backgroundProminence) private var prominence

    init(_ cell: DKTableCell, alignment: Alignment = .leading, help: String? = nil) {
        self.cell = cell
        self.alignment = alignment
        self.help = help
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: alignment)
            .help(help ?? "")
    }

    @ViewBuilder
    private var content: some View {
        if prominence == .increased, let text = plainText {
            Text(text.value)
                .font(text.font)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityLabel(cell.accessibilityText)
        } else {
            DKTableCellView(cell)
        }
    }

    private var plainText: (value: String, font: Font)? {
        switch cell {
        case let .text(value), let .muted(value): (value, DK.Typeface.body)
        case let .mono(value): (value, DK.Typeface.mono)
        case let .strong(value): (value, DK.Typeface.bodyStrong)
        default: nil
        }
    }
}

// MARK: - Text Log

/// A block of guest text as a static `DKLog`: a launchd description, a log
/// message. The text is split into lines once per change, so the log keeps
/// their identity while the page redraws.
struct VPhoneSystemTextLog: View {
    let text: String
    var tone: DKLogLine.Tone = .plain
    let label: String
    /// The dim line shown for empty text.
    var emptyText: String?
    var minHeight: CGFloat = 60

    @State private var lines: [DKLogLine] = []
    @State private var source: Source?

    private struct Source: Equatable {
        let text: String
        let tone: DKLogLine.Tone
    }

    var body: some View {
        DKLog(lines, following: false, wrapsLines: true, minHeight: minHeight, label: label)
            .onAppear(perform: update)
            .onChange(of: Source(text: text, tone: tone)) { _, _ in update() }
    }

    private func update() {
        let current = Source(text: text, tone: tone)
        guard source != current else { return }
        source = current
        lines = Self.lines(text, tone: tone, emptyText: emptyText)
    }

    static func lines(_ text: String, tone: DKLogLine.Tone, emptyText: String?) -> [DKLogLine] {
        guard !text.isEmpty else {
            return emptyText.map { [DKLogLine($0, tone: .dim)] } ?? []
        }
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { DKLogLine($0.replacingOccurrences(of: "\t", with: "    "), tone: tone) }
    }
}
