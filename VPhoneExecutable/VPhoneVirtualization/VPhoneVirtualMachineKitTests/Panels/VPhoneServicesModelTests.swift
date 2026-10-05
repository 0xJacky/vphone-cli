import Foundation
import Testing
@testable import VPhoneVirtualMachineKit

/// How Services reads launchd's services, filters them, and words their
/// state and last exit.
@MainActor
@Suite("Services")
struct VPhoneServicesModelTests {
    static let services: [[String: Any]] = [
        ["label": "com.apple.SpringBoard", "domains": ["system"], "pid": 61, "running": true, "last_exit_status": 0,
         "program": "/System/Library/CoreServices/SpringBoard.app/SpringBoard"],
        ["label": "com.apple.backboardd", "domains": ["system"], "pid": 58, "last_exit_status": 0, "program": "/usr/libexec/backboardd"],
        ["label": "com.vphone.vphoned", "domains": ["system"], "pid": 312, "running": true, "program": "/usr/bin/vphoned"],
        ["label": "com.apple.crashreportd", "domains": ["system"], "pid": 0, "running": false, "last_exit_status": 9,
         "program": "/usr/libexec/crashreportd"],
        ["label": "com.apple.ReportCrash", "domains": ["system"], "running": false, "disabled": true, "program": "/usr/libexec/ReportCrash"],
        ["label": ""],
    ]

    private func model() -> VPhoneServicesModel {
        let model = VPhoneServicesModel(control: VPhoneGuestControl())
        model.apply(listResult: ["services": Self.services])
        return model
    }

    // MARK: - List

    @Test
    func `rows sort by label and count the running ones`() {
        let model = model()
        #expect(model.hasLoaded)
        #expect(model.visibleRows.map(\.label) == [
            "com.apple.backboardd", "com.apple.crashreportd", "com.apple.ReportCrash", "com.apple.SpringBoard", "com.vphone.vphoned",
        ])
        #expect(model.runningCount == 3)
    }

    @Test
    func `filters show running, stopped or disabled services`() {
        let model = model()
        model.filter = .running
        #expect(Set(model.visibleRows.map(\.label)) == ["com.apple.SpringBoard", "com.apple.backboardd", "com.vphone.vphoned"])
        model.filter = .stopped
        #expect(Set(model.visibleRows.map(\.label)) == ["com.apple.crashreportd", "com.apple.ReportCrash"])
        model.filter = .disabled
        #expect(model.visibleRows.map(\.label) == ["com.apple.ReportCrash"])
        // The count of running services is the whole list's, not the filter's.
        #expect(model.runningCount == 3)
    }

    @Test
    func `search matches the label or the program path`() {
        let model = model()
        model.searchText = "springboard"
        #expect(model.visibleRows.map(\.label) == ["com.apple.SpringBoard"])
        model.searchText = "/usr/libexec"
        #expect(Set(model.visibleRows.map(\.label)) == ["com.apple.backboardd", "com.apple.crashreportd", "com.apple.ReportCrash"])
        model.searchText = "  "
        #expect(model.visibleRows.count == 5)
    }

    @Test
    func `a selection the filter hides is cleared`() {
        let model = model()
        model.selection = "com.apple.SpringBoard"
        #expect(model.selectedRow?.pid == 61)
        model.filter = .stopped
        #expect(model.selection == nil)
        #expect(model.selectedRow == nil)
    }

    // MARK: - Rows

    @Test
    func `a row reads its pid, running state and override`() throws {
        let backboardd = try #require(VPhoneServiceRow(Self.services[1]))
        // No `running` key: a pid means it runs.
        #expect(backboardd.isRunning)
        #expect(backboardd.pidText == "58")

        let crashreportd = try #require(VPhoneServiceRow(Self.services[3]))
        #expect(!crashreportd.isRunning)
        #expect(crashreportd.pid == nil)
        #expect(crashreportd.pidText == "—")

        // `services.list` carries `disabled` only for overridden labels;
        // `services.status` carries `override` and `enabled`.
        #expect(backboardd.disabled == nil)
        #expect(backboardd.disabledText == "—")
        #expect(VPhoneServiceRow(Self.services[4])?.disabledText == "Yes")
        #expect(VPhoneServiceRow(["label": "a", "override": true, "enabled": false])?.disabled == true)
        #expect(VPhoneServiceRow(["label": "a", "override": true, "enabled": true])?.disabledText == "No")
        #expect(VPhoneServiceRow(["label": "a", "override": false, "enabled": false])?.disabled == nil)
        #expect(VPhoneServiceRow(["label": ""]) == nil)
    }

    @Test
    func `the last exit decodes the wait status`() {
        let text = { (status: Int?) in VPhoneServiceExit(status: status).text }
        #expect(text(nil) == "—")
        #expect(text(0) == "0")
        #expect(text(256) == "1")
        #expect(text(9) == "SIGKILL")
        #expect(text(0x80 | 11) == "SIGSEGV+core")
        #expect(text(-15) == "SIGTERM")
        #expect(text(-64) == "SIG64")
        #expect(!VPhoneServiceExit(status: 0).isAbnormal)
        #expect(VPhoneServiceExit(status: 9).isAbnormal)
    }
}
