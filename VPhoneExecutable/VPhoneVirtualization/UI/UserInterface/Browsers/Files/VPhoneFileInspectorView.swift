import SwiftUI
import VPhoneDesignKit

/// The Files page's inspector: the selected item's icon, name, kind and facts,
/// its full path, and the Open, Download, Rename and Delete actions. With no
/// selection it describes the folder on show; with several, the selection as a
/// whole. `compact` is the one-row form shown under the table when the page is
/// too narrow for a side column.
struct VPhoneFileInspectorView: View {
    let model: VPhoneFileBrowserModel
    let compact: Bool
    let open: (VPhoneRemoteFile) -> Void
    let download: () -> Void
    let rename: (VPhoneRemoteFile) -> Void
    let delete: () -> Void

    var body: some View {
        let summary = Summary(model: model)
        if compact {
            compactBody(summary)
        } else {
            fullBody(summary)
        }
    }

    // MARK: - Side Column

    private func fullBody(_ summary: Summary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DK.Space.s4) {
                VStack(spacing: 10) {
                    DKFileIcon(summary.kind, size: 48)
                        .frame(width: 84, height: 84)
                        .background(DK.Palette.accentTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(spacing: 0) {
                        Text(summary.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DK.Palette.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .textSelection(.enabled)
                        Text(summary.subtitle)
                            .font(DK.Typeface.caption)
                            .foregroundStyle(DK.Palette.muted)
                    }
                }
                .frame(maxWidth: .infinity)

                if !summary.facts.isEmpty {
                    DKSection(rows: summary.facts)
                }

                Text(summary.path)
                    .font(DK.Typeface.mono)
                    .foregroundStyle(DK.Palette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, DK.Space.s2)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DK.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DK.Radius.row, style: .continuous))
                    .accessibilityLabel(VPhoneLocalization.format("Path %@", summary.path))

                if summary.hasSelection {
                    Grid(horizontalSpacing: DK.Space.s2, verticalSpacing: DK.Space.s2) {
                        GridRow {
                            actionButton(.open, summary: summary)
                            actionButton(.download, summary: summary)
                        }
                        GridRow {
                            actionButton(.rename, summary: summary)
                            actionButton(.delete, summary: summary)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(VPhoneLocalization.text("Selection actions"))
                } else {
                    Text(VPhoneLocalization.text("Select an item to open, download, rename or delete it. Double-click a folder to open it."))
                        .font(DK.Typeface.caption)
                        .foregroundStyle(DK.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, DK.Space.s5)
            .padding(.horizontal, DK.Space.s4)
        }
        .background(DK.Palette.window)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(VPhoneLocalization.text("Selection"))
    }

    // MARK: - Under the Table

    private func compactBody(_ summary: Summary) -> some View {
        HStack(spacing: DK.Space.s3) {
            DKFileIcon(summary.kind, size: 26)
                .frame(width: 40, height: 40)
                .background(DK.Palette.accentTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(DK.Typeface.bodyStrong)
                    .foregroundStyle(DK.Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(([summary.subtitle] + summary.facts.prefix(2).map(\.value)).joined(separator: " · "))
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .help(summary.path)
            Spacer(minLength: DK.Space.s2)
            if summary.hasSelection {
                HStack(spacing: 6) {
                    ForEach(Action.allCases, id: \.self) { action in
                        DKButton(spec(action, summary: summary, size: .icon))
                    }
                }
            }
        }
        .padding(.vertical, DK.Space.s3)
        .padding(.horizontal, DK.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DK.Palette.window)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(VPhoneLocalization.text("Selection"))
    }

    // MARK: - Actions

    private enum Action: CaseIterable {
        case open, download, rename, delete
    }

    private func spec(_ action: Action, summary: Summary, size: DKButtonSize = .regular) -> DKButtonSpec {
        let single = summary.single
        return switch action {
        case .open:
            DKButtonSpec(
                VPhoneLocalization.text("Open"),
                glyph: .right,
                variant: .primary,
                size: size,
                isEnabled: single != nil,
                help: single.map { $0.isDirectoryLike
                    ? VPhoneLocalization.text("Open this folder")
                    : VPhoneLocalization.text("Preview with Quick Look (Space)")
                },
            ) {
                if let single { open(single) }
            }
        case .download:
            DKButtonSpec(
                VPhoneLocalization.text("Download"),
                glyph: .download,
                size: size,
                help: VPhoneLocalization.text("Download the selection to a folder on this Mac"),
                action: download,
            )
        case .rename:
            DKButtonSpec(
                VPhoneLocalization.text("Rename"),
                glyph: .pencil,
                size: size,
                isEnabled: single != nil,
            ) {
                if let single { rename(single) }
            }
        case .delete:
            DKButtonSpec(
                VPhoneLocalization.text("Delete"),
                glyph: .trash,
                variant: .danger,
                size: size,
                help: VPhoneLocalization.text("Delete the selection from the guest"),
                action: delete,
            )
        }
    }

    /// A button that fills its grid cell, so the 2×2 grid's columns are even.
    private func actionButton(_ action: Action, summary: Summary) -> some View {
        let spec = spec(action, summary: summary)
        return Button(action: spec.action) {
            HStack(spacing: 6) {
                if let glyph = spec.glyph {
                    DKIcon(glyph, size: 14)
                }
                Text(spec.label)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(DKButtonStyle(variant: spec.variant))
        .disabled(!spec.isEnabled)
        .help(spec.help ?? "")
        .accessibilityLabel(spec.label)
    }

    // MARK: - Summary

    /// What the inspector says about the selection, or about the folder on show.
    private struct Summary {
        let kind: DKFileKind
        let title: String
        let subtitle: String
        let facts: [DKKeyValue]
        let path: String
        let hasSelection: Bool
        let single: VPhoneRemoteFile?

        @MainActor
        init(model: VPhoneFileBrowserModel) {
            let selected = model.selectedFiles
            hasSelection = !selected.isEmpty
            single = selected.count == 1 ? selected[0] : nil

            if let file = single {
                kind = file.kind
                title = file.name
                subtitle = file.kindDescription
                path = file.path
                var facts: [DKKeyValue] = []
                if !file.isDirectoryLike, !file.isSymbolicLink {
                    facts.append(DKKeyValue(VPhoneLocalization.text("Size"), file.displaySize))
                }
                facts.append(DKKeyValue(VPhoneLocalization.text("Modified"), file.displayDate))
                facts.append(DKKeyValue(
                    VPhoneLocalization.text("Permissions"),
                    "\(file.symbolicPermissions) (\(file.permissions))",
                    monospaced: true,
                ))
                if let resolved = file.resolvedPath, resolved != file.path {
                    facts.append(DKKeyValue(VPhoneLocalization.text("Resolves To"), resolved, monospaced: true))
                }
                self.facts = facts
            } else if hasSelection {
                let folders = selected.filter(\.isDirectoryLike).count
                let files = selected.count - folders
                kind = files == 0 ? .folder : .document(nil)
                title = VPhoneLocalization.format("%@ items", String(selected.count))
                subtitle = [
                    folders == 0 ? nil : folders == 1
                        ? VPhoneLocalization.text("1 folder") : VPhoneLocalization.format("%@ folders", String(folders)),
                    files == 0 ? nil : files == 1
                        ? VPhoneLocalization.text("1 file") : VPhoneLocalization.format("%@ files", String(files)),
                ].compactMap(\.self).joined(separator: ", ")
                path = model.currentPath
                let bytes = selected
                    .filter { !$0.isDirectoryLike && !$0.isSymbolicLink }
                    .reduce(Int64(0)) { $0 + Int64(clamping: $1.size) }
                facts = files == 0 ? [] : [DKKeyValue(
                    VPhoneLocalization.text("Size of Files"),
                    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file),
                )]
            } else {
                let name = (model.currentPath as NSString).lastPathComponent
                kind = .folder
                title = name.isEmpty ? "/" : name
                subtitle = VPhoneLocalization.text("Folder")
                path = model.currentPath
                let count = model.files.count
                facts = [DKKeyValue(
                    VPhoneLocalization.text("Items"),
                    count == 1 ? VPhoneLocalization.text("1 item") : VPhoneLocalization.format("%@ items", String(count)),
                )]
            }
        }
    }
}
