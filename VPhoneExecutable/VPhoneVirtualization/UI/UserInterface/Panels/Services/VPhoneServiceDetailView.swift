import SwiftUI
import VPhoneDesignKit

/// The detail bar under the service table: key facts for the selected
/// service over launchd's `print` description.
struct VPhoneServiceDetailView: View {
    let model: VPhoneServicesModel

    var body: some View {
        if let row = model.selectedRow {
            DKDetailBar(
                row.label,
                subtitle: row.pid.map { "pid \($0)" },
                facts: facts(row),
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(VPhoneLocalization.text("launchd description"))
                        .font(DK.Typeface.sectionTitle)
                        .foregroundStyle(DK.Palette.muted)
                        .accessibilityAddTraits(.isHeader)
                    description(row)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        } else {
            VPhonePanelEmptyState(
                title: "No Service Selected",
                systemImage: "doc.text.magnifyingglass",
                message: "Select a service to see launchd's description.",
            )
            .background(DK.Palette.surfaceRaised)
        }
    }

    // MARK: - Facts

    private func facts(_ row: VPhoneServiceRow) -> [DKKeyValue] {
        let exit = row.lastExit
        var facts = [
            DKKeyValue(
                VPhoneLocalization.text("State"),
                VPhoneLocalization.text(row.isRunning ? "Running" : "Stopped"),
                tone: row.isRunning ? .success : .idle,
            ),
            DKKeyValue(
                VPhoneLocalization.text("Last Exit"),
                exit.text + (row.lastExitStatus.map { $0 == 0 ? "" : "  (\($0))" } ?? ""),
                tone: exit.isAbnormal ? .warning : nil,
            ),
            DKKeyValue(
                VPhoneLocalization.text("Disabled"),
                row.disabledText,
                tone: row.disabled == true ? .warning : nil,
            ),
            DKKeyValue(VPhoneLocalization.text("Domains"), row.domainText.isEmpty ? "—" : row.domainText),
            DKKeyValue(VPhoneLocalization.text("Program"), row.program ?? "—"),
        ]
        if let detail = model.detail, detail.label == row.label {
            facts.append(DKKeyValue(VPhoneLocalization.text("Printed From"), detail.domain))
        }
        return facts
    }

    // MARK: - Description

    @ViewBuilder
    private func description(_ row: VPhoneServiceRow) -> some View {
        if let detail = model.detail, detail.label == row.label {
            VPhoneSystemTextLog(
                text: detail.text,
                label: String(localized: "launchd description of \(row.label)", bundle: VPhoneLocalization.bundle),
                emptyText: VPhoneLocalization.text("launchd returned an empty description."),
                minHeight: 48,
            )
        } else if let error = model.detailError {
            DKBanner(error, tone: .warning)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

