import AppKit
import SwiftUI
import VPhoneDesignKit

/// The folders Launchpad lists machines from: the default library, and the
/// folders added since.
struct VPhoneLaunchpadLibrarySettings: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var addError: VPhoneLaunchpadError?

    private var library: VPhoneLaunchpadMachineLibrary {
        model.machines
    }

    var body: some View {
        VPhoneLaunchpadSettingsPage {
            DKSection(
                String(localized: "Machine Folders"),
                footnote: String(localized: "Launchpad lists the machines in every folder here. New Machine adds the folder it creates in. An added folder is forgotten once it holds no machine; nothing on disk is deleted."),
            ) {
                ForEach(library.roots, id: \.self) { root in
                    DKListRow(item(for: root))
                }
                HStack {
                    DKButton(String(localized: "Add Folder…"), glyph: .folderPlus, size: .small) {
                        chooseFolder()
                    }
                    .disabled(library.globalActivity != nil)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            DKSection(
                String(localized: "New Machines"),
                footnote: String(localized: "New Machine offers the folder last created in while it is mounted and usable, else the default library."),
            ) {
                DKFormRow(String(localized: "Create in"), fill: true) {
                    Text(Self.shown(library.preferredRoot))
                        .font(DK.Typeface.mono)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(library.preferredRoot)
                }
            }
        }
        .errorAlert($addError)
    }

    private func item(for root: String) -> DKListItem {
        let isDefault = root == library.libraryRoot
        let isAvailable = VPhoneLaunchpadMachineLocations.isAvailable(root)
        let detail = VPhoneLaunchpadLibrarySettingsText.folderDetail(
            isDefault: isDefault,
            isAvailable: isAvailable,
            machines: library.machines.count(where: { $0.libraryRoot == root }),
            freeBytes: isAvailable || isDefault ? Self.freeSpace(root) : nil,
        )
        return DKListItem(
            Self.shown(root),
            monospacedTitle: true,
            badges: isDefault ? [DKListItem.Badge(String(localized: "Default"))] : [],
            lines: [DKListItem.Line(detail)],
            id: root,
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Add Machine Folder")
        panel.message = String(localized: "Choose a folder that holds machines.")
        panel.prompt = String(localized: "Add")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.present { url in
            let root = VPhoneLaunchpadMachineLocations.canonical(url)
            if let problem = VPhoneLaunchpadMachineLocations.problem(with: root) {
                addError = VPhoneLaunchpadError(String(localized: "Unable to Add Folder"), detail: problem)
            } else {
                library.addLocation(root)
            }
        }
    }

    static func shown(_ root: String) -> String {
        VPhoneLaunchpadHostSetup.abbreviated(URL(fileURLWithPath: root, isDirectory: true))
    }

    /// Free space on the volume holding `root`.
    private static func freeSpace(_ root: String) -> Int64? {
        let url = VPhoneLaunchpadHostSetup.existingAncestor(of: URL(fileURLWithPath: root, isDirectory: true))
        guard let bytes = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        else {
            return nil
        }
        return bytes
    }
}
