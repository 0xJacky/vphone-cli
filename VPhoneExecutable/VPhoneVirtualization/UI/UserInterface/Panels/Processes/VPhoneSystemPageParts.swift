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
    ///
    /// The table stays transparent until its first rows are styled: SwiftUI
    /// draws them with separators first, and they would show for a moment.
    func systemPageTable() -> some View {
        modifier(VPhoneSystemPageTable())
    }
}

private struct VPhoneSystemPageTable: ViewModifier {
    @State private var isStyled = false

    func body(content: Content) -> some View {
        content
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .opacity(isStyled ? 1 : 0)
            .background(DK.Palette.window)
            .background(VPhoneTableChrome(onFirstStyle: { isStyled = true }))
    }
}

/// Finds the `NSTableView` behind a SwiftUI `Table` and gives it the
/// design's rows. SwiftUI has no API for the selection color or the row
/// separators, and puts them back when it updates the table, so they are set
/// again after each update, scroll and selection.
private struct VPhoneTableChrome: NSViewRepresentable {
    /// Called once, when the rows on screen first have the design's look.
    let onFirstStyle: @MainActor () -> Void

    func makeNSView(context _: Context) -> VPhoneTableChromeView {
        let view = VPhoneTableChromeView()
        view.onFirstStyle = onFirstStyle
        return view
    }

    func updateNSView(_ view: VPhoneTableChromeView, context _: Context) {
        view.onFirstStyle = onFirstStyle
        view.setNeedsRestyle()
    }
}

/// Sits behind the table, with the table's frame, and styles it.
private final class VPhoneTableChromeView: NSView {
    private weak var tableView: NSTableView?
    private var observers: [NSObjectProtocol] = []
    private var isRestylePending = false
    private var pendingRowRetries = 0
    var onFirstStyle: (@MainActor () -> Void)?
    private var hasStyled = false

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
                if self.tableView == nil, self.window != nil {
                    // No table found behind this view: show the page as is
                    // rather than leave it transparent.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        MainActor.assumeIsolated { self?.didStyle() }
                    }
                }
            }
        }
    }

    /// Shows the table, the first time its rows are styled.
    private func didStyle() {
        guard !hasStyled else { return }
        hasStyled = true
        onFirstStyle?()
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
        } else {
            // Styled, or out of retries: either way the rows on screen are
            // as styled as they will get, so the table may show.
            if styled >= visible {
                pendingRowRetries = 0
            }
            didStyle()
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

/// A table cell drawn by DesignKit, aligned in its column and with an optional
/// tooltip. On a selected row drawn with the system accent fill the cell
/// switches to the on-accent ink by itself (`DKTableCellView`).
struct VPhoneSystemCell: View {
    let cell: DKTableCell
    var alignment: Alignment = .leading
    var help: String?

    init(_ cell: DKTableCell, alignment: Alignment = .leading, help: String? = nil) {
        self.cell = cell
        self.alignment = alignment
        self.help = help
    }

    var body: some View {
        DKTableCellView(cell)
            .frame(maxWidth: .infinity, alignment: alignment)
            .help(help ?? "")
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
