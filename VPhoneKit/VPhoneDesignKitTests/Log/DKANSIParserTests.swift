import Testing
@testable import VPhoneDesignKit

/// Terminal output turned into styled runs.
@Suite("DesignKit ANSI parser")
struct DKANSIParserTests {
    private let esc = "\u{1B}"

    // MARK: Plain text

    @Test
    func `text without escapes is one plain run`() {
        #expect(DKANSIParser.runs(in: "guest booted") == [DKLogRun("guest booted")])
    }

    @Test
    func `empty text has no runs`() {
        #expect(DKANSIParser.runs(in: "").isEmpty)
        #expect(DKANSIParser.runs(in: "\(esc)[31m\(esc)[0m").isEmpty)
    }

    @Test
    func `non-ASCII text passes through whole`() {
        #expect(DKANSIParser.strip("caf\u{E9} \u{1F4F1} 日本") == "caf\u{E9} \u{1F4F1} 日本")
    }

    // MARK: Colors

    @Test(arguments: [
        (30, DKLogColor.black), (31, .red), (32, .green), (33, .yellow),
        (34, .blue), (35, .magenta), (36, .cyan), (37, .white),
    ])
    func `base foreground codes name their hue`(code: Int, color: DKLogColor) {
        #expect(DKANSIParser.runs(in: "\(esc)[\(code)mx") == [DKLogRun("x", style: DKLogStyle(color: color))])
    }

    @Test(arguments: [
        (90, DKLogColor.gray), (91, .red), (92, .green), (93, .yellow),
        (94, .blue), (95, .magenta), (96, .cyan), (97, .white),
    ])
    func `bright foreground codes fold onto their hue and bright black is gray`(code: Int, color: DKLogColor) {
        #expect(DKANSIParser.runs(in: "\(esc)[\(code)mx") == [DKLogRun("x", style: DKLogStyle(color: color))])
    }

    @Test
    func `colored words become separate runs`() {
        let runs = DKANSIParser.runs(in: "status: \(esc)[32mok\(esc)[0m done")
        #expect(runs == [
            DKLogRun("status: "),
            DKLogRun("ok", style: DKLogStyle(color: .green)),
            DKLogRun(" done"),
        ])
    }

    @Test
    func `default foreground clears the color but keeps bold`() {
        let runs = DKANSIParser.runs(in: "\(esc)[1;31ma\(esc)[39mb")
        #expect(runs == [
            DKLogRun("a", style: DKLogStyle(color: .red, isBold: true)),
            DKLogRun("b", style: DKLogStyle(isBold: true)),
        ])
    }

    @Test
    func `background codes are ignored`() {
        #expect(DKANSIParser.runs(in: "\(esc)[41;104mx") == [DKLogRun("x")])
    }

    @Test
    func `extended color arguments are not read as codes`() {
        // `38;5;31` is palette color 31, not red; `38;2;1;31;32` is an RGB triple.
        #expect(DKANSIParser.runs(in: "\(esc)[38;5;31mx") == [DKLogRun("x")])
        #expect(DKANSIParser.runs(in: "\(esc)[38;2;1;31;32mx") == [DKLogRun("x")])
        #expect(DKANSIParser.runs(in: "\(esc)[38;5;200;32mx") == [DKLogRun("x", style: DKLogStyle(color: .green))])
        #expect(DKANSIParser.runs(in: "\(esc)[38:2::255:0:0;31mx") == [DKLogRun("x", style: DKLogStyle(color: .red))])
        #expect(DKANSIParser.runs(in: "\(esc)[48;5;1;1mx") == [DKLogRun("x", style: DKLogStyle(isBold: true))])
    }

    @Test
    func `a truncated extended color is skipped safely`() {
        #expect(DKANSIParser.runs(in: "\(esc)[38;5mx") == [DKLogRun("x")])
        #expect(DKANSIParser.runs(in: "\(esc)[38mx") == [DKLogRun("x")])
    }

    // MARK: Bold, faint and reset

    @Test
    func `bold and faint set and normal intensity clears both`() {
        let runs = DKANSIParser.runs(in: "\(esc)[1ma\(esc)[2mb\(esc)[22mc")
        #expect(runs == [
            DKLogRun("a", style: DKLogStyle(isBold: true)),
            DKLogRun("b", style: DKLogStyle(isBold: true, isFaint: true)),
            DKLogRun("c"),
        ])
    }

    @Test
    func `reset by zero, by an empty parameter list, and by an empty field`() {
        #expect(DKANSIParser.runs(in: "\(esc)[1;31ma\(esc)[0mb").last == DKLogRun("b"))
        #expect(DKANSIParser.runs(in: "\(esc)[1;31ma\(esc)[mb").last == DKLogRun("b"))
        #expect(DKANSIParser.runs(in: "\(esc)[1;31ma\(esc)[;32mb").last == DKLogRun("b", style: DKLogStyle(color: .green)))
    }

    @Test
    func `codes after a reset in the same sequence apply`() {
        #expect(DKANSIParser.runs(in: "\(esc)[31m\(esc)[0;1mx") == [DKLogRun("x", style: DKLogStyle(isBold: true))])
    }

    @Test
    func `unknown SGR codes change nothing`() {
        #expect(DKANSIParser.runs(in: "\(esc)[4;5;7;9;53;999mx") == [DKLogRun("x")])
    }

    @Test
    func `adjacent runs of one style merge`() {
        #expect(DKANSIParser.runs(in: "\(esc)[31ma\(esc)[31mb\(esc)[4mc") == [DKLogRun("abc", style: DKLogStyle(color: .red))])
    }

    // MARK: Other sequences

    @Test
    func `cursor and erase sequences are removed`() {
        #expect(DKANSIParser.strip("\(esc)[2K\(esc)[1Gprogress \(esc)[10;20H\(esc)[?25ldone\(esc)[?25h") == "progress done")
    }

    @Test
    func `a private-marker sequence ending in m is not applied`() {
        #expect(DKANSIParser.runs(in: "\(esc)[>4;2mx") == [DKLogRun("x")])
    }

    @Test
    func `a sequence with an intermediate byte is not applied`() {
        #expect(DKANSIParser.runs(in: "\(esc)[31 mx") == [DKLogRun("x")])
    }

    @Test
    func `OSC titles and hyperlinks are removed with either terminator`() {
        #expect(DKANSIParser.strip("\(esc)]0;window title\u{07}after") == "after")
        #expect(DKANSIParser.strip("\(esc)]8;;https://example.com\(esc)\\link\(esc)]8;;\(esc)\\ text") == "link text")
    }

    @Test
    func `DCS, APC, PM and SOS strings are removed`() {
        #expect(DKANSIParser.strip("a\(esc)Pq#0;2;0;0;0\(esc)\\b\(esc)_apc\(esc)\\c\(esc)^pm\u{07}d\(esc)Xsos\(esc)\\e") == "abcde")
    }

    @Test
    func `an unterminated string ends at a line feed`() {
        #expect(DKANSIParser.strip("\(esc)]0;title\nnext line") == "\nnext line")
    }

    @Test
    func `two-character and charset escapes are removed`() {
        #expect(DKANSIParser.strip("\(esc)7a\(esc)8\(esc)(Bb\(esc)=c\(esc)#8") == "abc")
    }

    @Test
    func `C1 control sequence introducers are understood`() {
        #expect(DKANSIParser.runs(in: "\u{9B}31mx") == [DKLogRun("x", style: DKLogStyle(color: .red))])
        #expect(DKANSIParser.strip("a\u{9D}0;title\u{9C}b") == "ab")
    }

    @Test
    func `control characters other than tab, line feed and carriage return are removed`() {
        #expect(DKANSIParser.strip("a\u{07}b\u{08}c\u{00}d\u{7F}e\u{85}f") == "abcdef")
        #expect(DKANSIParser.strip("a\tb\r\nc") == "a\tb\r\nc")
    }

    @Test
    func `a control character breaks off a sequence and is handled`() {
        #expect(DKANSIParser.strip("\(esc)[31\nx") == "\nx")
        #expect(DKANSIParser.strip("\(esc)[3\(esc)[32mx") == "x")
        #expect(DKANSIParser.runs(in: "\(esc)[3\(esc)[32mx") == [DKLogRun("x", style: DKLogStyle(color: .green))])
    }

    @Test
    func `a non-ASCII scalar inside a sequence ends it and is kept`() {
        #expect(DKANSIParser.strip("\(esc)[3\u{E9}") == "\u{E9}")
        #expect(DKANSIParser.strip("\(esc)\u{E9}") == "\u{E9}")
    }

    @Test
    func `a doubled escape starts one sequence`() {
        #expect(DKANSIParser.runs(in: "\(esc)\(esc)[31mx") == [DKLogRun("x", style: DKLogStyle(color: .red))])
    }

    // MARK: Partial sequences

    @Test(arguments: ["\u{1B}", "\u{1B}[", "\u{1B}[3", "\u{1B}[38;5", "\u{1B}]0;title", "\u{1B}]0;t\u{1B}", "\u{1B}("])
    func `an open sequence at the end of one-shot input is dropped`(tail: String) {
        #expect(DKANSIParser.strip("done" + tail) == "done")
    }

    @Test
    func `a sequence split across chunks is completed by the next chunk`() {
        var parser = DKANSIParser()
        #expect(parser.feed("a\(esc)[3") == [DKLogRun("a")])
        #expect(parser.isInsideSequence)
        #expect(parser.feed("1mb") == [DKLogRun("b", style: DKLogStyle(color: .red))])
        #expect(!parser.isInsideSequence)
    }

    @Test
    func `a lone escape at the end of a chunk joins the next chunk`() {
        var parser = DKANSIParser()
        #expect(parser.feed("a\(esc)") == [DKLogRun("a")])
        #expect(parser.feed("[1mb") == [DKLogRun("b", style: DKLogStyle(isBold: true))])
    }

    @Test
    func `a string terminator split across chunks is recognized`() {
        var parser = DKANSIParser()
        #expect(parser.feed("\(esc)]0;title\(esc)").isEmpty)
        #expect(parser.feed("\\after") == [DKLogRun("after")])
    }

    @Test
    func `style carries from one chunk to the next until reset`() {
        var parser = DKANSIParser()
        _ = parser.feed("\(esc)[33mfirst")
        #expect(parser.style == DKLogStyle(color: .yellow))
        #expect(parser.feed(" second") == [DKLogRun(" second", style: DKLogStyle(color: .yellow))])
        parser.reset()
        #expect(parser.style == .plain)
        #expect(parser.feed("third") == [DKLogRun("third")])
    }
}
