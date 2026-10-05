import Foundation
import Testing
@testable import VPhoneVirtualMachineKit

/// How Apps reads `apps.list`, filters and counts the apps, and which
/// actions it offers for them.
@MainActor
@Suite("Apps")
struct VPhoneAppBrowserModelTests {
    static let apps: [[String: Any]] = [
        ["bundle_id": "com.example.app", "name": "Example", "version": "1.0", "build": "1", "type": "User", "pid": 418,
         "path": "/private/var/containers/Bundle/Application/1A2B/Example.app"],
        ["bundle_id": "com.apple.Preferences", "name": "Settings", "type": "system", "pid": 377],
        ["bundle_id": "com.apple.mobilesafari", "name": "Safari", "type": "system", "pid": 0],
        ["bundle_id": "com.example.unnamed", "type": "user", "bundle_path": "/var/containers/Bundle/Application/X/Unnamed.app"],
        ["name": "No Bundle ID"],
    ]

    private func model() -> VPhoneAppBrowserModel {
        let model = VPhoneAppBrowserModel(control: VPhoneGuestControl())
        model.apply(listResult: ["apps": Self.apps])
        return model
    }

    @Test
    func `apps without a bundle ID are dropped and the rest sort by name`() {
        let model = model()
        #expect(model.hasLoaded)
        #expect(model.filteredApps.map(\.displayName) == ["com.example.unnamed", "Example", "Safari", "Settings"])
    }

    @Test
    func `filters show running, user or system apps`() {
        let model = model()
        model.filter = .running
        #expect(Set(model.filteredApps.map(\.bundleID)) == ["com.example.app", "com.apple.Preferences"])
        model.filter = .user
        #expect(Set(model.filteredApps.map(\.bundleID)) == ["com.example.app", "com.example.unnamed"])
        model.filter = .system
        #expect(Set(model.filteredApps.map(\.bundleID)) == ["com.apple.Preferences", "com.apple.mobilesafari"])
    }

    @Test
    func `search matches the name or the bundle ID, ignoring case`() {
        let model = model()
        model.searchText = "SAFARI"
        #expect(model.filteredApps.map(\.bundleID) == ["com.apple.mobilesafari"])
        model.searchText = "com.example"
        #expect(model.filteredApps.count == 2)
        model.searchText = " settings "
        #expect(model.filteredApps.map(\.name) == ["Settings"])
    }

    @Test
    func `the count says how many of the apps show`() {
        let model = model()
        #expect(model.countText == "4 apps")
        model.filter = .system
        #expect(model.countText == "2 of 4 apps")
        model.apply(listResult: ["apps": [Self.apps[0]]])
        model.filter = .all
        #expect(model.countText == "1 app")
    }

    @Test
    func `a record reads its type, name and paths`() throws {
        let app = try #require(VPhoneAppRecord(json: Self.apps[0]))
        #expect(!app.isSystem)
        #expect(app.typeTitle == "User")
        #expect(app.isRunning)
        #expect(app.bundlePath.hasSuffix("Example.app"))
        let unnamed = try #require(VPhoneAppRecord(json: Self.apps[3]))
        #expect(unnamed.displayName == "com.example.unnamed")
        #expect(unnamed.bundlePath == "/var/containers/Bundle/Application/X/Unnamed.app")
        #expect(!unnamed.isRunning)
        #expect(VPhoneAppRecord(json: Self.apps[1])?.typeTitle == "System")
    }

    @Test
    func `a reload keeps only the selected apps still installed`() {
        let model = model()
        model.selection = ["com.example.app", "com.apple.mobilesafari"]
        model.apply(listResult: ["apps": Array(Self.apps.prefix(2))])
        #expect(model.selection == ["com.example.app"])
        #expect(model.selectedApp?.name == "Example")
    }

    @Test
    func `actions need a connected guest, and system apps cannot be uninstalled`() {
        let model = model()
        let user: Set<String> = ["com.example.app"]
        // The guest is not connected.
        #expect(!model.canLaunch(user))
        #expect(!model.canTerminate(user))
        #expect(!model.canUninstall(user))
        #expect(!model.canUninstall(["com.apple.Preferences"]))
    }
}
