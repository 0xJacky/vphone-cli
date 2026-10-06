import Foundation

/// The Machines page's logic without its views: the machine menu's order and
/// enablement in each state, the patch editor's pending classification and
/// counts, the creation step strip, the sheets' field helpers and the log
/// translation the embedded terminal is fed through.
@main
struct MachinesLogicTests {
    static func expect(_ condition: Bool, _ message: @autoclosure () -> String, line: Int = #line) {
        precondition(condition, "line \(line): \(message())")
    }

    static func main() throws {
        menus()
        try patches()
        steps()
        fields()
        logs()
        terminal()
        print("MachinesLogicTests passed")
    }

    // MARK: - Terminal

    static func terminal() {
        typealias Failure = VPhoneLaunchpadTerminalFailure
        // A bundle from before the Terminal does not know the command.
        expect(Failure.reason(forDetail: "unknown command: terminal")?.contains("Core Bundle") == true, "old bundle")
        // A headless launch has no window to open it in.
        expect(Failure.reason(forDetail: "terminal needs a VM window; this launch is headless")?.contains("without a window") == true, "headless")
        // Anything else is shown as it came.
        expect(Failure.reason(forDetail: "guest not connected") == nil, "other errors pass through")
        expect(Failure.reason(forDetail: nil) == nil, "no detail")
    }

    // MARK: - Machine menu

    typealias Menu = VPhoneLaunchpadMachineMenu
    typealias Entry = Menu.Entry
    typealias Action = Menu.Action

    /// The menu as text: one action per entry, `-` for a separator, a
    /// trailing `!` when disabled, and a submenu's children in brackets.
    static func outline(_ entries: [Entry]) -> String {
        entries.map { entry in
            switch entry {
            case .separator:
                return "-"
            case let .item(action, isEnabled):
                return "\(action)\(isEnabled ? "" : "!")"
            case let .submenu(action, isEnabled, children):
                return "\(action)\(isEnabled ? "" : "!")[\(outline(children))]"
            }
        }
        .joined(separator: " ")
    }

    static func menus() {
        let stopped = Menu.Machine(run: .stopped, hasPatchLog: true)
        expect(
            outline(Menu.entries(for: [stopped])) ==
                "start startHeadless - openConsole showInFinder logs[consoleLog patchLog] - settings rename clone export - coreBundle[changeBundle updateGuestEnvironment installCustomFirmware!] - delete",
            outline(Menu.entries(for: [stopped])),
        )

        // Running: Stop alone runs; what needs a stopped machine dims, but a
        // new Core Bundle may be chosen for the next start.
        let running = Menu.Machine(run: .running)
        expect(
            outline(Menu.entries(for: [running])) ==
                "stop - openConsole showInFinder logs[consoleLog patchLog!] - settings! rename! clone! export! - coreBundle[changeBundle updateGuestEnvironment! installCustomFirmware!] - delete!",
            outline(Menu.entries(for: [running])),
        )

        // Being created: Show Progress, and a Core Bundle submenu with
        // nothing to offer is dimmed as a whole.
        let creating = Menu.Machine(run: .busy, isCreating: true, isRestored: false, customFirmwareInstalled: nil, canChangeBundle: false)
        expect(
            outline(Menu.entries(for: [creating])) ==
                "showProgress - openConsole showInFinder logs[consoleLog patchLog!] - settings! rename! clone! export! - coreBundle![changeBundle! updateGuestEnvironment! installCustomFirmware!] - delete!",
            outline(Menu.entries(for: [creating])),
        )

        // Being exported: Cancel Export instead of Start.
        let exporting = Menu.Machine(run: .busy, isExporting: true)
        expect(outline(Menu.entries(for: [exporting])).hasPrefix("cancelExport - openConsole"), outline(Menu.entries(for: [exporting])))
        expect(Menu.entries(for: [exporting]).contains(.submenu(.coreBundle, isEnabled: true, children: [
            .item(.changeBundle, isEnabled: true),
            .item(.updateGuestEnvironment, isEnabled: false),
            .item(.installCustomFirmware, isEnabled: false),
        ])), "an exporting machine may change its Core Bundle")

        // Busy otherwise (stopping, installing): Start stays, dimmed.
        expect(outline(Menu.entries(for: [Menu.Machine(run: .busy)])).hasPrefix("start! startHeadless! -"), "busy run group")

        // An unfinished install offers Install Custom Firmware, not the update.
        let unfinished = Menu.Machine(run: .stopped, customFirmwareInstalled: false)
        expect(
            outline(Menu.entries(for: [unfinished])).contains("coreBundle[changeBundle updateGuestEnvironment! installCustomFirmware]"),
            outline(Menu.entries(for: [unfinished])),
        )
        // A machine never restored has no guest environment to update.
        let unrestored = Menu.Machine(run: .stopped, isRestored: false)
        expect(outline(Menu.entries(for: [unrestored])).contains("updateGuestEnvironment!"), "unrestored machine")
        // No bundle to change to.
        let noBundles = Menu.Machine(run: .stopped, canChangeBundle: false)
        expect(outline(Menu.entries(for: [noBundles])).contains("coreBundle[changeBundle! updateGuestEnvironment"), "no bundles")

        // Several: the batch actions only, gated on every machine stopped.
        expect(
            outline(Menu.entries(for: [stopped, running])) ==
                "start startHeadless stop - showInFinder - settings! export! - changeBundle - delete!",
            outline(Menu.entries(for: [stopped, running])),
        )
        expect(
            outline(Menu.entries(for: [stopped, stopped])) ==
                "start startHeadless stop! - showInFinder - settings export - changeBundle - delete",
            outline(Menu.entries(for: [stopped, stopped])),
        )
        expect(outline(Menu.entries(for: [running, exporting])).hasPrefix("cancelExport - start! startHeadless! stop -"), "batch export")
        expect(outline(Menu.entries(for: [stopped, creating])).contains("changeBundle!"), "a creation keeps its bundle")

        // The menu bar keeps Start, Start Headless and Stop in place.
        expect(outline(Menu.entries(for: [running], placement: .menuBar)).hasPrefix("start! startHeadless! stop -"), "menu bar running")
        expect(outline(Menu.entries(for: [stopped], placement: .menuBar)).hasPrefix("start startHeadless stop! -"), "menu bar stopped")
        expect(
            outline(Menu.entries(for: [creating], placement: .menuBar)).hasPrefix("showProgress start! startHeadless! stop! -"),
            outline(Menu.entries(for: [creating], placement: .menuBar)),
        )
        // Past the run group the menu bar and the context menu agree.
        for machine in [stopped, running, creating, exporting, unfinished] {
            let bar = Menu.entries(for: [machine], placement: .menuBar)
            let context = Menu.entries(for: [machine])
            expect(Array(bar.drop { $0 != .separator }) == Array(context.drop { $0 != .separator }), "\(machine)")
        }

        // Nothing selected: an empty context menu, a dimmed menu bar menu of
        // the usual shape.
        expect(Menu.entries(for: []).isEmpty, "no context menu without a machine")
        let none = Menu.entries(for: [], placement: .menuBar)
        expect(
            outline(none) ==
                "start! startHeadless! stop! - openConsole! showInFinder! logs![consoleLog! patchLog!] - settings! rename! clone! export! - coreBundle![changeBundle! updateGuestEnvironment! installCustomFirmware!] - delete!",
            outline(none),
        )
    }

    // MARK: - Patches

    typealias Catalog = VPhoneLaunchpadPatchCatalog
    typealias Tally = VPhoneLaunchpadPatchTally

    static func patch(
        _ identifier: String,
        part: String,
        inPreset: Bool,
        pending: Bool?,
        wanted: Bool?,
        delivery: String? = nil,
        enabled: Bool? = nil,
    ) -> [String: Any] {
        var patch: [String: Any] = [
            "identifier": identifier,
            "title": identifier,
            "summary": "",
            "patchSet": part == "Guest" ? "com.vphone.patchset.guest" : "com.vphone.patchset.bootchain",
            "patchSetName": part == "Guest" ? "Guest" : "Boot Chain",
            "target": part,
            "applicability": "any",
            "bootEssential": false,
            "inPreset": inPreset,
            "part": part,
        ]
        patch["pending"] = pending
        patch["wanted"] = wanted
        patch["delivery"] = delivery
        patch["enabled"] = enabled ?? wanted
        return patch
    }

    static func catalog(_ patches: [[String: Any]], blocked: [String] = [], installed: Bool? = true) throws -> Catalog {
        var payload: [String: Any] = [
            "activePreset": "standard",
            "blockedPatches": blocked,
            "allowedPatches": [String](),
            "presets": [["identifier": "standard", "title": "Standard", "summary": ""]],
            "patches": patches,
        ]
        payload["installed"] = installed
        payload["pendingPatches"] = patches.count { $0["pending"] as? Bool == true }
        return try JSONDecoder().decode(Catalog.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    static func patches() throws {
        // A guest patch the guest lacks, a kernel patch turned off but still
        // in the kernelcache, AVPBooter and iBSS as wanted, and TXM off.
        let catalog = try catalog([
            patch("dyld-cfw-camera", part: "Guest", inPreset: true, pending: true, wanted: true, delivery: "update-environment"),
            patch("kernel-cfw-debugger", part: "kernelcache", inPreset: true, pending: true, wanted: false, delivery: "update-kernel"),
            patch("avpbooter-boot-dgst_bypass", part: "AVPBooter", inPreset: true, pending: false, wanted: true),
            patch("txm-cfw-get_task_allow", part: "TXM", inPreset: false, pending: false, wanted: false),
            patch("ibss-cfw-serial_label", part: "iBSS", inPreset: true, pending: false, wanted: true),
        ], blocked: ["kernel-cfw-debugger"])
        var selection = catalog.selection
        let initiallyOn = Set(catalog.patches.filter { selection.isOn($0) }.map(\.identifier))
        expect(initiallyOn == ["dyld-cfw-camera", "avpbooter-boot-dgst_bypass", "ibss-cfw-serial_label"], "\(initiallyOn)")

        // Delivery: the bundle's word, else the part.
        let kinds = catalog.patches.map(\.deliveryKind)
        expect(kinds == [.updateEnvironment, .updateKernel, .firmwarePatch, .restore, .restore], "\(kinds)")
        expect(catalog.patches[4].isRestoreOnlyStage && !catalog.patches[3].isRestoreOnlyStage, "iBSS is restore-only")
        expect(catalog.pendingGuestPatches == 1 && catalog.pendingKernelPatches == 1 && catalog.pendingRestorePatches == 0, "pending by kind")

        let opened = Tally(catalog: catalog, selection: selection, initiallyOn: initiallyOn, isMachine: true)
        expect(opened.total == 5 && opened.on == 3 && opened.changed == 1 && opened.edited == 0, "\(opened)")
        expect(opened.pending == 2, "\(opened)")
        expect(opened.pendingByDelivery == [.updateEnvironment: ["dyld-cfw-camera"], .updateKernel: ["kernel-cfw-debugger"]], "\(opened.pendingByDelivery)")

        // Turning TXM on: one more on, changed and edited, and pending, and
        // only a restore brings it.
        selection.set(catalog.patches[3], on: true)
        let edited = Tally(catalog: catalog, selection: selection, initiallyOn: initiallyOn, isMachine: true)
        expect(edited.on == 4 && edited.changed == 2 && edited.edited == 1 && edited.pending == 3, "\(edited)")
        expect(edited.pendingByDelivery[.restore] == ["txm-cfw-get_task_allow"], "\(edited.pendingByDelivery)")

        // Turning the kernel patch back on agrees with what the kernelcache
        // has, so it is no longer pending, and agrees with the preset.
        selection.set(catalog.patches[1], on: true)
        let back = Tally(catalog: catalog, selection: selection, initiallyOn: initiallyOn, isMachine: true)
        expect(back.pending == 2 && back.changed == 1 && back.edited == 2, "\(back)")
        expect(back.pendingByDelivery[.updateKernel] == nil, "\(back.pendingByDelivery)")
        expect(selection.blocked.isEmpty && selection.allowed == ["txm-cfw-get_task_allow"], "overrides")

        // New Machine has no guest to compare with.
        let newMachine = Tally(catalog: catalog, selection: selection, initiallyOn: nil, isMachine: false)
        expect(newMachine.pending == nil && newMachine.pendingByDelivery.isEmpty && newMachine.edited == 0, "\(newMachine)")
        expect(Tally.isPending(catalog.patches[0], selection: selection, initiallyOn: nil, isMachine: false) == nil, "no machine")

        // An older bundle reports no `pending`: the status is unknown.
        let older = try self.catalog([
            patch("dyld-cfw-camera", part: "Guest", inPreset: true, pending: nil, wanted: nil),
        ], installed: nil)
        expect(!Tally.showsStatus(older, isMachine: true), "older bundle")
        expect(Tally(catalog: older, selection: older.selection, initiallyOn: [], isMachine: true).pending == nil, "older bundle tally")

        // A version gate leaving a wanted patch out: on changes nothing.
        let gated = try self.catalog([
            patch("kernel-exp-gated", part: "kernelcache", inPreset: true, pending: false, wanted: false, enabled: true),
        ])
        expect(gated.patches[0].isGatedOut, "gated out")
        expect(gated.patches[0].isPending(on: true, savedOn: true) == false, "gated patch is not pending")
    }

    // MARK: - Creation steps

    static func steps() {
        typealias Format = VPhoneLaunchpadMachineFormat
        expect(Format.segment(.done, progress: nil) == (1, .success), "done")
        expect(Format.segment(.failed, progress: 0.3) == (1, .danger), "failed")
        expect(Format.segment(.active, progress: 0.63) == (0.63, .warning), "active")
        expect(Format.segment(.active, progress: nil) == (0, .warning), "active without progress")
        expect(Format.segment(.active, progress: 1.4) == (1, .warning), "clamped")
        expect(Format.segment(.pending, progress: 0.5) == (0, .warning), "pending")

        let states: [Format.StepState] = [.done, .active] + Array(repeating: .pending, count: 7)
        expect(Format.currentStepNumber(states) == 2, "step 2 of 9")
        expect(Format.currentStepNumber([.done, .done, .failed, .pending]) == 3, "failed step")
        expect(Format.currentStepNumber(Array(repeating: .done, count: 9)) == nil, "finished")
        expect(Format.currentStepNumber(Array(repeating: .pending, count: 9)) == nil, "not started")
    }

    // MARK: - Fields

    static func fields() {
        typealias Format = VPhoneLaunchpadMachineFormat
        expect(Format.memory(8192) == "8 GB", Format.memory(8192))
        expect(Format.memory(3000) == "3000 MB", Format.memory(3000))
        expect(Format.disk(64_000_000_000) == "64 GB", Format.disk(64_000_000_000))
        expect(Format.disk(64_999_999_999) == "64 GB", "disk rounds down")

        expect(Format.forwardArgument(transport: "tcp", hostPort: "8022", guestPort: "22", onAllAddresses: false) == "tcp:127.0.0.1:8022:22", "local forward")
        expect(Format.forwardArgument(transport: "udp", hostPort: " 5353 ", guestPort: "53", onAllAddresses: true) == "udp:0.0.0.0:5353:53", "shared forward")
        for (host, guest) in [("", "22"), ("0", "22"), ("65536", "22"), ("80", "x"), ("80", "-1")] {
            expect(Format.forwardArgument(transport: "tcp", hostPort: host, guestPort: guest, onAllAddresses: false) == nil, "\(host) → \(guest)")
        }
        expect(Format.forwardLabel("tcp:127.0.0.1:2222:22") == "TCP 2222 → 22", Format.forwardLabel("tcp:127.0.0.1:2222:22"))
        expect(Format.forwardHost("tcp:127.0.0.1:2222:22") == "127.0.0.1", "local host")
        expect(Format.forwardHost("udp:0.0.0.0:5353:53") == "0.0.0.0", "shared host")
        expect(Format.forwardLabel("odd") == "odd" && Format.forwardHost("odd") == nil, "not a forward")

        for _ in 0 ..< 64 {
            let mac = Format.randomMACAddress()
            expect(Format.isMACAddress(mac), mac)
            let first = UInt8(mac.prefix(2), radix: 16) ?? 0
            expect(first & 0x01 == 0 && first & 0x02 == 0x02, "unicast, locally administered: \(mac)")
        }
        expect(Format.isMACAddress("5e:3a:91:0c:7d:21") && !Format.isMACAddress("5e:3a:91:0c:7d") && !Format.isMACAddress("5e:3a:91:0c:7d:zz"), "MAC shape")

        expect(Format.localHostName(for: "research-26") == "research-26", "plain")
        expect(Format.localHostName(for: "pcc_research.2") == "pcc-research-2", Format.localHostName(for: "pcc_research.2"))
        expect(Format.localHostName(for: "__a__b__") == "a-b", Format.localHostName(for: "__a__b__"))
        expect(Format.localHostName(for: "研究") == "vphone", "no ASCII")
        expect(Format.localHostName(for: String(repeating: "a", count: 80)).count == 63, "one DNS label")
        expect(Format.localHostName(for: String(repeating: "a", count: 62) + "_b") == String(repeating: "a", count: 62), "no trailing hyphen")
    }

    // MARK: - Logs

    static func logs() {
        var plain = VPhoneLaunchpadLogTranslator()
        expect(plain.translate(Data("a\nb\r\nc".utf8)) == Data("a\r\nb\r\nc".utf8), "line feeds return")
        expect(plain.translate(Data("\n".utf8)) == Data("\r\n".utf8), "across chunks")

        expect(VPhoneLaunchpadLogStyle.creationTone(of: "$ vphone-cli fw prepare") == .command, "command")
        expect(VPhoneLaunchpadLogStyle.creationTone(of: "✕ restore failed") == .error, "error")
        expect(VPhoneLaunchpadLogStyle.creationTone(of: "● done") == .success, "success")
        expect(VPhoneLaunchpadLogStyle.creationTone(of: "warning: low space") == .warning, "warning")
        expect(VPhoneLaunchpadLogStyle.creationTone(of: "restore  Sending RestoreRamDisk") == nil, "plain")

        // A creation log holds a partial line back until its end arrives.
        var creation = VPhoneLaunchpadLogTranslator(style: .creation)
        expect(creation.translate(Data("$ vphone-cli re".utf8)).isEmpty, "partial line")
        let out = String(decoding: creation.translate(Data("store\r\nplain\n".utf8)), as: UTF8.self)
        expect(out == "\u{1B}[34m$ vphone-cli restore\u{1B}[0m\r\nplain\r\n", out.debugDescription)

        translatorChunks()
        splitter()
        panicLines()
        writer()
    }

    // MARK: - Console throughput

    /// A console log as a guest prints it: plain lines, coloured lines,
    /// bare and doubled line ends, progress redraws, blank lines, a creation
    /// log's marks and a little invalid UTF-8.
    static func consoleSample(lines: Int, seed: UInt64) -> Data {
        var random = SplitMix(seed: seed)
        let pieces: [String] = [
            "set_dir_stats:3204: disk1s7 setting dir-stats for ino 1234 parent 2",
            "\u{1B}[32m[vphoned]\u{1B}[0m ping ok",
            "\u{1B}[1;31mpanic(cpu 0 caller 0xfffffff0): \u{1B}[0m",
            "progress 12 100\r",
            "   \t ",
            "",
            "$ vphone-cli restore ios27-rc",
            "✕ restore failed",
            "● done",
            "warning: low space",
            "\u{1B}[?25l\u{1B}[2K redraw\u{1B}[",
            "\u{1B}x not a sequence \u{1B}[12;",
            "Stackshot succeeded",
            "spanic? ppanic unpanic",
            "研究 \u{3000} ok",
        ]
        var data = Data()
        for _ in 0 ..< lines {
            data.append(contentsOf: pieces[Int(random.next() % UInt64(pieces.count))].utf8)
            switch random.next() % 10 {
            case 0: data.append(contentsOf: [0x0D, 0x0A])
            case 1: data.append(0x0D)
            case 2: data.append(contentsOf: [0xE2, 0x9C])
            default: data.append(0x0A)
            }
        }
        return data
    }

    /// `data` cut at random points, some cuts inside a line, a CR LF pair or
    /// a UTF-8 sequence.
    static func chunks(of data: Data, seed: UInt64) -> [Data] {
        var random = SplitMix(seed: seed)
        var result: [Data] = []
        var start = data.startIndex
        while start < data.endIndex {
            let length = 1 + Int(random.next() % 300)
            let end = min(start + length, data.endIndex)
            result.append(Data(data[start ..< end]))
            start = end
        }
        return result
    }

    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// The translator's output does not depend on where the reads cut the
    /// log, and matches the byte-at-a-time and line-at-a-time translation it
    /// replaced.
    static func translatorChunks() {
        for seed in UInt64(1) ... 6 {
            let log = consoleSample(lines: 3000, seed: seed)
            let parts = chunks(of: log, seed: seed &* 31)
            for style in [VPhoneLaunchpadLogStyle.plain, .creation] {
                var whole = VPhoneLaunchpadLogTranslator(style: style)
                var cut = VPhoneLaunchpadLogTranslator(style: style)
                var reference = ReferenceTranslator(style: style)
                let expected = parts.reduce(into: Data()) { $0.append(reference.translate($1)) }
                let joined = parts.reduce(into: Data()) { $0.append(cut.translate($1)) }
                expect(whole.translate(log) == expected, "\(style) whole, seed \(seed)")
                expect(joined == expected, "\(style) chunked, seed \(seed)")
            }
        }
        var plain = VPhoneLaunchpadLogTranslator()
        expect(plain.translate(Data()).isEmpty, "empty chunk")
        expect(plain.translate(Data("a\r".utf8)) == Data("a\r".utf8), "CR at a chunk's end")
        expect(plain.translate(Data("\nb\n".utf8)) == Data("\nb\r\n".utf8), "its LF gains nothing")
        expect(plain.translate(Data("\n\n".utf8)) == Data("\r\n\r\n".utf8), "empty lines")
        var creation = VPhoneLaunchpadLogTranslator(style: .creation)
        expect(creation.translate(Data("● do".utf8)).isEmpty, "partial mark")
        let done = String(decoding: creation.translate(Data("ne\nwarn".utf8)), as: UTF8.self)
        expect(done == "\u{1B}[32m● done\u{1B}[0m\r\n", done.debugDescription)
        let warning = String(decoding: creation.translate(Data("ing: x\r\nwarn\n".utf8)), as: UTF8.self)
        expect(warning == "\u{1B}[33mwarning: x\u{1B}[0m\r\nwarn\r\n", warning.debugDescription)
    }

    /// The translation before it worked a chunk at a time.
    struct ReferenceTranslator {
        let style: VPhoneLaunchpadLogStyle
        var previous: UInt8 = 0
        var pending = Data()

        mutating func translate(_ data: Data) -> Data {
            switch style {
            case .plain:
                var output = Data()
                for byte in data {
                    if byte == 0x0A, previous != 0x0D {
                        output.append(0x0D)
                    }
                    output.append(byte)
                    previous = byte
                }
                return output
            case .creation:
                pending.append(data)
                var output = Data()
                while let end = pending.firstIndex(of: 0x0A) {
                    var line = pending[pending.startIndex ..< end]
                    if line.last == 0x0D {
                        line = line.dropLast()
                    }
                    let text = String(decoding: line, as: UTF8.self)
                    if let tone = VPhoneLaunchpadLogStyle.creationTone(of: text) {
                        output.append(Data((VPhoneLaunchpadLogStyle.escape(tone) + text + VPhoneLaunchpadLogStyle.reset).utf8))
                    } else {
                        output.append(line)
                    }
                    output.append(contentsOf: [0x0D, 0x0A])
                    pending = Data(pending[pending.index(after: end)...])
                }
                return output
            }
        }
    }

    /// The line splitter gives the lines the regular-expression splitter it
    /// replaced gave, wherever the reads cut the output.
    static func splitter() {
        func reference(_ data: Data) -> [String] {
            var buffer = data
            var lines: [String] = []
            func emit(_ bytes: Data) {
                let text = String(decoding: bytes, as: UTF8.self)
                    .replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    lines.append(text)
                }
            }
            while let end = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                emit(buffer[buffer.startIndex ..< end])
                buffer.removeSubrange(buffer.startIndex ... end)
            }
            emit(buffer)
            return lines
        }
        for seed in UInt64(1) ... 6 {
            let log = consoleSample(lines: 3000, seed: seed)
            var splitter = VPhoneLaunchpadLineSplitter()
            var lines: [String] = []
            for part in chunks(of: log, seed: seed &* 17) {
                splitter.feed(part) { lines.append($0) }
            }
            splitter.flush { lines.append($0) }
            let expected = reference(log)
            expect(lines == expected, "seed \(seed): \(lines.count) lines, expected \(expected.count)")
        }
        var splitter = VPhoneLaunchpadLineSplitter()
        var lines: [String] = []
        splitter.feed(Data("\u{1B}[1;32mok\u{1B}[0m\r\n \u{2003}\t\nrest".utf8)) { lines.append($0) }
        expect(lines == ["ok"], "colour dropped, blank lines skipped: \(lines)")
        splitter.feed(Data(" of it".utf8)) { lines.append($0) }
        splitter.flush { lines.append($0) }
        expect(lines == ["ok", "rest of it"], "partial line across chunks: \(lines)")
        expect(VPhoneLaunchpadLineSplitter.strippingEscapes("a\u{1B}[b\u{1B}") == "a\u{1B}", "ESC [ with no parameters ends at its final byte; a trailing ESC stays")
        expect(VPhoneLaunchpadLineSplitter.strippingEscapes("a\u{1B}[12;\u{1B}[0m研") == "a\u{1B}[12;研", "an unfinished sequence stays")
    }

    /// The panic check agrees with the pattern it compiles once.
    static func panicLines() {
        let lines = [
            "panic(cpu 0 caller 0xfffffff0)", "Kernel Panic", "PANIC", "xnu: kernel panic", "https://panic.apple.com/",
            "spanic", "ppanic", "PPANIC", "Ppanic", "unpanic", "stackshot succeeded", "Stackshot SUCCEEDED",
            "ſtackshot ſucceeded", "pstackshot succeeded", "stackshot  succeeded", "pani c", "set_dir_stats:3204: disk1s7",
            "", "p", "panic", "\u{1B}[31mpanic\u{1B}[0m", "研究panic",
        ]
        for line in lines {
            let expected = line.range(of: VPhoneLaunchpadPanicLine.pattern, options: [.regularExpression, .caseInsensitive]) != nil
            expect(VPhoneLaunchpadPanicLine.matches(line) == expected, "\(line.debugDescription) should be \(expected)")
        }
        expect(VPhoneLaunchpadPanicLine.contains("xPaNiC", "panic"), "any ASCII case")
        expect(!VPhoneLaunchpadPanicLine.contains("pan", "panic"), "shorter than the word")
        expect(!VPhoneLaunchpadPanicLine.contains("p@nic", "panic"), "only letters fold")
    }

    /// The writer keeps every line, in order, however many arrive at once,
    /// and the last twelve for error details.
    static func writer() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("writer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("create.log")
        let writer = VPhoneLaunchpadLogWriter(url: url)
        let count = 20000
        DispatchQueue.concurrentPerform(iterations: 4) { worker in
            for index in 0 ..< count / 4 {
                writer.write("\(worker) \(index)")
            }
        }
        var text = ""
        for _ in 0 ..< 500 {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if text.split(separator: "\n").count == count {
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        let lines = text.split(separator: "\n")
        expect(lines.count == count, "\(lines.count) of \(count) lines written")
        for worker in 0 ..< 4 {
            let own = lines.filter { $0.hasPrefix("\(worker) ") }.map { Int($0.split(separator: " ")[1])! }
            expect(own == Array(0 ..< count / 4), "worker \(worker)'s lines in order")
        }
        expect(writer.tail.split(separator: "\n").count == 12, "tail keeps twelve lines")
    }
}
