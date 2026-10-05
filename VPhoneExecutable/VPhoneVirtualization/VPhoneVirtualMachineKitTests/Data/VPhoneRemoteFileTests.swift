import Foundation
import Testing
import VPhoneDesignKit
@testable import VPhoneVirtualMachineKit

/// Entries of vphoned `file_list` as the Files page reads and counts them.
@MainActor
@Suite("Guest files")
struct VPhoneRemoteFileTests {
    private static let entries: [[String: Any]] = [
        ["name": "Library", "type": "dir", "perm": "755", "mtime": 1_790_000_000.0, "size": 640],
        ["name": "Containers", "type": "dir", "perm": "755", "mtime": 1_790_000_000.0, "size": 192],
        ["name": "Downloads", "type": "link", "perm": "777", "mtime": 1_790_000_000.0, "size": 20, "link_target_dir": true, "resolved_path": "/private/var/mobile/Media/Downloads"],
        ["name": "notes.md", "type": "file", "perm": "644", "mtime": 1_790_000_000.0, "size": 2048],
        ["name": "backup.tar.gz", "type": "file", "perm": "644", "mtime": 1_790_000_000.0, "size": 48_000_000],
        ["name": "data.bin", "type": "file", "perm": "600", "mtime": 1_790_000_000.0, "size": 65536],
        ["name": "current", "type": "link", "perm": "755", "mtime": 1_790_000_000.0, "size": 12],
    ]

    private func files() -> [VPhoneRemoteFile] {
        Self.entries.compactMap { VPhoneRemoteFile(dir: "/var/mobile", entry: $0) }
    }

    private func file(_ name: String) -> VPhoneRemoteFile {
        files().first { $0.name == name }!
    }

    // MARK: - Parsing

    @Test
    func `an entry becomes a file under its folder`() {
        let notes = file("notes.md")
        #expect(notes.path == "/var/mobile/notes.md")
        #expect(notes.id == notes.path)
        #expect(notes.type == .file)
        #expect(notes.size == 2048)
        #expect(notes.modified == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test
    func `names that are not one path component and unknown types are dropped`() {
        for name in ["..", ".", "a/b", ""] {
            #expect(VPhoneRemoteFile(dir: "/var", entry: ["name": name, "type": "file"]) == nil, "\(name)")
        }
        #expect(VPhoneRemoteFile(dir: "/var", entry: ["name": "x", "type": "socket"]) == nil)
        #expect(VPhoneRemoteFile(dir: "/var", entry: ["type": "file"]) == nil)
    }

    @Test
    func `a negative size reads as zero and a missing mode as dashes`() {
        let entry = VPhoneRemoteFile(dir: "/var", entry: ["name": "x", "type": "file", "size": -5])
        #expect(entry?.size == 0)
        #expect(entry?.permissions == "---")
    }

    // MARK: - Permissions

    @Test
    func `permissions read as ls -l modes`() {
        #expect(file("Library").symbolicPermissions == "drwxr-xr-x")
        #expect(file("notes.md").symbolicPermissions == "-rw-r--r--")
        #expect(file("data.bin").symbolicPermissions == "-rw-------")
        #expect(file("Downloads").symbolicPermissions == "lrwxrwxrwx")
        // A mode that is not octal is shown as the guest sent it.
        let odd = VPhoneRemoteFile(dir: "/", entry: ["name": "x", "type": "file", "perm": "rw?"])
        #expect(odd?.symbolicPermissions == "rw?")
    }

    // MARK: - Kind

    @Test
    func `kinds follow the type, link target and extension`() {
        #expect(file("Library").kind == .folder)
        #expect(file("Downloads").kind == .folderSymlink)
        #expect(file("current").kind == .symlink)
        #expect(file("notes.md").kind.typeDescription == "Markdown")
        #expect(file("backup.tar.gz").kind.typeDescription == "Gzip Archive")
        #expect(file("Library").kind.typeDescription == "Folder")
        #expect(file("Downloads").isDirectoryLike)
        #expect(!file("current").isDirectoryLike)
    }

    @Test
    func `folders and links show no size`() {
        #expect(file("Library").displaySize == "—")
        #expect(file("current").displaySize == "—")
        #expect(file("notes.md").displaySize != "—")
    }

    // MARK: - Model

    private func model() -> VPhoneFileBrowserModel {
        let model = VPhoneFileBrowserModel(control: VPhoneGuestControl(), quickLookController: VPhoneQuickLookController())
        model.files = files()
        return model
    }

    @Test
    func `folders are listed first in every sort order`() {
        let model = model()
        #expect(model.filteredFiles.map(\.name) == [
            "Containers", "Downloads", "Library", "backup.tar.gz", "current", "data.bin", "notes.md",
        ])
        model.sortOrder = [KeyPathComparator(\VPhoneRemoteFile.size, order: .reverse)]
        let names = model.filteredFiles.map(\.name)
        #expect(names.prefix(3).sorted() == ["Containers", "Downloads", "Library"])
        #expect(Array(names.dropFirst(3)) == ["backup.tar.gz", "data.bin", "notes.md", "current"])
    }

    @Test
    func `the status bar counts folders, files and the selection`() {
        let model = model()
        #expect(model.statusText == "3 folders · 4 files")
        model.selection = ["/var/mobile/notes.md"]
        #expect(model.statusText == "3 folders · 4 files · 1 selected")
        #expect(model.selectedFiles.map(\.name) == ["notes.md"])
    }

    @Test
    func `the filter matches names without case and counts what it shows`() {
        let model = model()
        model.searchText = "LIB"
        #expect(model.filteredFiles.map(\.name) == ["Library"])
        #expect(model.statusText == "1 folder · 0 files · 1 of 7 shown")
    }
}
