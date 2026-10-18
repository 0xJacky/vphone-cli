import Foundation
import Testing
@testable import VPhoneCoreKit

struct DiskLocationTests {
    private func manifest(disk: String = "Disk.img", nbd: VPhoneVirtualMachineManifest.NBDOptions? = nil) -> VPhoneVirtualMachineManifest {
        VPhoneVirtualMachineManifest(
            cpuCount: 4,
            memorySize: 4 << 30,
            diskImage: disk,
            romImages: .default,
            nbd: nbd,
        )
    }

    private func roundTrip(_ manifest: VPhoneVirtualMachineManifest) throws -> VPhoneVirtualMachineManifest {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.plist")
        try manifest.write(to: url)
        return try VPhoneVirtualMachineManifest.load(from: url)
    }

    // MARK: - Parsing

    @Test func `a plain name is a file disk`() throws {
        #expect(try VPhoneDiskLocation(manifestValue: "Disk.img") == .file(name: "Disk.img"))
    }

    @Test func `an nbd URL keeps host, port and export`() throws {
        let location = try VPhoneNBDLocation(parsing: "nbd://10.0.0.5:10810/wecom-01")
        #expect(location.host == "10.0.0.5")
        #expect(location.port == 10810)
        #expect(location.exportName == "wecom-01")
        #expect(location.urlString == "nbd://10.0.0.5:10810/wecom-01")
    }

    @Test func `the port defaults to 10809 and is written out`() throws {
        let location = try VPhoneNBDLocation(parsing: "nbd://storage.local/vol")
        #expect(location.port == 10809)
        #expect(location.urlString == "nbd://storage.local:10809/vol")
    }

    @Test func `an IPv6 host parses`() throws {
        let location = try VPhoneNBDLocation(parsing: "nbd://[fd00::5]:10809/vol")
        #expect(location.port == 10809)
        #expect(location.exportName == "vol")
        let again = try VPhoneNBDLocation(parsing: location.urlString)
        #expect(again == location)
    }

    @Test(arguments: ["nbds://h:10809/e", "NBDS://h/e", "nbds+unix:///e?socket=/tmp/s"])
    func `TLS URLs are refused with the TLS reason`(value: String) {
        #expect(throws: VPhoneDiskLocationError.tlsUnsupported(value)) {
            try VPhoneNBDLocation(parsing: value)
        }
    }

    @Test(arguments: ["nbd+unix:///e?socket=/tmp/s", "http://h/e", "file:///tmp/Disk.img"])
    func `other schemes are refused`(value: String) {
        #expect(throws: VPhoneDiskLocationError.self) {
            try VPhoneNBDLocation(parsing: value)
        }
    }

    @Test func `an export name is required`() {
        #expect(throws: VPhoneDiskLocationError.missingExportName) {
            try VPhoneNBDLocation(parsing: "nbd://h:10809/")
        }
        #expect(throws: VPhoneDiskLocationError.missingExportName) {
            try VPhoneNBDLocation(parsing: "nbd://h:10809")
        }
    }

    @Test(arguments: ["nbd://u:p@h/e", "nbd://h/e?tls-certificates=/x", "nbd://h/e#f"])
    func `credentials, queries and fragments are refused`(value: String) {
        #expect(throws: VPhoneDiskLocationError.self) {
            try VPhoneNBDLocation(parsing: value)
        }
    }

    @Test(arguments: ["../Disk.img", "sub/Disk.img", ""])
    func `a path that is neither a name nor a URL is refused`(value: String) {
        #expect(throws: VPhoneDiskLocationError.self) {
            try VPhoneDiskLocation(manifestValue: value)
        }
    }

    // MARK: - Manifest

    @Test func `a manifest with an nbd disk and options round trips`() throws {
        let loaded = try roundTrip(manifest(
            disk: "nbd://10.0.0.5:10809/wecom-01",
            nbd: .init(timeoutSeconds: 15, synchronization: .full),
        ))
        #expect(loaded.diskLocation.isNetwork)
        #expect(loaded.nbd?.effectiveTimeout == 15)
        #expect(loaded.nbd?.effectiveSynchronization == .full)
    }

    @Test func `older builds refuse an nbd manifest because its disk is not a plain name`() {
        // What a build from before NBD checks for every manifest file name.
        #expect(!VPhoneVirtualMachineManifest.isPlainFileName("nbd://10.0.0.5:10809/wecom-01"))
    }

    @Test func `a TLS disk URL makes the manifest unloadable`() {
        #expect(throws: VPhoneManifestError.self) {
            try roundTrip(manifest(disk: "nbds://10.0.0.5/wecom-01"))
        }
    }

    @Test(arguments: [0.5, 601.0])
    func `an NBD timeout outside the range makes the manifest unloadable`(timeout: Double) {
        #expect(throws: VPhoneManifestError.self) {
            try roundTrip(manifest(disk: "nbd://h/e", nbd: .init(timeoutSeconds: timeout)))
        }
    }

    @Test func `defaults are Virtualization's`() {
        let options = VPhoneVirtualMachineManifest.NBDOptions()
        #expect(options.effectiveTimeout == 5)
        #expect(options.effectiveSynchronization == .full)
    }

    @Test func `NBD options survive every other edit`() {
        let original = manifest(disk: "nbd://h/e", nbd: .init(timeoutSeconds: 30))
        #expect(original.updating(cpuCount: 2).nbd == original.nbd)
        #expect(original.updating(romImages: .default).nbd == original.nbd)
        #expect(original.updating(guestDevice: .default).nbd == original.nbd)
        #expect(original.updating(nvramStorage: "nvram.bin", sepStorage: "SEPStorage").nbd == original.nbd)
        #expect(original.updating(diskImage: "Disk.img", nbd: .some(nil)).nbd == nil)
        #expect(original.updating(diskImage: "Disk.img", nbd: .some(nil)).diskLocation == .file(name: "Disk.img"))
    }

    @Test func `a file disk manifest writes no nbd key`() throws {
        let data = try PropertyListEncoder().encode(manifest())
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["nbd"] == nil)
    }

    @Test func `resolve refuses an nbd disk`() {
        let m = manifest(disk: "nbd://h/e")
        #expect(throws: VPhoneManifestError.self) {
            try m.resolve(path: m.diskImage, in: URL(fileURLWithPath: "/tmp/vm"))
        }
    }

    // MARK: - Bundle

    @Test func `an nbd machine reports no disk size and its URL`() throws {
        let bundle = VPhoneBundle(url: URL(fileURLWithPath: "/nonexistent/vm"), manifest: manifest(disk: "nbd://h:10809/e"))
        #expect(bundle.diskSizeBytes == 0)
        #expect(VPhoneBundleActivity.stateFileNames(of: bundle) == ["SEPStorage", "nvram.bin"])
        #expect(throws: VPhoneBundleDiskError.self) {
            try bundle.requireLocalDisk(for: "clone")
        }
        let report = VPhoneBundleReport(bundle: bundle)
        #expect(report.networkDisk == "nbd://h:10809/e")
        #expect(report.stateLayout == "legacy")
        #expect(report.hasSavedState == false)
    }

    @Test func `a file machine keeps its disk among the state files`() {
        let bundle = VPhoneBundle(url: URL(fileURLWithPath: "/nonexistent/vm"), manifest: manifest())
        #expect(VPhoneBundleActivity.stateFileNames(of: bundle) == ["Disk.img", "SEPStorage", "nvram.bin"])
        #expect(throws: Never.self) {
            try bundle.requireLocalDisk(for: "clone")
        }
        #expect(VPhoneBundleReport(bundle: bundle).networkDisk == nil)
    }
}
