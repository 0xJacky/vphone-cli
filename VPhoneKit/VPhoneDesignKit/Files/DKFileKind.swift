import SwiftUI

// MARK: - Kind

/// What a file browser row is, as far as its icon and type description go.
/// Derived from the entry's name and what `stat` said about it; see
/// `init(name:isDirectory:isSymlink:)`.
public enum DKFileKind: Hashable, Sendable {
    /// A directory.
    case folder
    /// The ".." row that goes up one level.
    case parent
    /// A symbolic link whose target is not known to be a directory.
    case symlink
    /// A symbolic link whose target is a directory.
    case folderSymlink
    /// A file. The tag names its type when the extension is one the design
    /// marks; `nil` draws a plain page.
    case document(DKFileTag?)

    /// Classifies a directory entry. ".." is always `parent`. A link is a
    /// `folderSymlink` when the caller resolved its target and found a
    /// directory (`isDirectory` and `isSymlink` both true), otherwise `symlink`.
    /// Files are classified by extension, ignoring case; a leading dot does not
    /// start an extension, so ".zshrc" has none.
    public init(name: String, isDirectory: Bool = false, isSymlink: Bool = false) {
        if name == ".." {
            self = .parent
        } else if isSymlink {
            self = isDirectory ? .folderSymlink : .symlink
        } else if isDirectory {
            self = .folder
        } else {
            self = .document(DKFileTag(fileName: name))
        }
    }

    /// The tag drawn on the icon, if any.
    public var tag: DKFileTag? {
        if case let .document(tag) = self {
            return tag
        }
        return nil
    }

    /// Whether the icon is a folder (plain, parent or linked).
    public var isFolderLike: Bool {
        switch self {
        case .folder, .parent, .folderSymlink: true
        case .symlink, .document: false
        }
    }

    /// A short type description for inspectors and VoiceOver: "Folder",
    /// "Python Script", "Document".
    public var typeDescription: String {
        switch self {
        case .folder: "Folder"
        case .parent: "Enclosing Folder"
        case .symlink: "Symbolic Link"
        case .folderSymlink: "Folder Link"
        case let .document(tag): tag?.typeDescription ?? "Document"
        }
    }

    /// The lowercased extension of a file name: the text after the last dot,
    /// ignoring leading dots. Empty when there is none ("Makefile", ".zshrc",
    /// "name."). Only the last extension counts: "backup.tar.gz" gives "gz".
    public static func fileExtension(of name: String) -> String {
        let lastComponent = name.split(separator: "/", omittingEmptySubsequences: true).last ?? ""
        let base = lastComponent.drop { $0 == "." }
        guard let dot = base.lastIndex(of: "."), base.index(after: dot) < base.endIndex else {
            return ""
        }
        return base[base.index(after: dot)...].lowercased()
    }
}

// MARK: - Tag

/// The colored label on a document icon: two to four letters naming the file's
/// type ("PY", "YML", "JSON"). One-letter tags ("C", "H", "M") are the
/// conventional names of those languages.
public struct DKFileTag: Hashable, Sendable {
    /// The tag's fill. Every fill is light enough for the dark tag ink.
    public enum Tone: String, Hashable, Sendable, CaseIterable {
        /// Source, markup and configuration text.
        case code
        case python
        case go
        case yaml
        /// Compressed archives, packages and firmware containers.
        case archive
        case image
        /// Executables, libraries and opaque data.
        case binary

        public var color: Color {
            switch self {
            case .code: DK.Palette.tagBlue
            case .python: DK.Palette.tagPython
            case .go: DK.Palette.tagGo
            case .yaml: DK.Palette.tagYAML
            case .archive: DK.Palette.tagArchive
            case .image: DK.Palette.iconTeal
            case .binary: DK.Palette.dotIdle
            }
        }
    }

    public let text: String
    public let tone: Tone
    public let typeDescription: String

    public init(_ text: String, tone: Tone, typeDescription: String) {
        self.text = text
        self.tone = tone
        self.typeDescription = typeDescription
    }

    /// The tag for a file name, or `nil` for a plain document.
    public init?(fileName: String) {
        let ext = DKFileKind.fileExtension(of: fileName)
        if let tag = Self.byExtension[ext] {
            self = tag
        } else if ext.isEmpty, let name = fileName.split(separator: "/").last,
                  let tag = Self.byDotfile[name.lowercased()]
        {
            self = tag
        } else {
            return nil
        }
    }

    /// The fill color.
    public var color: Color {
        tone.color
    }

    /// Four-letter tags are set smaller so they fit the label.
    public var isCompact: Bool {
        text.count > 3
    }

    // MARK: Mapping

    /// Extension (lowercased, without the dot) to tag. After uTerm's
    /// `BrowserFileKind` and the design's `DKFileIcon.tagFor`, widened to the
    /// files a guest and its firmware actually hold.
    static let byExtension: [String: DKFileTag] = {
        var map: [String: DKFileTag] = [:]
        func add(_ extensions: [String], _ text: String, _ tone: Tone, _ description: String) {
            for ext in extensions {
                map[ext] = DKFileTag(text, tone: tone, typeDescription: description)
            }
        }
        // Languages with their own color.
        add(["py", "pyw"], "PY", .python, "Python Script")
        add(["go"], "GO", .go, "Go Source")
        add(["yml", "yaml"], "YML", .yaml, "YAML")

        // Source and text formats.
        add(["swift"], "SWFT", .code, "Swift Source")
        add(["c"], "C", .code, "C Source")
        add(["h"], "H", .code, "C Header")
        add(["m"], "M", .code, "Objective-C Source")
        add(["mm"], "MM", .code, "Objective-C++ Source")
        add(["cpp", "cc", "cxx"], "CPP", .code, "C++ Source")
        add(["hpp", "hh", "hxx"], "HPP", .code, "C++ Header")
        add(["s"], "ASM", .code, "Assembly Source")
        add(["js", "mjs", "cjs"], "JS", .code, "JavaScript")
        add(["jsx"], "JSX", .code, "JavaScript")
        add(["ts", "mts", "cts"], "TS", .code, "TypeScript")
        add(["tsx"], "TSX", .code, "TypeScript")
        add(["json"], "JSON", .code, "JSON")
        add(["plist"], "PLST", .code, "Property List")
        add(["entitlements"], "ENT", .code, "Entitlements")
        add(["strings"], "STR", .code, "Strings File")
        add(["md", "markdown"], "MD", .code, "Markdown")
        add(["sh", "bash", "zsh", "command"], "SH", .code, "Shell Script")
        add(["conf", "cfg", "ini"], "CONF", .code, "Configuration")
        add(["toml"], "TOML", .code, "TOML")
        add(["xml"], "XML", .code, "XML")
        add(["html", "htm"], "HTML", .code, "HTML")
        add(["css"], "CSS", .code, "CSS")
        add(["csv"], "CSV", .code, "CSV")
        add(["log"], "LOG", .code, "Log")

        // Archives and containers.
        add(["zip"], "ZIP", .archive, "ZIP Archive")
        add(["tar"], "TAR", .archive, "Tar Archive")
        add(["gz"], "GZ", .archive, "Gzip Archive")
        add(["tgz"], "TGZ", .archive, "Gzip Archive")
        add(["xz"], "XZ", .archive, "XZ Archive")
        add(["bz2"], "BZ2", .archive, "Bzip2 Archive")
        add(["zst"], "ZST", .archive, "Zstandard Archive")
        add(["tzst"], "TZST", .archive, "Zstandard Archive")
        add(["7z"], "7Z", .archive, "7-Zip Archive")
        add(["ipa"], "IPA", .archive, "iOS App Archive")
        add(["ipsw"], "IPSW", .archive, "Firmware Archive")
        add(["dmg"], "DMG", .archive, "Disk Image")
        add(["im4p"], "IM4P", .archive, "IMG4 Payload")
        add(["img4"], "IMG4", .archive, "IMG4 Image")

        // Images.
        add(["png"], "PNG", .image, "PNG Image")
        add(["jpg", "jpeg"], "JPG", .image, "JPEG Image")
        add(["gif"], "GIF", .image, "GIF Image")
        add(["heic", "heif"], "HEIC", .image, "HEIF Image")
        add(["tif", "tiff"], "TIFF", .image, "TIFF Image")
        add(["webp"], "WEBP", .image, "WebP Image")
        add(["bmp"], "BMP", .image, "BMP Image")
        add(["svg"], "SVG", .image, "SVG Image")
        add(["pdf"], "PDF", .image, "PDF Document")

        // Binaries and data.
        add(["bin", "o", "out", "exe"], "BIN", .binary, "Binary")
        add(["dat", "raw"], "DAT", .binary, "Data")
        add(["dylib", "so", "a"], "LIB", .binary, "Library")
        add(["app"], "APP", .binary, "Application")
        add(["db", "sqlite", "sqlite3"], "DB", .binary, "Database")
        return map
    }()

    /// Shell startup files: dotfiles with no extension that are still scripts.
    static let byDotfile: [String: DKFileTag] = {
        let shell = DKFileTag("SH", tone: .code, typeDescription: "Shell Script")
        let names = [".profile", ".bashrc", ".bash_profile", ".bash_login", ".zshrc", ".zshenv", ".zprofile", ".zlogin"]
        return Dictionary(uniqueKeysWithValues: names.map { ($0, shell) })
    }()
}
