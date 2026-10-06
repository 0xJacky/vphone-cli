import Foundation
import Testing
import VPhoneDesignKit
@testable import VPhoneVirtualMachineKit

/// How Device Info lays out and words vphoned's `device.info`.
@MainActor
@Suite("Device Info")
struct VPhoneDeviceInfoModelTests {
    static let info: [String: Any] = [
        "model": "iPhone17,3", "ios_version": "26.6.2 (23G90)", "sysname": "Darwin", "kernel": "25.6.0",
        "host": "research-26", "boot_time": 1_700_000_000, "uptime_seconds": 20,
        "boot_session_uuid": "3F2A9C14-5B7E-4D21-9A0C-7E1F2B3C4D5E",
        "memory_bytes": 8_589_934_592, "processor_count": 8,
        "storage": ["total_bytes": 64e9, "available_bytes": 33e9],
        "battery": ["state": 2, "fraction": 1.0],
        "lock": ["locked": false, "screen_off": false],
        "low_power_mode": ["enabled": false],
        "screen": ["width": 393, "height": 852, "scale": 3],
        "rotation": ["name": "Portrait", "degrees": 0, "locked": false],
        "brightness": ["value": 0.5, "auto": true], "volume": 0.6,
        "developer_mode": ["enabled": true, "writable": true],
        "agent": ["binary_hash": "9f86d081", "pid": 312],
        "network": ["addresses": ["lo0 127.0.0.1", "en0 fe80::1%en0", "en0 192.168.64.12", "en0 192.168.64.12", "garbage"]],
    ]

    private func model(_ info: [String: Any] = Self.info, pressure: [String: Any]? = nil) -> VPhoneDeviceInfoModel {
        let model = VPhoneDeviceInfoModel(control: VPhoneGuestControl())
        model.apply(deviceInfoResult: info)
        if let pressure {
            model.apply(jetsamResult: ["memory": pressure])
        }
        return model
    }

    private func info(replacing key: String, with value: Any) -> [String: Any] {
        var info = Self.info
        info[key] = value
        return info
    }

    private func row(_ label: String, in model: VPhoneDeviceInfoModel) -> VPhoneDeviceInfoRow? {
        model.sections.flatMap(\.rows).first { $0.label == label }
    }

    // MARK: - Layout

    @Test
    func `sections fill the design's two columns`() {
        let model = model()
        #expect(model.sections(in: .leading).map(\.kind) == [.device, .power, .security, .agent])
        #expect(model.sections(in: .trailing).map(\.kind) == [.hardware, .display])
        #expect(model.interleavedSections.map(\.kind) == [.device, .hardware, .power, .display, .security, .agent])
        #expect(model.sections(in: .leading).first?.rows.map(\.label) == [
            "Model", "iOS Version", "Kernel", "Host Name", "Boot Time", "Uptime", "Boot Session UUID",
        ])
    }

    @Test
    func `nothing shows before the first read`() {
        let model = VPhoneDeviceInfoModel(control: VPhoneGuestControl())
        #expect(!model.hasInfo)
        #expect(!model.canCopyJSON)
        #expect(model.sections.isEmpty)
        #expect(model.sortedAddresses.isEmpty)
    }

    @Test
    func `the jailbreak environment shows only on a jailbroken guest`() {
        let model = model()
        model.apply(environmentResult: ["layout": NSNull()])
        #expect(!model.sections.contains { $0.kind == .environment })
        model.apply(environmentResult: ["layout": "rootless", "jbroot": "/var/jb", "markers": [".installed_dopamine"]])
        #expect(model.sections(in: .trailing).last?.kind == .environment)
        #expect(row("Markers", in: model)?.value == ".installed_dopamine")
    }

    // MARK: - Values

    @Test
    func `identifiers read in monospace and missing values as a dash`() {
        let model = model(info(replacing: "host", with: ""))
        #expect(row("Model", in: model)?.monospaced == true)
        #expect(row("Kernel", in: model)?.value == "Darwin 25.6.0")
        #expect(row("Host Name", in: model)?.value == "—")
        #expect(row("Battery", in: model)?.monospaced == false)
    }

    @Test
    func `storage carries a gauge whose tone rises as it fills`() throws {
        let storage = try #require(row("Storage", in: model()))
        #expect(abs((storage.gauge ?? 0) - 31.0 / 64.0) < 0.001)
        #expect(storage.tone == .success)
        #expect(storage.value.contains("used of"))

        let nearlyFull = info(replacing: "storage", with: ["total_bytes": 100.0, "available_bytes": 10.0])
        #expect(row("Storage", in: model(nearlyFull))?.tone == .warning)
        let full = info(replacing: "storage", with: ["total_bytes": 100.0, "available_bytes": 1.0])
        #expect(row("Storage", in: model(full))?.tone == .danger)
        let unknown = info(replacing: "storage", with: ["total_bytes": -1.0])
        #expect(row("Storage", in: model(unknown))?.value == "—")
        #expect(row("Storage", in: model(unknown))?.gauge == nil)
    }

    @Test
    func `memory pressure reads the dispatch levels`() {
        let label = "Memory Pressure"
        #expect(row(label, in: model())?.value == "Unavailable")
        let normal = row(label, in: model(pressure: ["memorystatus_vm_pressure_level": 1, "memorystatus_level": 62]))
        #expect(normal?.value.hasPrefix("Normal · ") == true)
        #expect(normal?.tone == .success)
        let warning = row(label, in: model(pressure: ["memorystatus_vm_pressure_level": 2]))
        #expect(warning?.value == "Warning")
        #expect(warning?.tone == .warning)
        let critical = row(label, in: model(pressure: ["memorystatus_vm_pressure_level": 4]))
        #expect(critical?.value == "Critical")
        #expect(critical?.tone == .danger)
        #expect(row(label, in: model(pressure: ["memorystatus_vm_pressure_level": 3]))?.value == "Unknown (3)")
    }

    @Test
    func `battery reads its level and charge state`() {
        let charging = row("Battery", in: model())
        #expect(charging?.value.hasSuffix("· Charging") == true)
        #expect(charging?.tone == .success)

        let low = row("Battery", in: model(info(replacing: "battery", with: ["state": 1, "fraction": 0.1])))
        #expect(low?.value.hasSuffix("· Unplugged") == true)
        #expect(low?.tone == .warning)

        // UIDevice reports -1 for an unknown level.
        let unknown = row("Battery", in: model(info(replacing: "battery", with: ["state": 0, "fraction": -1])))
        #expect(unknown?.value == "Unknown")
        #expect(unknown?.tone == nil)
    }

    @Test
    func `the display reads in points, pixels and degrees`() {
        let model = model()
        #expect(row("Size", in: model)?.value == "393 × 852 pt")
        #expect(row("Pixels", in: model)?.value == "1179 × 2556 px")
        #expect(row("Scale", in: model)?.value == "3×")
        #expect(row("Orientation", in: model)?.value == "Portrait (0°)")
        #expect(row("Rotation Lock", in: model)?.value == "Off")
        #expect(row("Auto-Brightness", in: model)?.value == "On")
    }

    @Test
    func `Developer Mode reads on, armed, off or unavailable`() {
        let mode = { (developer: [String: Any]) in
            self.row("Developer Mode", in: self.model(self.info(replacing: "developer_mode", with: developer)))
        }
        #expect(mode(["enabled": true])?.value == "On")
        #expect(mode(["enabled": true])?.tone == .success)
        #expect(mode(["enabled": false, "armed": true])?.value == "On After Restart")
        #expect(mode(["enabled": false, "armed": true])?.tone == .warning)
        #expect(mode(["enabled": false])?.value == "Off")
        #expect(mode(["enabled": false])?.tone == .idle)
        #expect(mode([:])?.value == "Unavailable")
    }

    @Test
    func `a detected jailbreak adds its root and source`() {
        let plain = model()
        #expect(row("Jailbreak Layout", in: plain)?.value == "Not Detected")
        #expect(row("jbroot", in: plain) == nil)

        let jailbroken = model(info(replacing: "jailbreak", with: ["layout": "rootless", "jbroot": "/var/jb", "source": "marker"]))
        #expect(row("Jailbreak Layout", in: jailbroken)?.value == "rootless")
        #expect(row("Jailbreak Layout", in: jailbroken)?.tone == .info)
        #expect(row("jbroot", in: jailbroken)?.value == "/var/jb")
        #expect(row("Detected By", in: jailbroken)?.value == "marker")
    }

    // MARK: - Network

    @Test
    func `addresses are deduplicated and sorted by interface, IPv4 first`() {
        let addresses = model().sortedAddresses
        #expect(addresses.map(\.line) == [
            "en0\tIPv4\t192.168.64.12",
            "en0\tIPv6\tfe80::1%en0",
            "lo0\tIPv4\t127.0.0.1",
        ])
    }

    @Test
    func `a selected address that disappears is deselected`() {
        let model = model()
        model.selectedAddress = "lo0 127.0.0.1"
        model.apply(deviceInfoResult: info(replacing: "network", with: ["addresses": ["en0 192.168.64.12"]]))
        #expect(model.selectedAddress == nil)
    }

    @Test
    func `the raw response copies as sorted JSON`() {
        let model = model()
        #expect(model.canCopyJSON)
        let json = model.infoJSON ?? ""
        let agent = json.range(of: "\"agent\"")
        let battery = json.range(of: "\"battery\"")
        #expect(agent != nil && battery != nil)
        if let agent, let battery {
            #expect(agent.lowerBound < battery.lowerBound)
        }
        #expect(json.contains("\"model\" : \"iPhone17,3\""))
    }
}
