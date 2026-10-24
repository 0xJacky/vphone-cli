import Foundation
import Testing
@testable import VPhoneCoreKit

struct RemoteDiskMachineTests {
    // MARK: - Fixtures

    private struct Fixture {
        let root: URL
        let library: VPhoneLibrary
        let manifest: URL
        let rom: URL
        let seprom: URL

        var folder: URL { library.url(forName: "st-1") }
        var state: URL { folder.appendingPathComponent("MachineState") }
    }

    /// A template's config.plist with an identity and network settings a
    /// clone must not keep, and a machine folder holding only a MachineState
    /// with the template's state files and identity record in it.
    private func makeFixture(stateFiles: [String] = ["nvram.bin", "SEPStorage", "identity.plist"]) throws -> Fixture {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let rom = root.appendingPathComponent("rom.bin")
        let seprom = root.appendingPathComponent("seprom.bin")
        try Data([0xAA]).write(to: rom)
        try Data([0xBB]).write(to: seprom)

        let templates = VPhoneLibrary(root: root.appendingPathComponent("templates"))
        let template = try VPhoneBundleOperations.create(
            .init(name: "tpl", cpuCount: 2, memoryMB: 1024, diskSizeGB: 1, romSource: rom, sepromSource: rom),
            in: templates,
        )
        let network = template.manifest.networkConfig.with(
            macAddress: "02:00:00:00:00:01",
            ipv4: .some(.init(address: "192.168.64.20", prefixLength: 24)),
            portForwards: .some([.init(hostPort: 8022, guestPort: 22)]),
        )
        try template.manifest.updating(machineIdentifier: Data([0xEC, 0x1D]), networkConfig: network)
            .write(to: template.configURL)

        let library = VPhoneLibrary(root: root.appendingPathComponent("machines"))
        let state = library.url(forName: "st-1").appendingPathComponent("MachineState")
        try fm.createDirectory(at: state, withIntermediateDirectories: true)
        for name in stateFiles {
            try Data(name.utf8).write(to: state.appendingPathComponent(name))
        }
        return Fixture(root: root, library: library, manifest: template.configURL, rom: rom, seprom: seprom)
    }

    private func spec(_ fixture: Fixture, timeout: Double = 60) throws -> VPhoneRemoteDiskMachine {
        try VPhoneRemoteDiskMachine(
            name: "st-1",
            disk: VPhoneNBDLocation(parsing: "nbd://10.41.2.2:17600/vm-st-1-disk.tok"),
            timeoutSeconds: timeout,
            manifestSource: fixture.manifest,
        )
    }

    private func create(_ fixture: Fixture, timeout: Double = 60) throws -> VPhoneBundle {
        try VPhoneBundleOperations.createOnRemoteDisk(
            spec(fixture, timeout: timeout), in: fixture.library, romSource: fixture.rom, sepromSource: fixture.seprom,
        )
    }

    private func entries(_ url: URL) throws -> Set<String> {
        try Set(FileManager.default.contentsOfDirectory(atPath: url.path))
    }

    // MARK: - Making the machine

    @Test func `completes the folder around the mounted state with a new identity`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let bundle = try create(fixture)
        let manifest = bundle.manifest

        #expect(manifest.diskLocation.manifestValue == "nbd://10.41.2.2:17600/vm-st-1-disk.tok")
        #expect(manifest.nbd?.effectiveTimeout == 60)
        #expect(VPhoneMachineStateLayout.kind(of: manifest) == .stateDirectory)
        #expect(manifest.machineIdentifier.isEmpty)
        #expect(manifest.networkConfig.macAddress.isEmpty)
        #expect(manifest.networkConfig.ipv4 == nil)
        #expect(manifest.networkConfig.portForwards == nil)
        #expect(manifest.cpuCount == 2)

        let folder = try entries(fixture.folder)
        #expect(!folder.contains("Disk.img"))
        #expect(folder.contains("config.plist"))
        #expect(folder.contains(try #require(manifest.romImages?.avpBooter)))
        #expect(folder.contains(try #require(manifest.romImages?.avpSEPBooter)))
        // The first boot writes a new identity; the template's must be gone.
        #expect(try entries(fixture.state) == ["nvram.bin", "SEPStorage"])
        #expect(try Data(contentsOf: fixture.state.appendingPathComponent("SEPStorage")) == Data("SEPStorage".utf8))
        #expect(throws: Never.self) { try VPhoneMachineStateLayout.requireLaunchable(bundle) }
        #expect(try VPhoneBundle.load(at: fixture.folder).manifest.diskLocation.isNetwork)
    }

    @Test(arguments: [5.0, 59.0])
    func `refuses an NBD timeout shorter than a storage node's stalls`(timeout: Double) throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(throws: VPhoneRemoteDiskMachineError.timeoutTooShort(timeout)) {
            try create(fixture, timeout: timeout)
        }
        #expect(try entries(fixture.folder) == ["MachineState"])
    }

    @Test func `refuses a MachineState without the template's SEP storage`() throws {
        let fixture = try makeFixture(stateFiles: ["nvram.bin"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(throws: VPhoneRemoteDiskMachineError.self) { try create(fixture) }
        #expect(try entries(fixture.folder) == ["MachineState"])
        #expect(try entries(fixture.state) == ["nvram.bin"])
    }

    @Test func `refuses a folder that is not empty but for MachineState`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data([1]).write(to: fixture.folder.appendingPathComponent("Disk.img"))
        #expect(throws: VPhoneRemoteDiskMachineError.unexpectedEntries(path: fixture.folder.path, entries: ["Disk.img"])) {
            try create(fixture)
        }
    }

    @Test func `refuses a machine that is already there`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try create(fixture)
        #expect(throws: VPhoneLibraryError.alreadyExists(name: "st-1")) { try create(fixture) }
    }

    @Test func `refuses a missing machine folder`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.folder)
        #expect(throws: VPhoneRemoteDiskMachineError.missingFolder(path: fixture.folder.path)) { try create(fixture) }
    }

    @Test func `a failure removes only what it added`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let missingROM = fixture.root.appendingPathComponent("no-such-rom.bin")
        #expect(throws: (any Error).self) {
            try VPhoneBundleOperations.createOnRemoteDisk(
                spec(fixture), in: fixture.library, romSource: fixture.rom, sepromSource: missingROM,
            )
        }
        #expect(try entries(fixture.folder) == ["MachineState"])
        #expect(try entries(fixture.state).isSuperset(of: ["nvram.bin", "SEPStorage"]))
        // So a retry starts from the same place.
        #expect(throws: Never.self) { try create(fixture) }
    }

    @Test func `the caller's own undo keeps the state`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try create(fixture)
        try VPhoneBundleOperations.removeRemoteDiskMachineFiles(named: "st-1", in: fixture.library)
        #expect(try entries(fixture.folder) == ["MachineState"])
        #expect(try entries(fixture.state) == ["nvram.bin", "SEPStorage"])
    }

    // MARK: - Launch

    @Test func `an NBD machine never starts on missing state files, booted or not`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let bundle = try create(fixture)
        #expect(bundle.manifest.machineIdentifier.isEmpty)
        // What an unmounted state volume looks like: the mount point is empty.
        for name in ["nvram.bin", "SEPStorage"] {
            try FileManager.default.removeItem(at: fixture.state.appendingPathComponent(name))
        }
        #expect(throws: VPhoneMachineStateError.missingStateFile(machine: "st-1", file: "MachineState/nvram.bin")) {
            try VPhoneMachineStateLayout.requireLaunchable(bundle)
        }
    }
}
