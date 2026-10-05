import Foundation
import Testing
@testable import VPhoneVirtualMachineKit

/// The value formats the Guest Tools pages share, and the JSON readers that
/// accept the guest's number and string spellings.
@Suite("Panel formats")
struct VPhonePanelFormatTests {
    @Test
    func `dates name today, as the design's "Today 09:41:02"`() {
        let locale = Locale(identifier: "en_US")
        let now = Date().timeIntervalSince1970
        #expect(VPhonePanelFormat.date(now, locale: locale).hasPrefix("Today"))
        #expect(VPhonePanelFormat.date(now - 86400, locale: locale).hasPrefix("Yesterday"))
        let old = VPhonePanelFormat.date(1_000_000_000, locale: locale)
        #expect(old.contains("2001"))
        #expect(VPhonePanelFormat.date(nil) == "—")
        #expect(VPhonePanelFormat.date(0) == "—")
    }

    @Test
    func `CPU time keeps three significant digits under a minute`() {
        #expect(VPhonePanelFormat.cpuTime(3.3) == "3.30 s")
        #expect(VPhonePanelFormat.cpuTime(12.4) == "12.4 s")
        #expect(VPhonePanelFormat.cpuTime(nil) == "—")
        #expect(VPhonePanelFormat.cpuTime(.nan) == "—")
        #expect(VPhonePanelFormat.cpuTime(301.7) == VPhonePanelFormat.duration(301.7))
    }

    @Test
    func `sizes, durations and percentages follow DKFormat`() {
        #expect(VPhonePanelFormat.bytes(8_589_934_592) == "8.00 GB")
        #expect(VPhonePanelFormat.bytes(182_000_000) == "174 MB")
        #expect(VPhonePanelFormat.duration(20) == "20 s")
        #expect(VPhonePanelFormat.duration(20.9) == "20 s")
        #expect(VPhonePanelFormat.duration(3 * 3600 + 12 * 60) == "3h 12m")
        #expect(VPhonePanelFormat.percent(0.48) == "48%")
    }

    @Test
    func `missing and impossible values read as a dash`() {
        #expect(VPhonePanelFormat.bytes(Int?.none) == "—")
        #expect(VPhonePanelFormat.bytes(Int64?.none) == "—")
        #expect(VPhonePanelFormat.duration(-1) == "—")
        #expect(VPhonePanelFormat.duration(.infinity) == "—")
        #expect(VPhonePanelFormat.percent(nil) == "—")
        #expect(VPhonePanelFormat.percent(.nan) == "—")
    }

    @Test
    func `JSON readers accept numbers and strings`() {
        let object: [String: Any] = [
            "int": NSNumber(value: 42), "intString": "42", "double": "0.5", "flag": "YES", "off": NSNumber(value: false),
            "nested": ["a": 1], "list": [["a": 1], ["a": 2]],
        ]
        #expect(object.int("int") == 42)
        #expect(object.int("intString") == 42)
        #expect(object.string("int") == "42")
        #expect(object.double("double") == 0.5)
        #expect(object.bool("flag") == true)
        #expect(object.bool("off") == false)
        #expect(object.bool("missing") == nil)
        #expect(object.object("nested")?.int("a") == 1)
        #expect(object.objects("list").count == 2)
        #expect(object.objects("nested").isEmpty)
    }
}
