import Foundation
import VPhoneCoreKit
import VPhoneDesignKit

struct VPhoneRemoteFile: Identifiable, Hashable {
    let dir: String
    let name: String
    let type: FileType
    let size: UInt64
    let permissions: String
    let modified: Date
    let symlinkTargetsDirectory: Bool
    let resolvedPath: String?

    var id: String {
        path
    }

    var path: String {
        (dir as NSString).appendingPathComponent(name)
    }

    var isDirectory: Bool {
        type == .directory
    }

    var isSymbolicLink: Bool {
        type == .symbolicLink
    }

    var isDirectoryLike: Bool {
        isDirectory || symlinkTargetsDirectory
    }

    var displaySize: String {
        if isDirectory || isSymbolicLink {
            return "—"
        }
        return DKFormat.bytes(Int64(clamping: size))
    }

    var displayDate: String {
        Self.dateFormatter.string(from: modified)
    }

    /// The design's icon and type description for this entry.
    var kind: DKFileKind {
        DKFileKind(name: name, isDirectory: isDirectory || symlinkTargetsDirectory, isSymlink: isSymbolicLink)
    }

    /// The type description the inspector shows: "Folder", "Python Script".
    var kindDescription: String {
        VPhoneLocalization.text(kind.typeDescription)
    }

    /// The permission bits as `ls -l` writes them, "rwxr-xr-x", from the
    /// octal permissions vphoned reports. Set-user-ID, set-group-ID and
    /// sticky show as s, s and t over the execute bit (S, S and T without
    /// it). Text that is not octal comes back as is.
    var permissionString: String {
        guard let mode = Int(permissions, radix: 8) else { return permissions }
        let letters = Array("rwxrwxrwx")
        var bits = (0 ..< 9).map { index in
            mode & (1 << (8 - index)) != 0 ? letters[index] : "-"
        }
        for (flag, index, letter) in [(0o4000, 2, "s"), (0o2000, 5, "s"), (0o1000, 8, "t")] as [(Int, Int, Character)]
            where mode & flag != 0
        {
            bits[index] = bits[index] == "-" ? Character(letter.uppercased()) : letter
        }
        return String(bits)
    }

    /// `ls -l` style mode with the file type first, "drwxr-xr-x".
    var symbolicPermissions: String {
        guard Int(permissions, radix: 8) != nil else { return permissions }
        let typeLetter = switch type {
        case .directory: "d"
        case .symbolicLink: "l"
        case .file: "-"
        }
        return typeLetter + permissionString
    }

    enum FileType: String, Hashable {
        case file
        case directory = "dir"
        case symbolicLink = "link"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}

extension VPhoneRemoteFile {
    /// Parse from the dict returned by vphoned file_list entries.
    /// Returns nil for an entry whose name is not one path component, so a
    /// guest name never reaches a host path.
    init?(dir: String, entry: [String: Any]) {
        guard let name = entry["name"] as? String,
              VPhoneGuestFileName.isSafe(name),
              let typeStr = entry["type"] as? String,
              let type = FileType(rawValue: typeStr)
        else { return nil }

        self.dir = dir
        self.name = name
        self.type = type
        symlinkTargetsDirectory = entry["link_target_dir"] as? Bool ?? false
        resolvedPath = entry["resolved_path"] as? String
        // Read signed so a negative size becomes 0, not UInt64.max.
        size = UInt64(clamping: (entry["size"] as? NSNumber)?.int64Value ?? 0)
        permissions = entry["perm"] as? String ?? "---"
        modified = Date(timeIntervalSince1970: (entry["mtime"] as? Double) ?? 0)
    }
}
