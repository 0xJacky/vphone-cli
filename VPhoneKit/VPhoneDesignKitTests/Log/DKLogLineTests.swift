import SwiftUI
import Testing
@testable import VPhoneDesignKit

/// Log lines: tones, timestamps, rendering, the stream buffer and the filters.
@Suite("DesignKit log lines")
struct DKLogLineTests {
    private let esc = "\u{1B}"

    // MARK: Tones

    @Test
    func `line tones take the terminal palette`() {
        #expect(DKLogLine.Tone.plain.color == DK.Palette.terminalForeground)
        #expect(DKLogLine.Tone.command.color == DK.Palette.terminalBlue)
        #expect(DKLogLine.Tone.dim.color == DK.Palette.terminalDim)
        #expect(DKLogLine.Tone.success.color == DK.Palette.terminalGreen)
        #expect(DKLogLine.Tone.error.color == DK.Palette.terminalRed)
        #expect(DKLogLine.Tone.warning.color == DKLogPalette.yellow)
    }

    @Test
    func `command, result and failure lines are emphasized, plain and dim are not`() {
        let emphasized = DKLogLine.Tone.allCases.filter(\.isEmphasized)
        #expect(Set(emphasized) == [.command, .success, .warning, .error])
    }

    @Test
    func `line tones round-trip through the shared status tones`() {
        for tone in DKLogLine.Tone.allCases {
            #expect(DKLogLine.Tone(tone.statusTone) == tone)
        }
        #expect(DKLogLine.Tone(DKTone.accent) == .command)
    }

    @Test(arguments: [
        ("Fault", DKLogLine.Tone.error), ("Error", .warning), ("Debug", .dim),
        ("Default", .plain), ("Info", .plain), ("FAULT", .error), ("", .plain),
    ])
    func `unified log levels map to tones`(level: String, tone: DKLogLine.Tone) {
        #expect(DKLogLine.Tone(logLevel: level) == tone)
    }

    @Test
    func `ANSI colors map onto the terminal palette`() {
        #expect(DKLogColor.red.terminalColor == DK.Palette.terminalRed)
        #expect(DKLogColor.green.terminalColor == DK.Palette.terminalGreen)
        #expect(DKLogColor.blue.terminalColor == DK.Palette.terminalBlue)
        #expect(DKLogColor.white.terminalColor == DK.Palette.terminalForeground)
        #expect(DKLogColor.black.terminalColor == DK.Palette.terminalDim)
        #expect(DKLogColor.gray.terminalColor == DK.Palette.terminalDim)
    }

    @Test
    func `a run's own color wins over the line tone, faint falls back to dim`() {
        let line = DKLogLine("x", tone: .error)
        #expect(line.color(for: .plain) == DK.Palette.terminalRed)
        #expect(line.color(for: DKLogStyle(color: .green)) == DK.Palette.terminalGreen)
        #expect(line.color(for: DKLogStyle(isFaint: true)) == DK.Palette.terminalDim)
        #expect(line.color(for: DKLogStyle(color: .blue, isFaint: true)) == DK.Palette.terminalBlue)
    }

    @Test
    func `bold runs are bold and emphasized tones are semibold`() {
        #expect(DKLogLine("x").font(for: .plain) == DK.Typeface.log)
        #expect(DKLogLine("x").font(for: DKLogStyle(isBold: true)) == DK.Typeface.log.weight(.bold))
        #expect(DKLogLine("x", tone: .command).font(for: .plain) == DK.Typeface.log.weight(.semibold))
    }

    // MARK: Rendering

    @Test
    func `the attributed text is the timestamp, two spaces, then the runs`() {
        let line = DKLogLine(ansi: "09:41:19 vphoned \(esc)[32mok\(esc)[0m", splitsTimestamp: true)
        let attributed = line.attributedText
        #expect(String(attributed.characters) == "09:41:19  vphoned ok")
        let colors = attributed.runs.map { $0[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] }
        #expect(colors == [DK.Palette.terminalDim, DK.Palette.terminalForeground, DK.Palette.terminalGreen])
    }

    @Test
    func `an ANSI line keeps the text without escapes`() {
        let line = DKLogLine(ansi: "\(esc)[1;31merror:\(esc)[0m disk full", tone: .error)
        #expect(line.text == "error: disk full")
        #expect(line.runs.first == DKLogRun("error:", style: DKLogStyle(color: .red, isBold: true)))
        #expect(line.tone == .error)
        #expect(line.timestamp == nil)
    }

    @Test
    func `an empty plain line has no runs`() {
        #expect(DKLogLine("").runs.isEmpty)
        #expect(DKLogLine("").text.isEmpty)
    }

    @Test
    func `search matches the message and the timestamp, ignoring case`() {
        let line = DKLogLine("SpringBoard[61] Ready", timestamp: "09:41:19.204")
        #expect(line.matches("springboard"))
        #expect(line.matches("09:41"))
        #expect(line.matches("  "))
        #expect(line.matches(""))
        #expect(!line.matches("backboardd"))
    }

    // MARK: Timestamps

    @Test(arguments: [
        ("09:41:19 booted", "09:41:19", "booted"),
        ("9:41:19.204  booted", "9:41:19.204", "booted"),
        ("09:41:19,5\tbooted", "09:41:19,5", "booted"),
        ("2026-10-05 09:41:19.204123+0800  0x1a2  Default", "2026-10-05 09:41:19.204123+0800", "0x1a2  Default"),
        ("2026-10-05T09:41:19Z booted", "2026-10-05T09:41:19Z", "booted"),
        ("2026-10-05T09:41:19.5-07:00 booted", "2026-10-05T09:41:19.5-07:00", "booted"),
        ("[09:41:19.204] booted", "[09:41:19.204]", "booted"),
        ("[2026-10-05 09:41:19] booted", "[2026-10-05 09:41:19]", "booted"),
        ("09:41:19", "09:41:19", ""),
    ])
    func `a leading timestamp is split off`(text: String, timestamp: String, message: String) {
        let split = DKLogLine.splitTimestamp(text)
        #expect(split.timestamp == timestamp)
        #expect(split.message == message)
    }

    @Test(arguments: [
        "booted at 09:41:19",
        "09:41 booted",
        "09:41:19booted",
        "2026-10-05 booted",
        "2026-10-05X09:41:19 booted",
        "[09:41:19 booted",
        "123:41:19 booted",
        "",
    ])
    func `text without a leading timestamp is left whole`(text: String) {
        let split = DKLogLine.splitTimestamp(text)
        #expect(split.timestamp == nil)
        #expect(split.message == text)
    }

    @Test
    func `a dangling fraction or zone is not part of the timestamp`() {
        #expect(DKLogLine.splitTimestamp("09:41:19. x").timestamp == nil)
        #expect(DKLogLine.splitTimestamp("09:41:19+ x").timestamp == nil)
        #expect(DKLogLine.splitTimestamp("09:41:19+08: x").timestamp == nil)
    }

    @Test
    func `the message after a timestamp keeps combining marks`() {
        #expect(DKLogLine.splitTimestamp("09:41:19 e\u{301}x").message == "e\u{301}x")
    }

    @Test
    func `a colored timestamp is split from the styled runs`() {
        let line = DKLogLine(ansi: "\(esc)[90m09:41:19\(esc)[0m \(esc)[31mfailed\(esc)[0m", splitsTimestamp: true)
        #expect(line.timestamp == "09:41:19")
        #expect(line.runs == [DKLogRun("failed", style: DKLogStyle(color: .red))])
    }

    @Test
    func `timestamps stay in the text unless asked for`() {
        #expect(DKLogLine(ansi: "09:41:19 booted").text == "09:41:19 booted")
    }

    // MARK: Buffer

    @Test
    func `the buffer splits a stream into lines`() {
        var buffer = DKLogBuffer()
        buffer.append("one\ntwo\r\nthree\n")
        #expect(buffer.lines.map(\.text) == ["one", "two", "three"])
    }

    @Test
    func `an unfinished line grows in place and keeps its identity`() {
        var buffer = DKLogBuffer()
        buffer.append("down")
        let id = buffer.lines.last?.id
        buffer.append("loading")
        #expect(buffer.lines.map(\.text) == ["downloading"])
        #expect(buffer.lines.last?.id == id)
        buffer.append(" done\nnext")
        #expect(buffer.lines.map(\.text) == ["downloading done", "next"])
        #expect(buffer.lines.first?.id == id)
        #expect(buffer.lines.last?.id != id)
    }

    @Test
    func `colors carry across lines and chunk boundaries`() {
        var buffer = DKLogBuffer()
        buffer.append("\(esc)[3")
        buffer.append("1mred\nstill red\(esc)[0m plain\n")
        #expect(buffer.lines.count == 2)
        #expect(buffer.lines[0].runs == [DKLogRun("red", style: DKLogStyle(color: .red))])
        #expect(buffer.lines[1].runs == [DKLogRun("still red", style: DKLogStyle(color: .red)), DKLogRun(" plain")])
    }

    @Test
    func `a carriage return starts the line over`() {
        var buffer = DKLogBuffer()
        buffer.append("progress 10%\rprogress 50%")
        #expect(buffer.lines.map(\.text) == ["progress 50%"])
        buffer.append("\r")
        #expect(buffer.lines.map(\.text) == ["progress 50%"])
        buffer.append("progress \(esc)[32m100%\(esc)[0m\n")
        #expect(buffer.lines.map(\.text) == ["progress 100%"])
        #expect(buffer.lines[0].runs.last == DKLogRun("100%", style: DKLogStyle(color: .green)))
    }

    @Test
    func `a carriage return split from its line feed is a plain break`() {
        var buffer = DKLogBuffer()
        buffer.append("one\r")
        buffer.append("\ntwo\n")
        #expect(buffer.lines.map(\.text) == ["one", "two"])
    }

    @Test
    func `empty lines are kept`() {
        var buffer = DKLogBuffer()
        buffer.append("a\n\nb\n")
        #expect(buffer.lines.map(\.text) == ["a", "", "b"])
    }

    @Test
    func `a chunk's tone applies to the lines it starts`() {
        var buffer = DKLogBuffer()
        buffer.append("partial", tone: .error)
        buffer.append(" rest\nnew\n", tone: .dim)
        #expect(buffer.lines.map(\.tone) == [.error, .dim])
    }

    @Test
    func `the buffer splits timestamps when asked`() {
        var buffer = DKLogBuffer(splitsTimestamps: true)
        buffer.append("09:41:19.204  SpringBoard[61] ready\n")
        #expect(buffer.lines.first?.timestamp == "09:41:19.204")
        #expect(buffer.lines.first?.text == "SpringBoard[61] ready")
    }

    @Test
    func `the buffer keeps only the newest lines up to its limit`() {
        var buffer = DKLogBuffer(limit: 3)
        for index in 1 ... 5 {
            buffer.append("line \(index)\n")
        }
        #expect(buffer.lines.map(\.text) == ["line 3", "line 4", "line 5"])
        buffer.limit = 1
        #expect(buffer.lines.map(\.text) == ["line 5"])
    }

    @Test
    func `appending a finished line closes the open one`() {
        var buffer = DKLogBuffer()
        buffer.append("prompt$ ")
        buffer.append(line: DKLogLine("ls", tone: .command))
        buffer.append("output\n")
        #expect(buffer.lines.map(\.text) == ["prompt$ ", "ls", "output"])
    }

    @Test
    func `clearing forgets lines, colors and open sequences`() {
        var buffer = DKLogBuffer()
        buffer.append("\(esc)[31mred\n\(esc)[")
        buffer.clear()
        #expect(buffer.lines.isEmpty)
        buffer.append("32mplain\n")
        #expect(buffer.lines.map(\.runs) == [[DKLogRun("32mplain")]])
    }

    @Test
    func `a stream of thousands of lines stays within its limit`() {
        var buffer = DKLogBuffer(limit: 1000)
        let chunk = (0 ..< 5000).map { "\(esc)[32mline\(esc)[0m \($0)" }.joined(separator: "\n") + "\n"
        buffer.append(chunk)
        #expect(buffer.lines.count == 1000)
        #expect(buffer.lines.last?.text == "line 4999")
    }

    // MARK: Filters and following

    @Test
    func `level filters admit lines by tone`() {
        #expect(DKLogLine.Tone.allCases.allSatisfy(DKLogLevelFilter.all.admits))
        #expect(DKLogLine.Tone.allCases.filter(DKLogLevelFilter.errors.admits) == [.warning, .error])
        #expect(DKLogLine.Tone.allCases.filter(DKLogLevelFilter.faults.admits) == [.error])
    }

    @Test
    func `the log counts as at the bottom within a few points of the end`() {
        #expect(DKLogScrollMetrics(offset: 600, viewportHeight: 400, contentHeight: 1000).isAtBottom)
        #expect(DKLogScrollMetrics(offset: 595, viewportHeight: 400, contentHeight: 1000).isAtBottom)
        #expect(!DKLogScrollMetrics(offset: 500, viewportHeight: 400, contentHeight: 1000).isAtBottom)
        #expect(DKLogScrollMetrics(offset: 0, viewportHeight: 400, contentHeight: 120).isAtBottom)
    }
}
