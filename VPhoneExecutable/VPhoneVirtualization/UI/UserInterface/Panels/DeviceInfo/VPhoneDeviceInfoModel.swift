import AppKit
import Foundation
import VPhoneDesignKit

@MainActor
@Observable
final class VPhoneDeviceInfoModel {
    static let autoRefreshInterval: Duration = .seconds(5)

    let control: VPhoneGuestControl
    private(set) var isLoading = false
    private(set) var status: VPhoneGuestToolStatus?
    var autoRefresh = false
    var selectedAddress: VPhoneDeviceNetworkAddress.ID?

    /// The raw `device.info` result, `device.environment` result and the
    /// `memory` object of `memory.pressure`.
    private(set) var info: [String: Any]?
    private(set) var environment: [String: Any]?
    private(set) var jetsamMemory: [String: Any]?
    private(set) var infoJSON: String?
    private(set) var updatedAt: Date?

    var hasInfo: Bool {
        info != nil
    }

    var canCopyJSON: Bool {
        infoJSON != nil
    }

    init(control: VPhoneGuestControl) {
        self.control = control
    }

    // MARK: - Loading

    /// Reads `device.info`, then the memory pressure level and, unless this is
    /// a background poll, the jailbreak environment report.
    func refresh(polling: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await control.call("device.info")
            apply(deviceInfoResult: result)
        } catch {
            fail(String(localized: "Unable to read device information. Check the connection, then try again.", bundle: VPhoneLocalization.bundle))
            return
        }
        if let jetsam = try? await control.call("memory.pressure") {
            apply(jetsamResult: jetsam)
        }
        if !polling || environment == nil, let report = try? await control.call("device.environment") {
            apply(environmentResult: report)
        }
        updatedAt = .now
        let time = Date.now.formatted(date: .omitted, time: .standard)
        status = VPhoneGuestToolStatus(
            message: String(localized: "Updated at \(time).", bundle: VPhoneLocalization.bundle),
            isError: false,
        )
    }

    // MARK: - Parsing

    func apply(deviceInfoResult result: [String: Any]) {
        info = result
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        infoJSON = (try? JSONSerialization.data(withJSONObject: result, options: options))
            .flatMap { String(data: $0, encoding: .utf8) }
        if let selectedAddress, !addresses.contains(where: { $0.id == selectedAddress }) {
            self.selectedAddress = nil
        }
    }

    func apply(environmentResult result: [String: Any]) {
        environment = result
    }

    func apply(jetsamResult result: [String: Any]) {
        jetsamMemory = result.object("memory")
    }

    // MARK: - Copy

    func copyJSON() {
        guard let infoJSON else { return }
        copy(infoJSON, message: String(localized: "Copied device information as JSON.", bundle: VPhoneLocalization.bundle))
    }

    func copyValue(_ value: String) {
        copy(value, message: String(localized: "Copied the value to the Mac clipboard.", bundle: VPhoneLocalization.bundle))
    }

    func copyAddress(_ address: VPhoneDeviceNetworkAddress, full: Bool) {
        copy(full ? address.line : address.address, message: String(localized: "Copied the selection to the Mac clipboard.", bundle: VPhoneLocalization.bundle))
    }

    private func copy(_ text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = VPhoneGuestToolStatus(message: message, isError: false)
    }

    private func fail(_ message: String) {
        status = VPhoneGuestToolStatus(message: message, isError: true)
    }

    // MARK: - Network

    var addresses: [VPhoneDeviceNetworkAddress] {
        let raw = info?.object("network")?["addresses"] as? [String] ?? []
        var seen = Set<String>()
        return raw.compactMap(VPhoneDeviceNetworkAddress.init).filter { seen.insert($0.id).inserted }
    }

    /// The addresses by interface, IPv4 before IPv6.
    var sortedAddresses: [VPhoneDeviceNetworkAddress] {
        addresses.sorted { ($0.interface, $0.family, $0.address) < ($1.interface, $1.family, $1.address) }
    }

    // MARK: - Sections

    var sections: [VPhoneDeviceInfoSection] {
        guard let info else { return [] }
        var sections = [
            deviceSection(info),
            powerSection(info),
            securitySection(info),
            agentSection(info),
            hardwareSection(info),
            displaySection(info),
        ]
        // The full environment report only says something on a jailbroken guest.
        if let environment, environment.string("layout") != nil {
            sections.append(environmentSection(environment))
        }
        return sections
    }

    func sections(in column: VPhoneDeviceInfoSection.Column) -> [VPhoneDeviceInfoSection] {
        sections.filter { $0.kind.column == column }
    }

    /// The sections in the order the page's masonry places them: the leading
    /// and trailing sections taken in turn (Device, Hardware, Power,
    /// Display…), so each lands near where the two-column page had it and
    /// the shortest-column placement can even the columns out.
    var interleavedSections: [VPhoneDeviceInfoSection] {
        let leading = sections(in: .leading)
        let trailing = sections(in: .trailing)
        var result: [VPhoneDeviceInfoSection] = []
        for index in 0 ..< max(leading.count, trailing.count) {
            if index < leading.count {
                result.append(leading[index])
            }
            if index < trailing.count {
                result.append(trailing[index])
            }
        }
        return result
    }

    private func deviceSection(_ info: [String: Any]) -> VPhoneDeviceInfoSection {
        let kernel = [info.string("sysname"), info.string("kernel")].compactMap(\.self).joined(separator: " ")
        return VPhoneDeviceInfoSection(kind: .device, title: Self.text("Device"), rows: [
            VPhoneDeviceInfoRow(label: Self.text("Model"), value: Self.value(info.string("model")), monospaced: true),
            VPhoneDeviceInfoRow(label: Self.text("iOS Version"), value: Self.value(info.string("ios_version")), monospaced: true),
            VPhoneDeviceInfoRow(label: Self.text("Kernel"), value: Self.value(kernel), monospaced: true),
            VPhoneDeviceInfoRow(label: Self.text("Host Name"), value: Self.value(info.string("host")), monospaced: true),
            VPhoneDeviceInfoRow(label: Self.text("Boot Time"), value: VPhonePanelFormat.date(info.double("boot_time"))),
            VPhoneDeviceInfoRow(label: Self.text("Uptime"), value: VPhonePanelFormat.duration(info.double("uptime_seconds"))),
            VPhoneDeviceInfoRow(
                label: Self.text("Boot Session UUID"),
                value: Self.value(info.string("boot_session_uuid")),
                monospaced: true,
            ),
        ])
    }

    private func hardwareSection(_ info: [String: Any]) -> VPhoneDeviceInfoSection {
        var rows = [
            VPhoneDeviceInfoRow(label: Self.text("Physical Memory"), value: VPhonePanelFormat.bytes(info.int("memory_bytes"))),
            VPhoneDeviceInfoRow(label: Self.text("CPU Count"), value: Self.value(info.string("processor_count"))),
        ]
        let storage = info.object("storage") ?? [:]
        // Guest numbers: only finite values that fit in Int64 are converted.
        if let total = storage.double("total_bytes").flatMap(Self.byteCount), total > 0 {
            let available = storage.double("available_bytes").flatMap(Self.byteCount) ?? 0
            let used = max(0, total - available)
            let fraction = min(1, Double(used) / Double(total))
            let value = String(
                localized: "\(VPhonePanelFormat.bytes(used)) used of \(VPhonePanelFormat.bytes(total)) (\(VPhonePanelFormat.percent(fraction)))",
                bundle: VPhoneLocalization.bundle,
            )
            let tone: DKTone = fraction >= 0.95 ? .danger : fraction >= 0.85 ? .warning : .success
            rows.append(VPhoneDeviceInfoRow(label: Self.text("Storage"), value: value, tone: tone, gauge: fraction))
        } else {
            rows.append(VPhoneDeviceInfoRow(label: Self.text("Storage"), value: "—"))
        }
        rows.append(memoryPressureRow())
        return VPhoneDeviceInfoSection(kind: .hardware, title: Self.text("Hardware"), rows: rows)
    }

    /// `kern.memorystatus_vm_pressure_level` reports dispatch memory pressure
    /// levels (1 normal, 2 warning, 4 critical), as Processes reads them;
    /// `kern.memorystatus_level` is the percentage of memory available.
    private func memoryPressureRow() -> VPhoneDeviceInfoRow {
        let label = Self.text("Memory Pressure")
        guard let memory = jetsamMemory, let level = memory.int("memorystatus_vm_pressure_level") else {
            return VPhoneDeviceInfoRow(label: label, value: Self.text("Unavailable"))
        }
        let name: String
        let tone: DKTone
        switch level {
        case 0, 1: (name, tone) = (Self.text("Normal"), .success)
        case 2: (name, tone) = (Self.text("Warning"), .warning)
        case 4: (name, tone) = (Self.text("Critical"), .danger)
        default: (name, tone) = ("\(Self.text("Unknown")) (\(level))", .warning)
        }
        guard let available = memory.double("memorystatus_level") else {
            return VPhoneDeviceInfoRow(label: label, value: name, tone: tone)
        }
        let percent = VPhonePanelFormat.percent(available / 100)
        return VPhoneDeviceInfoRow(
            label: label,
            value: String(localized: "\(name) · \(percent) available", bundle: VPhoneLocalization.bundle),
            tone: tone,
        )
    }

    private func powerSection(_ info: [String: Any]) -> VPhoneDeviceInfoSection {
        let battery = info.object("battery") ?? [:]
        let state = battery.int("state")
        let stateName: String = switch state {
        case 1: Self.text("Unplugged")
        case 2: Self.text("Charging")
        case 3: Self.text("Full")
        default: Self.text("Unknown")
        }
        // UIDevice reports -1 when the level is unknown.
        let fraction = battery.double("fraction").flatMap { $0 >= 0 ? $0 : nil }
        let batteryValue = fraction.map { "\(VPhonePanelFormat.percent($0)) · \(stateName)" } ?? stateName
        var batteryTone: DKTone?
        if state == 2 || state == 3 {
            batteryTone = .success
        } else if state == 1, let fraction, fraction < 0.2 {
            batteryTone = .warning
        }
        let lock = info.object("lock") ?? [:]
        let lowPower = info.object("low_power_mode")?.bool("enabled")
        return VPhoneDeviceInfoSection(kind: .power, title: Self.text("Power"), rows: [
            VPhoneDeviceInfoRow(label: Self.text("Battery"), value: batteryValue, tone: batteryTone),
            VPhoneDeviceInfoRow(
                label: Self.text("Low Power Mode"),
                value: Self.onOff(lowPower),
                tone: lowPower == true ? .warning : nil,
            ),
            VPhoneDeviceInfoRow(
                label: Self.text("Lock State"),
                value: lock.bool("locked").map { $0 ? Self.text("Locked") : Self.text("Unlocked") } ?? "—",
            ),
            VPhoneDeviceInfoRow(label: Self.text("Screen"), value: lock.bool("screen_off").map { $0 ? Self.text("Off") : Self.text("On") } ?? "—"),
        ])
    }

    private func displaySection(_ info: [String: Any]) -> VPhoneDeviceInfoSection {
        let screen = info.object("screen") ?? [:]
        let rotation = info.object("rotation") ?? [:]
        let brightness = info.object("brightness") ?? [:]
        var size = "—"
        var pixels = "—"
        var scale = "—"
        if let width = screen.double("width"), let height = screen.double("height"), width > 0, height > 0 {
            size = "\(Self.number(width)) × \(Self.number(height)) pt"
            if let factor = screen.double("scale"), factor > 0 {
                pixels = "\(Self.number(width * factor)) × \(Self.number(height * factor)) px"
                scale = "\(Self.number(factor))×"
            }
        }
        let orientationName = rotation.string("name") ?? "—"
        let orientation = if let degrees = rotation.int("degrees") {
            "\(orientationName) (\(degrees)°)"
        } else {
            orientationName
        }
        return VPhoneDeviceInfoSection(kind: .display, title: Self.text("Display"), rows: [
            VPhoneDeviceInfoRow(label: Self.text("Size"), value: size, monospaced: true),
            VPhoneDeviceInfoRow(label: Self.text("Pixels"), value: pixels, monospaced: true),
            VPhoneDeviceInfoRow(label: Self.text("Scale"), value: scale),
            VPhoneDeviceInfoRow(label: Self.text("Orientation"), value: orientation),
            VPhoneDeviceInfoRow(label: Self.text("Rotation Lock"), value: Self.onOff(rotation.bool("locked"))),
            VPhoneDeviceInfoRow(label: Self.text("Brightness"), value: VPhonePanelFormat.percent(brightness.double("value"))),
            VPhoneDeviceInfoRow(label: Self.text("Auto-Brightness"), value: Self.onOff(brightness.bool("auto"))),
            VPhoneDeviceInfoRow(label: Self.text("Volume"), value: VPhonePanelFormat.percent(info.double("volume"))),
        ])
    }

    private func securitySection(_ info: [String: Any]) -> VPhoneDeviceInfoSection {
        let developer = info.object("developer_mode") ?? [:]
        let developerValue: String
        let developerTone: DKTone?
        if developer.bool("enabled") == true {
            (developerValue, developerTone) = (Self.text("On"), .success)
        } else if developer.bool("armed") == true {
            (developerValue, developerTone) = (Self.text("On After Restart"), .warning)
        } else if developer.bool("enabled") == false {
            (developerValue, developerTone) = (Self.text("Off"), .idle)
        } else {
            (developerValue, developerTone) = (Self.text("Unavailable"), nil)
        }
        let jailbreak = info.object("jailbreak") ?? [:]
        var rows = [
            VPhoneDeviceInfoRow(label: Self.text("Developer Mode"), value: developerValue, tone: developerTone),
            VPhoneDeviceInfoRow(label: Self.text("Developer Mode Writable"), value: Self.yesNo(developer.bool("writable"))),
        ]
        if let layout = jailbreak.string("layout") {
            rows.append(VPhoneDeviceInfoRow(label: Self.text("Jailbreak Layout"), value: layout, tone: .info))
            rows.append(VPhoneDeviceInfoRow(label: Self.text("jbroot"), value: Self.value(jailbreak.string("jbroot")), monospaced: true))
            rows.append(VPhoneDeviceInfoRow(label: Self.text("Detected By"), value: Self.value(jailbreak.string("source"))))
        } else {
            rows.append(VPhoneDeviceInfoRow(label: Self.text("Jailbreak Layout"), value: Self.text("Not Detected"), tone: .idle))
        }
        return VPhoneDeviceInfoSection(kind: .security, title: Self.text("Security"), rows: rows)
    }

    /// icli `environmentReport()`, as served by `device.environment`.
    private func environmentSection(_ report: [String: Any]) -> VPhoneDeviceInfoSection {
        let markers = report["markers"] as? [String] ?? []
        let tools = report["bootstrap_tools_present"] as? [String: Any] ?? [:]
        let present = tools.keys.filter { tools.bool($0) == true }.sorted()
        let missing = tools.keys.filter { tools.bool($0) != true }.sorted()
        let basebin = report.string("basebin_version") ?? ""
        let layout = report.string("layout")
        return VPhoneDeviceInfoSection(kind: .environment, title: Self.text("Jailbreak Environment"), rows: [
            VPhoneDeviceInfoRow(label: Self.text("Jailbreak Layout"), value: layout ?? Self.text("Not Detected"), tone: layout == nil ? .idle : .info),
            VPhoneDeviceInfoRow(label: Self.text("jbroot"), value: Self.value(report.string("jbroot")), monospaced: true),
            VPhoneDeviceInfoRow(label: Self.text("jbroot Source"), value: Self.value(report.string("jbroot_source"))),
            VPhoneDeviceInfoRow(label: Self.text("System Root Path"), value: Self.value(report.string("rootfs_prefix")), monospaced: true),
            VPhoneDeviceInfoRow(label: Self.text("Markers"), value: markers.isEmpty ? Self.text("None") : markers.joined(separator: ", ")),
            VPhoneDeviceInfoRow(label: Self.text("BaseBin Version"), value: basebin.isEmpty ? "—" : basebin, monospaced: true),
            VPhoneDeviceInfoRow(label: Self.text("Bootstrap Tools"), value: present.isEmpty ? Self.text("None") : present.joined(separator: ", ")),
            VPhoneDeviceInfoRow(
                label: Self.text("Missing Tools"),
                value: missing.isEmpty ? Self.text("None") : missing.joined(separator: ", "),
                tone: missing.isEmpty ? nil : .warning,
            ),
            VPhoneDeviceInfoRow(label: Self.text("Platform Binary"), value: Self.yesNo(report.bool("platform_binary"))),
            VPhoneDeviceInfoRow(label: Self.text("RootHide Runtime"), value: Self.yesNo(report.bool("roothide_runtime_active"))),
            VPhoneDeviceInfoRow(label: Self.text("Effective UID"), value: Self.value(report.string("euid")), monospaced: true),
        ])
    }

    private func agentSection(_ info: [String: Any]) -> VPhoneDeviceInfoSection {
        let agent = info.object("agent") ?? [:]
        return VPhoneDeviceInfoSection(kind: .agent, title: Self.text("vphoned Agent"), rows: [
            VPhoneDeviceInfoRow(label: Self.text("Binary SHA-256"), value: Self.value(agent.string("binary_hash")), monospaced: true),
            VPhoneDeviceInfoRow(label: Self.text("PID"), value: Self.value(agent.string("pid")), monospaced: true),
        ])
    }

    // MARK: - Value Formatting

    private static func text(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: VPhoneLocalization.bundle)
    }

    private static func value(_ string: String?) -> String {
        guard let string, !string.isEmpty else { return "—" }
        return string
    }

    private static func onOff(_ value: Bool?) -> String {
        value.map { $0 ? text("On") : text("Off") } ?? text("Unavailable")
    }

    private static func yesNo(_ value: Bool?) -> String {
        value.map { $0 ? text("Yes") : text("No") } ?? "—"
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 2)).grouping(.never))
    }

    /// A guest byte count as Int64, or nil when it is not finite, negative, or
    /// too large. `Double(Int64.max)` rounds up to 2^63, so the bound is exclusive.
    private static func byteCount(_ value: Double) -> Int64? {
        guard value.isFinite, value >= 0, value < Double(Int64.max) else { return nil }
        return Int64(value)
    }
}
