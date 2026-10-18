import ArgumentParser
import Foundation
import VPhoneCoreKit

// MARK: - Shared

/// Requests to a running VM's `vphone.sock` for the in-place freezing
/// commands. Each prints the VM's answer and fails when it refuses.
private enum VPhoneVirtualMachineStateControl {
    static func send(_ request: [String: Any], to bundle: VPhoneBundle, timeout: Int) throws -> [String: Any] {
        let socketPath = bundle.url.appendingPathComponent("vphone.sock").path
        guard let reply = VPhoneHostAutomationProbe.send(request, socketPath: socketPath, timeout: timeout) else {
            throw ValidationError("\(bundle.name) is not running, or its control socket does not answer. Start it with vm launch.")
        }
        return reply
    }

    static func printJSON(_ object: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func describeSupport(_ support: [String: Any]) -> [String] {
        if support["supported"] as? Bool == true {
            return ["save/restore: supported"]
        }
        var lines = ["save/restore: NOT supported (\(support["error"] as? String ?? "unknown"))"]
        for blocker in support["blockers"] as? [[String: Any]] ?? [] {
            lines.append("  blocked by: \(blocker["device"] as? String ?? "?") - \(blocker["message"] as? String ?? "")")
        }
        if let remainder = support["remainder"] as? String {
            lines.append("  blocked without any checked device: \(remainder)")
        }
        return lines
    }

    static func absolute(_ path: String) -> URL {
        URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
            .standardizedFileURL
    }
}

// MARK: - pause / resume

struct VPhoneVirtualMachinePauseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pause",
        abstract: "Pause a running VM in place (its memory stays allocated)",
        discussion: """
        The guest stops executing until vm resume. Its memory is not given back to the Mac; \
        to free it, use vm save-state, which saves the paused state and stops the VM.
        """,
    )

    @OptionGroup var lib: VPhoneLibraryOption
    @Argument(help: "VM name") var name: String?
    @Flag(name: .shortAndLong, help: "Emit JSON") var json = false

    func run() throws {
        let name = try VPhoneVirtualMachineSelection.resolveExisting(name, in: lib.library)
        let reply = try VPhoneVirtualMachineStateControl.send(["t": "pause"], to: lib.library.bundle(named: name), timeout: 60)
        guard reply["ok"] as? Bool == true else {
            throw ValidationError(reply["error"] as? String ?? "the VM refused to pause")
        }
        if json {
            try VPhoneVirtualMachineStateControl.printJSON(reply["result"] ?? [:])
        } else {
            print("\(name): paused")
        }
    }
}

struct VPhoneVirtualMachineResumeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Resume a VM paused with vm pause",
    )

    @OptionGroup var lib: VPhoneLibraryOption
    @Argument(help: "VM name") var name: String?
    @Flag(name: .shortAndLong, help: "Emit JSON") var json = false

    func run() throws {
        let name = try VPhoneVirtualMachineSelection.resolveExisting(name, in: lib.library)
        let reply = try VPhoneVirtualMachineStateControl.send(["t": "resume"], to: lib.library.bundle(named: name), timeout: 60)
        guard reply["ok"] as? Bool == true else {
            throw ValidationError(reply["error"] as? String ?? "the VM refused to resume")
        }
        if json {
            try VPhoneVirtualMachineStateControl.printJSON(reply["result"] ?? [:])
        } else {
            print("\(name): running")
        }
    }
}

// MARK: - save-state

struct VPhoneVirtualMachineSaveStateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "save-state",
        abstract: "Save a running VM's memory and device state, then stop it (same-Mac restore only)",
        discussion: """
        Pauses the VM, has Virtualization save its state into a new directory (default: \
        SavedState/ in the machine folder), then by default stops the VM so its memory goes back \
        to the Mac. vm restore-state resumes it later.

        Virtualization ties the saved file to the Mac that wrote it: it cannot be restored on \
        another Mac, and may be refused after a macOS update, in which case vm restore-state boots \
        the guest cold. A state is good for one restore; booting the machine any other way marks \
        the default one as used.

        Before saving, Virtualization's validateSaveRestoreSupport() must accept the configuration. \
        When it does not, this command names each device that blocks it. --check only does that.
        """,
    )

    @OptionGroup var lib: VPhoneLibraryOption
    @Argument(help: "VM name") var name: String?
    @Argument(help: "Directory to create (default: <machine>/SavedState)") var path: String?
    @Option(name: .customLong("then"), help: "After saving: stop (default) | pause | resume") var followUp: String = "stop"
    @Flag(help: "Replace an existing saved state at the path") var replace = false
    @Flag(help: "Only report whether the VM's configuration can be saved, and what blocks it") var check = false
    @Flag(help: "PoC only: save even though validateSaveRestoreSupport() refuses the configuration")
    var ignoreValidation = false
    @Option(help: "Seconds to wait for the save") var timeout: Int = 900
    @Flag(name: .shortAndLong, help: "Emit JSON") var json = false

    func validate() throws {
        guard ["stop", "pause", "resume"].contains(followUp) else {
            throw ValidationError("--then must be stop, pause or resume.")
        }
    }

    func run() throws {
        let name = try VPhoneVirtualMachineSelection.resolveExisting(name, in: lib.library)
        let bundle = try lib.library.bundle(named: name)

        if check {
            let reply = try VPhoneVirtualMachineStateControl.send(["t": "vmstate", "check": true], to: bundle, timeout: 60)
            guard reply["ok"] as? Bool == true, let result = reply["result"] as? [String: Any] else {
                throw ValidationError(reply["error"] as? String ?? "the VM refused the request")
            }
            let support = result["save_restore"] as? [String: Any] ?? [:]
            if json {
                try VPhoneVirtualMachineStateControl.printJSON(result)
            } else {
                print("state: \(result["state"] as? String ?? "?")")
                VPhoneVirtualMachineStateControl.describeSupport(support).forEach { print($0) }
            }
            if support["supported"] as? Bool != true {
                throw ExitCode(2)
            }
            return
        }

        let directory = path.map(VPhoneVirtualMachineStateControl.absolute)
            ?? VPhoneSavedMachineState.defaultDirectory(of: bundle.url)
        let request: [String: Any] = [
            "t": "save-state",
            "path": directory.path,
            "after": followUp,
            "replace": replace,
            "ignore_validation": ignoreValidation,
        ]
        let reply = try VPhoneVirtualMachineStateControl.send(request, to: bundle, timeout: timeout)
        guard reply["ok"] as? Bool == true, let result = reply["result"] as? [String: Any] else {
            if let support = (reply["result"] as? [String: Any])?["save_restore"] as? [String: Any] {
                if json {
                    try VPhoneVirtualMachineStateControl.printJSON(reply)
                } else {
                    VPhoneVirtualMachineStateControl.describeSupport(support).forEach { print($0) }
                }
            }
            throw ValidationError(reply["error"] as? String ?? "the VM refused to save its state")
        }

        if followUp == "stop" {
            // vphone-vm exits a moment after replying.
            var waited = 0.0
            while !VPhoneGuestProcesses.virtualMachinePIDs(config: bundle.configURL).isEmpty, waited < 30 {
                Thread.sleep(forTimeInterval: 0.25)
                waited += 0.25
            }
        }
        if json {
            try VPhoneVirtualMachineStateControl.printJSON(result)
        } else {
            let bytes = (result["bytes"] as? NSNumber)?.int64Value ?? 0
            print("\(name): saved \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) to \(directory.path)")
            print(String(
                format: "pause %.2f s, save %.2f s, %@ %.2f s",
                (result["pause_seconds"] as? NSNumber)?.doubleValue ?? 0,
                (result["save_seconds"] as? NSNumber)?.doubleValue ?? 0,
                followUp,
                (result["after_seconds"] as? NSNumber)?.doubleValue ?? 0,
            ))
            if followUp == "stop" {
                print("\(name): stopped; resume it on this Mac with vm restore-state \(name)\(path == nil ? "" : " \(directory.path)")")
            }
        }
    }
}

// MARK: - restore-state

struct VPhoneVirtualMachineRestoreStateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore-state",
        abstract: "Start a VM from a state saved by vm save-state (falls back to a cold boot)",
        discussion: """
        Launches the VM as vm launch does, but resumes the saved memory instead of booting. \
        vphone first checks the saved state belongs to this machine (machine identifier and \
        hardware model), this Mac, this configuration and, for a disk file, this exact disk \
        image; Virtualization then checks it again. If either refuses, the guest boots cold \
        instead, unless --no-cold-boot-fallback is given. A resumed state is marked used.
        """,
    )

    @OptionGroup var lib: VPhoneLibraryOption
    @Argument(help: "VM name") var name: String?
    @Argument(help: "Saved state directory (default: <machine>/SavedState)") var path: String?
    @Flag(name: .customLong("headless"), help: "Boot without a VM window or menu bar") var headless = false
    @Option(help: "Expose the guest HTTP/WebSocket API on host:port (for example 127.0.0.1:8765)")
    var apiListen: String?
    @Option(help: "Kernel GDB debug stub port on host (omit for system-assigned; valid: 6000...65535)")
    var kernelDebugPort: Int?
    @Flag(inversion: .prefixedNo, help: "Boot cold when the saved state cannot be used") var coldBootFallback = true
    @Flag(help: "PoC only: let Virtualization try a state saved on another Mac (it refuses)")
    var restoreFromOtherHost = false
    @Option(name: .shortAndLong, help: "Resource base override (default: inferred from the running binary path)")
    var projectRoot: String?
    @Flag(name: .customShort("v"), help: "Increase verbosity: -v tool detail, -vv guest serial, -vvv internal trace")
    var verboseCount: Int

    func run() throws {
        let name = try VPhoneVirtualMachineSelection.resolveExisting(name, in: lib.library)
        let bundle = try lib.library.bundle(named: name)
        let directory = path.map(VPhoneVirtualMachineStateControl.absolute)
            ?? VPhoneSavedMachineState.defaultDirectory(of: bundle.url)
        if !VPhoneSavedMachineState.hasUsableState(in: directory) {
            let reason = "\(directory.path) holds no unused saved state"
            guard coldBootFallback else { throw ValidationError(reason) }
            FileHandle.standardError.write(Data("warning: \(reason); vphone-vm will boot \(name) cold\n".utf8))
        }
        try VPhoneVirtualMachineLaunchCommand.launch(
            name: name,
            library: lib.library,
            dfu: false,
            headless: headless,
            apiListen: apiListen,
            kernelDebugPort: kernelDebugPort,
            projectRoot: projectRoot,
            verboseCount: verboseCount,
            restore: (directory, coldBootFallback, restoreFromOtherHost),
        )
    }
}

// MARK: - storage

/// The machine's disk (file or NBD) and where its identity-bearing state lives.
struct VPhoneVirtualMachineStorageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "storage",
        abstract: "Show or change a VM's disk (file or nbd://) and state layout",
        discussion: """
        Without options, shows where the machine's disk and state live.

        --disk nbd://host[:port]/export attaches the disk from a Network Block Device server \
        (Virtualization's NBD client, macOS 14+). TLS (nbds://) is not supported by that client: \
        serve the export on a trusted link. --nbd-timeout sets how long the client waits on the \
        connection before it reconnects (default 5 s; reconnects are invisible to the guest, its \
        I/O stalls meanwhile). If the client gives up for good, vphone-vm stops the VM. \
        --disk Disk.img goes back to the file in the machine folder, which switching to NBD \
        leaves in place untouched. An NBD machine cannot be cloned, snapshotted, rebased, \
        exported or trimmed by vphone: do that on the storage side.

        --state-dir on moves nvram.bin and SEPStorage into MachineState/ and records the machine \
        identity (machine identifier, MAC, hardware model) there in identity.plist, so that one \
        directory holds what must follow the machine to another Mac for a cold start. vphone \
        builds from before this layout refuse to load such a machine. --state-dir off moves them \
        back. The machine must be stopped for either change.
        """,
    )

    @OptionGroup var lib: VPhoneLibraryOption
    @Argument(help: "VM name") var name: String?
    @Option(help: "Disk: a file name in the machine folder (Disk.img) or nbd://host[:port]/export") var disk: String?
    @Option(help: "NBD connection timeout in seconds before reconnecting (1-600)") var nbdTimeout: Double?
    @Option(help: "NBD flush handling: full (default) | none") var nbdSync: String?
    @Option(help: "Keep NVRAM, SEP storage and identity in MachineState/: on | off") var stateDir: String?
    @Flag(name: .shortAndLong, help: "Emit JSON") var json = false

    func validate() throws {
        if let stateDir, stateDir != "on", stateDir != "off" {
            throw ValidationError("--state-dir must be on or off.")
        }
        if let nbdSync, VPhoneVirtualMachineManifest.NBDOptions.Synchronization(rawValue: nbdSync) == nil {
            throw ValidationError("--nbd-sync must be full or none.")
        }
        if let disk {
            _ = try VPhoneDiskLocation(manifestValue: disk)
        }
        try VPhoneVirtualMachineManifest.NBDOptions(timeoutSeconds: nbdTimeout).validate()
    }

    func run() throws {
        let name = try VPhoneVirtualMachineSelection.resolveExisting(name, in: lib.library)
        var bundle = try lib.library.bundle(named: name)

        if disk != nil || nbdTimeout != nil || nbdSync != nil {
            try VPhoneBundleActivity.requireStopped(bundle)
            let location = try disk.map(VPhoneDiskLocation.init(manifestValue:)) ?? bundle.manifest.diskLocation
            if case let .file(fileName) = location,
               VPhoneVirtualMachineManifest.fileKind(at: bundle.url.appendingPathComponent(fileName)) != .regularFile
            {
                throw ValidationError("\(bundle.url.appendingPathComponent(fileName).path) is not a disk image file in the machine folder.")
            }
            let nbd: VPhoneVirtualMachineManifest.NBDOptions? = switch location {
            case .file:
                nil
            case .networkBlockDevice:
                VPhoneVirtualMachineManifest.NBDOptions(
                    timeoutSeconds: nbdTimeout ?? bundle.manifest.nbd?.timeoutSeconds,
                    synchronization: nbdSync.flatMap(VPhoneVirtualMachineManifest.NBDOptions.Synchronization.init(rawValue:))
                        ?? bundle.manifest.nbd?.synchronization,
                )
            }
            let wasFile = bundle.manifest.diskLocation.fileName
            let updated = bundle.manifest.updating(diskImage: location.manifestValue, nbd: .some(nbd))
            try updated.write(to: bundle.configURL)
            try VPhoneHostFilePermissions.makeAccessible(at: bundle.configURL)
            bundle = VPhoneBundle(url: bundle.url, manifest: updated)
            if location.isNetwork, let wasFile,
               VPhoneVirtualMachineManifest.fileKind(at: bundle.url.appendingPathComponent(wasFile)) == .regularFile
            {
                FileHandle.standardError.write(Data(
                    "note: \(wasFile) stays in the machine folder and is no longer used. Do not boot it while the NBD export is in use elsewhere.\n".utf8,
                ))
            }
        }

        switch stateDir {
        case "on": bundle = try VPhoneMachineStateLayout.moveToStateDirectory(bundle)
        case "off": bundle = try VPhoneMachineStateLayout.moveToLegacyLayout(bundle)
        default: break
        }

        let report = Self.report(of: bundle)
        if json {
            try VPhoneVirtualMachineStateControl.printJSON(report)
            return
        }
        print("disk:        \(report["disk"] as? String ?? "?")")
        if let nbd = report["nbd"] as? [String: Any] {
            print("nbd:         timeout \(nbd["timeout_seconds"] ?? "?") s, sync \(nbd["synchronization"] ?? "?"), TLS not supported")
        }
        print("layout:      \(report["state_layout"] as? String ?? "?")")
        print("nvram:       \(report["nvram"] as? String ?? "?")")
        print("sep storage: \(report["sep_storage"] as? String ?? "?")")
        if let identity = report["identity"] as? [String: Any] {
            print("identity:    ECID \(identity["ecid"] ?? "-"), MAC \(identity["mac"] ?? "-"), hardware model \(identity["hardware_model_recorded"] as? Bool == true ? "recorded" : "not yet recorded")")
        }
        if let problem = report["problem"] as? String {
            print("problem:     \(problem)")
        }
        print("saved state: \(report["saved_state"] as? String ?? "none")")
    }

    static func report(of bundle: VPhoneBundle) -> [String: Any] {
        var report: [String: Any] = [
            "disk": bundle.manifest.diskLocation.manifestValue,
            "state_layout": VPhoneMachineStateLayout.kind(of: bundle.manifest)?.rawValue ?? "mixed",
            "nvram": bundle.url.appendingPathComponent(bundle.manifest.nvramStorage).path,
            "sep_storage": bundle.url.appendingPathComponent(bundle.manifest.sepStorage).path,
        ]
        if bundle.manifest.diskLocation.isNetwork {
            let nbd = bundle.manifest.nbd ?? .init()
            report["nbd"] = [
                "timeout_seconds": nbd.effectiveTimeout,
                "synchronization": nbd.effectiveSynchronization.rawValue,
                "tls": false,
            ]
        }
        if VPhoneMachineStateLayout.kind(of: bundle.manifest) == .stateDirectory {
            report["state_directory"] = VPhoneMachineStateLayout.directory(of: bundle).path
            do {
                if let record = try VPhoneMachineIdentityRecord.load(from: VPhoneMachineStateLayout.identityURL(of: bundle)) {
                    report["identity"] = [
                        "ecid": record.ecid ?? "",
                        "udid": record.udid ?? "",
                        "mac": record.macAddress,
                        "hardware_model_recorded": !record.hardwareModel.isEmpty,
                        "matches_config": record.machineIdentifier == bundle.manifest.machineIdentifier,
                    ]
                }
            } catch {
                report["problem"] = "\(error)"
            }
        }
        if report["problem"] == nil {
            do {
                try VPhoneMachineStateLayout.requireLaunchable(bundle)
            } catch {
                report["problem"] = "\(error)"
            }
        }
        let saved = VPhoneSavedMachineState.defaultDirectory(of: bundle.url)
        if let binding = try? VPhoneSavedStateBinding.load(from: VPhoneSavedMachineState.bindingFile(in: saved)) {
            report["saved_state"] = binding.invalidated.map { "used (\($0.reason))" }
                ?? "\(saved.path), saved \(binding.saved) on \(binding.hostName)"
        }
        return report
    }
}
