import Foundation

// MARK: - Reading

extension VPhoneLaunchpadPatchCatalog {
    /// Reads the catalogue with one Core Bundle version's `vphone-cli`.
    ///
    /// `preset` reports against that preset instead of the machine's own record,
    /// which is how the picker re-bases what `inPreset` means. Passing neither a
    /// machine nor a preset reports what the bundle does by default.
    @MainActor
    static func read(
        using commandLine: VPhoneLaunchpadCommandLine?,
        machine: VPhoneLaunchpadMachinePath?,
        preset: String?,
    ) async throws -> VPhoneLaunchpadPatchCatalog {
        #if DEBUG
            if VPhoneLaunchpadPreview.isActive {
                guard let catalog = VPhoneLaunchpadPreview.patchCatalog(preset: preset, machine: machine != nil) else {
                    throw VPhoneLaunchpadError(String(localized: "Unable to list the bundle's patches."))
                }
                return catalog
            }
        #endif
        guard let commandLine else {
            throw VPhoneLaunchpadError(
                String(localized: "No Core Bundle version is in use. Choose a version in Core Bundle."),
            )
        }
        var arguments = ["fw", "patches"]
        if let machine {
            arguments.append(machine.name)
        }
        if let preset {
            arguments += ["--preset", preset]
        }
        arguments.append("--json")
        if let machine {
            arguments += machine.libraryArguments
        }
        let result = try await commandLine.run(arguments, recordInHistory: false)
        guard result.succeeded, let data = result.jsonData else {
            throw VPhoneLaunchpadError(
                String(localized: "Unable to list the bundle's patches."),
                detail: result.tail,
            )
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }
}
