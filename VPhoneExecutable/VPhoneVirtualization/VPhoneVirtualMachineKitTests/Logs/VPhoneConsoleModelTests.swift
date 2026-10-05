import Foundation
import Testing
@testable import VPhoneVirtualMachineKit

/// Console rows from vphoned `logs.syslog`, and the level and search filters.
@MainActor
@Suite("Guest console")
struct VPhoneConsoleModelTests {
    private func model() -> VPhoneConsoleModel {
        let model = VPhoneConsoleModel(control: VPhoneGuestControl())
        func entry(_ level: String, _ process: String, _ subsystem: String, _ message: String) -> [String: Any] {
            ["date": "2026-10-05T09:41:19Z", "level": level, "process": process, "pid": 61, "subsystem": subsystem, "category": "cat", "message": message]
        }
        model.apply(syslogResult: ["entries": [
            entry("notice", "SpringBoard", "com.apple.SpringBoard", "Application launched"),
            entry("info", "backboardd", "com.apple.backboardd", "Event dispatched"),
            entry("debug", "vphoned", "com.vphone.vphoned", "processes.list served 214 rows"),
            entry("error", "mediaserverd", "com.apple.coremedia", "Audio route not ready\nRetrying"),
            entry("fault", "locationd", "com.apple.locationd", "Unexpected nil client for café"),
        ], "truncated": true])
        return model
    }

    @Test
    func `levels read from the guest's names`() {
        #expect(VPhoneConsoleLevel(guestValue: "notice") == .notice)
        #expect(VPhoneConsoleLevel(guestValue: "default") == .notice)
        #expect(VPhoneConsoleLevel(guestValue: "INFO") == .info)
        #expect(VPhoneConsoleLevel(guestValue: "Debug") == .debug)
        #expect(VPhoneConsoleLevel(guestValue: "error") == .error)
        #expect(VPhoneConsoleLevel(guestValue: "fault") == .fault)
        #expect(VPhoneConsoleLevel(guestValue: nil) == .notice)
        #expect(VPhoneConsoleLevel.notice.title == "Default")
    }

    @Test
    func `entries arrive in order with consecutive ids`() {
        let model = model()
        #expect(model.entries.map(\.id) == [0, 1, 2, 3, 4])
        #expect(model.visibleEntries.map(\.process) == ["SpringBoard", "backboardd", "vphoned", "mediaserverd", "locationd"])
        #expect(model.lastCaptureTruncated)
        #expect(model.newestVisibleID == 4)
        #expect(!model.isFiltered)
    }

    @Test
    func `the table shows a message's first line`() {
        let entry = model().entries[3]
        #expect(entry.summary == "Audio route not ready…")
        #expect(entry.message == "Audio route not ready\nRetrying")
        #expect(VPhoneConsoleEntry.summary(of: "one line") == "one line")
        let long = String(repeating: "x", count: VPhoneConsoleEntry.summaryLimit + 10)
        #expect(VPhoneConsoleEntry.summary(of: long).count == VPhoneConsoleEntry.summaryLimit + 1)
    }

    @Test
    func `the level filter keeps errors and faults, or faults only`() {
        let model = model()
        model.levelFilter = .error
        #expect(model.visibleEntries.map(\.level) == [.error, .fault])
        #expect(model.isFiltered)
        model.levelFilter = .fault
        #expect(model.visibleEntries.map(\.level) == [.fault])
        #expect(model.newestVisibleID == 4)
        model.levelFilter = .all
        #expect(model.visibleEntries.count == 5)
    }

    @Test
    func `search matches message, process and subsystem without case or accents`() {
        let model = model()
        model.searchText = "ROUTE"
        #expect(model.visibleEntries.map(\.process) == ["mediaserverd"])
        model.searchText = "backboard"
        #expect(model.visibleEntries.map(\.process) == ["backboardd"])
        model.searchText = "com.vphone"
        #expect(model.visibleEntries.map(\.process) == ["vphoned"])
        model.searchText = "cafe"
        #expect(model.visibleEntries.map(\.process) == ["locationd"])
        model.searchText = "  "
        #expect(model.visibleEntries.count == 5)
        #expect(!model.isFiltered)
    }

    @Test
    func `search and level filter combine`() {
        let model = model()
        model.searchText = "com.apple"
        model.levelFilter = .error
        #expect(model.visibleEntries.map(\.process) == ["mediaserverd", "locationd"])
        model.levelFilter = .fault
        #expect(model.visibleEntries.map(\.process) == ["locationd"])
    }

    @Test
    func `saved lines carry the date, level, process and origin`() {
        let model = model()
        let text = model.logText([model.entries[3]])
        #expect(text.hasSuffix(" Error   mediaserverd[61] (com.apple.coremedia:cat) Audio route not ready\nRetrying\n"))
        #expect(model.logText([]).isEmpty)
    }

    @Test
    func `Clear empties the console`() {
        let model = model()
        model.selection = [1]
        model.clear()
        #expect(model.entries.isEmpty)
        #expect(model.visibleEntries.isEmpty)
        #expect(model.selection.isEmpty)
        #expect(!model.lastCaptureTruncated)
    }

    @Test
    func `capture parameters carry the level and a trimmed process name`() {
        let model = model()
        model.levelFilter = .fault
        model.processFilter = "  SpringBoard "
        let params = model.captureParameters
        #expect(params["level"] as? String == "fault")
        #expect(params["process"] as? String == "SpringBoard")
        model.processFilter = " "
        #expect(model.captureParameters["process"] == nil)
    }
}
