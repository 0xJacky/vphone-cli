import Foundation
import Testing
@testable import VPhoneVirtualMachineKit

/// Crash reports from vphoned `logs.crashes` and `logs.crash`.
@Suite("Guest crash reports")
struct VPhoneCrashReportContentTests {
    private static let ips = """
    {"app_name":"Preferences","bug_type":"309","os_version":"iPhone OS 26.0 (23A341)","timestamp":"2026-10-05 09:41:08.00 +0800","incident_id":"6F1C2A54-0B7E-4E8A-9A11-3C2B1D0E9F77"}
    {"procName":"Preferences","pid":377,"exception":{"type":"EXC_BAD_ACCESS"},"threads":[]}
    """

    private func content(_ text: String, extra: [String: Any] = [:]) -> VPhoneCrashReportContent? {
        var result: [String: Any] = ["path": "/var/mobile/Library/Logs/CrashReporter/x.ips", "content": text]
        result.merge(extra) { $1 }
        return VPhoneCrashReportContent.Fields(crashResult: result).map(VPhoneCrashReportContent.init)
    }

    @Test
    func `an ips header line becomes the report facts`() throws {
        let report = try #require(content(Self.ips))
        let header = try #require(report.header)
        #expect(header.appName == "Preferences")
        #expect(header.bugType == "309")
        #expect(header.osVersion == "iPhone OS 26.0 (23A341)")
        #expect(header.timestamp == "2026-10-05 09:41:08.00 +0800")
        #expect(header.incidentID == "6F1C2A54-0B7E-4E8A-9A11-3C2B1D0E9F77")
        #expect(report.rawText == Self.ips)
    }

    @Test
    func `the app name falls back to name, then procName`() throws {
        let named = try #require(content("{\"name\":\"SpringBoard\"}\n{}"))
        #expect(named.header?.appName == "SpringBoard")
        let proc = try #require(content("{\"procName\":\"backboardd\"}\n{}"))
        #expect(proc.header?.appName == "backboardd")
        #expect(proc.header?.bugType == nil)
    }

    @Test
    func `the body is re-indented in its own key order`() throws {
        let report = try #require(content(Self.ips))
        #expect(report.isReindented)
        #expect(report.displayText == """
        {
          "procName": "Preferences",
          "pid": 377,
          "exception": {
            "type": "EXC_BAD_ACCESS"
          },
          "threads": []
        }
        """)
    }

    @Test
    func `a report that is not ips JSON is shown as it is`() throws {
        let text = "Incident Identifier: 1234\nCrashReporter Key: abc\n"
        let report = try #require(content(text))
        #expect(report.header == nil)
        #expect(report.displayText == text)
        #expect(!report.isReindented)

        // A JSON header over a text body keeps the facts and the body as sent.
        let mixed = try #require(content("{\"bug_type\":\"288\"}\nStackshot text"))
        #expect(mixed.header?.bugType == "288")
        #expect(mixed.displayText == "Stackshot text")
    }

    @Test
    func `base64 content is decoded and size and truncation are kept`() throws {
        let encoded = Data(Self.ips.utf8).base64EncodedString()
        let report = try #require(content(encoded, extra: ["encoding": "base64", "size": 99999, "truncated": true]))
        #expect(report.header?.appName == "Preferences")
        #expect(report.size == 99999)
        #expect(report.truncated)
        #expect(content("not base64!", extra: ["encoding": "base64"]) == nil)
    }

    @Test
    func `re-indenting refuses nesting past its limit`() {
        let deep = String(repeating: "[", count: VPhoneCrashReportContent.maxReindentDepth + 2)
            + String(repeating: "]", count: VPhoneCrashReportContent.maxReindentDepth + 2)
        #expect(VPhoneCrashReportContent.reindent(Substring(deep)) == nil)
        #expect(VPhoneCrashReportContent.reindent("{\"a\":\"x,{y}\"}") == "{\n  \"a\": \"x,{y}\"\n}")
    }

    @Test
    func `report kinds come from the file name`() {
        typealias Kind = VPhoneCrashReport.Kind
        #expect(Kind(fileName: "JetsamEvent-2026-10-05-093000.ips") == .jetsamEvent)
        #expect(Kind(fileName: "SpringBoard.cpu_resource-2026-10-05.ips") == .cpuResource)
        #expect(Kind(fileName: "panic-full-2026-10-05.ips") == .panic)
        #expect(Kind(fileName: "mediaserverd-2026-10-04.crash") == .legacyCrash)
        #expect(Kind(fileName: "Preferences-2026-10-05-094108.ips") == .ipsReport)
        #expect(Kind(fileName: "notes.txt") == .other)
        #expect(Kind.cpuResource.displayProcess("SpringBoard.cpu_resource") == "SpringBoard")
    }

    @Test
    func `a listed report needs a path and a safe name`() {
        let report = VPhoneCrashReport(json: ["path": "/var/mobile/Library/Logs/CrashReporter/a.ips", "process": "a", "size": 2048, "mtime": 0])
        #expect(report?.name == "a.ips")
        #expect(report?.dateText == "—")
        #expect(report?.kind == .ipsReport)
        #expect(VPhoneCrashReport(json: ["path": ""]) == nil)
        #expect(VPhoneCrashReport(json: ["path": "/x", "name": "../evil"]) == nil)
    }
}
