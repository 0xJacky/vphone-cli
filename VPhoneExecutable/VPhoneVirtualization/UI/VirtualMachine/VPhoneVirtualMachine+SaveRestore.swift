import Dynamic
import Foundation
import Virtualization
import VPhoneCoreKit

// MARK: - Pause, resume, save and restore

/// In-place freezing on the Mac that runs the machine. `pause` keeps the guest
/// in this process's memory; `saveState` writes that memory out so the
/// process can end and give it back; `restoreState` resumes it later, on the
/// same Mac only (Virtualization ties the file to the host).
///
/// Whether a vphone configuration can be saved at all is Virtualization's
/// call, made by `validateSaveRestoreSupport()`. Its error names only the
/// first part it does not support, so `saveRestoreSupport()` takes the
/// configuration apart to name every part that blocks it.
extension VPhoneVirtualMachine {
    enum SaveFollowUp: String, CaseIterable {
        /// Stop the VM and end the process: the memory goes back to the Mac.
        case stop
        /// Stay paused, for a supervisor that snapshots the disk next.
        case pause
        /// Run on. The disk then moves on and the state no longer matches it.
        case resume
    }

    var stateName: String {
        switch virtualMachine.state {
        case .stopped: "stopped"
        case .running: "running"
        case .paused: "paused"
        case .error: "error"
        case .starting: "starting"
        case .pausing: "pausing"
        case .resuming: "resuming"
        case .stopping: "stopping"
        case .saving: "saving"
        case .restoring: "restoring"
        @unknown default: "unknown"
        }
    }

    var statusDictionary: [String: Any] {
        var status: [String: Any] = [
            "state": stateName,
            "disk": options.diskDescription,
            "state_layout": options.stateLayout.rawValue,
        ]
        if let networkDiskStatus {
            status["nbd"] = networkDiskStatus.dictionary
        }
        return status
    }

    // MARK: Pause / resume

    func pause() async throws {
        guard virtualMachine.canPause else { throw VPhoneVirtualMachineError.notRunning(stateName) }
        nonisolated(unsafe) let vm = virtualMachine
        try await vm.pause()
        print("[vphone] Paused")
    }

    func resume() async throws {
        guard virtualMachine.canResume else { throw VPhoneVirtualMachineError.notRunning(stateName) }
        nonisolated(unsafe) let vm = virtualMachine
        try await vm.resume()
        print("[vphone] Resumed")
    }

    // MARK: Support

    struct SaveRestoreSupport {
        let supported: Bool
        let error: String?
        let report: VPhoneSaveRestoreDiagnosis.Report?

        var dictionary: [String: Any] {
            var d: [String: Any] = ["supported": supported]
            if let error {
                d["error"] = error
            }
            if let report {
                d["blockers"] = report.blockers.map { ["device": $0.name, "message": $0.message] }
                if let remainder = report.remainder {
                    d["remainder"] = remainder
                }
                d["summary"] = report.summary
            }
            return d
        }
    }

    /// One part of the configuration the diagnosis can take out, by the
    /// configuration class it is, so a report names the private device.
    private struct Candidate {
        let name: String
        let remove: (VZVirtualMachineConfiguration) -> Void
    }

    private static let sepWithoutStub = "SEP coprocessor without its GDB stub"

    private var saveRestoreCandidates: [Candidate] {
        func setPrivate(_ selector: String, _ value: Any?) -> (VZVirtualMachineConfiguration) -> Void {
            { configuration in
                let sel = NSSelectorFromString(selector)
                if configuration.responds(to: sel) {
                    _ = configuration.perform(sel, with: value)
                }
            }
        }
        return [
            Candidate(name: "multi-touch screen (_VZUSBTouchScreenConfiguration)", remove: setPrivate("_setMultiTouchDevices:", [Any]())),
            Candidate(name: "SEP coprocessor (_VZSEPCoprocessorConfiguration with its GDB stub)", remove: setPrivate("_setCoprocessors:", [Any]())),
            Candidate(name: Self.sepWithoutStub, remove: { _ in }),
            Candidate(
                name: "accelerators (_VZMacVideoToolbox/_VZMacNeuralEngine/_VZMacScalerAccelerator)",
                remove: setPrivate("_setAcceleratorDevices:", [Any]()),
            ),
            Candidate(
                name: "synthetic battery (_VZMacBatteryPowerSourceDeviceConfiguration)",
                remove: setPrivate("_setPowerSourceDevices:", [Any]()),
            ),
            Candidate(name: "kernel GDB stub (_VZGDBDebugStubConfiguration)", remove: setPrivate("_setDebugStub:", nil)),
            Candidate(name: "custom boot ROM (VZMacOSBootLoader _setROMURL)", remove: { $0.bootLoader = VZMacOSBootLoader() }),
            Candidate(name: "PL011 serial port (_VZPL011SerialPortConfiguration)", remove: { $0.serialPorts = [] }),
            Candidate(name: "audio (host input and output)", remove: { $0.audioDevices = [] }),
            Candidate(name: "network device", remove: { $0.networkDevices = [] }),
            Candidate(name: "USB keyboard", remove: { $0.keyboards = [] }),
            Candidate(name: "vsock device", remove: { $0.socketDevices = [] }),
            Candidate(name: "graphics", remove: { $0.graphicsDevices = [] }),
            Candidate(name: "entropy device", remove: { $0.entropyDevices = [] }),
            Candidate(name: "disk (\(options.diskDescription))", remove: { $0.storageDevices = [] }),
        ]
    }

    func saveRestoreSupport() -> SaveRestoreSupport {
        do {
            try configuration.validateSaveRestoreSupport()
            return SaveRestoreSupport(supported: true, error: nil, report: nil)
        } catch {
            let message = Self.message(of: error)
            let candidates = saveRestoreCandidates
            let report = VPhoneSaveRestoreDiagnosis.diagnose(candidates: candidates.map(\.name)) { kept in
                guard let copy = configuration.copy() as? VZVirtualMachineConfiguration else {
                    return "the configuration could not be copied"
                }
                for candidate in candidates where !kept.contains(candidate.name) {
                    candidate.remove(copy)
                }
                if kept.contains(Self.sepWithoutStub), let sep = sepConfigurationWithoutDebugStub() {
                    _ = copy.perform(NSSelectorFromString("_setCoprocessors:"), with: [sep])
                }
                do {
                    try copy.validateSaveRestoreSupport()
                    return nil
                } catch {
                    return Self.message(of: error)
                }
            }
            return SaveRestoreSupport(supported: false, error: message, report: report)
        }
    }

    private func sepConfigurationWithoutDebugStub() -> AnyObject? {
        let sep = Dynamic._VZSEPCoprocessorConfiguration(storageURL: options.sepStorageURL)
        if let sepRomURL = options.sepRomURL {
            sep.setRomBinaryURL(sepRomURL)
        }
        return sep.asAnyObject
    }

    static func message(of error: Error) -> String {
        let error = error as NSError
        return error.localizedFailureReason ?? error.localizedDescription
    }

    // MARK: Save

    struct SaveResult {
        let directory: URL
        let binding: VPhoneSavedStateBinding
        let pauseSeconds: Double
        let saveSeconds: Double
        let followUpSeconds: Double

        var dictionary: [String: Any] {
            [
                "path": directory.path,
                "bytes": binding.stateFileSize,
                "after": binding.after,
                "pause_seconds": pauseSeconds,
                "save_seconds": saveSeconds,
                "after_seconds": followUpSeconds,
                "host": binding.hostName,
                "disk_checked": binding.disk != nil,
            ]
        }
    }

    /// Pauses the VM if it runs, saves its state into `directory` (created;
    /// it must not exist unless `replacing`), then does `followUp`.
    ///
    /// The state is written to a hidden sibling directory and renamed into
    /// place with its binding, so a listed state is always complete. A failed
    /// save resumes a VM that was running.
    func saveState(
        to directory: URL,
        then followUp: SaveFollowUp,
        replacing: Bool,
        ignoringValidation: Bool,
    ) async throws -> SaveResult {
        guard virtualMachine.state == .running || virtualMachine.state == .paused else {
            throw VPhoneVirtualMachineError.notRunning(stateName)
        }
        let support = saveRestoreSupport()
        if !support.supported {
            let reason = support.report?.summary ?? support.error ?? "unknown"
            guard ignoringValidation else {
                throw VPhoneVirtualMachineError.saveRestoreUnsupported(reason)
            }
            print("[vphone] validateSaveRestoreSupport failed (\(reason)); saving anyway as asked")
        }

        let fm = FileManager.default
        let exists = VPhoneVirtualMachineManifest.fileKind(at: directory) != .missing
        if exists, !replacing {
            throw VPhoneSavedStateError.alreadyExists(path: directory.path)
        }
        let parent = directory.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".\(directory.lastPathComponent).saving-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        var published = false
        defer {
            if !published {
                try? fm.removeItem(at: staging)
            }
        }

        nonisolated(unsafe) let vm = virtualMachine
        let wasRunning = virtualMachine.state == .running
        let clock = ContinuousClock()
        let start = clock.now
        if wasRunning {
            try await vm.pause()
        }
        let paused = clock.now
        let stateFile = VPhoneSavedMachineState.stateFile(in: staging)
        do {
            try await vm.saveMachineStateTo(url: stateFile)
        } catch {
            if wasRunning {
                try? await vm.resume()
            }
            throw error
        }
        let saved = clock.now
        print("[vphone] Saved machine state to \(directory.path)")

        var disk: VPhoneDiskFingerprint?
        if case let .file(url) = options.disk {
            disk = VPhoneDiskFingerprint(of: url)
        }
        // Taken now, before the follow-up: after a stop the disk is as the
        // state left it, after a resume it moves on and the state goes stale.
        switch followUp {
        case .stop:
            virtualMachine.delegate = nil
            try await vm.stop()
            if case let .file(url) = options.disk {
                disk = VPhoneDiskFingerprint(of: url)
            }
            print("[vphone] Stopped after saving")
        case .pause:
            break
        case .resume:
            try await vm.resume()
            print("[vphone] Resumed after saving")
        }
        let done = clock.now

        let size = (try? fm.attributesOfItem(atPath: stateFile.path)[.size] as? NSNumber)?.int64Value ?? 0
        let binding = VPhoneSavedStateBinding(
            hardwareModel: hardwareModelData,
            machineIdentifier: machineIdentifierData,
            configuration: savedStateConfiguration,
            hostUUID: VPhoneHostIdentity.platformUUID(),
            hostName: VPhoneHostIdentity.hostName(),
            hostOSBuild: VPhoneHostIdentity.osBuild(),
            vphoneVersion: VPhoneHostIdentity.vphoneVersion,
            disk: disk,
            stateFileSize: size,
            saved: Date(),
            after: followUp.rawValue,
        )
        try binding.write(to: VPhoneSavedMachineState.bindingFile(in: staging))
        try VPhoneHostFilePermissions.makeAccessible(at: staging)
        try publish(staging, as: directory, replacing: exists)
        published = true

        if followUp == .stop {
            // The reply to the request that asked for this goes out first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.onStoppedAfterSave?()
            }
        }
        return SaveResult(
            directory: directory,
            binding: binding,
            pauseSeconds: Self.seconds(paused - start),
            saveSeconds: Self.seconds(saved - paused),
            followUpSeconds: Self.seconds(done - saved),
        )
    }

    private func publish(_ staging: URL, as directory: URL, replacing: Bool) throws {
        let fm = FileManager.default
        if replacing {
            let old = directory.deletingLastPathComponent()
                .appendingPathComponent(".\(directory.lastPathComponent).old-\(UUID().uuidString)", isDirectory: true)
            try fm.moveItem(at: directory, to: old)
            do {
                try fm.moveItem(at: staging, to: directory)
            } catch {
                try? fm.moveItem(at: old, to: directory)
                throw error
            }
            try? fm.removeItem(at: old)
        } else {
            guard renamex_np(staging.path, directory.path, UInt32(RENAME_EXCL)) == 0 else {
                throw VPhoneSavedStateError.alreadyExists(path: directory.path)
            }
        }
    }

    var savedStateConfiguration: VPhoneSavedStateConfiguration {
        VPhoneSavedStateConfiguration(
            manifest: manifest,
            effectiveCPUCount: configuration.cpuCount,
            effectiveMemorySize: configuration.memorySize,
        )
    }

    private static func seconds(_ duration: Duration) -> Double {
        let (s, attoseconds) = duration.components
        return Double(s) + Double(attoseconds) / 1e18
    }

    // MARK: Restore

    /// Restores the state in `directory` into this stopped VM and resumes it.
    /// Throws, leaving the VM stopped, when the binding refuses the state or
    /// Virtualization does; the caller then boots it cold. A state that was
    /// resumed is marked used.
    func restoreState(from directory: URL, allowOtherHost: Bool) async throws {
        let bindingURL = VPhoneSavedMachineState.bindingFile(in: directory)
        let stateFile = VPhoneSavedMachineState.stateFile(in: directory)
        guard let binding = try VPhoneSavedStateBinding.load(from: bindingURL),
              VPhoneVirtualMachineManifest.fileKind(at: stateFile) == .regularFile
        else {
            throw VPhoneSavedStateError.missing(path: directory.path)
        }
        var disk: VPhoneDiskFingerprint?
        if case let .file(url) = options.disk {
            disk = VPhoneDiskFingerprint(of: url)
        }
        let verification = binding.verify(
            against: .init(
                hardwareModel: hardwareModelData,
                machineIdentifier: machineIdentifierData,
                configuration: savedStateConfiguration,
                hostUUID: VPhoneHostIdentity.platformUUID(),
                hostOSBuild: VPhoneHostIdentity.osBuild(),
                disk: disk,
            ),
            allowOtherHost: allowOtherHost,
        )
        for warning in verification.warnings {
            print("[vphone] Saved state warning: \(warning)")
        }
        guard verification.isRestorable else {
            throw VPhoneSavedStateError.notRestorable(path: directory.path, reasons: verification.refusals)
        }

        print("[vphone] Restoring machine state from \(directory.path) (saved \(binding.saved) on \(binding.hostName))")
        userspaceNetwork?.start()
        nonisolated(unsafe) let vm = virtualMachine
        let clock = ContinuousClock()
        let start = clock.now
        try await vm.restoreMachineStateFrom(url: stateFile)
        let restored = clock.now
        do {
            try await vm.resume()
        } catch {
            try? await vm.stop()
            throw error
        }
        let resumed = clock.now
        try? VPhoneSavedMachineState.invalidate(in: directory, reason: "restored on \(VPhoneHostIdentity.hostName()) at \(Date())")
        print("[vphone] Restored in \(Self.seconds(restored - start)) s, resumed in \(Self.seconds(resumed - restored)) s")
    }

    /// Marks a saved state of this machine as overtaken, because the machine
    /// is about to run without it and its disk will move on. A state saved by
    /// another machine is left alone.
    func invalidateOwnSavedState(in directory: URL, reason: String) {
        guard let binding = try? VPhoneSavedStateBinding.load(from: VPhoneSavedMachineState.bindingFile(in: directory)),
              binding.invalidated == nil,
              binding.machineIdentifier == machineIdentifierData
        else { return }
        do {
            try VPhoneSavedMachineState.invalidate(in: directory, reason: reason)
            print("[vphone] Marked the saved state at \(directory.path) as used: \(reason)")
        } catch {
            print("[vphone] Warning: could not mark the saved state at \(directory.path) as used: \(error)")
        }
    }
}
