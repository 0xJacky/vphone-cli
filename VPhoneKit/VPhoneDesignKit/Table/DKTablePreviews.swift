import SwiftUI

// MARK: - Machines

/// The Launchpad Machines list from `Main.dc.html`, built from `DKTableRow`s.
private struct DKMachinesTablePreview: View {
    @State private var selection: String? = "research-26"

    private let columns = [
        DKTableColumn("Name", width: .flexible(min: 170, weight: 1.5)),
        DKTableColumn("State", width: .flexible(min: 150, weight: 1.2)),
        DKTableColumn("Firmware", width: .flexible(min: 120, weight: 1.1)),
        DKTableColumn("Bundle", width: .fixed(76)),
        DKTableColumn("Resources", width: .flexible(min: 120)),
    ]

    private let rows: [DKTableRow<String>] = [
        DKTableRow(id: "research-26", cells: [
            .title("research-26", subtitle: "iPhone17,3", leading: .glyph(.phone)),
            .status(.success, "Running since 09:41"),
            .title("iOS 26.6.2", subtitle: "23G90", subtitleMonospaced: true, strong: false),
            .mono("2.6.0"),
            .muted("8 CPU · 8 GB · 64 GB"),
        ]),
        DKTableRow(id: "ios27-hooks", cells: [
            .title("ios27-hooks", subtitle: "iPhone17,3", leading: .glyph(.phone)),
            .status(.idle, "Stopped"),
            .title("iOS 27.0", subtitle: "24A435", subtitleMonospaced: true, strong: false),
            DKTableCell.mono("2.5.0").warning("Mixed bundle versions"),
            .muted("6 CPU · 6 GB · 48 GB"),
        ]),
        DKTableRow(id: "ipad-lab", cells: [
            .title("ipad-lab", subtitle: "iPad16,1", leading: .glyph(.ipad)),
            .status(.idle, "Stopped"),
            .title("iPadOS 27.0.1", subtitle: "24A446", subtitleMonospaced: true, strong: false),
            .mono("2.6.0"),
            .muted("8 CPU · 8 GB · 64 GB"),
        ]),
        DKTableRow(id: "pcc-research-2", cells: [
            .title("pcc-research-2", subtitle: "iPhone17,3", leading: .glyph(.phone)),
            .status(.warning, "Creating · Downloading 63%", progress: 0.63),
            .title("iOS 26.6.2", subtitle: "23G90", subtitleMonospaced: true, strong: false),
            .mono("2.6.0"),
            .muted("8 CPU · 8 GB · 64 GB"),
        ]),
    ]

    var body: some View {
        DKDataTable(
            "Machines",
            columns: columns,
            rows: rows,
            selection: $selection,
            roomy: true,
            minWidth: 640,
            emptyText: "No machines in this view.",
        )
        .frame(width: 820, height: 300)
        .background(DK.Palette.page)
    }
}

// MARK: - Patches

/// The grouped patch list from `Patches.dc.html`: a toggle column, group headers,
/// and highlighted rows for patches the guest does not run yet.
private struct DKPatchesTablePreview: View {
    struct Patch: Identifiable {
        var id: String
        var title: String
        var part: String
        var delivery: (String, DKTone)
        var applied: Bool
        var on: Bool
        var gate: String
        var essential = false

        var pending: Bool {
            on != applied
        }

        var status: String {
            if pending {
                return on ? "Not applied · turns on" : "Not applied · turns off"
            }
            return on ? "Applied" : "Off"
        }
    }

    @State private var selection: String? = "kernel-exp-frida_thread_set_state_entitlement_flag"
    @State private var groups: [DKTableGroup<Patch>] = [
        DKTableGroup(title: "Boot Chain", detail: "com.vphone.patchset.bootchain", trailing: "21 patches", rows: [
            Patch(id: "avpbooter-boot-dgst_bypass", title: "AVPBooter digest bypass", part: "AVPBooter", delivery: ("fw patch", .accent), applied: true, on: true, gate: "All", essential: true),
            Patch(id: "txm-cfw-get_task_allow", title: "TXM get-task-allow", part: "TXM", delivery: ("Restore (erases)", .danger), applied: true, on: false, gate: "All"),
        ]),
        DKTableGroup(title: "Kernel Base", detail: "com.vphone.patchset.kernel.base", trailing: "18 patches", rows: [
            Patch(id: "kernel-boot-apfs_root_snapshot", title: "APFS root snapshot", part: "kernelcache", delivery: ("Update Kernel", .info), applied: true, on: true, gate: "All", essential: true),
        ]),
        DKTableGroup(title: "Frida Stalker", detail: "com.vphone.patchset.kernel.frida", trailing: "2 patches", rows: [
            Patch(id: "kernel-exp-frida_thread_set_state_entitlement_flag", title: "thread_set_state entitlement", part: "kernelcache", delivery: ("Update Kernel", .info), applied: false, on: true, gate: "Frida-capable"),
            Patch(id: "kernel-exp-frida_vm_map_delete_immutable_code", title: "Immutable code deletion", part: "kernelcache", delivery: ("Update Kernel", .info), applied: false, on: true, gate: "Frida-capable"),
        ]),
        DKTableGroup(title: "Guest Identity", detail: "com.vphone.patchset.guest.identity", trailing: "4 patches", rows: [
            Patch(id: "dyld-cfw-camera", title: "Camera shared cache symbols", part: "dyld cache", delivery: ("Apply to Guest", .success), applied: true, on: false, gate: "All"),
        ]),
    ]

    private let columns = [
        DKTableColumn("On", width: .fixed(44)),
        DKTableColumn("Patch", width: .flexible(min: 260, weight: 2.4)),
        DKTableColumn("Part", width: .fixed(110)),
        DKTableColumn("Reaches the guest by", width: .fixed(130)),
        DKTableColumn("Status", width: .fixed(170)),
        DKTableColumn("Applies to", width: .fixed(100)),
    ]

    var body: some View {
        DKDataTable(
            "Patches",
            columns: columns,
            groups: groups,
            selection: $selection,
            rowStyle: .plain,
            highlight: { $0.pending ? .warning : nil },
        ) { patch, column in
            switch column {
            case 0:
                Toggle(patch.title, isOn: binding(for: patch.id))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            case 1:
                DKTableCellView(.title(
                    patch.title,
                    subtitle: patch.id,
                    subtitleMonospaced: true,
                    strong: patch.pending,
                ).warning(patch.essential && !patch.on ? "The machine may not boot without this patch." : nil))
            case 2:
                DKTableCellView(.mono(patch.part))
            case 3:
                DKTableCellView(.badge(patch.delivery.1, patch.delivery.0))
            case 4:
                Text(patch.status)
                    .font(patch.pending ? DK.Typeface.captionStrong : DK.Typeface.caption)
                    .foregroundStyle(patch.pending ? DK.Palette.warningInk : patch.on ? DK.Palette.successInk : DK.Palette.muted)
                    .lineLimit(1)
            default:
                DKTableCellView(.muted(patch.gate))
            }
        }
        .frame(width: 860, height: 380)
        .background(DK.Palette.page)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding {
            groups.flatMap(\.rows).first { $0.id == id }?.on ?? false
        } set: { isOn in
            for g in groups.indices {
                if let r = groups[g].rows.firstIndex(where: { $0.id == id }) {
                    groups[g].rows[r].on = isOn
                }
            }
        }
    }
}

// MARK: - System Table

/// The same cells inside SwiftUI's `Table`, the way the Launchpad windows use them.
private struct DKSystemTablePreview: View {
    struct Disk: Identifiable {
        var id: String
        var size: Double
        var used: Double
    }

    private let disks = [
        Disk(id: "research-26", size: 64, used: 38),
        Disk(id: "ios27-hooks", size: 48, used: 46),
        Disk(id: "ipad-lab", size: 64, used: 12),
    ]

    var body: some View {
        Table(disks) {
            TableColumn("Machine") { disk in
                DKTableCellView(.title(disk.id, leading: .glyph(.phone)))
            }
            TableColumn("Disk size") { disk in
                DKTableCellView(.mono("\(Int(disk.size)) GB"))
            }
            .width(90)
            TableColumn("Disk image") { disk in
                DKTableCellView(.bar(disk.used / disk.size, tone: disk.used / disk.size > 0.9 ? .warning : .accent, value: "\(Int(disk.used)) GB"))
            }
            TableColumn("State") { disk in
                DKTableCellView(.badge(disk.used / disk.size > 0.9 ? .warning : .success, disk.used / disk.size > 0.9 ? "Nearly full" : "OK"))
            }
            .width(110)
        }
        .frame(width: 640, height: 180)
    }
}

// MARK: - Previews

#Preview("Machines · Light") {
    DKMachinesTablePreview().preferredColorScheme(.light)
}

#Preview("Machines · Dark") {
    DKMachinesTablePreview().preferredColorScheme(.dark)
}

#Preview("Patches · Light") {
    DKPatchesTablePreview().preferredColorScheme(.light)
}

#Preview("Patches · Dark") {
    DKPatchesTablePreview().preferredColorScheme(.dark)
}

#Preview("System Table cells") {
    DKSystemTablePreview()
}

#Preview("Empty") {
    DKDataTable(
        "Machines",
        columns: [DKTableColumn("Name"), DKTableColumn("State")],
        rows: [DKTableRow<String>](),
        emptyText: "No machines match “ios28”.",
    )
    .frame(width: 400, height: 160)
}

// MARK: - Sorting and multiple selection

private struct DKSortableTablePreview: View {
    @State private var selection: Set<String> = ["vm-2"]
    @State private var order = [DKTableSortDescriptor("name")]

    private let columns = [
        DKTableColumn("Name", width: .flexible(min: 140), sortKey: "name"),
        DKTableColumn("Disk", width: .flexible(min: 160), sortKey: "disk"),
        DKTableColumn("Note", width: .flexible(min: 100)),
    ]

    private let rows: [DKTableRow<String>] = [
        DKTableRow(id: "vm-10", cells: [.title("vm-10"), .bar(0.9, value: "58 GB"), .muted("restored")]),
        DKTableRow(id: "vm-2", cells: [.title("vm-2"), .bar(0.2, value: "13 GB"), .muted("fresh")]),
        DKTableRow(id: "vm-1", cells: [.title("vm-1"), .bar(0.5, value: "32 GB"), .muted("patched")]),
    ]

    var body: some View {
        DKDataTable(
            "Machines",
            columns: columns,
            rows: rows.sorted(by: order, columns: columns),
            selection: $selection,
            sortOrder: $order,
            contextMenu: { row in
                [DKMenuItem("Reveal \(row.id)") {}, DKMenuItem.separator, DKMenuItem("Delete…") {}.destructive()]
            },
        )
        .frame(width: 560, height: 200)
    }
}

#Preview("Sorting and multiple selection") {
    DKSortableTablePreview()
}
