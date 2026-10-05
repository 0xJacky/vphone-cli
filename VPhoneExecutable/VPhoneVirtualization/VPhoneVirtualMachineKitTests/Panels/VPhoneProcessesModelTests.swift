import Foundation
import Testing
@testable import VPhoneVirtualMachineKit

/// How Processes reads `processes.list` and `memory.pressure`, filters and
/// sorts the rows, and picks signal targets.
@MainActor
@Suite("Processes")
struct VPhoneProcessesModelTests {
    static let processes: [[String: Any]] = [
        ["pid": 1, "name": "launchd", "executable": "/sbin/launchd", "ppid": 0, "uid": 0, "footprint_bytes": 9_400_000],
        ["pid": 61, "name": "SpringBoard", "executable": "/System/Library/CoreServices/SpringBoard.app/SpringBoard",
         "bundle_id": "com.apple.springboard", "ppid": 1, "uid": 501, "footprint_bytes": 182_000_000,
         "jetsam_priority": 0, "jetsam_limit_mb": -1],
        ["pid": 118, "name": "locationd", "executable": "/usr/libexec/locationd", "ppid": 1, "uid": 0,
         "footprint_bytes": 12_000_000, "jetsam_priority": 12, "jetsam_limit_mb": 60],
        ["pid": 312, "name": "vphoned", "executable": "/usr/bin/vphoned", "ppid": 1, "uid": 0, "footprint_bytes": 8_000_000],
        ["name": "no pid"],
    ]

    private func model() -> VPhoneProcessesModel {
        let model = VPhoneProcessesModel(control: VPhoneGuestControl())
        model.apply(processesResult: ["processes": Self.processes])
        return model
    }

    // MARK: - List

    @Test
    func `rows without a pid are dropped and the largest footprint comes first`() {
        let model = model()
        #expect(model.hasLoaded)
        #expect(model.rows.count == 4)
        #expect(model.visibleRows.map(\.pid) == [61, 118, 1, 312])
    }

    @Test
    func `sorting by pid orders the table numerically`() {
        let model = model()
        model.sortOrder = [KeyPathComparator(\VPhoneProcessRow.pid)]
        #expect(model.visibleRows.map(\.pid) == [1, 61, 118, 312])
    }

    @Test
    func `search matches an exact pid, a name, a bundle ID or a path`() {
        let model = model()
        let matches = { (query: String) -> [Int] in
            model.searchText = query
            return model.visibleRows.map(\.pid).sorted()
        }
        #expect(matches("312") == [312])
        #expect(matches("31") == [])
        #expect(matches("spring") == [61])
        #expect(matches("com.apple.SPRINGBOARD") == [61])
        #expect(matches("/usr/libexec") == [118])
        #expect(matches("  vphoned  ") == [312])
        #expect(matches("") == [1, 61, 118, 312])
    }

    @Test
    func `a reload drops selected processes that exited`() {
        let model = model()
        model.selection = [61, 312]
        model.apply(processesResult: ["processes": Array(Self.processes.prefix(2))])
        #expect(model.selection == [61])
    }

    // MARK: - Signals

    @Test
    func `launchd is never a signal target`() {
        let model = model()
        model.selection = [1]
        #expect(!model.canSignal)
        model.requestSignal(.term)
        #expect(model.pendingSignal == nil)

        model.selection = [1, 61]
        #expect(model.canSignal)
        model.requestSignal(.term)
        #expect(model.pendingSignal?.targets.map(\.pid) == [61])
    }

    @Test
    func `hidden rows are not signalled`() {
        let model = model()
        model.selection = [61, 118]
        model.searchText = "locationd"
        #expect(model.selectedRows.map(\.pid) == [118])
    }

    // MARK: - Row Formatting

    @Test
    func `users, limits and priorities read as the design shows them`() throws {
        let rows = model().rows
        let launchd = try #require(rows.first { $0.pid == 1 })
        let springBoard = try #require(rows.first { $0.pid == 61 })
        let locationd = try #require(rows.first { $0.pid == 118 })
        #expect(launchd.userTitle == "root")
        #expect(springBoard.userTitle == "mobile")
        #expect(launchd.jetsamPriorityTitle == "—")
        #expect(launchd.jetsamLimitTitle == "—")
        #expect(springBoard.jetsamPriorityTitle == "0")
        #expect(springBoard.jetsamLimitTitle == "None")
        #expect(locationd.jetsamLimitTitle == VPhonePanelFormat.bytes(Int64(60 * 1_048_576)))
        #expect(springBoard.bundleTitle == "com.apple.springboard")
        #expect(launchd.bundleTitle == "—")
        #expect(springBoard.reference == "SpringBoard (61)")
    }

    @Test
    func `a name the kernel cut short reads as the executable's name`() throws {
        let row = try #require(VPhoneProcessRow([
            "pid": 900, "name": "com.apple.Mobil",
            "executable": "/usr/libexec/com.apple.MobileSoftwareUpdate.Daemon",
        ]))
        #expect(row.displayName == "com.apple.MobileSoftwareUpdate.Daemon")
        let unnamed = try #require(VPhoneProcessRow(["pid": 901, "executable": "/usr/sbin/cfprefsd"]))
        #expect(unnamed.displayName == "cfprefsd")
        let nothing = try #require(VPhoneProcessRow(["pid": 902]))
        #expect(nothing.displayName == "—")
        #expect(nothing.userTitle == "—")
        #expect(VPhoneProcessRow(["pid": 903, "uid": 77])?.userTitle == "77")
    }

    // MARK: - Memory

    @Test
    func `the memory summary reads pressure and the share available`() {
        let summary = { (memory: [String: Any]) in VPhoneProcessMemorySummary(memory).summary }
        #expect(summary(["memorystatus_vm_pressure_level": 1, "memorystatus_level": 62]) == "normal, 62% available")
        #expect(summary(["memorystatus_vm_pressure_level": 2]) == "warning")
        #expect(summary(["memorystatus_vm_pressure_level": 4]) == "critical")
        #expect(summary(["memorystatus_level": 40]) == "40% available")
        #expect(summary([:]) == nil)

        let model = model()
        model.apply(jetsamResult: ["memory": ["hw_memsize": 8_589_934_592]])
        #expect(model.memory?.totalBytes == 8_589_934_592)
    }
}
