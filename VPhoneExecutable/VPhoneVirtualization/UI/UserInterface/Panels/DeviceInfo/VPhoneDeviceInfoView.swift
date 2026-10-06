import SwiftUI
import VPhoneDesignKit

struct VPhoneDeviceInfoView: View {
    @Bindable var model: VPhoneDeviceInfoModel

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            DKStatusBar(
                isConnected: model.control.isConnected,
                text: activity ?? model.status?.message,
                detail: "device.info",
                textTone: activity == nil ? model.status?.tone : nil,
            )
        }
        .guestToolShortcuts([
            VPhoneGuestToolShortcut(key: "r", isEnabled: !model.isLoading) {
                Task { await model.refresh() }
            },
            VPhoneGuestToolShortcut(key: "c", modifiers: [.command, .shift], isEnabled: model.canCopyJSON) {
                model.copyJSON()
            },
        ])
        // Restarts when Auto Refresh changes and stops when the page closes.
        .task(id: model.autoRefresh) {
            if !model.hasInfo, model.control.isConnected {
                await model.refresh()
            }
            while model.autoRefresh, !Task.isCancelled {
                try? await Task.sleep(for: VPhoneDeviceInfoModel.autoRefreshInterval)
                guard model.autoRefresh, !Task.isCancelled else { break }
                guard model.control.isConnected else { continue }
                await model.refresh(polling: model.hasInfo)
            }
        }
    }

    private var activity: String? {
        model.isLoading && !model.hasInfo
            ? String(localized: "Reading device information…", bundle: VPhoneLocalization.bundle)
            : nil
    }

    // MARK: - Header

    private var header: some View {
        DKPageHeader(
            String(localized: "Device Info", bundle: VPhoneLocalization.bundle),
            subtitle: model.updatedAt.map {
                String(localized: "Updated at \($0.formatted(date: .omitted, time: .standard))", bundle: VPhoneLocalization.bundle)
            },
            actions: [
                DKButtonSpec(
                    String(localized: "Auto Refresh", bundle: VPhoneLocalization.bundle),
                    glyph: .timer,
                    variant: model.autoRefresh ? .pressed : .secondary,
                    help: String(localized: "Refresh every 5 seconds while this page is open", bundle: VPhoneLocalization.bundle),
                ) { model.autoRefresh.toggle() },
                DKButtonSpec(
                    String(localized: "Copy as JSON", bundle: VPhoneLocalization.bundle),
                    glyph: .copy,
                    isEnabled: model.canCopyJSON,
                    help: String(localized: "Copy the raw device.info response as JSON (⇧⌘C)", bundle: VPhoneLocalization.bundle),
                ) { model.copyJSON() },
                DKButtonSpec(
                    String(localized: "Refresh", bundle: VPhoneLocalization.bundle),
                    glyph: .refresh,
                    isEnabled: !model.isLoading,
                    help: String(localized: "Read the device information again (⌘R)", bundle: VPhoneLocalization.bundle),
                ) { Task { await model.refresh() } },
            ],
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.hasInfo {
            readout
        } else if model.isLoading {
            VPhoneGuestToolPlaceholder(
                glyph: .info,
                title: String(localized: "Reading Device Information", bundle: VPhoneLocalization.bundle),
                isLoading: true,
            )
        } else if !model.control.isConnected {
            VPhoneGuestToolPlaceholder(
                glyph: .phone,
                title: String(localized: "Guest Not Connected", bundle: VPhoneLocalization.bundle),
                message: String(localized: "Device information appears once vphoned connects. Start the VM, then choose Refresh.", bundle: VPhoneLocalization.bundle),
            )
        } else {
            VPhoneGuestToolPlaceholder(
                glyph: .phone,
                title: String(localized: "No Device Information", bundle: VPhoneLocalization.bundle),
                message: String(localized: "Choose Refresh to read the device again.", bundle: VPhoneLocalization.bundle),
            )
        }
    }

    private var readout: some View {
        // Masonry, not two fixed columns: every card keeps its own height and
        // goes under the shortest column, so a short card is never stretched
        // into an empty one beside the long Network table, and a wide window
        // gets a third column.
        VPhoneGuestToolContent {
            DKMasonry {
                ForEach(model.interleavedSections) { section in
                    sectionView(section)
                }
                networkSection
            }
        }
    }

    private func sectionView(_ section: VPhoneDeviceInfoSection) -> some View {
        DKSection(section.title) {
            ForEach(section.rows) { row in
                VPhoneDeviceInfoRowView(row: row) { model.copyValue(row.value) }
            }
        }
    }

    // MARK: - Network

    private var networkSection: some View {
        DKSection(String(localized: "Network", bundle: VPhoneLocalization.bundle)) {
            let rows = model.sortedAddresses
            if rows.isEmpty {
                Text("The guest reported no IPv4 or IPv6 addresses.", bundle: VPhoneLocalization.bundle)
                    .font(DK.Typeface.caption)
                    .foregroundStyle(DK.Palette.muted)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight, alignment: .leading)
            } else {
                DKDataTable(
                    String(localized: "Network interfaces", bundle: VPhoneLocalization.bundle),
                    columns: [
                        DKTableColumn(String(localized: "Interface", bundle: VPhoneLocalization.bundle), width: .fixed(90)),
                        DKTableColumn(String(localized: "Family", bundle: VPhoneLocalization.bundle), width: .fixed(70)),
                        DKTableColumn(String(localized: "Address", bundle: VPhoneLocalization.bundle), width: .flexible(min: 160)),
                    ],
                    rows: rows,
                    selection: $model.selectedAddress,
                    minWidth: 340,
                    scrollsVertically: false,
                ) { address, column in
                    addressCell(address, column: column)
                }
            }
        }
    }

    private func addressCell(_ address: VPhoneDeviceNetworkAddress, column: Int) -> some View {
        let cell: DKTableCell = switch column {
        case 0: .mono(address.interface)
        case 1: .text(address.family)
        default: .mono(address.address)
        }
        return DKTableCellView(cell)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                Button(String(localized: "Copy Address", bundle: VPhoneLocalization.bundle)) {
                    model.copyAddress(address, full: false)
                }
                Button(String(localized: "Copy Row", bundle: VPhoneLocalization.bundle)) {
                    model.copyAddress(address, full: true)
                }
            }
    }
}

// MARK: - Row

/// A key-value row; a row with a gauge shows a thin capacity bar before its
/// value, as Storage does.
private struct VPhoneDeviceInfoRowView: View {
    let row: VPhoneDeviceInfoRow
    let copy: () -> Void

    var body: some View {
        Group {
            if let gauge = row.gauge {
                gaugeRow(gauge)
            } else {
                DKKeyValueRow(row.keyValue)
            }
        }
        .help(row.monospaced ? row.value : "")
        .contextMenu {
            Button(String(localized: "Copy", bundle: VPhoneLocalization.bundle), action: copy)
        }
    }

    /// `DKKeyValueRow` with the design's 72pt progress bar between the dot
    /// and the value.
    private func gaugeRow(_ gauge: Double) -> some View {
        HStack(spacing: DK.Space.s3) {
            Text(row.label)
                .foregroundStyle(DK.Palette.muted)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            HStack(spacing: DK.Space.s2) {
                if let tone = row.tone {
                    DKStatusDot(tone)
                }
                DKProgress(value: gauge, tone: .accent, thin: true, label: row.label)
                    .frame(width: 72)
                Text(row.value)
                    .foregroundStyle(row.keyValue.valueTone?.text ?? DK.Palette.ink)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .font(DK.Typeface.body)
        .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }
}
