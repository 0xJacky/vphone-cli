import Foundation
import Testing
@testable import VPhoneCoreKit

struct SavedMachineStateTests {
    private let configuration = VPhoneSavedStateConfiguration(
        cpuCount: 4,
        memorySize: 4 << 30,
        disk: "Disk.img",
        macAddress: "02:00:00:00:00:01",
        networkMode: "nat",
        screen: "1290x2796@460",
        hardwareKeyboard: true,
        guestProductType: "iPhone17,3",
    )

    private let disk = VPhoneDiskFingerprint(device: 1, inode: 2, size: 3, modifiedSeconds: 4, modifiedNanoseconds: 5)

    private func binding(disk: VPhoneDiskFingerprint?, after: String = "stop") -> VPhoneSavedStateBinding {
        VPhoneSavedStateBinding(
            hardwareModel: Data([3]),
            machineIdentifier: Data([1, 2]),
            configuration: configuration,
            hostUUID: "HOST-A",
            hostName: "mac-a",
            hostOSBuild: "27A100",
            vphoneVersion: "2.10.1",
            disk: disk,
            stateFileSize: 4096,
            saved: Date(timeIntervalSince1970: 1_000),
            after: after,
        )
    }

    private func current(
        machineIdentifier: Data = Data([1, 2]),
        hardwareModel: Data = Data([3]),
        configuration: VPhoneSavedStateConfiguration? = nil,
        host: String = "HOST-A",
        build: String = "27A100",
        disk: VPhoneDiskFingerprint?,
    ) -> VPhoneSavedStateBinding.Current {
        .init(
            hardwareModel: hardwareModel,
            machineIdentifier: machineIdentifier,
            configuration: configuration ?? self.configuration,
            hostUUID: host,
            hostOSBuild: build,
            disk: disk,
        )
    }

    // MARK: - Verification

    @Test func `the same machine, Mac and disk restore`() {
        let result = binding(disk: disk).verify(against: current(disk: disk))
        #expect(result.isRestorable)
        #expect(result.warnings.isEmpty)
    }

    @Test func `another machine identifier is refused`() {
        let result = binding(disk: disk).verify(against: current(machineIdentifier: Data([9]), disk: disk))
        #expect(!result.isRestorable)
        #expect(result.refusals.contains { $0.contains("another machine") })
    }

    @Test func `another hardware model is refused`() {
        let result = binding(disk: disk).verify(against: current(hardwareModel: Data([4]), disk: disk))
        #expect(result.refusals.contains { $0.contains("hardware model") })
    }

    @Test func `each changed setting is named`() {
        let changed = VPhoneSavedStateConfiguration(
            cpuCount: 8,
            memorySize: 4 << 30,
            disk: "nbd://h:10809/e",
            macAddress: "02:00:00:00:00:01",
            networkMode: "nat",
            screen: "1290x2796@460",
            hardwareKeyboard: true,
            guestProductType: "iPhone17,3",
        )
        let result = binding(disk: disk).verify(against: current(configuration: changed, disk: disk))
        #expect(result.refusals.count == 2)
        #expect(result.refusals.contains { $0.contains("CPU count") && $0.contains("4 -> 8") })
        #expect(result.refusals.contains { $0.contains("the disk changed") })
    }

    @Test func `another Mac is refused unless the PoC flag asks to try`() {
        let refused = binding(disk: disk).verify(against: current(host: "HOST-B", disk: disk))
        #expect(refused.refusals.contains { $0.contains("another Mac") })
        let tried = binding(disk: disk).verify(against: current(host: "HOST-B", disk: disk), allowOtherHost: true)
        #expect(tried.isRestorable)
        #expect(tried.warnings.contains { $0.contains("another Mac") })
    }

    @Test func `a macOS update only warns`() {
        let result = binding(disk: disk).verify(against: current(build: "27B5", disk: disk))
        #expect(result.isRestorable)
        #expect(result.warnings.contains { $0.contains("27A100 -> 27B5") })
    }

    @Test func `a disk written since the save is refused`() {
        let written = VPhoneDiskFingerprint(device: 1, inode: 2, size: 3, modifiedSeconds: 4, modifiedNanoseconds: 6)
        let result = binding(disk: disk).verify(against: current(disk: written))
        #expect(result.refusals.contains { $0.contains("disk image changed") })
        let gone = binding(disk: disk).verify(against: current(disk: nil))
        #expect(gone.refusals.contains { $0.contains("gone") })
    }

    @Test func `an NBD disk cannot be checked, which is a warning`() {
        let result = binding(disk: nil).verify(against: current(disk: nil))
        #expect(result.isRestorable)
        #expect(result.warnings.contains { $0.contains("not a local file") })
        let resumed = binding(disk: nil, after: "resume").verify(against: current(disk: nil))
        #expect(resumed.warnings.contains { $0.contains("kept running") })
    }

    @Test func `a used state is refused`() {
        var used = binding(disk: disk)
        used.invalidated = .init(reason: "restored", at: Date())
        #expect(used.verify(against: current(disk: disk)).refusals.contains { $0.contains("restored") })
    }

    // MARK: - Files

    @Test func `the binding round trips and invalidation sticks`() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(!VPhoneSavedMachineState.hasUsableState(in: dir))
        try binding(disk: disk).write(to: VPhoneSavedMachineState.bindingFile(in: dir))
        #expect(!VPhoneSavedMachineState.hasUsableState(in: dir), "no state file yet")
        try Data([0]).write(to: VPhoneSavedMachineState.stateFile(in: dir))
        #expect(VPhoneSavedMachineState.hasUsableState(in: dir))
        #expect(try VPhoneSavedStateBinding.load(from: VPhoneSavedMachineState.bindingFile(in: dir)) == binding(disk: disk))

        try VPhoneSavedMachineState.invalidate(in: dir, reason: "the machine booted cold", now: Date(timeIntervalSince1970: 2_000))
        #expect(!VPhoneSavedMachineState.hasUsableState(in: dir))
        let reloaded = try #require(try VPhoneSavedStateBinding.load(from: VPhoneSavedMachineState.bindingFile(in: dir)))
        #expect(reloaded.invalidated?.reason == "the machine booted cold")
        // A second invalidation keeps the first reason.
        try VPhoneSavedMachineState.invalidate(in: dir, reason: "again")
        #expect(try VPhoneSavedStateBinding.load(from: VPhoneSavedMachineState.bindingFile(in: dir))?.invalidated?.reason == "the machine booted cold")
    }

    @Test func `invalidating where there is no state does nothing`() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: Never.self) {
            try VPhoneSavedMachineState.invalidate(in: dir, reason: "x")
        }
    }

    @Test func `a write changes the disk fingerprint`() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Disk.img")
        try Data([1, 2, 3]).write(to: file)
        let before = try #require(VPhoneDiskFingerprint(of: file))
        #expect(VPhoneDiskFingerprint(of: file) == before)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seek(toOffset: 1)
        try handle.write(contentsOf: Data([9]))
        try handle.close()
        #expect(VPhoneDiskFingerprint(of: file) != before)
        #expect(VPhoneDiskFingerprint(of: dir) == nil, "not a regular file")
    }

    // MARK: - Diagnosis

    @Test func `each blocker is found even though Virtualization names only the first`() {
        // What Virtualization did on macOS 27 for the vphone device set
        // (PoC probe on a PV=2 model): it reports the first unsupported part.
        let unsupported = ["multi-touch": "Unsupported multi-touch device in configuration.",
                           "SEP coprocessor": "Unsupported coprocessor in configuration."]
        let order = ["multi-touch", "SEP coprocessor"]
        let report = VPhoneSaveRestoreDiagnosis.diagnose(
            candidates: ["accelerators", "multi-touch", "battery", "SEP coprocessor", "GDB stub"],
        ) { kept in
            order.first { kept.contains($0) }.flatMap { unsupported[$0] }
        }
        #expect(report.blockers.map(\.name) == ["multi-touch", "SEP coprocessor"])
        #expect(report.remainder == nil)
        #expect(report.summary.contains("SEP coprocessor (Unsupported coprocessor in configuration.)"))
    }

    @Test func `a failure outside the candidates is reported as such`() {
        let report = VPhoneSaveRestoreDiagnosis.diagnose(candidates: ["a", "b"]) { _ in "platform not supported" }
        #expect(report.blockers.isEmpty)
        #expect(report.remainder == "platform not supported")
    }
}

struct HostIdentityTests {
    @Test func `this Mac has a stable hardware UUID and a build`() {
        let uuid = VPhoneHostIdentity.platformUUID()
        #expect(UUID(uuidString: uuid) != nil)
        #expect(VPhoneHostIdentity.platformUUID() == uuid)
        #expect(!VPhoneHostIdentity.osBuild().isEmpty)
    }
}
