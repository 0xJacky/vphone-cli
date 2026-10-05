import SwiftUI
import VPhoneDesignKit

// MARK: - Change Core Bundle

/// Binds one or more machines to another installed Core Bundle. The host
/// programs follow at the next start; the guest environment can be updated
/// now on stopped machines. The boot chain stays as created.
struct VPhoneLaunchpadChangeBundleView: View {
    let machines: [VPhoneLaunchpadMachine]
    @Environment(VPhoneLaunchpadModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var version = ""
    @State private var updatesEnvironment = true

    private var library: VPhoneLaunchpadMachineLibrary {
        model.machines
    }

    private var title: String {
        machines.count == 1
            ? String(localized: "Change Core Bundle of \(machines[0].name)")
            : String(localized: "Change Core Bundle of \(machines.count) Machines")
    }

    /// Nothing to do when every machine already runs with `version` and
    /// its guest environment is left alone.
    private var canApply: Bool {
        !version.isEmpty && (updatesEnvironment || machines.contains { library.bundleVersion(for: $0.path) != version })
    }

    var body: some View {
        DKSheet(
            title,
            width: 520,
            trailing: [
                .cancel(String(localized: "Cancel")) { dismiss() },
                .primary(String(localized: "Apply"), isEnabled: canApply) { apply() },
            ],
        ) {
            DKSection(String(localized: "Current"), rows: machines.map { machine in
                DKKeyValue(
                    machine.name,
                    library.bundleVersion(for: machine.path) ?? "—",
                    monospaced: true,
                    id: machine.path.url.path,
                )
            })
            DKSection(
                footnote: String(localized: "Host programs change at the next start. The guest environment is updated now on stopped machines; running machines keep theirs until it is updated later. Guest patches follow each machine’s patch choice when its guest environment is updated. The boot chain stays as it was built."),
            ) {
                DKFormRow(String(localized: "Core Bundle"), fill: true) {
                    Picker("Core Bundle", selection: $version) {
                        ForEach(model.bundles.selectableVersions, id: \.self) { version in
                            if version == model.bundles.defaultVersion {
                                Text("\(version) (Default)").tag(version)
                            } else {
                                Text(verbatim: version).tag(version)
                            }
                        }
                    }
                    .dkFieldPicker(fill: true)
                }
                VPhoneLaunchpadSwitchRow(isOn: $updatesEnvironment) {
                    Text("Update guest environment")
                }
            }
        }
        .vphoneLaunchpadSheetChrome()
        .onAppear {
            // The machines' own version when they share one, else the default.
            let current = Set(machines.map { library.bundleVersion(for: $0.path) })
            let versions = model.bundles.selectableVersions
            if current.count == 1, let shared = current.first ?? nil, versions.contains(shared) {
                version = shared
            } else {
                version = model.bundles.defaultVersion.flatMap { versions.contains($0) ? $0 : nil } ?? versions.first ?? ""
            }
        }
    }

    private func apply() {
        // setBundle leaves out machines with no guest environment to update.
        let version = version
        let library = library
        let paths = machines.map(\.path)
        let updatesEnvironment = updatesEnvironment
        Task {
            await library.setBundle(version, for: paths, updateEnvironment: updatesEnvironment)
        }
        dismiss()
    }
}
