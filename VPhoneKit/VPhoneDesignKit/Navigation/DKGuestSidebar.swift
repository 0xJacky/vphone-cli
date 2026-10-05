import SwiftUI

// MARK: - Tools

/// A page of the Guest Tools window, in sidebar order.
public enum DKGuestTool: String, Sendable, CaseIterable, Hashable, Identifiable {
    case deviceInfo, controls
    case apps, processes, services
    case files, keychain, preferences, clipboard
    case console, crashLogs

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .deviceInfo: "Device Info"
        case .controls: "Controls"
        case .apps: "Apps"
        case .processes: "Processes"
        case .services: "Services"
        case .files: "Files"
        case .keychain: "Keychain"
        case .preferences: "Preferences"
        case .clipboard: "Clipboard"
        case .console: "Console"
        case .crashLogs: "Crash Logs"
        }
    }

    public var glyph: DKGlyph {
        switch self {
        case .deviceInfo: .info
        case .controls: .sliders
        case .apps: .apps
        case .processes: .cpu
        case .services: .gear
        case .files: .folder
        case .keychain: .key
        case .preferences: .list
        case .clipboard: .clipboard
        case .console: .terminal
        case .crashLogs: .warning
        }
    }

    public var section: DKGuestToolSection {
        switch self {
        case .deviceInfo, .controls: .device
        case .apps, .processes, .services: .software
        case .files, .keychain, .preferences, .clipboard: .data
        case .console, .crashLogs: .logs
        }
    }
}

/// A group of guest tools under one sidebar title, in sidebar order.
public enum DKGuestToolSection: String, Sendable, CaseIterable, Hashable, Identifiable {
    case device, software, data, logs

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .device: "Device"
        case .software: "Software"
        case .data: "Data"
        case .logs: "Logs"
        }
    }

    /// The section's tools, in sidebar order.
    public var tools: [DKGuestTool] {
        DKGuestTool.allCases.filter { $0.section == self }
    }
}

// MARK: - Sidebar

/// The Guest Tools window's sidebar: the machine name with its state, its iOS
/// version and address, then Device, Software, Data and Logs.
public struct DKGuestSidebar: View {
    @Binding var selection: DKGuestTool
    let machineName: String
    let machineTone: DKTone
    let stateLabel: String?
    let facts: [DKSidebarFact]
    let sections: [DKSidebarSection<DKGuestTool>]

    /// - Parameters:
    ///   - machineName: The machine's name, at the top.
    ///   - machineTone: The dot before the name.
    ///   - stateLabel: What VoiceOver reads for the dot ("Guest connected").
    ///   - iOSVersion: The guest's iOS version; omitted when nil.
    ///   - address: The guest's address, in monospace; omitted when nil.
    ///   - counts: A count to show after a tool ("Crash Logs 3").
    public init(
        selection: Binding<DKGuestTool>,
        machineName: String,
        machineTone: DKTone = .success,
        stateLabel: String? = nil,
        iOSVersion: String? = nil,
        address: String? = nil,
        counts: [DKGuestTool: Int] = [:],
    ) {
        _selection = selection
        self.machineName = machineName
        self.machineTone = machineTone
        self.stateLabel = stateLabel
        facts = Self.facts(iOSVersion: iOSVersion, address: address)
        sections = Self.sections(counts: counts)
    }

    public var body: some View {
        DKSidebar(sections: sections, selection: $selection, header: {
            DKSidebarMachineHeader(machineName, tone: machineTone, stateLabel: stateLabel, facts: facts)
        })
        .accessibilityLabel("Guest Tools")
    }

    // MARK: Model

    /// The sidebar's sections, with an optional count per tool.
    public nonisolated static func sections(counts: [DKGuestTool: Int] = [:]) -> [DKSidebarSection<DKGuestTool>] {
        DKGuestToolSection.allCases.map { section in
            DKSidebarSection(section.title, items: section.tools.map { tool in
                DKSidebarItem(id: tool, label: tool.title, glyph: tool.glyph, count: counts[tool])
            })
        }
    }

    nonisolated static func facts(iOSVersion: String?, address: String?) -> [DKSidebarFact] {
        var facts: [DKSidebarFact] = []
        if let iOSVersion {
            facts.append(DKSidebarFact("iOS", iOSVersion))
        }
        if let address {
            facts.append(DKSidebarFact("Address", address, isMonospaced: true))
        }
        return facts
    }
}

// MARK: - Previews

private struct DKGuestSidebarPreview: View {
    @State private var selection: DKGuestTool = .deviceInfo

    var body: some View {
        DKGuestSidebar(
            selection: $selection,
            machineName: "research-26",
            stateLabel: "Guest connected",
            iOSVersion: "26.6.2",
            address: "192.168.64.12",
        )
        .frame(height: 720)
    }
}

#Preview("Guest sidebar, light") {
    DKGuestSidebarPreview().preferredColorScheme(.light)
}

#Preview("Guest sidebar, dark") {
    DKGuestSidebarPreview().preferredColorScheme(.dark)
}
