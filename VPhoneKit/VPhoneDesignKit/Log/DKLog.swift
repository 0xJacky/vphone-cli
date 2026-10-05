import SwiftUI

/// A read-only log (`.dk-log`): monospaced lines on the terminal background,
/// each in its tone's color, with ANSI colors kept per run.
///
/// While `following`, the view stays scrolled to the newest line as lines
/// arrive and shows a block cursor after it. Scrolling up stops following;
/// scrolling back to the bottom resumes it. Pass a binding to drive and observe
/// following from a toolbar toggle, `true` to let the view manage it, or
/// `false` for a static log that never follows.
///
/// Rows are laid out lazily, so a log of many thousands of lines only builds
/// the rows on screen; feed it from `DKLogBuffer` to cap its length.
public struct DKLog: View {
    let lines: [DKLogLine]
    let label: String
    let isFlush: Bool
    let wrapsLines: Bool
    let minHeight: CGFloat?
    let externalFollowing: Binding<Bool>?
    let canFollow: Bool

    @State private var localFollowing: Bool
    @State private var position = ScrollPosition()

    /// A log that follows its newest line, or a static one.
    ///
    /// - Parameters:
    ///   - lines: The lines, oldest first.
    ///   - following: `true` to follow new lines (the view stops and resumes as the
    ///     user scrolls); `false` for a static log with no cursor.
    ///   - flush: Drops the border and rounded corners, for a log that fills a panel.
    ///   - wrapsLines: Wraps long lines instead of scrolling sideways.
    ///   - minHeight: The least height the log takes.
    ///   - label: What VoiceOver calls the log.
    public init(
        _ lines: [DKLogLine],
        following: Bool = true,
        flush: Bool = false,
        wrapsLines: Bool = false,
        minHeight: CGFloat? = nil,
        label: String = "Console",
    ) {
        self.lines = lines
        self.label = label
        isFlush = flush
        self.wrapsLines = wrapsLines
        self.minHeight = minHeight
        externalFollowing = nil
        canFollow = following
        _localFollowing = State(initialValue: following)
    }

    /// A log whose following state is shared with the caller, as with the
    /// Auto-Scroll toggle of `DKLogToolbar`. The view sets it to false when the
    /// user scrolls up and back to true at the bottom.
    public init(
        _ lines: [DKLogLine],
        following: Binding<Bool>,
        flush: Bool = false,
        wrapsLines: Bool = false,
        minHeight: CGFloat? = nil,
        label: String = "Console",
    ) {
        self.lines = lines
        self.label = label
        isFlush = flush
        self.wrapsLines = wrapsLines
        self.minHeight = minHeight
        externalFollowing = following
        canFollow = true
        _localFollowing = State(initialValue: following.wrappedValue)
    }

    private var isFollowing: Bool {
        canFollow && (externalFollowing?.wrappedValue ?? localFollowing)
    }

    private func setFollowing(_ value: Bool) {
        guard canFollow, isFollowing != value else {
            return
        }
        if let externalFollowing {
            externalFollowing.wrappedValue = value
        } else {
            localFollowing = value
        }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: isFlush ? 0 : DK.Radius.card, style: .continuous)
        let anchor: UnitPoint = isFollowing ? .bottomLeading : .topLeading
        ScrollView(wrapsLines ? .vertical : [.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    DKLogRow(line: line, wraps: wrapsLines)
                        .equatable()
                }
                if isFollowing {
                    DKLogCursor()
                }
            }
            .frame(maxWidth: wrapsLines ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, isFlush ? 10 : 14)
            .padding(.vertical, isFlush ? 8 : 12)
            .textSelection(.enabled)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.topLeading, for: .alignment)
        .defaultScrollAnchor(anchor, for: .initialOffset)
        .defaultScrollAnchor(anchor, for: .sizeChanges)
        .onScrollGeometryChange(for: DKLogScrollMetrics.self) { geometry in
            DKLogScrollMetrics(geometry)
        } action: { old, new in
            followScrolling(from: old, to: new)
        }
        .onChange(of: lines.last) {
            scrollToNewest()
        }
        .onChange(of: isFollowing) { _, following in
            if following {
                scrollToNewest()
            }
        }
        .frame(minHeight: minHeight)
        .background(DK.Palette.terminalBackground)
        .clipShape(shape)
        .overlay {
            if !isFlush {
                shape.strokeBorder(DK.Palette.line, lineWidth: DK.Metric.hairline)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    // MARK: Following

    private func scrollToNewest() {
        guard isFollowing else {
            return
        }
        position.scrollTo(edge: .bottom)
    }

    /// Stops following when the user scrolls up and resumes at the bottom. New
    /// lines and the scroll to them only move the offset down, so they never
    /// stop following on their own.
    private func followScrolling(from old: DKLogScrollMetrics, to new: DKLogScrollMetrics) {
        guard canFollow else {
            return
        }
        if new.isAtBottom {
            setFollowing(true)
        } else if new.offset < old.offset - 0.5 {
            setFollowing(false)
        } else if isFollowing, new.viewportHeight != old.viewportHeight {
            scrollToNewest()
        }
    }
}

// MARK: - Pieces

/// Where the log is scrolled, reduced to what following needs.
struct DKLogScrollMetrics: Equatable {
    var offset: CGFloat
    var viewportHeight: CGFloat
    var isAtBottom: Bool

    /// How close to the end counts as the bottom, in points.
    static let bottomSlack: CGFloat = 8

    init(offset: CGFloat, viewportHeight: CGFloat, contentHeight: CGFloat) {
        self.offset = offset
        self.viewportHeight = viewportHeight
        isAtBottom = offset + viewportHeight >= contentHeight - Self.bottomSlack
    }

    init(_ geometry: ScrollGeometry) {
        self.init(
            offset: geometry.contentOffset.y,
            viewportHeight: geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom,
            contentHeight: geometry.contentSize.height,
        )
    }
}

/// One line. Equatable so an append re-renders only the rows that changed.
struct DKLogRow: View, Equatable {
    let line: DKLogLine
    let wraps: Bool

    var body: some View {
        Text(line.attributedText)
            .font(DK.Typeface.log)
            .lineLimit(wraps ? nil : 1)
            .fixedSize(horizontal: !wraps, vertical: true)
            .frame(maxWidth: wraps ? .infinity : nil, alignment: .leading)
            // 12pt text on a 1.55 line height.
            .padding(.vertical, 2)
    }
}

/// The block after the newest line while the log follows.
struct DKLogCursor: View {
    var body: some View {
        Rectangle()
            .fill(DK.Palette.terminalDim)
            .frame(width: 7, height: 15)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

private let previewLines: [DKLogLine] = {
    var buffer = DKLogBuffer(splitsTimestamps: true)
    buffer.append(line: DKLogLine("$ vphone-cli vm launch research-26", tone: .command))
    buffer.append("[boot output]\n", tone: .dim)
    buffer.append("09:41:19.204  guest booted to lock screen\n")
    buffer.append("09:41:21.003  vphoned listening on vsock \u{1B}[1m1339\u{1B}[0m\n")
    buffer.append("09:41:21.412  \u{1B}[33mwarning:\u{1B}[0m audio route not ready\n")
    buffer.append("09:41:22.090  \u{1B}[31merror:\u{1B}[0m mediaserverd exited\n")
    buffer.append("\u{1B}]0;title\u{07}progress 40%\rprogress 100%\n")
    buffer.append(line: DKLogLine("ping ok", tone: .success))
    return buffer.lines
}()

private struct DKLogPreviewFeed: View {
    @State private var buffer = DKLogBuffer(limit: 2000)
    @State private var following = true
    @State private var search = ""
    @State private var level = DKLogLevelFilter.all

    var body: some View {
        VStack(spacing: 0) {
            DKLogToolbar(searchText: $search, level: $level, following: $following) {
                buffer.clear()
            }
            DKLog(
                buffer.lines.filter { level.admits($0.tone) && $0.matches(search) },
                following: $following,
                flush: true,
                label: "Guest console",
            )
        }
        .task {
            var count = 0
            while !Task.isCancelled {
                count += 1
                let tone: DKLogLine.Tone = count % 7 == 0 ? .error : count % 5 == 0 ? .warning : .plain
                buffer.append("line \(count) \u{1B}[32mok\u{1B}[0m\n", tone: tone)
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }
}

#Preview("Log, light") {
    VStack(spacing: DK.Space.s4) {
        DKLog(previewLines)
        DKLog(previewLines, following: false, flush: true, label: "Report")
    }
    .padding()
    .frame(width: 640, height: 420)
    .background(DK.Palette.window)
    .preferredColorScheme(.light)
}

#Preview("Log, dark") {
    VStack(spacing: DK.Space.s4) {
        DKLog(previewLines)
        DKLog(previewLines, following: false, flush: true, wrapsLines: true, label: "Report")
    }
    .padding()
    .frame(width: 640, height: 420)
    .background(DK.Palette.window)
    .preferredColorScheme(.dark)
}

#Preview("Streaming console") {
    DKLogPreviewFeed()
        .frame(width: 760, height: 360)
        .background(DK.Palette.window)
}
