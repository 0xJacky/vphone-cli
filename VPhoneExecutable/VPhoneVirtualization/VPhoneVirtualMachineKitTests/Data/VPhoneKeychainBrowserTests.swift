import Foundation
import Testing
@testable import VPhoneVirtualMachineKit

/// Keychain rows from vphoned `keychain_list`, their TSV copy and filtering.
@MainActor
@Suite("Guest keychain")
struct VPhoneKeychainBrowserTests {
    private static let entries: [[String: Any]] = [
        ["class": "genp", "account": "user@example.com", "service": "com.example.app.token", "accessGroup": "ABCDE12345.com.example.app", "protection": "ak", "valueEncoding": "hidden", "source": "security", "modified": 1_790_000_000.0],
        ["class": "inet", "account": "admin", "server": "router.local", "accessGroup": "apple", "protection": "ck", "value": "hunter2", "valueEncoding": "utf8", "source": "security"],
        ["class": "cert", "label": "Example Root CA", "accessGroup": "com.apple.certificates", "protection": "dk", "value": "AAAA", "valueEncoding": "base64", "valueSize": 1342, "source": "security"],
        ["class": "keys", "label": "Device Key", "accessGroup": "com.apple.security", "protection": "akpu", "valueEncoding": "protected", "protectedMetadata": true, "_rowid": 12],
    ]

    private func items() -> [VPhoneKeychainItem] {
        Self.entries.enumerated().compactMap { VPhoneKeychainItem(index: $0.offset, entry: $0.element) }
    }

    private func model() -> VPhoneKeychainBrowserModel {
        let model = VPhoneKeychainBrowserModel(control: VPhoneGuestControl())
        model.items = items()
        return model
    }

    // MARK: - Items

    @Test
    func `rows parse with stable ids by source`() {
        let items = items()
        #expect(items.map(\.id) == ["genp-security-0", "inet-security-1", "cert-security-2", "keys-database-12"])
        #expect(items.map(\.isAccessible) == [true, true, true, false])
        #expect(items[0].modified == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(VPhoneKeychainItem(index: 0, entry: ["account": "no class"]) == nil)
    }

    @Test
    func `values and protection read as the table shows them`() {
        let items = items()
        #expect(items.map(\.displayValue) == ["Hidden", "hunter2", "Binary data (1.31 KB)", "Protected"])
        #expect(items.map(\.displayClass) == ["Password", "Internet", "Certificate", "Cryptographic Key"])
        #expect(items.map(\.protectionDescription) == [
            "When Unlocked", "After First Unlock", "Always", "When Passcode Set (This Device Only)",
        ])
        #expect(items.map(\.displayName) == ["user@example.com", "admin", "Example Root CA", "Device Key"])
    }

    // MARK: - TSV

    @Test
    func `Copy Row writes a header and one line per row in table order`() throws {
        let model = model()
        let ids = Set(model.items.map(\.id))
        let lines = try #require(model.rowsTSV(ids: ids)).components(separatedBy: "\n")
        #expect(lines.first == "Class\tAccount\tService\tAccess Group\tProtection\tValue")
        #expect(lines.count == 5)
        // Sorted by name: admin, Device Key, Example Root CA, user@example.com.
        #expect(lines[1] == "Internet\tadmin\t\tapple\tck\thunter2")
        #expect(lines[4] == "Password\tuser@example.com\tcom.example.app.token\tABCDE12345.com.example.app\tak\tHidden")
        #expect(lines.allSatisfy { $0.components(separatedBy: "\t").count == 6 })
    }

    @Test
    func `TSV fields never split a row`() {
        #expect(VPhoneKeychainBrowserModel.tsvField("a\tb\nc\r\nd") == "a b c d")
        let model = VPhoneKeychainBrowserModel(control: VPhoneGuestControl())
        model.items = [VPhoneKeychainItem(index: 0, entry: ["class": "genp", "account": "multi\nline", "value": "x\ty", "valueEncoding": "utf8", "source": "security"])!]
        let text = model.rowsTSV(ids: [model.items[0].id])
        #expect(text?.components(separatedBy: "\n").count == 2)
        #expect(text?.hasSuffix("Password\tmulti line\t\t\t\tx y") == true)
    }

    @Test
    func `TSV covers only rows that are shown`() {
        let model = model()
        model.filterClass = "inet"
        #expect(model.rowsTSV(ids: ["genp-security-0"]) == nil)
        #expect(model.rowsTSV(ids: Set(model.items.map(\.id)))?.components(separatedBy: "\n").count == 2)
    }

    // MARK: - Filtering

    @Test
    func `the type filter keeps one class`() {
        let model = model()
        model.filterClass = "cert"
        #expect(model.filteredItems.map(\.id) == ["cert-security-2"])
        model.filterClass = nil
        #expect(model.filteredItems.count == 4)
    }

    @Test
    func `search matches any column without case`() {
        let model = model()
        model.searchText = "ROUTER"
        #expect(model.filteredItems.map(\.itemClass) == ["inet"])
        model.searchText = "com.apple"
        #expect(Set(model.filteredItems.map(\.itemClass)) == ["cert", "keys"])
        model.searchText = "akpu"
        #expect(model.filteredItems.map(\.itemClass) == ["keys"])
        model.searchText = "nothing matches"
        #expect(model.filteredItems.isEmpty)
    }

    @Test
    func `the count says how many of the items are shown`() {
        let model = model()
        #expect(model.statusText == "4 items")
        model.filterClass = "genp"
        #expect(model.statusText == "1 of 4 items")
    }

    @Test
    func `only rows Security.framework answered for can be acted on`() {
        let model = model()
        let all = Set(model.items.map(\.id))
        #expect(Set(model.editableItems(ids: all).map(\.id)) == ["genp-security-0", "inet-security-1", "cert-security-2"])
    }
}
