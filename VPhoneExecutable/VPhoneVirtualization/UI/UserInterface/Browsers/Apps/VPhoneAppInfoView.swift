import SwiftUI
import VPhoneDesignKit

// MARK: - App Info

/// The App Info pane beside the app table: `apps.info`, `apps.binary`, URL
/// schemes and the CoreTelephony network policy of the selected app, with
/// the selected app's actions.
struct VPhoneAppInfoView: View {
    let model: VPhoneAppBrowserModel

    var body: some View {
        if let detail = model.detail, let app = model.selectedApp, app.id == detail.bundleID {
            ScrollView {
                VStack(alignment: .leading, spacing: DK.Space.s4) {
                    header(detail)
                    actions(app, detail)
                    bundleSection(detail)
                    containerSection(detail)
                    schemeSection(detail)
                    binarySection(detail)
                    entitlementSection(detail)
                    networkSection(detail)
                }
                .padding(DK.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel(VPhoneLocalization.text("App Info"))
        } else if model.selection.count > 1 {
            VPhonePanelEmptyState(
                title: "Multiple Apps Selected",
                systemImage: "square.stack",
                message: "Select one app to see its info.",
            )
        } else {
            VPhonePanelEmptyState(
                title: "No App Selected",
                systemImage: "info.circle",
                message: "Select an app to see its bundle, binary and data container.",
            )
        }
    }

    // MARK: - Header

    private func header(_ detail: VPhoneAppDetail) -> some View {
        HStack(alignment: .top, spacing: DK.Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.displayName)
                    .font(DK.Typeface.pageTitle)
                    .foregroundStyle(DK.Palette.ink)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(detail.bundleID)
                    .font(DK.Typeface.mono)
                    .foregroundStyle(DK.Palette.muted)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if model.isLoadingDetail {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func actions(_ app: VPhoneAppRecord, _ detail: VPhoneAppDetail) -> some View {
        let ids: Set<VPhoneAppRecord.ID> = [app.id]
        return VPhoneAppInfoFlow {
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Open URL…"),
                glyph: .link,
                isEnabled: model.canLaunch(ids),
                help: VPhoneLocalization.text("Open a URL in this app"),
            ) { model.requestOpenURL(app) })
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Show in Files"),
                glyph: .folder,
                isEnabled: model.control.isConnected,
                help: VPhoneLocalization.text("Open the File Browser at the data container"),
            ) {
                if detail.dataPath.isEmpty {
                    Task { await model.showDataContainer(app) }
                } else {
                    model.reveal(path: detail.dataPath)
                }
            })
            DKButton(DKButtonSpec(
                VPhoneLocalization.text("Uninstall…"),
                glyph: .trash,
                variant: .danger,
                isEnabled: model.canUninstall(ids),
                help: app.isSystem
                    ? VPhoneLocalization.text("System apps cannot be uninstalled")
                    : VPhoneLocalization.text("Remove the app and its data from the guest"),
            ) { model.requestUninstall([app]) })
        }
    }

    // MARK: - Sections

    private func bundleSection(_ detail: VPhoneAppDetail) -> some View {
        DKSection(VPhoneLocalization.text("Bundle")) {
            VPhoneAppInfoError(message: detail.infoError)
            VPhoneAppInfoRows(rows: [
                ("Version", detail.version),
                ("Build", detail.build),
                ("Type", detail.type),
                ("Signer", detail.signer),
                ("Minimum OS", detail.minimumOS),
                ("SDK", detail.sdk),
            ])
            VPhoneAppInfoPathRow(key: "Path", value: detail.bundlePath)
            VPhoneAppInfoPathRow(key: "Executable", value: detail.executable)
        }
    }

    private func containerSection(_ detail: VPhoneAppDetail) -> some View {
        DKSection(
            VPhoneLocalization.text("Data Container"),
            accessory: detail.dataPath.isEmpty ? nil : DKButtonSpec(VPhoneLocalization.text("Copy Path")) {
                model.copy([detail.dataPath])
            },
        ) {
            if detail.dataPath.isEmpty {
                VPhoneAppInfoPlaceholder(text: detail.hasInfo ? "This app has no data container." : "Loading…")
            } else {
                VPhoneAppInfoPathRow(key: "Path", value: detail.dataPath)
            }
            if detail.groupContainers.isEmpty {
                if detail.hasInfo {
                    DKKeyValueRow(DKKeyValue(VPhoneLocalization.text("App Groups"), VPhoneLocalization.text("None")))
                }
            } else {
                ForEach(detail.groupContainers) { group in
                    VPhoneAppInfoPathRow(key: group.identifier, value: group.path, localizesKey: false)
                        .contextMenu {
                            Button("Show in Files") { model.reveal(path: group.path) }
                            Button("Copy Path") { model.copy([group.path]) }
                        }
                }
            }
        }
    }

    private func schemeSection(_ detail: VPhoneAppDetail) -> some View {
        DKSection(VPhoneLocalization.text("URL Schemes")) {
            if detail.urlSchemes.isEmpty {
                VPhoneAppInfoPlaceholder(text: detail.hasInfo ? "This app declares no URL schemes." : "Loading…")
            } else {
                ForEach(detail.urlSchemes, id: \.self) { scheme in
                    VPhoneAppInfoValueRow(value: "\(scheme)://")
                }
            }
        }
    }

    private func binarySection(_ detail: VPhoneAppDetail) -> some View {
        DKSection(VPhoneLocalization.text("Mach-O")) {
            VPhoneAppInfoError(message: detail.binaryError)
            VPhoneAppInfoRows(rows: [
                ("Encrypted", detail.encrypted.map { $0 ? VPhoneLocalization.text("Yes (FairPlay)") : VPhoneLocalization.text("No") } ?? ""),
                ("Entitlements", detail.hasBinary || detail.hasInfo ? String(detail.entitlements.count) : ""),
            ])
            if let error = detail.signingError {
                VPhoneAppInfoError(message: error)
            }
        }
    }

    private func entitlementSection(_ detail: VPhoneAppDetail) -> some View {
        DKSection(
            VPhoneLocalization.text("Entitlements"),
            accessory: detail.entitlements.isEmpty ? nil : DKButtonSpec(
                VPhoneLocalization.text("Copy as Property List"),
                help: VPhoneLocalization.text("Copy the entitlements as an XML property list"),
            ) { model.copy([detail.entitlementsPlist]) },
        ) {
            if detail.entitlements.isEmpty {
                VPhoneAppInfoPlaceholder(text: detail.hasBinary || detail.hasInfo ? "The binary has no entitlements." : "Loading…")
            } else {
                ForEach(detail.entitlements) { entitlement in
                    VPhoneAppInfoPathRow(key: entitlement.key, value: entitlement.value, localizesKey: false, monospacedKey: true)
                }
            }
        }
    }

    private func networkSection(_ detail: VPhoneAppDetail) -> some View {
        DKSection(
            VPhoneLocalization.text("Network Access"),
            accessory: detail.networkPolicy.map { policy in
                DKButtonSpec(
                    VPhoneLocalization.text("Allow Network"),
                    isEnabled: !policy.allowed && !model.isBusy && model.control.isConnected,
                    help: VPhoneLocalization.text("Allow Wi-Fi and cellular data for this app"),
                ) { Task { await model.repairNetworkPolicy() } }
            },
        ) {
            VPhoneAppInfoError(message: detail.networkPolicyError)
            if let policy = detail.networkPolicy {
                DKKeyValueRow(DKKeyValue(
                    VPhoneLocalization.text("Wi-Fi and cellular data"),
                    VPhoneLocalization.text(policy.allowed ? "Allowed" : "Restricted"),
                    tone: policy.allowed ? .success : .warning,
                ))
                ForEach(policy.entries) { entry in
                    DKKeyValueRow(DKKeyValue(entry.title, entry.value))
                }
            } else if detail.networkPolicyError == nil {
                VPhoneAppInfoPlaceholder(text: "Loading…")
            }
        }
    }
}

// MARK: - Rows

/// Short key-value rows; empty values are left out.
struct VPhoneAppInfoRows: View {
    let rows: [(String, String)]

    var body: some View {
        ForEach(rows.filter { !$0.1.isEmpty }, id: \.0) { key, value in
            DKKeyValueRow(DKKeyValue(VPhoneLocalization.text(key), value))
        }
    }
}

/// A long value, such as a path or an entitlement, under its key, wrapped
/// instead of clipped. Nothing shows for an empty value.
struct VPhoneAppInfoPathRow: View {
    let key: String
    let value: String
    var localizesKey = true
    var monospacedKey = false

    var body: some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(localizesKey ? VPhoneLocalization.text(key) : key)
                    .font(monospacedKey ? DK.Typeface.mono : DK.Typeface.body)
                    .foregroundStyle(monospacedKey ? DK.Palette.ink : DK.Palette.muted)
                    .textSelection(.enabled)
                Text(value)
                    .font(DK.Typeface.mono)
                    .foregroundStyle(monospacedKey ? DK.Palette.muted : DK.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, DK.Space.s2)
            .accessibilityElement(children: .combine)
        }
    }
}

/// A row holding one monospaced value.
struct VPhoneAppInfoValueRow: View {
    let value: String

    var body: some View {
        Text(value)
            .font(DK.Typeface.mono)
            .foregroundStyle(DK.Palette.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight, alignment: .leading)
            .padding(.horizontal, 14)
    }
}

/// A muted row standing in for a value that is loading or absent.
struct VPhoneAppInfoPlaceholder: View {
    let text: String

    var body: some View {
        Text(VPhoneLocalization.text(text))
            .font(DK.Typeface.body)
            .foregroundStyle(DK.Palette.muted)
            .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight, alignment: .leading)
            .padding(.horizontal, 14)
    }
}

/// What the guest said when a section could not load.
struct VPhoneAppInfoError: View {
    let message: String?

    var body: some View {
        if let message {
            HStack(alignment: .firstTextBaseline, spacing: DK.Space.s2) {
                DKIcon(.warning, size: 13)
                    .foregroundStyle(DK.Palette.warning)
                Text(message)
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.warningInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, DK.Space.s2)
        }
    }
}

/// Buttons that wrap onto further lines when the pane is narrow.
struct VPhoneAppInfoFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }
}
