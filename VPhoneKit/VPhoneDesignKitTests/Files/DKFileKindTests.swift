import Testing
@testable import VPhoneDesignKit

/// How directory entries are classified for their icons.
@Suite("DesignKit file kinds")
struct DKFileKindTests {
    @Test(arguments: [
        ("hook.py", "PY", DKFileTag.Tone.python),
        ("main.go", "GO", .go),
        ("config.yaml", "YML", .yaml),
        ("config.yml", "YML", .yaml),
        ("notes.md", "MD", .code),
        ("App.swift", "SWFT", .code),
        ("index.js", "JS", .code),
        ("index.ts", "TS", .code),
        ("package.json", "JSON", .code),
        ("Info.plist", "PLST", .code),
        ("run.sh", "SH", .code),
        ("hook.c", "C", .code),
        ("hook.h", "H", .code),
        ("system.log", "LOG", .code),
        ("Demo.ipa", "IPA", .archive),
        ("payload.zip", "ZIP", .archive),
        ("rootfs.tar", "TAR", .archive),
        ("cache.tzst", "TZST", .archive),
        ("shot.png", "PNG", .image),
        ("photo.jpeg", "JPG", .image),
        ("data.bin", "BIN", .binary),
        ("libhook.dylib", "LIB", .binary),
    ])
    func `a known extension gets its tag`(name: String, text: String, tone: DKFileTag.Tone) throws {
        let tag = try #require(DKFileKind(name: name).tag, "\(name)")
        #expect(tag.text == text)
        #expect(tag.tone == tone)
    }

    @Test
    func `extensions match regardless of case`() {
        #expect(DKFileKind(name: "README.MD").tag?.text == "MD")
        #expect(DKFileKind(name: "Hook.Py").tag?.text == "PY")
        #expect(DKFileKind(name: "IMG_0001.HEIC").tag?.tone == .image)
    }

    @Test
    func `only the last of a double extension counts`() {
        #expect(DKFileKind(name: "backup.tar.gz").tag?.text == "GZ")
        #expect(DKFileKind(name: "rootfs.tar.zst").tag?.text == "ZST")
        #expect(DKFileKind(name: "kernelcache.release.im4p").tag?.text == "IM4P")
        #expect(DKFileKind.fileExtension(of: "backup.tar.gz") == "gz")
    }

    @Test
    func `a dotfile has no extension`() {
        #expect(DKFileKind.fileExtension(of: ".gitignore") == "")
        #expect(DKFileKind(name: ".gitignore") == .document(nil))
        #expect(DKFileKind(name: ".DS_Store") == .document(nil))
        #expect(DKFileKind.fileExtension(of: ".config.json") == "json")
        #expect(DKFileKind(name: ".config.json").tag?.text == "JSON")
    }

    @Test
    func `shell startup dotfiles are shell scripts`() {
        #expect(DKFileKind(name: ".zshrc").tag?.text == "SH")
        #expect(DKFileKind(name: "/var/mobile/.profile").tag?.text == "SH")
    }

    @Test
    func `a name without an extension is a plain document`() {
        #expect(DKFileKind(name: "Makefile") == .document(nil))
        #expect(DKFileKind(name: "trailing.") == .document(nil))
        #expect(DKFileKind(name: "notes.txt") == .document(nil))
        #expect(DKFileKind(name: "archive.unknownext") == .document(nil))
        #expect(DKFileKind(name: "Makefile").typeDescription == "Document")
    }

    @Test
    func `directories, links and the parent row are not documents`() {
        #expect(DKFileKind(name: "..") == .parent)
        #expect(DKFileKind(name: "..", isDirectory: true) == .parent)
        #expect(DKFileKind(name: "Library", isDirectory: true) == .folder)
        #expect(DKFileKind(name: "hook.py", isDirectory: true) == .folder)
        #expect(DKFileKind(name: "Downloads", isSymlink: true) == .symlink)
        #expect(DKFileKind(name: "Media", isDirectory: true, isSymlink: true) == .folderSymlink)
        #expect(DKFileKind(name: "Library", isDirectory: true).tag == nil)
        #expect(DKFileKind.folderSymlink.isFolderLike)
        #expect(!DKFileKind.symlink.isFolderLike)
    }

    @Test
    func `type descriptions name the kind`() {
        #expect(DKFileKind.folder.typeDescription == "Folder")
        #expect(DKFileKind.symlink.typeDescription == "Symbolic Link")
        #expect(DKFileKind(name: "hook.py").typeDescription == "Python Script")
    }

    @Test
    func `every tag is one to four characters and only long tags are compact`() {
        let tags = Array(DKFileTag.byExtension.values) + Array(DKFileTag.byDotfile.values)
        #expect(!tags.isEmpty)
        for tag in tags {
            #expect((1 ... 4).contains(tag.text.count), "\(tag.text)")
            #expect(tag.text == tag.text.uppercased(), "\(tag.text)")
            #expect(tag.isCompact == (tag.text.count == 4), "\(tag.text)")
            #expect(!tag.typeDescription.isEmpty)
        }
    }

    @Test
    func `every extension key is lowercased and dotless`() {
        for key in DKFileTag.byExtension.keys {
            #expect(key == key.lowercased())
            #expect(!key.contains("."))
        }
    }

    @Test
    func `every tone has a color`() {
        #expect(DKFileTag.Tone.allCases.count == 7)
        for tone in DKFileTag.Tone.allCases {
            _ = tone.color
        }
    }
}
