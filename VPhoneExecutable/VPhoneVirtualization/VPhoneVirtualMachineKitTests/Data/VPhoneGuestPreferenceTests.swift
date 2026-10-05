import Foundation
import Testing
@testable import VPhoneVirtualMachineKit

/// Preference values read from vphoned `settings.get` and typed for `settings.set`.
@MainActor
@Suite("Guest preferences")
struct VPhoneGuestPreferenceTests {
    // MARK: - Writing

    @Test
    func `write types use the wire names settings.set expects`() {
        #expect(VPhoneGuestPreferenceType.allCases.map(\.rawValue) == ["string", "bool", "int", "float"])
    }

    @Test
    func `Boolean accepts true, false and their usual spellings`() throws {
        for text in ["true", "YES", " 1 "] {
            #expect(try VPhoneGuestPreferenceType.bool.parse(text).get() as? Bool == true, "\(text)")
        }
        for text in ["false", "no", "0"] {
            #expect(try VPhoneGuestPreferenceType.bool.parse(text).get() as? Bool == false, "\(text)")
        }
        #expect(throws: VPhoneGuestPreferenceParseError.self) { try VPhoneGuestPreferenceType.bool.parse("maybe").get() }
    }

    @Test
    func `numbers must be whole for Integer and finite for Float`() throws {
        #expect(try VPhoneGuestPreferenceType.int.parse(" 42 ").get() as? Int64 == 42)
        #expect(try VPhoneGuestPreferenceType.int.parse("-7").get() as? Int64 == -7)
        #expect(throws: VPhoneGuestPreferenceParseError.self) { try VPhoneGuestPreferenceType.int.parse("4.2").get() }
        #expect(try VPhoneGuestPreferenceType.float.parse("1.25").get() as? Double == 1.25)
        #expect(throws: VPhoneGuestPreferenceParseError.self) { try VPhoneGuestPreferenceType.float.parse("inf").get() }
        #expect(throws: VPhoneGuestPreferenceParseError.self) { try VPhoneGuestPreferenceType.float.parse("abc").get() }
    }

    @Test
    func `String keeps the text exactly`() throws {
        #expect(try VPhoneGuestPreferenceType.string.parse("  en_US \n").get() as? String == "  en_US \n")
    }

    // MARK: - Reading

    @Test
    func `values map to their kinds and summaries`() {
        func entry(_ value: Any?) -> VPhoneGuestPreferenceEntry {
            VPhoneGuestPreferenceEntry(key: "k", value: value)
        }
        #expect(entry(true).kind == .bool)
        #expect(entry(true).summary == "true")
        #expect(entry(10).kind == .int)
        #expect(entry(10).summary == "10")
        #expect(entry(1.25).kind == .float)
        #expect(entry(1.25).summary == "1.25")
        #expect(entry("en_US").kind == .string)
        #expect(entry(Date(timeIntervalSince1970: 0)).summary == "1970-01-01T00:00:00Z")
        #expect(entry(Data(count: 2048)).kind == .data)
        #expect(entry(NSNull()).kind == .null)
        #expect(entry(nil).summary == "—")
        #expect(entry(["a"]).summary == "1 item")
        #expect(entry(["a": 1, "b": 2]).summary == "2 keys")
    }

    @Test
    func `only scalars round-trip through the write form`() {
        #expect(VPhoneGuestPreferenceEntry(key: "k", value: "s").writableType == .string)
        #expect(VPhoneGuestPreferenceEntry(key: "k", value: false).writableType == .bool)
        #expect(VPhoneGuestPreferenceEntry(key: "k", value: 3).writableType == .int)
        #expect(VPhoneGuestPreferenceEntry(key: "k", value: 0.5).writableType == .float)
        #expect(VPhoneGuestPreferenceEntry(key: "k", value: [1]).writableType == nil)
        #expect(VPhoneGuestPreferenceEntry(key: "k", value: Date()).writableType == nil)
    }

    @Test
    func `collections become an outline with paths as ids`() throws {
        let entry = VPhoneGuestPreferenceEntry(key: "AppleKeyboards", value: ["en_US@sw=QWERTY", "emoji@sw=Emoji"])
        let children = try #require(entry.children)
        #expect(children.map(\.key) == ["[0]", "[1]"])
        #expect(children.map(\.id) == ["AppleKeyboards/0", "AppleKeyboards/1"])
        #expect(children.map(\.summary) == ["en_US@sw=QWERTY", "emoji@sw=Emoji"])

        let dictionary = VPhoneGuestPreferenceEntry(key: "D", value: ["b": 1, "a10": 2, "a2": 3])
        #expect(dictionary.children?.map(\.key) == ["a2", "a10", "b"])
    }

    @Test
    func `a whole domain reads as sorted keys and pretty JSON`() {
        let result = VPhoneGuestPreferenceReadResult(
            domain: ".GlobalPreferences",
            key: nil,
            value: ["AppleLocale": "en_US", "AppleLanguages": ["en-US"], "NSRecentsLimit": 10],
        )
        #expect(result.entries.map(\.key) == ["AppleLanguages", "AppleLocale", "NSRecentsLimit"])
        #expect(result.title == ".GlobalPreferences")
        #expect(result.text == """
        {
          "AppleLanguages" : [
            "en-US"
          ],
          "AppleLocale" : "en_US",
          "NSRecentsLimit" : 10
        }
        """)
    }

    @Test
    func `one key reads as one entry, a missing one as nothing`() {
        let one = VPhoneGuestPreferenceReadResult(domain: "com.apple.springboard", key: "SBIdleTimer", value: 30)
        #expect(one.entries.map(\.key) == ["SBIdleTimer"])
        #expect(one.text == "30")
        #expect(one.title == "com.apple.springboard › SBIdleTimer")

        let missing = VPhoneGuestPreferenceReadResult(domain: "com.apple.springboard", key: "Nope", value: nil)
        #expect(missing.entries.isEmpty)
        #expect(missing.text.isEmpty)
    }

    // MARK: - Model

    @Test
    func `a read result fills the write form for a top-level scalar`() throws {
        let model = VPhoneGuestPreferencesModel(control: VPhoneGuestControl())
        model.domain = ".GlobalPreferences"
        model.apply(readValue: ["AppleLocale": "en_US", "AppleKeyboards": ["a"]], domain: ".GlobalPreferences", key: nil)
        #expect(model.status == nil)
        #expect(model.canCopyResult)

        let result = try #require(model.readResult)
        let locale = try #require(result.entries.first { $0.key == "AppleLocale" })
        let keyboards = try #require(result.entries.first { $0.key == "AppleKeyboards" })
        #expect(model.canEdit(locale))
        #expect(!model.canEdit(keyboards))
        let nested = try #require(keyboards.children?.first)
        #expect(!model.canEdit(nested))

        model.edit(locale, switchToWrite: true)
        #expect(model.mode == .write)
        #expect(model.writeKey == "AppleLocale")
        #expect(model.writeType == .string)
        #expect(model.writeValue == "en_US")
        #expect(model.currentWriteValue?.summary == "en_US")
        #expect(model.focusRequest == .value)
    }

    @Test
    func `an empty read says so in the status`() {
        let model = VPhoneGuestPreferencesModel(control: VPhoneGuestControl())
        model.apply(readValue: nil, domain: "com.example", key: "missing")
        #expect(model.status?.isError == false)
        #expect(model.status?.message == "missing is not set in com.example.")
        #expect(!model.canCopyResult)
    }
}
