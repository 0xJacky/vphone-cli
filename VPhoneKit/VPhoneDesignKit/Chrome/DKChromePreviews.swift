#if DEBUG
import SwiftUI

// MARK: - Board

/// A window on the page ground, as the design canvas draws one.
private struct DKChromePreviewWindow<Content: View>: View {
    var width: CGFloat
    var height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DK.Radius.window, style: .continuous)
        VStack(spacing: 0) {
            content
        }
        .frame(width: width, height: height)
        .background(DK.Palette.window)
        .clipShape(shape)
        .overlay(shape.strokeBorder(DK.Palette.line, lineWidth: DK.Metric.hairline))
        .padding(DK.Space.s6)
        .background(DK.Palette.page)
    }
}

/// Muted text centered in the room it is given, where a later component goes.
private struct DKChromePreviewSlot: View {
    var text: String

    var body: some View {
        Text(text)
            .font(DK.Typeface.body)
            .foregroundStyle(DK.Palette.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - VM window

private struct DKChromePreviewVMWindow: View {
    var body: some View {
        DKChromePreviewWindow(width: 472, height: 1000) {
            DKTitleBar(
                machine: "research-26",
                kind: .display,
                tone: .success,
                status: "Running",
                os: "iOS 26.6.2",
                address: "192.168.64.12",
                actions: [DKButtonSpec("Guest Tools", glyph: .sidebar, variant: .ghost, size: .icon)],
                drawsTrafficLights: true,
            )
            ZStack {
                DK.Palette.display
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color(white: 0.36))
                    .overlay {
                        Text("[guest display]\n393 × 852 pt")
                            .multilineTextAlignment(.center)
                            .font(DK.Typeface.mono)
                            .foregroundStyle(Color(white: 0.66))
                    }
                    .aspectRatio(393.0 / 852.0, contentMode: .fit)
                    .padding(DK.Space.s4)
            }
            DKControlBar(
                leading: [
                    DKButtonSpec("Rotate Left", glyph: .restart, size: .icon),
                    DKButtonSpec("Copy Screenshot", glyph: .camera, size: .icon),
                ],
                center: [DKButtonSpec("Home", glyph: .home, size: .largeIcon)],
                trailing: [DKButtonSpec("Recording 00:42", glyph: .record, variant: .recording)],
            )
        }
    }
}

#Preview("VM window") {
    DKChromePreviewVMWindow()
        .preferredColorScheme(.light)
}

#Preview("VM window, dark") {
    DKChromePreviewVMWindow()
        .preferredColorScheme(.dark)
}

// MARK: - Title bars

private struct DKChromePreviewTitleBars: View {
    var body: some View {
        VStack(spacing: DK.Space.s4) {
            ForEach(DKVMWindowKind.allCases, id: \.self) { kind in
                DKChromePreviewWindow(width: 720, height: kind.usesCompactTitleBar ? 52 : 68) {
                    DKTitleBar(
                        machine: "research-26",
                        kind: kind,
                        tone: kind == .terminal ? .warning : .success,
                        os: "iOS 26.6.2",
                        address: "192.168.64.12",
                        actions: [DKButtonSpec("Guest Tools", glyph: .sidebar, variant: .ghost, size: .icon)],
                        drawsTrafficLights: true,
                    )
                }
            }
        }
        .background(DK.Palette.page)
    }
}

#Preview("Title bars") {
    DKChromePreviewTitleBars()
        .preferredColorScheme(.light)
}

#Preview("Title bars, dark") {
    DKChromePreviewTitleBars()
        .preferredColorScheme(.dark)
}

// MARK: - Guest Tools panel

private struct DKChromePreviewPanel: View {
    private let pages = ["Device Info", "Controls", "Apps", "Processes", "Services", "Keychain", "Preferences", "Clipboard", "Console", "Crash Logs"]

    var body: some View {
        DKChromePreviewWindow(width: 1000, height: 640) {
            DKPanel {
                VStack(alignment: .leading, spacing: 1) {
                    Text("research-26")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.bottom, DK.Space.s4)
                    ForEach(pages, id: \.self) { page in
                        Text(page)
                            .fontWeight(page == "Device Info" ? .semibold : .regular)
                            .frame(maxWidth: .infinity, minHeight: DK.Metric.rowHeight, alignment: .leading)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: DK.Radius.row)
                                    .fill(page == "Device Info" ? DK.Palette.selectionNeutral : .clear),
                            )
                    }
                }
                .font(DK.Typeface.body)
                .foregroundStyle(DK.Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
            } header: {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Device Info").font(DK.Typeface.pageTitle)
                        Text("Updated at 09:41:22").font(DK.Typeface.caption).foregroundStyle(DK.Palette.muted)
                    }
                    Spacer()
                    DKButton("Refresh", glyph: .refresh) {}
                }
                .foregroundStyle(DK.Palette.ink)
                .padding(.horizontal, DK.Space.s4)
                .padding(.vertical, DK.Space.s3)
            } content: {
                DKChromePreviewSlot(text: "Panel content")
            } statusBar: {
                HStack {
                    Text("Connected")
                    Spacer()
                }
                .font(DK.Typeface.monoSmall)
                .foregroundStyle(DK.Palette.muted)
                .padding(.horizontal, DK.Space.s3)
                .frame(height: DK.Metric.statusBarHeight)
                .background(DK.Palette.sidebar)
            }
        }
    }
}

#Preview("Guest Tools panel") {
    DKChromePreviewPanel()
        .preferredColorScheme(.light)
}

#Preview("Guest Tools panel, dark") {
    DKChromePreviewPanel()
        .preferredColorScheme(.dark)
}

// MARK: - Launchpad window

private struct DKChromePreviewWindowShell: View {
    var body: some View {
        DKChromePreviewWindow(width: 1100, height: 640) {
            DKWindowShell {
                DKChromePreviewSlot(text: "Sidebar")
            } content: {
                DKChromePreviewSlot(text: "Page content")
            } inspector: {
                DKChromePreviewSlot(text: "Inspector")
            }
        }
    }
}

#Preview("Launchpad window") {
    DKChromePreviewWindowShell()
        .preferredColorScheme(.light)
}

#Preview("Launchpad window, dark") {
    DKChromePreviewWindowShell()
        .preferredColorScheme(.dark)
}

// MARK: - New Machine sheet

private enum DKChromePreviewPage: String, CaseIterable, Hashable {
    case general = "General"
    case hardware = "Hardware"
    case advanced = "Advanced"
}

private struct DKChromePreviewNewMachine: View {
    @State private var page = DKChromePreviewPage.general

    var body: some View {
        DKSheet(
            "New Machine",
            subtitle: "Downloads firmware, patches the boot chain, restores and boots — in one run.",
            width: 720,
            note: page == .hardware
                ? DKSheetNote("64 GB disk leaves 41 GB free on this volume.", tone: .warning)
                : DKSheetNote("iOS 26.6.2 · 8 cores · 8 GB · 64 GB"),
            trailing: [.cancel {}, .primary("Create") {}],
        ) {
            switch page {
            case .general:
                card(["Name", "Location"])
                card(["Core Bundle"])
                card(["Firmware", "iOS 26.6.2", "iOS 27.0", "iOS 27.0.1"])
                card(["Patches"])
            case .hardware:
                card(["CPU Cores", "Memory", "Disk"])
            case .advanced:
                card(["Network", "Serial Console"])
                card(["Keep Downloaded Firmware"])
            }
        } pages: {
            Picker("Page", selection: $page) {
                ForEach(DKChromePreviewPage.allCases, id: \.self) { page in
                    Text(page.rawValue).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .clipShape(RoundedRectangle(cornerRadius: DK.Radius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DK.Radius.sheet, style: .continuous)
                .strokeBorder(DK.Palette.lineStrong, lineWidth: DK.Metric.hairline),
        )
        .padding(DK.Space.s6)
        .background(DK.Palette.page)
    }

    private func card(_ rows: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    DK.Palette.dividerSoft.frame(height: DK.Metric.hairline)
                }
                Text(row)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, DK.Space.s3)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DK.Radius.card).fill(DK.Palette.window),
        )
        .overlay(
            RoundedRectangle(cornerRadius: DK.Radius.card).strokeBorder(DK.Palette.line),
        )
    }
}

#Preview("New Machine sheet") {
    DKChromePreviewNewMachine()
        .preferredColorScheme(.light)
}

#Preview("New Machine sheet, dark") {
    DKChromePreviewNewMachine()
        .preferredColorScheme(.dark)
}
#endif
