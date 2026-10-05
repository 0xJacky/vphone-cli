@preconcurrency import Foundation
import SwiftUI
import UniformTypeIdentifiers
import VPhoneCoreKit
import VPhoneDesignKit

/// The Files page: a header with Upload, New Folder, Refresh and a filter, a
/// path bar, the folder's table with an inspector for the selection, and a
/// status bar. The whole page takes files dropped from Finder.
struct VPhoneFileBrowserView: View {
    @Bindable var model: VPhoneFileBrowserModel

    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var fileToRename: VPhoneRemoteFile?
    @State private var renameName = ""
    @State private var isDropTargeted = false
    @State private var contentWidth: CGFloat = 0

    /// The table keeps 520pt before the inspector moves under it.
    private static let inspectorWidth: CGFloat = 280
    private static let sideBySideWidth: CGFloat = 520 + inspectorWidth

    var body: some View {
        VStack(spacing: 0) {
            header
            pathBar
            content
                .opacity(model.isTransferring ? 0.25 : 1)
                .disabled(model.isTransferring)
                .overlay {
                    if model.isTransferring {
                        transferProgress
                    }
                }
            DKStatusBar(
                isConnected: model.control.isConnected,
                text: statusMessage,
                detail: model.statusText,
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DK.Palette.window)
        .overlay {
            if isDropTargeted {
                dropHighlight
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: dropFiles)
        .task { await model.refresh() }
        .alert(
            "Error",
            isPresented: .init(
                get: { model.error != nil },
                set: {
                    if !$0 {
                        model.error = nil
                    }
                },
            ),
        ) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
        .sheet(isPresented: $showNewFolder) {
            newFolderSheet
        }
        .sheet(item: $fileToRename) { file in
            renameSheet(for: file)
        }
    }

    private var statusMessage: String {
        guard model.control.isConnected else {
            return VPhoneLocalization.text("Guest not connected")
        }
        if model.isLoading {
            return VPhoneLocalization.text("Loading…")
        }
        return [
            VPhoneLocalization.text("Connected"),
            model.currentPath,
            VPhoneLocalization.text("Drop files anywhere to upload here"),
        ].joined(separator: " · ")
    }

    // MARK: - Header

    private var header: some View {
        DKPageHeader(VPhoneLocalization.text("Files"), subtitle: model.currentPath) {
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Upload"),
                glyph: .upload,
                isEnabled: !model.isTransferring,
                help: VPhoneLocalization.text("Upload files from this Mac to this folder"),
                action: uploadAction,
            ))
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("New Folder"),
                glyph: .folderPlus,
                size: .icon,
                isEnabled: !model.isTransferring,
                help: VPhoneLocalization.text("New Folder (⌘N)"),
                action: beginNewFolder,
            ))
            .keyboardShortcut("n", modifiers: .command)
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Refresh"),
                glyph: .refresh,
                size: .icon,
                isEnabled: !model.isTransferring,
                help: VPhoneLocalization.text("Refresh (⌘R)"),
            ) {
                Task { await model.refresh() }
            })
            .keyboardShortcut("r", modifiers: .command)
            DKSearchField(VPhoneLocalization.text("Filter files"), text: $model.searchText, width: 170)
        }
    }

    // MARK: - Path Bar

    private var pathBar: some View {
        HStack(spacing: 6) {
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Back"),
                glyph: .left,
                size: .icon,
                isEnabled: model.canGoBack && !model.isTransferring,
                help: VPhoneLocalization.text("Back (⌘←)"),
            ) { model.goBack() })
            .keyboardShortcut(.leftArrow, modifiers: .command)
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Forward"),
                glyph: .right,
                size: .icon,
                isEnabled: model.canGoForward && !model.isTransferring,
                help: VPhoneLocalization.text("Forward (⌘→)"),
            ) { model.goForward() })
            .keyboardShortcut(.rightArrow, modifiers: .command)
            ScrollView(.horizontal, showsIndicators: false) {
                DKPathBar(path: model.currentPath, rootLabel: VPhoneLocalization.text("Guest root")) { path in
                    model.goToPath(path)
                }
                .padding(.leading, 6)
            }
            .disabled(model.isTransferring)
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, DK.Space.s2)
        .padding(.horizontal, DK.Space.s4)
        .overlay(alignment: .bottom) {
            DK.Palette.divider.frame(height: DK.Metric.hairline)
        }
    }

    // MARK: - Content

    private var content: some View {
        let sideBySide = contentWidth == 0 || contentWidth >= Self.sideBySideWidth
        return Group {
            if sideBySide {
                HStack(spacing: 0) {
                    tableView
                    DK.Palette.divider.frame(width: DK.Metric.hairline)
                    inspector(compact: false)
                        .frame(width: Self.inspectorWidth)
                }
            } else {
                VStack(spacing: 0) {
                    tableView
                    DK.Palette.divider.frame(height: DK.Metric.hairline)
                    inspector(compact: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
    }

    private func inspector(compact: Bool) -> some View {
        VPhoneFileInspectorView(
            model: model,
            compact: compact,
            open: { model.openItem($0) },
            download: downloadAction,
            rename: beginRename,
            delete: { Task { await model.deleteSelected() } },
        )
    }

    // MARK: - Table

    private var tableView: some View {
        Table(of: VPhoneRemoteFile.self, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name) { file in
                HStack(spacing: DK.Space.s2) {
                    DKFileIcon(file.kind, size: 18)
                    Text(file.name)
                        .font(DK.Typeface.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .help(file.name)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(file.name), \(file.kindDescription)")
            }
            .width(min: 160, ideal: 260, max: .infinity)

            TableColumn("Permissions", value: \.permissions) { file in
                DKTableCellView(.badge(.neutral, file.permissions))
                    .help(file.symbolicPermissions)
            }
            .width(min: 70, ideal: 90, max: 110)

            TableColumn("Modified", value: \.modified) { file in
                DKTableCellView(.muted(file.displayDate))
            }
            .width(min: 90, ideal: 130, max: .infinity)

            TableColumn("Size", value: \.size) { file in
                DKTableCellView(.mono(file.displaySize))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80, max: 120)
        } rows: {
            ForEach(model.filteredFiles) { file in
                if file.isDirectoryLike {
                    TableRow(file)
                } else {
                    TableRow(file)
                        .draggable(FileDragItem(file: file, control: model.control))
                }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(DK.Palette.window)
        .contextMenu(forSelectionType: VPhoneRemoteFile.ID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            primaryAction(for: ids)
        }
        .onKeyPress(.space) {
            model.quickLookSelected()
            return .handled
        }
        .onChange(of: model.selection) {
            model.closeQuickLook()
        }
        .overlay {
            if model.filteredFiles.isEmpty, !model.isLoading {
                Text(model.searchText.isEmpty
                    ? VPhoneLocalization.text("This folder is empty. Drop files here to upload them.")
                    : VPhoneLocalization.text("No items match the filter."))
                    .font(DK.Typeface.body)
                    .foregroundStyle(DK.Palette.muted)
                    .multilineTextAlignment(.center)
                    .padding(DK.Space.s6)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Transfer Progress

    private var transferProgress: some View {
        DKCard(.padded) {
            Text(model.transferName ?? VPhoneLocalization.text("Transferring…"))
                .font(DK.Typeface.bodyStrong)
                .lineLimit(1)
                .truncationMode(.middle)
            if model.transferTotal > 0, model.transferCurrent > 0 {
                DKProgress(
                    value: Double(model.transferCurrent) / Double(model.transferTotal),
                    label: VPhoneLocalization.text("Transfer"),
                )
            } else {
                DKProgress.indeterminate(label: VPhoneLocalization.text("Transfer"))
            }
            if model.transferTotal > 0 {
                Text(VPhoneLocalization.format(
                    "%@ / %@", formatBytes(model.transferCurrent), formatBytes(model.transferTotal),
                ))
                .font(DK.Typeface.monoSmall)
                .foregroundStyle(DK.Palette.muted)
            }
        }
        .frame(width: 320)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Context Menu

    @ViewBuilder
    func contextMenu(for ids: Set<VPhoneRemoteFile.ID>) -> some View {
        Button("Open") { primaryAction(for: ids) }
        Button("Download") {
            model.selection = ids
            downloadAction()
        }
        if ids.count == 1, let file = model.files.first(where: { ids.contains($0.id) }) {
            Button("Rename…") { beginRename(file) }
        }
        Button("Delete") {
            model.selection = ids
            Task { await model.deleteSelected() }
        }
        Divider()
        Button("Refresh") { Task { await model.refresh() } }
        Divider()
        Button("Copy Name") { copyNames(ids: ids) }
        Button("Copy Path") { copyPaths(ids: ids) }
        Divider()
        Button("Upload…") { uploadAction() }
        Button("New Folder…") { beginNewFolder() }
    }

    // MARK: - New Folder Sheet

    var newFolderSheet: some View {
        nameSheet(
            title: VPhoneLocalization.text("New Folder"),
            prompt: VPhoneLocalization.text("Folder name"),
            text: $newFolderName,
            confirm: VPhoneLocalization.text("Create"),
            canConfirm: validName(newFolderName),
            cancel: { showNewFolder = false },
            submit: createFolder,
        )
    }

    // MARK: - Rename Sheet

    func renameSheet(for file: VPhoneRemoteFile) -> some View {
        nameSheet(
            title: VPhoneLocalization.text("Rename"),
            prompt: VPhoneLocalization.text("Name"),
            text: $renameName,
            confirm: VPhoneLocalization.text("Rename"),
            canConfirm: validName(renameName) && renameName.trimmingCharacters(in: .whitespaces) != file.name,
            cancel: { fileToRename = nil },
            submit: { rename(file) },
        )
    }

    private func nameSheet(
        title: String,
        prompt: String,
        text: Binding<String>,
        confirm: String,
        canConfirm: Bool,
        cancel: @escaping () -> Void,
        submit: @escaping () -> Void,
    ) -> some View {
        VStack(alignment: .leading, spacing: DK.Space.s4) {
            Text(title)
                .font(DK.Typeface.sheetTitle)
                .foregroundStyle(DK.Palette.ink)
            TextField(prompt, text: text)
                .textFieldStyle(.dkFieldMono)
                .onSubmit(submit)
            HStack(spacing: DK.Space.s2) {
                Spacer()
                DKButton(VPhoneLocalization.text("Cancel"), action: cancel)
                    .keyboardShortcut(.cancelAction)
                DKButton(DKButtonSpec(confirm, variant: .primary, isEnabled: canConfirm, action: submit))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DK.Space.s5)
        .frame(width: 340)
        .background(DK.Palette.sidebar)
    }

    // MARK: - Actions

    func primaryAction(for ids: Set<VPhoneRemoteFile.ID>) {
        guard let id = ids.first,
              let file = model.filteredFiles.first(where: { $0.id == id })
        else { return }
        model.openItem(file)
    }

    func beginNewFolder() {
        newFolderName = ""
        showNewFolder = true
    }

    func beginRename(_ file: VPhoneRemoteFile) {
        renameName = file.name
        fileToRename = file
    }

    func uploadAction() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        // Header and context menu actions come from the window hosting this page, which is key.
        VPhoneAlert.present(panel, on: NSApp.keyWindow) { response in
            guard response == .OK else { return }
            Task { await model.uploadFiles(urls: panel.urls) }
        }
    }

    func downloadAction() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = VPhoneLocalization.text("Save Here")
        VPhoneAlert.present(panel, on: NSApp.keyWindow) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model.downloadSelected(to: url) }
        }
    }

    func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard validName(name) else { return }
        showNewFolder = false
        Task { await model.createNewFolder(name: name) }
    }

    func rename(_ file: VPhoneRemoteFile) {
        let name = renameName.trimmingCharacters(in: .whitespaces)
        guard validName(name), name != file.name else { return }
        fileToRename = nil
        Task { await model.renameFile(file, to: name) }
    }

    func validName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != "." && trimmed != ".."
            && !trimmed.contains("/") && !trimmed.contains("\0")
    }

    // MARK: - Drop to Upload

    /// Shown over the whole page while files are dragged in from Finder.
    var dropHighlight: some View {
        RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
            .strokeBorder(DK.Palette.accent, lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                    .fill(DK.Palette.accentTint),
            )
            .overlay {
                HStack(spacing: DK.Space.s2) {
                    DKIcon(.upload, size: 16)
                        .foregroundStyle(DK.Palette.accent)
                    Text(VPhoneLocalization.format("Drop to Upload to %@", model.currentPath))
                        .font(DK.Typeface.bodyStrong)
                        .foregroundStyle(DK.Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, DK.Space.s2)
                .background(Capsule().fill(DK.Palette.window))
                .overlay(Capsule().strokeBorder(DK.Palette.line, lineWidth: DK.Metric.hairline))
            }
            .padding(DK.Space.s1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    func dropFiles(_ providers: [NSItemProvider]) -> Bool {
        guard !model.isTransferring else { return false }
        let validProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !validProviders.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in validProviders {
                if let url = await loadDroppedURL(from: provider) {
                    urls.append(url)
                }
            }
            if urls.isEmpty {
                model.error = VPhoneLocalization.text(
                    "Unable to read the dropped items. Drag files from Finder, then try again.",
                )
            } else {
                await model.uploadFiles(urls: urls)
            }
        }
        return true
    }

    func loadDroppedURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    // MARK: - Copy

    func copyNames(ids: Set<VPhoneRemoteFile.ID>) {
        let names = model.filteredFiles
            .filter { ids.contains($0.id) }
            .map(\.name)
            .joined(separator: "\n")
        NSPasteboard.general.prepareForNewContents()
        NSPasteboard.general.setString(names, forType: .string)
    }

    func copyPaths(ids: Set<VPhoneRemoteFile.ID>) {
        let paths = model.filteredFiles
            .filter { ids.contains($0.id) }
            .map(\.path)
            .joined(separator: "\n")
        NSPasteboard.general.prepareForNewContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Drag out

private struct FileDragItem: Transferable {
    let file: VPhoneRemoteFile
    let control: VPhoneGuestControl

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { item in
            guard !item.file.isDirectoryLike else {
                throw CocoaError(.fileNoSuchFile)
            }
            let data = try await item.control.downloadFile(path: item.file.path)
            // A fresh private directory; the name is created in it exclusively.
            let tempDir = try VPhoneHostDownloadDirectory.makeTemporary()
            let tempURL = try tempDir.writeNewFile(named: item.file.name, data: data)
            VPhoneHostDownloadDirectory.markQuarantined(tempURL)
            return SentTransferredFile(tempURL)
        }
    }
}
