import ArgumentParser
import FirmwarePatcher
import Foundation
import VPhoneCoreKit
import VPhonePatchKit

struct VPhoneVirtualMachineCreateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a VM end-to-end (prepare → patch → restore → CFW → first boot)",
        discussion: """
        Runs the full custom-firmware pipeline for a new VM. Requires an internet connection \
        to download IPSWs, a macOS host that is not itself a VM, and sudo to install custom \
        firmware.

        By default the pipeline builds a template instead of the VM: a machine in \
        <library>/.templates that never boots, keyed by the guest device, the iOS and cloudOS \
        builds, the preset and the disk size. The VM is then cloned from it with a new identity, \
        and every later create with the same key clones from the same template in a fraction \
        of a second, without root, an IPSW download or a restore, sharing every unchanged block \
        on disk. Such machines share the template's SEP root secret and Data volume keys; \
        --no-template builds the VM on its own, with keys of its own, as before. \
        --template <id> clones from a template listed by vm template list.

        After cfw install a new template's System volume is trimmed offline (--trim, standard \
        by default; vm template trim describes the tiers). It then boots once before it is \
        frozen (its setup boot): the orig-fs snapshot is deleted, which frees what the trim \
        removed, Setup Assistant skipped, first-boot work waited for, the default system apps \
        removed (App Store, Home, TV, News, FaceTime, iTunes Store, Messages, Games, Find My, \
        Wallet; never Phone or Camera) and the trimmed service profile applied, then it reboots, \
        is checked and shut down. Every clone starts at the Lock Screen with that state. \
        --slim off trims nothing and keeps every app and service (Setup is still skipped); \
        --trim, --keep-languages, --service-profile, --remove-apps, --keep-apps and \
        --accounts-off pick parts. Each choice is part of the key, so templates with different \
        slimming live side by side. A template never keeps the restore tree: --keep-artifacts \
        keeps it only with --no-template.

        --cpu, --memory, --network and --unlock-at-startup are set on the new VM, whichever way \
        it is made.

        --remote-disk nbd://host:port/export --from-manifest <config.plist> makes a machine whose \
        disk is that NBD export and whose state lives in a MachineState/ mounted beforehand (a Mac \
        fleet's storage-backed machine): the folder <library>/<name>/ must already exist and hold \
        only MachineState, with the template's nvram.bin and SEPStorage in it. The machine is \
        completed around them from the template's config.plist, with a new identity and this \
        bundle's ROMs, as a clone from a template is; nothing is copied, downloaded or booted. \
        --nbd-timeout (default and minimum 60 s) is how long the NBD client waits out a stalled \
        server: a reconnect stops the VM. On failure only what this create added to the folder \
        is removed.
        """,
    )

    @OptionGroup var lib: VPhoneLibraryOption
    @Argument(help: "new VM name") var name: String
    @Option(name: .shortAndLong, help: "iPhone IPSW URL or local path") var iphoneSource: String?
    @Option(name: .shortAndLong, help: "cloudOS IPSW URL or local path") var cloudosSource: String?
    @Option(help: "GPU driver bundle from the same cloudOS build, for offline AEA recovery")
    var gpuDriverBundle: String?
    @Option(help: "Directory for downloaded IPSWs, shared by every VM (default: ~/.vphone/ipsws or $VPHONE_ROOT/ipsws)")
    var ipswCache: String?
    @Option(help: ArgumentHelp(
        "Guest device, when the IPSW covers several models (iPad15,5 from the iPad Air IPSW)",
        valueName: "product-type",
    ))
    var device: String?
    @Option(help: ArgumentHelp(
        "Full OTA (.aea) URL or local path for a device Apple ships no IPSW for (AppleTV14,1) (default: the catalog's OTA of the IPSW's build)",
        valueName: "ota",
    ))
    var otaSource: String?
    @Option(help: ArgumentHelp("The OTA's AEA key in base64, as AppleDB lists it (default: the catalog's)", valueName: "base64"))
    var otaKey: String?
    @Option(name: .shortAndLong, help: "Disk size (GB, default 64)") var diskSize: UInt64?
    @Option(
        name: .customLong("preset"),
        help: "Patch preset for the new VM. Defaults to standard; run `fw patches` to see what each one applies.",
    )
    var preset: String?
    @Option(name: .long, help: "CPU cores (default 8)") var cpu: UInt?
    @Option(name: .long, help: "Memory (MB, default 8192)") var memory: UInt64?
    @Option(name: [.customShort("n"), .long], help: "Network mode: nat (default) | bridged | tunnel | none")
    var network: String?
    @Option(name: .long, help: "Unlock the guest when it starts: on | off (default)")
    var unlockAtStartup: String?
    @Option(help: ArgumentHelp("Clone the VM from this template (vm template list)", valueName: "id"))
    var template: String?
    @Flag(help: "Build the VM on its own, with SEP and Data volume keys of its own, instead of from a template")
    var noTemplate = false
    @Flag(help: "Do not boot the new VM to check that vphoned answers")
    var skipFirstBoot = false
    @OptionGroup(title: "Template slimming") var slimming: VPhoneTemplateSlimmingOptions
    @Flag(
        name: .customLong("keep-artifacts"),
        help: "Keep the prepared restore tree after installation. Downloaded IPSWs always stay in the IPSW cache.",
    )
    var keepArtifacts = false
    @Flag(name: .customShort("v"), help: "Increase verbosity: -v tool detail, -vv guest serial, -vvv internal trace")
    var verboseCount: Int
    @OptionGroup(title: "Remote disk") var remote: VPhoneRemoteDiskCreateOptions

    private var isAppleTV: Bool {
        VPhoneGuestDevice.named(device)?.family == .appleTV
    }

    /// A preset that customises the system before the restore (`minimal`): the
    /// offline trim and the setup boot of a template write the System volume,
    /// which would break that system's seal.
    private var customisesRestoredSystem: Bool {
        VPhonePatchPresetStore.preset(named: preset ?? defaultPreset)?.patchSets
            .contains { $0.identifier == FirmwareRestoreImagePatchSet.identifier } ?? false
    }

    /// An Apple TV takes the TV preset; one whose userland comes from an OTA
    /// takes the arm64e one, with the GPU driver and the userland swap. An
    /// Apple Watch takes the watch preset, an iPhone XS Max `minimal`: its iOS 18
    /// research board kernel boots no other.
    private var defaultPreset: String {
        switch VPhoneGuestDevice.named(device) {
        case let guest? where guest.family == .appleTV:
            guest.restoreBase == nil ? VPhonePatchPreset.tvOSIdentifier : VPhonePatchPreset.tvOS4KIdentifier
        case let guest? where guest.family == .watch:
            VPhonePatchPreset.watchOSIdentifier
        case let guest? where guest.notchedArtworkSubtype != nil:
            VPhonePatchPreset.minimalIdentifier
        default:
            VPhonePatchPreset.standardIdentifier
        }
    }

    func validate() throws {
        if remote.remoteDisk != nil {
            try validateRemoteDisk()
            return
        }
        try remote.requireUnused()
        if template != nil, noTemplate {
            throw ValidationError("--template and --no-template exclude each other.")
        }
        if noTemplate, try !slimming.request.isEmpty {
            throw ValidationError("The slimming switches shape a template; --no-template builds the VM without one.")
        }
        if otaSource != nil || otaKey != nil, VPhoneGuestDevice.named(device)?.restoreBase == nil {
            throw ValidationError("--ota-source and --ota-key are for a device Apple ships no IPSW for, such as --device AppleTV14,1.")
        }
        if isAppleTV {
            // Templates and their setup boot drive iOS Setup Assistant and its apps.
            if template != nil {
                throw ValidationError("An Apple TV guest is built without a template; --template cannot be used.")
            }
            if try !slimming.request.isEmpty {
                throw ValidationError("An Apple TV guest is built without a template; the slimming switches do not apply.")
            }
        }
        if customisesRestoredSystem {
            if template != nil {
                throw ValidationError("The \(preset ?? defaultPreset) preset builds a VM without a template; --template cannot be used.")
            }
            if try !slimming.request.isEmpty {
                throw ValidationError("The \(preset ?? defaultPreset) preset builds a VM without a template; the slimming switches do not apply.")
            }
        }
        _ = try slimming.resolve()
        if template != nil {
            let firmware = [
                ("--iphone-source", iphoneSource != nil),
                ("--cloudos-source", cloudosSource != nil),
                ("--gpu-driver-bundle", gpuDriverBundle != nil),
                ("--ipsw-cache", ipswCache != nil),
                ("--keep-artifacts", keepArtifacts),
            ].filter(\.1).map(\.0)
            if !firmware.isEmpty {
                throw ValidationError("\(firmware.joined(separator: ", ")) cannot be used with --template: the template's firmware is already installed.")
            }
        }
    }

    func run() throws {
        if remote.remoteDisk != nil {
            try runRemoteDisk()
            return
        }
        let resources = VPhoneResources.resolve()
        if let device, VPhoneGuestDevice.named(device) == nil {
            throw ValidationError("vphone runs \(VPhoneGuestDevice.known.map(\.productType).joined(separator: ", ")) guests, not \(device).")
        }
        let networkMode = try network.map(VPhoneVirtualMachineConfigCommand.parseMode)
        let unlocks = try unlockAtStartup.map { try VPhoneVirtualMachineConfigCommand.parseSwitch($0, option: "--unlock-at-startup") }
        let templateUse: VPhoneVirtualMachineCreator.TemplateUse = if let template {
            .identifier(template)
        } else if noTemplate || isAppleTV || customisesRestoredSystem {
            .none
        } else {
            .automatic
        }

        // Resolved up front: a create boots the guest four times, and this is
        // also where a missing vphone-vm should be reported — before any of the
        // long-running download and patch work, not after it. A clone from a
        // named template that skips its first boot starts no guest at all.
        let launcher: VPhoneGuestLaunchPlanner? = if case .identifier = templateUse, skipFirstBoot {
            nil
        } else {
            try VPhoneGuestLaunchPlanner()
        }

        var sources = VPhoneFirmwareSources(iphoneSource: nil, cloudosSource: nil)
        if templateUse == .none || templateUse == .automatic {
            // Prompt for any firmware component not supplied on the command line,
            // from the guest device's builds.
            sources = try VPhoneFirmwareSourceSelection.resolve(iphone: iphoneSource, cloudos: cloudosSource, device: device)
            guard sources.iphoneSource != nil, sources.cloudosSource != nil else {
                throw ValidationError("Specify both --iphone-source and --cloudos-source when running without a terminal.")
            }
        }
        let orchestrator = VPhoneVirtualMachineCreator(
            library: lib.library,
            resources: resources,
            launcher: launcher,
        )
        try orchestrator.run(.init(
            name: name,
            iphoneSource: sources.iphoneSource,
            cloudosSource: sources.cloudosSource,
            gpuDriverBundle: gpuDriverBundle.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) },
            ipswCacheDirectory: ipswCache.map {
                URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
            } ?? VPhoneResources.ipswCacheDirectory(),
            device: device,
            otaSource: otaSource,
            otaKey: otaKey,
            patchPreset: preset ?? defaultPreset,
            cpuCount: cpu ?? 8,
            memoryMB: memory ?? 8192,
            diskSizeGB: diskSize ?? 64,
            networkMode: networkMode,
            unlocksAtStartup: unlocks,
            verbosity: VPhoneVerbosity(count: verboseCount),
            keepArtifacts: keepArtifacts,
            template: templateUse,
            templateRequest: VPhoneMachineTemplateRequest(
                device: device,
                patchPreset: preset,
                diskSizeGB: diskSize,
                slimming: slimming.request.isEmpty ? nil : slimming.resolve(),
            ),
            skipsFirstBoot: skipFirstBoot,
            slimming: slimming.resolve(),
        ))
    }
}

// MARK: - Remote disk

struct VPhoneRemoteDiskCreateOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Make the VM on this NBD export instead of a disk image (nbd://host:port/export)", valueName: "url"))
    var remoteDisk: String?
    @Option(help: ArgumentHelp("With --remote-disk: the template's config.plist the VM is made from", valueName: "path"))
    var fromManifest: String?
    @Option(help: "With --remote-disk: NBD connection timeout in seconds (60-600, default 60)")
    var nbdTimeout: Double?
    @Flag(name: .customLong("json"), help: "With --remote-disk: print the new VM as JSON")
    var json = false

    /// Without --remote-disk none of its options may be given.
    func requireUnused() throws {
        let given = [
            ("--from-manifest", fromManifest != nil),
            ("--nbd-timeout", nbdTimeout != nil),
            ("--json", json),
        ].filter(\.1).map(\.0)
        if !given.isEmpty {
            throw ValidationError("\(given.joined(separator: ", ")) only go with --remote-disk.")
        }
    }
}

extension VPhoneVirtualMachineCreateCommand {
    private func validateRemoteDisk() throws {
        guard let remoteDisk = remote.remoteDisk else { return }
        guard remote.fromManifest != nil else {
            throw ValidationError("--remote-disk needs --from-manifest, the template's config.plist.")
        }
        guard case .networkBlockDevice = try VPhoneDiskLocation(manifestValue: remoteDisk) else {
            throw ValidationError("--remote-disk takes an nbd://host:port/export URL, not \(remoteDisk).")
        }
        let excluded = try [
            ("--template", template != nil),
            ("--no-template", noTemplate),
            ("--iphone-source", iphoneSource != nil),
            ("--cloudos-source", cloudosSource != nil),
            ("--gpu-driver-bundle", gpuDriverBundle != nil),
            ("--ipsw-cache", ipswCache != nil),
            ("--device", device != nil),
            ("--ota-source", otaSource != nil),
            ("--ota-key", otaKey != nil),
            ("--disk-size", diskSize != nil),
            ("--preset", preset != nil),
            ("--keep-artifacts", keepArtifacts),
            ("the slimming switches", !slimming.request.isEmpty),
        ].filter(\.1).map(\.0)
        if !excluded.isEmpty {
            throw ValidationError("\(excluded.joined(separator: ", ")) cannot be used with --remote-disk: the VM is made from the template's config.plist and the state already in MachineState/.")
        }
        do {
            try remoteSpec(disk: remoteDisk).validate()
        } catch let error as VPhoneRemoteDiskMachineError {
            throw ValidationError(error.description)
        } catch let error as VPhoneDiskLocationError {
            throw ValidationError(error.description)
        }
        _ = try network.map(VPhoneVirtualMachineConfigCommand.parseMode)
        _ = try unlockAtStartup.map { try VPhoneVirtualMachineConfigCommand.parseSwitch($0, option: "--unlock-at-startup") }
    }

    private func remoteSpec(disk: String) throws -> VPhoneRemoteDiskMachine {
        try VPhoneRemoteDiskMachine(
            name: name,
            disk: VPhoneNBDLocation(parsing: disk),
            timeoutSeconds: remote.nbdTimeout ?? VPhoneRemoteDiskMachine.minimumTimeoutSeconds,
            manifestSource: URL(fileURLWithPath: ((remote.fromManifest ?? "") as NSString).expandingTildeInPath),
        )
    }

    /// Completes the mounted machine folder and applies the settings a create
    /// from a template applies. Nothing boots: the first start is the caller's.
    private func runRemoteDisk() throws {
        guard let remoteDisk = remote.remoteDisk else { return }
        let networkMode = try network.map(VPhoneVirtualMachineConfigCommand.parseMode)
        let unlocks = try unlockAtStartup.map { try VPhoneVirtualMachineConfigCommand.parseSwitch($0, option: "--unlock-at-startup") }
        let library = lib.library
        try VPhoneBundleOperations.createOnRemoteDisk(remoteSpec(disk: remoteDisk), in: library)
        let bundle: VPhoneBundle
        do {
            bundle = try VPhoneBundleOperations.updateConfig(
                bundleNamed: name,
                in: library,
                cpuCount: cpu,
                memoryMB: memory,
                networkMode: networkMode,
                unlocksAtStartup: unlocks,
            )
        } catch {
            try? VPhoneBundleOperations.removeRemoteDiskMachineFiles(named: name, in: library)
            throw error
        }
        let manifest = bundle.manifest
        if remote.json {
            let report: [String: Any] = [
                "name": bundle.name,
                "path": bundle.url.path,
                "disk": manifest.diskLocation.manifestValue,
                "nbd_timeout_seconds": manifest.nbd?.effectiveTimeout ?? VPhoneRemoteDiskMachine.minimumTimeoutSeconds,
                "state_layout": VPhoneMachineStateLayout.kind(of: manifest)?.rawValue ?? "mixed",
                "state_directory": VPhoneMachineStateLayout.directory(of: bundle).path,
                "cpu": manifest.cpuCount,
                "memory_mb": manifest.memorySize / (1024 * 1024),
                "network": manifest.networkConfig.mode.rawValue,
                "unlock_at_startup": manifest.unlocksScreenAtStartup,
                "boot_rom": manifest.romImages?.avpBooter ?? "",
                "sep_rom": manifest.romImages?.avpSEPBooter ?? "",
                "device": manifest.guestDevice.productType,
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return
        }
        print("[+] \(bundle.name) made on \(manifest.diskLocation.manifestValue) with its state in "
            + "\(VPhoneMachineStateLayout.directory(of: bundle).path), a new identity, "
            + "\(manifest.cpuCount) CPU, \(manifest.memorySize / (1024 * 1024)) MB, network \(manifest.networkConfig.mode.rawValue)")
    }
}
