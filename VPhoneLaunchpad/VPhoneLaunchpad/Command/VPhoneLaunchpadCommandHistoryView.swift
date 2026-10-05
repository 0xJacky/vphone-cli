import AppKit
import SwiftUI
import VPhoneDesignKit

/// The commands Launchpad ran, newest first, in a sheet.
struct VPhoneLaunchpadCommandHistoryView: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []

    private var entries: [VPhoneLaunchpadCommandHistory.Entry] {
        model.history.entries.reversed()
    }

    var body: some View {
        VPhoneLaunchpadSheet(Text("Recent Commands")) {
            if entries.isEmpty {
                ContentUnavailableView("Commands that Launchpad runs appear here.", systemImage: "terminal")
            } else {
                table
            }
        } accessory: {
            Button("Copy") { copy(selection) }
                .disabled(selection.isEmpty)
        } actions: {
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(width: 760, height: 460)
    }

    /// The status and time keep fixed widths, so the command gets the rest.
    private var table: some View {
        Table(entries, selection: $selection) {
            TableColumn("") { entry in
                statusIcon(entry)
                    .help(entry.status.map { String(localized: "Exit status \($0)") } ?? "")
            }
            .width(16)
            TableColumn("Started") { entry in
                VPhoneLaunchpadTableCell(.muted(entry.date.formatted(date: .omitted, time: .standard)), verticalPadding: 0)
            }
            .width(64)
            TableColumn("Command") { entry in
                VPhoneLaunchpadTableCell(.mono(entry.text), verticalPadding: 0)
                    .help(entry.text)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button("Copy Command") { copy(ids) }
                .disabled(ids.isEmpty)
        }
        .onCopyCommand {
            let text = commands(selection)
            return text.isEmpty ? [] : [NSItemProvider(object: text as NSString)]
        }
    }

    /// A check for a command that exited with 0, a cross for one that did
    /// not, and the spinner while it runs.
    @ViewBuilder
    private func statusIcon(_ entry: VPhoneLaunchpadCommandHistory.Entry) -> some View {
        switch entry.status {
        case nil:
            VPhoneLaunchpadSpinner()
                .frame(width: 15, height: 15)
        case let status? where status == 0:
            VPhoneLaunchpadTableCell(.icon(.check, tone: .success, label: String(localized: "Exit status \(status)")), verticalPadding: 0)
        case let status?:
            VPhoneLaunchpadTableCell(.icon(.xCircle, tone: .danger, label: String(localized: "Exit status \(status)")), verticalPadding: 0)
        }
    }

    /// The selected commands, one per line, in the order the table shows them.
    private func commands(_ ids: Set<UUID>) -> String {
        entries.filter { ids.contains($0.id) }.map(\.text).joined(separator: "\n")
    }

    private func copy(_ ids: Set<UUID>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commands(ids), forType: .string)
    }
}

