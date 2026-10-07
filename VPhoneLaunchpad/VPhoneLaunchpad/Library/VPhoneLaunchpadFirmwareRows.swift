import Foundation

// MARK: - Rows

/// The Firmwares page's kind filter.
nonisolated enum VPhoneLaunchpadFirmwareFilter: String, CaseIterable, Hashable, Sendable {
    case all, iPhone, iPad, cloudOS

    func admits(_ kind: VPhoneLaunchpadIPSW.Kind) -> Bool {
        switch self {
        case .all: true
        case .iPhone: kind == .iPhone
        case .iPad: kind == .iPad
        case .cloudOS: kind == .cloudOS
        }
    }
}

/// A status the page draws as a badge, or as a status dot while downloading.
nonisolated struct VPhoneLaunchpadFirmwareStatus: Hashable, Sendable {
    enum Tone: Hashable, Sendable {
        case success, info, warning, danger, neutral
    }

    var tone: Tone
    var text: String
}

/// One IPSW in the Downloaded table.
nonisolated struct VPhoneLaunchpadFirmwareRow: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var fileName: String
    var kind: VPhoneLaunchpadIPSW.Kind
    var kindLabel: String
    var size: Int64
    var usedBy: [String]
    var status: VPhoneLaunchpadFirmwareStatus?
    var isDownloading: Bool
    /// Why the IPSW cannot be deleted now; nil when it can.
    var blockedReason: String? = nil
}

/// One machine's prepared restore files.
nonisolated struct VPhoneLaunchpadRestoreFilesItem: Identifiable, Hashable, Sendable {
    /// The machine folder.
    var id: String
    var machine: String
    /// The library folder, shown when the machines span several.
    var library: String?
    var trees: [String]
    var size: Int64
    var detail: String
    /// Why the files cannot be removed now; nil when they can.
    var blockedReason: String?
}

// MARK: - Catalog

/// Names from `fw catalog --json`, found by the file a catalog URL becomes
/// in the cache, or by the URL's own file name for a copy kept elsewhere.
nonisolated struct VPhoneLaunchpadFirmwareCatalogIndex: Sendable {
    struct Entry: Hashable, Sendable {
        var name: String
        var url: String
        var isCloudOS: Bool
    }

    private var names: [String: String] = [:]
    /// Build and product types of each iOS or iPadOS release the catalog lists.
    private var releases: [VPhoneLaunchpadIPSW] = []

    init(entries: [Entry]) {
        for entry in entries {
            guard let url = URL(string: entry.url) else {
                continue
            }
            names[VPhoneLaunchpadIPSW.cacheName(for: url)] = entry.name
            names[url.lastPathComponent] = entry.name
            if !entry.isCloudOS, let facts = VPhoneLaunchpadIPSW(fileName: url.lastPathComponent) {
                releases.append(facts)
            }
        }
    }

    func name(forFile fileName: String) -> String? {
        names[fileName]
    }

    /// Whether the catalog lists this release for one of its devices.
    func lists(_ facts: VPhoneLaunchpadIPSW) -> Bool {
        releases.contains { release in
            release.build == facts.build
                && (facts.productTypes.isEmpty || !Set(release.productTypes).isDisjoint(with: facts.productTypes))
        }
    }
}

// MARK: - Machines

/// What a machine was restored from, or is being created from, for the Used
/// by column.
nonisolated struct VPhoneLaunchpadFirmwareUse: Hashable, Sendable {
    struct Release: Hashable, Sendable {
        var version: String
        var build: String
    }

    var machine: String
    /// `guestProductType` from the machine's config.plist.
    var productType: String?
    var ios: Release?
    var cloudOS: Release?
    /// The `--iphone-source` and `--cloudos-source` of a creation under way:
    /// URLs, or paths of local files.
    var sources: [String] = []
    var isCreating = false
    /// A creation that has not finished: under way, or stopped short and
    /// waiting for a retry, which reads its sources again.
    var needsSources = false

    func uses(_ file: VPhoneLaunchpadLibraryScan.IPSWFile) -> Bool {
        if sources.contains(where: { Self.source($0, is: file) }) {
            return true
        }
        guard let facts = file.facts else {
            return false
        }
        if facts.kind == .cloudOS {
            return cloudOS == Release(version: facts.version, build: facts.build)
        }
        guard ios == Release(version: facts.version, build: facts.build) else {
            return false
        }
        guard let productType, !facts.productTypes.isEmpty else {
            return true
        }
        return facts.productTypes.contains(productType)
    }

    static func source(_ source: String, is file: VPhoneLaunchpadLibraryScan.IPSWFile) -> Bool {
        if let url = URL(string: source), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return VPhoneLaunchpadIPSW.cacheName(for: url) == file.name
        }
        let path = source.hasPrefix("file://") ? URL(string: source)?.path ?? source : source
        return URL(fileURLWithPath: path).standardizedFileURL.path == file.url.standardizedFileURL.path
    }
}

/// What the page knows about the machine that owns restore files.
nonisolated struct VPhoneLaunchpadRestoreOwner: Hashable, Sendable {
    enum Activity: Hashable, Sendable {
        case stopped
        case running
        /// Another action is under way, such as a kernel update.
        case busy
    }

    enum Creation: Hashable, Sendable {
        case none
        case running
        /// Stopped short of first boot; a retry starts from the failed step.
        case unfinished
        case finished
    }

    var activity: Activity
    var creation: Creation
    /// From `vm list`: false while the custom firmware install has not finished.
    var customFirmwareInstalled: Bool?
    /// "iOS 26.6.2 (23G90) + cloudOS 26.4 (23E5207q)", when restored.
    var firmware: String?
}

// MARK: - Building

nonisolated enum VPhoneLaunchpadFirmwareRows {
    static func rows(
        _ files: [VPhoneLaunchpadLibraryScan.IPSWFile],
        catalog: VPhoneLaunchpadFirmwareCatalogIndex?,
        uses: [VPhoneLaunchpadFirmwareUse],
        isCreating: Bool = false,
    ) -> [VPhoneLaunchpadFirmwareRow] {
        files.map { file in
            let facts = file.facts
            let kind = facts?.kind ?? .unknown
            let catalogName = catalog?.name(forFile: file.name)
            return VPhoneLaunchpadFirmwareRow(
                id: file.id,
                title: title(file, catalogName: catalogName),
                fileName: file.name,
                kind: kind,
                kindLabel: kindLabel(kind, beta: facts?.isBeta == true || catalogName?.localizedCaseInsensitiveContains("beta") == true),
                size: file.size,
                usedBy: uses.filter { $0.uses(file) }.map { use in
                    use.isCreating ? String(localized: "\(use.machine) (creating)") : use.machine
                },
                status: status(file, catalog: catalog),
                isDownloading: file.isDownloading,
                blockedReason: deletionBlock(file, uses: uses, isCreating: isCreating),
            )
        }
        .sorted { lhs, rhs in
            lhs.kind == rhs.kind
                ? lhs.title.localizedStandardCompare(rhs.title) == .orderedDescending
                : order(lhs.kind) < order(rhs.kind)
        }
    }

    /// iPhone first, cloudOS last, as the filter reads.
    private static func order(_ kind: VPhoneLaunchpadIPSW.Kind) -> Int {
        switch kind {
        case .iPhone: 0
        case .iPad: 1
        case .cloudOS: 2
        case .unknown: 3
        }
    }

    static func title(_ file: VPhoneLaunchpadLibraryScan.IPSWFile, catalogName: String?) -> String {
        if let catalogName {
            guard let build = file.facts?.build, !catalogName.contains(build) else {
                return catalogName
            }
            return "\(catalogName) (\(build))"
        }
        return file.facts?.title ?? file.name
    }

    static func kindLabel(_ kind: VPhoneLaunchpadIPSW.Kind, beta: Bool) -> String {
        let name = switch kind {
        case .iPhone: String(localized: "iPhone")
        case .iPad: String(localized: "iPad")
        case .cloudOS: String(localized: "cloudOS")
        case .unknown: String(localized: "Unknown")
        }
        return beta ? String(localized: "\(name) · beta") : name
    }

    static func status(_ file: VPhoneLaunchpadLibraryScan.IPSWFile, catalog: VPhoneLaunchpadFirmwareCatalogIndex?) -> VPhoneLaunchpadFirmwareStatus? {
        if file.isDownloading {
            return VPhoneLaunchpadFirmwareStatus(tone: .warning, text: String(localized: "Downloading"))
        }
        guard let facts = file.facts else {
            return VPhoneLaunchpadFirmwareStatus(tone: .danger, text: String(localized: "Unreadable"))
        }
        if facts.kind == .cloudOS {
            return facts.hasGuestBoard.map { has in
                has
                    ? VPhoneLaunchpadFirmwareStatus(tone: .info, text: String(localized: "Has vphone600ap"))
                    : VPhoneLaunchpadFirmwareStatus(tone: .warning, text: String(localized: "No vphone600ap"))
            }
        }
        guard let catalog else {
            return nil
        }
        return catalog.lists(facts)
            ? VPhoneLaunchpadFirmwareStatus(tone: .success, text: String(localized: "In Catalog"))
            : VPhoneLaunchpadFirmwareStatus(tone: .neutral, text: String(localized: "Not in Catalog"))
    }

    static func counts(_ rows: [VPhoneLaunchpadFirmwareRow]) -> [VPhoneLaunchpadFirmwareFilter: Int] {
        var counts: [VPhoneLaunchpadFirmwareFilter: Int] = [:]
        for filter in VPhoneLaunchpadFirmwareFilter.allCases {
            counts[filter] = rows.count { filter.admits($0.kind) }
        }
        return counts
    }

    // MARK: Deleting

    /// Why `file` cannot be deleted now, or nil. A restored machine no longer
    /// reads its IPSWs: Update Kernel and Update Guest Environment work from
    /// the machine folder. So only a creation that has not finished holds
    /// one, since a retry reads its sources again. A partial file is a
    /// download, and only a creation under way downloads (`isCreating`).
    static func deletionBlock(
        _ file: VPhoneLaunchpadLibraryScan.IPSWFile,
        uses: [VPhoneLaunchpadFirmwareUse],
        isCreating: Bool,
    ) -> String? {
        let creations = uses
            .filter { use in use.needsSources && use.sources.contains { VPhoneLaunchpadFirmwareUse.source($0, is: file) } }
            .map(\.machine)
        if !creations.isEmpty {
            return String(localized: "Creating \(creations.joined(separator: ", ")) reads this IPSW. Finish or discard the creation first.")
        }
        if file.isDownloading, isCreating {
            return String(localized: "This IPSW is still downloading.")
        }
        return nil
    }

    // MARK: Restore files

    static func restoreItem(
        _ machine: VPhoneLaunchpadLibraryScan.Machine,
        owner: VPhoneLaunchpadRestoreOwner?,
        showsLibrary: Bool,
    ) -> VPhoneLaunchpadRestoreFilesItem {
        let owner = owner ?? VPhoneLaunchpadRestoreOwner(activity: .stopped, creation: .none)
        var detail: [String] = []
        if let firmware = owner.firmware {
            detail.append(firmware)
        }
        let blocked: String?
        switch (owner.creation, owner.activity) {
        case (.running, _):
            detail.append(String(localized: "in use by creation"))
            blocked = String(localized: "The machine is being created from these files.")
        case (.unfinished, _):
            detail.append(String(localized: "kept for retrying the creation"))
            blocked = String(localized: "Retrying the creation needs these files. Finish or discard the creation first.")
        case (_, .running):
            detail.append(String(localized: "machine running"))
            blocked = String(localized: "Stop the machine first.")
        case (_, .busy):
            detail.append(String(localized: "machine busy"))
            blocked = String(localized: "Wait for the machine's current action to finish.")
        default:
            if owner.customFirmwareInstalled == false {
                detail.append(String(localized: "needed to install custom firmware"))
                blocked = String(localized: "Installing custom firmware needs these files.")
            } else {
                detail.append(String(localized: "kept after creation"))
                blocked = nil
            }
        }
        return VPhoneLaunchpadRestoreFilesItem(
            id: machine.id,
            machine: machine.name,
            library: showsLibrary ? VPhoneLaunchpadLibraryFormat.abbreviated(machine.libraryRoot) : nil,
            trees: machine.restoreTrees,
            size: machine.restoreAllocated,
            detail: detail.joined(separator: " · "),
            blockedReason: blocked,
        )
    }
}
