import Foundation
import Testing
@testable import VPhoneDesignKit

/// Disabled sidebar rows, the Bundles warning and the localizable titles.
@Suite("DesignKit sidebar state")
struct DKSidebarStateTests {
    private let sections = [
        DKSidebarSection("A", items: [
            DKSidebarItem(id: 1, label: "One", glyph: .info),
            DKSidebarItem(id: 2, label: "Two", glyph: .info, isEnabled: false),
        ]),
        DKSidebarSection("B", items: [
            DKSidebarItem(id: 3, label: "Three", glyph: .info),
            DKSidebarItem(id: 4, label: "Four", glyph: .info, isEnabled: false),
        ]),
    ]

    @Test
    func `arrow keys skip disabled rows`() {
        #expect(sections.sidebarItemID(from: 1, offset: 1) == 3)
        #expect(sections.sidebarItemID(from: 3, offset: -1) == 1)
        #expect(sections.sidebarItemID(from: 3, offset: 1) == 3)
        #expect(sections.sidebarItemID(from: nil, offset: -1) == 3)
    }

    @Test
    func `from a disabled row the arrows step to the nearest enabled one`() {
        #expect(sections.sidebarItemID(from: 2, offset: 1) == 3)
        #expect(sections.sidebarItemID(from: 2, offset: -1) == 1)
        #expect(sections.sidebarItemID(from: 4, offset: 1) == 3)
    }

    @Test
    func `a disabled row reads its reason`() {
        let item = DKSidebarItem(id: 1, label: "Keychain", glyph: .key, isEnabled: false, disabledReason: "Needs vphoned 2.6")
        #expect(item.accessibilityText == "Keychain, Needs vphoned 2.6")
        #expect(DKSidebarItem(id: 1, label: "Keychain", glyph: .key, disabledReason: "Ignored").accessibilityText == "Keychain")
    }

    @Test
    func `the launchpad sidebar can warn on Bundles`() throws {
        let items = DKLaunchpadSidebar.sections(bundleVersion: "2.6.0", bundlesNeedAttention: true).allSidebarItems()
        let bundles = try #require(items.first { $0.id == .bundles })
        #expect(bundles.isWarning)
        #expect(bundles.trailingText == "2.6.0")
        #expect(DKLaunchpadSidebar.sections().allSidebarItems().allSatisfy { !$0.isWarning })
    }

    @Test
    func `guest tools that are unavailable are disabled with their reason`() throws {
        let items = DKGuestSidebar.sections(unavailable: [.keychain: "Needs vphoned 2.6", .console: ""]).allSidebarItems()
        let keychain = try #require(items.first { $0.id == .keychain })
        #expect(!keychain.isEnabled)
        #expect(keychain.disabledReason == "Needs vphoned 2.6")
        let console = try #require(items.first { $0.id == .console })
        #expect(!console.isEnabled)
        #expect(items.filter(\.isEnabled).count == DKGuestTool.allCases.count - 2)
    }

    @Test
    func `titles fall back to English in a bundle without the keys`() {
        let bundle = Bundle(for: DKBundleToken.self)
        #expect(DKLaunchpadDestination.hostSetup.title(bundle: bundle) == "Host Setup")
        #expect(DKLaunchpadSection.system.title(bundle: bundle) == "System")
        #expect(DKGuestTool.crashLogs.title(bundle: bundle) == "Crash Logs")
        #expect(DKGuestToolSection.logs.title(bundle: bundle) == "Logs")
        #expect(DKGuestTool.deviceInfo.title == DKGuestTool.deviceInfo.title(bundle: .main))
    }
}

private final class DKBundleToken {}
