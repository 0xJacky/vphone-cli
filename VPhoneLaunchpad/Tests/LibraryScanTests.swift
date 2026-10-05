import Foundation

/// The Library pages' formatting, IPSW reading, folder measuring and row
/// building, against fixtures made in a temporary folder.
@main
struct LibraryScanTests {
    static func expect(_ condition: Bool, _ message: @autoclosure () -> String, line: Int = #line) {
        precondition(condition, "line \(line): \(message())")
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-scan-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // The shared IPSW cache is looked up under VPHONE_ROOT; keep it in the fixture.
        setenv("VPHONE_ROOT", root.appendingPathComponent("data").path, 1)

        formats()
        fileNames()
        try zips(in: root)
        try await machines(in: root)
        try await removal(in: root)
        rows()
        sharedNAT(in: root)
        print("LibraryScanTests passed")
    }

    // MARK: - Formatting

    static func formats() {
        typealias Format = VPhoneLaunchpadLibraryFormat
        expect(Format.size(9_400_000_000) == "9.4 GB", Format.size(9_400_000_000))
        expect(Format.size(166_200_000_000) == "166 GB", Format.size(166_200_000_000))
        expect(Format.size(99_960_000_000) == "100 GB", Format.size(99_960_000_000))
        expect(Format.size(524_288) == "524 KB", Format.size(524_288))
        expect(Format.size(0) == "0 bytes", Format.size(0))
        expect(Format.size(31_000_000_000) == "31 GB", Format.size(31_000_000_000))
        expect(Format.compactSize(31_200_000_000) == "31 GB", Format.compactSize(31_200_000_000))
        expect(Format.compactSize(2_400_000_000) == "2.4 GB", Format.compactSize(2_400_000_000))
        expect(Format.diskSize(64_000_000_000) == "64 GB", Format.diskSize(64_000_000_000))
        expect(Format.portForward(transport: "tcp", hostAddress: nil, hostPort: 2222, guestPort: 22) == "2222 → 22", "tcp forward")
        expect(Format.portForward(transport: "udp", hostAddress: "127.0.0.1", hostPort: 5353, guestPort: 53) == "5353 → 53/udp", "udp forward")
        expect(Format.portForward(transport: "tcp", hostAddress: "0.0.0.0", hostPort: 8080, guestPort: 80) == "0.0.0.0:8080 → 80", "bound forward")
        expect(Format.normalizedMAC("2:8b:e3:17:a4:a0") == "02:8b:e3:17:a4:a0", "bootpd MAC")
        expect(Format.normalizedMAC("5E:3A:91:0C:7D:21") == "5e:3a:91:0c:7d:21", "upper-case MAC")
        expect(Format.normalizedMAC("not a mac") == nil, "bad MAC")
    }

    // MARK: - IPSW names

    static func fileNames() {
        let cached = VPhoneLaunchpadIPSW(fileName: "iPhone17_3_27.0_24A435_Restore-3c6d6dc0803d.ipsw")
        expect(cached?.productTypes == ["iPhone17,3"], "\(String(describing: cached?.productTypes))")
        expect(cached?.version == "27.0" && cached?.build == "24A435", "cached version and build")
        expect(cached?.kind == .iPhone && cached?.title == "iOS 27.0 (24A435)", "cached kind and title")
        expect(cached?.fromManifest == false && cached?.hasGuestBoard == nil, "name facts are guesses")

        let pad = VPhoneLaunchpadIPSW(fileName: "iPad16,1,iPad16,2_26.6.2_23G90_Restore.ipsw")
        expect(pad?.productTypes == ["iPad16,1", "iPad16,2"], "\(String(describing: pad?.productTypes))")
        expect(pad?.kind == .iPad && pad?.title == "iPadOS 26.6.2 (23G90)", "iPad title")

        let cachedPad = VPhoneLaunchpadIPSW(fileName: "iPad16_1_iPad16_2_26.6.2_23G90_Restore-0123456789ab.ipsw")
        expect(cachedPad?.productTypes == ["iPad16,1", "iPad16,2"], "\(String(describing: cachedPad?.productTypes))")

        expect(VPhoneLaunchpadIPSW(fileName: "c0ecdb4b310cf5239ab2b248dd3098eec297dc5aa3bbe6ad-b80d96a0b616.ipsw") == nil, "hash name")
        expect(VPhoneLaunchpadIPSW(fileName: "notes.txt") == nil, "not an IPSW")
        expect(VPhoneLaunchpadIPSW.productTypes(in: "iPhoneOS_iPad16,1") == ["iPad16,1"], "tree name products")

        let beta = VPhoneLaunchpadIPSW(version: "26.4", build: "23E5207q", productTypes: [], deviceClasses: ["vresearch101ap"], fromManifest: true)
        expect(beta.isBeta && beta.kind == .cloudOS && beta.hasGuestBoard == false, "cloudOS without the guest board")

        // The names `fw prepare` gave two real downloads.
        let rc = URL(string: "https://updates.cdn-apple.com/2026FallFCS/2d0cd01d-b4f9-4a20-a1e8-f3be54570da7/iPhone17,3_27.0_24A435_Restore.ipsw")!
        expect(VPhoneLaunchpadIPSW.cacheName(for: rc) == "iPhone17_3_27.0_24A435_Restore-3c6d6dc0803d.ipsw", VPhoneLaunchpadIPSW.cacheName(for: rc))
        let point = URL(string: "https://updates.cdn-apple.com/2026FallFCS/38dca0ee-bb5d-4132-ad13-62d57bcd6d32/iPhone17,3_27.0.1_24A446_Restore.ipsw")!
        expect(VPhoneLaunchpadIPSW.cacheName(for: point) == "iPhone17_3_27.0.1_24A446_Restore-1c2c1e8da8de.ipsw", VPhoneLaunchpadIPSW.cacheName(for: point))

        let uuid = UUID().uuidString
        expect(VPhoneLaunchpadIPSW.finalName(ofPartial: ".a-0123456789ab.ipsw.\(uuid).partial") == "a-0123456789ab.ipsw", "partial name")
        expect(VPhoneLaunchpadIPSW.finalName(ofPartial: ".a.ipsw.partial") == nil, "partial without UUID")
        expect(VPhoneLaunchpadIPSW.finalName(ofPartial: "a.ipsw") == nil, "not partial")
    }

    // MARK: - Zip

    static var cloudManifest: [String: Any] { [
        "ProductVersion": "26.4",
        "ProductBuildVersion": "23E5207q",
        "SupportedProductTypes": ["ComputeModule14,1"],
        "BuildIdentities": [
            ["Info": ["DeviceClass": "VRESEARCH101AP"]],
            ["Info": ["DeviceClass": "vphone600ap"]],
        ],
    ] }

    static func manifestData(_ plist: [String: Any]) throws -> Data {
        // Padding that deflates well, so the member is really compressed.
        var plist = plist
        plist["Padding"] = String(repeating: "BuildIdentity ", count: 4000)
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    static func zip(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        expect(process.terminationStatus == 0, "zip \(arguments)")
    }

    static func zips(in root: URL) throws {
        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try manifestData(cloudManifest).write(to: source.appendingPathComponent("BuildManifest.plist"))
        try Data(repeating: 7, count: 100_000).write(to: source.appendingPathComponent("Firmware.bin"))

        for (name, level) in [("deflated.ipsw", "-6"), ("stored.ipsw", "-0")] {
            try zip(["-q", level, "../\(name)", "Firmware.bin", "BuildManifest.plist"], in: source)
            let facts = try VPhoneLaunchpadIPSW.read(root.appendingPathComponent(name))
            expect(facts.version == "26.4" && facts.build == "23E5207q", "\(name) version")
            expect(facts.kind == .cloudOS && facts.hasGuestBoard == true, "\(name) is a cloudOS with vphone600ap")
            expect(facts.title == "cloudOS 26.4 (23E5207q)", "\(name) title")
        }

        let zip64 = root.appendingPathComponent("zip64.ipsw")
        let iPhone: [String: Any] = [
            "ProductVersion": "26.6.2", "ProductBuildVersion": "23G90",
            "SupportedProductTypes": ["iPhone17,3"],
            "BuildIdentities": [["Info": ["DeviceClass": "d47ap"]]],
        ]
        try zip64Archive(member: "BuildManifest.plist", contents: manifestData(iPhone)).write(to: zip64)
        let facts = try VPhoneLaunchpadIPSW.read(zip64)
        expect(facts.kind == .iPhone && facts.productTypes == ["iPhone17,3"] && facts.build == "23G90", "ZIP64 manifest")

        let notZip = root.appendingPathComponent("broken.ipsw")
        try Data(repeating: 0, count: 4096).write(to: notZip)
        expect((try? VPhoneLaunchpadIPSW.read(notZip)) == nil, "not a zip")
    }

    /// A one-member stored archive whose entry and end record go through
    /// ZIP64, as an IPSW over 4 GB has them.
    static func zip64Archive(member: String, contents: Data) -> Data {
        var data = Data()
        func le16(_ value: Int) { withUnsafeBytes(of: UInt16(value).littleEndian) { data.append(contentsOf: $0) } }
        func le32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func le64(_ value: Int) { withUnsafeBytes(of: UInt64(value).littleEndian) { data.append(contentsOf: $0) } }
        let name = Data(member.utf8)

        le32(0x0403_4B50); le16(45); le16(0); le16(0); le16(0); le16(0); le32(0)
        le32(UInt32(contents.count)); le32(UInt32(contents.count)); le16(name.count); le16(0)
        data.append(name)
        data.append(contents)

        let directory = data.count
        le32(0x0201_4B50); le16(45); le16(45); le16(0); le16(0); le16(0); le16(0); le32(0)
        le32(.max); le32(.max); le16(name.count); le16(4 + 24); le16(0); le16(0); le16(0); le32(0); le32(.max)
        data.append(name)
        le16(1); le16(24); le64(contents.count); le64(contents.count); le64(0)
        let directorySize = data.count - directory

        let record = data.count
        le32(0x0606_4B50); le64(44); le16(45); le16(45); le32(0); le32(0)
        le64(1); le64(1); le64(directorySize); le64(directory)
        le32(0x0706_4B50); le32(0); le64(record); le32(1)
        le32(0x0605_4B50); le16(0); le16(0); le16(0xFFFF); le16(0xFFFF); le32(.max); le32(.max); le16(0)
        return data
    }

    // MARK: - Machines and the cache

    static func machines(in root: URL) async throws {
        let library = root.appendingPathComponent("machines", isDirectory: true)
        let machine = library.appendingPathComponent("ipad-lab", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: machine, withIntermediateDirectories: true)
        let config: NSDictionary = ["diskImage": "Disk.img", "guestProductType": "iPad16,1"]
        expect(config.write(to: machine.appendingPathComponent("config.plist"), atomically: true), "config.plist")

        // A sparse disk image: 64 MB long, 1 MB written.
        let disk = machine.appendingPathComponent("Disk.img")
        manager.createFile(atPath: disk.path, contents: nil)
        let handle = try FileHandle(forWritingTo: disk)
        try handle.write(contentsOf: Data(repeating: 1, count: 1 << 20))
        try handle.truncate(atOffset: 64 << 20)
        try handle.close()

        let tree = machine.appendingPathComponent("iPhoneOS_iPad16,1_26.6.2_23G90_Restore", isDirectory: true)
        try manager.createDirectory(at: tree.appendingPathComponent("Firmware", isDirectory: true), withIntermediateDirectories: true)
        try Data(repeating: 2, count: 300_000).write(to: tree.appendingPathComponent("Firmware/kernelcache"))
        let originals = machine.appendingPathComponent("FirmwareOriginals/iPhoneOS_iPad16,1_26.6.2_23G90_Restore", isDirectory: true)
        try manager.createDirectory(at: originals, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 50_000).write(to: originals.appendingPathComponent("iBoot"))
        // A link with a restore tree's name is neither measured nor followed.
        let elsewhere = root.appendingPathComponent("elsewhere", isDirectory: true)
        try manager.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Data(repeating: 4, count: 500_000).write(to: elsewhere.appendingPathComponent("big"))
        try manager.createSymbolicLink(at: machine.appendingPathComponent("iPhone99,1_1.0_1A1_Restore"), withDestinationURL: elsewhere)

        let cache = root.appendingPathComponent("ipsws", isDirectory: true)
        try manager.createDirectory(at: cache, withIntermediateDirectories: true)
        try manager.copyItem(at: root.appendingPathComponent("deflated.ipsw"), to: cache.appendingPathComponent("c0ecdb4b310cf5239ab2b248dd3098eec297dc5aa3bbe6ad-b80d96a0b616.ipsw"))
        try Data(repeating: 5, count: 1000).write(to: cache.appendingPathComponent(".iPhone17_3_27.0_24A435_Restore-3c6d6dc0803d.ipsw.\(UUID().uuidString).partial"))
        try Data(repeating: 6, count: 10).write(to: cache.appendingPathComponent("readme.txt"))

        let measured = try VPhoneLaunchpadLibraryScanner.measure(.init(libraryRoot: library.path, name: "ipad-lab"))
        expect(measured != nil, "machine measured")
        guard let measured else {
            return
        }
        expect(measured.productType == "iPad16,1", "product type")
        expect(VPhoneLaunchpadLibraryScanner.originalsProductType(machine) == "iPad16,1", "product type from FirmwareOriginals")
        expect(measured.restoreTrees == ["iPhoneOS_iPad16,1_26.6.2_23G90_Restore"], "\(measured.restoreTrees)")
        expect(measured.diskImageSize == 64 << 20, "disk size \(String(describing: measured.diskImageSize))")
        let written = measured.diskImageAllocated ?? 0
        expect(written >= 1 << 20 && written < 64 << 20, "sparse disk allocation \(written)")
        expect(measured.restoreAllocated >= 300_000 && measured.restoreAllocated < 500_000, "restore allocation \(measured.restoreAllocated)")
        expect(measured.otherAllocated >= 50_000 && measured.otherAllocated < 500_000, "other allocation \(measured.otherAllocated)")
        expect(measured.totalAllocated == written + measured.restoreAllocated + measured.otherAllocated, "total")
        expect(try VPhoneLaunchpadLibraryScanner.measure(.init(libraryRoot: library.path, name: "missing")) == nil, "missing machine")

        let files = try VPhoneLaunchpadLibraryScanner.ipsws(in: cache)
        expect(files.count == 2, "\(files.map(\.name))")
        let cloud = files.first { !$0.isDownloading }
        expect(cloud?.facts?.kind == .cloudOS && cloud?.facts?.fromManifest == true, "cached cloudOS read from its manifest")
        let partial = files.first(where: \.isDownloading)
        expect(partial?.name == "iPhone17_3_27.0_24A435_Restore-3c6d6dc0803d.ipsw" && partial?.facts?.kind == .iPhone, "download in progress")

        let scan = try await VPhoneLaunchpadLibraryScanner.scan(libraryRoots: [library.path], machines: [.init(libraryRoot: library.path, name: "ipad-lab")])
        expect(scan.machines.count == 1, "scan machines")
        expect(!scan.volumes.isEmpty && scan.volumes[0].available != nil, "volume")

        // A cancelled scan stops instead of measuring.
        let cancelled = Task {
            try await VPhoneLaunchpadLibraryScanner.scan(libraryRoots: [library.path], machines: [.init(libraryRoot: library.path, name: "ipad-lab")])
        }
        cancelled.cancel()
        expect((try? await cancelled.value) == nil, "cancelled scan")
    }

    static func removal(in root: URL) async throws {
        let machine = root.appendingPathComponent("machines/ipad-lab", isDirectory: true)
        let tree = "iPhoneOS_iPad16,1_26.6.2_23G90_Restore"
        do {
            try await VPhoneLaunchpadLibraryScanner.removeRestoreTrees(["FirmwareOriginals"], in: machine)
            expect(false, "FirmwareOriginals refused")
        } catch is VPhoneLaunchpadLibraryScanner.RemovalError {}
        do {
            try await VPhoneLaunchpadLibraryScanner.removeRestoreTrees(["../ipsws_Restore"], in: machine)
            expect(false, "a path refused")
        } catch is VPhoneLaunchpadLibraryScanner.RemovalError {}
        try await VPhoneLaunchpadLibraryScanner.removeRestoreTrees([tree, "iPhone99,1_1.0_1A1_Restore"], in: machine)
        let manager = FileManager.default
        expect(!manager.fileExists(atPath: machine.appendingPathComponent(tree).path), "tree removed")
        expect(manager.fileExists(atPath: machine.appendingPathComponent("FirmwareOriginals").path), "originals kept")
        expect(manager.fileExists(atPath: root.appendingPathComponent("elsewhere/big").path), "link target kept")
        expect((try? manager.destinationOfSymbolicLink(atPath: machine.appendingPathComponent("iPhone99,1_1.0_1A1_Restore").path)) != nil, "link kept")
    }

    // MARK: - Rows

    static func file(_ name: String, _ facts: VPhoneLaunchpadIPSW?, downloading: Bool = false) -> VPhoneLaunchpadLibraryScan.IPSWFile {
        VPhoneLaunchpadLibraryScan.IPSWFile(
            url: URL(fileURLWithPath: "/cache/\(name)"),
            name: name,
            size: 10_000_000_000,
            allocatedSize: 10_000_000_000,
            facts: facts,
            isDownloading: downloading,
        )
    }

    static func rows() {
        let padFile = file("iPad16,1,iPad16,2_26.6.2_23G90_Restore.ipsw", VPhoneLaunchpadIPSW(version: "26.6.2", build: "23G90", productTypes: ["iPad16,1", "iPad16,2"], deviceClasses: ["j717ap"], fromManifest: true))
        let phoneFile = file("iPhone17_3_27.0_24A435_Restore-3c6d6dc0803d.ipsw", VPhoneLaunchpadIPSW(fileName: "iPhone17_3_27.0_24A435_Restore-3c6d6dc0803d.ipsw"))
        let cloudFile = file("c0ecdb4b-b80d96a0b616.ipsw", VPhoneLaunchpadIPSW(version: "26.4", build: "23E5207q", productTypes: [], deviceClasses: ["vresearch101ap", "vphone600ap"], fromManifest: true))
        let unknownFile = file("mystery.ipsw", nil)

        let release = VPhoneLaunchpadFirmwareUse.Release(version: "26.6.2", build: "23G90")
        let cloud = VPhoneLaunchpadFirmwareUse.Release(version: "26.4", build: "23E5207q")
        let pad = VPhoneLaunchpadFirmwareUse(machine: "ipad-mini-01", productType: "iPad16,1", ios: release, cloudOS: cloud)
        let otherPad = VPhoneLaunchpadFirmwareUse(machine: "ipad-pro-13", productType: "iPad17,3", ios: release, cloudOS: cloud)
        let creating = VPhoneLaunchpadFirmwareUse(
            machine: "phone",
            sources: ["https://updates.cdn-apple.com/2026FallFCS/2d0cd01d-b4f9-4a20-a1e8-f3be54570da7/iPhone17,3_27.0_24A435_Restore.ipsw"],
            isCreating: true,
        )
        expect(pad.uses(padFile) && !otherPad.uses(padFile), "iPad match by product type")
        expect(pad.uses(cloudFile) && otherPad.uses(cloudFile), "cloudOS match by build")
        expect(creating.uses(phoneFile) && !creating.uses(padFile), "creation source match")
        expect(!pad.uses(unknownFile), "unknown file")
        expect(VPhoneLaunchpadFirmwareUse.source("/cache/mystery.ipsw", is: unknownFile), "local source match")

        let catalog = VPhoneLaunchpadFirmwareCatalogIndex(entries: [
            .init(name: "iOS 27.0 RC", url: "https://updates.cdn-apple.com/2026FallFCS/2d0cd01d-b4f9-4a20-a1e8-f3be54570da7/iPhone17,3_27.0_24A435_Restore.ipsw", isCloudOS: false),
            .init(name: "cloudOS 26.4", url: "https://updates.cdn-apple.com/x/c0ecdb4b", isCloudOS: true),
        ])
        let rows = VPhoneLaunchpadFirmwareRows.rows([unknownFile, cloudFile, padFile, phoneFile], catalog: catalog, uses: [pad, otherPad, creating])
        expect(rows.map(\.kind) == [.iPhone, .iPad, .cloudOS, .unknown], "\(rows.map(\.kind))")
        expect(rows[0].title == "iOS 27.0 RC (24A435)" && rows[0].usedBy == ["phone (creating)"], "\(rows[0])")
        expect(rows[0].status?.text == "In Catalog", "catalog status")
        expect(rows[1].title == "iPadOS 26.6.2 (23G90)" && rows[1].usedBy == ["ipad-mini-01"], "\(rows[1])")
        expect(rows[1].status?.text == "Not in Catalog", "iPad not in this catalog")
        expect(rows[2].kindLabel == "cloudOS · beta" && rows[2].status?.text == "Has vphone600ap", "\(rows[2])")
        expect(rows[2].usedBy == ["ipad-mini-01", "ipad-pro-13"], "\(rows[2].usedBy)")
        expect(rows[3].title == "mystery.ipsw" && rows[3].status?.text == "Unreadable", "\(rows[3])")
        let counts = VPhoneLaunchpadFirmwareRows.counts(rows)
        expect(counts[.all] == 4 && counts[.iPhone] == 1 && counts[.iPad] == 1 && counts[.cloudOS] == 1, "\(counts)")
        let uncatalogued = VPhoneLaunchpadFirmwareRows.rows([padFile], catalog: nil, uses: [])
        expect(uncatalogued[0].status == nil && uncatalogued[0].usedBy.isEmpty, "no catalog, no status")

        let measured = VPhoneLaunchpadLibraryScan.Machine(
            folder: URL(fileURLWithPath: "/lib/m"), libraryRoot: "/lib", name: "m", productType: nil,
            diskImageSize: nil, diskImageAllocated: nil, restoreTrees: ["iPhone17,3_26.6.2_23G90_Restore"],
            restoreAllocated: 13_900_000_000, totalAllocated: 13_900_000_000,
        )
        func item(_ activity: VPhoneLaunchpadRestoreOwner.Activity, _ creation: VPhoneLaunchpadRestoreOwner.Creation, installed: Bool? = true) -> VPhoneLaunchpadRestoreFilesItem {
            VPhoneLaunchpadFirmwareRows.restoreItem(
                measured,
                owner: VPhoneLaunchpadRestoreOwner(activity: activity, creation: creation, customFirmwareInstalled: installed),
                showsLibrary: false,
            )
        }
        expect(item(.stopped, .none).blockedReason == nil, "stopped machine")
        expect(item(.stopped, .finished).blockedReason == nil, "finished creation")
        expect(item(.busy, .running).blockedReason != nil, "creation under way")
        expect(item(.stopped, .unfinished).blockedReason != nil, "creation to retry")
        expect(item(.running, .none).blockedReason != nil, "running machine")
        expect(item(.busy, .none).blockedReason != nil, "busy machine")
        expect(item(.stopped, .none, installed: false).blockedReason != nil, "custom firmware still to install")
    }

    // MARK: - Shared NAT

    static func sharedNAT(in root: URL) {
        let fallback = VPhoneLaunchpadSharedNAT.current(preferences: root.appendingPathComponent("missing.plist"))
        expect(fallback?.subnet == "192.168.64.0/24" && fallback?.gateway == "192.168.64.1" && fallback?.isDefault == true, "vmnet default")
        let moved = VPhoneLaunchpadSharedNAT.make(address: "10.37.129.2", mask: "255.255.254.0", isDefault: false)
        expect(moved?.subnet == "10.37.128.0/23" && moved?.gateway == "10.37.129.2", "\(String(describing: moved))")
        expect(VPhoneLaunchpadSharedNAT.make(address: "10.0.0.1", mask: "255.0.255.0", isDefault: false) == nil, "mask with a hole")
        let preferences = root.appendingPathComponent("vmnet.plist")
        try? (["Shared_Net_Address": "192.168.70.1", "Shared_Net_Mask": "255.255.255.0"] as NSDictionary).write(to: preferences)
        let read = VPhoneLaunchpadSharedNAT.current(preferences: preferences)
        expect(read?.subnet == "192.168.70.0/24" && read?.isDefault == false, "\(String(describing: read))")
        let unreadable = root.appendingPathComponent("unreadable.plist")
        try? Data("not a plist".utf8).write(to: unreadable)
        expect(VPhoneLaunchpadSharedNAT.current(preferences: unreadable) == nil, "unreadable preferences")
    }
}
