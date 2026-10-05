import Foundation

/// The lines of a log fed as a stream of terminal output, ready for `DKLog`.
///
/// Chunks need not end on a line or escape-sequence boundary: an unfinished
/// last line is shown as it grows and keeps its identity until its line feed
/// arrives, and colors carry from one line to the next as in a terminal.
/// A carriage return starts its line over, so a progress meter redrawn with
/// `\r` shows its latest state; `\r\n` is an ordinary line break.
public struct DKLogBuffer: Sendable {
    /// Every line kept, oldest first.
    public private(set) var lines: [DKLogLine] = []
    /// How many lines to keep; the oldest go first. Nil keeps everything.
    public var limit: Int? {
        didSet { trim() }
    }

    /// Whether a leading timestamp on each line moves to `DKLogLine.timestamp`.
    public var splitsTimestamps: Bool

    private var parser = DKANSIParser()
    /// The runs of the line that has not seen its line feed yet.
    private var openRuns: [DKLogRun] = []
    private var openLine: (id: UUID, tone: DKLogLine.Tone)?

    public init(limit: Int? = 10000, splitsTimestamps: Bool = false) {
        self.limit = limit
        self.splitsTimestamps = splitsTimestamps
    }

    /// Appends terminal output. `tone` applies to lines this chunk starts.
    public mutating func append(_ chunk: String, tone: DKLogLine.Tone = .plain) {
        for run in parser.feed(chunk) {
            var pieces = run.text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
            let last = pieces.removeLast()
            for piece in pieces {
                openRuns.appendMerging(DKLogRun(String(piece), style: run.style))
                closeLine(tone: tone)
            }
            openRuns.appendMerging(DKLogRun(String(last), style: run.style))
        }
        if !openRuns.isEmpty {
            let id = openLine?.id ?? UUID()
            let lineTone = openLine?.tone ?? tone
            let line = makeLine(id: id, tone: lineTone)
            if openLine == nil {
                lines.append(line)
                openLine = (id, lineTone)
            } else if let index = lines.indices.last {
                lines[index] = line
            }
        }
        trim()
    }

    /// Appends a finished line. An open line is closed first.
    public mutating func append(line: DKLogLine) {
        openRuns.removeAll()
        openLine = nil
        lines.append(line)
        trim()
    }

    /// Removes every line and forgets colors and any half-read sequence.
    public mutating func clear() {
        lines.removeAll()
        openRuns.removeAll()
        openLine = nil
        parser.reset()
    }

    // MARK: Lines

    private mutating func closeLine(tone: DKLogLine.Tone) {
        if let openLine {
            let line = makeLine(id: openLine.id, tone: openLine.tone)
            if let index = lines.indices.last {
                lines[index] = line
            }
        } else {
            lines.append(makeLine(id: UUID(), tone: tone))
        }
        openRuns.removeAll()
        openLine = nil
    }

    private func makeLine(id: UUID, tone: DKLogLine.Tone) -> DKLogLine {
        DKLogLine(id: id, parsedRuns: Self.applyingCarriageReturns(openRuns), tone: tone, splitsTimestamp: splitsTimestamps)
    }

    /// Keeps what follows the last carriage return that has text after it, and
    /// drops carriage returns at the end (the `\r` of `\r\n`, or a redraw whose
    /// text has not arrived yet).
    static func applyingCarriageReturns(_ runs: [DKLogRun]) -> [DKLogRun] {
        guard runs.contains(where: { $0.text.unicodeScalars.contains("\r") }) else {
            return runs
        }
        var result: [DKLogRun] = []
        // A carriage return clears the line only once text follows it, so one
        // with nothing after it yet leaves the old text showing.
        var pendingReturn = false
        for run in runs {
            let pieces = run.text.unicodeScalars.split(separator: "\r", omittingEmptySubsequences: false)
            for (offset, piece) in pieces.enumerated() {
                if offset > 0 {
                    pendingReturn = true
                }
                guard !piece.isEmpty else {
                    continue
                }
                if pendingReturn {
                    result.removeAll()
                    pendingReturn = false
                }
                result.appendMerging(DKLogRun(String(piece), style: run.style))
            }
        }
        return result
    }

    private mutating func trim() {
        guard let limit, lines.count > limit else {
            return
        }
        let overflow = lines.count - Swift.max(limit, 0)
        lines.removeFirst(overflow)
        if lines.isEmpty {
            openRuns.removeAll()
            openLine = nil
        }
    }
}
