import Darwin
import Foundation
import Testing
@testable import VPhoneCoreKit

struct MachineStateLayoutTests {
    // MARK: - Fixtures

    private func makeBundle(identifier: Data = Data([0xEC, 0x1D]), mac: String = "02:00:00:00:00:01") throws -> (root: URL, bundle: VPhoneBundle) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let rom = root.appendingPathComponent("rom.bin")
        try Data([0xAA]).write(to: rom)
        var bundle = try VPhoneBundleOperations.create(
            .init(name: "vm", cpuCount: 2, memoryMB: 1024, diskSizeGB: 1, romSource: rom, sepromSource: rom),
            in: VPhoneLibrary(root: root),
        )
        try Data([1, 2, 3]).write(to: bundle.url.appendingPathComponent("Disk.img"))
        try Data([4, 5, 6]).write(to: bundle.url.appendingPathComponent("SEPStorage"))
        try Data([7, 8, 9]).write(to: bundle.url.appendingPathComponent("nvram.bin"))
        let manifest = bundle.manifest.updating(
            machineIdentifier: identifier,
            networkConfig: bundle.manifest.networkConfig.with(macAddress: mac),
        )
        try manifest.write(to: bundle.configURL)
        bundle = VPhoneBundle(url: bundle.url, manifest: manifest)
        return (root, bundle)
    }

    private func read(_ path: String, in bundle: VPhoneBundle) throws -> Data {
        try Data(contentsOf: bundle.url.appendingPathComponent(path))
    }

    private func exists(_ path: String, in bundle: VPhoneBundle) -> Bool {
        VPhoneVirtualMachineManifest.fileKind(at: bundle.url.appendingPathComponent(path)) != .missing
    }

    // MARK: - Manifest

    @Test func `a new machine uses the legacy layout`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(VPhoneMachineStateLayout.kind(of: bundle.manifest) == .legacy)
        #expect(throws: Never.self) { try VPhoneMachineStateLayout.requireLaunchable(bundle) }
    }

    @Test func `MachineState names load and resolve inside the subfolder`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let moved = try VPhoneMachineStateLayout.moveToStateDirectory(bundle)
        let loaded = try VPhoneVirtualMachineManifest.load(from: moved.configURL)
        #expect(loaded.nvramStorage == "MachineState/nvram.bin")
        #expect(loaded.sepStorage == "MachineState/SEPStorage")
        let url = try loaded.resolve(path: loaded.sepStorage, in: bundle.url)
        #expect(url.path == bundle.url.appendingPathComponent("MachineState/SEPStorage").path)
    }

    @Test(arguments: ["MachineState/../SEPStorage", "Other/SEPStorage", "MachineState/a/b", "MachineState/"])
    func `no other subfolder or escape is accepted`(name: String) {
        #expect(!VPhoneVirtualMachineManifest.isStateFileName(name))
        let manifest = VPhoneVirtualMachineManifest(cpuCount: 1, memorySize: 1 << 30, romImages: .default)
        #expect(throws: VPhoneManifestError.self) {
            try manifest.resolve(path: name, in: URL(fileURLWithPath: "/tmp/vm"))
        }
    }

    @Test func `a mixed layout does not load`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        try bundle.manifest.updating(nvramStorage: "MachineState/nvram.bin", sepStorage: "SEPStorage")
            .write(to: bundle.configURL)
        #expect(throws: VPhoneManifestError.self) {
            try VPhoneVirtualMachineManifest.load(from: bundle.configURL)
        }
    }

    @Test func `older builds refuse a state-directory manifest`() {
        // A build from before the layout checks every name with this.
        #expect(!VPhoneVirtualMachineManifest.isPlainFileName("MachineState/nvram.bin"))
    }

    // MARK: - Moving

    @Test func `moving in keeps every byte, records the identity and moves back`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }

        let moved = try VPhoneMachineStateLayout.moveToStateDirectory(bundle)
        #expect(VPhoneMachineStateLayout.kind(of: moved.manifest) == .stateDirectory)
        #expect(try read("MachineState/nvram.bin", in: moved) == Data([7, 8, 9]))
        #expect(try read("MachineState/SEPStorage", in: moved) == Data([4, 5, 6]))
        #expect(!exists("nvram.bin", in: moved))
        #expect(!exists("SEPStorage", in: moved))
        #expect(try read("Disk.img", in: moved) == Data([1, 2, 3]))
        let record = try #require(try VPhoneMachineIdentityRecord.load(from: VPhoneMachineStateLayout.identityURL(of: moved)))
        #expect(record.machineIdentifier == Data([0xEC, 0x1D]))
        #expect(record.macAddress == "02:00:00:00:00:01")
        #expect(try VPhoneVirtualMachineManifest.load(from: moved.configURL).machineIdentifier == Data([0xEC, 0x1D]))
        #expect(throws: Never.self) { try VPhoneMachineStateLayout.requireLaunchable(moved) }
        #expect(VPhoneBundleActivity.stateFileNames(of: moved) == ["Disk.img", "MachineState/SEPStorage", "MachineState/nvram.bin"])

        let back = try VPhoneMachineStateLayout.moveToLegacyLayout(moved)
        #expect(VPhoneMachineStateLayout.kind(of: back.manifest) == .legacy)
        #expect(try read("nvram.bin", in: back) == Data([7, 8, 9]))
        #expect(try read("SEPStorage", in: back) == Data([4, 5, 6]))
        #expect(!exists("MachineState", in: back))
        #expect(try VPhoneVirtualMachineManifest.load(from: back.configURL).nvramStorage == "nvram.bin")
    }

    @Test func `moving twice is a no-op`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let once = try VPhoneMachineStateLayout.moveToStateDirectory(bundle)
        let twice = try VPhoneMachineStateLayout.moveToStateDirectory(once)
        #expect(twice.manifest.nvramStorage == once.manifest.nvramStorage)
        #expect(try read("MachineState/nvram.bin", in: twice) == Data([7, 8, 9]))
    }

    @Test func `an interrupted move is refused at launch and finished by moving again`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        // The files moved, the manifest was not written.
        let state = VPhoneMachineStateLayout.directory(of: bundle)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false)
        #expect(rename(bundle.url.appendingPathComponent("SEPStorage").path, state.appendingPathComponent("SEPStorage").path) == 0)
        #expect(throws: VPhoneMachineStateError.interruptedMove(machine: "vm", file: "MachineState/SEPStorage")) {
            try VPhoneMachineStateLayout.requireLaunchable(bundle)
        }
        let finished = try VPhoneMachineStateLayout.moveToStateDirectory(bundle)
        #expect(throws: Never.self) { try VPhoneMachineStateLayout.requireLaunchable(finished) }
        #expect(try read("MachineState/SEPStorage", in: finished) == Data([4, 5, 6]))
        #expect(try read("MachineState/nvram.bin", in: finished) == Data([7, 8, 9]))
    }

    @Test func `a copy in both places is not overwritten`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = VPhoneMachineStateLayout.directory(of: bundle)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false)
        try Data([0xFF]).write(to: state.appendingPathComponent("nvram.bin"))
        #expect(throws: VPhoneMachineStateError.bothCopiesExist(machine: "vm", file: "nvram.bin")) {
            try VPhoneMachineStateLayout.moveToStateDirectory(bundle)
        }
        // Nothing moved, the manifest is unchanged.
        #expect(try read("nvram.bin", in: bundle) == Data([7, 8, 9]))
        #expect(try read("SEPStorage", in: bundle) == Data([4, 5, 6]))
        #expect(try VPhoneVirtualMachineManifest.load(from: bundle.configURL).nvramStorage == "nvram.bin")
    }

    @Test func `a booted machine with an empty state directory does not launch`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let moved = try VPhoneMachineStateLayout.moveToStateDirectory(bundle)
        // An unmounted shared volume: the mount point is an empty directory.
        let state = VPhoneMachineStateLayout.directory(of: moved)
        try FileManager.default.removeItem(at: state)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: false)
        #expect(throws: VPhoneMachineStateError.missingStateFile(machine: "vm", file: "MachineState/nvram.bin")) {
            try VPhoneMachineStateLayout.requireLaunchable(moved)
        }
    }

    @Test func `a machine that never booted may start with an empty state directory`() throws {
        let (root, bundle) = try makeBundle(identifier: Data(), mac: "")
        defer { try? FileManager.default.removeItem(at: root) }
        let moved = try VPhoneMachineStateLayout.moveToStateDirectory(bundle)
        // No identity yet, so no record was written.
        #expect(!exists("MachineState/identity.plist", in: moved))
        try FileManager.default.removeItem(at: moved.url.appendingPathComponent("MachineState/nvram.bin"))
        #expect(throws: Never.self) { try VPhoneMachineStateLayout.requireLaunchable(moved) }
    }

    @Test func `a symbolic link for MachineState is refused`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let moved = try VPhoneMachineStateLayout.moveToStateDirectory(bundle)
        let state = VPhoneMachineStateLayout.directory(of: moved)
        let elsewhere = root.appendingPathComponent("elsewhere")
        try FileManager.default.moveItem(at: state, to: elsewhere)
        try FileManager.default.createSymbolicLink(at: state, withDestinationURL: elsewhere)
        #expect(throws: VPhoneMachineStateError.notADirectory(path: state.path)) {
            try VPhoneMachineStateLayout.requireLaunchable(moved)
        }
    }

    // MARK: - Identity

    private func record(_ id: [UInt8], mac: String = "02:00:00:00:00:01", model: [UInt8] = [3]) -> VPhoneMachineIdentityRecord {
        VPhoneMachineIdentityRecord(machineIdentifier: Data(id), macAddress: mac, hardwareModel: Data(model), machineName: "vm")
    }

    @Test func `no record means config.plist decides`() {
        #expect(VPhoneMachineIdentityReconciliation.reconcile(
            manifestIdentifier: Data(), manifestMAC: "", hardwareModel: Data([3]), record: nil,
        ) == .useManifest)
    }

    @Test func `an empty config.plist adopts the recorded identity`() {
        #expect(VPhoneMachineIdentityReconciliation.reconcile(
            manifestIdentifier: Data(), manifestMAC: "", hardwareModel: Data([3]), record: record([1, 2]),
        ) == .adopt(machineIdentifier: Data([1, 2]), macAddress: "02:00:00:00:00:01"))
        // A MAC already in config.plist stays.
        #expect(VPhoneMachineIdentityReconciliation.reconcile(
            manifestIdentifier: Data(), manifestMAC: "02:00:00:00:00:09", hardwareModel: Data([3]), record: record([1, 2]),
        ) == .adopt(machineIdentifier: Data([1, 2]), macAddress: "02:00:00:00:00:09"))
    }

    @Test func `the same identity boots`() {
        #expect(VPhoneMachineIdentityReconciliation.reconcile(
            manifestIdentifier: Data([1, 2]), manifestMAC: "02:00:00:00:00:01", hardwareModel: Data([3]), record: record([1, 2]),
        ) == .useManifest)
        // A record vm storage wrote has no hardware model yet.
        #expect(VPhoneMachineIdentityReconciliation.reconcile(
            manifestIdentifier: Data([1, 2]), manifestMAC: "", hardwareModel: Data([3]), record: record([1, 2], model: []),
        ) == .useManifest)
    }

    @Test func `another machine's state directory is refused`() {
        guard case .mismatch = VPhoneMachineIdentityReconciliation.reconcile(
            manifestIdentifier: Data([9, 9]), manifestMAC: "", hardwareModel: Data([3]), record: record([1, 2]),
        ) else {
            Issue.record("expected a mismatch")
            return
        }
    }

    @Test func `another hardware model is refused`() {
        guard case .mismatch = VPhoneMachineIdentityReconciliation.reconcile(
            manifestIdentifier: Data([1, 2]), manifestMAC: "", hardwareModel: Data([4]), record: record([1, 2]),
        ) else {
            Issue.record("expected a mismatch")
            return
        }
    }

    @Test func `a damaged record is an error, not an absent one`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let moved = try VPhoneMachineStateLayout.moveToStateDirectory(bundle)
        let url = VPhoneMachineStateLayout.identityURL(of: moved)
        try Data("not a plist".utf8).write(to: url)
        #expect(throws: VPhoneMachineStateError.unreadableIdentity(path: url.path)) {
            try VPhoneMachineIdentityRecord.load(from: url)
        }
    }

    // MARK: - Other operations in the new layout

    @Test func `a new-identity clone drops the source's identity record`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try VPhoneMachineStateLayout.moveToStateDirectory(bundle)
        let library = VPhoneLibrary(root: root)
        let clone = try VPhoneBundleOperations.clone(bundleNamed: "vm", to: "copy", in: library, newIdentity: true)
        #expect(clone.manifest.machineIdentifier.isEmpty)
        #expect(!exists("MachineState/identity.plist", in: clone))
        #expect(try read("MachineState/SEPStorage", in: clone) == Data([4, 5, 6]))

        let backup = try VPhoneBundleOperations.clone(bundleNamed: "vm", to: "backup", in: library, newIdentity: false)
        #expect(exists("MachineState/identity.plist", in: backup))
    }

    @Test func `snapshots taken in one layout revert in the other`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try VPhoneMachineSnapshots.create("before", of: bundle)
        #expect(snapshot.files.contains("nvram.bin"))

        let moved = try VPhoneMachineStateLayout.moveToStateDirectory(bundle)
        try Data([0]).write(to: moved.url.appendingPathComponent("MachineState/nvram.bin"))
        try Data([0]).write(to: moved.url.appendingPathComponent("MachineState/SEPStorage"))
        try VPhoneMachineSnapshots.revert(to: "before", of: moved)
        #expect(try read("MachineState/nvram.bin", in: moved) == Data([7, 8, 9]))
        #expect(try read("MachineState/SEPStorage", in: moved) == Data([4, 5, 6]))
        #expect(!exists("nvram.bin", in: moved))

        let after = try VPhoneMachineSnapshots.create("after", of: moved)
        // Stored flat, as in the legacy layout.
        #expect(after.files.sorted() == ["Disk.img", "SEPStorage", "nvram.bin"])
        let folder = try VPhoneMachineSnapshots.folder(named: "after", of: moved)
        #expect(try Data(contentsOf: folder.appendingPathComponent("SEPStorage")) == Data([4, 5, 6]))
    }

    @Test func `snapshots, clones and exports refuse an NBD machine`() throws {
        let (root, bundle) = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let nbd = bundle.manifest.updating(diskImage: "nbd://10.0.0.5:10809/vm")
        try nbd.write(to: bundle.configURL)
        let library = VPhoneLibrary(root: root)
        let machine = try library.bundle(named: "vm")
        #expect(throws: VPhoneBundleDiskError.self) {
            try VPhoneMachineSnapshots.create("s", of: machine)
        }
        #expect(throws: VPhoneBundleDiskError.self) {
            try VPhoneBundleOperations.clone(bundleNamed: "vm", to: "copy", in: library)
        }
        #expect(!FileManager.default.fileExists(atPath: library.url(forName: "copy").path))
    }
}
