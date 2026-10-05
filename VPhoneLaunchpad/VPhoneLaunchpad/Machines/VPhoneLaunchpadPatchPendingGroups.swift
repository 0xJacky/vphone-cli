import SwiftUI
import VPhoneDesignKit

/// The patch editor's "not applied" section for an existing machine: the
/// patches whose wanted state has not reached the guest, grouped by the step
/// that delivers them, each with what that step costs.
///
/// It explains; it does not act. The steps themselves (Apply to Guest, Update
/// Kernel) live in the Machines inspector, which runs them with the machine's
/// own Core Bundle once the choice is saved.
struct VPhoneLaunchpadPatchPendingGroups: View {
    typealias Delivery = VPhoneLaunchpadPatchCatalog.Delivery

    let title: String
    /// Whether `cfw install` finished. Before that the differences are from
    /// the last `fw patch`, and the next install builds them in anyway.
    let installed: Bool
    /// Pending identifiers by delivery, in catalogue order.
    let pending: [Delivery: [String]]

    /// How many identifiers a group lists before it says how many more.
    private static let shownIdentifiers = 6

    var body: some View {
        if installed {
            DKSection(
                title,
                note: String(localized: "Highlighted below. Each group reaches the guest a different way; apply them from the machine’s inspector."),
                card: false,
            ) {
                HStack(alignment: .top, spacing: DK.Space.s3) {
                    ForEach(Delivery.allCases) { delivery in
                        group(delivery, identifiers: pending[delivery] ?? [])
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            DKSection(title, card: false) {
                DKBanner(
                    String(localized: "The guest is not installed yet, so these differ from the last fw patch. The next fw patch, restore and cfw install build the machine with this choice."),
                    tone: .info,
                )
            }
        }
    }

    // MARK: - Group

    private func group(_ delivery: Delivery, identifiers: [String]) -> some View {
        let tone = identifiers.isEmpty ? DKTone.neutral : delivery.tone
        return DKCard(fillsHeight: true, tone: tone) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: DK.Space.s2) {
                    DKIcon(delivery.glyph, size: 16)
                        .foregroundStyle(delivery.tone.color)
                    Text(delivery.groupTitle)
                        .font(DK.Typeface.bodyStrong)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DKBadge(String(identifiers.count), tone: tone)
                }
                Text(delivery.explanation)
                    .font(DK.Typeface.caption)
                    .lineSpacing(2)
                    .foregroundStyle(DK.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if identifiers.isEmpty {
                    Text("Nothing pending")
                        .font(DK.Typeface.caption)
                        .foregroundStyle(DK.Palette.muted)
                } else {
                    DKFlowLayout(horizontalSpacing: DK.Space.s1, verticalSpacing: DK.Space.s1) {
                        ForEach(identifiers.prefix(Self.shownIdentifiers), id: \.self) { identifier in
                            chip(identifier)
                        }
                        if identifiers.count > Self.shownIdentifiers {
                            chip(String(localized: "+\(identifiers.count - Self.shownIdentifiers) more"))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, DK.Space.s3)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            Text(delivery.cost)
                .font(DK.Typeface.footnote)
                .foregroundStyle(DK.Palette.muted)
                .padding(.vertical, 7)
                .padding(.horizontal, DK.Space.s3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func chip(_ text: String) -> some View {
        Text(verbatim: text)
            .font(DK.Typeface.monoSmall)
            .foregroundStyle(DK.Palette.inkSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(DK.Palette.surfaceSunken))
    }
}

// MARK: - Delivery wording

extension VPhoneLaunchpadPatchCatalog.Delivery {
    /// The row badge.
    var label: String {
        switch self {
        case .updateEnvironment: String(localized: "Apply to Guest")
        case .updateKernel: String(localized: "Update Kernel")
        case .firmwarePatch: String(localized: "fw patch")
        case .restore: String(localized: "Restore (erases)")
        }
    }

    var tone: DKTone {
        switch self {
        case .updateEnvironment: .success
        case .updateKernel: .info
        case .firmwarePatch: .accent
        case .restore: .danger
        }
    }

    var glyph: DKGlyph {
        switch self {
        case .updateEnvironment: .refresh
        case .updateKernel: .cpu
        case .firmwarePatch: .bolt
        case .restore: .warning
        }
    }

    var groupTitle: String {
        switch self {
        case .updateEnvironment: String(localized: "Apply to Guest")
        case .updateKernel: String(localized: "Update Kernel")
        case .firmwarePatch: String(localized: "AVPBooter via fw patch")
        case .restore: String(localized: "Restore only — erases")
        }
    }

    var explanation: String {
        switch self {
        case .updateEnvironment:
            String(localized: "Turned on or off in place, from the backups and the shared cache undo log.")
        case .updateKernel:
            String(localized: "Re-patched from the machine’s originals and swapped into Preboot. No restore.")
        case .firmwarePatch:
            String(localized: "Read from the machine folder at every boot. fw patch needs the prepared restore files.")
        case .restore:
            String(localized: "TXM, DeviceTree and LLB change only in a restore. iBSS and iBEC matter only to the next one.")
        }
    }

    var cost: String {
        switch self {
        case .updateEnvironment, .updateKernel: String(localized: "Keeps the data · machine stopped")
        case .firmwarePatch: String(localized: "Takes effect at the next boot")
        case .restore: String(localized: "Erases the data")
        }
    }
}
