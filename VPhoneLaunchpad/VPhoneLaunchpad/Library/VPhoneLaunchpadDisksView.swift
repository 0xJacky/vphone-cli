import AppKit
import SwiftUI
import VPhoneDesignKit

/// The Disks page. Space used by machines, restore files and the IPSW cache in each library folder.
///
/// Only the library folders Launchpad lists (the default one and the folders
/// added in New Machine) and the IPSW cache are measured, by what their files
/// take on the volume. A disk image is sparse, so its usage bar is what the
/// guest has written against the size the guest sees.
struct VPhoneLaunchpadDisksView: View {
    @Environment(VPhoneLaunchpadModel.self) private var model
    @State private var scan: VPhoneLaunchpadLibraryScan?

    var body: some View {
        VPhoneLaunchpadDisksPage(
            subtitle: subtitle,
            summary: scan.map(summary),
            rows: scan.map(rows) ?? [],
            onShowLibrary: showLibrary,
            onOpenFirmwares: { model.show(.firmwares) },
        )
        .task(id: VPhoneLaunchpadLibraryScanKey.key(library)) { await rescan() }
    }

    private var library: VPhoneLaunchpadMachineLibrary {
        model.machines
    }

    private var subtitle: String {
        let roots = library.roots
        let count = library.machines.count
        let machines = count == 1 ? String(localized: "1 machine") : String(localized: "\(count) machines")
        let place = roots.count == 1
            ? VPhoneLaunchpadLibraryFormat.abbreviated(roots[0])
            : String(localized: "\(roots.count) library folders")
        return "\(place) · \(machines)"
    }

    private func rescan() async {
        #if DEBUG
            if VPhoneLaunchpadPreview.isActive {
                scan = VPhoneLaunchpadPreview.libraryScan
                return
            }
        #endif
        guard library.hasListed else {
            return
        }
        let folders = library.machines.map { VPhoneLaunchpadLibraryScanner.MachineFolder(libraryRoot: $0.libraryRoot, name: $0.name) }
        do {
            scan = try await VPhoneLaunchpadLibraryScanner.scan(libraryRoots: library.roots, machines: folders)
        } catch {
            // Cancelled: the page went away or the machines changed again.
        }
    }

    // MARK: - Rows

    private func rows(_ scan: VPhoneLaunchpadLibraryScan) -> [VPhoneLaunchpadDiskRow] {
        let spans = library.spansLibraries
        return library.machines.map { machine in
            let measured = scan.machines.first { $0.libraryRoot == machine.libraryRoot && $0.name == machine.name }
            return VPhoneLaunchpadDiskRow(
                id: "\(machine.libraryRoot)/\(machine.name)",
                name: machine.name,
                library: spans ? VPhoneLaunchpadLibraryFormat.abbreviated(machine.libraryRoot) : nil,
                state: library.stateTone(machine.path),
                // What `vm new --disk-size` asked for; the file's own size when unlisted.
                diskSize: machine.diskSizeBytes > 0 ? machine.diskSizeBytes : measured?.diskImageSize,
                diskAllocated: measured?.diskImageAllocated,
                restoreAllocated: measured?.restoreAllocated ?? 0,
                totalAllocated: measured?.totalAllocated ?? 0,
            )
        }
    }

    private func summary(_ scan: VPhoneLaunchpadLibraryScan) -> VPhoneLaunchpadDiskSummary {
        let roots = library.roots
        let caption = roots.count == 1
            ? String(localized: "Used by \(VPhoneLaunchpadLibraryFormat.abbreviated(roots[0])) and the IPSW cache")
            : String(localized: "Used by \(roots.count) library folders and the IPSW cache")
        let removable = scan.machines.filter { measured in
            guard measured.restoreAllocated > 0 else {
                return false
            }
            let path = VPhoneLaunchpadMachinePath(libraryRoot: measured.libraryRoot, name: measured.name)
            return library.creations[path] == nil && library.state(of: path) == .stopped
        }
        return VPhoneLaunchpadDiskSummary(
            usedCaption: caption,
            machineDisks: scan.machines.reduce(0) { $0 + ($1.diskImageAllocated ?? 0) },
            restoreFiles: scan.machines.reduce(0) { $0 + $1.restoreAllocated },
            otherMachineFiles: scan.machines.reduce(0) { $0 + $1.otherAllocated },
            ipswCache: scan.cacheAllocated,
            volumes: scan.volumes.map { volume in
                VPhoneLaunchpadDiskSummary.Volume(
                    name: volume.name,
                    available: volume.available,
                    isLow: volume.available.map { $0 < VPhoneLaunchpadDiskSummary.recommendedFree } ?? false,
                )
            },
            removableRestoreFiles: removable.map { "\($0.name) (\(VPhoneLaunchpadLibraryFormat.size($0.restoreAllocated)))" },
            ipswCount: scan.completeIPSWs.count,
        )
    }

    // MARK: - Finder

    private func showLibrary() {
        let folders = library.roots
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .filter(VPhoneLaunchpadLibraryScanner.isDirectory)
        guard !folders.isEmpty else {
            reveal(URL(fileURLWithPath: library.libraryRoot, isDirectory: true))
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(folders)
    }

    private func reveal(_ url: URL) {
        let shown = VPhoneLaunchpadLibraryScanner.isDirectory(url) ? url : VPhoneLaunchpadLibraryScanner.existingAncestor(of: url)
        NSWorkspace.shared.activateFileViewerSelecting([shown])
    }
}

// MARK: - Machine state

extension VPhoneLaunchpadMachineLibrary {
    /// The status dot of a machine on the Library pages, as the Machines list
    /// colors its state: running green, busy or being created amber, a
    /// panicked guest red, stopped grey.
    func stateTone(_ machine: VPhoneLaunchpadMachinePath) -> DKTone {
        switch state(of: machine) {
        case .running: panicked.contains(machine) ? .danger : .success
        case .busy: .warning
        case .stopped: .idle
        }
    }
}
